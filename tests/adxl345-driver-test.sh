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
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
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
# The namespace is a bare identifier, not a quoted string. It was quoted
# until Friday 9 October 2026, which is the spelling kernels from 6.13
# take; 6.6 stringifies the argument itself, so the quotes would have
# become part of the name. This test kept expecting the quotes for most
# of that day and turned CI red from b20546d, because it was not rerun
# after the driver changed.
core_ns=$(sed -n 's/.*EXPORT_SYMBOL_NS_GPL([^,]*, *\([A-Z_][A-Z0-9_]*\)).*/\1/p' "$CORE")
check "the core exports into a namespace" "$core_ns" "BENCH_ADXL345"
has "the I2C file imports it" "$I2C" "MODULE_IMPORT_NS($core_ns)"
has "the SPI file imports it" "$SPI" "MODULE_IMPORT_NS($core_ns)"

# The FIFO path's timestamps and its interrupt line, both found wanting
# by the first capture on Friday 9 October 2026: every sample in a batch
# carried the interrupt time, and the line in /proc/interrupts carried
# the bus address, which no tool was looking for.
has "FIFO samples are timestamped back from the interrupt at the period" 	"$CORE" 'timestamp - (s64)(entries - 1 - i) \* st->period_ns'
has "the period is cached when the rate is written" "$CORE" 'st->period_ns = bench_adxl345_period_ns(i)'
has "the interrupt line is named after the IIO device" "$CORE" 'indio_dev->name, indio_dev'
has "buffer/watermark reaches the driver" "$CORE" '.hwfifo_set_watermark = bench_adxl345_set_watermark'


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

echo "--- the events, which were pushed by a handler nothing could reach"

# THE CHECK THAT WOULD HAVE CAUGHT IT. Until Friday 16 October 2026 the
# interrupt handler pushed three IIO events and no code anywhere set the
# matching bits in INT_ENABLE, so the part never ran the tap or free
# fall function at all: page 17 of the datasheet, Revision 0, says only
# data ready, watermark and overrun are always enabled, and that for
# every other bit INT_ENABLE enables the function itself. The acceptance
# table called criterion 6 "Configured" for two weeks.
#
# So: every event direction this file names must also be declared in an
# iio_event_spec. A fourth push added without a spec fires this.
# Same word-splitting loop as the register check above, and the same
# directive: the pattern admits only [A-Z_0-9], so every match is one
# whitespace-free token.
# shellcheck disable=SC2013
for d in $(grep -o 'IIO_EV_DIR_[A-Z_0-9]*' "$CORE" | sort -u); do
	if grep -q "\.dir = $d," "$CORE"; then
		ok "$d is declared in an event spec, not only pushed"
	else
		no "$d is pushed but no event spec declares it" \
			"user space gets no attribute, and the part is never told to detect it"
	fi
done

has "enabling an event writes INT_ENABLE" "$CORE" \
	'regmap_update_bits(st->regmap, BENCH_ADXL345_INT_ENABLE'
has "and the enable path is the only one that arms a gesture" "$CORE" \
	'static int bench_adxl345_write_event_config'

# Three registers whose reset value of zero disables the very function
# the events depend on, so probe has to write all three.
for r in DUR LATENT WINDOW THRESH_TAP THRESH_FF TIME_FF TAP_AXES; do
	has "probe writes $r" "$CORE" "{ BENCH_ADXL345_$r,"
done

for r in DUR LATENT WINDOW; do
	v=$(sed -n "s/^#define BENCH_ADXL345_${r}_DEFAULT[[:space:]]*\(0x[0-9a-fA-F]*\).*/\1/p" "$HDR")
	case $v in
	"" | 0x0 | 0x00)
		no "the $r default is not zero" \
			"zero disables tap or double tap, datasheet page 15" ;;
	*)
		ok "the $r default is not zero, so tap detection can run" ;;
	esac
done

# The two values the datasheet does recommend a range for, checked
# against the range rather than against whatever was typed. Page 15 for
# the threshold, page 16 for the time, both Revision 0.
ff=$(sed -n 's/^#define BENCH_ADXL345_THRESH_FF_DEFAULT[[:space:]]*0x\([0-9a-fA-F]*\).*/\1/p' "$HDR")
ffd=$(printf '%d' "0x$ff" 2>/dev/null || echo -1)
if [ "$ffd" -ge 5 ] && [ "$ffd" -le 9 ]; then
	ok "the free fall threshold is inside the recommended 0x05 to 0x09"
else
	no "the free fall threshold is inside the recommended 0x05 to 0x09" "got 0x$ff"
fi

tf=$(sed -n 's/^#define BENCH_ADXL345_TIME_FF_DEFAULT[[:space:]]*0x\([0-9a-fA-F]*\).*/\1/p' "$HDR")
tfd=$(printf '%d' "0x$tf" 2>/dev/null || echo -1)
if [ "$tfd" -ge 20 ] && [ "$tfd" -le 70 ]; then
	ok "the free fall time is inside the recommended 0x14 to 0x46"
