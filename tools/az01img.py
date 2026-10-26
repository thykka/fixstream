#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reader/writer for AZ01 update images (5.x firmware line).

Format (little-endian): strings are u32 length (NUL excluded) + bytes + NUL, blobs u32 length + bytes,
both padded to 4. A header ("AZ01", u32 version, u32 header length, build string, compatible strings,
device IDs, description), then one PART record per partition (u32 record header length, u64 data size,
name, compression "none" or "xz", digests over the stored data, then the data), then an EOF record.
Every record starts on an 8-byte boundary.

usage: az01img.py inspect IMG
       az01img.py extract IMG OUTDIR
       az01img.py write BASE OUT [--part NAME=FILE]... [--compatible STR]... [--xz-level N]

inspect  prints the header and each partition, verifies every hash; exits 1 on any mismatch.
extract  verifies, then writes OUTDIR/<name>.raw for each partition (xz partitions unpacked).
write    builds OUT from BASE (a stock image): same header, partition order, compression and hash
         algorithms. Each --part replaces a partition's unpacked data; it is packed
         with BASE's compression and sizes and hashes are recomputed. Other partitions are copied
         from BASE. --compatible (repeatable) narrows the compatible-string list to a subset of
         BASE's, kept in BASE's order. --xz-level (default 6, stock's) is for tests only: any
         other level gives a valid image that is not byte-identical to a release build."""
import argparse, hashlib, os, shutil, struct, subprocess, sys, tempfile

MAGIC, PART = b'AZ01', b'PART'
VERSION = 1
# Matches the stock 5.0.4 rootfs stream: LZMA2 preset 6 (8 MiB dictionary), 24 MiB blocks, CRC32.
XZ_LEVEL = 6
XZ_ARGS = ['-T0', '--block-size=25165824', '-C', 'crc32']  # after 'xz -<level>'
XZ_UNPACK_ARGS = ['xz', '-dc', '-T0']
CHUNK = 1 << 22
# Records (PART, then one EOF) start on 8-byte boundaries, zero-padded; the 4.3.4 updater
# (libaz01-prog.so.0.89, 0xbcb4) rejects anything else as "file corrupt".
ALIGN = 8
EOF = b'EOF\0'
EOF_RECORD = EOF + struct.pack('<IQ', 16, 0)


class FormatError(Exception):
    pass


class Reader:
    def __init__(self, data, pos=0):
        self.data, self.pos = data, pos

    def u32(self):
        return self._unpack('<I')

    def u64(self):
        return self._unpack('<Q')

    def _unpack(self, fmt):
        n = struct.calcsize(fmt)
        if self.pos + n > len(self.data):
            raise FormatError('truncated at offset %d' % self.pos)
        v, = struct.unpack_from(fmt, self.data, self.pos)
        self.pos += n
        return v

    def blob(self, nul=False):
        n = self.u32()
        end = self.pos + n + (1 if nul else 0)
        if end > len(self.data):
            raise FormatError('truncated at offset %d' % self.pos)
        v = self.data[self.pos:self.pos + n]
        if nul and self.data[end - 1] != 0:
            raise FormatError('string not NUL-terminated at offset %d' % self.pos)
        self.pos = (end + 3) & ~3
        return v

    def string(self):
        return self.blob(nul=True).decode()


def pack_blob(v, nul=False):
    b = struct.pack('<I', len(v)) + v + (b'\0' if nul else b'')
    return b + b'\0' * (-len(b) % 4)


def pack_string(s):
    return pack_blob(s.encode(), nul=True)


def parse(path):
    """Returns (header, parts). Each part: name, compression, hashes [(algo, digest)], offset, size."""
    size = os.path.getsize(path)
    with open(path, 'rb') as f:
        head = f.read(12)
        if len(head) < 12 or head[:4] != MAGIC:
            raise FormatError('not an AZ01 image')
        hdr_len, = struct.unpack_from('<I', head, 8)
        f.seek(0)
        r = Reader(f.read(hdr_len), 4)
        header = {'version': r.u32(), 'length': r.u32(), 'build': r.string(),
                  'compatible': [r.string() for _ in range(r.u32())],
                  'devices': [r.u32() for _ in range(r.u32())],
                  'description': r.string()}
        if header['version'] != VERSION:
            raise FormatError('unsupported version %d' % header['version'])
        if r.pos != hdr_len:
            raise FormatError('header length %d, parsed %d' % (hdr_len, r.pos))
        parts, pos = [], hdr_len
        while True:
            f.seek(pos)
            pad = -pos % ALIGN
            if f.read(pad) != bytes(pad):
                raise FormatError('expected %d bytes of zero padding at offset %d' % (pad, pos))
            pos += pad
            magic = f.read(4)
            if magic == EOF:
                f.seek(pos)
                if f.read() != EOF_RECORD:
                    raise FormatError('bad EOF record at offset %d, or data after it' % pos)
                break
            if magic != PART:
                raise FormatError('expected a PART or EOF record at offset %d' % pos)
            rec_len, = struct.unpack('<I', f.read(4))
            f.seek(pos)
            r = Reader(f.read(rec_len), 8)
            data_size = r.u64()
            part = {'name': r.string(), 'compression': r.string(),
                    'hashes': [(r.string(), r.blob()) for _ in range(r.u32())],
                    'offset': pos + rec_len, 'size': data_size}
            if r.pos != rec_len:
                raise FormatError('%s: record length %d, parsed %d' % (part['name'], rec_len, r.pos))
            if not part['hashes']:
                raise FormatError('%s: no hash' % part['name'])
            if part['offset'] + data_size > size:
                raise FormatError('%s: data runs past end of file' % part['name'])
            parts.append(part)
            pos = part['offset'] + data_size
    return header, parts


def stored_chunks(path, part):
    with open(path, 'rb') as f:
        f.seek(part['offset'])
        left = part['size']
        while left:
            c = f.read(min(CHUNK, left))
            if not c:
                raise FormatError('%s: unexpected end of file' % path)
            left -= len(c)
            yield c


def digests(path, part, algos):
    """Hashes the stored data of part with each algorithm."""
    hs = [hashlib.new(algo) for algo in algos]
    for c in stored_chunks(path, part):
        for h in hs:
            h.update(c)
    return [h.digest() for h in hs]


def verify(path, part):
    """Returns [(algo, ok)] for each hash in the record."""
    algos = [algo for algo, _ in part['hashes']]
    got = digests(path, part, algos)
    return [(algo, g == want) for (algo, want), g in zip(part['hashes'], got)]


def inspect(path):
    header, parts = parse(path)
    print('version: %d' % header['version'])
    print('build: %s' % header['build'])
    print('compatible: %s' % ' '.join(header['compatible']))
    print('devices: %s' % ' '.join('0x%08x' % d for d in header['devices']))
    print('description: %s' % header['description'])
    ok = True
    for p in parts:
        results = verify(path, p)
        ok &= all(good for _, good in results)
        print('%s %s %d %s' % (p['name'], p['compression'], p['size'],
                               ' '.join('%s %s' % (a, 'OK' if good else 'MISMATCH') for a, good in results)))
    return ok


def extract(path, outdir):
    _, parts = parse(path)
    bad = [p['name'] for p in parts if not all(ok for _, ok in verify(path, p))]
    if bad:
        raise FormatError('hash mismatch in %s; nothing extracted' % ', '.join(bad))
    os.makedirs(outdir, exist_ok=True)
    for p in parts:
        dest = os.path.join(outdir, p['name'] + '.raw')
        with open(dest, 'wb') as o:
            if p['compression'] == 'none':
                for c in stored_chunks(path, p):
                    o.write(c)
            elif p['compression'] == 'xz':
                unpack_xz(stored_chunks(path, p), o, p['name'])
            else:
                raise FormatError('%s: unknown compression %r' % (p['name'], p['compression']))
        print('%s -> %s' % (p['name'], dest))


def unpack_xz(chunks, out, name):
    """Writes the xz stream in chunks, unpacked, to the open file out. xz -T0 unpacks the blocks in
    parallel (1.3 s for the stock rootfs, against 7.6 s single-threaded) and fails on a corrupt,
    truncated or trailing-garbage stream."""
    if not shutil.which('xz'):
        raise FormatError('xz not found; install it with: brew install xz')
    proc = subprocess.Popen(XZ_UNPACK_ARGS, stdin=subprocess.PIPE, stdout=out, stderr=subprocess.PIPE)
    try:
        for c in chunks:
            proc.stdin.write(c)
        proc.stdin.close()
    except BrokenPipeError:
        pass
    err = proc.stderr.read().decode(errors='replace').strip()
    if proc.wait() != 0:
        raise FormatError('%s: xz stream does not unpack: %s' % (name, err))


def pack(src, compression, dest, xz_level=XZ_LEVEL):
    """Packs the unpacked file src into dest with the given compression."""
    if compression == 'none':
        shutil.copyfile(src, dest)
    elif compression == 'xz':
        if not shutil.which('xz'):
            raise FormatError('xz not found; install it with: brew install xz')
        with open(src, 'rb') as i, open(dest, 'wb') as o:
            subprocess.run(['xz', '-%d' % xz_level] + XZ_ARGS + ['-c'], stdin=i, stdout=o, check=True)
    else:
        raise FormatError('unknown compression %r' % compression)


def write(base, out, replacements, compatible=None, xz_level=XZ_LEVEL):
    if os.path.exists(out) and os.path.samefile(base, out):
        raise FormatError('output would overwrite %s' % base)
    header, parts = parse(base)
    unknown = set(replacements) - {p['name'] for p in parts}
    if unknown:
        raise FormatError('no partition %s in %s' % (', '.join(sorted(unknown)), base))
    compat = header['compatible']
    if compatible is not None:
        extra = [c for c in compatible if c not in compat]
        if extra or not compatible:
            raise FormatError('compatible strings must be a non-empty subset of %s' % ' '.join(compat))
        compat = [c for c in compat if c in compatible]
    body = (pack_string(header['build'])
            + struct.pack('<I', len(compat)) + b''.join(pack_string(c) for c in compat)
            + struct.pack('<I', len(header['devices'])) + b''.join(struct.pack('<I', d) for d in header['devices'])
            + pack_string(header['description']))
    tmpdir = tempfile.mkdtemp(prefix='az01-', dir=os.path.dirname(os.path.abspath(out)))
    try:
        with open(out, 'wb') as o:
            o.write(MAGIC + struct.pack('<II', header['version'], 12 + len(body)) + body)
            for p in parts:
                o.write(bytes(-o.tell() % ALIGN))
                if p['name'] in replacements:
                    packed = os.path.join(tmpdir, p['name'])
                    pack(replacements[p['name']], p['compression'], packed, xz_level)
                    src = {'offset': 0, 'size': os.path.getsize(packed)}
                    src_path = packed
                else:
                    src, src_path = p, base
                algos = [algo for algo, _ in p['hashes']]
                hashes = zip(algos, digests(src_path, src, algos))
                rec = (pack_string(p['name']) + pack_string(p['compression'])
                       + struct.pack('<I', len(algos))
                       + b''.join(pack_string(algo) + pack_blob(d) for algo, d in hashes))
                o.write(PART + struct.pack('<IQ', 16 + len(rec), src['size']) + rec)
                for c in stored_chunks(src_path, src):
                    o.write(c)
            o.write(bytes(-o.tell() % ALIGN) + EOF_RECORD)
    except BaseException:
        if os.path.exists(out):
            os.remove(out)
        raise
    finally:
        shutil.rmtree(tmpdir)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('inspect').add_argument('image')
    x = sub.add_parser('extract')
    x.add_argument('image')
    x.add_argument('outdir')
    w = sub.add_parser('write')
    w.add_argument('base')
    w.add_argument('out')
    w.add_argument('--part', action='append', default=[], metavar='NAME=FILE')
    w.add_argument('--compatible', action='append', metavar='STR')
    w.add_argument('--xz-level', type=int, choices=range(10), default=XZ_LEVEL, metavar='0-9')
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'inspect':
            return 0 if inspect(a.image) else 1
        if a.cmd == 'extract':
            extract(a.image, a.outdir)
        elif a.cmd == 'write':
            if any('=' not in s for s in a.part):
                ap.error('--part takes NAME=FILE')
            replacements = dict(s.split('=', 1) for s in a.part)
            write(a.base, a.out, replacements, a.compatible, a.xz_level)
        return 0
    except FormatError as e:
        print('error: %s' % e, file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
