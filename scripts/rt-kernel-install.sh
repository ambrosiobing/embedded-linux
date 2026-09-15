#!/bin/sh
#
# rt-kernel-install.sh - put the real-time kernel on a card that already
# boots the generic one, without taking the generic one away.
#
#   scripts/rt-kernel-install.sh install BOOT ROOT [DEPLOY]
#   scripts/rt-kernel-install.sh select  BOOT rt|generic
#   scripts/rt-kernel-install.sh status  BOOT
#
# BOOT is the mounted FAT partition, ROOT the mounted rootfs, DEPLOY the
# directory the RT build left its artefacts in. On Windows the FAT
# partition is the one that appears as a drive letter when the card is
# inserted, which is why this works on a laptop that cannot mount ext4:
# "select" and "status" only ever touch BOOT.
#
# Why not simply flash a second card. Because then the two rows of the
# results table differ in the kernel and in every package, timestamp and
# random seed that a second rootfs brings with it. One card with two
# kernels on it is the only version of this experiment where the sentence
# "everything else was identical" is true.
#
# Why not overwrite the kernel. Because a kernel that does not boot then
# costs a reflash and a rebuild, from a board with no console output to say
# what went wrong. Here the recovery is one line edited on a FAT partition
# from any machine with a card reader, which is the difference between a
# bad evening and a lost one.
#
# What this does not do: reboot the board, or check that the kernel works.
# Both need the board, and a script that claimed either would be lying.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

BEGIN="# >>> bench rt-kernel-install"
END="# <<< bench rt-kernel-install"

usage() {
	sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

# The firmware reads config.txt top to bottom and the last assignment
# wins, so the block goes at the end and the switch is which lines inside
# it are commented. Keeping both lines present, one of them commented, is
# deliberate: the file then documents that a fallback exists, to somebody
# who finds the card and has never read this script.
write_block() {
	config=$1
	want=$2

	tmp=$config.bench-tmp
	sed "/^${BEGIN}\$/,/^${END}\$/d" "$config" >"$tmp"

	{
		printf '%s\n' "$BEGIN"
		echo "# Two kernels on one card. Project 8 compares them, so"
		echo "# both stay installed and this block chooses. The dtbs"
		echo "# and overlays move with the kernel: a 6.12 kernel with"
		echo "# the 6.6 BSP's overlays is a combination nobody tested."
		if [ "$want" = rt ]; then
			echo "kernel=kernel8-rt.img"
			echo "device_tree=rt/bcm2711-rpi-4-b.dtb"
			echo "overlay_prefix=rt/overlays/"
			echo "#kernel=kernel8.img"
		else
			echo "#kernel=kernel8-rt.img"
			echo "#device_tree=rt/bcm2711-rpi-4-b.dtb"
			echo "#overlay_prefix=rt/overlays/"
			echo "kernel=kernel8.img"
		fi
		printf '%s\n' "$END"
	} >>"$tmp"

	mv "$tmp" "$config"
}

do_install() {
	boot=$1
	root=$2
	deploy=${3:-$KAS_BUILD_DIR/tmp/deploy/images/raspberrypi4-64}

	[ -d "$boot" ] || die "$boot is not a directory"
	[ -d "$root" ] || die "$root is not a directory"
	[ -d "$deploy" ] || die "no deploy directory at $deploy.
       Build the real-time image first: ./go rt"
	[ -f "$boot/config.txt" ] ||
		die "$boot has no config.txt, so it is not a Pi boot partition."

	image=$deploy/Image
	[ -f "$image" ] || image=$deploy/Image-raspberrypi4-64.bin
	[ -f "$image" ] || die "no kernel Image in $deploy"

	note "kernel   $image"
	cp "$image" "$boot/kernel8-rt.img"

	mkdir -p "$boot/rt/overlays"
	for dtb in "$deploy"/*.dtb; do
		[ -f "$dtb" ] || continue
		cp "$dtb" "$boot/rt/"
	done
	if [ -d "$deploy/overlays" ]; then
		cp "$deploy"/overlays/* "$boot/rt/overlays/" 2>/dev/null || true
	fi

	# The modules have to arrive too, and under their own version, which
	# is what lets both kernels keep their own set. A kernel booting
	# with another kernel's modules is the failure that looks like
	# working hardware with one driver missing.
	# A glob, not "ls | tail". Parsing ls output is a habit this
	# repository has already had to unlearn once, and the glob says the
	# same thing without a pipeline that breaks on a space in a path.
	modules=
	for candidate in "$deploy"/modules-*.tgz; do
		if [ -f "$candidate" ]; then
			modules=$candidate
		fi
	done
	if [ -n "$modules" ]; then
		note "modules  $modules"
		tar -xzf "$modules" -C "$root"
	else
		note "warning: no modules-*.tgz in $deploy"
		note "The RT kernel will boot with no modules at all, which on"
		note "this image means no wireless and no spidev."
	fi

	write_block "$boot/config.txt" rt
	note "config.txt now selects the real-time kernel"
	note "Next: edit cmdline.txt for the isolation the run needs, then"
	note "boot and check /sys/kernel/realtime and /proc/cmdline."
}

do_select() {
	boot=$1
	want=$2
	case $want in
	rt | generic) ;;
	*) die "select takes rt or generic, not '$want'" ;;
	esac
	[ -f "$boot/config.txt" ] || die "$boot has no config.txt"

	if [ "$want" = rt ] && [ ! -f "$boot/kernel8-rt.img" ]; then
		die "there is no kernel8-rt.img on $boot. Run install first."
	fi
	write_block "$boot/config.txt" "$want"
	note "config.txt now selects the $want kernel"
}

do_status() {
	boot=$1
	[ -f "$boot/config.txt" ] || die "$boot has no config.txt"

	if [ -f "$boot/kernel8-rt.img" ]; then
		note "kernel8-rt.img present"
	else
		note "kernel8-rt.img absent"
	fi
	if grep -q "^kernel=kernel8-rt.img" "$boot/config.txt"; then
		note "config.txt selects: rt"
	else
		note "config.txt selects: generic"
	fi
	if [ -f "$boot/cmdline.txt" ]; then
		note "cmdline: $(cat "$boot/cmdline.txt")"
	fi
}

action=${1:-}
case $action in
install)
	[ $# -ge 3 ] || usage
	do_install "$2" "$3" "${4:-}"
	;;
select)
	[ $# -ge 3 ] || usage
	do_select "$2" "$3"
	;;
status)
	[ $# -ge 2 ] || usage
	do_status "$2"
	;;
*) usage ;;
esac
