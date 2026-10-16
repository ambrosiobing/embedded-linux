#!/bin/sh
#
# flash.sh - write the built image to a card.
#
#   scripts/flash.sh /dev/sdX                 the newest image just built
#   scripts/flash.sh /dev/sdX IMAGE.wic.bz2   a named image, archived or not
#
# The second form is what makes an archived image useful: the build tree is
# disposable and gets deleted, and a copy kept by scripts/archive.sh is then
# the only way back to that exact state without repeating the build.
#
# bmaptool skips the empty blocks, so a 1 GB image writes in well under a
# minute. The device is never guessed: pass it, then confirm it.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

dev=${1:-}
[ -n "$dev" ] || die "usage: flash.sh /dev/sdX   (lsblk lists the candidates)"
[ -b "$dev" ] || die "$dev is not a block device."

case $dev in
/dev/sda | /dev/nvme0n1 | /dev/vda)
	die "$dev is very likely the system disk. Refusing."
	;;
esac

# Newest, not lexically last. deploy/images holds one directory per
# MACHINE, and a build host that has built for two of them has two images
# here. "raspberrypi4-64" sorts after "raspberrypi3-64", so the old sort
# would have written a Pi 4 image to a card for a Pi 3, which does not warn
# and does not boot: the symptom is a dark board that reads as dead
# hardware. See newest_path in common.sh.
#
# The ignored images are named rather than dropped, above the confirmation
# prompt, because that prompt is the last gate before the card is erased
# and the operator should be able to see that there was a choice at all.
named=${2:-}
if [ -n "$named" ]; then
	[ -f "$named" ] || die "no such image: $named"
	image=$named
else
	image=$(find "$KAS_BUILD_DIR/tmp/deploy/images" -name '*.wic.bz2' -type f \
		-printf '%T@ %p\n' 2>/dev/null | newest_path image)
	[ -n "$image" ] || die "no image found. Run scripts/build.sh first,
       or name an archived image: scripts/flash.sh $dev IMAGE.wic.bz2
       (scripts/archive.sh list shows what has been kept)."
fi

bmap=${image%.bz2}.bmap
[ -f "$bmap" ] || bmap=

note "image  $image"
# An archived image carries the record of what it is, and this is the one
# moment it is worth reading: the card is about to be erased, and the two
# facts that decide whether this is the right image are the board it was
# built for and the commit it came from.
prov=$(dirname "$image")/PROVENANCE.txt
if [ -f "$prov" ]; then
	sed -n 's/^\(machine\|commit\|config\|archived\) /       &/p' "$prov"
fi
note "target $dev"
lsblk -o NAME,SIZE,MODEL,MOUNTPOINT "$dev" 2>/dev/null || true

printf 'Everything on %s will be erased. Type the device path to continue: ' "$dev"
read -r answer
[ "$answer" = "$dev" ] || die "not confirmed."

require_tool bmaptool
if [ -n "$bmap" ]; then
	sudo bmaptool copy --bmap "$bmap" "$image" "$dev"
else
	sudo bmaptool copy --nobmap "$image" "$dev"
fi
sync
note "written."

# The card is written and still in the reader, which is the last moment the
# boot partition can be read before it becomes a board's problem. config.txt
# can name an overlay whose .dtbo was never deployed, and the firmware skips
# it in silence: the board boots and the feature is simply absent. That cost
# Project 9 a boot, a card and most of an evening on Sunday 4 October 2026.
case $dev in
*[0-9]) part=${dev}p1 ;;
*) part=${dev}1 ;;
esac

overlays=unchecked
if [ -b "$part" ]; then
	mnt=$(mktemp -d)
	if sudo mount -o ro "$part" "$mnt" 2>/dev/null; then
		if sh "$(dirname "$0")/check-overlays.sh" "$mnt"; then
			overlays=ok
		else
			overlays=bad
		fi
		sudo umount "$mnt"
	else
		note "could not mount $part read-only, so the overlays on this"
		note "card were NOT checked. Mount it and run:"
		note "    ./go overlays /path/to/boot"
	fi
	rmdir "$mnt" 2>/dev/null || true
else
	note "no $part, so the overlays on this card were NOT checked."
fi

# THE FILE THAT HAS TO BE WRITTEN BEFORE THE CARD LEAVES THE READER.
#
# Flashing erases the card, and the network configuration lives on the
# card rather than in the image, so it is gone after every flash. The
# hand-over has carried that as a line since September and the line is
# what gets skipped; on Friday 16 October 2026 it was skipped and the
# board came up on no network, with no usable serial console on that
# board, which cost an evening and a second trip to the reader.
#
# Checked here because this is the last moment it is cheap.
case $dev in
*[0-9]) rootpart=${dev}p2 ;;
*) rootpart=${dev}2 ;;
esac

creds=unchecked
if [ -b "$part" ] && [ -b "$rootpart" ]; then
	bmnt=$(mktemp -d)
	rmnt=$(mktemp -d)
	# The boot partition is mounted WRITABLE here, unlike the overlay
	# pass above, because this step copies the file rather than only
	# looking for it. umask=000 so that the copy is readable by the
	# first-boot service, which runs as root but reads a FAT mount
	# whose permissions come from the mount options.
	if sudo mount -o rw,umask=000 "$part" "$bmnt" 2>/dev/null &&
		sudo mount -o ro "$rootpart" "$rmnt" 2>/dev/null; then
		# No sudo, and the store is passed explicitly rather than
		# derived inside the script: umask=000 above makes the FAT
		# mount writable by this user, and a path derived under sudo
		# would resolve HOME to root's.
		if sh "$(dirname "$0")/credentials.sh" "$bmnt" "$rmnt" \
			"${BENCH_CREDENTIALS:-$BENCH_WORK/credentials}"; then
			creds=ok
		else
			creds=missing
		fi
		sync
	else
		note "could not mount both partitions, so the credential files on"
		note "this card were NOT written or checked."
	fi
	sudo umount "$rmnt" 2>/dev/null || true
	sudo umount "$bmnt" 2>/dev/null || true
	rmdir "$rmnt" "$bmnt" 2>/dev/null || true
fi

note "Connect the console at 115200 8N1 before powering up."

# Non-zero on purpose. The image is written either way, and a card that will
# boot with features silently missing is worth failing the command over.
[ "$overlays" != bad ] || exit 1

# Same reasoning, different file. A missing credential file is not a broken
# card, it is an unreachable board, and on a bench whose Pi 3B+ has no
# usable serial console those are the same thing.
[ "$creds" != missing ] || exit 1
