#!/bin/sh
#
# iio-rate-test.sh - the three acquisition paths, against a fake sysfs.
#
# This file is named in a comment at the top of iio-rate and did not exist
# until Thursday 1 October 2026. The program ran against hardware for the
# first time that morning and three defects surfaced inside twenty-five
# minutes, each of which this suite now asserts against:
#
#   09:36  it looked for buffer/hwfifo_watermark, which is one of two
#          conventions, and told a part with a 4.5 kB FIFO that it had none
#   09:44  it enabled the timestamp channel and no data channel, so the
#          kernel refused the buffer with EIO
#   10:01  it wrote the watermark before the buffer length, which the IIO
#          core rejects, and which worked once by accident on a dirty
#          system
#
# None of the three is subtle and none was findable before, because there
# was nothing to find them with.
#
#   sh tests/iio-rate-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-iio/files/iio-rate

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

contains() {
	case $2 in
	*"$3"*) ok "$1" ;;
	*)
		no "$1: '$3' not in output"
		printf '%s\n' "$2" | sed 's/^/         /'
		;;
	esac
}

# ------------------------------------------------------- the fake board
#
# A device directory the way the IIO core builds one, for a part with a
# hardware FIFO. Which watermark attribute exists is the variable: the
# whole point of the first group of tests is that there is more than one
# convention and the program may not assume either.

DEV=$WORK/sys/bus/iio/devices/iio:device0

build_device() {
	# ${WORK:?} rather than $WORK: if WORK were ever empty this line
	# would be "rm -rf /sys /dev /proc", and the form that refuses is
	# the one to write in a file that runs unattended in CI.
	rm -rf "${WORK:?}/sys" "${WORK:?}/dev" "${WORK:?}/proc" "${WORK:?}/results"
	mkdir -p "$DEV/buffer" "$DEV/buffer0" "$DEV/scan_elements" \
		"$WORK/dev" "$WORK/proc" "$WORK/results"

	echo lsm6dsv16x_accel >"$DEV/name"
	echo 0 >"$DEV/sampling_frequency"
	echo "7.500 15.000 30.000 60.000 120.000 240.000 480.000 960.000" \
		>"$DEV/sampling_frequency_available"
	echo 0 >"$DEV/buffer/enable"
	echo 2 >"$DEV/buffer/length"

	for c in in_accel_x in_accel_y in_accel_z in_timestamp; do
		echo 0 >"$DEV/scan_elements/${c}_en"
	done

	# The character device the buffer is read through. A regular file is
	# enough: dd reads it and stops, which is what a short capture looks
	# like from the program's side.
	printf 'rawrawraw' >"$WORK/dev/iio:device0"

	printf '%s\n' \
		' 185:   100   101   102   103  pinctrl-bcm2835  24 Edge  lsm6dsx' \
		>"$WORK/proc/interrupts"
}

# iio-decode is a separate program with its own suite. Here it only has to
# produce a header and some rows, so that the sample count and the
# timestamp column have something to work on.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/iio-decode" <<'STUB'
#!/bin/sh
cat <<'CSV'
in_accel_x,in_accel_y,in_accel_z,in_timestamp
1,2,3,1000000
1,2,3,2000000
1,2,3,3000000
CSV
STUB
chmod +x "$WORK/bin/iio-decode"
PATH=$WORK/bin:$PATH
export PATH

# A run that is expected to succeed is still invoked with "|| true", so
# that a regression reports a FAILED line naming what it wanted instead of
# aborting the suite under set -e. The exit status is checked explicitly
# wherever a refusal is the thing under test.
run_fifo() {
	BENCH_IIO_ROOT=$WORK \
	BENCH_IIO_RESULTS=$WORK/results \
	BENCH_IIO_DURATION=1 \
	BENCH_IIO_IRQ=lsm6 \
		sh "$SUT" fifo lsm6dsv16x_accel "$1" "$2" 2>&1
}

# ------------------------------------- the watermark, and its conventions
#
# Two interfaces exist for a hardware watermark. hwfifo_watermark is an
# optional one a handful of drivers expose directly; buffer/watermark is
# the standard one, backed by .set_watermark in iio_buffer_setup_ops,
# which the IIO core clamps to the hardware FIFO size. st_lsm6dsx uses the
# second. A program that tests only for the first calls a part with a
# 4.5 kB FIFO FIFO-less, which is what this one did.

build_device
echo 0 >"$DEV/buffer/hwfifo_watermark"
out=$(run_fifo 480 64 || true)
contains "the legacy hwfifo_watermark is used when present" \
	"$out" "buffer/hwfifo_watermark"
check "and it receives the watermark" "$(cat "$DEV/buffer/hwfifo_watermark")" "64"

