#!/bin/sh
#
# debug-proxy-test.sh - the console splitter, without a console.
#
# agent-proxy.sh owns one resource and its whole job is to refuse when
# something else already has it. That refusal is the thing worth testing,
# because it is the one this bench meets most often and the one whose
# symptom lies: a terminal program holding /dev/ttyUSB0 makes agent-proxy
# fail to open it, and the board looks dead.
#
# Everything external is a stub on PATH: agent-proxy itself, fuser, lsof
# and ps. The device is an ordinary file in a temporary directory, which
# is enough because the script only ever tests it with -e, -r and -w.
#
# The case that needed the most care is the third one. A guard that
# refuses has to name what it matched, otherwise the reader either
# believes it or switches it off, and on a long debugging session people
# switch it off. So the test asserts on the pid AND the process name, not
# merely on a non-zero exit.
#
#   sh tests/debug-proxy-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/projects/09-kernel-debug/host/agent-proxy.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BIN=$WORK/bin
mkdir -p "$BIN"

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
		echo "$2" | sed 's/^/           /'
		fail=$((fail + 1))
		;;
	*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	esac
}

# ------------------------------------------------------------- the stubs
#
# agent-proxy records its argument vector instead of running. That
# recording is the assertion for the happy path: the argument order is
# unusual (port pair, then a target host of 0, then the device) and
# getting it wrong is not something a syntax check would catch.
cat >"$BIN/agent-proxy" <<'EOF'
#!/bin/sh
echo "$@" >"$RECORD"
exit 0
EOF

# No holder by default. fuser exits 1 and prints nothing when nothing has
# the file open, which is what the real one does.
cat >"$BIN/fuser" <<'EOF'
#!/bin/sh
if [ -n "${HOLDER_PIDS:-}" ]; then
	echo "$HOLDER_PIDS"
	exit 0
fi
exit 1
EOF

cat >"$BIN/ps" <<'EOF'
#!/bin/sh
# ps -o comm= -p PID
for arg in "$@"; do
	case $arg in
	-p) next=pid ;;
	*)
		if [ "${next:-}" = pid ]; then
			case $arg in
			4242) echo "picocom" ;;
			4243) echo "minicom" ;;
			*) echo "unknown" ;;
			esac
			next=
		fi
		;;
	esac
done
EOF

chmod 0755 "$BIN/agent-proxy" "$BIN/fuser" "$BIN/ps"

DEVICE=$WORK/ttyUSB0
: >"$DEVICE"

RECORD=$WORK/record
export RECORD

run() {
	RECORD=$WORK/record
	rm -f "$RECORD"
	PATH="$BIN:$PATH" HOLDER_PIDS="${HOLDER_PIDS:-}" RECORD="$RECORD" \
		sh "$SUT" "$@" 2>&1
}

# --------------------------------------------------------- the happy path
out=$(run "$DEVICE" 2>&1) || true
rc=0
argv=$(cat "$WORK/record" 2>/dev/null || echo "NOT RUN")

check "agent-proxy is invoked with the documented argument order" \
	"$argv" "5550^5551 0 $DEVICE,115200"
contains "the console port is printed before it is needed" "$out" "5550"
contains "the gdb port is printed as a target remote line" "$out" "5551"

# The invocation is echoed before running. That is deliberate: a version
# of agent-proxy wanting different arguments would otherwise fail with a
# usage message that never names this script.
contains "the command is printed before it runs" "$out" "+ agent-proxy"

# ------------------------------------------------------- a custom baud rate
out=$(run "$DEVICE" 921600 2>&1) || true
argv=$(cat "$WORK/record" 2>/dev/null || echo "NOT RUN")
check "a second argument becomes the baud rate" \
	"$argv" "5550^5551 0 $DEVICE,921600"

# -------------------------------------------------- the device is held
#
# The case this script exists for. Two pids, so that the loop over them
# is exercised rather than a single-value path that happens to work.
rc=0
out=$(HOLDER_PIDS="4242 4243" run "$DEVICE" 2>&1) || rc=$?
check "a held device is refused" "$rc" "1"
contains "the refusal names the first pid" "$out" "4242"
contains "the refusal names the first process" "$out" "picocom"
contains "the refusal names the second pid" "$out" "4243"
contains "the refusal names the second process" "$out" "minicom"
contains "the refusal says where the terminal should go instead" \
	"$out" "5550"
absent "a held device never reaches agent-proxy" "$(cat "$WORK/record" 2>/dev/null || echo)" "^"

# ------------------------------------------------ a missing device
rc=0
out=$(run "$WORK/nosuchdevice" 2>&1) || rc=$?
check "a missing device is refused" "$rc" "1"
contains "the refusal names the missing path" "$out" "nosuchdevice"
contains "the refusal suggests where adapters appear" "$out" "ttyUSB0"

# ------------------------------------- neither fuser nor lsof is present
#
# The script cannot ask the question. It must say so rather than printing
# a clean result from a question it never asked, which is the failure
# mode this repository has shipped three times.
BIN2=$WORK/bin2
mkdir -p "$BIN2"
cp "$BIN/agent-proxy" "$BIN2/agent-proxy"
rm -f "$WORK/record"
out=$(PATH="$BIN2:/usr/bin:/bin" RECORD="$WORK/record" sh "$SUT" "$DEVICE" 2>&1) || true
case $out in
*"neither fuser nor lsof"*)
	echo "ok       an unanswerable question is reported, not assumed"
	pass=$((pass + 1))
	;;
*)
	# fuser or lsof exists on this host, so the branch cannot be
	# reached. Say that, rather than counting an untested branch as
	# a pass.
	echo "skipped  the host has fuser or lsof, so the 'cannot check'"
	echo "         branch was not exercised here. CI runs on an image"
	echo "         that has them, so this is expected to stay skipped."
	;;
esac

# ------------------------------------------- agent-proxy is not installed
BIN3=$WORK/bin3
mkdir -p "$BIN3"
cp "$BIN/fuser" "$BIN/ps" "$BIN3/"
rc=0
out=$(PATH="$BIN3:/usr/bin:/bin" sh "$SUT" "$DEVICE" 2>&1) || rc=$?
check "a missing agent-proxy is refused" "$rc" "1"
contains "the refusal says how to build it" "$out" "git clone"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
