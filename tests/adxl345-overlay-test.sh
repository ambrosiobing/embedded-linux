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
# The pattern is BitBake's own variable syntax, which is the point of
# the assertion; single quotes keep the shell out of it.
# shellcheck disable=SC2016
has "and deploys it into overlays/" "$RECIPE" 'install -m 0644 ${B}/bench-adxl345.dtbo ${DEPLOYDIR}/overlays/'
# The source;destination pair rather than the whole assignment. The
# first spelling of this matched the complete line including its closing
# quote, so adding the control overlay on Saturday 17 October 2026 broke
# it by turning that quote into a backslash continuation. What the
# assertion is about is that this file reaches the card, and the pair is
# what says so.
has "the image copies overlays/bench-adxl345.dtbo onto the card" \
	"$IMG" 'overlays/bench-adxl345.dtbo;overlays/bench-adxl345.dtbo'
has "and IMAGE_BOOT_FILES is appended to rather than replaced" \
	"$IMG" '^IMAGE_BOOT_FILES:append'
has "and waits for the deploy before assembling" "$IMG" 'do_image\[depends\] += "bench-adxl345-dt:do_deploy"'
has "the image installs the overlay recipe" "$IMG" '^    bench-adxl345-dt '
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
# Backticks inside the pattern are Markdown, not a command
# substitution, and single quotes are what keeps them that way.
# shellcheck disable=SC2016
has "and the design's wiring table puts INT1 on pin 16" "$DESIGN" '| `INT1` | 16 | GPIO23 |'

echo "--- the control overlay, which is this one with a single property changed"

# ACCEPTANCE CRITERION 7 IS A COMPARISON, AND A COMPARISON DIFFERS IN
# ONE VARIABLE OR IT IS NOT ONE. The control that puts this part under
# mainline's driver is generated in the recipe by substituting the
# compatible, rather than kept as a second .dts, because two copies of a
# description drift and this repository has paid for that twice.
#
# The substitution is reproduced here and the result compared with the
# source, so the one-variable property is checked rather than trusted.
# diff prints one line for the removal and one for the addition, hence
# two.
CTRL=$WORK/control.dts
sed 's/compatible = "bench,adxl345";/compatible = "adi,adxl345";/' \
	"$DTS" >"$CTRL"
# The "|| true" is load bearing under set -e: grep -c prints 0 and exits
# 1 when it matches nothing, and nothing is exactly the case this
# assertion exists to catch, so without it the suite ends here instead of
# reporting. Found by breaking the substitution on purpose and watching
# a different assertion fail while this one said nothing at all.
differing=$(diff "$DTS" "$CTRL" | grep -c '^[<>]' || true)
if [ "$differing" -eq 2 ]; then
	ok "the control differs from the source in exactly one line"
else
	no "the control differs in $((differing / 2)) lines, not one"
fi
has "and that line is mainline's compatible" "$CTRL" 'compatible = "adi,adxl345";'
hasnt "and ours is not in it" "$CTRL" 'compatible = "bench,adxl345";'

# The recipe has to do the same substitution, anchored the same way. A
# looser pattern would edit the comment block as well, which quotes both
# strings while explaining the switch.
has "the recipe generates the control from the one source" \
	"$RECIPE" "sed 's/compatible = \"bench,adxl345\";/compatible = \"adi,adxl345\";/'"

# And the failure that matters: sed is silent when its pattern is absent,
# so a substitution that stopped applying would produce a control that is
# a byte-for-byte copy of the thing it is a control for. Every
# measurement taken with it would then agree perfectly, for the wrong
# reason, and nothing downstream could tell.
has "and refuses a control with no adi compatible" \
	"$RECIPE" 'bbfatal "the control overlay has no adi,adxl345 compatible'
has "and one that still claims ours" \
	"$RECIPE" 'bbfatal "the control overlay still claims bench,adxl345"'
has "the recipe compiles the control" "$RECIPE" 'bench-adxl345-adi.dtbo'
has "and deploys it beside the other" \
	"$RECIPE" 'install -m 0644 ${B}/bench-adxl345-adi.dtbo'
has "the image carries both overlays" "$IMG" 'overlays/bench-adxl345-adi.dtbo'

# Carrying both is not loading both. config.txt names one, and which one
# is the whole experiment.
hasnt "and config.txt still asks for ours, not the control" \
	"$KAS" 'dtoverlay=bench-adxl345-adi'

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
