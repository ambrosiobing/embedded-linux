"""Where a decoded frame goes: a file, a broker, three LEDs.

Every sink implements the same two methods and does nothing clever. That
is the point of splitting them out: the supervisor decides *when* something
happened, the decoder decides *what* the bytes mean, and these decide where
it is written. None of the three has to be understood to change another.

Each sink imports its dependency inside its constructor rather than at the
top of the module. It reads oddly and it buys something specific: the
gateway can be started without an MQTT broker, without a GPIO chip, or on a
laptop with none of the three installed, and the part that is missing fails
at the point where it is configured, naming itself, instead of at import
time with a traceback that blames the program.

SPDX-License-Identifier: MIT
"""

import json
import os
import time

from .bluest import fields_of

# Every state the supervisor can emit. LED_FOR_STATE below must cover all
# of them, and tests/stwin-sinks-test.sh asserts exactly that: the first
# version of this file was missing "resolving", so the LEDs went dark for
# the seconds between Connected and the first notification. Dark is the
# one thing the three of them are not supposed to be able to say.
STATES = ("scanning", "connecting", "resolving", "streaming", "backoff",
          "off")


class Sink:
    """No-op base, so a sink only implements what it cares about."""

    def write(self, record):
        """One decoded notification."""

    def rssi(self, address, value, when):
        """One advertisement, before a connection exists."""

    def state(self, name):
        """A supervisor state transition."""

    def close(self):
        """Release whatever was acquired."""


def flatten(mask, record):
    """A record as a flat list of values, in the column order of the mask.

    Vector features become three columns; scalars become one. The order is
    the mask order, which is also the order the bytes arrived in, so the
    file reads like the frame.
    """
    row = []
    for _bit, name, fmt, _scale, _unit in fields_of(mask):
        value = record.get(name)
        width = 3 if fmt.count("h") == 3 else 1
        if value is None:
            row.extend([""] * width)
        elif isinstance(value, list):
            row.extend(value)
        else:
            row.append(value)
    return row


def header_for(mask):
    """Column names for a mask, fixed for the life of a file."""
    names = ["host_ts", "dev_ts"]
    for _bit, name, fmt, _scale, unit in fields_of(mask):
        if fmt.count("h") == 3:
            names.extend(["%s_x_%s" % (name, unit),
                          "%s_y_%s" % (name, unit),
                          "%s_z_%s" % (name, unit)])
        else:
            names.append("%s_%s" % (name, unit))
    # Two columns that are almost always empty and are the reason the file
    # can be trusted: a frame the decoder could not finish is written here
    # too, visibly incomplete, rather than being dropped or padded.
    names.extend(["undecoded_mask", "undecoded"])
    return names


class CsvSink(Sink):
    """One file per day per feature mask, with a real header.

    Per mask, not only per day, because the columns are a property of the
    mask: a peripheral that notifies on two characteristics produces two
    shapes of row, and one file holding both is a file no plotting tool
    will read. Per day because a gateway that runs for a month should not
    produce one file that has to be split before it can be opened.
    """

    def __init__(self, directory, clock=time.time):
        self.directory = directory
        self.clock = clock
        self.handles = {}
        os.makedirs(directory, exist_ok=True)

    def path_for(self, mask, when):
        day = time.strftime("%Y%m%d", time.gmtime(when))
        return os.path.join(self.directory, "%s-%08x.csv" % (day, mask))

    def _handle(self, mask, when):
        path = self.path_for(mask, when)
        current = self.handles.get(mask)
        if current is not None:
            if current[0] == path:
                return current[1]
            # The day rolled over. Close the old file rather than leaving
            # a descriptor open for every day the gateway has been up.
            current[1].close()

        fresh = not os.path.exists(path) or os.path.getsize(path) == 0
        handle = open(path, "a", encoding="ascii")
        if fresh:
            handle.write(",".join(header_for(mask)) + "\n")
        self.handles[mask] = (path, handle)
        return handle

    def write(self, record):
        mask = record["mask"]
        when = record.get("host_ts", self.clock())
        handle = self._handle(mask, when)
        row = ["%.6f" % when, record.get("dev_ts", "")]
        row.extend(flatten(mask, record))
        row.append(record.get("undecoded_mask", ""))
        row.append(record.get("undecoded", ""))
        handle.write(",".join(str(v) for v in row) + "\n")
        # Flushed every line. A gateway is judged by what survived the
        # power cut, and a buffered line that never reached the card is
        # indistinguishable from a frame that never arrived.
        handle.flush()

    def close(self):
        for _path, handle in self.handles.values():
            handle.close()
        self.handles = {}


