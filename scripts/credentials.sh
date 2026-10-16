#!/bin/sh
#
# credentials.sh - put the network configuration on a freshly flashed
# card, from a copy kept on the build laptop.
#
#   scripts/credentials.sh /mnt/boot /mnt/root [SOURCE_DIR]
#
# WHY THIS EXISTS
#
# Every bench image takes its network from a file on the FAT boot
# partition, because nothing in this repository may ever hold an SSID or
# a key. Flashing erases the card, so that file is gone after every
# flash, and writing it again was a line in a hand-over.
#
# It is the line that gets skipped. On Friday 16 October 2026 it was
# skipped: the card was flashed, the board came up on no network and the
# Pi 3B+ has no usable serial console, so the only way back in was to
# pull the card out again. That had happened before, and the repository
# had carried a note about it since September, which is the proof that a
# note is not the fix.
#
# So the file is kept once on the build laptop, outside the repository
# and outside the image, and copied here while the card is still in the
# reader. Nobody retypes a key, and nothing in git ever sees one.
#
# WHERE THE COPY LIVES
#
#   $BENCH_CREDENTIALS, or $BENCH_WORK/credentials, or ~/bench/credentials
#
# One file per image kind, named exactly as the boot partition wants it:
# wifi.conf, router.conf. Permissions are the operator's business; this
# script never prints a value, only whether one is set.
#
# WHAT IT REFUSES
#
# A card whose rootfs carries a provisioning program and which has
# neither the file nor a copy to take it from. That is an unreachable
# board, and refusing while the reader is still attached costs seconds
# where finding out later costs an evening.
#
# An image with no provisioning program is left alone entirely, which is
# the difference between a guard and a nuisance: this one can only fire
# where the file has a reader waiting for it.
#
# SPDX-License-Identifier: MIT

set -eu

boot=${1:-}
root=${2:-}
src=${3:-${BENCH_CREDENTIALS:-${BENCH_WORK:-$HOME/bench}/credentials}}

if [ -z "$boot" ] || [ -z "$root" ]; then
	echo "usage: credentials.sh /path/to/boot /path/to/root [SOURCE_DIR]" >&2
	exit 2
fi

[ -d "$boot" ] || { echo "no such directory: $boot" >&2; exit 2; }
[ -d "$root" ] || { echo "no such directory: $root" >&2; exit 2; }

status=0

# program on the rootfs : file it reads : what the file configures
#
# One list, so a new provisioning program is one line here rather than a
# new script.
for pair in \
	"usr/bin/bench-wifi-setup:wifi.conf:the wireless network" \
	"usr/bin/bench-router-setup:router.conf:the LTE router and its access point"
do
	prog=${pair%%:*}
	rest=${pair#*:}
	file=${rest%%:*}
	what=${rest#*:}

	[ -f "$root/$prog" ] || continue

	if [ -f "$boot/$file" ]; then
		echo "--- credentials  $file already on the card"
		continue
	fi

	if [ -f "$src/$file" ]; then
		if cp "$src/$file" "$boot/$file" 2>/dev/null; then
			echo "--- credentials  $file copied from $src"
			continue
		fi
		echo "--- credentials  $file is in $src and could not be copied" >&2
		echo "                 onto the card. Is the boot partition" >&2
		echo "                 mounted read-only?" >&2
		status=1
		continue
	fi

	echo "--- credentials  $file is MISSING, and there is no copy in" >&2
	echo "                 $src to take it from." >&2
	echo "                 This card boots with no configuration for" >&2
	echo "                 $what, and a board that joins no network is" >&2
	echo "                 reachable only by pulling the card again." >&2
	echo "                 Make the copy once, and every later flash" >&2
	echo "                 takes it from there:" >&2
	echo "                     ./go credentials" >&2
	status=1
done

exit "$status"
