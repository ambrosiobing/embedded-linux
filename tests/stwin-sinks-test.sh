#!/bin/sh
#
# stwin-sinks-test.sh - what happens to a record after it is decoded.
#
# Three sinks, none of which needs the thing it talks to. The CSV sink
# needs a directory, the MQTT sink takes its client as an argument, and
# the LED sink drives an object with two methods rather than libgpiod
# directly. That last one is the only reason the LED logic can be checked
# anywhere but on a board.
#
# What is proven here: that a file's columns are fixed by the feature mask
# and are written once, that the day rolls over into a new file, that a
# frame the decoder could not finish is still recorded and is visibly
# incomplete, that the MQTT topic and payload are what the README says
# they are, and that exactly one LED is lit in every state.
#
#   sh tests/stwin-sinks-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/bench-stwin/files
PYTHON=${PYTHON:-python3}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bench_stwin"
for module in __init__.py bluest.py sinks.py; do
	cp "$SRC/$module" "$WORK/bench_stwin/$module"
done

cat >"$WORK/run.py" <<'PYTHON'
import json
import os
import sys

sys.path.insert(0, sys.argv[1])

from bench_stwin.sinks import (LED_FOR_STATE, STATES, CsvSink, LedSink,
                               MqttSink, header_for)

work = sys.argv[2]
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


ACC_GYRO_MAG = 0x00E00000
ENV = 0x001C0000

# Two fixed instants, chosen to be on different days in UTC.
DAY_ONE = 1789000000.0      # 2026-09-10, and DAY_TWO is the 11th
DAY_TWO = DAY_ONE + 86400.0

# --------------------------------------------------------------- the header

check("columns carry the unit as well as the axis",
      header_for(ACC_GYRO_MAG),
      ["host_ts", "dev_ts",
       "acc_x_mg", "acc_y_mg", "acc_z_mg",
       "gyro_x_dps", "gyro_y_dps", "gyro_z_dps",
       "mag_x_mGa", "mag_y_mGa", "mag_z_mGa",
       "undecoded_mask", "undecoded"])
check("a scalar feature is one column, not three",
      header_for(0x00080000),
      ["host_ts", "dev_ts", "hum_percent", "undecoded_mask", "undecoded"])

# ------------------------------------------------------------------- CSV

csv_dir = os.path.join(work, "csv")
sink = CsvSink(csv_dir)

sink.write({"mask": ACC_GYRO_MAG, "host_ts": DAY_ONE, "dev_ts": 0x1234,
            "acc": [10.0, -10.0, 1024.0], "gyro": [0.1, -0.2, 0.3],
            "mag": [100.0, -56.0, 300.0], "mac": "C0:11:22:33:44:55"})

day_one_path = os.path.join(csv_dir, "20260910-00e00000.csv")
check("the file is named by day and mask", os.path.exists(day_one_path), True)

# Read while the sink is still open. Every line is flushed, because a
# gateway is judged by what survived the power cut.
with open(day_one_path, encoding="ascii") as handle:
    lines = handle.read().splitlines()
check("one header and one row", len(lines), 2)
check("the header is the mask's columns",
      lines[0], ",".join(header_for(ACC_GYRO_MAG)))
check("the row is the values in mask order", lines[1],
      "1789000000.000000,4660,10.0,-10.0,1024.0,0.1,-0.2,0.3,"
      "100.0,-56.0,300.0,,")

# A second mask is a second file, because the columns are different and one
# file holding both shapes is a file no plotting tool will read.
sink.write({"mask": ENV, "host_ts": DAY_ONE, "dev_ts": 7,
            "press": 1000.0, "hum": 59.5, "temp": 28.2})
check("a second mask opens a second file",
      os.path.exists(os.path.join(csv_dir, "20260910-001c0000.csv")), True)

# The day rolls over.
sink.write({"mask": ACC_GYRO_MAG, "host_ts": DAY_TWO, "dev_ts": 1,
            "acc": [1.0, 2.0, 3.0], "gyro": [0.0, 0.0, 0.0],
            "mag": [0.0, 0.0, 0.0]})
check("the next day is a new file",
      os.path.exists(os.path.join(csv_dir, "20260911-00e00000.csv")), True)
check("and the old one was not appended to",
      len(open(day_one_path, encoding="ascii").read().splitlines()), 2)

# An incomplete record is written, not dropped, and says so in two columns
# that are empty on every good row.
sink.write({"mask": 0x00800100, "host_ts": DAY_TWO, "dev_ts": 2,
            "acc": [4.0, 5.0, 6.0], "undecoded_mask": "00000100",
            "undecoded": "deadbeef"})
