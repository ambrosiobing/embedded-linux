#!/bin/sh
#
# explorer-overlay-test.sh - the overlay against the documents, and the
# kernel fragment against the claim the image recipe makes about it.
#
# Project 6 has no application. Its product is a hardware description plus
# four documents that describe the same twenty numbers, and the failure
# this suite exists to prevent is the one the skill file calls out as the
# shape behind the bench's two worst bugs: a claim written when it was
# true, left standing after the thing it described changed.
#
# Nothing here needs dtc, a kernel or a board. It reads the .dts, the
# fragment, the image recipe and the pin map as text and asserts that they
# still agree with each other.
#
# THE THREE CROSS-FILE ASSERTIONS ARE THE POINT:
#
#   the input device name in the overlay == the one explorer-verify greps
#   every BCM pin in the overlay == one the pin map document lists
#   every symbol in explorer.cfg is =y == what bench-explorer-image claims
#
# The last one guards a comment. bench-explorer-image says it needs no
# kernel-module-* lines because explorer.cfg is entirely built in, and
# that sentence is true today and is one careless "=m" away from being a
# lie that costs a flash and a boot.
#
#   sh tests/explorer-overlay-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DTS=$ROOT/meta-bench/recipes-bench/bench-explorer700/files/bench-explorer700-overlay.dts
CFG=$ROOT/meta-bench/recipes-kernel/linux/files/explorer.cfg
IMG=$ROOT/meta-bench/recipes-core/images/bench-explorer-image.bb
VERIFY=$ROOT/meta-bench/recipes-bench/bench-explorer/files/explorer-verify
PINMAP=$ROOT/projects/06-explorer700/docs/pin-map.md
KAS=$ROOT/kas/bench-explorer.yml

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

count_is() {
	# count_is DESCRIPTION FILE PATTERN WANT
	got=$(grep -c "$3" "$2" || true)
	if [ "$got" = "$4" ]; then
		ok "$1"
	else
		no "$1" "want $4 matches of '$3', got $got"
	fi
}

for f in "$DTS" "$CFG" "$IMG" "$VERIFY" "$PINMAP" "$KAS"; do
	[ -r "$f" ] || {
		echo "FAILED   missing input: $f"
		exit 1
	}
done

