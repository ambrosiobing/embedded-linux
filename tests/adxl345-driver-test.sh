#!/bin/sh
#
# adxl345-driver-test.sh - the driver as text, because it cannot be built
# here.
#
# Project 5 is the first thing in this repository that compiles kernel
# code, and the authoring machine has no kernel tree. So this suite does
# not compile anything. It reads the three sources, the header, the
# fragment, the recipe and the image recipe as text and asserts the things
# that must agree between them.
#
# That sounds weak and catches a specific, expensive class of defect. The
# failures this guards against all look like working code in review:
#
#   - the compatible string in one bus file drifting from the other, so
#     one bus binds and the other silently does not
#   - claiming mainline's "adi,adxl345", which makes two drivers match one
#     node and lets module load order decide which reading you get
#   - a register used in the core that is defined nowhere, or defined
#     twice with different values
#   - the scale constant drifting from the arithmetic its own comment
#     gives, which is the defect most likely to survive review because
#     every axis still moves and only the magnitude is wrong
#   - a module built by the recipe and never named in the image, which is
#     decision 75 and has cost this bench a board twice
#
# None of it proves the driver works. It proves the parts of it that are
# claims about other files are true. The compile is CI's job once a kernel
# tree exists, and the board's job after that.
#
#   sh tests/adxl345-driver-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/bench-adxl345
HDR=$SRC/files/bench-adxl345.h
CORE=$SRC/files/bench-adxl345-core.c
I2C=$SRC/files/bench-adxl345-i2c.c
SPI=$SRC/files/bench-adxl345-spi.c
RECIPE=$SRC/bench-adxl345_0.1.bb
FRAG=$ROOT/meta-bench/recipes-kernel/linux/files/adxl345.cfg
IMAGE=$ROOT/meta-bench/recipes-core/images/bench-adxl345-image.bb

pass=0
fail=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	fail=$((fail + 1))
}

check() {
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		no "$1"
		echo "         want: $3"
		echo "         got:  $2"
	fi
}

has() {
	if grep -q "$3" "$2"; then
		ok "$1"
	else
		no "$1: '$3' not in $(basename "$2")"
	fi
}

lacks() {
	if grep -q "$3" "$2"; then
		no "$1: '$3' is in $(basename "$2") and should not be"
	else
		ok "$1"
	fi
}

# ------------------------------------------------- the files are all there

for f in "$HDR" "$CORE" "$I2C" "$SPI" "$RECIPE" "$FRAG" "$IMAGE"; do
	if [ -f "$f" ]; then
		ok "$(basename "$f") exists"
	else
		no "$(basename "$f") is missing"
	fi
done

# --------------------------------------------- the compatible string, twice
#
# The whole coexistence argument rests on this one string being ours in
# both bus files and never mainline's. If it drifts in one file, that bus
# stops binding and the other keeps working, which reads as a hardware
# fault.

check "the I2C bus file claims exactly one compatible" \
	"$(grep -c '\.compatible = ' "$I2C")" "1"
check "and so does the SPI bus file" \
	"$(grep -c '\.compatible = ' "$SPI")" "1"

i2c_compat=$(sed -n 's/.*\.compatible = "\([^"]*\)".*/\1/p' "$I2C")
spi_compat=$(sed -n 's/.*\.compatible = "\([^"]*\)".*/\1/p' "$SPI")

check "the two bus files agree on it" "$i2c_compat" "$spi_compat"
check "and it is ours" "$i2c_compat" "bench,adxl345"

# Checked against the extracted value rather than the whole file, because
# both bus files discuss mainline's string in a comment explaining why
# they do not claim it. Grepping the file fails on the explanation, which
# is the wrong thing to punish: the assertion is about what the driver
# matches, not about what it talks about.
if [ "$i2c_compat" = "adi,adxl345" ]; then
	no "the I2C file must not claim mainline's string"
else
	ok "the I2C file does not claim mainline's string"
fi
if [ "$spi_compat" = "adi,adxl345" ]; then
	no "the SPI file must not claim mainline's string"
else
	ok "the SPI file does not claim mainline's string"
fi

# ------------------------------------------------------------- the seam
#
# The core must not know what a bus is. This is the assertion that the
# design document's central claim is still true of the code.

lacks "the core does not include i2c.h" "$CORE" '#include <linux/i2c.h>'
lacks "the core does not include spi.h" "$CORE" '#include <linux/spi'
has "the core takes a regmap" "$CORE" 'struct regmap \*regmap'
has "the I2C file builds one" "$I2C" 'devm_regmap_init_i2c'
has "the SPI file builds one" "$SPI" 'devm_regmap_init_spi'

# Both bus files must import the namespace the core exports into, or the
# module loads and its probe symbol is unresolved.
core_ns=$(sed -n 's/.*EXPORT_SYMBOL_NS_GPL([^,]*, *"\([^"]*\)").*/\1/p' "$CORE")
check "the core exports into a namespace" "$core_ns" "BENCH_ADXL345"
has "the I2C file imports it" "$I2C" "MODULE_IMPORT_NS(\"$core_ns\")"
has "the SPI file imports it" "$SPI" "MODULE_IMPORT_NS(\"$core_ns\")"

# ------------------------------------------- every register is defined once

