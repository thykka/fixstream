#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Patches the stock EngineOS 5.0.4 update image for the Numark Mixstream Pro with the selected mods.
#
# Usage: patch.sh <stock image> [--no-beat-jump] [--no-extra-fx] [--no-splash]
#
# Writes out/MIXSTREAMPRO-5.0.4-Update.img, the name the unit requires. Only the root filesystem and the
# splash partition change; the image header, recoverysplash, and the partition order and compression stay
# stock. Needs python3 (3.8 or later), xz, e2fsprogs (debugfs, e2fsck, dumpe2fs) and, for the splash, ffmpeg.
# For tests: PATCH_OUT overrides the output directory (default: out/).
#
# Each mod is a directory with apply.sh, sourced in a subshell. It edits the rootfs, or writes a raw
# splash image (800x1280 BGRA, 4,096,000 bytes, opaque) to $SPLASH. It can use:
#   ROOT  repo root           TOOLS  directory of the Python tools    MOD  the mod's own directory
#   RAW   rootfs image being patched    SPLASH  custom splash path (absent until written)
#   FWORK empty scratch dir   step, die   dbg "<debugfs command>"   (read-only)
#   replace <local file> <rootfs path>        overwrite a file, keeping its mode and ownership
#   add <local file> <rootfs path> <mode>     add a new root-owned file (mode e.g. 0644)
#   add_symlink <rootfs path> <target>        add a new root-owned symlink
#   sha256 <file>          print its SHA-256
#   dbgw <command file>    run debugfs -w and fail on errors (for edits the helpers don't cover, e.g. in tests)
#   touched <path>...      list paths for the mode and ownership check (the helpers do this themselves)
# The helpers queue their edits; they are written in one debugfs run after apply.sh returns.
#
# Sourced instead of run, this file only defines its functions (patch_main runs them in order), so a
# builder can add steps between them.
set -euo pipefail

STOCK_SHA256=e642aaa686138d25a4e192b4afcdb51f1730d601ef8807bd4dfafadc40d6e995
IMG_NAME=MIXSTREAMPRO-5.0.4-Update.img
ROOTFS_SIZE=516031488
SPLASH_SIZE=4096000  # 800x1280 BGRA, stored uncompressed
MIN_FREE=1048576     # less rootfs free space than this (bytes) fails the patch
PUBLIC_MODS=(02-beat-jump 04-extra-fx 07-boot-splash)  # applied in this order

# Two layouts: the development tree (this file beside the Python tools, mods/NN-<mod>/v5/), or patch.sh at
# the top with tools/ and mods/<mod>/
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "$HERE/az01img.py" ]; then
	ROOT=$(cd "$HERE/../.." && pwd)
	TOOLS=$HERE
	public_mod_dir() { echo "$ROOT/mods/$1/v5"; }
else
	ROOT=$HERE
	TOOLS=$HERE/tools
	public_mod_dir() { echo "$ROOT/mods/${1#[0-9][0-9]-}"; }
fi
AZ01=(python3 -I "$TOOLS/az01img.py")

step() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }
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
	[ -n "$d" ] && [ -x "$d/debugfs" ] && [ -x "$d/e2fsck" ] && [ -x "$d/dumpe2fs" ] && { E2=$d; break; }
done

dbg() { "$E2/debugfs" -R "$1" "$RAW" 2>/dev/null; }
dbgw() {
	"$E2/debugfs" -w -f "$1" "$RAW" > "$1.log" 2>&1
	! grep -i -E 'error|not found|cannot|failed' "$1.log" || die "debugfs reported errors (see $1.log)"
}
touched() { printf '%s\n' "$@" >> "$TOUCHED"; }
meta() {  # <rootfs> <path>: "<type> <mode> <uid> <gid>" (e.g. "regular 0644 0 0"), or nothing if absent
	"$E2/debugfs" -R "stat $2" "$1" 2>/dev/null | python3 -I -c '
import re, sys
m = re.search(r"Type: (\w+)\s+Mode:\s+([0-7]+).*?User:\s+(\d+)\s+Group:\s+(\d+)", sys.stdin.read(), re.S)
if m: print(*m.groups())'
}
free_bytes() {  # <rootfs>: free blocks x block size
	"$E2/dumpe2fs" -h "$1" 2>/dev/null | awk -F: '/^Free blocks/ {f = $2} /^Block size/ {b = $2} END {print f * b}'
}

