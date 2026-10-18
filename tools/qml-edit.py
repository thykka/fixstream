#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Edit a QML file by short anchors, without quoting the surrounding code.

  qml-edit.py block <in> <out> <anchor> <replacement>
      Replace the block whose opening line is <anchor> (e.g. "PitchBend {", leading whitespace
      ignored; must match exactly one line) through its matching closing brace line with the
      contents of the file <replacement>.
  qml-edit.py import <in> <out> <import> <after>
      Insert the line <import> after the line <after> in the header, unless already present.
"""
import sys


def block(s, anchor, new):
    lines = s.split('\n')
    hits = [i for i, l in enumerate(lines) if l.strip() == anchor]
    assert len(hits) == 1, 'anchor %r found %d times' % (anchor, len(hits))
    start = hits[0]
    depth = 0
    for end in range(start, len(lines)):
        depth += lines[end].count('{') - lines[end].count('}')
        if depth == 0:
            break
    else:
        raise AssertionError('no closing brace for %r' % anchor)
    return '\n'.join(lines[:start]) + '\n' + new + '\n'.join(lines[end + 1:])


def add_import(s, imp, after):
    head, sep, body = s.partition('\nMidiAssignment {')
    assert sep, 'MidiAssignment root not found'
    lines = head.split('\n')
    if imp not in lines:
        assert lines.count(after) == 1, '%r not found once in the header' % after
        lines.insert(lines.index(after) + 1, imp)
    return '\n'.join(lines) + sep + body


def main():
    cmd, src, dst, a, b = sys.argv[1:]
    s = open(src).read()
    if cmd == 'block':
        s = block(s, a, open(b).read())
    elif cmd == 'import':
        s = add_import(s, a, b)
    else:
        sys.exit(__doc__)
    open(dst, 'w').write(s)


if __name__ == '__main__':
    main()
