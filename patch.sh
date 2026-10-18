#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Patches the stock EngineOS 4.3.4 update image for the Numark Mixstream Pro with the selected mods.
#
# Usage: ./patch.sh <stock image> [--no-beat-jump] [--no-extra-fx] [--no-splash]
#
# Writes out/MIXSTREAMPRO-4.3.4-Update.img. Only the root filesystem and the splash partition change;
# the update-mode splash (recoverysplash) stays stock.
#
# Each mod is mods/<name>/apply.sh, sourced in a subshell. It edits the rootfs, or writes a raw
# splash image (800x1280 BGRA, 4,096,000 bytes) to $SPLASH. It can use:
#   ROOT  repo root           RAW    rootfs image being patched     SPLASH  custom splash path
#   FWORK empty scratch dir   die    dbg "<debugfs command>"  (read-only)
#   replace <local file> <rootfs path>          overwrite a file, keeping its mode and ownership
#   add <local file> <rootfs path> <mode>       add a new file owned by root
set -euo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
STOCK_SHA256=150c94b95af7d95855c34aeb01272b1486d80961b5a7c8d74aab536a5b1e8e81
ROOTFS_SIZE=524288000
SPLASH_SIZE=4096000  # 800x1280 BGRA
OUT="$ROOT/out"
WORK="$OUT/work"
IMG="$OUT/MIXSTREAMPRO-4.3.4-Update.img"
RAW="$WORK/rootfs.raw"
SPLASH="$WORK/splash.raw"
TOUCHED="$WORK/touched"

step() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
usage() { die "usage: $0 <stock image> [--no-beat-jump] [--no-extra-fx] [--no-splash]"; }

[ $# -ge 1 ] || usage
STOCK=$1; shift
MODS=(beat-jump extra-fx boot-splash)
for a in "$@"; do
	case "$a" in
		--no-beat-jump) MODS=("${MODS[@]/beat-jump}") ;;
		--no-extra-fx) MODS=("${MODS[@]/extra-fx}") ;;
		--no-splash) MODS=("${MODS[@]/boot-splash}") ;;
		*) usage ;;
	esac
