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
SPIDTS=$ROOT/meta-bench/recipes-bench/bench-adxl345-dt/files/bench-adxl345-spi-overlay.dts
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

for f in "$DTS" "$SPIDTS" "$RECIPE" "$I2C" "$IMG" "$KAS" "$DESIGN"; do
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
SPIDTS_CODE=$(code_of "$SPIDTS" c)
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
# ${B} here is BitBake's build directory inside the recipe text being
# searched, not a shell expansion, and single quotes are what keep it
# literal. shellcheck cannot tell the difference and reports SC2016,
# which is an info finding that still exits non-zero and so fails the
# whole run.
# shellcheck disable=SC2016
has "and deploys it beside the other" \
	"$RECIPE" 'install -m 0644 ${B}/bench-adxl345-adi.dtbo'
has "the image carries both overlays" "$IMG" 'overlays/bench-adxl345-adi.dtbo'

# Carrying both is not loading both. config.txt names one, and which one
# is the whole experiment.
hasnt "and config.txt still asks for ours, not the control" \
	"$KAS" 'dtoverlay=bench-adxl345-adi'

# ------------------------------------------------- the SPI arm, on paper
#
# Added Monday 19 October 2026, and NOTHING HERE IS A HARDWARE CLAIM.
# No part has ever answered over SPI on this bench. What these assertions
# hold together is the same set of agreements the I2C arm needs, so that
# the bench session which moves the straps does not also discover that a
# file disagrees with another file.
#
# The three SPI properties are checked against the driver's own statement
# of them rather than against a datasheet remembered here.
# bench-adxl345-spi.c says the part is CPOL=1 CPHA=1 and that the device
# tree states it, and that the 5 MHz ceiling is stated there too. If that
# file is ever changed to assume them instead, these fail and say so.

SPI=$ROOT/meta-bench/recipes-bench/bench-adxl345/files/bench-adxl345-spi.c

has "the SPI overlay claims this project's compatible" 	"$SPIDTS_CODE" 'compatible = "bench,adxl345";'
hasnt "and not mainline's" "$SPIDTS_CODE" '"adi,adxl345"'
has "it targets spi0" "$SPIDTS_CODE" 'target = <&spi0>;'
has "the node sits on chip select 0" "$SPIDTS_CODE" 'adxl345@0 {'
has "and reg says the same" "$SPIDTS_CODE" 'reg = <0>;'

# Two drivers on one chip select is the defect this bench met on eplepi,
# where config.txt had given both SPI0 chip selects to CAN overlays. The
# firmware declares a spidev on each, so the overlay removes the one it
# is about to occupy instead of relying on winning it.
has "it disables the firmware's spidev on that chip select" 	"$SPIDTS_CODE" 'target = <&spidev0>;'
has "and says disabled" "$SPIDTS_CODE" 'status = "disabled";'

has "the overlay states SPI mode 3, polarity" "$SPIDTS_CODE" 'spi-cpol;'
has "and phase" "$SPIDTS_CODE" 'spi-cpha;'
has "the driver is the authority for that, and still says so" 	"$SPI" 'CPOL=1 CPHA=1'
has "the overlay states the 5 MHz ceiling" 	"$SPIDTS_CODE" 'spi-max-frequency = <5000000>;'
has "and the driver still leaves it to the device tree" 	"$SPI" 'spi-max-frequency'

# The interrupt lead does not move when the bus does, so this is the one
# property that must be identical in both overlays rather than merely
# present in each.
has "the SPI overlay keeps INT1 on GPIO23, level high" 	"$SPIDTS_CODE" 'interrupts = <23 4>;'
i2cirq=$(grep -o 'interrupts = <[0-9]* [0-9]*>;' "$DTS_CODE" | head -1)
spiirq=$(grep -o 'interrupts = <[0-9]* [0-9]*>;' "$SPIDTS_CODE" | head -1)
if [ "$i2cirq" = "$spiirq" ] && [ -n "$i2cirq" ]; then
	ok "and it is the same cell the I2C overlay asks for"
else
	no "and it is the same cell the I2C overlay asks for" 		"i2c: $i2cirq  spi: $spiirq"
fi

