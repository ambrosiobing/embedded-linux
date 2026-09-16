#!/bin/sh
#
# kernel-config-test.sh - which .config the check reads, and what it says.
#
# When two kernels have been built, choosing between their .config files is
# the whole correctness of this check, and it was wrong. The search ended
# in "sort | tail -1" over the paths, which is a version sort done
# lexically, and that gets kernel versions backwards:
#
#   linux-raspberrypi/6.12.93+git/...   sorts first
#   linux-raspberrypi/6.6.63+git/...    sorts last, because "6" > "1"
#
# So after building a 6.12 real-time kernel it read the 6.6 one from the
# day before and reported CONFIG_PREEMPT_RT as missing. The obvious reading
# of that output is that the fragment failed. It had not. Nothing in the
# result said which kernel it came from except one line of path that nobody
# reads when the verdict below it is a wall of MISMATCH.
#
# So: rank by modification time, and prove it against two trees whose names
# sort the wrong way round.
#
#   sh tests/kernel-config-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/scripts/check-kernel-config.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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

FRAGS=$WORK/files
mkdir -p "$FRAGS"
export BENCH_FRAGMENT_DIR=$FRAGS
export BENCH_WORK=$WORK/bench

cat >"$FRAGS/bench.cfg" <<'EOF'
CONFIG_GPIO_CDEV=y
# CONFIG_GPIO_CDEV_V1 is not set
EOF

cat >"$FRAGS/rt.cfg" <<'EOF'
CONFIG_PREEMPT_RT=y
# CONFIG_PREEMPT is not set
EOF

# Two kernels, built on different days, named so that a lexical sort picks
# the older one.
TUNE=$WORK/bench/build/tmp/work/raspberrypi4_64-poky-linux/linux-raspberrypi
OLD=$TUNE/6.6.63+git/linux-raspberrypi4_64-standard-build
NEW=$TUNE/6.12.93+git/linux-raspberrypi4_64-standard-build
mkdir -p "$OLD" "$NEW"

cat >"$OLD/.config" <<'EOF'
CONFIG_GPIO_CDEV=y
CONFIG_PREEMPT=y
EOF

cat >"$NEW/.config" <<'EOF'
CONFIG_GPIO_CDEV=y
CONFIG_PREEMPT_RT=y
EOF

# The 6.12 tree is the newer build, whatever its name sorts as.
touch -d "2026-09-15 17:56" "$OLD/.config"
touch -d "2026-09-16 06:55" "$NEW/.config"

rc=0
out=$(sh "$SUT" -f rt 2>&1) || rc=$?
check "the newest .config is used, not the last one alphabetically" "$rc" "0"
contains "and it is the 6.12 tree" "$out" "6.12.93+git"
contains "PREEMPT_RT is found there" "$out" "ok        CONFIG_PREEMPT_RT=y"
contains "and the build time is reported" "$out" "2026-09-16 06:55"

# Reverse the ages. The same two trees, the same names, and now the 6.6
# build is the recent one, so that is what should be checked, and it should
# fail against the real-time fragment.
touch -d "2026-09-16 09:00" "$OLD/.config"
rc=0
out=$(sh "$SUT" -f rt 2>&1) || rc=$?
check "rebuilding the other kernel changes which one is checked" "$rc" "1"
contains "and it is the 6.6 tree now" "$out" "6.6.63+git"
contains "which does not carry PREEMPT_RT" "$out" "MISMATCH  CONFIG_PREEMPT_RT=y"
contains "and its CONFIG_PREEMPT is reported as unwanted" "$out" \
	"MISMATCH  CONFIG_PREEMPT is set"

# An explicit path still wins over any search.
cat >"$WORK/explicit.config" <<'EOF'
CONFIG_GPIO_CDEV=y
CONFIG_PREEMPT_RT=y
EOF
rc=0
out=$(sh "$SUT" -f rt "$WORK/explicit.config" 2>&1) || rc=$?
check "an explicit config is used as given" "$rc" "0"
contains "and named" "$out" "explicit.config"

rc=0
out=$(sh "$SUT" -f rt "$WORK/nosuch.config" 2>&1) || rc=$?
check "an unreadable explicit config is an error" "$rc" "1"

# No build at all has to be an error rather than a silent pass.
rm -rf "$WORK/bench"
rc=0
out=$(sh "$SUT" -f rt 2>&1) || rc=$?
check "no built kernel is an error" "$rc" "1"
contains "and says how to get one" "$out" "/proc/config.gz"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
