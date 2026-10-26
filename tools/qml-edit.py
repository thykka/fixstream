#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Edit a QML file by short anchors, without quoting the surrounding vendor code.
Ported from fixstream's tools/qml-edit.py (4.x), for features that edit the same file in turn.

  qml-edit.py block <in> <out> <anchor> <replacement>
      Replace the block whose opening line is <anchor> (e.g. "PitchBend {", leading whitespace
      ignored; must match exactly one line) through its matching closing brace line with the
      contents of the file <replacement>.
  qml-edit.py import <in> <out> <import> <after>
      Insert the line <import> after the line <after>, one of the file's leading imports, unless
      <import> is already one of them.

Nothing is written on an error.
"""
import sys


def die(msg):
    sys.exit('ERROR: ' + msg)


def block(s, anchor, new):
    lines = s.split('\n')
    hits = [i for i, l in enumerate(lines) if l.strip() == anchor]
    if len(hits) != 1:
        die('anchor %r found %d times' % (anchor, len(hits)))
    start, depth = hits[0], 0
    for end in range(start, len(lines)):
        depth += lines[end].count('{') - lines[end].count('}')
        if depth == 0:
            break
    else:
        die('no closing brace for %r' % anchor)
    return ''.join(l + '\n' for l in lines[:start]) + new + '\n'.join(lines[end + 1:])


def add_import(s, imp, after):
    lines = s.split('\n')
    n = 0
    while n < len(lines) and lines[n].startswith('import '):
        n += 1
    if imp in lines[:n]:
        return s
    if after not in lines[:n]:
        die('%r is not one of the imports' % after)
    lines.insert(lines.index(after) + 1, imp)
    return '\n'.join(lines)


def main():
    if len(sys.argv) != 6 or sys.argv[1] not in ('block', 'import'):
        sys.exit(__doc__)
    cmd, src, dst = sys.argv[1:4]
    s = open(src).read()
    if cmd == 'block':
        anchor, replacement = sys.argv[4:]
        s = block(s, anchor, open(replacement).read())
    else:
        imp, after = sys.argv[4:]
        s = add_import(s, imp, after)
    open(dst, 'w').write(s)


if __name__ == '__main__':
    main()