# Mod helpers: queue debugfs commands in $FWORK/edits.cmd
queue() {  # <rootfs path>: refuse a path queued twice, then record it as touched
	! grep -q -x -F "$1" "$FWORK/queued" 2>/dev/null || die "$1 edited twice"
	echo "$1" >> "$FWORK/queued"
	touched "$1"
}
write_file() {  # <local file> <rootfs path> <mode> <uid> <gid> <replace|new>
	local name; name=$(basename "$2")
	[ -f "$1" ] || die "no such file: $1"
	[[ "$1" != *'"'* ]] || die "unsupported file name: $1"
	queue "$2"
	{
		echo "cd $(dirname "$2")"
		[ "$6" = new ] || echo "rm $name"
		echo "write \"$1\" $name"
		echo "sif $name mode 010$3"
		echo "sif $name uid $4"
		echo "sif $name gid $5"
	} >> "$FWORK/edits.cmd"
}
replace() {
	local m; m=$(meta "$RAW" "$2")
	[[ "$m" == regular\ * ]] || die "$2 is not a regular file in the rootfs"
	read -r -a m <<< "$m"
	write_file "$1" "$2" "${m[1]}" "${m[2]}" "${m[3]}" replace
}
add() {
	[ -z "$(meta "$RAW" "$2")" ] || die "$2 already exists"
	[[ "$3" =~ ^0[0-7]{3}$ ]] || die "bad mode for $2: $3"
	write_file "$1" "$2" "$3" 0 0 new
}
add_symlink() {
	local name; name=$(basename "$1")
	[ -z "$(meta "$RAW" "$1")" ] || die "$1 already exists"
	queue "$1"
	{
		echo "cd $(dirname "$1")"
		echo "symlink $name $2"
		echo "sif $name uid 0"
		echo "sif $name gid 0"
	} >> "$FWORK/edits.cmd"
}

patch_setup() {  # <output dir> <image file name>
	OUT=$1
	IMG="$OUT/$2"
	WORK="$OUT/work"
	RAW="$WORK/rootfs.raw"
	SPLASH="$WORK/splash.raw"
	TOUCHED="$WORK/touched"
}

check_inputs() {  # <stock image>
	STOCK=$1
	[ -f "$STOCK" ] || die "no such file: $STOCK"
	command -v python3 >/dev/null || die "python3 not found"
	command -v xz >/dev/null || die "xz not found (macOS: brew install xz)"
	[ -n "$E2" ] || die "e2fsprogs (debugfs, e2fsck, dumpe2fs) not found (macOS: brew install e2fsprogs)"
	[ "$(sha256 "$STOCK")" = "$STOCK_SHA256" ] || die "stock image hash mismatch: $STOCK is not the stock EngineOS 5.0.4 Mixstream Pro image"
	echo "Stock image OK"
}

extract_stock() {
	step "Extracting stock image"
	rm -rf "$WORK" "$IMG" && mkdir -p "$WORK/stock"
	"${AZ01[@]}" extract "$STOCK" "$WORK/stock" >/dev/null
	cp "$WORK/stock/rootfs.raw" "$RAW"
	: > "$TOUCHED"
	echo "OK"
}

apply_mod() {  # <mod dir> <label>
	step "Applying $2"
	(
		MOD=$1
		FWORK="$WORK/mods/$2"
		mkdir -p "$FWORK"
		source "$MOD/apply.sh"
		[ ! -f "$FWORK/edits.cmd" ] || dbgw "$FWORK/edits.cmd"
	)
}

