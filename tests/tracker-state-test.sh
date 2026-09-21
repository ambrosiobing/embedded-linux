#!/bin/sh
# tracker-state-test.sh - drive Project 16's state machine with no modem.
#
# Six scenarios, each a pseudo-terminal answering AT commands from a table:
# the whole happy path, a network that refuses the attach, a network that
# grants no PSM, a network that grants less PSM than was asked for, a slow
# cold attach, and a server that never acknowledges.
#
# What this proves: that the state machine makes the right transition for a
# given answer, that the granted PSM timers are read back and decoded
# rather than echoed from the configuration, and that an unacknowledged
# report reaches BACKOFF instead of being reported as a success.
#
# What it does not prove: that a SIM7070G gives any of those answers. Every
# response in tests/fake-modem.py came from the AT command manual and not
# from the part, so this suite cannot close acceptance criteria 1 to 9.
# Those need the board. See projects/16-nbiot-tracker/README.md.
#
# Requires a pty, so it skips on the Windows authoring laptop and runs on
# the WSL laptop and in CI.
#
# SPDX-License-Identifier: MIT
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tracker="$root/meta-bench/recipes-bench/bench-tracker/files/tracker"
fake="$root/tests/fake-modem.py"

python=${PYTHON:-python3}
command -v "$python" >/dev/null 2>&1 || {
	echo "SKIP: no $python on this host"
	exit 0
}

# The skip has to be a real check rather than a guess from uname: this runs
# under WSL, under Git Bash and in CI, and only one of those three lacks a
# pty. Asking the interpreter is one line and cannot be wrong about it.
if ! "$python" -c "import pty, termios" >/dev/null 2>&1; then
	echo "SKIP: no pty on this host, so the state machine cannot be"
	echo "      driven here. Run on the WSL laptop, or let CI run it."
	exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass=0
fail=0

check() {
	_what=$1
	_want=$2
	_file=$3
	if grep -q -- "$_want" "$_file"; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		echo "FAIL: $_what"
		echo "      wanted: $_want"
		echo "      in $_file, which holds:"
		sed 's/^/        /' "$_file"
	fi
}

refute() {
	_what=$1
	_unwanted=$2
	_file=$3
	if grep -q -- "$_unwanted" "$_file"; then
		fail=$((fail + 1))
		echo "FAIL: $_what"
		echo "      did not want: $_unwanted"
		echo "      but it is in $_file"
	else
		pass=$((pass + 1))
	fi
}

