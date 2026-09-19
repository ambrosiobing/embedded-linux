#!/bin/sh
#
# build.sh - the mainline kernel for the NanoPi NEO Air, from a tag, with
# the bench fragment merged in.
#
#   . projects/02-neo-air-mainline/toolchain.env
#   sh projects/02-neo-air-mainline/kernel/build.sh
#
# Produces, in $NEO_OUT:
#
#   zImage                               the kernel
#   sun8i-h3-nanopi-neo-air.dtb          the board description
#   modules/lib/modules/<version>/       brcmfmac and friends
#   kernel-version                       one line, read by mkrootfs.sh
#
# THE DEVICE TREE PATH MOVED. Kernels before 6.5 keep the sunxi device
# trees directly in arch/arm/boot/dts/; 6.5 and later put them under
# arch/arm/boot/dts/allwinner/. This script looks in both and says which it
# found, because a hardcoded path silently produces no .dtb and the board
# then hangs after "Starting kernel ..." with no further output at all.
#
# SPDX-License-Identifier: MIT

set -eu

die() {
	echo "kernel/build.sh: $1" >&2
	exit 1
}

note() {
	echo "--- $1"
}

[ "${NEO_ENV:-}" = 1 ] || die "toolchain.env has not been sourced.
       . projects/02-neo-air-mainline/toolchain.env"

HERE=$(cd "$(dirname "$0")" && pwd)
FRAGMENT=$HERE/fragments/bench.cfg
[ -r "$FRAGMENT" ] || die "no fragment at $FRAGMENT"

# An optional SECOND fragment, so another project can add its own options
# without editing this file. Project 3 measures boot time against variants
# of this configuration, and each of its variants is one such fragment:
# kernel trimming, and three compression choices measured against each
# other. Before this existed there was no way in at all, and its whole
# variant plan had nothing to build.
#
# Unset is the normal case and behaves exactly as before. A path that is
# set and unreadable is refused by name rather than skipped, because a
# variant whose fragment was silently dropped would be built as the
# baseline and then measured as though it were not, and the two rows would
# differ by nothing with no way to see why.
EXTRA=${NEO_EXTRA_FRAGMENT:-}
if [ -n "$EXTRA" ]; then
	[ -r "$EXTRA" ] || die "NEO_EXTRA_FRAGMENT is set and cannot be read:
       $EXTRA
       Unset it to build the baseline, or fix the path."
fi

