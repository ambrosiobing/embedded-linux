#!/bin/sh
#
# bench-state-test.sh - exercise the state machine without a board.
#
# bench-state is where the interesting decision lives: which of three words
# describes the system right now. That decision is testable on any host by
# putting a fake systemctl first on PATH, so it is tested here rather than
# discovered on the bench.
#
#   sh tests/bench-state-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/recipes-bench/bench-status/files/bench-state

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/run"

# A systemctl whose answers come from two environment variables.
cat >"$WORK/bin/systemctl" <<'FAKE'
#!/bin/sh
case "$1" in
is-system-running)
	echo "${FAKE_SYSTEM:-running}"
	[ "${FAKE_SYSTEM:-running}" = running ] || exit 1
	;;
is-active)
	shift
	[ "$1" = --quiet ] && shift
	for unit in ${FAKE_ACTIVE:-}; do
		[ "$unit" = "$1" ] && exit 0
	done
	exit 3
	;;
esac
exit 0
FAKE
chmod +x "$WORK/bin/systemctl"

printf 'sshd.socket\n' >"$WORK/watch.conf"

PATH=$WORK/bin:$PATH
BENCH_STATE_DIR=$WORK/run
BENCH_WATCH_FILE=$WORK/watch.conf
export PATH BENCH_STATE_DIR BENCH_WATCH_FILE

pass=0
fail=0

check() {
	name=$1
	want=$2
	got=$(cat "$WORK/run/state" 2>/dev/null || echo "<no file>")
	if [ "$got" = "$want" ]; then
		echo "ok       $name"
		pass=$((pass + 1))
	else
		echo "FAILED   $name: wanted '$want', got '$got'"
		fail=$((fail + 1))
	fi
}

run_poll() {
	rm -f "$WORK/run/state"
	env FAKE_SYSTEM="$1" FAKE_ACTIVE="$2" sh "$SUT" poll
}

run_poll starting "sshd.socket"
check "system still coming up is yellow" starting

run_poll degraded "sshd.socket"
check "a degraded system is red" failed

run_poll running "sshd.socket"
check "everything active is green" ok

run_poll running ""
check "a watched unit stopped is red" failed

rm -f "$WORK/run/state"
sh "$SUT" set failed
check "an explicit latch is red" failed

rm -f "$WORK/run/state"
if sh "$SUT" set nonsense 2>/dev/null; then
	echo "FAILED   an unknown state is refused"
	fail=$((fail + 1))
else
	echo "ok       an unknown state is refused"
	pass=$((pass + 1))
fi

rm -f "$WORK/run/state"
got=$(sh "$SUT" show)
if [ "$got" = starting ]; then
	echo "ok       show without a state file says starting"
	pass=$((pass + 1))
else
	echo "FAILED   show without a state file said '$got'"
	fail=$((fail + 1))
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
