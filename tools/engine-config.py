#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read and patch a device configuration compiled into the Engine binary.

Each device config is a zlib-compressed Qt resource (:/Configurations/<code>/Configuration.txt):
  [4-byte BE resource length][4-byte BE uncompressed length][zlib stream]
The patched config is recompressed in place. It must not grow; the unused tail is zero-filled,
so the binary keeps its size and every other resource keeps its offset.

  engine-config.py show <Engine> <code>
  engine-config.py set <Engine> <out> <code> <key> <value> [<key> <value> ...]
"""
import sys
import zlib


def find(b, code):
    """Return (offset of the resource length field, config text) for device <code>."""
    hits = []
    i = 4
    while True:
        i = b.find(b'\x78', i)
        if i < 0:
            break
        if b[i + 1] in (0x01, 0x5e, 0x9c, 0xda) and i >= 8:
            qlen = int.from_bytes(b[i - 4:i], 'big')
            rlen = int.from_bytes(b[i - 8:i - 4], 'big')
            if 0 < qlen < 1 << 20 and rlen > 4:
                d = zlib.decompressobj()
                try:
                    text = d.decompress(b[i:i + rlen - 4])
                except zlib.error:
                    text = b''
                if len(text) == qlen and d.eof and not d.unused_data \
                        and ('/Configuration/Name %s\n' % code).encode() in text \
                        and text.split(b'\n')[1] == ('# %s' % code).encode():
                    hits.append((i - 8, text))
        i += 1
    if len(hits) != 1:
        sys.exit('expected one config for %s, found %d' % (code, len(hits)))
    return hits[0]


def patch(text, changes):
    lines = text.decode().split('\n')
    for key, value in changes:
        idx = [n for n, l in enumerate(lines) if l.split(' ', 1)[0] == key]
        if len(idx) != 1:
            sys.exit('expected one line for %s, found %d' % (key, len(idx)))
        old = lines[idx[0]]
        lines[idx[0]] = '%s %s' % (key, value)
        print('%s\n  -> %s' % (old, lines[idx[0]]))
    return '\n'.join(lines).encode()


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == 'show':
        b = open(sys.argv[2], 'rb').read()
        off, text = find(b, sys.argv[3])
        print('# resource at 0x%x, %d bytes compressed' % (off, int.from_bytes(b[off:off + 4], 'big')))
        sys.stdout.write(text.decode())
        return
    if len(sys.argv) < 7 or sys.argv[1] != 'set' or (len(sys.argv) - 5) % 2:
        sys.exit(__doc__)
    src, dst, code = sys.argv[2:5]
    changes = list(zip(sys.argv[5::2], sys.argv[6::2]))
    b = bytearray(open(src, 'rb').read())
    off, text = find(b, code)
    rlen = int.from_bytes(b[off:off + 4], 'big')
    new = patch(text, changes)
    z = zlib.compress(new, 9)
    if 4 + len(z) > rlen:
        sys.exit('recompressed config is %d bytes, %d available' % (4 + len(z), rlen))
    b[off:off + 4 + rlen] = (4 + len(z)).to_bytes(4, 'big') + len(new).to_bytes(4, 'big') + z \
        + bytes(rlen - 4 - len(z))
    # Verify: same size, the config decodes to exactly the intended text, nothing else changed.
    orig = open(src, 'rb').read()
    assert len(b) == len(orig)
    off2, text2 = find(bytes(b), code)
    assert off2 == off and text2 == new
    assert b[:off] == orig[:off] and b[off + 4 + rlen:] == orig[off + 4 + rlen:]
    open(dst, 'wb').write(b)
    print('resource at 0x%x: %d -> %d bytes (%d zero-filled)' % (off, rlen, 4 + len(z), rlen - 4 - len(z)))


if __name__ == '__main__':
    main()
