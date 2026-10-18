#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Replace a string constant in a precompiled QML unit inside the Engine binary.

Engine's QML is compiled ahead of time (Qt 5.15 "qv4cdata" units); Qt runs these units, not the QML
source kept in the resources. Each unit has a string table of static Qt 5 strings:
  [ref -1][size][alloc 0][offset32 24][offset64 24][0] (4 bytes each), then UTF-16LE characters,
  padded to 8 bytes.
The unit is the only one containing <marker> (UTF-16) whose string table has <old> exactly once. <new>
must not be longer than <old>; the size field is updated and the unused characters are zero-filled,
so the binary keeps its size and nothing else moves. The units' MD5 checksum fields are zero, so no
checksum needs updating.

  engine-qmlc.py replace <Engine> <out> <marker> <old> <new>
"""
import struct
import sys

MAGIC = b'qv4cdata'


def units(b):
    i = b.find(MAGIC)
    while i >= 0:
        size = struct.unpack('<I', b[i + 24:i + 28])[0]
        yield i, size
        i = b.find(MAGIC, i + 8)


def header(n):
    return struct.pack('<6i', -1, n, 0, 24, 24, 0)


def find(b, marker, old):
    """Return the offset of <old>'s string header in the one matching unit."""
    pat = header(len(old)) + old.encode('utf-16-le') + b'\0\0'
    hits = []
    for u, size in units(b):
        unit = b[u:u + size]
        if marker.encode('utf-16-le') in unit and unit.count(pat) == 1:
            hits.append(u + unit.index(pat))
    if len(hits) != 1:
        sys.exit('expected one unit with the marker and the string, found %d' % len(hits))
    return hits[0]


def main():
    if len(sys.argv) != 7 or sys.argv[1] != 'replace':
        sys.exit(__doc__)
    src, dst, marker, old, new = sys.argv[2:7]
    if len(new) > len(old):
        sys.exit('new string is longer than the old one (%d > %d)' % (len(new), len(old)))
    orig = open(src, 'rb').read()
    b = bytearray(orig)
    off = find(orig, marker, old)
    end = off + 24 + 2 * len(old)
    b[off:end] = header(len(new)) + new.encode('utf-16-le') + bytes(2 * (len(old) - len(new)))
    # Verify: same size, only this string's bytes changed, and the new string is found the same way.
    assert len(b) == len(orig) and b[:off] == orig[:off] and b[end:] == orig[end:]
    assert find(bytes(b), marker, new) == off
    open(dst, 'wb').write(b)
    print('%s\n  -> %s' % (old, new))
    print('string at 0x%x: %d -> %d characters' % (off, len(old), len(new)))


if __name__ == '__main__':
    main()
