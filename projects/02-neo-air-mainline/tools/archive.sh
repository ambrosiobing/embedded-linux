#!/bin/sh
#
# archive.sh - copy this project's artefacts out of the build tree and into
# the image store, with a provenance file beside them.
#
#   ./go neo-air archive
#
# WHY THIS EXISTS.
#
# Project 2 was the only project in this repository with a booting board and
# no archived image. Its artefacts lived solely in $NEO_OUT, which is inside
# the WSL virtual disk, and that file has been compacted, filled to
# read-only and rebuilt on this bench before. Losing it meant a rebuild of
# U-Boot, a 6.12 kernel and a 394 MB root filesystem, and the eMMC would
# have been the only remaining copy of the thing that works.
#
# The Yocto side has had scripts/archive.sh since Project 8. This is the
# same store, the same naming and the same provenance discipline, for a
# project that has no BitBake to ask.
#
# TWO TIERS OF SAFE, and they are not the same tier. An image in
# $BENCH_WORK/images survives ./go clean, because the store sits beside the
# caches rather than inside the build tree. It does NOT survive a problem
# with the virtual disk. Point BENCH_IMAGE_DIR at a directory on the
# Windows side to get the second tier.
#
# SPDX-License-Identifier: MIT

set -eu

die() {
	echo "neo-air/archive: $1" >&2
	exit 1
}

note() {
	echo "--- $1"
}

[ "${NEO_ENV:-}" = 1 ] || die "toolchain.env has not been sourced.
       ./go neo-air archive"

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)

STORE=${BENCH_IMAGE_DIR:-${BENCH_WORK:-$(dirname "$NEO_WORK")}/images}

# The artefacts, in the order a reader wants them: what boots the board,
# what the kernel is, what the root filesystem is. kernel-version is tiny
# and is what mkrootfs.sh reads, so it travels with them.
ARTEFACTS="u-boot-sunxi-with-spl.bin zImage $BOARD_DTB kernel-version rootfs.tar"

for f in $ARTEFACTS; do
	[ -r "$NEO_OUT/$f" ] ||
		die "no $f in $NEO_OUT.
       Build before archiving: ./go neo-air all, then sudo ./go neo-air rootfs.
       Archiving half a set produces a directory that looks complete and
       cannot flash a card, which is worse than no directory at all."
done

# The commit, and whether the tree was clean when it was built. A -dirty
# stamp is the honest answer and the reason .gitignore keeps build trees out
# of the checkout: an archive taken from a modified tree that does not say
# so is wrong about the one thing provenance exists to record.
commit=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)
dirty=
if ! git -C "$REPO" diff --quiet 2>/dev/null ||
	! git -C "$REPO" diff --cached --quiet 2>/dev/null; then
	dirty=-dirty
fi
stamp=$(date '+%Y-%m-%d')_$commit$dirty

DEST=$STORE/proj02-neo-air/$stamp

# Refuse to write over an existing stamp rather than merging into it. Two
# builds from one commit on one day are a real situation, and silently
# mixing their artefacts produces a directory whose PROVENANCE.txt describes
# only the second. The stamp is the identity; a collision means say so.
[ ! -d "$DEST" ] || die "$DEST already exists.
       That stamp is a commit and a date, so this is a second archive of
       the same commit on the same day. Remove the directory if the new
       build supersedes it, or commit first so the stamp differs."

note "store      $STORE"
note "stamp      $stamp"
mkdir -p "$DEST"

for f in $ARTEFACTS; do
	cp -p "$NEO_OUT/$f" "$DEST/"
	note "  $(printf '%-32s %s' "$f" "$(du -h "$DEST/$f" | cut -f1)")"
done

kver=$(cat "$NEO_OUT/kernel-version")

{
	echo "Project 2, NanoPi NEO Air on mainline"
	echo "====================================="
	echo
	echo "Archived      $(date '+%A %d %B %Y, %H:%M')"
	echo "Repository    $commit${dirty:+  (WORKING TREE WAS MODIFIED)}"
	echo "Board         FriendlyARM NanoPi NEO Air, Allwinner H3"
	echo
	echo "Pinned inputs"
	echo "-------------"
	echo
	printf '  U-Boot        %s\n' "$UBOOT_TAG"
	printf '  Linux         %s, built as %s\n' "$KERNEL_TAG" "$kver"
	printf '  Debian        %s %s\n' "$DEBIAN_SUITE" "$DEBIAN_ARCH"
	printf '  defconfigs    %s, %s\n' "$UBOOT_DEFCONFIG" "$KERNEL_DEFCONFIG"
	printf '  device tree   %s\n' "$BOARD_DTB"
	echo
	echo "sha256"
	echo "------"
	echo
	for f in $ARTEFACTS; do
		printf '  %s  %s\n' \
			"$(sha256sum "$DEST/$f" | cut -d' ' -f1)" "$f"
	done
	echo
	echo "To write a card from these"
	echo "--------------------------"
	echo
	echo "  sudo env NEO_OUT=$DEST ./go neo-air card /dev/sdX"
	echo
	echo "sdcard.sh reads every artefact from \$NEO_OUT, so pointing it at"
	echo "this directory writes exactly what was archived. The env form is"
	echo "deliberate: this bench's sudo ignores -E, so a variable set before"
	echo "sudo does not survive it. Check the device"
	echo "with lsblk first; the script refuses system disks and anything the"
	echo "kernel reports as non-removable, and asks you to type the path"
	echo "back before it writes."
	echo
	echo "The bootloader goes to byte 8192 and the first partition starts at"
	echo "sector 2048. Everything dangerous in this project is the gap"
	echo "between those two numbers, which is 1016 KiB."
	echo
	echo "To rebuild instead"
	echo "------------------"
	echo
	printf '  git checkout %s\n' "$commit"
	echo "  ./go neo-air all"
	echo "  sudo ./go neo-air rootfs"
	echo
	echo "toolchain.env at that commit pins the tags above. The one input"
	echo "not pinned by it is the AP6212 NVRAM, which comes from Debian's"
	echo "firmware-brcm80211 and whose checksum is recorded in"
	echo "docs/BRINGUP.md section 5."
	if [ -n "$dirty" ]; then
		echo
		echo "WARNING"
		echo "-------"
		echo
		echo "The working tree had uncommitted changes when this was built,"
		echo "so the commit above does not describe what produced these"
		echo "files. Treat the checkout line as a starting point, not as a"
		echo "reproduction."
	fi
} >"$DEST/PROVENANCE.txt"

note "wrote      $DEST"
note "           PROVENANCE.txt has the pins, the checksums and the flash line"
if [ -n "$dirty" ]; then
	note "NOTE: the working tree was modified, and the stamp says -dirty."
	note "      Commit first if this archive is meant to be reproducible."
fi
