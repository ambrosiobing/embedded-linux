#!/bin/sh
#
# lcd35a-overlay-test.sh - Project 7's overlay, fragment, image recipe and
# design document against each other.
#
# Project 7 has almost no application. Its product is a hardware
# description and a kernel configuration, and every way it can fail is a
# way that a build cannot see: a fragment line Kconfig drops, a device
# tree property read as the wrong width, a pin claimed by two drivers.
# None of those produce an error anywhere. They produce a board that does
# not work, a week later, with nothing in any log.
#
# So this suite reads the files as text and asserts that they still agree.
# Nothing here needs a board, and the dtc section is skipped rather than
# failed where dtc is absent, which is said out loud rather than silently.
#
# THE ASSERTIONS THAT ARE NOT ABOUT SYNTAX:
#
#   spidev0 and spidev1 are both disabled   or the panel never binds
#   every ti,* numeric carries /bits/ 16    or the driver reads half a cell
#   every symbol in lcd35a.cfg is =y        or the image recipe's comment lies
#   bench-status is removed from the image  or two drivers want GPIO17
#   drmfill's driver name == the overlay's  or it can never find the panel
#
#   sh tests/lcd35a-overlay-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DTS=$ROOT/meta-bench/recipes-bench/bench-lcd35a-overlay/files/bench-lcd35a-overlay.dts
CFG=$ROOT/meta-bench/recipes-kernel/linux/files/lcd35a.cfg
IMG=$ROOT/meta-bench/recipes-core/images/bench-lcd35a-image.bb
FILL=$ROOT/meta-bench/recipes-bench/bench-lcd35a/files/drmfill.c
VERIFY=$ROOT/meta-bench/recipes-bench/bench-lcd35a/files/lcd35a-verify
KAS=$ROOT/kas/bench-lcd35a.yml
DESIGN=$ROOT/projects/07-lcd35-drm/docs/DESIGN.md

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
skip=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	fail=$((fail + 1))
	[ $# -gt 1 ] && printf '         %s\n' "$2"
	return 0
}

skipped() {
	echo "skipped  $1"
	skip=$((skip + 1))
}

has() {
	# has DESCRIPTION FILE PATTERN
	if grep -q "$3" "$2"; then
		ok "$1"
	else
		no "$1" "not found in $(basename "$2"): $3"
	fi
}

echo "--- every file this suite reads exists"
for f in "$DTS" "$CFG" "$IMG" "$FILL" "$VERIFY" "$KAS" "$DESIGN"; do
	if [ -f "$f" ]; then
		ok "$(basename "$f")"
	else
		no "missing: $f"
	fi
done
[ "$fail" -eq 0 ] || {
	echo
	echo "cannot continue with files missing"
	exit 1
}

echo
echo "--- the bus conflict that produces no useful error"

# With spidev left enabled the panel node never binds and the only thing
# dmesg says is that chipselect 0 is already in use. Two assertions, not
# one, because a copy of this overlay that disabled only spidev0 would
# lose the touch controller and keep the panel, which is harder to notice.
for node in spidev0 spidev1; do
	if awk -v n="$node" '
		$0 ~ "target = <&" n ">" { found = 1 }
		found && /status/ { print; exit }
	' "$DTS" | grep -q 'disabled'; then
		ok "$node is disabled"
	else
		no "$node is not disabled" \
			"the panel will not bind: chipselect already in use"
	fi
done

echo
echo "--- the property width that is read wrong rather than rejected"

# The ads7846 binding declares these as 16-bit cells and the driver reads
# them with device_property_read_u16. Without /bits/ 16 they are 32-bit
# cells, the driver reads the wrong half of each, and the result is a
# touchscreen that reports nonsense rather than one that fails to probe.
for prop in x-plate-ohms pressure-max x-min x-max y-min y-max; do
	line=$(grep "ti,$prop" "$DTS" || true)
	if [ -z "$line" ]; then
		no "ti,$prop is absent from the overlay"
	elif echo "$line" | grep -q '/bits/ 16'; then
		ok "ti,$prop carries /bits/ 16"
	else
		no "ti,$prop has no /bits/ 16" \
			"the driver will read the wrong half of the cell"
	fi
done

echo
echo "--- the driver names, which three files have to agree on"

has "the overlay names the panel compatible the driver matches" \
	"$DTS" 'waveshare,rpi-lcd-35'
has "the overlay names the touch compatible" "$DTS" 'ti,ads7846'
has "drmfill looks for the same driver name" "$FILL" '"ili9486"'
has "lcd35a-verify looks for the same driver name" "$VERIFY" 'ili9486'
has "lcd35a-verify looks for the touch driver too" "$VERIFY" 'ads7846'

echo
echo "--- the three GPIOs, against the design document's wiring table"

# Any pin in the overlay that the wiring table does not mention is a pin
# somebody added without telling the reader.
pins=$(awk -F'[<>]' '/brcm,pins/ { print $2 }' "$DTS")
if [ -z "$pins" ]; then
	no "no brcm,pins line in the overlay"
else
	for p in $pins; do
		if grep -q "GPIO$p" "$DESIGN"; then
			ok "GPIO$p is in the design document's wiring table"
		else
			no "GPIO$p is in the overlay and not in the table"
		fi
	done
fi

