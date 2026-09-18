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

note "tree       $TREE"
note "tag        $KERNEL_TAG"
note "defconfig  $KERNEL_DEFCONFIG"

make -C "$TREE" "$KERNEL_DEFCONFIG"

merged=$( cd "$TREE" && ARCH="$ARCH" scripts/kconfig/merge_config.sh \
	-m .config "$FRAGMENT" 2>&1 )
printf '%s\n' "$merged"

make -C "$TREE" olddefconfig

# What was asked for against what arrived. A kernel fragment that is
# silently dropped is this repository's oldest recurring failure, and the
# symptom here is the worst kind: CONFIG_BRCMFMAC absent gives a board that
# boots perfectly and has no wireless interface, with nothing in dmesg
# naming a cause.
missing=
while read -r line; do
	case $line in
	'' | '#'*) continue ;;
	esac
	key=${line%%=*}
	grep -q "^$line\$" "$TREE/.config" || missing="$missing $key"
done <"$FRAGMENT"
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
