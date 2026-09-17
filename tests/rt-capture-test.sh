#!/bin/sh
#
# rt-capture-test.sh - the external instrument, without the instrument.
#
# rt-capture had no test until 17 September 2026, and the thing that went
# wrong on the board is exactly the thing a test can hold: it ran at
# ordinary priority against stress-ng on the same three cores, and its ring
# buffer overran twice.
#
# THE ASSERTION THAT MATTERS IS AN ORDERING.
#
# The daqhats library spawns its own reader thread inside a_in_scan_start,
# and on Linux a thread inherits the scheduling policy of whoever created
# it. So raising the priority after that call would raise this program's
# Python loop and leave the thread that actually drains SPI where it was.
# The fix and the bug produce identical code at a glance and differ only in
# which line comes first.
#
# Neither the HAT nor root is needed. daqhats is replaced with a stub that
# records the calls it receives, and os.sched_setscheduler is replaced with
# one that records rather than performs, so the order is observable on any
# machine and SCHED_FIFO is never actually requested.
#
#   sh tests/rt-capture-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-rt/files/rt-capture
PYTHON=${PYTHON:-python3}

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

if ! "$PYTHON" -c "import numpy" 2>/dev/null; then
	echo "FAILED   numpy is not installed, and rt-capture imports it."
	echo "         sudo apt-get install -y python3-numpy"
	exit 1
fi

# ------------------------------------------------------------- the driver
#
# Imports rt-capture as a module rather than running it as a script, so
# main() is called deliberately and the __main__ guard does not fire twice.

cat >"$WORK/drive.py" <<'PYEOF'
import importlib.machinery
import importlib.util
import os
import sys
import types

import numpy as np

SUT = sys.argv[1]
REFUSE = len(sys.argv) > 2 and sys.argv[2] == "refuse"

# The authoring laptop is Windows, where os has neither SCHED_FIFO nor
# sched_param, so rt-capture would take its AttributeError branch and this
# test would assert nothing on the machine it is usually run from. Supplied
# when absent; on Linux these already exist and are left alone.
if not hasattr(os, "SCHED_FIFO"):
    os.SCHED_FIFO = 1
if not hasattr(os, "sched_param"):
    os.sched_param = lambda priority: priority

calls = []

# Record rather than perform. SCHED_FIFO needs privileges that a test
# runner does not have, and asking for them would make this test pass or
# fail on who is logged in rather than on what the code does.
def fake_setscheduler(pid, policy, param):
    calls.append("sched_setscheduler")
    if REFUSE:
        raise PermissionError(1, "Operation not permitted")

os.sched_setscheduler = fake_setscheduler


class Result(object):
    def __init__(self, data):
        self.data = data
        self.hardware_overrun = False
        self.buffer_overrun = False


class mcc118(object):
    def __init__(self, address):
        calls.append("mcc118")

    def a_in_scan_start(self, **kwargs):
        calls.append("a_in_scan_start")

    def a_in_scan_read_numpy(self, **kwargs):
        calls.append("read")
        return Result(np.zeros(10, "f8"))

    def a_in_scan_stop(self):
        calls.append("stop")

    def a_in_scan_cleanup(self):
        calls.append("cleanup")


stub = types.ModuleType("daqhats")
stub.mcc118 = mcc118
stub.OptionFlags = types.SimpleNamespace(CONTINUOUS=1)
sys.modules["daqhats"] = stub

# spec_from_file_location returns None for a file with no extension,
# because there is no suffix for it to pick a loader from, and the failure
# arrives later as "NoneType has no attribute loader". Every program in
# meta-bench/ is extensionless, so name the loader explicitly.
loader = importlib.machinery.SourceFileLoader("rt_capture", SUT)
spec = importlib.util.spec_from_loader("rt_capture", loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

rc = module.main(["--seconds", "0.05", "--out", sys.argv[-1]])
print("RC=%d" % rc)
print("CALLS=%s" % ",".join(calls))
PYEOF

# ------------------------------------------------------------------ cases

out=$("$PYTHON" "$WORK/drive.py" "$SUT" normal "$WORK/a.npy" 2>&1)
order=$(printf '%s\n' "$out" | sed -n 's/^CALLS=//p')

contains "the priority is requested at all" "$order" "sched_setscheduler"
contains "and the scan is started" "$order" "a_in_scan_start"

# The whole point. A comma-separated prefix match, so later calls do not
# matter and the two names cannot be reordered without failing.
case $order in
*sched_setscheduler,a_in_scan_start*)
	echo "ok       the priority is set BEFORE the scan starts"
	pass=$((pass + 1))
	;;
*)
	echo "FAILED   the priority is set BEFORE the scan starts"
	echo "         the library's reader thread is created in"
	echo "         a_in_scan_start and inherits the policy in force then,"
	echo "         so setting it afterwards raises the wrong thread."
	echo "         call order was: $order"
	fail=$((fail + 1))
	;;
esac

contains "the run still completes" "$out" "RC=0"

# A refusal is survivable and must be visible. A run that quietly took the
# slow path is a row taken under conditions no column records.
out=$("$PYTHON" "$WORK/drive.py" "$SUT" refuse "$WORK/b.npy" 2>&1)
contains "a refused priority is reported" "$out" "could not set SCHED_FIFO"
contains "and names where overruns come from" "$out" "overruns come from"
contains "and the run continues rather than aborting" "$out" "RC=0"

order=$(printf '%s\n' "$out" | sed -n 's/^CALLS=//p')
contains "and the scan still runs after a refusal" "$order" "a_in_scan_start"

# The priority constant is part of the method, not an implementation
# detail: it has to sit below rt-toggle's SCHED_FIFO 80 so that the task
# being measured still preempts the instrument measuring it.
priority=$("$PYTHON" -c "
import importlib.machinery, importlib.util, sys, types
stub = types.ModuleType('daqhats')
stub.mcc118 = object
stub.OptionFlags = types.SimpleNamespace(CONTINUOUS=1)
sys.modules['daqhats'] = stub
loader = importlib.machinery.SourceFileLoader('c', sys.argv[1])
spec = importlib.util.spec_from_loader('c', loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
print(m.CAPTURE_PRIORITY)
" "$SUT")
check "the priority is 60" "$priority" "60"

verdict=$("$PYTHON" -c "print('below' if $priority < 80 else 'at-or-above')")
check "which is below rt-toggle's 80" "$verdict" "below"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