# And the same three have to be the ones the nodes actually reference.
for want in "dc-gpios.*24" "reset-gpios.*25" "pendown-gpio.*17"; do
	has "the overlay references $want" "$DTS" "$want"
done

echo
echo "--- the fragment is entirely =y, which the image recipe depends on"

# bench-lcd35a-image says it needs no kernel-module-* lines because this
# fragment is built in. That sentence is true today and is one careless
# "=m" away from being a lie that costs a flash and a boot.
bad=""
while read -r line; do
	case $line in
	CONFIG_*=m) bad="$bad $line" ;;
	esac
done <"$CFG"
if [ -z "$bad" ]; then
	ok "no =m in lcd35a.cfg"
else
	no "lcd35a.cfg has modules:$bad" \
		"bench-lcd35a-image claims it needs no kernel-module lines"
fi

# The two that are load bearing rather than merely present. Both are
# modules in the Raspberry Pi 3 defconfig, and either one missing takes
# the whole project with it.
has "the SPI bus controller is forced built in" "$CFG" '^CONFIG_SPI_BCM2835=y'
has "DRM is forced built in" "$CFG" '^CONFIG_DRM=y'
has "the panel driver is built in" "$CFG" '^CONFIG_TINYDRM_ILI9486=y'
has "the touch driver is built in" "$CFG" '^CONFIG_TOUCHSCREEN_ADS7846=y'

# HWMON is the subtle one. TOUCHSCREEN_ADS7846 is declared
# "depends on HWMON = n || HWMON", so with HWMON=m the =y line above is
# not a valid configuration and Kconfig drops it without a word.
has "HWMON is pinned so the touch driver can be built in" \
	"$CFG" '^CONFIG_HWMON=y'

# And the console chain, which acceptance criterion 2 rides on.
has "fbdev emulation is on" "$CFG" '^CONFIG_DRM_FBDEV_EMULATION=y'
has "the framebuffer console is on" "$CFG" '^CONFIG_FRAMEBUFFER_CONSOLE=y'

echo
echo "--- the pin that two drivers would otherwise want"

# Project 1's bench-status holds GPIO17, GPIO22 and GPIO27. GPIO17 is this
# panel's pen-down interrupt and ads7846 requests it at probe. bench-image
# installs bench-status, so this image has to remove it, and the symptom
# of forgetting would look like a touch fault rather than a conflict.
has "the image removes bench-status" "$IMG" 'IMAGE_INSTALL:remove.*bench-status'

echo
echo "--- the image installs what the criteria are measured with"

has "libdrm-tests, which carries modetest for criterion 3" \
	"$IMG" 'libdrm-tests'
has "evtest, which reads the raw corners for criterion 5" "$IMG" 'evtest'
has "the overlay recipe" "$IMG" 'bench-lcd35a-overlay'
has "the overlay reaches the boot partition" "$IMG" 'IMAGE_BOOT_FILES'
has "and is deployed before the image is assembled" \
	"$IMG" 'do_image\[depends\].*bench-lcd35a-overlay:do_deploy'

echo
echo "--- the kas file"

has "the kernel switch is on" "$KAS" 'BENCH_LCD35A_KERNEL = "1"'
has "the SPI bus is enabled in config.txt" "$KAS" 'ENABLE_SPI_BUS = "1"'
has "the overlay is loaded by config.txt" "$KAS" 'dtoverlay=bench-lcd35a'
has "the DSI panel overlay is not inherited" "$KAS" 'RPI_EXTRA_CONFIG ='

# The DSI overlay belongs to the Pi 4 bench image and is an overlay for
# hardware this board does not have, which costs a deferred probe retrying
# for ever.
if grep -q 'vc4-kms-dsi-7inch' "$KAS"; then
	no "the kas file still loads the 7 inch DSI overlay"
else
	ok "no DSI overlay for a board that has no DSI display"
fi

echo
echo "--- the overrides, which are acceptance criterion 6"

for ov in speed rotate swapxy; do
	has "override $ov" "$DTS" "^[[:space:]]*$ov[[:space:]]*="
done

echo
echo "--- dtc"

if command -v dtc >/dev/null 2>&1; then
	# -@ keeps the symbol table, which is what lets the overlay resolve
	# &spi0 and &gpio on the board. Warnings are collected rather than
	# ignored: criterion 6 is that this compiles without them, so a
	# warning is a failure here and not a note.
	if dtc -@ -I dts -O dtb -o "$WORK/out.dtbo" "$DTS" 2>"$WORK/err"; then
		if [ -s "$WORK/err" ]; then
			no "dtc compiled it with warnings" \
				"$(head -3 "$WORK/err")"
		else
			ok "dtc -@ compiles it with no warnings"
		fi
		# A .dtbo without a symbol table cannot resolve phandles at
		# load time, and dtoverlay rejects it with "not a base or
		# overlay", which reads like corruption.
		if fdtget -l "$WORK/out.dtbo" / 2>/dev/null |
			grep -q '__symbols__'; then
			ok "the compiled overlay carries a symbol table"
		else
			skipped "symbol table check needs fdtget"
		fi
	else
		no "dtc refused the overlay" "$(head -5 "$WORK/err")"
	fi
else
	skipped "dtc is absent, so the overlay was not compiled here.
         CI installs device-tree-compiler and does compile it, so this
         is a gap on this host and not in the suite."
fi

echo
printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
