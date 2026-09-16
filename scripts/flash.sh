#!/bin/sh
#
# flash.sh - write the built image to a card.
#
#   scripts/flash.sh /dev/sdX
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
image=$(find "$KAS_BUILD_DIR/tmp/deploy/images" -name '*.wic.bz2' \
	-printf '%T@ %p\n' 2>/dev/null | newest_path image)
[ -n "$image" ] || die "no image found. Run scripts/build.sh first."

bmap=${image%.bz2}.bmap
[ -f "$bmap" ] || bmap=

note "image  $image"
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
note "written. Connect the console at 115200 8N1 before powering up."
