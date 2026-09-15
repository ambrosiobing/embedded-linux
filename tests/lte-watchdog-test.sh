#!/bin/sh
#
# lte-watchdog-test.sh - the escalation state machine, without a modem.
#
# The watchdog reaches the hardware only through commands it looks up on
# PATH: mmcli, ping, nmcli and lte-gpio. That is not an accident of style,
# it is what makes this file possible. Every one of them is replaced here
# by a stub that records how it was called, so the whole ladder from a
# healthy bearer to a PWRKEY power cycle runs on a laptop in under a
# second.
#
# What is proven here: the ordering of the three recovery levels, that a
# success resets the level, that the level never skips a rung, that the
# power cycle sends one press when the modem is gone and two when it is
# still enumerated, and that the counters land in the metrics file.
#
# What is not proven: that any of those commands does what the stub
# pretends. Only a board can show that. See docs/failover-tests.md.
#
#   sh tests/lte-watchdog-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-lte/files/lte-watchdog
PYTHON=${PYTHON:-python3}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/fake"
BENCH_TEST_DIR=$WORK/fake
export BENCH_TEST_DIR

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

# ---------------------------------------------------------------- stubs

cat >"$WORK/bin/mmcli" <<'STUB'
#!/bin/sh
echo "mmcli $*" >>"$BENCH_TEST_DIR/calls"
for arg in "$@"; do
	case $arg in
	--reset) exit 0 ;;
	esac
done
case ${1:-} in
-L)
	if [ -f "$BENCH_TEST_DIR/no-modem" ]; then
		echo "No modems were found"
	else
		echo "    /org/freedesktop/ModemManager1/Modem/0 [SimTech] SIM7600E-H"
	fi
	exit 0
	;;
esac
if [ -f "$BENCH_TEST_DIR/no-modem" ]; then
	echo "error: couldn't find modem" >&2
	exit 1
fi
echo "modem.generic.device-identifier : deadbeef"
echo "modem.generic.state             : $(cat "$BENCH_TEST_DIR/state")"
STUB

cat >"$WORK/bin/ping" <<'STUB'
#!/bin/sh
echo "ping $*" >>"$BENCH_TEST_DIR/calls"
[ -f "$BENCH_TEST_DIR/ping-fails" ] && exit 1
exit 0
STUB

cat >"$WORK/bin/nmcli" <<'STUB'
#!/bin/sh
echo "nmcli $*" >>"$BENCH_TEST_DIR/calls"
exit 0
STUB

cat >"$WORK/bin/lte-gpio" <<'STUB'
#!/bin/sh
echo "lte-gpio $*" >>"$BENCH_TEST_DIR/calls"
exit 0
STUB

