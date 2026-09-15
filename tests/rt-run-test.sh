#!/bin/sh
#
# rt-run-test.sh - the measurement protocol, without a board.
#
# rt-run reaches the hardware through commands it looks up on PATH and
# through files under $RT_ROOT. Both are replaced here, so the whole
# protocol runs on a laptop in a second: the ordering of the three
# processes, the refusal to label a run with a claim the kernel does not
# support, the throttle gate, and the shape of the row that comes out.
#
# What is proven here: that the capture is armed before the toggler starts
# and cyclictest runs after it finishes, that stress-ng and the capture are
# confined to the housekeeping cores, that an isolation claim is checked
# against the kernel in both directions, that a throttling board refuses to
# start, that an overrun voids the run instead of producing a row, and that
# every column of the row comes from the instrument it says it does.
#
# What is not proven: that any of the stubs resembles the real thing. Only
# a board with a HAT on it can show that, and until one has been run the
# project README says so in the results section rather than implying
# numbers that do not exist.
#
#   sh tests/rt-run-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-rt/files/rt-run

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/results" "$WORK/scratch"
CALLS=$WORK/calls
export BENCH_TEST_DIR=$WORK

pass=0
fail=0

check() {
	if [ "$2" = "$3" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: wanted '$3', got '$2'"
		fail=$((fail + 1))
	fi
}

contains() {
	case $2 in
	*"$3"*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	*)
		echo "FAILED   $1: '$3' not in output"
		echo "$2" | sed 's/^/           /'
		fail=$((fail + 1))
		;;
	esac
}

absent() {
	case $2 in
	*"$3"*)
		echo "FAILED   $1: '$3' should not be in the output"
		fail=$((fail + 1))
		;;
	*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	esac
}

# ---------------------------------------------------------------- stubs

cat >"$WORK/bin/uname" <<'STUB'
#!/bin/sh
case ${1:-} in
-r) echo "6.12.93-v8-rt" ;;
-v) echo "#1 SMP PREEMPT_RT Mon Sep 15 00:00:00 UTC 2026" ;;
*) echo Linux ;;
esac
STUB

cat >"$WORK/bin/taskset" <<'STUB'
#!/bin/sh
echo "taskset $*" >>"$BENCH_TEST_DIR/calls"
shift 2
exec "$@"
STUB

cat >"$WORK/bin/stress-ng" <<'STUB'
#!/bin/sh
echo "stress-ng $*" >>"$BENCH_TEST_DIR/calls"
sleep 30
STUB

cat >"$WORK/bin/rt-capture" <<'STUB'
#!/bin/sh
echo "rt-capture start" >>"$BENCH_TEST_DIR/calls"
out=
while [ $# -gt 0 ]; do
	case $1 in
	--out) out=$2 ;;
	esac
	shift
done
if [ -f "$BENCH_TEST_DIR/overrun" ]; then
	echo "rt-capture: overrun, discarding the run" >&2
	exit 2
fi
: >"$out"
echo "rt-capture done" >>"$BENCH_TEST_DIR/calls"
STUB

cat >"$WORK/bin/rt-toggle" <<'STUB'
#!/bin/sh
echo "rt-toggle $*" >>"$BENCH_TEST_DIR/calls"
out=
while [ $# -gt 0 ]; do
	case $1 in
	-o) out=$2 ;;
	esac
	shift
done
cat >"$out" <<'HIST'
# rt-toggle
# chip /dev/gpiochip0 line 20 cpu 3 priority 80
# toggle_us 1000 edges 60000 overflow 0
# min_us 2.000 mean_us 4.500 max_us 29.000
# p99_us 9 p999_us 14
# bin_us count
4 59000
29 1
HIST
STUB

cat >"$WORK/bin/cyclictest" <<'STUB'
#!/bin/sh
echo "cyclictest $*" >>"$BENCH_TEST_DIR/calls"
echo "T: 0 ( 1234) P:80 I:1000 C:  60000 Min:      6 Act:    8 Avg:    9 Max:     31"
STUB