# An optional patch against the kernel tree, applied after it is pinned to
# the tag and before anything is configured.
#
# A LOCAL COMMIT IN THAT TREE CANNOT SURVIVE. This script puts the tree at
# $KERNEL_TAG whenever "git describe --exact-match" does not already say
# so, and a commit of your own makes that check fail, so the next build
# re-fetches, checks the tag out and runs "git clean -qxdf" over the top.
#
# On 20 September Project 3 added a device-tree node as a commit there,
# built, and got a dtb with no node in it. The build printed "re-fetching"
# and then eleven thousand lines of success. Nothing said the edit was
# gone, and the symptom would have been a marker that never rises, found
# after a flash and a boot.
#
# Absolute, because "git -C" runs from the tree and a relative path would
# resolve against it rather than against where you typed it.
EXTRA_PATCH=${NEO_EXTRA_PATCH:-}
if [ -n "$EXTRA_PATCH" ]; then
	case $EXTRA_PATCH in
	/*) ;;
	*) EXTRA_PATCH=$PWD/$EXTRA_PATCH ;;
	esac
	[ -r "$EXTRA_PATCH" ] || die "NEO_EXTRA_PATCH is set and cannot be read:
       $EXTRA_PATCH
       Unset it to build an unpatched tree, or fix the path."
fi

# Configuration before environment, same order and same reason as the
# U-Boot script: this guard is true on every machine, the toolchain check
# only on this one.
case $NEO_SRC in
"$(cd "$HERE/../../.." && pwd)"*)
	die "NEO_SRC is inside the repository: $NEO_SRC
       Sources and artefacts belong outside the checkout. See toolchain.env."
	;;
esac

command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 ||
	die "${CROSS_COMPILE}gcc is not on PATH."

for tool in bc flex bison make; do
	command -v "$tool" >/dev/null 2>&1 ||
		die "$tool is missing. See docs/BRINGUP.md for the package list."
done

TREE=$NEO_SRC/linux
mkdir -p "$NEO_SRC" "$NEO_OUT"

if [ -d "$TREE/.git" ]; then
	have=$(git -C "$TREE" describe --tags --exact-match 2>/dev/null || echo "")
	if [ "$have" != "$KERNEL_TAG" ]; then
		note "tree is at '${have:-no tag}', wanted $KERNEL_TAG, re-fetching"
		git -C "$TREE" fetch --depth 1 origin \
			"refs/tags/$KERNEL_TAG:refs/tags/$KERNEL_TAG"
		git -C "$TREE" checkout -q "$KERNEL_TAG"
		git -C "$TREE" clean -qxdf
	fi
else
	note "cloning linux at $KERNEL_TAG, this is a large clone even shallow"
	git clone --depth 1 -b "$KERNEL_TAG" \
		https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$TREE"
fi

if [ -n "$EXTRA_PATCH" ]; then
	# Tracked files back to the tag FIRST, so a second run does not try to
	# apply a patch that is already applied and fail. This touches only
	# the files the previous patch changed, and leaves untracked build
	# output alone, so the rebuild stays incremental: a device-tree patch
	# recompiles a dtb rather than a kernel.
	git -C "$TREE" checkout -q -- .

	git -C "$TREE" apply --check "$EXTRA_PATCH" 2>/dev/null ||
		die "NEO_EXTRA_PATCH does not apply to this tree:
       $EXTRA_PATCH
       The tree is at $KERNEL_TAG. A patch made against a different
       version, or one already carried by the tag, fails here rather than
       half applying. 'git -C $TREE apply --check <patch>' says why."

	git -C "$TREE" apply "$EXTRA_PATCH"
	note "patch      $EXTRA_PATCH"
fi

note "tree       $TREE"
note "tag        $KERNEL_TAG"
note "defconfig  $KERNEL_DEFCONFIG"

make -C "$TREE" "$KERNEL_DEFCONFIG"

note "fragment   $FRAGMENT"
[ -z "$EXTRA" ] || note "extra      $EXTRA"

# Built as a list rather than interpolated, so the empty case passes no
# empty argument and neither path is subject to word splitting.
set -- .config "$FRAGMENT"
[ -z "$EXTRA" ] || set -- "$@" "$EXTRA"

merged=$( cd "$TREE" && ARCH="$ARCH" scripts/kconfig/merge_config.sh \
	-m "$@" 2>&1 )
printf '%s\n' "$merged"

make -C "$TREE" olddefconfig

# What was asked for against what arrived. A kernel fragment that is
# silently dropped is this repository's oldest recurring failure, and the
# symptom here is the worst kind: CONFIG_BRCMFMAC absent gives a board that
# boots perfectly and has no wireless interface, with nothing in dmesg
# naming a cause.
#
# Both fragments are checked, not only this project's own. An extra
# fragment that was merged and then dropped by a dependency is exactly the
# failure this loop exists for, and it is no less likely for belonging to
# another project.
#
# NOTE what this cannot see: a "# CONFIG_X is not set" line is skipped as
# a comment, so options a fragment turns OFF are merged and never
# verified. That is pre-existing and it matters more for an extra
# fragment than for this one, because trimming a kernel is mostly made of
# such lines.
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
       Requested and absent. Do not build on top of this."

note "every fragment option is present in .config"

make -C "$TREE" -j"$(nproc)" zImage dtbs modules

version=$(make -C "$TREE" -s kernelrelease)
note "version    $version"

# The dtb, wherever this kernel keeps it.
dtb=
for candidate in \
	"$TREE/arch/arm/boot/dts/allwinner/$BOARD_DTB" \
	"$TREE/arch/arm/boot/dts/$BOARD_DTB"; do
	if [ -f "$candidate" ]; then
		dtb=$candidate
		break
	fi
done
[ -n "$dtb" ] || die "built the dtbs and $BOARD_DTB is in neither
       arch/arm/boot/dts/allwinner/ nor arch/arm/boot/dts/.
       Without it the kernel is handed no board description and stops
       after 'Starting kernel ...' with nothing further on the console."
note "dtb        $dtb"

rm -rf "$NEO_OUT/modules"
make -C "$TREE" INSTALL_MOD_PATH="$NEO_OUT/modules" modules_install >/dev/null

cp "$TREE/arch/arm/boot/zImage" "$NEO_OUT/"
cp "$dtb" "$NEO_OUT/"
printf '%s\n' "$version" >"$NEO_OUT/kernel-version"

# brcmfmac is the module the whole Wi-Fi step depends on, and the way it
# goes missing is not a build error. Assert it is on disk rather than
# assuming modules_install copied what the fragment asked for.
found=$(find "$NEO_OUT/modules/lib/modules/$version" -name 'brcmfmac.ko*' | head -n 1)
[ -n "$found" ] || die "brcmfmac.ko is not under
       $NEO_OUT/modules/lib/modules/$version
       The fragment asked for it as a module and modules_install did not
       produce it. Wi-Fi would be absent on the board with no message."
note "modules    $NEO_OUT/modules/lib/modules/$version"
note "           brcmfmac present"

note "wrote      zImage, $BOARD_DTB, modules, kernel-version in $NEO_OUT"
