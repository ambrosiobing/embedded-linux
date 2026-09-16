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
# The device tree the firmware should load for the RT kernel.
#
# This used to be the literal string "rt/bcm2711-rpi-4-b.dtb", written
# whatever the card was for. On a Pi 3 that names a Pi 4's device tree and
# the board does not boot, with no console output to say why, which is the
# failure this whole script exists to avoid.
#
# It cannot be derived at select time, because "select" runs against a card
# on a laptop with no build tree in sight. So install writes the name it
# chose to $boot/rt/DTB and select reads it back. A file on the card is the
# right place for a fact about that card.
rt_dtb_name() {
	boot=$1
	[ -f "$boot/rt/DTB" ] || return 1
	tr -d ' \r\n' <"$boot/rt/DTB"
}

write_block() {
	config=$1
	want=$2
	boot=$(dirname "$config")

	dtb=$(rt_dtb_name "$boot") || dtb=
	if [ "$want" = rt ] && [ -z "$dtb" ]; then
		die "no $boot/rt/DTB, so the device tree for this card is not
       recorded and selecting the real-time kernel would guess at it.
       Run install first, which writes it."
	fi

	tmp=$config.bench-tmp
	sed "/^${BEGIN}\$/,/^${END}\$/d" "$config" >"$tmp"

	{
		printf '%s\n' "$BEGIN"
		echo "# Two kernels on one card. Project 8 compares them, so"
		echo "# both stay installed and this block chooses. The dtbs"
		echo "# and overlays move with the kernel: a 6.12 kernel with"
		echo "# the 6.6 BSP's overlays is a combination nobody tested."
		echo "# The device tree below is this board's, recorded by"
		echo "# install in rt/DTB. A Pi 4 name on a Pi 3 card is a"
		echo "# board that does not boot and does not say why."
		if [ "$want" = rt ]; then
			echo "kernel=kernel8-rt.img"
			echo "device_tree=rt/$dtb"
			echo "overlay_prefix=rt/overlays/"
			echo "#kernel=kernel8.img"
		else
			echo "#kernel=kernel8-rt.img"
			[ -z "$dtb" ] || echo "#device_tree=rt/$dtb"
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
	# The deploy directory, and NOT a hardcoded machine name.
	#
	# This defaulted to .../images/raspberrypi4-64, which was right while
	# one board had ever been built and silently wrong afterwards. With
	# two machines present it would have written a Pi 4 kernel onto a Pi 3
	# card, and the only symptom is a board that does not come up.
	#
	# One machine present: use it. More than one: refuse and list them.
	# Choosing between two boards is not a default a script gets to make,
	# and "newest wins" is the wrong rule here because the newest build is
	# not necessarily the card in your hand.
	deploy=${3:-}
	if [ -z "$deploy" ]; then
		images=$KAS_BUILD_DIR/tmp/deploy/images
		found=$(find "$images" -maxdepth 1 -mindepth 1 -type d \
			-printf '%f\n' 2>/dev/null | sort)
		count=$(printf '%s\n' "$found" | grep -c . || true)
		if [ "$count" -eq 1 ]; then
			deploy=$images/$found
		elif [ "$count" -eq 0 ]; then
			die "no built images under $images. Build first: ./go rt"
		else
			die "more than one machine has been built, and which card is
       in front of you is not something this script can know:

$(printf '%s\n' "$found" | sed 's|^|           |')

       Name the one you want:
           scripts/rt-kernel-install.sh install BOOT ROOT $images/<machine>"
		fi
	fi

	[ -d "$boot" ] || die "$boot is not a directory"
	[ -d "$root" ] || die "$root is not a directory"
	[ -d "$deploy" ] || die "no deploy directory at $deploy.
       Build the real-time image first: ./go rt"
	[ -f "$boot/config.txt" ] ||
		die "$boot has no config.txt, so it is not a Pi boot partition."

	# deploy/images holds one directory per MACHINE and that directory
	# name is the only part of the layout Yocto guarantees, so it is
	# where the machine comes from rather than from a guess.
	machine=$(basename "$deploy")

	image=$deploy/Image
	[ -f "$image" ] || image=$deploy/Image-$machine.bin
	[ -f "$image" ] || die "no kernel Image in $deploy"

	# Which device tree this board needs. BENCH_RT_DTB overrides, because
	# a machine name is coarser than a board: raspberrypi3-64 covers the
	# 3B and the 3B+, and they are different files.
	if [ -n "${BENCH_RT_DTB:-}" ]; then
		dtb=$BENCH_RT_DTB
	else
		case $machine in
		raspberrypi4-64) dtb=bcm2711-rpi-4-b.dtb ;;
		raspberrypi3-64) dtb=bcm2710-rpi-3-b.dtb ;;
		*) dtb= ;;
		esac
	fi
	if [ -z "$dtb" ] || [ ! -f "$deploy/$dtb" ]; then
		die "cannot tell which device tree $machine needs${dtb:+ (tried $dtb)}.
       Name it explicitly, from the ones this build produced:

