#!/bin/sh
#
# build.sh - U-Boot for the NanoPi NEO Air, from a tag, with the bench
# fragment merged in.
#
#   . projects/02-neo-air-mainline/toolchain.env
#   sh projects/02-neo-air-mainline/uboot/build.sh
#
# Produces $NEO_OUT/u-boot-sunxi-with-spl.bin, which is SPL and U-Boot
# proper in one file, written to byte 8192 of whichever medium is booting.
#
# WHAT THIS SCRIPT REFUSES TO DO, and why each refusal is here:
#
#   run without toolchain.env      an unpinned bootloader is not evidence
#   build in the repository        a build tree in the checkout made every
#                                  archived image in this repository claim
#                                  a dirty tree, once
#   reuse a tree at another tag    a checkout left at a different tag looks
#                                  identical and builds something else
#   report success without the     the interesting failure is a build that
#   binary                         succeeds and produces nothing at the
#                                  path the next step reads
#
# SPDX-License-Identifier: MIT

set -eu

die() {
	echo "u-boot/build.sh: $1" >&2
	exit 1
}

note() {
	echo "--- $1"
}

[ "${NEO_ENV:-}" = 1 ] || die "toolchain.env has not been sourced.
       . projects/02-neo-air-mainline/toolchain.env
       Everything this builds is pinned there: the tag, the toolchain,
       the defconfig. Building without it is building something else."

HERE=$(cd "$(dirname "$0")" && pwd)
FRAGMENT=$HERE/fragments/bench.config
[ -r "$FRAGMENT" ] || die "no fragment at $FRAGMENT"

# An optional SECOND fragment, the same mechanism as kernel/build.sh and
# for the same reason: Project 3 varies this configuration to measure what
# each change costs in boot time, and its U-Boot variant is one fragment
# holding a preboot marker, a zero boot delay and the probes it turns off.
#
# Unset behaves exactly as before. Set and unreadable is refused by name,
# because a variant built silently as the baseline would be measured as a
# change that made no difference.
EXTRA=${NEO_EXTRA_FRAGMENT:-}
if [ -n "$EXTRA" ]; then
	[ -r "$EXTRA" ] || die "NEO_EXTRA_FRAGMENT is set and cannot be read:
       $EXTRA
       Unset it to build the baseline, or fix the path."
fi

# Configuration errors before environment probing, in that order and on
# purpose. A misconfigured NEO_SRC is wrong on every machine; a missing
# cross compiler is wrong only on this one. Checking the toolchain first
# put this guard behind a condition no authoring laptop can satisfy, which
# made it a guard nobody could ever test.
case $NEO_SRC in
"$(cd "$HERE/../../.." && pwd)"*)
	die "NEO_SRC is inside the repository: $NEO_SRC
       Sources and artefacts belong outside the checkout. See the note in
       toolchain.env and the reasoning in .gitignore, which records what
       a build tree in the checkout cost this repository once."
	;;
esac

command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 ||
	die "${CROSS_COMPILE}gcc is not on PATH.
       sudo apt install gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf"

for tool in bison flex swig dtc make; do
	command -v "$tool" >/dev/null 2>&1 ||
		die "$tool is missing. See docs/BRINGUP.md for the package list."
done

# Headers, which command -v cannot see.
#
# This check exists because the loop above claimed to name whichever
# dependency was missing, and then a build failed forty seconds in with
#
#   tools/mkeficapsule.c:20:10: fatal error: gnutls/gnutls.h:
#   No such file or directory
#
# command -v answers a question about executables. U-Boot's host tools also
# need development headers, and a missing header is invisible to it. The
# check was true about the thing it looked at and silent about the rest,
# which is this repository's oldest recurring shape.
#
# pkg-config rather than a path test, because the include directory is
# multiarch and differs between distributions, and a hardcoded
# /usr/include/gnutls would be a second wrong answer.
if command -v pkg-config >/dev/null 2>&1; then
	for lib in gnutls openssl; do
		pkg-config --exists "$lib" 2>/dev/null ||
			die "the $lib development headers are missing.

       U-Boot builds mkeficapsule and other host tools that include them,
       and a missing header is not visible to a check that looks for
       executables, so this fails partway through the build rather than
       at the start.

       sudo apt install libgnutls28-dev libssl-dev"
	done
