#!/bin/sh
#
# build.sh - the one entry point for Project 2, behind ./go neo-air.
#
#   ./go neo-air uboot     U-Boot from a tag, with the bench fragment
#   ./go neo-air kernel    mainline, the fragment, zImage, dtb, modules
#   ./go neo-air rootfs    Debian armhf, then the modules, then depmod
#   ./go neo-air card DEV  write the development microSD
#   ./go neo-air fel       recover a board with no working bootloader
#   ./go neo-air all       uboot, kernel, rootfs, in that order
#
# WHY THIS EXISTS RATHER THAN FOUR PATHS TO REMEMBER.
#
# Project 2 is the only project here with no Yocto, so ./go had nothing to
# dispatch to and its scripts were run by full path with toolchain.env
# sourced by hand. That is two things to get right before anything builds,
# and the second one is invisible when forgotten: sudo keeps its own
# environment, so "sudo sh mkrootfs.sh" loses every pin and the script's
# refusal is the only thing standing between that and an unpinned rootfs.
#
# This sources toolchain.env itself. The refusals in the individual
# scripts stay exactly as they are, because they are what protects a
# direct invocation; this just removes the most common way to trip them.
#
# The order in "all" is not cosmetic. The kernel has to be built before
# the root filesystem, because brcmfmac is a module and a rootfs assembled
# before the modules exist gives a board with no wireless interface and
# nothing in dmesg naming a cause.
#
# SPDX-License-Identifier: MIT

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)

die() {
	echo "neo-air: $1" >&2
	exit 1
}

usage() {
	sed -n '3,11p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

[ -r "$HERE/toolchain.env" ] || die "no toolchain.env beside $0"

# Sourced here so that a caller does not have to, and exported so that a
# sudo -E further down keeps it.
# shellcheck source=/dev/null
. "$HERE/toolchain.env"

# Disk, before anything else, and on the Windows figure rather than the
# guest one.
#
# This mirrors require_host_disk_gb in scripts/common.sh rather than
# sourcing it: common.sh exports KAS_WORK_DIR and KAS_BUILD_DIR and warns
# about stray Yocto layer clones, none of which this project has. The
# duplication is deliberate and small; the comment is here so that a
# change to one is a reminder about the other.
#
# Under WSL the guest filesystem reports the virtual disk maximum, not
# what Windows can supply. The VHDX grows on demand out of the host drive,
# so a build can exhaust Windows while the guest still claims hundreds of
# free gigabytes. It filled a 254 GB system drive to zero here once and
# took the filesystem read-only in the middle of a build.
#
# What this project actually consumes, measured as estimates rather than
# from a run, and therefore generous:
#
#   uboot    a shallow clone plus a build          about 1 GB
#   kernel   a shallow mainline clone is the big   about 6 GB
#            one, plus the build and modules
#   rootfs   a debootstrap tree plus its tar       about 3 GB
require_space() {
	want=$1
	what=$2

	# The guest, which is the only number that exists when this is not
	# WSL at all.
	if [ -d "$NEO_WORK" ] || mkdir -p "$NEO_WORK" 2>/dev/null; then
		have=$(df -BG --output=avail "$NEO_WORK" 2>/dev/null |
			tail -n 1 | tr -dc '0-9')
		if [ -n "${have:-}" ] && [ "$have" -lt "$want" ]; then
			die "$NEO_WORK has ${have} GB free and $what needs about ${want} GB."
		fi
	fi

	# And the host, which is the one that matters under WSL.
	[ -d /mnt/c ] || return 0
	hosthave=$(df -BG --output=avail /mnt/c 2>/dev/null |
		tail -n 1 | tr -dc '0-9')
	[ -n "${hosthave:-}" ] || return 0
	if [ "$hosthave" -lt "$want" ]; then
		die "the Windows drive behind WSL has ${hosthave} GB free and $what
       needs about ${want} GB there. The guest will report far more,
       because the virtual disk grows on demand out of exactly this space.

       To reclaim: delete a stale build tree, then from an Administrator
       PowerShell, wsl --shutdown followed by diskpart compact vdisk. The
       VHDX never shrinks on its own. See references/bench.md."
	fi
}

# The ARM cross toolchain is not part of ./go setup, which installs what a
# Yocto build host needs. Say the whole apt line once rather than letting
# each script report one missing tool at a time.
need_toolchain() {
	command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1 && return 0
	die "${CROSS_COMPILE}gcc is not installed, and ./go setup does not
       install it: that installs a Yocto build host, and this project
       does not use Yocto.

       sudo apt install gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf \\
           bison flex swig device-tree-compiler u-boot-tools bc \\
           libncurses-dev libssl-dev rsync picocom debootstrap \\
           qemu-user-binfmt sunxi-tools"
}

case "${1:-}" in
uboot)
	require_space 1 "the U-Boot build"
	need_toolchain
	exec sh "$HERE/uboot/build.sh"
	;;
kernel)
	require_space 6 "the kernel build"
	need_toolchain
	exec sh "$HERE/kernel/build.sh"
	;;
rootfs)
	require_space 3 "the root filesystem"
	[ "$(id -u)" = 0 ] || die "rootfs needs root for debootstrap and chroot.
       sudo -E ./go neo-air rootfs
       The -E matters: without it sudo drops every pin from toolchain.env
       and the build script refuses rather than building something else."
	exec sh "$HERE/rootfs/mkrootfs.sh"
	;;
card)
	shift
	[ $# -ge 1 ] || die "which device? ./go neo-air card /dev/sdX
       lsblk lists the candidates. The device is never guessed."
	[ "$(id -u)" = 0 ] || die "card needs root. sudo -E ./go neo-air card $1"
	exec sh "$HERE/tools/sdcard.sh" "$@"
	;;
fel)
	shift
	exec sh "$HERE/tools/fel-boot.sh" "$@"
	;;
all)
	require_space 7 "uboot and kernel together"
	need_toolchain
	sh "$HERE/uboot/build.sh"
	sh "$HERE/kernel/build.sh"
	echo "--- uboot and kernel done."
	echo "--- rootfs needs root and is not run from 'all' for that reason:"
	echo "---   sudo -E ./go neo-air rootfs"
	;;
*)
	usage
	;;
esac
