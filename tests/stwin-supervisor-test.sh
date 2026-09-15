#!/bin/sh
#
# stwin-supervisor-test.sh - the connection ladder, without a radio.
#
# The supervisor reaches Bluetooth only through a `link` object with two
# methods, and a session object with three. That indirection is not
# decoration: it is what lets the state machine, the back-off ladder and
# every failure path run here in under a second, instead of on a board
# where reproducing "the peripheral accepted the connection and then
# dropped it" means pulling a battery at the right moment.
#
# What is proven here: the order of the states, that a failure at each of
# the four steps goes back to Scanning rather than out of the loop, that
# the delay doubles and is capped, that it resets on data rather than on
# connection, that a session is always closed, and that a link which stays
# up and stops delivering is treated as dead.
#
# What is not proven: that bleak and bluetoothd behave like the fake. Only
# a board can show that, which is what docs/BRINGUP.md is for.
#
#   sh tests/stwin-supervisor-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/bench-stwin/files
PYTHON=${PYTHON:-python3}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The modules are installed as a package, so they are tested as one. A flat
# copy would make the relative imports fail here and nowhere else, which is
# the kind of difference between test and target that hides a real fault.
mkdir -p "$WORK/bench_stwin"
for module in __init__.py bluest.py sinks.py supervisor.py; do
	cp "$SRC/$module" "$WORK/bench_stwin/$module"
done

cat >"$WORK/run.py" <<'PYTHON'
import asyncio
import sys
import time

sys.path.insert(0, sys.argv[1])

from bench_stwin.sinks import Sink
from bench_stwin.supervisor import Supervisor

passed = 0
failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        print("ok       %s" % label)
        passed += 1
    else:
        print("FAILED   %s: wanted %r, got %r" % (label, want, got))
        failed += 1


class Recorder(Sink):
    """Everything the supervisor told its sinks, in order."""

    def __init__(self):
        self.states = []
        self.records = []
        self.rssi_reports = []
        self.closed = False

    def write(self, record):
        self.records.append(record)

    def rssi(self, address, value, when):
        self.rssi_reports.append((address, value))

    def state(self, name):
        self.states.append(name)

    def close(self):
        self.closed = True


class FakeSession:
    def __init__(self, link, characteristics=2):
        self.link = link
        self.characteristics = characteristics
        self.closed = asyncio.Event()
        self.close_calls = 0
        self.on_frame = None

    async def subscribe(self, on_frame):
        self.on_frame = on_frame
        self.link.calls.append("subscribe")
        if self.link.subscribe_raises:
            raise RuntimeError("StartNotify failed")
        return self.characteristics

    async def wait_closed(self):
        await self.closed.wait()

    async def close(self):
        self.close_calls += 1
        self.link.calls.append("close")


class FakeLink:
    """A link that can be told to fail at any step."""

    def __init__(self):
        self.calls = []
        self.scan_result = "device"
        self.connect_raises = False
        self.subscribe_raises = False
        self.characteristics = 2
        self.advertisements = [("C0:11:22:33:44:55", -62)]
        self.sessions = []
        self.frames_to_send = []
        self.hold_open = False

    async def scan(self, address, timeout, on_advertisement):
        self.calls.append("scan")
        for addr, rssi in self.advertisements:
            on_advertisement(addr, rssi)
        return self.scan_result

    async def connect(self, device):
        self.calls.append("connect")
        if self.connect_raises:
            raise RuntimeError("le-connection-abort-by-local")
        session = FakeSession(self, self.characteristics)
        self.sessions.append(session)
        # Deliver the scripted frames as soon as something subscribes, then
        # drop the link, so one round of the ladder completes per call.
        asyncio.get_running_loop().call_soon(self._deliver, session)
        return session

    def _deliver(self, session):
        if session.on_frame is not None:
            for mask, data in self.frames_to_send:
                session.on_frame(mask, data, "C0:11:22:33:44:55")
        if not self.hold_open:
            session.closed.set()
        else:
            asyncio.get_running_loop().call_soon(self._deliver, session)


class FakeClock:
    """A clock that does not move, so timestamps are assertable.

    It is the right clock for every case except the stall test, which is
    about time passing. Writing that one against a frozen clock is how
    this file first came to hang: the supervisor waited for a quiet period
    that could never elapse, forever, in 30-second steps.
    """

    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def build(link, clock=None, **kwargs):
    recorder = Recorder()
    delays = []

    async def sleep(seconds):
        delays.append(seconds)
        await asyncio.sleep(0)

    supervisor = Supervisor(link, [recorder], sleep=sleep,
                            clock=clock or FakeClock(), **kwargs)
    return supervisor, recorder, delays


ACC = 0x00800000
FRAME = bytes.fromhex("3412" "0a00f6ff0004")


# ------------------------------------------------------------ happy path

link = FakeLink()
link.frames_to_send = [(ACC, FRAME)]
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=1))