cat >"$WORK/bin/rt-analyze" <<'STUB'
#!/bin/sh
echo "rt-analyze $*" >>"$BENCH_TEST_DIR/calls"
echo "edges=30000 periods=29999 mean_us=2000.012 expected_us=2000.000 clock_offset_ppm=6.000 sd_us=1.200 p99_us=4.000 p999_us=9.000 max_abs_us=23.000 subsample_fraction=0.980 sample_us=10.000 histogram=hist.txt"
STUB

cat >"$WORK/bin/rt-irq-affinity" <<'STUB'
#!/bin/sh
echo "rt-irq-affinity $*" >>"$BENCH_TEST_DIR/calls"
exit 0
STUB

cat >"$WORK/bin/vcgencmd" <<'STUB'
#!/bin/sh
if [ -f "$BENCH_TEST_DIR/throttled" ]; then
	echo "throttled=0x50005"
else
	echo "throttled=0x0"
fi
STUB

# The real one would make every test wait two seconds for a stub that has
# already finished.
cat >"$WORK/bin/sleep" <<'STUB'
#!/bin/sh
echo "sleep $*" >>"$BENCH_TEST_DIR/calls"
STUB

chmod +x "$WORK"/bin/*
PATH=$WORK/bin:$PATH
export PATH

cat >"$WORK/rt.conf" <<CONF
RT_CPU=3
RT_HOUSEKEEPING=0-2
RT_PRIORITY=80
RT_TOGGLE_US=1000
RT_DURATION=5
RT_SCRATCH=$WORK/scratch
RT_RESULTS=$WORK/results
CONF
export RT_CONF=$WORK/rt.conf
export RT_ROOT=$WORK

# A /sys as the kernel would present it: realtime either 1 or 0, an
# isolated list that may be empty, and one cpufreq directory.
build_sys() {
	rm -rf "$WORK/sys"
	mkdir -p "$WORK/sys/devices/system/cpu/cpu0/cpufreq" \
		"$WORK/sys/kernel"
	echo "${1:-1}" >"$WORK/sys/kernel/realtime"
	echo "${2:-}" >"$WORK/sys/devices/system/cpu/isolated"
	echo ondemand \
		>"$WORK/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
}

reset() {
	: >"$CALLS"
	rm -f "$WORK/throttled" "$WORK/overrun"
	rm -rf "$WORK/results"
	mkdir -p "$WORK/results"
}

# Written as a function rather than as "[ -f x ] && echo yes || echo no",
# which shellcheck rejects as SC2015 and is right to: that idiom runs the
# third branch when the second one fails, not only when the test does.
csv_exists() {
	if [ -f "$WORK/results/results.csv" ]; then
		echo yes
	else
		echo no
	fi
}

# ------------------------------------------------------- the happy path

build_sys 1 "3"
reset
out=$(sh "$SUT" -i -a -g performance -L 2>&1)
calls=$(cat "$CALLS")

contains "the label describes the configuration" "$out" \
	"rt-iso-aff-performance-load"
contains "the kernel is reported as real-time" "$out" "realtime=yes"

# Ordering is the method. The capture has to be armed before the toggler
# starts, and cyclictest has to run after it stops: a scan armed late loses
# the first edges, and cyclictest running alongside the toggler means two
# SCHED_FIFO tasks at the same priority taking turns on one core, which
# makes both histograms describe the sharing rather than the kernel.
at() {
	grep -n "$1" "$CALLS" | head -1 | cut -d: -f1
}

before() {
	if [ "${1:-0}" -lt "${2:-0}" ]; then
		echo yes
	else
		echo no
	fi
}

capture_line=$(at "rt-capture start")
toggle_line=$(at "^rt-toggle ")
cyclic_line=$(at "^cyclictest ")
check "capture is armed before the toggler" \
	"$(before "$capture_line" "$toggle_line")" "yes"
check "cyclictest runs after the toggler" \
	"$(before "$toggle_line" "$cyclic_line")" "yes"

contains "stress-ng is confined to the housekeeping cores" "$calls" \
	"taskset -c 0-2 stress-ng"
contains "the capture is confined too" "$calls" "taskset -c 0-2 rt-capture"
contains "the toggler is pinned to the isolated core" "$calls" \
	"rt-toggle -d 5 -c 3"
contains "cyclictest uses the same core and period" "$calls" \
	"-i 1000 -a 3"
contains "affinity was applied and then verified" "$calls" \
	"rt-irq-affinity check 0-2"

row=$(tail -1 "$WORK/results/results.csv")
header=$(head -1 "$WORK/results/results.csv")
check "the header has 27 columns" \
	"$(echo "$header" | awk -F, '{print NF}')" "27"
check "so does the row" "$(echo "$row" | awk -F, '{print NF}')" "27"

field() {
	n=$(echo "$header" | tr ',' '\n' | grep -n "^$1$" | cut -d: -f1)
	echo "$row" | cut -d, -f"$n"
}

check "kernel column"        "$(field kernel)"        "6.12.93-v8-rt"
contains "the uname -v string is in the row" "$row" "SMP PREEMPT_RT"
check "measurement quality column" "$(field ext_subsample)" "0.980"
check "realtime column"      "$(field realtime)"      "yes"
check "isolated column"      "$(field isolated)"      "yes"
check "affinity column"      "$(field affinity)"      "yes"
check "governor column"      "$(field governor)"      "performance"
check "load column"          "$(field load)"          "yes"
check "external edge count"  "$(field ext_edges)"     "30000"
check "external mean"        "$(field ext_mean_us)"   "2000.012"
check "external p99.9"       "$(field ext_p999_us)"   "9.000"
check "external maximum"     "$(field ext_max_us)"    "23.000"
check "clock offset"         "$(field ext_ppm)"       "6.000"
check "internal mean"        "$(field int_mean_us)"   "4.500"
check "internal maximum"     "$(field int_max_us)"    "29.000"
check "internal p99.9"       "$(field int_p999_us)"   "14"
check "cyclictest minimum"   "$(field cyc_min_us)"    "6"
check "cyclictest average"   "$(field cyc_avg_us)"    "9"
check "cyclictest maximum"   "$(field cyc_max_us)"    "31"
check "throttle before"      "$(field throttled_before)" "0x0"
check "throttle after"       "$(field throttled_after)"  "0x0"

check "the governor was actually written" \
	"$(cat "$WORK/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")" \
	"performance"
check "the capture file was removed after analysis" \
	"$(ls "$WORK/scratch" | wc -l | tr -d ' ')" "0"

# --------------------------------------------------- the claims are checked

build_sys 1 ""
reset
rc=0
out=$(sh "$SUT" -i 2>&1) || rc=$?
check "-i on a kernel that isolated nothing is refused" "$rc" "1"
contains "and says how to fix it" "$out" "isolcpus=3 nohz_full=3 rcu_nocbs=3"
check "no row was written" \
	"$(csv_exists)" "no"

build_sys 1 "3"
reset
rc=0
out=$(sh "$SUT" 2>&1) || rc=$?
check "an isolated kernel without -i is refused too" "$rc" "1"
contains "and says why that matters" "$out" "would not be the configuration"

build_sys 1 "2-3"
reset
sh "$SUT" -i >/dev/null 2>&1
check "a range in the isolated list is accepted" \
	"$(csv_exists)" "yes"

build_sys 0 ""
reset
out=$(sh "$SUT" 2>&1)
contains "realtime=0 reads as a generic kernel" "$out" "realtime=no"
contains "and the label says so" "$out" "label      generic"

# ------------------------------------------------------------- the gates

build_sys 1 "3"
reset
: >"$WORK/throttled"
rc=0
out=$(sh "$SUT" -i 2>&1) || rc=$?
check "a throttling board refuses to start" "$rc" "1"
contains "and names the state" "$out" "throttled=0x50005"
absent "nothing was measured" "$(cat "$CALLS")" "rt-toggle"

reset
: >"$WORK/overrun"
rc=0
out=$(sh "$SUT" -i 2>&1) || rc=$?
check "an overrun voids the run" "$rc" "1"
contains "and says so" "$out" "the run is void"
check "and appends no row" \
	"$(csv_exists)" "no"

reset
out=$(sh "$SUT" -i -n 2>&1)
contains "a dry run prints the plan" "$out" "dry run, nothing started"
absent "and starts nothing" "$(cat "$CALLS")" "rt-toggle"
check "and writes no row" \
	"$(csv_exists)" "no"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