# code_of FILE STYLE prints the path of a copy with the comments removed.
#
# EVERY ABSENCE CHECK BELOW RUNS AGAINST ONE OF THESE, and the reason is
# that the first run of this suite produced three false positives, all the
# same shape: the overlay's own comment explaining why there is no
# cs-gpios, the one explaining why the buzzer is not a pwm-beeper, and the
# image recipe's paragraph explaining why it names no kernel-module
# package. A rule that cannot tell use from mention flags the
# documentation of the very decision it is there to protect.
#
# That is now the fourth, fifth and sixth time in this repository, after
# the firewall test on a cross-referencing comment, the image package
# check on bench-hub-image, and the HIL server test on install.sh. The fix
# has been the same every time and is the same here: name the legitimate
# context. Widening the pattern or deleting the rule both end with a
# check that teaches its reader to skip a line.
code_of() {
	out=$WORK/$(basename "$1").code
	case $2 in
	# Device tree and BitBake C-style: blank from /* onward, drop the
	# continuation lines of a block comment, drop // to end of line.
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
IMG_CODE=$(code_of "$IMG" hash)

echo "--- the OLED is on SPI, which is where the specification is wrong"

has "the panel uses the DRM compatible" "$DTS" 'compatible = "solomon,ssd1306"'
hasnt "and not the fbdev I2C one the specification names" "$DTS_CODE" "ssd1306fb-i2c"
has "the display fragment targets spi0" "$DTS" "target = <&spi0>"
has "spidev0 is disabled, or it keeps chip select 0" "$DTS" "target = <&spidev0>"

# dc-gpios is not optional: ssd130x-spi does devm_gpiod_get(dev, "dc", ...)
# with no _optional, so a node without it fails probe. A 4-wire SPI panel
# has no control byte to carry data-versus-command, which is the whole
# difference from the I2C part.
has "dc-gpios is present, which the driver requires" "$DTS" "dc-gpios"
has "reset-gpios is present, and the board wires it" "$DTS" "reset-gpios"

# The controller drives GPIO8 as CE0. Claiming it again in the node would
# be two owners on one line, which is the class of bug the design
# document's ownership table exists for.
hasnt "the node does not claim chip select as a gpio" "$DTS_CODE" "cs-gpios"

echo
echo "--- the joystick, which the specification maps wrongly"

count_is "five keys" "$DTS" "linux,code = <" 5
has "left is expander line 0" "$DTS" "gpios = <&pcf8574 0 1>"
has "up is expander line 1" "$DTS" "gpios = <&pcf8574 1 1>"
has "down is expander line 2" "$DTS" "gpios = <&pcf8574 2 1>"
has "right is expander line 3" "$DTS" "gpios = <&pcf8574 3 1>"

# The fifth key is NOT on the expander. The specification puts it on line
# 4; the vendor manual puts it on a SoC pin, and line 4 drives the second
# LED instead.
has "press is on GPIO20, not on the expander" "$DTS" "gpios = <&gpio 20 1>"
has "expander line 4 is the second LED" "$DTS" "gpios = <&pcf8574 4 0>"

# Five distinct key codes. Two keys sharing one code is a joystick where
# two directions do the same thing, which reads as a broken contact.
codes=$(grep -o "linux,code = <[0-9]*>" "$DTS" | sort -u | wc -l)
if [ "$codes" -eq 5 ]; then
	ok "the five key codes are distinct"
else
	no "the five key codes are distinct" "got $codes distinct codes"
fi

# Polled, because four of the five lines are on an I2C expander and those
# are sleeping lines. A driver using the atomic accessors refuses them at
# probe with -EINVAL.
has "the keys are polled" "$DTS" 'compatible = "gpio-keys-polled"'
has "and a poll interval is set, which the binding requires" "$DTS" "poll-interval"

echo
echo "--- the decisions the design document records as deliberate"

# The expander's INT is on GPIO21 and is deliberately unused: an
# open-drain output with no confirmed pull-up under an edge-triggered
# handler is an interrupt storm, not a silent failure. If somebody adds
# it, this test should fail and send them to read the argument first.
hasnt "the expander has no interrupt, which is the documented choice" \
	"$DTS_CODE" "interrupt-parent"
has "and the file says why" "$DTS" "NO INTERRUPT HERE"

# GPIO18 carries the IR receiver, so the specification's pwm-beeper
# fallback is not available on this board.
hasnt "the buzzer is not on PWM" "$DTS_CODE" "pwm-beeper"
has "the buzzer is a gpio-beeper" "$DTS" 'compatible = "gpio-beeper"'

echo
echo "--- the pressure sensor, whose identity the manual contradicts"

has "the address is the manual's 0x76" "$DTS" "reg = <0x76>"
hasnt "and not the specification's 0x77" "$DTS_CODE" "reg = <0x77>"
has "the compatible is bmp280" "$DTS" 'compatible = "bosch,bmp280"'
has "the address is a parameter, so a wrong guess is a config.txt edit" \
	"$DTS" 'bmp_addr = <&bmp>,"reg:0"'

echo
echo "--- cross-file: the overlay and explorer-verify name the same things"

# explorer-verify finds the joystick by input device name rather than by
# event index, because four of its five lines come up over I2C in no fixed
# order. The name comes from the overlay's label property, so the two
# files have to agree and nothing but this test says so.
label=$(grep -o 'label = "explorer700-keys"' "$DTS" || true)
sought=$(grep -o '"explorer700-keys"' "$VERIFY" || true)
if [ -n "$label" ] && [ -n "$sought" ]; then
	ok "the keys label matches what explorer-verify searches for"
else
	no "the keys label matches what explorer-verify searches for" \
		"overlay: '$label', verify: '$sought'"
fi

for led in led1 led2; do
	if grep -q "label = \"explorer:$led\"" "$DTS" &&
		grep -q "explorer:\$led" "$VERIFY"; then
		ok "the overlay defines explorer:$led and the checker looks for it"
	else
		no "the overlay defines explorer:$led and the checker looks for it"
	fi
done

echo
echo "--- cross-file: every BCM pin in the overlay is in the pin map"

# The pin map is the document that carries the evidence for each number
# and the column saying whether anything has confirmed it. A pin that
# reached the overlay without reaching that document is a number with no
# provenance, which on this project is the whole risk.
# Into a file and then redirected in, rather than piped into the loop.
# A "while read" at the end of a pipeline runs in a subshell, so every
# pass and fail this loop counts would be discarded when that subshell
# exits, and the suite would report a total that silently omits these.
grep -o "<&gpio [0-9]* " "$DTS" | grep -o "[0-9]*" | sort -un >"$WORK/pins"
while read -r pin; do
	# The document bolds the pins that differ from the project
	# specification, and that emphasis is carrying meaning. So the
	# pattern tolerates the markers rather than the document dropping
	# them to suit a test.
	#
	# ${pin} rather than $pin: the next character is a bracket, and
	# shellcheck reads "$pin[" as an array subscript (SC1087).
	if grep -qE "[|] [*]{0,2}${pin}[*]{0,2} [|]" "$PINMAP"; then
		ok "GPIO$pin appears in pin-map.md"
	else
		no "GPIO$pin appears in pin-map.md" \
			"the overlay uses it and the document does not list it"
	fi
done <"$WORK/pins"

echo
echo "--- cross-file: the fragment is entirely built in, as the image claims"

# bench-explorer-image names no kernel-module-* package and says in a
# comment that it does not need to, because everything in explorer.cfg is
# =y. That sentence is one careless "=m" away from being a lie, and the
# cost of the lie is the whole I2C bus: the Pi 3 defconfig builds
# CONFIG_I2C_BCM2835 and CONFIG_SPI_BCM2835 as modules.
modules=$(grep -c "^CONFIG_[A-Z0-9_x]*=m" "$CFG" || true)
if [ "$modules" = "0" ]; then
	ok "no symbol in explorer.cfg is a module"
else
	no "no symbol in explorer.cfg is a module" \
		"$modules line(s) are =m, so the image now needs kernel-module-* entries"
fi

hasnt "and the image recipe names no kernel module" "$IMG_CODE" "kernel-module-"

# The two bus controllers, which are the expensive ones to forget.
has "the I2C controller is built in" "$CFG" "^CONFIG_I2C_BCM2835=y"
has "the SPI controller is built in" "$CFG" "^CONFIG_SPI_BCM2835=y"

# BMP280_I2C is not in the Pi defconfig at all, so without this line the
# driver core exists and the part never probes.
has "the BMP280 I2C glue is named" "$CFG" "^CONFIG_BMP280_I2C=y"

# Not the fbdev driver, which depends on I2C and cannot bind an SPI panel.
hasnt "FB_SSD1307 is not requested" "$CFG" "^CONFIG_FB_SSD1307"
has "the DRM SPI transport is" "$CFG" "^CONFIG_DRM_SSD130X_SPI=y"
has "and the shim that gives it a framebuffer node" "$CFG" \
	"^CONFIG_DRM_FBDEV_EMULATION=y"

echo
echo "--- the kas file turns on both buses and frees the console"

has "the kernel fragment switch is on" "$KAS" 'BENCH_EXPLORER_KERNEL = "1"'
has "I2C is enabled" "$KAS" 'ENABLE_I2C = "1"'

# Without SPI there is no spi0 node for the display fragment to attach to,
# and the overlay loads with the OLED silently missing while every other
# peripheral works. It is the least obvious failure in the configuration.
has "SPI is enabled" "$KAS" 'ENABLE_SPI_BUS = "1"'
has "disable-bt frees the PL011 for the CP2102" "$KAS" "dtoverlay=disable-bt"
has "and the overlay is loaded" "$KAS" "dtoverlay=bench-explorer700"

# meta-raspberrypi turns GPIO_IR into its own gpio-ir overlay, which would
# be a second receiver claiming GPIO18.
hasnt "GPIO_IR is not set, or a second IR overlay claims GPIO18" \
	"$KAS" "^ *GPIO_IR ="

echo
echo "--- structure, because there is no dtc on the authoring laptop"

# WHAT THIS SECTION CANNOT DO, said plainly because a check that hides its
# limits is worse than no check: it is not a device tree compiler. It will
# not catch a bad cell count, a property the binding does not allow, or a
# phandle that resolves to the wrong kind of node. dtc on the build laptop
# is the real check and ./go explorer is when it runs.
#
# What it does catch is the two mistakes that are easy to make by hand and
# annoying to diagnose from dtc's output: unbalanced braces, and a
# parameter pointing at a label that does not exist. The second is the one
# worth having, because __overrides__ is the least familiar syntax in the
# file and a parameter naming a missing label is a build failure a long
# way from its cause.

opens=$(tr -cd '{' <"$DTS_CODE" | wc -c)
closes=$(tr -cd '}' <"$DTS_CODE" | wc -c)
if [ "$opens" -eq "$closes" ]; then
	ok "braces balance ($opens pairs)"
else
	no "braces balance" "$opens opening, $closes closing"
fi

# Every fragment needs somewhere to attach.
frags=$(grep -c "fragment@[0-9]" "$DTS_CODE" || true)
targets=$(grep -cE "target(-path)? = " "$DTS_CODE" || true)
if [ "$frags" -eq "$targets" ]; then
	ok "each of the $frags fragments has a target"
else
	no "each fragment has a target" "$frags fragments, $targets targets"
fi

# Every label a parameter points at is defined somewhere in the file.
missing=
for ref in $(sed -n '/__overrides__/,$p' "$DTS_CODE" |
	grep -o "<&[a-z_0-9]*>" | tr -d '<>&' | sort -u); do
	grep -q "^[[:space:]]*$ref:" "$DTS_CODE" || missing="$missing $ref"
done
if [ -z "$missing" ]; then
	ok "every label named by a parameter is defined"
else
	no "every label named by a parameter is defined" "undefined:$missing"
fi

# And the reverse direction is deliberately NOT checked. A label defined
# and never referenced is fine: dtc -@ puts it in the symbol table, which
# is what lets a later overlay or a debugging session reach the node by
# name. ds3231 and pcf8591 are both in that position on purpose.

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
