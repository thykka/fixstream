# SPDX-License-Identifier: GPL-3.0-or-later
# Custom boot splash. Sourced by patch.sh.
#   1. splash partition: splash.png (1280×800 landscape, opaque) as the raw image at $SPLASH,
#      rotated 90° clockwise to 800×1280, BGRA, 4,096,000 bytes (stored uncompressed in AZ01).
#   2. Engine's own splash: the same PNG at /usr/Engine/emod.png, and Engine's splash path points there
#      (engine-patch.py, patch splash: the EmbeddedCommon.qml binding JC11 inherits).
# Applies to stock Engine or to the beat jump or extra FX mod's output (engine-patch.py checks); the edits don't overlap.

ENGINE=/usr/Engine/Engine
PNG=/usr/Engine/emod.png

command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || die "ffmpeg (ffmpeg, ffprobe) not found (macOS: brew install ffmpeg)"
[ "$(ffprobe -v error -show_entries stream=width,height -of csv=p=0:s=x "$MOD/splash.png")" = 1280x800 ] || die "splash.png is not 1280x800"

ffmpeg -v error -i "$MOD/splash.png" -f rawvideo -pix_fmt rgba "$FWORK/splash.rgba"
ffmpeg -v error -i "$MOD/splash.png" -vf transpose=1 -f rawvideo -pix_fmt bgra "$SPLASH"

# Check every pixel against the decoded PNG: position (rotation) and channel order.
python3 -I - "$FWORK/splash.rgba" "$SPLASH" <<'PY'
import sys
src, out = (open(p, 'rb').read() for p in sys.argv[1:])
W, H = 1280, 800  # landscape source; output is H wide, W high
assert len(src) == len(out) == W * H * 4, 'unexpected size'
assert set(src[3::4]) == {255}, 'splash.png has transparent pixels'
for y in range(H):
    for x in range(W):
        i = (y * W + x) * 4
        o = (x * H + (H - 1 - y)) * 4  # 90° clockwise
        r, g, b, a = src[i:i + 4]
        assert out[o:o + 4] == bytes((b, g, r, a)), 'pixel mismatch at %d,%d' % (x, y)
print('splash: %d px checked (rotation, BGRA)' % (W * H))
PY

dbg "dump $ENGINE $FWORK/Engine.in"
python3 -I "$TOOLS/engine-patch.py" apply "$FWORK/Engine.in" "$FWORK/Engine" splash

replace "$FWORK/Engine" "$ENGINE"
add "$MOD/splash.png" "$PNG" 0644  # like Engine's other data files
