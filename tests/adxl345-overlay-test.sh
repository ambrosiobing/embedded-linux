#!/bin/sh
#
# adxl345-overlay-test.sh - the overlay against the driver, the image and
# the kas file, with no dtc, no kernel and no board.
#
# Four files have to agree for the part to appear in /sys/bus/iio, and
# nothing in BitBake checks any of the four agreements:
#
#   the compatible in the overlay == the one the I2C bus file matches
#   the address in the overlay    == the one read off the bus, 0x53
#   the .dtbo name the recipe deploys == the name the image copies
#                                     == the name config.txt requests
#   the interrupt in the overlay    == the pin the design's wiring table
#                                      says INT1 is on
#
# Each of those is a claim written when it was true. The last one has
# already changed once: it was written as its opposite, no interrupt
# property while INT1 was unwired, and inverted the night the wire went
# on. A node that names a GPIO nothing drives probes cleanly, reads
# cleanly through sysfs, and never fills a buffer, which is why the two
# files are held to each other rather than either being trusted alone.
#
#   sh tests/adxl345-overlay-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DTS=$ROOT/meta-bench/recipes-bench/bench-adxl345-dt/files/bench-adxl345-overlay.dts
RECIPE=$ROOT/meta-bench/recipes-bench/bench-adxl345-dt/bench-adxl345-dt_0.1.bb
I2C=$ROOT/meta-bench/recipes-bench/bench-adxl345/files/bench-adxl345-i2c.c
IMG=$ROOT/meta-bench/recipes-core/images/bench-adxl345-image.bb
KAS=$ROOT/kas/bench-adxl345.yml
DESIGN=$ROOT/projects/05-iio-adxl345/docs/DESIGN.md

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

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

has() {
	# has DESCRIPTION FILE PATTERN
	if grep -q "$3" "$2"; then
		ok "$1"
	else
		no "$1" "expected to find: $3"
	fi
}

hasnt() {
	if grep -q "$3" "$2"; then
		no "$1" "should not contain: $3"
	else
		ok "$1"
	fi
}

for f in "$DTS" "$RECIPE" "$I2C" "$IMG" "$KAS" "$DESIGN"; do
	[ -r "$f" ] || {
		echo "FAILED   missing input: $f"
		exit 1
	}
done

# Comments removed before any absence check, for the reason
# tests/explorer-overlay-test.sh gives at length: the overlay's own
# comment quotes mainline's compatible string while explaining why the
# node does not use it, and a rule that cannot tell use from mention
# would flag the documentation of the decision it protects.
code_of() {
	out=$WORK/$(basename "$1").code
	case $2 in
	c) sed -e 's|/\*.*||' -e 's|//.*||' -e '/^[[:space:]]*\*/d' "$1" >"$out" ;;
	hash) sed 's/#.*//' "$1" >"$out" ;;
	*)
		echo "code_of: unknown style $2" >&2
		exit 1
		;;
	esac
	printf '%s\n' "$out"
}

DTS_CODE=$(code_of "$DTS" c)
I2C_CODE=$(code_of "$I2C" c)

echo "--- the compatible string, which is the A/B switch"

compat=$(sed -n 's/.*compatible = "\(bench,adxl345\)".*/\1/p' "$DTS_CODE" | head -n 1)
if [ "$compat" = "bench,adxl345" ]; then
	ok "the overlay declares bench,adxl345"
else
	no "the overlay declares bench,adxl345" "got: ${compat:-nothing}"
fi
has "and the I2C bus file matches exactly that string" "$I2C_CODE" '\.compatible = "bench,adxl345"'
hasnt "the overlay does not also claim mainline's string" "$DTS_CODE" '"adi,adxl345"'

echo "--- the address, read off the bus on Friday 9 October 2026"

has "the node sits at 0x53" "$DTS_CODE" 'adxl345@53 {'
has "and reg says the same" "$DTS_CODE" 'reg = <0x53>;'
has "the design records 0x53 for SDO low" "$DESIGN" 'low gives .0x53.'

echo "--- one .dtbo name across recipe, image and config.txt"

has "the recipe compiles bench-adxl345.dtbo" "$RECIPE" 'bench-adxl345\.dtbo'
has "and deploys it into overlays/" "$RECIPE" 'install -m 0644 ${B}/bench-adxl345.dtbo ${DEPLOYDIR}/overlays/'
has "the image copies overlays/bench-adxl345.dtbo onto the card" "$IMG" 'IMAGE_BOOT_FILES:append = " overlays/bench-adxl345.dtbo;overlays/bench-adxl345.dtbo"'
has "and waits for the deploy before assembling" "$IMG" 'do_image\[depends\] += "bench-adxl345-dt:do_deploy"'
has "the image installs the overlay recipe" "$IMG" '^    bench-adxl345-dt \\'
has "config.txt requests dtoverlay=bench-adxl345" "$KAS" 'dtoverlay=bench-adxl345'
hasnt "and requests it through an override, never a plain assignment" "$KAS" '^    RPI_EXTRA_CONFIG = '

echo "--- the interrupt, now that INT1 is wired"

# This group was its own opposite until late on Friday 9 October 2026:
# no interrupts property while the design's wiring table said INT1 was
# not connected. The wire went onto header pin 16 that night, the
# property went into the node, and the three assertions inverted. The
# overlay's own comment carries the reasoning for level high.
has "the node names the gpio controller as its interrupt parent" "$DTS_CODE" 'interrupt-parent = <&gpio>;'
has "and asks for GPIO23, level high" "$DTS_CODE" 'interrupts = <23 4>;'
has "and the design's wiring table puts INT1 on pin 16" "$DESIGN" '| `INT1` | 16 | GPIO23 |'

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
