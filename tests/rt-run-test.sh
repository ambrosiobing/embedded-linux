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
export BENCH_TEST_DIR="$WORK"

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

# uname -v is what decides realtime=yes, so the tests have to be able to
# change it. It used to be hardcoded to PREEMPT_RT, which meant the generic
# half of the experiment was never simulated at all.
cat >"$WORK/bin/uname" <<'STUB'
#!/bin/sh
case ${1:-} in
-r) echo "${BENCH_TEST_UNAME_R:-6.12.93-v8-rt}" ;;
-v) echo "${BENCH_TEST_UNAME_V:-#1 SMP PREEMPT_RT Mon Sep 15 00:00:00 UTC 2026}" ;;
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
# What cyclictest actually prints under "-h 400 -q", which is how rt-run
# invokes it: a histogram, then zero-padded summary lines. There is no T:
# line in this mode.
#
# This stub used to emit the T: line, which cyclictest prints only WITHOUT
# -h. So the fixture described an invocation rt-run does not make, the
# parser was written to match the fixture, and all three cyc_* columns were
# blank in every row on real hardware while these tests passed. Found by
# reading a results row on the board, not here.
cat <<'HIST'
# /dev/cpu_dma_latency set to 0us
# Histogram
000004 000010
000013 004413
000100 000001
# Total: 000010000
# Min Latencies: 00004
# Avg Latencies: 00013
# Max Latencies: 00100
# Histogram Overflows: 00000
HIST
STUB

cat >"$WORK/bin/rt-analyze" <<'STUB'
#!/bin/sh
echo "rt-analyze $*" >>"$BENCH_TEST_DIR/calls"
echo "edges=30000 periods=29999 mean_us=2000.012 expected_us=2000.000 clock_offset_ppm=6.000 sd_us=1.200 p99_us=4.000 p999_us=9.000 max_abs_us=23.000 subsample_fraction=0.980 sample_us=10.000 histogram=hist.txt"
STUB

cat >"$WORK/bin/rt-compare" <<'STUB'
#!/bin/sh
echo "rt-compare $*" >>"$BENCH_TEST_DIR/calls"
echo "sd ratio 1.415"
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
export RT_CONF="$WORK/rt.conf"
export RT_ROOT="$WORK"