build_device
echo 0 >"$DEV/buffer/watermark"
out=$(run_fifo 480 64 || true)
contains "the standard buffer/watermark is used when hwfifo is absent" \
	"$out" "buffer/watermark"
check "and it receives the watermark" "$(cat "$DEV/buffer/watermark")" "64"

build_device
echo 0 >"$DEV/buffer0/watermark"
out=$(run_fifo 480 64 || true)
contains "buffer0/watermark is the third place looked" \
	"$out" "buffer0/watermark"

# And a device with no watermark attribute at all is a device with no
# third path, which is a refusal rather than a crash. The message names
# every place it looked, because "no hardware FIFO" was the old message
# and it stated a fact about the silicon inferred from a filename.
build_device
status=0
out=$(run_fifo 480 64) || status=$?
check "no watermark attribute is a refusal" "$status" "1"
contains "and the refusal names where it looked" "$out" "buffer0/watermark"
case $out in
*"has no hardware FIFO"*)
	no "the refusal no longer claims the hardware lacks a FIFO" ;;
*)
	ok "the refusal no longer claims the hardware lacks a FIFO" ;;
esac

# ----------------------------------------- the rate attribute's two names
#
# A driver that declares its rate shared by type exposes
# in_accel_sampling_frequency and no device-level sampling_frequency.
# Mainline's ADXL345 driver and Project 5's both do, and on Friday
# 9 October 2026 this program wrote to the name that was not there and
# died with "Permission denied" on a file that did not exist.

build_device
echo 0 >"$DEV/buffer/watermark"
rm -f "$DEV/sampling_frequency"
echo 0 >"$DEV/in_accel_sampling_frequency"
out=$(run_fifo 480 64 || true)
contains "a per-type rate attribute is found when the device-level one is absent" 	"$out" "in_accel_sampling_frequency"
check "and it receives the rate" "$(cat "$DEV/in_accel_sampling_frequency")" "480"

build_device
echo 0 >"$DEV/buffer/watermark"
rm -f "$DEV/sampling_frequency"
status=0
out=$(run_fifo 480 64) || status=$?
check "no rate attribute of either name is a refusal" "$status" "1"
contains "and the refusal names both names" "$out" "Looked for sampling_frequency and in_"

# ------------------------------------------------ every channel, not one
#
# A buffer holding a timestamp and no data channel is not a buffer the
# IIO core will enable: it rejects the configuration with EIO, which
# arrives as "echo: I/O error" and names nothing. The program enabled
# in_timestamp alone until this was found on hardware.

