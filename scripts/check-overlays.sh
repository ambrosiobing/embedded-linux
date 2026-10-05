#!/bin/sh
#
# check-overlays.sh - every dtoverlay= in config.txt has its .dtbo on the card.
#
#   scripts/check-overlays.sh /mnt/boot
#
# The firmware reads config.txt, looks for overlays/NAME.dtbo on the same
# FAT partition, and does nothing at all when it is absent. The kernel
# never hears about it, because overlay handling finishes before the kernel
# starts, so the first symptom is a feature that is simply not there on a
# board that boots perfectly.
#
# On Sunday 4 October 2026 that cost Project 9 a boot, a card and most of
# an evening. config.txt asked for disable-bt, ramoops and gpio-led and the
# card carried only disable-bt, so the heartbeat LED was never created and
# pstore had no backend, from a config.txt that was exactly right.
# meta-raspberrypi composes KERNEL_DEVICETREE out of a hand curated
# RPI_KERNEL_DEVICETREE_OVERLAYS, and neither of those two is in that list.
#
# flash.sh runs this with the card still in the reader. It is also usable by
# hand against any mounted boot partition, which is how it gets tested
# without a card: see tests/overlays-check-test.sh.
#
# SPDX-License-Identifier: MIT

. "$(dirname "$0")/common.sh"

boot=${1:-}
[ -n "$boot" ] || die "usage: check-overlays.sh /path/to/mounted/boot"
[ -d "$boot" ] || die "$boot is not a directory."

config=$boot/config.txt
[ -f "$config" ] || die "no config.txt in $boot, so this is not a boot partition."

dir=$boot/overlays

note "config.txt  $config"
note "overlays    $dir"

# os_prefix and overlay_prefix move where the firmware looks. This check does
# not follow them, so when either is set it says so rather than reporting
# confidently on a directory the firmware is not reading. A check that is
# right for the wrong reason teaches you to trust it.
if grep -qE '^[[:space:]]*(os_prefix|overlay_prefix)=' "$config"; then
	note "NOTE: config.txt sets os_prefix or overlay_prefix, which moves"
	note "      where the firmware looks for overlays. This check reads"
	note "      $dir and does not follow the prefix."
fi

# Commented lines are reported rather than ignored in silence, because a
# dtoverlay that was switched off by a '#' looks identical, in a later
# reading of this output, to one that was never written.
disabled=$(sed -n 's/^[[:space:]]*#[[:space:]]*dtoverlay=\([a-zA-Z0-9_.-][a-zA-Z0-9_.-]*\).*/\1/p' \
	"$config" | sort -u | tr '\n' ' ')

# A bare "dtoverlay=" with no name is the idiom that ends parameter scope
# for the previous overlay. It names no file and is not a request.
wanted=$(sed -n 's/^[[:space:]]*dtoverlay=\([a-zA-Z0-9_.-][a-zA-Z0-9_.-]*\).*/\1/p' \
	"$config" | sort -u)

if [ -z "$wanted" ]; then
	note "no dtoverlay lines in config.txt, nothing to check"
	if [ -n "$disabled" ]; then
		note "commented out: $disabled"
	fi
	exit 0
fi

count=$(printf '%s\n' "$wanted" | wc -l | tr -d ' ')
note "requested    $count: $(printf '%s' "$wanted" | tr '\n' ' ')"
if [ -n "$disabled" ]; then
	note "commented out, not checked: $disabled"
fi

# The directory being absent is a different fault from a file being absent,
# and it has a different cause, so it gets its own message rather than being
# reported as every overlay missing at once.
if [ ! -d "$dir" ]; then
	echo "error: $dir does not exist, so none of the $count requested" >&2
	echo "       overlays can load. On a Yocto image this means the" >&2
	echo "       bootfiles were assembled without them." >&2
	exit 1
fi

have=0
for f in "$dir"/*.dtbo; do
	if [ -e "$f" ]; then
		have=$((have + 1))
	fi
done
note "on the card  $have .dtbo files"

missing=
for name in $wanted; do
	[ -f "$dir/$name.dtbo" ] || missing="$missing $name"
done

if [ -n "$missing" ]; then
	echo "error: config.txt asks for overlays that are not on this card:" >&2
	for name in $missing; do
		echo "           $name   (expected $dir/$name.dtbo)" >&2
	done
	echo "       The firmware skips these without a word and the kernel" >&2
	echo "       never hears about it, so the board will boot and the" >&2
	echo "       features they provide will simply be absent." >&2
	echo "       For a meta-raspberrypi image the fix is in the kas file:" >&2
	echo "           KERNEL_DEVICETREE:append = \" overlays/NAME.dtbo\"" >&2
	exit 1
fi

note "every requested overlay is present"
