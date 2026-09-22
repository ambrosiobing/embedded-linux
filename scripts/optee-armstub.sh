#!/bin/sh
#
# optee-armstub.sh - put the secure world onto a card that bitbake wrote.
#
#   scripts/optee-armstub.sh install BOOT OPTEE_OUT
#   scripts/optee-armstub.sh status  BOOT
#   scripts/optee-armstub.sh remove  BOOT
#
# BOOT is the mounted FAT partition of a card flashed with
# bench-tee-image. OPTEE_OUT is the out/boot directory of an OP-TEE build
# repository checkout, which is where its "make" leaves armstub8.bin,
# u-boot.bin and uboot.env.
#
# This exists because the two halves of this project are built by two
# different tools. bitbake builds the kernel, the device trees, the
# rootfs and the trusted application; the OP-TEE build repository builds
# Trusted Firmware-A, OP-TEE OS and U-Boot and packs them into
# armstub8.bin. Nothing joins them except a boot partition, and joining
# them by hand is four files and three config.txt lines that are easy to
# get almost right.
#
# What it does not do: build anything, verify a signature, or check that
# the versions match. The version check is a line in docs/BRINGUP.md and
# it needs the board, because the only authority on which OP-TEE is
# running is the OP-TEE that is running.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

BEGIN="# >>> bench optee-armstub"
END="# <<< bench optee-armstub"