chmod +x "$WORK/bin"/*
PATH=$WORK/bin:$PATH
export PATH

# Every wait is zero, so the ladder runs at the speed of the stubs. The
# real values are in the shipped lte.conf and are the point of the unit,
# not of the state machine.
cat >"$WORK/lte.conf" <<'CONF'
probe_host = 203.0.113.1
probe_iface = wwan0
probe_interval = 0
failures_before_recovery = 3
nm_connection = lte
settle_s = 0
settle_cold_s = 0
pwrkey_gap_s = 0
pwrkey_verified = 1
CONF

run() {
	iterations=$1
	rm -f "$BENCH_TEST_DIR/calls"
	: >"$BENCH_TEST_DIR/calls"
	printf '%s\n' "${2:-connected}" >"$BENCH_TEST_DIR/state"
	"$PYTHON" "$SUT" --config "$WORK/lte.conf" --interval 0 \
		--iterations "$iterations" >"$WORK/log" 2>&1 || true
}

metric() {
	grep "^$1 " "$WORK/metrics.prom" 2>/dev/null | tail -1 | awk '{print $2}'
}

calls() {
	# grep -c prints 0 and exits 1 when nothing matches, so the count is
	# captured first and the exit status handled separately. Written the
	# obvious way, with "|| echo 0", a no-match prints the zero twice.
	count=$(grep -c "$1" "$BENCH_TEST_DIR/calls" 2>/dev/null) || count=0
	printf '%s\n' "$count"
}

printf 'metrics_path = %s\n' "$WORK/metrics.prom" >>"$WORK/lte.conf"

# --------------------------------------------------- a healthy bearer

rm -f "$BENCH_TEST_DIR/ping-fails" "$BENCH_TEST_DIR/no-modem"
run 3
check "healthy: no probe failures" "$(metric lte_probe_failures_total)" "0"
check "healthy: level stays 0" "$(metric lte_watchdog_level)" "0"
check "healthy: state is connected" \
	"$(grep -c 'lte_watchdog_state{state="connected"} 1' "$WORK/metrics.prom")" "1"
check "healthy: no recovery ran" "$(calls 'nmcli con up')" "0"

# ------------------------------------------- three failures, level one

touch "$BENCH_TEST_DIR/ping-fails"
run 3
check "level 1: three failures counted" "$(metric lte_probe_failures_total)" "3"
check "level 1: bearer restarted once" "$(calls 'nmcli con up lte')" "1"
check "level 1: no modem reset yet" "$(calls 'mmcli -m any --reset')" "0"
check "level 1: no power cycle yet" "$(calls 'lte-gpio pwrkey')" "0"

# ------------------------------------------------- six failures, level two

run 6
check "level 2: bearer restarted first" "$(calls 'nmcli con up lte')" "1"
check "level 2: then the modem reset" "$(calls 'mmcli -m any --reset')" "1"
check "level 2: still no power cycle" "$(calls 'lte-gpio pwrkey')" "0"

# ----------------------------------------------- nine failures, level three

run 9
check "level 3: reached the power cycle" \
	"$(grep -c 'lte_recoveries_total{level="3"} 1' "$WORK/metrics.prom")" "1"
check "level 3: modem present, so off then on" "$(calls 'lte-gpio pwrkey')" "2"

# ------------------------------- a modem that is gone gets one press only

touch "$BENCH_TEST_DIR/no-modem"
run 9
check "cold start: a single press, not a pair" "$(calls 'lte-gpio pwrkey')" "1"
rm -f "$BENCH_TEST_DIR/no-modem"

# --------------------- level 3 is refused until it is armed by a human

# The PWRKEY offset in lte.conf comes from a vendor demo and the default
# jumper positions, both properties of a HAT revision rather than of the
# part. A wrong offset drives an unknown header pin on a board that is by
# then unattended, so the only rung that touches hardware stays off until
# somebody has confirmed the wiring.
#
# The other half of that bargain is asserted here too: levels 1 and 2 must
# keep working while it is unarmed, or the safety measure would cost more
# than it saves.
sed '/pwrkey_verified/d' "$WORK/lte.conf" >"$WORK/unarmed.conf"
printf 'metrics_path = %s\n' "$WORK/unarmed.prom" >>"$WORK/unarmed.conf"

touch "$BENCH_TEST_DIR/ping-fails"
: >"$BENCH_TEST_DIR/calls"
printf 'connected\n' >"$BENCH_TEST_DIR/state"
"$PYTHON" "$SUT" --config "$WORK/unarmed.conf" --interval 0 \
	--iterations 9 >"$WORK/log" 2>&1 || true

check "unarmed: no power cycle attempted" "$(calls 'lte-gpio pwrkey')" "0"
check "unarmed: level 1 still ran" "$(calls 'nmcli con up lte')" "1"
check "unarmed: level 2 still ran" "$(calls 'mmcli -m any --reset')" "1"
check "unarmed: the refusal is counted" \
	"$(grep -c '^lte_pwrkey_refused_total 1$' "$WORK/unarmed.prom")" "1"
check "unarmed: no level 3 recovery is claimed" \
	"$(grep -c 'lte_recoveries_total{level="3"} 0' "$WORK/unarmed.prom")" "1"
check "unarmed: it says why in the log" \
	"$(grep -c 'level 3 refused' "$WORK/log")" "1"
rm -f "$BENCH_TEST_DIR/ping-fails"

# ------------------------------------------------- a success resets the level

rm -f "$BENCH_TEST_DIR/ping-fails"
run 4
check "recovered: level back to 0" "$(metric lte_watchdog_level)" "0"
check "recovered: state connected again" \
	"$(grep -c 'lte_watchdog_state{state="connected"} 1' "$WORK/metrics.prom")" "1"

# -------------------------------- a registered modem is not a working one

# The bearer says connected and the ping does not come back. This is the
# APN typo and the carrier that has stopped forwarding, and it is the whole
# reason the probe has two halves rather than one.
touch "$BENCH_TEST_DIR/ping-fails"
run 3 connected
check "registered but dead: still escalates" "$(calls 'nmcli con up lte')" "1"

# The other way round: the ping would succeed but the modem is not
# connected, so the probe must not even try.
rm -f "$BENCH_TEST_DIR/ping-fails"
run 3 registered
check "not connected: no ping attempted" "$(calls '^ping ')" "0"
check "not connected: escalates anyway" "$(calls 'nmcli con up lte')" "1"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
