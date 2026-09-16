#!/bin/sh
#
# kas-run-test.sh - the build directory is not left to chance.
#
# kas reads KAS_WORK_DIR and KAS_BUILD_DIR from the environment and falls
# back to paths relative to the current directory when they are absent. A
# bare "kas shell kas/bench-rt.yml -c ..." run from a checkout therefore
# builds in <checkout>/build, with its own downloads and sstate-cache, and
# succeeds. It cost 7.7 GB of a nearly full disk and an hour of confusion:
# the tree it produced was correct and in the wrong place, so the next
# command looked in the right place and read the previous project's kernel.
#
# Everything that invokes kas now goes through scripts/kas.sh, and what
# this checks is that it exports the two variables, refuses a command with
# no configuration, and passes BitBake's arguments through unchanged.
#
#   sh tests/kas-run-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/scripts/kas.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/bench"
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

# A kas that records how it was called and what it inherited, which is the
# whole question.
cat >"$WORK/bin/kas" <<'STUB'
#!/bin/sh
{
	echo "argv: $*"
	echo "KAS_WORK_DIR=${KAS_WORK_DIR:-unset}"
	echo "KAS_BUILD_DIR=${KAS_BUILD_DIR:-unset}"
} >>"$BENCH_TEST_DIR/calls"
STUB
chmod +x "$WORK/bin/kas"
PATH=$WORK/bin:$PATH
export PATH

export BENCH_WORK="$WORK/bench"

run() {
	: >"$CALLS"
	rc=0
	out=$(sh "$SUT" "$@" 2>&1) || rc=$?
	printf '%s' "$out"
}

# ------------------------------------------------- the default shell

out=$(run shell)
calls=$(cat "$CALLS")
contains "a bare shell uses the shared configuration" "$calls" \
	"argv: shell $ROOT/kas/bench-rpi4.yml"
contains "and kas is told where to work" "$calls" \
	"KAS_WORK_DIR=$WORK/bench"
contains "and where to build" "$calls" \
	"KAS_BUILD_DIR=$WORK/bench/build"

# ------------------------------------------ a shell on another config

out=$(run shell bench-rt)
calls=$(cat "$CALLS")
contains "a named configuration is used" "$calls" \
	"argv: shell $ROOT/kas/bench-rt.yml"
contains "in the same build directory" "$calls" \
	"KAS_BUILD_DIR=$WORK/bench/build"

# --------------------------------------------------- one bitbake command

out=$(run bitbake bench-rt -c kernel_configme virtual/kernel)
calls=$(cat "$CALLS")
contains "the configuration is chosen" "$calls" "kas/bench-rt.yml"
contains "and BitBake's arguments are passed through" "$calls" \
	"-c bitbake -c kernel_configme virtual/kernel"
contains "still in the shared build directory" "$calls" \
	"KAS_BUILD_DIR=$WORK/bench/build"

# ------------------------------------------------------------- refusals

rc=0
out=$(sh "$SUT" bitbake -c unpack virtual/kernel 2>&1) || rc=$?
check "a bitbake with no configuration is refused" "$rc" "1"
contains "and an example is given" "$out" "./go bitbake bench-rt"

rc=0
out=$(sh "$SUT" bitbake bench-nosuch -c unpack 2>&1) || rc=$?
check "a configuration that does not exist is refused" "$rc" "1"
contains "and named" "$out" "bench-nosuch"

rc=0
out=$(sh "$SUT" bitbake bench-rt 2>&1) || rc=$?
check "a bitbake with nothing to run is refused" "$rc" "1"

rc=0
out=$(sh "$SUT" 2>&1) || rc=$?
check "no action at all is a usage error" "$rc" "2"

# --------------------------------------------- the stray tree is reported

# The tree this whole script exists to prevent. It is a warning rather than
# an error: the directory is harmless once noticed, and deleting several
# gigabytes of somebody else's work is not a decision to take silently.
mkdir -p "$ROOT/build"
out=$(run shell)
rmdir "$ROOT/build"
contains "a build tree inside the checkout is reported" "$out" \
	"build tree inside the checkout"
contains "and the reason is given" "$out" "without KAS_BUILD_DIR set"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
