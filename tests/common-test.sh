#!/bin/sh
#
# common-test.sh - the helpers in scripts/common.sh that everything else
# builds on.
#
# Only newest_path so far, and it is here rather than inside one script's
# test because four scripts now depend on it and one of them erases a card.
#
# The bug it replaced was written four separate times. Every script that
# had to choose between build outputs ended in "sort | tail -1", which
# orders paths as text:
#
#   6.12.93 before 6.6.63                     "1" < "6"
#   raspberrypi3-64 before raspberrypi4-64    "3" < "4"
#
# So on a build host that has built for two machines, the abandoned one
# wins. In check-kernel-symbols.sh that meant reading a kernel nobody was
# building and reporting the right answer anyway, because both trees were
# the same version. In flash.sh it means writing an image for the wrong
# board to a card, which does not warn and does not boot.
#
#   sh tests/common-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0

check() {
	if [ "$2" = "$3" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: got '$2', wanted '$3'"
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
		fail=$((fail + 1))
		;;
	esac
}

# common.sh wants these; it is sourced rather than run, so nothing builds.
BENCH_WORK=$WORK/bench
export BENCH_WORK
mkdir -p "$BENCH_WORK"

# shellcheck source=/dev/null
. "$ROOT/scripts/common.sh"

# ------------------------------------------- the newest wins, not the last

# Deliberately in the order a lexical sort would produce, with the mtimes
# the other way round, so a test that passes cannot be passing by accident
# of the input order.
feed() {
	printf '1600000000 /deploy/images/raspberrypi4-64/bench.wic.bz2\n'
	printf '1700000000 /deploy/images/raspberrypi3-64/bench.wic.bz2\n'
}

out=$(feed | newest_path image 2>/dev/null)
check "the newest path is the one printed" \
	"$out" "/deploy/images/raspberrypi3-64/bench.wic.bz2"

err=$(feed | newest_path image 2>&1 >/dev/null)
contains "the path not chosen is named" "$err" "raspberrypi4-64/bench.wic.bz2"
contains "and it says what it did" "$err" "newest wins"
contains "and how many there were" "$err" "1 older image(s)"

# The label is the caller's word for what it is choosing between, because
# "older tree" and "older image" send the reader to different places.
err=$(feed | newest_path "kernel tree" 2>&1 >/dev/null)
contains "the label is the caller's" "$err" "older kernel tree(s)"

# ----------------------------------------- stdout carries only the answer
#
# Every caller does config=$(... | newest_path ...), so a single stray line
# on stdout becomes part of a path and the script goes looking for a file
# whose name ends in a sentence about warnings.
out=$(feed | newest_path image 2>/dev/null | wc -l | tr -d ' ')
check "exactly one line on stdout, whatever is on stderr" "$out" "1"

# --------------------------------------------------- one candidate, quiet

one=$(printf '1700000000 /deploy/images/raspberrypi3-64/bench.wic.bz2\n')

out=$(printf '%s\n' "$one" | newest_path image 2>/dev/null)
check "a single candidate is returned" \
	"$out" "/deploy/images/raspberrypi3-64/bench.wic.bz2"

err=$(printf '%s\n' "$one" | newest_path image 2>&1 >/dev/null)
check "and nothing is said about it" "$err" ""

# ------------------------------------------------------- nothing to pick
#
# An empty result is the caller's to report: flash.sh says "run build.sh
# first" and check-kernel-symbols.sh says "run kernel_configme", and
# neither sentence belongs in a helper.
out=$(printf '' | newest_path image 2>/dev/null) || true
check "no candidates gives empty output" "$out" ""

err=$(printf '' | newest_path image 2>&1 >/dev/null) || true
check "and no complaint either" "$err" ""

# ------------------------------------------------- paths containing spaces
#
# cut -d' ' -f2- keeps everything after the first field, so a path with a
# space in it survives. Build directories should not have spaces in them
# and one day one will.
out=$(printf '1700000000 /deploy/my images/bench.wic.bz2\n' |
	newest_path image 2>/dev/null)
check "a path with a space is not truncated" "$out" "/deploy/my images/bench.wic.bz2"

# ------------------------------------------- both names for one config
#
# ./go rt builds bench-rt, so "./go archive rt" is the thing a hand types
# after months of the former. It used to answer "no such configuration:
# kas/rt.yml", which is true and names a file nobody had in mind.
#
# build.sh resolves through here too, so this is not only about ergonomics
# any more: a regression would break every build verb.

out=$(resolve_kas_config bench-rt)
check "the full name resolves" "$(basename "$out")" "bench-rt.yml"

out=$(resolve_kas_config rt)
check "the short name resolves to the same file" \
	"$(basename "$out")" "bench-rt.yml"

out=$(resolve_kas_config rt-generic)
check "and a short name with its own hyphen is not confused" \
	"$(basename "$out")" "bench-rt-generic.yml"

# The full name wins when both could match, because a file that exists is
# never a guess.
out=$(resolve_kas_config bench-rpi4)
check "an exact match is preferred" "$(basename "$out")" "bench-rpi4.yml"

rc=0
out=$( (resolve_kas_config nonesuch) 2>&1 ) || rc=$?
check "an unknown name fails" "$rc" "1"
contains "and names both spellings it tried" "$out" "no kas/bench-nonesuch.yml"
contains "and lists what does exist" "$out" "bench-router"
contains "and says either spelling works" "$out" "Either spelling works"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