done
read -r -a MODS <<< "${MODS[*]}"  # drop the emptied entries
[ ${#MODS[@]} -gt 0 ] || die "no mods selected"

sha256() { python3 -I -c '
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    while (c := f.read(1 << 22)): h.update(c)
print(h.hexdigest())' "$1"; }
size() { wc -c < "$1" | tr -d ' '; }

# e2fsprogs: Homebrew keeps it out of PATH (keg-only); Linux has it in /sbin or /usr/sbin.
E2=
for d in "${E2FSPROGS_SBIN:-}" /opt/homebrew/opt/e2fsprogs/sbin /usr/local/opt/e2fsprogs/sbin /usr/sbin /sbin; do
	[ -n "$d" ] && [ -x "$d/debugfs" ] && [ -x "$d/e2fsck" ] && { E2=$d; break; }
done
dbg() { "$E2/debugfs" -R "$1" "$RAW" 2>/dev/null; }
dbgw() {
	"$E2/debugfs" -w -f "$1" "$RAW" > "$1.log" 2>&1
	! grep -i -E 'error|not found|cannot|failed' "$1.log" || die "debugfs reported errors (see $1.log)"
}
# Prints "<octal mode> <uid> <gid>" for a regular file in a rootfs image, or nothing if absent.
owner() {
	"$E2/debugfs" -R "stat $1" "$2" 2>/dev/null | python3 -I -c '
import re, sys
s = sys.stdin.read()
m = re.search(r"Type: regular\s+Mode:\s+([0-7]+).*?User:\s+(\d+)\s+Group:\s+(\d+)", s, re.S)
if m: print(*m.groups())'
}
write_file() {  # <local file> <rootfs path> <mode> <uid> <gid>
	local cmd="$FWORK/debugfs.$(basename "$2").cmd"
	{
		echo "cd $(dirname "$2")"
		[ -z "$(owner "$2" "$RAW")" ] || echo "rm $(basename "$2")"
		echo "write $1 $(basename "$2")"
		echo "sif $(basename "$2") mode 010$3"
		echo "sif $(basename "$2") uid $4"
		echo "sif $(basename "$2") gid $5"
	} > "$cmd"
	dbgw "$cmd"
	echo "$2" >> "$TOUCHED"
}
replace() {
	local o; o=$(owner "$2" "$RAW")
	[ -n "$o" ] || die "$2 is not a regular file in the rootfs"
	read -r -a o <<< "$o"
	write_file "$1" "$2" "${o[0]: -4}" "${o[1]}" "${o[2]}"
}
add() {
	[ -z "$(dbg "stat $2")" ] || die "$2 already exists"
	[[ "$3" =~ ^0[0-7]{3}$ ]] || die "bad mode for $2: $3"
	write_file "$1" "$2" "$3" 0 0
}

step "Checking inputs"
[ -f "$STOCK" ] || die "no such file: $STOCK"
for t in python3 xz dtc; do command -v $t >/dev/null || die "$t not found (see README: Requirements)"; done
[ -n "$E2" ] || die "e2fsprogs (debugfs, e2fsck) not found (see README: Requirements)"
if [[ " ${MODS[*]} " == *" boot-splash "* ]]; then
	command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 || die "ffmpeg not found (see README: Requirements)"
fi
[ "$(sha256 "$STOCK")" = "$STOCK_SHA256" ] || die "$STOCK is not the stock EngineOS 4.3.4 Mixstream Pro image (SHA-256 mismatch)"
echo "Stock image OK"
echo "Mods: ${MODS[*]}"

step "Extracting stock image"
rm -rf "$WORK" && mkdir -p "$WORK/stock"
python3 -I "$ROOT/tools/inmimg.py" extract "$STOCK" "$WORK/stock" | grep -E 'hash (OK|MISMATCH)'
cp "$WORK/stock/rootfs.raw" "$RAW"
: > "$TOUCHED"

for m in "${MODS[@]}"; do
	step "Applying $m"
	FWORK="$WORK/mods/$m"
	mkdir -p "$FWORK"
	( source "$ROOT/mods/$m/apply.sh" )
done

if [ -f "$SPLASH" ]; then
	step "Checking custom splash"
	[ "$(size "$SPLASH")" = "$SPLASH_SIZE" ] || die "splash is not $SPLASH_SIZE bytes"
	python3 -I -c 'import sys; assert set(open(sys.argv[1], "rb").read()[3::4]) == {255}, "splash alpha not 255"' "$SPLASH"
	! cmp -s "$SPLASH" "$WORK/stock/splash.raw" || die "custom splash is identical to stock"
	echo "OK"
fi

step "Checking filesystem"
[ "$(size "$RAW")" = "$ROOTFS_SIZE" ] || die "rootfs size changed"
"$E2/e2fsck" -fn "$RAW"
# Changed files keep stock mode and ownership; added files are root-owned with the requested mode.
sort -u "$TOUCHED" | while read -r p; do
	now=$(owner "$p" "$RAW"); was=$(owner "$p" "$WORK/stock/rootfs.raw")
	[ -n "$now" ] || die "$p missing after patching"
	if [ -n "$was" ]; then
		[ "$now" = "$was" ] || die "$p: mode/owner $now, stock $was"
	else
		[[ "$now" == *" 0 0" ]] || die "$p: added file not owned by root ($now)"
	fi
	echo "$p: mode/uid/gid $now"
done

step "Compressing rootfs"
mkdir -p "$WORK/pack"
xz -9 -T0 --check=crc64 -c "$RAW" > "$WORK/pack/rootfs.img.xz"

step "Packing image"
# recoverysplash, and splash unless a mod wrote one: the stock compressed blobs, byte for byte
python3 -I - "$ROOT/tools" "$STOCK" "$WORK/pack" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import inmimg
b, nodes = inmimg.parse(sys.argv[2])
for n in ('splash', 'recoverysplash'):
    open('%s/%s.img.xz' % (sys.argv[3], n), 'wb').write(inmimg.val(b, nodes['/images/' + n]['data'], True))
PY
# A custom splash is compressed like stock: one xz block, CRC64
[ ! -f "$SPLASH" ] || xz -9 -T1 --check=crc64 -c "$SPLASH" > "$WORK/pack/splash.img.xz"
python3 -I "$ROOT/tools/inmimg.py" dts "$STOCK" "$WORK/pack/stock.dts"
python3 -I - "$WORK/pack/stock.dts" "$WORK/pack/image.dts" "$WORK/pack" <<'PY'
import hashlib, re, struct, sys
src, dst, pack = sys.argv[1:]
s = open(src).read()
for node in ('rootfs', 'splash'):
    h = hashlib.sha1(open('%s/%s.img.xz' % (pack, node), 'rb').read()).digest()
    cells = ' '.join('0x%08x' % x for x in struct.unpack('>5I', h))
    s, n = re.subn(r'(\t%s \{.*?hash \{\s*value = <)[^>]*(>)' % node, lambda m: m.group(1) + cells + m.group(2), s, flags=re.S)
    assert n == 1, node + ' hash not found in the stock image source'
open(dst, 'w').write(s)
PY
( cd "$WORK/pack" && dtc -I dts -O dtb -o "$IMG" image.dts )

step "Verifying image"
mkdir -p "$WORK/verify"
python3 -I "$ROOT/tools/inmimg.py" extract "$IMG" "$WORK/verify" | grep -E 'hash (OK|MISMATCH)' | tee "$WORK/verify.log"
[ "$(grep -c 'hash OK' "$WORK/verify.log")" = 3 ] || die "image hash check failed"
cmp "$WORK/verify/rootfs.raw" "$RAW" || die "packed rootfs differs from patched rootfs"
cmp "$WORK/verify/recoverysplash.raw" "$WORK/stock/recoverysplash.raw" || die "recoverysplash differs from stock"
if [ -f "$SPLASH" ]; then
	cmp "$WORK/verify/splash.raw" "$SPLASH" || die "packed splash differs from custom splash"
else
	cmp "$WORK/verify/splash.raw" "$WORK/stock/splash.raw" || die "splash differs from stock"
fi
python3 -I - "$ROOT/tools" "$IMG" "$STOCK" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import inmimg
(b, nodes), (sb, snodes) = inmimg.parse(sys.argv[2]), inmimg.parse(sys.argv[3])
assert list(nodes) == list(snodes), 'node layout differs from stock'
for k in ('compatible', 'inmusic,devices', 'inmusic,version'):
    assert inmimg.val(b, nodes['/'][k]) == inmimg.val(sb, snodes['/'][k]), k + ' differs from stock'
    print('%s = %s' % (k, inmimg.val(b, nodes['/'][k])))
assert inmimg.val(b, nodes['/']['compatible']) == 'inmusic,nh08'
assert [n for n in nodes if 'partition' in nodes[n]] == ['/images/splash', '/images/recoverysplash', '/images/rootfs']
print('partitions: splash, recoverysplash, rootfs')
PY
rm -rf "$WORK"

step "Done"
echo "Mods: ${MODS[*]}"
echo "$IMG"
echo "SHA-256: $(sha256 "$IMG")"
echo "Copy it to the root of an SD card or USB stick under this exact name, then update from the unit (see README)."