# A /sys as the kernel would present it: realtime either 1 or 0, an
# isolated list that may be empty, and one cpufreq directory.
# $1 is what /sys/kernel/realtime should contain, or the word "absent" to
# leave the file out entirely.
#
# "absent" is the real hardware case and was not simulated until the board
# arrived. /sys/kernel/realtime came from the out-of-tree RT patches;
# PREEMPT_RT was merged into mainline for 6.12 without it, so on the kernel
# this project builds the file does not exist on either kernel. Every
# fixture here created it, so every test agreed with a version of the world
# that no board would ever present.
build_sys() {
	rm -rf "$WORK/sys"
	# poky writes /etc/timestamp during rootfs assembly, unique per build.
	# rt-run reads it so every row says which image produced it: two images
	# can carry the same kernel and differ in everything else, which
	# happened twice in one day on this project.
	mkdir -p "$WORK/etc"
	echo "20260916142705" >"$WORK/etc/timestamp"
	mkdir -p "$WORK/sys/devices/system/cpu/cpu0/cpufreq" \
		"$WORK/sys/kernel"
	if [ "${1:-1}" != absent ]; then
		echo "${1:-1}" >"$WORK/sys/kernel/realtime"
	fi
	echo "${2:-}" >"$WORK/sys/devices/system/cpu/isolated"

	# nohz_full defaults to the same set as isolcpus, because that is what
	# a correctly configured board looks like and because every existing
	# case in this file was written before rt-run checked it.
	#
	# Pass a third argument to diverge, or "absent" to omit the file, which
	# is what a kernel built without CONFIG_NO_HZ_FULL looks like. That was
	# the real board on 17 September: isolcpus took, the other two
	# parameters were rejected, and this suite would have passed anyway
	# because the only file it wrote was "isolated".
	# ${3-...} and NOT ${3:-...}. The colon form substitutes the default
	# when the argument is unset OR EMPTY, and "empty" is precisely the
	# case this fixture has to be able to express: a kernel that has the
	# nohz_full file and lists nothing in it, which is what isolcpus alone
	# produces. With the colon, build_sys 1 "3" "" wrote "3" into the file,
	# the guard in rt-run correctly declined to refuse a properly isolated
	# core, and the test called that a bug in rt-run. It was a bug here.
	_nohz=${3-${2:-}}
	if [ "$_nohz" != absent ]; then
		echo "$_nohz" >"$WORK/sys/devices/system/cpu/nohz_full"
	fi

	echo ondemand \
		>"$WORK/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"

	# min and max differ unless a case says otherwise, so the governor is
	# reported by name. Equal values are what force_turbo=1 produces, and
	# rt-run reports that as "fixed" however the policy names itself.
	echo "${4:-600000}" \
		>"$WORK/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq"
	echo "${5:-1500000}" \
		>"$WORK/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq"
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
check "the header has 28 columns" \
	"$(echo "$header" | awk -F, '{print NF}')" "28"
check "so does the row" "$(echo "$row" | awk -F, '{print NF}')" "28"

field() {
	n=$(echo "$header" | tr ',' '\n' | grep -n "^$1$" | cut -d: -f1)
	echo "$row" | cut -d, -f"$n"
}

# Which image produced this row. Two images can carry the same kernel and
# differ in everything else, so without this a reflash mid-matrix leaves
# rows that are indistinguishable except by wall-clock time.
#
# Asserted here rather than beside the column count above, because
# field() is defined below that point and calling it earlier returns an
# empty string with no error under set -e.
check "the row says which image produced it" \
	"$(field image_build)" "20260916142705"
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
# Parsed from "# Min/Avg/Max Latencies:", which is what -h mode prints,
# and unpadded: 00004 has to arrive as 4 rather than as a string.
check "cyclictest minimum"   "$(field cyc_min_us)"    "4"
check "cyclictest average"   "$(field cyc_avg_us)"    "13"
check "cyclictest maximum"   "$(field cyc_max_us)"    "100"
check "throttle before"      "$(field throttled_before)" "0x0"
check "throttle after"       "$(field throttled_after)"  "0x0"

check "the governor was actually written" \
	"$(cat "$WORK/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")" \
	"performance"
check "the capture file was removed after analysis" \
	"$(find "$WORK/scratch" -mindepth 1 | wc -l | tr -d ' ')" "0"

# The comparison runs at the end, on the label just recorded, and after the
# analysis rather than instead of it.
contains "the instruments are compared at the end of the run" "$calls" \
	"rt-compare --results $WORK/results rt-iso-aff-performance-load"
check "and after the analysis, not before" \
	"$(before "$(at '^rt-analyze ')" "$(at '^rt-compare ')")" "yes"
contains "and its verdict reaches the operator" "$out" "sd ratio"

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

# A generic kernel, described consistently.
#
# This used to be build_sys 0 with the uname stub left saying PREEMPT_RT,
# which is a machine whose version string and whose sysfs file contradict
# each other. No such kernel exists. It passed only because the old code
# read the sysfs file and ignored uname, so the fixture could be incoherent
# without anything noticing, and the generic half of the experiment was
# never actually simulated.
build_sys 0 ""
reset
out=$(BENCH_TEST_UNAME_V="#1 SMP PREEMPT_DYNAMIC Mon Sep 15 00:00:00 UTC 2026" \
	sh "$SUT" 2>&1)
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

# --------------------------------- the kernel says what kind it is, or no row
#
# This whole table is one comparison between two kernels differing in one
# symbol, so realtime= is the column that gives every row its meaning.
#
# It used to be read from /sys/kernel/realtime alone, with absent treated
# as "not real-time". That file came from the out-of-tree RT patches and
# did not survive the merge into mainline for 6.12. On the first boot of
# the real board it was not there, and the old code would have written
# realtime=no on a kernel whose own version string says PREEMPT_RT, called
# the run "generic", and named the files to match. Two arms of an
# experiment labelled identically is not a slower experiment.

echo "== the preemption model is read from uname, not from a vanished file"

reset
build_sys absent
out=$(sh "$SUT" -n 2>&1)
contains "absent sysfs file, PREEMPT_RT in uname -v, reads as realtime" \
	"$out" "realtime=yes"

reset
build_sys absent
out=$(BENCH_TEST_UNAME_V="#1 SMP PREEMPT_DYNAMIC Mon Sep 15 00:00:00 UTC 2026" \
	sh "$SUT" -n 2>&1)
contains "a generic kernel reads as generic" "$out" "realtime=no"

# The old interface, where it still exists, has to agree. A host with both
# that disagrees is one where something is not what it claims, and picking
# a winner is how a wrong row gets written with confidence.
reset
build_sys 0
rc=0
out=$(sh "$SUT" -n 2>&1) || rc=$?
check "uname and sysfs disagreeing is a refusal, not a guess" "$rc" "1"
contains "and it says both readings" "$out" "disagrees with itself"

reset
build_sys 1
out=$(sh "$SUT" -n 2>&1)
contains "agreeing sources still work" "$out" "realtime=yes"

# ------------------------------- isolation is three parameters, not one
#
# /sys/devices/system/cpu/isolated is populated by isolcpus alone, so every
# check that reads only that file passes on a kernel built without
# CONFIG_NO_HZ_FULL or CONFIG_RCU_NOCB_CPU. That is what happened: four rows
# were written isolated=yes for a core still taking its timer tick.

# ------------------------------- a governor the kernel does not have
#
# scaling_governor takes any string and the kernel rejects an unknown one
# with EINVAL, which a shell reports as "echo: write error: Invalid
# argument" naming the line number of an echo. That is what ended row 1 of
# the matrix on 17 September: the message named neither the governor, nor
# the file, nor the list of what was on offer.
#
# The cause is worth keeping in the test. rt-common.cfg sets
# CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE, which picks the DEFAULT and
# compiles nothing else in; the board turned out to offer conservative,
# userspace, powersave, performance and schedutil, with no ondemand, so
# four rows of the published matrix asked for something absent.

reset
build_sys 1
echo "conservative userspace powersave performance schedutil" 	>"$WORK/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
rc=0
out=$(sh "$SUT" -g ondemand 2>&1) || rc=$?
check "a governor the kernel lacks is refused" "$rc" "1"
contains "and the refusal names the one asked for" "$out" "no 'ondemand' governor"
contains "and lists what the kernel does offer" "$out" "schedutil"
contains "and says the default symbol is not the same question" "$out" 	"CONFIG_CPU_FREQ_DEFAULT_GOV"
contains "and warns that a rebuild must cover both arms" "$out" "BOTH arms"

reset
build_sys 1
echo "performance schedutil" 	>"$WORK/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"
rc=0
out=$(sh "$SUT" -n -g schedutil 2>&1) || rc=$?
check "a governor the kernel has is accepted" "$rc" "0"

reset
build_sys 1 "3" absent
rc=0
out=$(sh "$SUT" -i -n 2>&1) || rc=$?
check "-i refuses when the kernel has no nohz_full file at all" "$rc" "1"
contains "and names the config symbol that creates it" "$out" "CONFIG_NO_HZ_FULL"
contains "and says where to turn it on" "$out" "rt-common.cfg"

reset
build_sys 1 "3" ""
rc=0
out=$(sh "$SUT" -i -n 2>&1) || rc=$?
check "-i refuses when nohz_full is present but empty" "$rc" "1"
contains "and says the tick is still arriving" "$out" "still arriving on CPU"

reset
build_sys 1 "3" "0-2"
rc=0
out=$(sh "$SUT" -i -n 2>&1) || rc=$?
check "-i refuses when nohz_full covers the wrong cores" "$rc" "1"

reset
build_sys 1 "3" "3"
out=$(sh "$SUT" -i -n 2>&1)
contains "all three agreeing is accepted" "$out" "isolated   yes"

# ------------------------------------- the governor column and force_turbo
#
# With force_turbo=1 the firmware pins the clock underneath cpufreq. The
# sysfs interface remains and the policy still calls itself ondemand while
# having one frequency to choose from, so reading scaling_governor reports
# a policy that cannot act. Row 8 of the generic half recorded exactly that.
#
# These run the full path rather than -n, because governor_now is called
# after the dry-run exit and a dry run therefore never reaches it. The note
# printed by -n shows what was ASKED for; the column shows what was found.

reset
build_sys 1 "" "" 1500000 1500000
sh "$SUT" -d 1 >/dev/null 2>&1
row=$(tail -1 "$WORK/results/results.csv")
header=$(head -1 "$WORK/results/results.csv")
check "min equal to max is recorded as fixed" "$(field governor)" "fixed"

reset
build_sys 1 "" "" 600000 1500000
sh "$SUT" -d 1 >/dev/null 2>&1
row=$(tail -1 "$WORK/results/results.csv")
header=$(head -1 "$WORK/results/results.csv")
check "and a governor with room to move is recorded by name" \
	"$(field governor)" "ondemand"

# ------------------------------------------ the shipped header and this one
#
# projects/08-preempt-rt/results/results.csv is committed with a header and
# no rows, so that the schema is readable before any board has run. Nothing
# kept it in step with the header this script writes, and it drifted: when
# image_build was added here, the committed file stayed at 27 columns while
# the schema table beside it documented 28.
#
# That is harmless right up until somebody appends a board's row to the
# shipped file, or reads a column by position, and then it is a silent
# off-by-one across every column after the second.

shipped=$ROOT/projects/08-preempt-rt/results/results.csv
written=$(grep -o 'timestamp,label,[a-z_,0-9]*throttled_after' "$SUT" |
	head -n 1)
check "the committed results.csv header is the one rt-run writes" \
	"$(head -n 1 "$shipped")" "$written"

# Not by counting table rows. The schema table groups columns onto shared
# rows, the comparison table below it has the same shape, and a column name
# containing digits escapes the obvious pattern. Ask the question directly
# instead: is every column the board writes described somewhere.
schema=$ROOT/projects/08-preempt-rt/results/README.md
undocumented=
for column in $(printf '%s\n' "$written" | tr ',' ' '); do
	grep -q -- "\`$column\`" "$schema" || undocumented="$undocumented $column"
done
check "every column rt-run writes is documented" "$undocumented" ""
check "and the schema says how many there are" \
	"$(sed -n 's/^\([0-9]*\) columns, in this order.*/\1/p' "$schema")" \
	"$(printf '%s\n' "$written" | tr ',' '\n' | grep -c .)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