undefined=0
duplicated=0
# Word splitting is the point here, not an accident: the grep pattern
# admits only [A-Z0-9_], so every match is one whitespace-free token and
# splitting on whitespace yields exactly one symbol per iteration.
#
# The suggested "while read" loop would be wrong rather than merely
# different. The body increments two counters, and a while loop fed by a
# pipe runs in a subshell, so both would come back zero and the two
# assertions below would pass no matter what the header contained. That is
# the worst outcome available: a check that reports success because it
# counted in a scope nobody reads.
#
# The tool's name is deliberately not the first word of any line above.
# A comment that opens with it is parsed as a directive, which is how this
# fix broke the very run it was written for.
# shellcheck disable=SC2013
for sym in $(grep -o 'BENCH_ADXL345_[A-Z0-9_]*' "$CORE" | sort -u); do
	defs=$(grep -c "^#define $sym\b" "$HDR" || true)
	if [ "$defs" -eq 0 ]; then
		# Names defined in the core itself are fine.
		if grep -q "^#define $sym\b" "$CORE"; then
			continue
		fi
		echo "         undefined: $sym"
		undefined=$((undefined + 1))
	elif [ "$defs" -gt 1 ]; then
		echo "         defined $defs times: $sym"
		duplicated=$((duplicated + 1))
	fi
done
check "every register the core uses is defined" "$undefined" "0"
check "and none is defined twice" "$duplicated" "0"

# ------------------------------------------------------- the scale is right
#
# The comment above the constant gives the arithmetic. This recomputes it
# and compares, so the two cannot drift apart. A scale wrong by a factor
# is the defect most likely to survive review: every axis still moves and
# the signs are still right.
#
# 3.9 mg/LSB * 9.80665 m/s^2/g = 0.038245935 m/s^2, so 38245935 nano.

stated=$(sed -n 's/^#define BENCH_ADXL345_SCALE_NANO[[:space:]]*\([0-9]*\).*/\1/p' \
	"$CORE")
# %.0f and not %d: the product is 0.038245935 exactly in decimal, and
# %d truncates the binary representation of it to ...934. A test that
# rounds differently from the arithmetic it checks reports a defect that
# is its own.
computed=$(awk 'BEGIN { printf "%.0f", 0.0039 * 9.80665 * 1000000000 }')
check "the scale constant matches its own derivation" "$stated" "$computed"

# And a sanity check that the number means what the comment says: one g
# should come back as about 9.81 m/s^2 over 256 LSB in full resolution.
gravity=$(awk -v s="$stated" 'BEGIN { printf "%.2f", s / 1000000000 * 256 }')
check "256 LSB reads as one g" "$gravity" "9.79"

# ----------------------------------------------- the watermark is not 32
#
# A watermark equal to the FIFO depth leaves no room to service the
# interrupt before the next sample overruns, and an overrun is a short
# buffer rather than an error anyone sees.

depth=$(sed -n 's/^#define BENCH_ADXL345_FIFO_DEPTH[[:space:]]*\([0-9]*\).*/\1/p' \
	"$HDR")
mark=$(sed -n \
	's/^#define BENCH_ADXL345_WATERMARK_DEFAULT[[:space:]]*\([0-9]*\).*/\1/p' \
	"$HDR")
check "the FIFO depth is the part's 32" "$depth" "32"
verdict=$(awk -v d="$depth" -v m="$mark" \
	'BEGIN { print (m > 0 && m < d) ? "below" : "not below" }')
check "the watermark leaves headroom" "$verdict" "below"

# ------------------------------------------ the drain reads what is there
#
# Reading the watermark count instead of FIFO_STATUS leaves samples behind
# whenever the thread was late, on every busy system, until an overrun
# throws them away.
has "the drain reads FIFO_STATUS" "$CORE" 'BENCH_ADXL345_FIFO_STATUS'
has "and uses its entry count" "$CORE" 'FIFO_STATUS_ENTRIES'

# --------------------------------------------- the module reaches the image
#
# Decision 75: a driver that is configured is not a driver that is
# installed. Every .ko the Makefile builds must be named in the image.

for m in core i2c spi; do
	has "kernel-module-bench-adxl345-$m is installed" \
		"$IMAGE" "kernel-module-bench-adxl345-$m"
done

# The recipe must actually build all three, or the image names a package
# nothing produces.
for m in core i2c spi; do
	has "the Makefile builds bench-adxl345-$m" \
		"$SRC/files/Makefile" "obj-m += bench-adxl345-$m.o"
done

has "the recipe inherits module" "$RECIPE" '^inherit module'

# ------------------------------------------- the control is on the card too
#
# The comparison against mainline is the reason the fragment enables a
# second driver. If the image does not install it, the control exists in
# the kernel configuration and nowhere a board can reach.

has "the fragment enables mainline's I2C driver" "$FRAG" 'CONFIG_ADXL345_I2C=m'
has "the fragment enables mainline's SPI driver" "$FRAG" 'CONFIG_ADXL345_SPI=m'
has "mainline's I2C module is installed" "$IMAGE" 'kernel-module-adxl345-i2c'
has "mainline's SPI module is installed" "$IMAGE" 'kernel-module-adxl345-spi'

# ADXL345 itself has no prompt in drivers/iio/accel/Kconfig; it is
# selected by the two above. Asking for it as a request is a line kconfig
# accepts and ignores, so it has to carry the consequence marker that
# ./go ksym understands.
has "the promptless symbol is marked as a consequence" \
	"$FRAG" '^# consequence:'
consequence_line=$(grep -n '^# consequence:' "$FRAG" | cut -d: -f1)
next_line=$((consequence_line + 1))
check "and the marker sits directly above CONFIG_ADXL345" \
	"$(sed -n "${next_line}p" "$FRAG")" "CONFIG_ADXL345=m"

# The two IIO drivers depend on INPUT_ADXL34X=n in 6.12. Leaving the input
# driver on does not conflict at runtime, it makes both lines above
# unsatisfiable and kconfig drops them silently.
has "the input driver for the same part is off" \
	"$FRAG" '^# CONFIG_INPUT_ADXL34X is not set'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
