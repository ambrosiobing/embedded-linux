#!/bin/sh
#
# fel-boot.sh - load U-Boot over USB into a board with no working
# bootloader.
#
# RUNS ON THE HOST, with the board's micro USB port connected to the PC
# rather than to its power supply.
#
#   . projects/02-neo-air-mainline/toolchain.env
#   sudo ./go neo-air fel
#
# THIS IS THE ANSWER TO "I BRICKED IT".
#
# The Allwinner boot ROM probes mmc0 and then mmc2 for an eGON.BT0 header
# at byte 8192. When it finds neither it does not hang: it enters FEL mode
# and waits for a USB host to push code into SRAM. So a board whose
# bootloader has been erased on both media is recoverable without opening
# anything, without a JTAG probe, and without touching the eMMC by hand.
#
# That property is the reason the project deliberately erases the eMMC
# bootloader once, as an acceptance test. A recovery path that has never
# been used is a recovery path nobody knows the state of.
#
# What you should see when the board is in FEL mode:
#
#   Bus 001 Device 014: ID 1f3a:efe8 Allwinner Technology sunxi SoC OTG
#   connector in FEL/flashing mode
#
# After this script runs, U-Boot appears on the serial console, and the
# bootloader can be written back from its prompt:
#
#   => mmc dev 2
#   => ext4load mmc 0:1 0x42000000 u-boot-sunxi-with-spl.bin
#   => mmc write 0x42000000 0x10 0x800
#
# 0x10 is sector 16, which is byte 8192 at 512 bytes per sector.
#
# SPDX-License-Identifier: MIT

set -eu

die() {
	echo "fel-boot: $1" >&2
	exit 1
}

note() {
	echo "--- $1"
}

[ "${NEO_ENV:-}" = 1 ] || die "toolchain.env has not been sourced.
       . projects/02-neo-air-mainline/toolchain.env"

command -v sunxi-fel >/dev/null 2>&1 ||
	die "sunxi-fel is missing.
       sudo apt install sunxi-tools"

BIN=${NEO_FEL_IMAGE:-$NEO_OUT/u-boot-sunxi-with-spl.bin}
[ -r "$BIN" ] || die "no bootloader image at $BIN
       Run uboot/build.sh first. FEL pushes this exact file into SRAM."

# sunxi-fel needs the device, which means root or a udev rule. Say which,
# because "ERROR: Allwinner USB FEL device not found!" is also what an
# unplugged board looks like and the two need different actions.
if ! sunxi-fel version >/dev/null 2>&1; then
	die "no board in FEL mode.

       Three things it could be, in the order worth checking:

       1. The board is not in FEL mode. It enters FEL only when the boot
          ROM finds no eGON.BT0 header at byte 8192 of either mmc0 or
          mmc2. Remove the SD card, and if the eMMC still has a
          bootloader the board will boot from it instead.

       2. The micro USB port is connected to the power supply rather
          than to this PC. It is one port with two jobs.

       3. Permissions. lsusb should show 1f3a:efe8; if it does and this
          still fails, run it as root with sudo ./go neo-air fel, or
          add a udev rule."
fi

note "board      $(sunxi-fel version)"
note "image      $BIN"
note "pushing U-Boot into SRAM over USB"

sunxi-fel -v uboot "$BIN"

note "done. U-Boot is now running from SRAM and DRAM, not from any card."
note "Watch the serial console for the prompt, then write the bootloader"
note "back to the eMMC:"
note "  => mmc dev 2"
note "  => mmc write <addr> 0x10 0x800"
note "Nothing on either medium has been changed by this script."
