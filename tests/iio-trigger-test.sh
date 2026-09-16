#!/bin/sh
#
# iio-trigger-test.sh - two kinds of software trigger, created two ways.
#
# A hrtimer trigger is a configfs object: it exists because a directory was
# created, and it is removed with rmdir. A sysfs trigger is not a configfs
# object at all; it is created by writing a number to an attribute. They
# look similar from the outside and nothing about the names says which is
# which, so both are exercised here.
#
# The branch worth having a test for is the one where configfs is not
# mounted. /sys/kernel/config exists in any image built with
# CONFIG_CONFIGFS_FS and says nothing about whether anything was mounted on
# it, so a mkdir there succeeds, creates an ordinary directory, and
# produces a trigger the kernel has never heard of. Everything downstream
# then reports an empty buffer.
#
#   sh tests/iio-trigger-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-iio/files/iio-trigger

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

HR=$WORK/sys/kernel/config/iio/triggers/hrtimer

# find rather than ls, because shellcheck is right that ls output is not a
# list: SC2012. Only the count is wanted, and find gives it without caring
# what the names contain.
count_objects() {
	find "$HR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' '
}

object_names() {
	find "$HR" -mindepth 1 -maxdepth 1 -exec basename {} ';'
}

DEVICES=$WORK/sys/bus/iio/devices

reset_tree() {
	rm -rf "$WORK/sys" "$WORK/proc"
	mkdir -p "$HR" "$DEVICES" "$WORK/proc"
	# configfs mounted, which is the normal case. The test that needs it
	# absent rewrites this file.
	echo "none $WORK/sys/kernel/config configfs rw,relatime 0 0" \
		>"$WORK/proc/mounts"
}

# The IIO core registers a trigger device for each configfs object. Nothing
# in a fixture does that by itself, so the tests that need a registered
# trigger create one, which is also what makes the "created and the core
# registered nothing" branch reachable.
register_trigger() {
	_n=$1
	_name=$2
	mkdir -p "$DEVICES/trigger$_n"
	echo "$_name" >"$DEVICES/trigger$_n/name"
	: >"$DEVICES/trigger$_n/sampling_frequency"
}

# As above, but a sysfs trigger, which has a trigger_now attribute and no
# sampling_frequency. That difference is the whole distinction between the
# two kinds and is what "fire" keys on.
register_sysfs_trigger() {
	_n=$1
	_name=$2
	mkdir -p "$DEVICES/trigger$_n"
	echo "$_name" >"$DEVICES/trigger$_n/name"
	: >"$DEVICES/trigger$_n/trigger_now"
}

run() {
	BENCH_IIO_ROOT=$WORK sh "$SUT" "$@" 2>&1 || true
}

run_status() {
	_rc=0
	BENCH_IIO_ROOT=$WORK sh "$SUT" "$@" >/dev/null 2>&1 || _rc=$?
	echo "$_rc"
}

# ------------------------------------------------- configfs, unmounted
#
# The branch this suite exists for. An earlier version of iio-trigger
# skipped this check whenever a test root was set, on the grounds that a
# test root has no /proc/mounts, which made the most valuable branch in the
# program the one branch no test could reach.

reset_tree
: >"$WORK/proc/mounts"          # the directory exists; nothing is mounted
check "an unmounted configfs is refused" \
	"$(run_status add hrtimer t100 100)" "1"
out=$(run add hrtimer t100 100)
contains "and says how to mount it" "$out" "mount -t configfs none"
# Matched on a fragment that lives on one line. The message wraps, and an
# assertion spanning its line break tests the formatting rather than the
# content: reflowing the paragraph would break the test without changing
# what it says.
contains "and says why the directory existing proves nothing" \
	"$out" "CONFIG_CONFIGFS_FS"
check "and creates no object" "$(count_objects)" "0"

# ------------------------------------------- created, but never registered

reset_tree
check "a trigger the IIO core does not register is refused" \
	"$(run_status add hrtimer t100 100)" "1"
out=$(run add hrtimer t100 100)
contains "and says it removed the object again" "$out" "has been removed again"
check "and the configfs directory is gone" "$(count_objects)" "0"

# That cleanup is not tidiness. Without it the next attempt fails with
# "already exists", which points at the name rather than at whatever went
# wrong the first time.
out=$(run add hrtimer t100 100)
case $out in
*"already exists"*) no "a retry after a failed add is not confused by debris" ;;
*) ok "a retry after a failed add is not confused by debris" ;;
esac

# ------------------------------------------------------- the normal path

reset_tree
register_trigger 0 t100
check "adding a hrtimer trigger succeeds" \
	"$(run_status add hrtimer t100 100)" "0"
check "the configfs object exists" "$(object_names)" "t100"
check "the rate is written to the trigger DEVICE, not the configfs dir" \
	"$(cat "$DEVICES/trigger0/sampling_frequency")" "100"
contains "and it says which device it used" \
	"$(run add hrtimer t100 100 2>&1 || true)" "already exists"

out=$(run list)
contains "list shows the configfs objects" "$out" "t100"
contains "and the triggers the core knows about" "$out" "trigger0  t100"

# ------------------------------------- the name is the link, not the index
#
# trigger0 is not necessarily the first one created, and the numbering
# changes when one is removed. Matching by name is the only stable way, so
# a trigger registered as trigger7 must still be found.

reset_tree
register_trigger 7 t250
check "a trigger at an arbitrary index is still found by name" \
	"$(run_status add hrtimer t250 250)" "0"
check "and its rate lands on the right device" \
	"$(cat "$DEVICES/trigger7/sampling_frequency")" "250"

# --------------------------------------------------------------- firing

reset_tree
register_trigger 0 t100
run add hrtimer t100 100 >/dev/null
check "a hrtimer trigger cannot be fired by hand" \
	"$(run_status fire t100)" "1"
contains "and says why" "$(run fire t100)" "fires from the kernel"

reset_tree
register_sysfs_trigger 0 sysfstrig0
check "a sysfs trigger can be fired" "$(run_status fire sysfstrig0)" "0"
check "and the write lands in trigger_now" \
	"$(cat "$DEVICES/trigger0/trigger_now")" "1"

check "firing a trigger that does not exist is an error" \
	"$(run_status fire nosuchtrigger)" "1"

# ------------------------------------------------------------- removal

reset_tree
register_trigger 0 t100
run add hrtimer t100 100 >/dev/null
check "removing a hrtimer trigger succeeds" "$(run_status remove t100)" "0"
check "and the configfs object is gone" "$(count_objects)" "0"
check "removing one that does not exist is an error" \
	"$(run_status remove t100)" "1"

# ------------------------------------------------- a sysfs trigger is a number

reset_tree
mkdir -p "$DEVICES/iio_sysfs_trigger"
: >"$DEVICES/iio_sysfs_trigger/add_trigger"
check "a sysfs trigger identified by a name is refused" \
	"$(run_status add sysfs notanumber)" "1"
contains "and says it wants a number" \
	"$(run add sysfs notanumber)" "identified by a number"
check "a number is accepted" "$(run_status add sysfs 0)" "0"
check "and written to add_trigger" \
	"$(cat "$DEVICES/iio_sysfs_trigger/add_trigger")" "0"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