else
	note "pkg-config is absent, so the header check is skipped"
	note "           a missing development header will surface as a"
	note "           compile error partway through the build"
fi

TREE=$NEO_SRC/u-boot
mkdir -p "$NEO_SRC" "$NEO_OUT"

if [ -d "$TREE/.git" ]; then
	# A tree that exists is only reusable if it is at the tag this build
	# claims. Tags are cheap to check and a wrong one is invisible: the
	# banner printed on the console says the version it was built from,
	# and nobody reads it until something else has already gone wrong.
	have=$(git -C "$TREE" describe --tags --exact-match 2>/dev/null || echo "")
	if [ "$have" != "$UBOOT_TAG" ]; then
		note "tree is at '${have:-no tag}', wanted $UBOOT_TAG, re-fetching"
		git -C "$TREE" fetch --depth 1 origin "refs/tags/$UBOOT_TAG:refs/tags/$UBOOT_TAG"
		git -C "$TREE" checkout -q "$UBOOT_TAG"
		git -C "$TREE" clean -qxdf
	fi
else
	note "cloning u-boot at $UBOOT_TAG"
	git clone --depth 1 -b "$UBOOT_TAG" \
		https://source.denx.de/u-boot/u-boot.git "$TREE"
fi

note "tree       $TREE"
note "tag        $UBOOT_TAG"
note "defconfig  $UBOOT_DEFCONFIG"
note "fragment   $FRAGMENT"

make -C "$TREE" "$UBOOT_DEFCONFIG"

# merge_config.sh reports what it did and exits 0 either way. Its output is
# printed because it is informative, and NOT parsed for failure, which was
# a mistake here on the first real run.
#
# The line it prints most often is
#
#     Value of CONFIG_MMC_SUNXI_SLOT_EXTRA is redefined by fragment ...
#     Previous value: CONFIG_MMC_SUNXI_SLOT_EXTRA=-1
#     New value: CONFIG_MMC_SUNXI_SLOT_EXTRA=2
#
# which is the fragment overriding the defconfig, which is what a fragment
# is for. The first version of this script treated the word "redefined" as
# an error and refused a build that had just done exactly the right thing.
#
# The question worth asking is not what the merge said about its work, it
# is whether the option is in the produced .config. That check is below and
# it is the one that catches a dropped option.
[ -z "$EXTRA" ] || note "extra      $EXTRA"

# Built as a list rather than interpolated, so the empty case passes no
# empty argument and neither path is subject to word splitting.
set -- .config "$FRAGMENT"
[ -z "$EXTRA" ] || set -- "$@" "$EXTRA"

merged=$( cd "$TREE" && ARCH="$ARCH" scripts/kconfig/merge_config.sh \
	-m "$@" 2>&1 )
printf '%s\n' "$merged"

make -C "$TREE" olddefconfig

# And check the fragment actually reached the config, rather than trusting
# that the merge said so. Same rule as ./go kconfig in the Yocto projects:
# the question is not what was asked for, it is what arrived.
#
# Both fragments, not only this project's own. And note what this cannot
# see: a "# CONFIG_X is not set" line is skipped as a comment, so the
# options a fragment turns OFF are merged and never verified. Project 3's
# U-Boot variant is almost entirely such lines, since its change is to
# stop probing what this bench does not have.
check_fragment() {
	while read -r line; do
		case $line in
		'' | '#'*) continue ;;
		esac
		key=${line%%=*}
		grep -q "^$line\$" "$TREE/.config" || missing="$missing $key"
	done <"$1"
}

missing=
check_fragment "$FRAGMENT"
[ -z "$EXTRA" ] || check_fragment "$EXTRA"
[ -z "$missing" ] || die "these fragment options are not in the built .config:$missing
       They were requested and are absent, which is the failure this
       check exists to make loud."

note "every fragment option is present in .config"

make -C "$TREE" -j"$(nproc)"

BIN=$TREE/u-boot-sunxi-with-spl.bin
[ -f "$BIN" ] || die "the build reported success and $BIN does not exist."

cp "$BIN" "$NEO_OUT/"
size=$(wc -c <"$BIN")
note "wrote      $NEO_OUT/u-boot-sunxi-with-spl.bin, $size bytes"
note "write it to byte 8192 of the medium:"
note "  dd if=$NEO_OUT/u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1024 seek=8 conv=notrunc,fsync"
