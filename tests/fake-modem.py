#!/usr/bin/env python3
"""fake-modem - a pseudo-terminal that answers AT commands from a table.

The point of the exercise is that the tracker's state machine can be driven
through every one of its transitions on a laptop, including the ones a real
modem will only produce on a bad day: a network that refuses the attach, a
network that grants no PSM, a server that never acknowledges. Waiting for a
carrier to refuse an attach is not a test strategy.

How it is wired. This creates a pty, prints the slave path on stdout, and
then serves the master side. The tracker is pointed at the slave path with
--port, so from its side the port is a character device that it opens,
configures with termios and reads and writes, which is what it will do on
the board. Nothing in the tracker knows it is under test.

What this is not. It is not a modem simulator and it does not model the
radio. It answers strings with strings. Every response in the tables below
was written from the SIM7070G AT command manual rather than captured from
the part on the bench, which means this file can only prove that the state
machine does the right thing with a given answer. Whether the part gives
that answer is acceptance criteria 1 to 9 and it needs the board. The
scenario tables are marked accordingly, and the first real transcript
that lands in projects/16-nbiot-tracker/docs/evidence/ replaces them.

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import argparse
import errno
import os
import re
import select
import struct
import sys
import time

# The granted timers the happy path reports back: TAU 00101000 is unit 001,
# hours, count 01000, eight of them; Active-Time 00000001 is unit 000, two
# second units, one of them. The tracker decodes these, so the test can
# assert on 28800 and 2 rather than on the octets, which is the assertion
# that would have caught the wrong default this program's first run found.
GRANTED_TAU = "00101000"
GRANTED_ACTIVE = "00000001"

# A network that grants less than was asked for. Not an error case: it is
# the ordinary case, and the one acceptance criterion 4 exists for. TAU
# 00100001 is unit 001, hours, count 00001, so one hour rather than eight.
STINGY_TAU = "00100001"

COMMON = [
    (r"^AT$", ["OK"]),
    (r"^ATE0$", ["OK"]),
    (r"^AT\+CNMP=38$", ["OK"]),
    (r"^AT\+CMNB=[123]$", ["OK"]),
    (r"^AT\+CGDCONT=.*$", ["OK"]),
    (r"^AT\+CEREG=4$", ["OK"]),
    (r"^AT\+CPSMS=.*$", ["OK"]),
    (r"^AT\+CEDRXS=.*$", ["OK"]),
    (r"^AT\+CSQ$", ["+CSQ: 17,0", "OK"]),
    (r"^AT\+CNACT=0,1$", ["OK", "+APP PDP: 0,ACTIVE"]),
    (r"^AT\+CNACT=0,0$", ["OK"]),
    (r"^AT\+CAOPEN=.*$", ["+CAOPEN: 0,0", "OK"]),
    (r"^AT\+CACLOSE=0$", ["OK"]),
]

ATTACHED = [
    (r"^AT\+CEREG\?$",
     ['+CEREG: 4,1,"1A2B","01234567",9,,,"%s","%s"'
      % (GRANTED_ACTIVE, GRANTED_TAU), "OK"]),
    (r"^AT\+CPSMS\?$",
     ['+CPSMS: 1,,,"%s","%s"' % (GRANTED_TAU, GRANTED_ACTIVE), "OK"]),
]

SCENARIOS = {
    # The whole path: power, configure, attach, report, acknowledged.
    "happy": COMMON + ATTACHED,

    # The network refuses. stat 3 is a registration denied, and the tracker
    # has to stop rather than retry: a denied attach is usually a SIM or a
    # subscription, and retrying it on a timer is how a tracker spends a
    # battery on a problem no amount of waking will fix.
    "denied": COMMON + [
        (r"^AT\+CEREG\?$", ["+CEREG: 4,3", "OK"]),
    ],

    # Attached, and PSM refused. The configuration asked for eight hours,
    # +CPSMS? answers mode 0, and the tracker must record that it got
    # nothing rather than repeating what it requested.
    "no-psm": COMMON + [
        (r"^AT\+CEREG\?$", ['+CEREG: 4,1,"1A2B","01234567",9', "OK"]),
        (r"^AT\+CPSMS\?$", ["+CPSMS: 0", "OK"]),
    ],

    # Attached, and PSM granted at less than was asked for.
    "stingy-psm": COMMON + [
        (r"^AT\+CEREG\?$",
         ['+CEREG: 4,1,"1A2B","01234567",9,,,"%s","%s"'
          % (GRANTED_ACTIVE, STINGY_TAU), "OK"]),
        (r"^AT\+CPSMS\?$",
         ['+CPSMS: 1,,,"%s","%s"' % (STINGY_TAU, GRANTED_ACTIVE), "OK"]),
    ],

    # The modem takes its time. Three unregistered answers before the
    # fourth says yes, which is the ordinary NB-IoT cold attach and the
    # reason attach_timeout_s is not at_timeout_s.
    "slow-attach": COMMON + ATTACHED,

    # The server never acknowledges. The tracker should reach BACKOFF
    # rather than hang or claim a successful report.
    "no-ack": COMMON + ATTACHED,
}

# Scenarios where the +CARECV must not produce a matching acknowledgement.
NO_ACK = {"no-ack"}
SLOW = {"slow-attach"}


def coap_ack(message_id, token):
    """A 2.04 Changed acknowledgement for the message just sent.

    Built here rather than canned, because the message id and the token are
    chosen at random by the tracker for every report. A canned reply would
    pass the first time and then pass for ever without ever matching, which
    is the failure mode where a test agrees with itself.
    """
    first = (1 << 6) | (2 << 4) | len(token)
    return struct.pack("!BBH", first, (2 << 5) | 4, message_id) + token


class FakeModem:
    def __init__(self, scenario, log=None):
        self.table = [(re.compile(p), r) for p, r in SCENARIOS[scenario]]
        self.scenario = scenario
        self.log = log or (lambda msg: None)
        self.buf = b""
        self.pending_send = 0
        self.last_message_id = None
        self.last_token = b""
        self.data_waiting = False
        self.attach_polls = 0
        self.seen = []

    def handle(self, line):
        """One command in, a list of response lines out."""
        self.seen.append(line)
        self.log("cmd %s" % line)

        if self.scenario in SLOW and line == "AT+CEREG?":
            self.attach_polls += 1
            if self.attach_polls <= 3:
                return ["+CEREG: 4,2", "OK"]

        match = re.match(r"^AT\+CASEND=0,(\d+)$", line)
        if match:
            self.pending_send = int(match.group(1))
            return ["PROMPT"]

        match = re.match(r"^AT\+CARECV=0,(\d+)$", line)
        if match:
            if not self.data_waiting:
                return ["+CARECV: 0,", "OK"]
            self.data_waiting = False
            if self.scenario in NO_ACK:
                return ["OK"]
            payload = coap_ack(self.last_message_id, self.last_token)
            return ["+CARECV: %d,%s" % (len(payload), payload.hex()), "OK"]

        for pattern, response in self.table:
            if pattern.match(line):
                return list(response)
        return ["ERROR"]

    def take_datagram(self, data):
        """The bytes written after the send prompt.

        The message id and the token are read out of the CoAP header here
        so the acknowledgement can carry them back. A modem does not do
        this; a fake one has to, because the alternative is an
        acknowledgement that never matches and a test that cannot tell a
        broken matcher from a broken send.
        """
        if len(data) >= 4:
            _, _, self.last_message_id = struct.unpack("!BBH", data[:4])
            token_length = data[0] & 0x0F
            self.last_token = data[4:4 + token_length]
        self.data_waiting = True
        self.log("datagram %d bytes, message id %s"
                 % (len(data), self.last_message_id))
        if self.scenario in NO_ACK:
            return ["OK"]
        return ["OK", "+CADATAIND: 0"]


def serve(master, modem, idle_timeout):
    """Read commands, write answers, until the far side goes quiet.

    Quiet rather than closed: the tracker exits and the pty's slave side
    has no other holder, so a read here returns EIO on Linux rather than
    EOF. Treating that as the end of the session is what stops this from
    being a process the test has to kill.
    """
    deadline = time.monotonic() + idle_timeout
    buf = b""
    started = False
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.25)
        if not ready:
            continue
        try:
            chunk = os.read(master, 1024)
        except OSError as exc:
            # EIO on a pty master means no process currently holds the
            # slave. Before the tracker has opened the port that is simply
            # "not yet", and returning here would end the session before it
            # began: the first draft did exactly that, and every scenario
            # would have reported a modem that answered nothing. After the
            # tracker has spoken, the same EIO means it has exited, which
            # is the end of the session.
            if exc.errno != errno.EIO or started:
                return
            time.sleep(0.05)
            continue
        if not chunk:
            if started:
                return
            time.sleep(0.05)
            continue
        started = True
        deadline = time.monotonic() + idle_timeout
        buf += chunk

        if modem.pending_send:
            if len(buf) < modem.pending_send:
                continue
            datagram, buf = (buf[:modem.pending_send],
                             buf[modem.pending_send:])
            modem.pending_send = 0
            write_lines(master, modem.take_datagram(datagram))

        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            line = raw.decode("ascii", "replace").strip("\r \t")
            if not line:
                continue
            write_lines(master, modem.handle(line))


def write_lines(master, lines):
    for line in lines:
        if line == "PROMPT":
            # Not a line. The modem signals that it is ready for the
            # payload with a bare "> " and no terminator, which is why the
            # tracker reads the prompt with a different function from the
            # one that reads responses.
            os.write(master, b"> ")
            continue
        os.write(master, b"\r\n" + line.encode("ascii") + b"\r\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description="a pty that answers AT")
    parser.add_argument("-s", "--scenario", default="happy",
                        choices=sorted(SCENARIOS))
    parser.add_argument("--idle-timeout", type=float, default=15.0)
    parser.add_argument("--seen", help="write the commands received here, "
                                       "one per line, when the session ends")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    def log(message):
        if args.verbose:
            sys.stderr.write("fake-modem: %s\n" % message)
            sys.stderr.flush()

    # Imported here rather than at the top so that --help and an import of
    # this file for its tables both work on a host with no pty, which the
    # Windows authoring laptop is. The test script checks for this and
    # skips rather than failing; see tests/tracker-state-test.sh.
    try:
        import pty
    except ImportError:
        sys.stderr.write("fake-modem: no pty on this host, so the state "
                         "machine cannot be driven here. Run this on the "
                         "WSL laptop or let CI run it.\n")
        return 77

    master, slave = pty.openpty()
    sys.stdout.write(os.ttyname(slave) + "\n")
    sys.stdout.flush()
    # Closed here on purpose. While this process holds the slave open, the
    # tracker's exit leaves the pty with a holder and the read above blocks
    # until the idle timeout instead of ending the session, which turns
    # every test into a fifteen second wait.
    os.close(slave)

    modem = FakeModem(args.scenario, log=log)
    try:
        serve(master, modem, args.idle_timeout)
    finally:
        if args.seen:
            with open(args.seen, "w", encoding="ascii", newline="\n") as fh:
                for line in modem.seen:
                    fh.write(line + "\n")
        os.close(master)
    return 0


if __name__ == "__main__":
    sys.exit(main())