check_rootfs() {
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

	step "Checking modes and owners"
	# Changed paths keep their stock type, mode and owner; added ones are root's
	local p now was
	while read -r p; do
		now=$(meta "$RAW" "$p")
		was=$(meta "$WORK/stock/rootfs.raw" "$p")
		[ -n "$now" ] || die "$p missing after patching"
		if [ -n "$was" ]; then
			[ "$now" = "$was" ] || die "$p: type, mode and owner $now, stock $was"
		else
			[[ "$now" == *" 0 0" ]] || die "$p: added, not owned by root ($now)"
		fi
		echo "$p: $now"
	done < <(sort -u "$TOUCHED")

	step "Checking free space"
	echo "$(free_bytes "$RAW") bytes free"
	[ "$(free_bytes "$RAW")" -ge "$MIN_FREE" ] || die "less than $MIN_FREE bytes free on the rootfs"
}

write_image() {  # [<az01img.py write option>...]
	step "Writing image"
	# Stock header and recoverysplash; rootfs always repacked (xz like stock); splash raw, custom or stock
	local parts=(--part "rootfs=$RAW")
	[ ! -f "$SPLASH" ] || parts+=(--part "splash=$SPLASH")
	"${AZ01[@]}" write "$STOCK" "$IMG" "${parts[@]}" "$@"
	echo "OK"
}

verify_image() {
	step "Verifying image"
	header() { "${AZ01[@]}" inspect "$1" | grep -E '^(version|build|compatible|devices|description):'; }
	layout() { "${AZ01[@]}" inspect "$1" | grep -v -E '^(version|build|compatible|devices|description):' | cut -d' ' -f1,2; }
	"${AZ01[@]}" inspect "$IMG" | tee "$WORK/inspect.log"
	[ "$(header "$IMG")" = "$(header "$STOCK")" ] || die "header differs from stock"
	[ "$(layout "$IMG")" = "$(layout "$STOCK")" ] || die "partition names, order or compression differ from stock"
	mkdir -p "$WORK/verify"
	"${AZ01[@]}" extract "$IMG" "$WORK/verify" >/dev/null
	cmp "$WORK/verify/rootfs.raw" "$RAW" || die "packed rootfs differs from patched rootfs"
	cmp "$WORK/verify/recoverysplash.raw" "$WORK/stock/recoverysplash.raw" || die "recoverysplash differs from stock"
	if [ -f "$SPLASH" ]; then
		cmp "$WORK/verify/splash.raw" "$SPLASH" || die "packed splash differs from custom splash"
	else
		cmp "$WORK/verify/splash.raw" "$WORK/stock/splash.raw" || die "splash differs from stock"
	fi
	rm -rf "$WORK/verify"
	echo "OK"
}

patch_main() {
	local usage="usage: $0 <stock image> [--no-beat-jump] [--no-extra-fx] [--no-splash]"
	local stock= mods=" ${PUBLIC_MODS[*]} " a m
	for a in "$@"; do
		case "$a" in
			--no-beat-jump) mods=${mods/ 02-beat-jump / } ;;
			--no-extra-fx) mods=${mods/ 04-extra-fx / } ;;
			--no-splash) mods=${mods/ 07-boot-splash / } ;;
			-*) die "$usage" ;;
			*) [ -z "$stock" ] || die "$usage"; stock=$a ;;
		esac
	done
	[ -n "$stock" ] || die "$usage"
	read -r -a mods <<< "$mods"
	[ ${#mods[@]} -gt 0 ] || die "no mods selected"

	step "Checking inputs"
	echo "Mods: ${mods[*]#[0-9][0-9]-}"
	patch_setup "${PATCH_OUT:-$ROOT/out}" "$IMG_NAME"
	check_inputs "$stock"
	extract_stock
	for m in "${mods[@]}"; do
		apply_mod "$(public_mod_dir "$m")" "${m#[0-9][0-9]-}"
	done
	check_rootfs
	write_image
	verify_image
	rm -rf "$WORK"

	step "Done"
	echo "Mods: ${mods[*]#[0-9][0-9]-}"
	echo "$IMG"
	echo "SHA-256: $(sha256 "$IMG")"
	echo "Copy it to the top level of a USB stick or SD card under this exact name, then update from the unit."
}

[ "${BASH_SOURCE[0]}" != "$0" ] || patch_main "$@"