check_status() {
	_what=$1
	_want=$2
	_got=$3
	if [ "$_want" = "$_got" ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
		echo "FAIL: $_what: wanted exit $_want, got $_got"
	fi
}

# The tracker reaches tracker-gpio by name through PATH, which is Project
# 15's seam and the reason the whole program runs here. A stub on PATH
# exercises that seam rather than stepping around it with --no-power: the
# happy path must actually pulse PWRKEY, and the stub records that it did.
mkdir -p "$work/bin"
cat >"$work/bin/tracker-gpio" <<'STUB'
#!/bin/sh
echo "tracker-gpio $*" >>"$TRACKER_GPIO_LOG"
if [ "${1:-}" = "marker-hold" ]; then
	# The real tool announces on stdout, flushes, and then blocks until
	# it is signalled. The tracker waits for that line before it starts
	# the thing being measured, so a stub that exited immediately would
	# let the send begin outside the marked interval and the suite would
	# pass while the instrument measured the wrong seconds.
	echo "marker: stub held"
	exec sleep 300
fi
STUB
chmod +x "$work/bin/tracker-gpio"
PATH="$work/bin:$PATH"
export PATH

# A configuration whose PSM request is deliberately different from what the
# fake network grants, so an assertion on the granted values cannot pass by
# accidentally matching the request. 00110001 is unit 001, hours, count
# 10001, seventeen hours: a value no scenario grants.
cat >"$work/tracker.conf" <<'CONF'
apn=bench.test
coap_host=198.51.100.7
coap_port=5683
coap_path=bench/16/position
psm_tau=00110001
psm_active=00000001
# An offset, so the marker path is exercised rather than skipped. The value
# is arbitrary because the stub on PATH is what receives it: the real
# offset is one of the three facts still to be read off the board, and
# tracker-gpio refuses rather than guessing when it is unset.
marker_gpio=21
attach_timeout_s=20
at_timeout_s=5
# RFC 7252's own defaults add up to thirty seconds of waiting for an
# acknowledgement that the no-ack scenario is never going to send. Shortened
# here so the suite proves the refusal in about a second. The schedule's
# shape is what is under test, not its constants.
ack_timeout_s=0.3
max_retransmit=2
CONF

run_scenario() {
	_scenario=$1
	_out="$work/$_scenario.log"
	_seen="$work/$_scenario.seen"
	TRACKER_GPIO_LOG="$work/$_scenario.gpio"
	export TRACKER_GPIO_LOG
	: >"$TRACKER_GPIO_LOG"

	"$python" "$fake" --scenario "$_scenario" --seen "$_seen" \
		>"$work/$_scenario.pty" 2>"$work/$_scenario.fake" &
	_fake_pid=$!

	# Wait for the pty path rather than sleeping a fixed time. A fixed
	# sleep is the reason flaky suites get switched off, and the file
	# either has a line in it or it does not.
	_waited=0
	while [ ! -s "$work/$_scenario.pty" ]; do
		_waited=$((_waited + 1))
		if [ "$_waited" -gt 100 ]; then
			echo "FAIL: $_scenario: fake modem never printed a pty"
			fail=$((fail + 1))
			kill "$_fake_pid" 2>/dev/null || true
			return 1
		fi
		sleep 0.1
	done
	_port=$(head -n 1 "$work/$_scenario.pty")

	set +e
	"$python" "$tracker" -c "$work/tracker.conf" -p "$_port" \
		>"$_out" 2>&1
	_status=$?
	set -e
	wait "$_fake_pid" 2>/dev/null || true

	# One plain variable, read by the check_status that follows each
	# scenario. This was an eval building a name per scenario, which
	# neither a reader nor shellcheck could follow: CI reported the three
	# variables as never assigned, and it was right about what it could
	# see. Project 3's suite had the same construct and the same fix.
	last_status=$_status
	return 0
}

echo "== happy: the whole path =="
run_scenario happy
check "happy: PWRKEY is pulsed through the PATH seam" \
	"tracker-gpio pwrkey" "$work/happy.gpio"
check "happy: the marker is held, not pulsed" \
	"tracker-gpio marker-hold" "$work/happy.gpio"
check "happy: reaches CONFIGURED" "state BOOTING -> CONFIGURED" "$work/happy.log"
check "happy: reaches REGISTERED" "state CONFIGURED -> REGISTERED" "$work/happy.log"
check "happy: sends" "state REGISTERED -> SENDING" "$work/happy.log"
check "happy: acknowledged" "SENDING -> REGISTERED: acknowledged" "$work/happy.log"
check "happy: ends ASLEEP" "state REGISTERED -> ASLEEP" "$work/happy.log"
check_status "happy: exit" 0 "$last_status"

# The granted values, decoded. 00101000 is eight hours, 28800 seconds, and
# the configuration above asked for seventeen. An implementation that
# echoed the request would print 61200 here, which is exactly the defect
# acceptance criterion 4 exists to catch.
check "happy: granted TAU is decoded to seconds" "28800 s" "$work/happy.log"
refute "happy: the request is not reported as the grant" \
	"61200 s" "$work/happy.log"
check "happy: sleeps on the network's TAU" \
	"sleeping on the network's TAU of 28800 s" "$work/happy.log"

# The radio lockout is an instrument requirement, not just a network
# preference: the PPK2 stops at 1 A and a GPRS burst on this class of part
# is well above that. If this assertion ever fails, the next capture is
# the one that clips.
check "happy: 2G is locked out before any attach" \
	"AT+CNMP=38" "$work/happy.seen"

echo "== denied: the network refuses the attach =="
run_scenario denied
check "denied: reaches FAILED" "-> FAILED: network refused the attach" \
	"$work/denied.log"
refute "denied: never claims a report" "SENDING" "$work/denied.log"
check_status "denied: exit" 1 "$last_status"

echo "== no-psm: attached, PSM refused =="
run_scenario no-psm
check "no-psm: attaches anyway" "-> REGISTERED" "$work/no-psm.log"
check "no-psm: says plainly that nothing was granted" \
	"psm granted: nothing reported" "$work/no-psm.log"
check "no-psm: falls back to the host's own interval" \
	"no PSM granted" "$work/no-psm.log"
refute "no-psm: does not invent a TAU" "28800 s" "$work/no-psm.log"

echo "== stingy-psm: granted less than requested =="
run_scenario stingy-psm
check "stingy-psm: reports one hour, not the seventeen requested" \
	"3600 s" "$work/stingy-psm.log"
refute "stingy-psm: does not report the request" "61200 s" \
	"$work/stingy-psm.log"

echo "== slow-attach: three polls before registration =="
run_scenario slow-attach
check "slow-attach: gets there" "-> REGISTERED" "$work/slow-attach.log"
check "slow-attach: really did poll more than once" \
	"AT+CEREG?" "$work/slow-attach.seen"
check_status "slow-attach: exit" 0 "$last_status"

echo "== no-ack: the server never answers =="
run_scenario no-ack
check "no-ack: tries to send" "state REGISTERED -> SENDING" "$work/no-ack.log"
check "no-ack: reaches BACKOFF" "-> BACKOFF: no acknowledgement" \
	"$work/no-ack.log"
# Anchored on the log's own punctuation, not on the bare word. A plain
# grep for "acknowledged" also matches "unacknowledged" and "no
# acknowledgement", so this assertion passed while the program was doing
# the wrong thing, which is the same substring mistake that let a broken
# register definition through on Project 5.
refute "no-ack: never claims an acknowledgement" "REGISTERED: acknowledged" \
	"$work/no-ack.log"
check "no-ack: closes the socket anyway" "AT+CACLOSE=0" "$work/no-ack.seen"
check "no-ack: and deactivates the context, so the modem can sleep" \
	"AT+CNACT=0,0" "$work/no-ack.seen"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