class MqttSink(Sink):
    """One JSON object per frame, on bench/stwin/<mac>/<mask>."""

    def __init__(self, broker, port=1883, prefix="bench/stwin",
                 client_factory=None, client_id="stwin-gw"):
        self.prefix = prefix
        if client_factory is None:
            client_factory = self._paho_client
        self.client = client_factory(client_id)
        self.client.connect(broker, port, keepalive=60)
        # The network loop runs in its own thread, so publish() never
        # blocks the asyncio loop that is receiving notifications. A
        # gateway that stalls its radio client because a broker is slow has
        # turned a reporting problem into a data-loss problem.
        self.client.loop_start()

    @staticmethod
    def _paho_client(client_id):
        import paho.mqtt.client as mqtt

        # paho-mqtt 2.0 made the callback API version the first positional
        # argument of Client(), and raises ValueError without it. The 1.x
        # spelling, Client(client_id), is what every example written before
        # 2024 uses and it fails at construction time with a message about
        # migrations. meta-python ships 2.0.0, so this is the spelling that
        # works on the image; VERSION2 is chosen rather than VERSION1
        # because the compatibility shim is the thing that will be removed.
        return mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                           client_id=client_id)

    def topic(self, record):
        return "%s/%s/%s" % (self.prefix,
                             record.get("mac", "unknown").replace(":", ""),
                             "%08x" % record["mask"])

    def write(self, record):
        payload = dict(record)
        payload["mask"] = "%08x" % record["mask"]
        # QoS 0. The broker is on the same board or one hop away, the data
        # is a sample stream where the next frame is 20 ms behind this one,
        # and the CSV file is the record of what happened. Paying for
        # delivery guarantees on telemetry that is superseded before it
        # could be retried is the wrong trade.
        self.client.publish(self.topic(record), json.dumps(payload), qos=0)

    def rssi(self, address, value, when):
        self.client.publish(
            "%s/%s/rssi" % (self.prefix, address.replace(":", "")),
            json.dumps({"rssi": value, "host_ts": when}), qos=0)

    def close(self):
        self.client.loop_stop()
        self.client.disconnect()


# The three lines, and what each state lights. One colour at a time, so an
# LED that is on is never ambiguous.
LED_FOR_STATE = {
    "scanning": "yellow",
    "connecting": "yellow",
    "resolving": "yellow",
    "streaming": "green",
    "backoff": "red",
    "off": None,
}


class GpiodLines:
    """The libgpiod v2 request, behind two methods that take booleans.

    This wrapper is the whole reason LedSink can be tested. Everything
    gpiod-specific, the enums included, is created here at construction
    time; LedSink then speaks in True and False and never imports gpiod.
    Without the wrapper the LED logic could only be exercised on a machine
    with the bindings and a GPIO chip, which is a board.
    """

    def __init__(self, chip, offsets, consumer="stwin-gw"):
        import gpiod
        from gpiod.line import Direction, Value

        # The v2 Python API, matching the v2 C API the rest of this
        # repository uses: a config dict of offsets to LineSettings, not
        # the v1 chip.get_line() call that every tutorial written before
        # 2022 shows. python3-gpiod in meta-python is 2.1.3, which is the
        # same library version the C daemons here are compiled against.
        self._active = Value.ACTIVE
        self._inactive = Value.INACTIVE
        settings = gpiod.LineSettings(direction=Direction.OUTPUT,
                                      output_value=Value.INACTIVE)
        self._request = gpiod.request_lines(
            chip, consumer=consumer,
            config={tuple(offsets): settings})

    def set(self, states):
        self._request.set_values(
            {offset: self._active if on else self._inactive
             for offset, on in states.items()})

    def release(self):
        self._request.release()


class LedSink(Sink):
    """Link state on three GPIO lines."""

    def __init__(self, chip="/dev/gpiochip0", green=5, yellow=6, red=13,
                 lines=None):
        self.offsets = {"green": green, "yellow": yellow, "red": red}
        if lines is None:
            lines = GpiodLines(chip, list(self.offsets.values()))
        self.lines = lines
        self.state("off")

    def state(self, name):
        lit = LED_FOR_STATE.get(name)
        self.lines.set({offset: (colour == lit)
                        for colour, offset in self.offsets.items()})

    def close(self):
        self.state("off")
        self.lines.release()


class LogSink(Sink):
    """Everything to a logger, which is what journalctl reads.

    Present because a gateway with no LEDs wired and no broker running
    should still be debuggable, and because the first bring-up happens
    before either of those exists.
    """

    def __init__(self, log, every=50):
        self.log = log
        self.every = every
        self.count = 0

    def write(self, record):
        self.count += 1
        if self.every and self.count % self.every == 0:
            self.log.info("%d frames, last %s", self.count,
                          json.dumps({k: v for k, v in record.items()
                                      if k not in ("mac",)}, default=str))

    def rssi(self, address, value, when):
        self.log.info("adv %s rssi %s", address, value)

    def state(self, name):
        self.log.info("state %s", name)