build_device
echo 0 >"$DEV/buffer/watermark"
run_fifo 480 64 >/dev/null 2>&1 || true
all_on=yes
for f in "$DEV"/scan_elements/*_en; do
	[ "$(cat "$f")" = "1" ] || all_on=no
done
check "every scan element is enabled, not only the timestamp" "$all_on" "yes"
check "the data channels specifically" \
	"$(cat "$DEV/scan_elements/in_accel_x_en")" "1"

# A device whose scan_elements directory is empty has nothing to put in a
# buffer, which is a driver fault and is reported as one rather than
# producing an empty capture that looks like a measurement.
build_device
echo 0 >"$DEV/buffer/watermark"
rm -f "$DEV"/scan_elements/*_en
status=0
out=$(run_fifo 480 64) || status=$?
check "no scan elements is a refusal" "$status" "1"
contains "and it says so" "$out" "no scan elements"

# ------------------------------------------- the order of the two writes
#
# The IIO core requires watermark <= buffer length. A plain file cannot
# refuse a write the way the kernel does, so no fixture built from
# directories can catch this dynamically: on this fake board both writes
# succeed in either order. It is asserted structurally instead, which is
# exactly the check that would have caught it.
#
# The fault only appears on a freshly loaded driver, because a previous
# run leaves the length at 256 and a later watermark of 64 then fits. It
# was found by reloading a module to re-arm an interrupt.

len_line=$(grep -n 'buffer/length' "$SUT" | head -1 | cut -d: -f1)
# The single quotes are deliberate: this searches the source for the
# literal text >"$wm_attr", so the dollar must not expand.
# shellcheck disable=SC2016
wm_line=$(grep -n '>"\$wm_attr"' "$SUT" | head -1 | cut -d: -f1)
if [ "$len_line" -lt "$wm_line" ]; then
	ok "the buffer length is written before the watermark"
else
	no "the buffer length is written before the watermark"
	echo "         length at line $len_line, watermark at line $wm_line"
	echo "         the IIO core rejects a watermark above the length"
fi

# --------------------------------------------------- the ordinary guards

build_device
echo 0 >"$DEV/buffer/watermark"
status=0
out=$(BENCH_IIO_ROOT=$WORK BENCH_IIO_RESULTS=$WORK/results \
	BENCH_IIO_DURATION=1 sh "$SUT" fifo no_such_device 480 64 2>&1) || status=$?
check "an unknown device name is a refusal" "$status" "1"
contains "and the message says what to run instead" "$out" "iio-probe"

build_device
echo 0 >"$DEV/buffer/watermark"
rm -f "$WORK/dev/iio:device0"
status=0
out=$(run_fifo 480 64) || status=$?
check "a missing character device is a refusal" "$status" "1"
contains "and it names CONFIG_IIO_BUFFER" "$out" "CONFIG_IIO_BUFFER"

# A device is found by its name and never by its index, because which
# iio:deviceN a driver gets depends on probe order.
build_device
echo 0 >"$DEV/buffer/watermark"
out=$(run_fifo 480 64 || true)
contains "the device is identified by name" "$out" "lsm6dsv16x_accel"

# ------------------------------------------------------------ the result

build_device
echo 0 >"$DEV/buffer/watermark"
out=$(run_fifo 480 64 || true)
contains "the row records which path produced it" "$out" "hardware FIFO"
contains "and the timestamps say where they came from" \
	"$out" "driver-interpolated"
contains "and refuse to be called a latency measurement" \
	"$out" "NOT a latency measurement"
check "a row is written to the results file" \
	"$(grep -c '^20\|^19' "$WORK/results/rates.csv" 2>/dev/null || echo 0)" "1"

# ------------------------- criterion 4 is arithmetic, so it is checked here
#
# A hardware FIFO at rate R with watermark W interrupts R/W times a second.
# This program printed the measurement and left the division to the reader
# until Thursday 1 October 2026, on a bench where the two are 30 times
# apart: 7.5 per second expected at 480 Hz over a watermark of 64, and
# 225.60 measured.

out=$(run_fifo 480 64 || true)
contains "the expected interrupt rate is printed, not left to the reader" \
	"$out" "expected   7.50/s from 480 Hz over a watermark of 64"
contains "and the ratio beside it" "$out" "ratio      "

# The quiet fixture never advances /proc/interrupts, so the delta is zero
# and so is the ratio. That is the passing case and it must not exit
# non-zero, or every other assertion in this file would be measuring the
# wrong thing.
status=0
run_fifo 480 64 >/dev/null 2>&1 || status=$?
check "a ratio inside the limit exits zero" "$status" "0"

# Now a storm.
#
# The program reads /proc/interrupts, backgrounds dd, sleeps for the
# duration, then reads /proc/interrupts again. The only lever on a counter
# it reads itself is to change the file DURING that sleep, so a writer runs
# alongside and increments it the whole time.
#
# Written as a loop rather than one timed write on purpose. A single write
# has to land after the first read and before the second, which is a race
# against setup time; a monotonic series cannot miss, because whenever the
# first read happens the next write is larger. This suite has already
# shipped one flaky assertion and that is one more than it should have.
(
	i=200
	while [ "$i" -lt 2000 ]; do
		# Written to a temporary file and moved into place. ">"
		# truncates before it writes, iio-rate samples this file
		# twice, and a read landing inside that window sees an empty
		# file, comes back 0 and sends the delta negative. That is
		# what failed CI run 37146377402 on Saturday 3 October 2026
		# while this suite passed on the authoring laptop: the race
		# is timing-dependent and the two hosts schedule differently.
		# mv within one filesystem is atomic, so a reader sees either
		# the old complete file or the new one and never a gap.
		printf '%s' " 185:   $i   $i   $i   $i  pinctrl-bcm2835  24 Edge  lsm6dsx" \
			>"$WORK/proc/interrupts.tmp"
		mv "$WORK/proc/interrupts.tmp" "$WORK/proc/interrupts"
		i=$((i + 100))
		sleep 0.1
	done
) &
bumper=$!

status=0
out=$(run_fifo 480 64) || status=$?
kill "$bumper" 2>/dev/null || true
wait "$bumper" 2>/dev/null || true

contains "a storm is named as a failure rather than printed as a number" \
	"$out" "FAIL  the interrupt rate is more than twice"
contains "and it says what a healthy line reads" "$out" "0.00 and no"
check "and the run exits non-zero" "$status" "3"

# Restore the quiet stub, so anything added after this file is not run
# against a storming fixture by accident.
cat >"$WORK/bin/iio-decode" <<'STUB'
#!/bin/sh
cat <<'CSV'
in_accel_x,in_accel_y,in_accel_z,in_timestamp
1,2,3,1000000
1,2,3,2000000
1,2,3,3000000
CSV
STUB
chmod +x "$WORK/bin/iio-decode"
printf '%s' ' 185:   100   101   102   103  pinctrl-bcm2835  24 Edge  lsm6dsx' \
	>"$WORK/proc/interrupts"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
