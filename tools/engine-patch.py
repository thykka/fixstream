#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Patch the 5.0.4 Engine binary: the NH08 config flags and the splash path (same size, fixed addresses).

  engine-patch.py apply <in> <out> <patch>...
      Write <in> with the selected patches applied to <out>. <in> must be the stock 5.0.4 Engine,
      or stock plus other known patches (so mods can patch one after another); a patch that is
      already applied, or any other input, is refused and nothing is written.

Patches:
  beat-jump  audio.deck.hasBeatJump = 1                                  (beat jump)
  dj-fx      audio.fx.hasDJFx = 1, hasLimitedTouchFx = 1, hasNHFx = 0    (extra FX)
  splash     Engine's splash image is file:///usr/Engine/emod.png         (boot splash)
All three are proven on the unit.
"""
import hashlib, struct, sys

STOCK_SHA256 = 'e1eb0e2b858880016daa3ad14538426204f8e698d855a274aebc924a5f9a5caa'


def le32(x):
    return struct.pack('<I', x)


# name -> [(address, stock bytes, patched bytes)]; addresses are file offsets
PATCHES = {
    'beat-jump': [  # in the NH08 config builder
        (0xf6c090, le32(0xe3a03001), le32(0xe5c430d9)),  # mov r3, 1 -> strb r3, [r4, 0xd9]: hasBeatJump = 1
    ],
    'dj-fx': [
        (0xf6c0d0, le32(0xe3003125), le32(0xe3a02001)),  # movw r3, 0x125 -> mov r2, 1
        (0xf6c0d4, le32(0xe3002101), le32(0xe5c42122)),  # movw r2, 0x101 -> strb r2, [r4, 0x122]: hasDJFx = 1
        (0xf6c0dc, le32(0xe18420b3), le32(0xe5c42125)),  # strh r2, [r4, r3] -> strb r2, [r4, 0x125]: hasLimitedTouchFx = 1, hasNHFx stays 0
    ],
    # In the raw (uncompressed) Qt resource /Skins/EmbeddedCommon/Views/EmbeddedCommon.qml:
    # the splashScreenImageLocation binding, a literal URL (no geometry tag) padded to the stock length with a comment
    'splash': [
        (0x213f65f, b'Qt.resolvedUrl(`../img/SplashScreen${screenGeometryTag}.png`)',
                    b'"file:///usr/Engine/emod.png" // fixstream 07: Engine splash.'),
    ],
}


def applied_patches(d):
    """The known patches applied to Engine d. Exits unless d is the stock 5.0.4 Engine plus some of
    them: each patch's ranges must be all stock or all patched, and undoing the patched ones in a copy
    must give the stock SHA-256."""
    applied, base = [], bytearray(d)
    for name, ranges in PATCHES.items():
        state = {{s: 'stock', p: 'patched'}.get(bytes(d[a:a + len(s)])) for a, s, p in ranges}
        if state == {'patched'}:
            applied.append(name)
            for addr, stock, _ in ranges:
                base[addr:addr + len(stock)] = stock
        elif state != {'stock'}:
            break
    else:
        if hashlib.sha256(base).hexdigest() == STOCK_SHA256:
            return applied
    sys.exit('ERROR: not the stock 5.0.4 Engine' + (' plus known patches' if applied else ''))


def apply(src, dst, names):
    for name in names:
        if name not in PATCHES:
            sys.exit('ERROR: unknown patch: %s (known: %s)' % (name, ', '.join(PATCHES)))
    d = bytearray(open(src, 'rb').read())
    applied = applied_patches(d)
    for name in names:
        if name in applied:
            sys.exit('ERROR: %s is already applied' % name)
        for addr, stock, patched in PATCHES[name]:
            d[addr:addr + len(stock)] = patched
    open(dst, 'wb').write(d)


def main():
    if len(sys.argv) < 5 or sys.argv[1] != 'apply':
        sys.exit(__doc__)
    apply(sys.argv[2], sys.argv[3], sys.argv[4:])


if __name__ == '__main__':
    main()