$(find "$deploy" -maxdepth 1 -name 'bcm*.dtb' ! -name '*+git0*' \
			! -name "*-$machine.dtb" -printf '           %f\n' 2>/dev/null | sort)

           BENCH_RT_DTB=<name> scripts/rt-kernel-install.sh install ..."
	fi
	if [ "$machine" = raspberrypi3-64 ] && [ -z "${BENCH_RT_DTB:-}" ]; then
		note "note     raspberrypi3-64 covers the 3B and the 3B+, which"
		note "         take different device trees. Defaulting to $dtb;"
		note "         set BENCH_RT_DTB=bcm2710-rpi-3-b-plus.dtb for a 3B+."
	fi

	note "machine  $machine"
	note "device   $dtb"
	note "kernel   $image"
	cp "$image" "$boot/kernel8-rt.img"

	# Recorded on the card, because select and status run on a laptop
	# with no build tree and must not guess at it.
	mkdir -p "$boot/rt"
	printf '%s\n' "$dtb" >"$boot/rt/DTB"

	mkdir -p "$boot/rt/overlays"
	for dtb in "$deploy"/*.dtb; do
		[ -f "$dtb" ] || continue
		cp "$dtb" "$boot/rt/"
	done

	# The overlays, from either layout this BSP produces.
	#
	# This used to be "if [ -d $deploy/overlays ]" with a "|| true" after
	# the copy. meta-raspberrypi scarthgap writes the .dtbo files flat
	# into deploy/images rather than into an overlays/ subdirectory, so
	# that branch was never taken, nothing was installed, and config.txt
	# still announced overlay_prefix=rt/overlays/ pointing at an empty
	# directory. Every dtoverlay= line would then fail silently.
	#
	# Each overlay appears three times in deploy/images: the plain name,
	# the name with the machine appended, and the name with the full
	# version appended. The firmware wants the plain one, so the other
	# two are filtered out rather than copied and left to confuse.
	overlays=0
	if [ -d "$deploy/overlays" ]; then
		for dtbo in "$deploy"/overlays/*.dtbo; do
			[ -f "$dtbo" ] || continue
			cp -L "$dtbo" "$boot/rt/overlays/"
			overlays=$((overlays + 1))
		done
	else
		for dtbo in "$deploy"/*.dtbo; do
			[ -f "$dtbo" ] || continue
			case $(basename "$dtbo") in
			*+git0*) continue ;;
			*-"$machine".dtbo) continue ;;
			esac
			cp -L "$dtbo" "$boot/rt/overlays/"
			overlays=$((overlays + 1))
		done
		# overlay_map.dtb lives with the overlays, not with the device
		# trees, and the firmware reads it to resolve overlay names.
		if [ -f "$deploy/overlay_map.dtb" ]; then
			cp -L "$deploy/overlay_map.dtb" "$boot/rt/overlays/"
		fi
	fi

	# Loudly, because config.txt is about to claim these exist. A silent
	# zero here is a board that boots without the overlays the image was
	# designed around, which reads as a hardware fault.
	[ "$overlays" -gt 0 ] || die "no .dtbo files found in $deploy, either
       flat or under overlays/. config.txt would point overlay_prefix at an
       empty directory and every dtoverlay= line would fail silently.
       Check that the build completed do_deploy for the kernel."
	note "overlays $overlays installed"

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