else
	no "the free fall time is inside the recommended 0x14 to 0x46" "got 0x$tf"
fi

# Nothing is armed at probe: the operator enables an event or it does
# not fire. setup_events writes parameters only.
if sed -n '/^static int bench_adxl345_setup_events/,/^}/p' "$CORE" |
	grep -q INT_ENABLE; then
	no "probe arms no event behind the operator" \
		"setup_events touches INT_ENABLE"
else
	ok "probe arms no event behind the operator"
fi

# THE EVIDENCE A CRITERION NAMES HAS TO BE IN THE IMAGE. Criterion 6
# named iio_event_monitor, which lives in the kernel tree's tools/iio
# and is packaged by nothing in this layer, so no bench image has ever
# carried it: the criterion asked for output from a program that was
# shipped to no board. That is decision 75's shape again, one layer up.
# The backtick is built rather than typed: a literal one inside single
# quotes is legal shell and confuses enough tools to be worth avoiding.
BT=$(printf '`')
crit6=$(grep -o "${BT}[a-z0-9-]*${BT} output while the board is tapped" \
	"$ROOT/projects/05-iio-adxl345/README.md" | tr -d "$BT" | cut -d" " -f1)
if [ -n "$crit6" ]; then
	ok "criterion 6 names a tool: $crit6"
else
	no "criterion 6 names a tool"
fi
if grep -q "bindir}/$crit6" "$ROOT/meta-bench/recipes-bench/bench-iio/bench-iio_0.1.bb"; then
	ok "and bench-iio installs it"
else
	no "and bench-iio installs it, so the evidence can be produced"
fi
has "and project 5 image installs bench-iio" "$IMAGE" "^    bench-iio "

echo "--- the registers probe must write whole, not merge"

# THE PART KEEPS ITS REGISTERS ACROSS A REBOOT. The ADXL345 has no reset
# pin and no software reset, so only removing power returns it to the
# datasheet defaults, and every probe inherits whatever the last session
# left. Read off the bench on Friday 16 October 2026: DATA_FORMAT 0xaf
# with SELF_TEST, INT_INVERT and Justify set, the three offset registers
# holding up to 1.9 g of trim, BW_RATE at 12.5 Hz while the driver
# assumed 100, INT_ENABLE with data ready, activity and inactivity on.
# Every one of those produces readings that look like data.
#
# So the configuration registers are written, never merged. A
# regmap_update_bits on any of them is the defect coming back.
# ONLY THE PROBE IS READ HERE, and the exclusion is the point rather
# than a convenience: bench_adxl345_powerdown clears the measure bit
# with an update_bits on remove, which is correct, and a rule written
# against the whole file flags it. The first run of this check did
# exactly that.
PROBE=$WORKDIR/probe.c
sed -n '/^int bench_adxl345_core_probe/,$p' "$CORE" >"$PROBE"

for r in DATA_FORMAT POWER_CTL BW_RATE INT_ENABLE; do
	if grep -q "regmap_update_bits(regmap, BENCH_ADXL345_$r" "$PROBE"; then
		no "probe writes $r whole rather than merging bits" 			"an update_bits leaves whatever the last session left"
	else
		ok "probe writes $r whole rather than merging bits"
	fi
	has "and probe writes $r at all" "$PROBE" "regmap_write(regmap, BENCH_ADXL345_$r"
done

for r in OFSX OFSY OFSZ; do
	has "probe clears $r" "$PROBE" "regmap_write(regmap, BENCH_ADXL345_$r, 0)"
done

# The cached sample period and the rate register have to come from one
# constant, or the FIFO timestamps are spread at a rate the part is not
# running at.
has "the probe writes the rate it caches" "$PROBE" 	'regmap_write(regmap, BENCH_ADXL345_BW_RATE,'
has "and the cached period comes from the same constant" "$PROBE" 	'bench_adxl345_period_ns(BENCH_ADXL345_RATE_DEFAULT -'

echo "--- the triggered path, which the design table claimed for a week"

# THE MIDDLE ROW OF docs/DESIGN.md's THREE PATHS, which was a plan
# written in the present tense until Saturday 17 October 2026. Nothing
# found it: it was noticed because Project 10's iio-rate had no trigger
# directory to attach to.
#
# What follows is one assertion per way this path fails without saying
# anything.

# ONE. A pollfunc whose hard-irq half is NULL never has pf->timestamp
# written, and every sample then carries whatever was in that field.
# The two halves are asserted together because either one alone is the
# defect rather than half of it.
has "the pollfunc stores the trigger time in its hard irq half" \
	"$CORE" 'iio_alloc_pollfunc(iio_pollfunc_store_time'