usage() {
	sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

# The five lines the firmware needs, and no more. Three of them are the
# reference build's whole config.txt, which is worth knowing before
# copying a distribution's file full of settings that predate the secure
# world. The other two were added on Tuesday 22 September 2026, after a
# board spent an evening proving they were missing.
#
# There is no "armstub=" line, and that is not an omission: in 64-bit
# mode the Raspberry Pi firmware loads a file called armstub8.bin if one
# is there. The option exists for naming a different file.
#
# The two addresses have to agree with uboot.env, which carries
# kernel_addr_r and fdt_addr_r. Change one side only and the board stops
# booting with nothing on the console to say which.
write_block() {
	config=$1
	tmp=$config.bench-tmp

	sed "/^${BEGIN}\$/,/^${END}\$/d" "$config" >"$tmp"
	{
		printf '%s\n' "$BEGIN"
		echo "# The secure world boots first: the firmware loads"
		echo "# armstub8.bin (TF-A, with OP-TEE as BL32 and U-Boot as"
		echo "# BL33), and U-Boot then loads the kernel from this"
		echo "# partition at the addresses below. They must match"
		echo "# kernel_addr_r and fdt_addr_r in uboot.env."
		echo "enable_uart=1"
		echo "kernel_address=0x02000000"
		echo "device_tree_address=0x01000000"
		echo "# arm_64bit=1 reads as redundant and is not. With"
		echo "# armstub8.bin present the board reaches 64-bit mode"
		echo "# anyway, which is why its absence went unnoticed"
		echo "# until the stub was taken away: the same card then"
		echo "# boots to silence, because the firmware defaults"
		echo "# arm_64bit to 0 on a Pi 3 and goes looking for a"
		echo "# kernel7.img that a 64-bit image does not have."
		echo "arm_64bit=1"
		echo "# uart_2ndstage=1 makes start.elf itself report on"
		echo "# the serial line. Without it every failure before"
		echo "# the kernel is a blinking LED and no message, which"
		echo "# is how the line above cost an evening to find."
		echo "uart_2ndstage=1"
		printf '%s\n' "$END"
	} >>"$tmp"
	mv "$tmp" "$config"
}

do_install() {
	boot=$1
	src=$2

	[ -d "$boot" ] || die "$boot is not a directory"
	[ -f "$boot/config.txt" ] ||
		die "$boot has no config.txt, so it is not a Pi boot partition."
	[ -d "$src" ] || die "$src is not a directory.
       It should be out/boot in an OP-TEE build repository checkout,
       after: repo init -u https://github.com/OP-TEE/manifest.git -m
       rpi3.xml && repo sync && cd build && make"

	[ -f "$src/armstub8.bin" ] || die "no armstub8.bin in $src.
       That file is the whole secure world: TF-A with OP-TEE inside it.
       Without it the board boots the kernel directly and there is no
       TEE for the driver to find."

	# Back up whatever boots today, once. A card that was booting
	# before this ran should still boot after the "remove" command,
	# and the only way to promise that is to keep the file.
	if [ ! -f "$boot/config.txt.bench-orig" ]; then
		cp "$boot/config.txt" "$boot/config.txt.bench-orig"
		note "kept the original config.txt as config.txt.bench-orig"
	fi

	note "armstub  $src/armstub8.bin"
	cp "$src/armstub8.bin" "$boot/armstub8.bin"

	# A previous "remove" leaves armstub8.bin.off behind. The fresh
	# stub has just been written over the name that matters, so the
	# old one is now only a way to be confused in a month.
	if [ -f "$boot/armstub8.bin.off" ]; then
		rm -f "$boot/armstub8.bin.off"
		note "cleared armstub8.bin.off left by an earlier remove"
	fi

	# uboot.env is U-Boot's environment, and it carries the commands
	# that load kernel8.img and the device tree. Without it U-Boot
	# stops at its own prompt on the serial console, which looks like
	# a hang to anyone not watching that console.
	if [ -f "$src/uboot.env" ]; then
		cp "$src/uboot.env" "$boot/uboot.env"
		note "uboot.env installed"
	else
		note "warning: no uboot.env in $src."
		note "U-Boot will stop at its prompt rather than boot Linux."
	fi

	write_block "$boot/config.txt"
	note "config.txt now boots the secure world first"
	note "Next: boot with the console attached and watch for three"
	note "banners, TF-A then OP-TEE then U-Boot, before the kernel."
}

do_remove() {
	boot=$1

	[ -f "$boot/config.txt" ] || die "$boot has no config.txt"

	if [ -f "$boot/config.txt.bench-orig" ]; then
		mv "$boot/config.txt.bench-orig" "$boot/config.txt"
		note "config.txt restored from the copy kept at install"
	else
		tmp=$boot/config.txt.bench-tmp
		sed "/^${BEGIN}\$/,/^${END}\$/d" "$boot/config.txt" >"$tmp"
		mv "$tmp" "$boot/config.txt"
		note "removed the block; there was no original to restore"
	fi

	# A card that has just had the secure world removed has to still
	# boot, and until Tuesday 22 September 2026 it did not.
	#
	# The image's own config.txt carries no arm_64bit=1. With the stub
	# in place that costs nothing, because the board reaches 64-bit
	# mode anyway; restore that config.txt and take the stub away and
	# the firmware goes looking for a kernel7.img the image has never
	# shipped, finds nothing, and stops without printing a character.
	# So "remove" used to return a brick and say it had restored the
	# card. One line, and it does not.
	if ! grep -q '^arm_64bit=' "$boot/config.txt"; then
		{
			echo "# Added by optee-armstub.sh remove. Without it the"
			echo "# firmware looks for kernel7.img on a Pi 3 and this"
			echo "# image ships only kernel8.img, so the board boots"
			echo "# to silence."
			echo "arm_64bit=1"
		} >>"$boot/config.txt"
		note "appended arm_64bit=1; without it the card would not boot"
	fi

	# The stub is moved aside, not deleted and not left in place.
	#
	# This used to leave it where it was, with a comment saying the
	# config.txt lines were enough to boot without it. That
	# contradicted do_install's comment above, which says the firmware
	# loads a file named armstub8.bin whenever one is present, no
	# armstub= line required. Both cannot be true, and on Tuesday 22
	# September 2026 nobody settled which: the file was renamed by
	# hand and the board booted straight to the kernel.
	#
	# Renaming is the answer that does not depend on knowing. It costs
	# nothing, it keeps the file so that putting the secure world back
	# is one command rather than another build of the reference stack,
	# and it is correct whichever of those two claims holds.
	if [ -f "$boot/armstub8.bin" ]; then
		mv "$boot/armstub8.bin" "$boot/armstub8.bin.off"
		note "armstub8.bin renamed to armstub8.bin.off"
		note "install puts it back; the firmware ignores the new name"
	fi
}

do_status() {
	boot=$1

	[ -f "$boot/config.txt" ] || die "$boot has no config.txt"

	if [ -f "$boot/armstub8.bin" ]; then
		note "armstub8.bin present, $(wc -c <"$boot/armstub8.bin") bytes"
	elif [ -f "$boot/armstub8.bin.off" ]; then
		note "armstub8.bin absent, but armstub8.bin.off is here:"
		note "  this card had the secure world and it was removed"
	else
		note "armstub8.bin absent"
	fi
	if [ -f "$boot/uboot.env" ]; then
		note "uboot.env present"
	else
		note "uboot.env absent"
	fi
	if grep -q "^${BEGIN}\$" "$boot/config.txt"; then
		note "config.txt boots the secure world"
	else
		note "config.txt does not mention it"
	fi
	if [ -f "$boot/kernel8.img" ]; then
		note "kernel8.img present, which is what U-Boot loads"
	else
		note "warning: no kernel8.img, so U-Boot has nothing to boot"
	fi
}

action=${1:-}
case $action in
install)
	[ $# -ge 3 ] || usage
	do_install "$2" "$3"
	;;
remove)
	[ $# -ge 2 ] || usage
	do_remove "$2"
	;;
status)
	[ $# -ge 2 ] || usage
	do_status "$2"
	;;
*) usage ;;
esac