# The four names have to agree across three files, which is what row
# three of the list at the top of this file is about. Four overlays now.
has "the recipe compiles bench-adxl345-spi.dtbo" 	"$RECIPE" 'bench-adxl345-spi\.dtbo'
has "and the SPI control beside it" 	"$RECIPE" 'bench-adxl345-spi-adi\.dtbo'
# shellcheck disable=SC2016
has "it deploys the SPI overlay" 	"$RECIPE" 'install -m 0644 ${B}/bench-adxl345-spi.dtbo ${DEPLOYDIR}/overlays/'
# shellcheck disable=SC2016
has "and the SPI control" 	"$RECIPE" 'install -m 0644 ${B}/bench-adxl345-spi-adi.dtbo ${DEPLOYDIR}/overlays/'
has "the recipe fetches the SPI source" 	"$RECIPE" 'file://bench-adxl345-spi-overlay.dts'
has "the image copies the SPI overlay onto the card" 	"$IMG" 'overlays/bench-adxl345-spi\.dtbo;overlays/bench-adxl345-spi\.dtbo'
has "and the SPI control" 	"$IMG" 'overlays/bench-adxl345-spi-adi\.dtbo;overlays/bench-adxl345-spi-adi\.dtbo'

# The substitution guard, both directions, the same as the I2C control's.
# A control identical to its subject is the failure that reads as a
# perfect agreement.
# The control is REDIRECTED INTO ITS OWN FILE, which is what makes it a
# separate subject rather than an in-place edit of the thing it is a
# control for. BitBake variable syntax, so single quotes.
# shellcheck disable=SC2016
has "the SPI control is generated into its own file" 	"$RECIPE" '> ${B}/bench-adxl345-spi-adi-overlay.dts'
has "from the SPI source and not the I2C one" 	"$RECIPE" 'bench-adxl345-spi-overlay.dts'
has "and a substitution that did not apply is fatal" 	"$RECIPE" 'the SPI control overlay has no adi,adxl345 compatible'
has "and so is one that left ours behind" 	"$RECIPE" 'the SPI control overlay still claims bench,adxl345'

# Carrying four is not loading four. config.txt names one, and the SPI
# arm needs the straps moved before it can be the one.
hasnt "config.txt does not yet ask for the SPI overlay" 	"$KAS" 'dtoverlay=bench-adxl345-spi'
has "the .dts says on its face that no part has answered over SPI" 	"$SPIDTS" 'NOT YET RUN ON HARDWARE'
has "and that the brown lead comes off first" "$SPIDTS" 'brown lead comes'

# --------------------------------------------- the four overlays compile
#
# ADDED TUESDAY 20 OCTOBER 2026, CLOSING A NAMED GAP.
#
# bench-adxl345-spi-overlay.dts was written on Sunday 18 October and had
# been read by no compiler anywhere: there is no dtc on the authoring
# laptop, and the lint job does not run BitBake, so its first real compile
# would have been a build on the build laptop. What ran instead was a
# structural check, braces and angle brackets balanced. That is not a
# compile and was not presented as one.
#
# tests/lcd35a-overlay-test.sh has compiled Project 7's overlay this way
# since before any of this, and scripts/host-setup.sh and the CI workflow
# both install device-tree-compiler for it. So the tool was there the
# whole time and this suite simply never asked. The shape below is that
# sibling's, copied rather than varied.
#
# All four, because the recipe builds four .dtbo and the two controls are
# generated by a sed the recipe runs at build time. A control that does
# not compile fails the build, and generating it here with the same
# substitution is the only way a test can see that before BitBake does.
if command -v dtc >/dev/null 2>&1; then
	for src in "$DTS" "$SPIDTS"; do
		base=$(basename "$src" .dts)

		# -@ keeps the symbol table, which is what lets an overlay
		# resolve &i2c1, &spi0, &spidev0 and &gpio at load time.
		# Without it the firmware refuses the file with a message
		# that reads like corruption.
		if dtc -@ -I dts -O dtb -o "$WORK/$base.dtbo" "$src" 			2>"$WORK/$base.err"; then
			if [ -s "$WORK/$base.err" ]; then
				no "dtc compiles $base with no warnings" 					"$(head -3 "$WORK/$base.err")"
			else
				ok "dtc compiles $base with no warnings"
			fi
		else
			no "dtc compiles $base" "$(head -5 "$WORK/$base.err")"
		fi

		# The control, generated exactly as the recipe generates it.
		sed 's/compatible = "bench,adxl345";/compatible = "adi,adxl345";/' 			"$src" >"$WORK/$base-adi.dts"
		if dtc -@ -I dts -O dtb -o "$WORK/$base-adi.dtbo" 			"$WORK/$base-adi.dts" 2>"$WORK/$base-adi.err"; then
			if [ -s "$WORK/$base-adi.err" ]; then
				no "dtc compiles the $base control with no warnings" 					"$(head -3 "$WORK/$base-adi.err")"
			else
				ok "dtc compiles the $base control with no warnings"
			fi
		else
			no "dtc compiles the $base control" 				"$(head -5 "$WORK/$base-adi.err")"
		fi
	done
else
	echo "skipped  dtc is absent, so none of the four overlays was"
	echo "         compiled here. The build laptop and CI both install"
	echo "         device-tree-compiler and do compile them, so this is"
	echo "         a gap on this host and not in the suite."
fi

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