partial = os.path.join(csv_dir, "20260911-00800100.csv")
row = open(partial, encoding="ascii").read().splitlines()[1]
check("an incomplete frame is still recorded",
      row, "1789086400.000000,2,4.0,5.0,6.0,00000100,deadbeef")
sink.close()

# Reopening appends rather than writing a second header, which is what
# makes a restart of the service invisible in the data.
again = CsvSink(csv_dir)
again.write({"mask": ACC_GYRO_MAG, "host_ts": DAY_ONE, "dev_ts": 9,
             "acc": [0.0, 0.0, 0.0], "gyro": [0.0, 0.0, 0.0],
             "mag": [0.0, 0.0, 0.0]})
again.close()
check("a restart does not write a second header",
      len(open(day_one_path, encoding="ascii").read().splitlines()), 3)

# A field the record is missing leaves its columns empty rather than
# shifting everything after it.
short = CsvSink(os.path.join(work, "short"))
short.write({"mask": ACC_GYRO_MAG, "host_ts": DAY_ONE, "dev_ts": 3,
             "acc": [1.0, 2.0, 3.0]})
short_row = open(os.path.join(work, "short", "20260910-00e00000.csv"),
                 encoding="ascii").read().splitlines()[1]
check("a missing feature leaves empty columns, not a short row",
      len(short_row.split(",")), len(header_for(ACC_GYRO_MAG)))
short.close()

# ------------------------------------------------------------------ MQTT


class FakeClient:
    def __init__(self, client_id):
        self.client_id = client_id
        self.calls = []
        self.published = []

    def connect(self, host, port, keepalive):
        self.calls.append(("connect", host, port, keepalive))

    def loop_start(self):
        self.calls.append(("loop_start",))

    def loop_stop(self):
        self.calls.append(("loop_stop",))

    def disconnect(self):
        self.calls.append(("disconnect",))

    def publish(self, topic, payload, qos):
        self.published.append((topic, payload, qos))


made = {}


def factory(client_id):
    made["client"] = FakeClient(client_id)
    return made["client"]


mqtt = MqttSink("broker.local", 1883, "bench/stwin", client_factory=factory)
client = made["client"]
check("the broker is connected on construction",
      client.calls[0], ("connect", "broker.local", 1883, 60))
check("and the network loop is started in its own thread",
      client.calls[1], ("loop_start",))

mqtt.write({"mask": ACC_GYRO_MAG, "mac": "C0:11:22:33:44:55",
            "host_ts": DAY_ONE, "dev_ts": 1, "acc": [1.0, 2.0, 3.0]})
topic, payload, qos = client.published[0]
check("the topic is prefix, address without colons, and the mask",
      topic, "bench/stwin/C01122334455/00e00000")
check("telemetry goes at QoS 0", qos, 0)

decoded = json.loads(payload)
check("the mask is a string in JSON, not a number",
      decoded["mask"], "00e00000")
check("the measurements survive the round trip",
      decoded["acc"], [1.0, 2.0, 3.0])

mqtt.rssi("C0:11:22:33:44:55", -70, DAY_ONE)
topic, payload, _qos = client.published[1]
check("RSSI has its own topic", topic, "bench/stwin/C01122334455/rssi")
check("with the value and a timestamp",
      json.loads(payload), {"rssi": -70, "host_ts": DAY_ONE})

mqtt.close()
check("closing stops the loop before disconnecting",
      client.calls[-2:], [("loop_stop",), ("disconnect",)])

# ------------------------------------------------------------------- LEDs


class FakeLines:
    def __init__(self):
        self.last = None
        self.released = False

    def set(self, states):
        self.last = dict(states)

    def release(self):
        self.released = True


lines = FakeLines()
leds = LedSink(green=5, yellow=6, red=13, lines=lines)
check("a fresh sink lights nothing", lines.last,
      {5: False, 6: False, 13: False})

expected = {
    "scanning": {5: False, 6: True, 13: False},
    "connecting": {5: False, 6: True, 13: False},
    "resolving": {5: False, 6: True, 13: False},
    "streaming": {5: True, 6: False, 13: False},
    "backoff": {5: False, 6: False, 13: True},
}
for state, want in expected.items():
    leds.state(state)
    check("state %s lights the right line" % state, lines.last, want)

# A state missing from the table falls through to nothing lit, which is a
# silent gap: three LEDs that are all dark mean "off", and "off" is
# supposed to mean the service is not running. So the table is checked
# against the list of states the supervisor can emit, rather than against
# the handful this test happens to exercise.
check("the colour table covers every state, and invents none",
      sorted(LED_FOR_STATE), sorted(STATES))

leds.close()
check("closing turns them off", lines.last, {5: False, 6: False, 13: False})
check("and releases the lines", lines.released, True)

print()
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTHON

"$PYTHON" -u "$WORK/run.py" "$WORK" "$WORK"