has "and the handler pushes that time rather than reading the clock" \
	"$CORE" 'pf->timestamp'

# TWO. A trigger counts its consumers and fires again only once every
# one of them has reported done. An early return anywhere in the
# handler therefore stops the path for good after a single failed bus
# read, and the symptom is a trigger that has died rather than a read
# that failed. So the handler is required to have exactly one exit.
HANDLER=$WORKDIR/handler.c
sed -n '/^static irqreturn_t bench_adxl345_trigger_handler/,/^}/p' \
	"$CORE" >"$HANDLER"
# Comment lines are dropped before counting, for two reasons: the
# handler's own comment explains why it has one exit and uses the word,
# and the defect this is looking for is an indented "if (ret) return",
# which an anchored pattern would miss. The first spelling here counted
# only returns at the start of a line and the mutation that adds the
# early return went straight past it.
#
# The trailing space is load bearing: without it the pattern also
# matches the irqreturn_t in the function's own signature, and the
# count is two before anything is wrong.
exits=$(grep -v '^[[:space:]]*[*/]' "$HANDLER" | grep -c 'return ')
check "the trigger handler has one exit, so none can skip notify_done" \
	"$exits" "1"
has "and it does report done to the trigger" "$HANDLER" \
	'iio_trigger_notify_done(indio_dev->trig)'

# THREE. The two buffer modes, which are not alternatives: the core
# picks the triggered one when a trigger is attached and this driver's
# FIFO path otherwise. With no interrupt the FIFO path cannot run at
# all, and a reader that enabled it would wait on a buffer nothing can
# push into with no error anywhere.
has "the triggered mode is declared" "$CORE" \
	'indio_dev->modes |= INDIO_BUFFER_TRIGGERED'
has "and the fifo mode is withdrawn when nothing can interrupt" "$CORE" \
	'indio_dev->modes &= ~INDIO_BUFFER_SOFTWARE'

# FOUR. The buffer has to be attached whether or not INT1 is wired,
# because the triggered path needs the kfifo and does not need the
# part's interrupt. It sat inside the interrupt branch until the
# triggered path existed, which is why this is a line-order assertion
# rather than a grep: moving it back inside would still match.
buf=$(grep -n 'devm_iio_kfifo_buffer_setup(dev' "$CORE" | cut -d: -f1)
gate=$(grep -n 'if (st->irq > 0) {' "$CORE" | cut -d: -f1)
if [ -n "$buf" ] && [ -n "$gate" ] && [ "$buf" -lt "$gate" ]; then
	ok "the buffer is attached before the interrupt is asked for"
else
	no "the buffer is attached inside the interrupt branch, leaving the triggered path nowhere to push"
fi

# FIVE. Both halves of the buffer setup ops have to know which path
# they are for. A postenable that programs the part's FIFO while a
# trigger is attached fills one buffer from two sources, and the
# capture then carries twice the samples either path produced, in an
# order that looks like jitter.
trigs=$(grep -c 'if (indio_dev->trig)' "$CORE")
check "both buffer halves ask which path the enable is for" "$trigs" "2"

# SIX. The pollfunc is allocated by hand, so it is freed by hand.
has "the pollfunc is released" "$CORE" 'iio_dealloc_pollfunc'
has "and by a devm action, so no remove hook has to exist" "$CORE" \
	'devm_add_action_or_reset(dev, bench_adxl345_free_pollfunc'

# SEVEN. The helper every in-tree driver uses for this,
# iio_triggered_buffer_setup, lives behind CONFIG_IIO_TRIGGERED_BUFFER,
# which has no prompt in drivers/iio/Kconfig and is reached only by an
# in-tree select. An out-of-tree module can select nothing, a fragment
# line asking for the symbol directly is dropped by kconfig without a
# word, and the module then fails at modprobe with an unknown symbol,
# which reads like a corrupt .ko rather than like a missing option.
#
# Both halves are asserted, because either one on its own is the trap:
# the driver must not call the helper, and the fragment must not ask
# for the symbol. What the path does need is CONFIG_IIO_TRIGGER, which
# bench.cfg sets for every image here.
# The pattern carries the open bracket, so it matches a call and not
# the driver's own comment explaining why it makes none. Without it
# this assertion failed on the sentence that documents it, which is the
# third rule in this repository to have matched its own prose.
lacks "the driver does not call the helper behind the promptless symbol" \
	"$CORE" 'iio_triggered_buffer_setup('
lacks "and the fragment does not ask kconfig for that symbol" \
	"$FRAG" 'CONFIG_IIO_TRIGGERED_BUFFER'
has "the symbol the path does need is on for every image" \
	"$ROOT/meta-bench/recipes-kernel/linux/files/bench.cfg" \
	'^CONFIG_IIO_TRIGGER=y'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