check("the states in order, once", rec.states,
      ["scanning", "connecting", "resolving", "streaming", "backoff"])
check("scan came before connect",
      link.calls.index("scan") < link.calls.index("connect"), True)
check("one frame reached the sinks", len(rec.records), 1)
check("the record carries the mask", rec.records[0]["mask"], ACC)
check("and the peripheral address", rec.records[0]["mac"],
      "C0:11:22:33:44:55")
check("and a host timestamp", rec.records[0]["host_ts"], 1000.0)
check("the frame was decoded", rec.records[0]["acc"], [10.0, -10.0, 1024.0])
check("the advertisement RSSI was reported", rec.rssi_reports,
      [("C0:11:22:33:44:55", -62)])
check("the session was closed", link.sessions[0].close_calls, 1)
# The delay after a round that streamed is the starting one. Asserting on
# supervisor.backoff instead would read 2.0 here and look like a bug: the
# reset happens when streaming begins, and the doubling happens when the
# round ends, so after one full round the *next* delay is already 2.
check("the delay after a streaming round is the first rung", delays, [1.0])

# ------------------------------------------------------- nothing advertising

link = FakeLink()
link.scan_result = None
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=1))
check("no advertisement means no connect", "connect" in link.calls, False)
check("and the ladder backs off", rec.states, ["scanning", "backoff"])

# -------------------------------------------------------- connect refused

link = FakeLink()
link.connect_raises = True
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=1))
check("a refused connection is not fatal", rec.states,
      ["scanning", "connecting", "backoff"])

# ------------------------------------------------- nothing worth subscribing

link = FakeLink()
link.characteristics = 0
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=1))
check("a peripheral with no BlueST characteristic backs off", rec.states,
      ["scanning", "connecting", "resolving", "backoff"])
check("and its session is still closed", link.sessions[0].close_calls, 1)

# StartNotify failing is an error rather than a count of zero, and has to
# land in the same place.
link = FakeLink()
link.subscribe_raises = True
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=1))
check("a failed StartNotify backs off too", rec.states[-1], "backoff")
check("and closes the session", link.sessions[0].close_calls, 1)

# ------------------------------------------------------- the back-off ladder

link = FakeLink()
link.scan_result = None
sup, rec, delays = build(link, backoff_start=1.0, backoff_max=30.0)
asyncio.run(sup.run(rounds=7))
check("the delay doubles and is capped", delays,
      [1.0, 2.0, 4.0, 8.0, 16.0, 30.0, 30.0])

# Reset is by data, not by connection. A peripheral that accepts a
# connection and drops it without sending anything must not reset the
# ladder, or a persistent fault is retried as fast as the radio allows.
link = FakeLink()
link.characteristics = 0
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=3))
check("a connection without data does not reset the ladder", delays,
      [1.0, 2.0, 4.0])

link = FakeLink()
link.frames_to_send = [(ACC, FRAME)]
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=3))
check("a streaming round does reset it", delays, [1.0, 1.0, 1.0])

# ----------------------------------------------------- a frame that is wrong

# Mask promises three int16 and the frame carries one. The decoder raises,
# the supervisor counts it, and the loop keeps running: a peripheral whose
# frames do not match the table must not take the gateway down.
link = FakeLink()
link.frames_to_send = [(ACC, bytes.fromhex("3412" "0a00"))]
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=1))
check("an undecodable frame is counted", sup.decode_errors, 1)
check("and written nowhere", len(rec.records), 0)
check("and the ladder still completes", rec.states[-1], "backoff")

# ------------------------------------------------------------- a quiet link

# The session stays open and stops delivering. A supervision timeout never
# fires because the link is alive; without the stall check the gateway
# sits in Streaming with a green LED and writes nothing.
class SilentLink(FakeLink):
    def _deliver(self, session):
        return


link = SilentLink()
link.hold_open = True
sup, rec, delays = build(link, clock=time.time, stall_timeout=0.05)
asyncio.run(sup.run(rounds=1))
check("a connected but silent link is given up", rec.states,
      ["scanning", "connecting", "resolving", "streaming", "backoff"])
check("and its session is closed", link.sessions[0].close_calls, 1)

# With the check disabled the same link would never be given up, which is
# what the default of 30 s exists to prevent. Proven by running one round
# with a session that does close, so the test cannot hang.
link = FakeLink()
sup, rec, delays = build(link, stall_timeout=0)
asyncio.run(sup.run(rounds=1))
check("stall_timeout=0 still follows the normal path", rec.states[-1],
      "backoff")

# ------------------------------------------------------------- shutdown

link = FakeLink()
sup, rec, delays = build(link)
asyncio.run(sup.run(rounds=1))
sup.close()
check("close turns the LEDs off", rec.states[-1], "off")
check("and closes every sink", rec.closed, True)

print()
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTHON

"$PYTHON" -u "$WORK/run.py" "$WORK"
