# SPDX-License-Identifier: GPL-3.0-or-later
# Custom boot splash. Sourced by patch.sh.
#   1. splash partition: splash.png (1280×800 landscape, opaque) as the raw image at $SPLASH,
#      rotated 90° clockwise to 800×1280, BGRA, 4,096,000 bytes.
#   2. Engine's own splash: the same PNG at /usr/Engine/emod.png, and the JC11 skin's compiled QML
#      points its splash image there.

MOD="$ROOT/mods/boot-splash"
ENGINE=/usr/Engine/Engine
PNG=/usr/Engine/emod.png

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
[ -z "$(dbg "stat $PNG")" ] || die "$PNG already exists"

# JC11.qml builds the path as `${base}${isPortrait ? "_portrait" : ""}.png`; NH08 is landscape.
python3 -I "$ROOT/tools/engine-qmlc.py" replace "$FWORK/Engine.in" "$FWORK/Engine" JM08For3rdParty \
	../../EmbeddedCommon/img/SplashScreen "file://${PNG%.png}"

replace "$FWORK/Engine" "$ENGINE"
add "$MOD/splash.png" "$PNG" 0644
