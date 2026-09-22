#!/usr/bin/env python3
"""tracker-at-test - the parsers, the timer octets, CoAP, and the machine.

This suite and tests/tracker-state-test.sh divide the program between them
along the line where the host stops mattering. That one needs a pty, so it
runs on the WSL laptop and in CI and skips on the Windows authoring laptop.
This one substitutes the port in process and runs anywhere, which means the
state machine's transitions are covered on every host that can run Python,
and only the transport waits for a machine with a pty.

The division is deliberate rather than a convenience. A suite that skips
everywhere it is usually run is a suite whose failures are discovered by
someone else, and the transitions are the part being designed.

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(path, name):
    """Import a file whose name is not an identifier.

    `tracker` has no extension and `fake-modem.py` has a dash, because one
    is a program on a board and the other is named for what it pretends to
    be. Neither is importable by the ordinary route.

    The loader is named rather than inferred. Left to work it out,
    spec_from_file_location decides from the extension, and a file with no
    extension gets no loader and a spec of None, which then fails one line
    later with an AttributeError about NoneType that says nothing at all
    about the real cause.
    """
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_file_location(name, path, loader=loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


T = load(os.path.join(ROOT, "meta-bench", "recipes-bench", "bench-tracker",
                      "files", "tracker"), "tracker_prog")
F = load(os.path.join(HERE, "fake-modem.py"), "fake_modem")

PASS = []
FAIL = []


def check(what, got, want):
    if got == want:
        PASS.append(what)
    else:
        FAIL.append("%s\n      wanted: %r\n      got:    %r"
                    % (what, want, got))


def check_true(what, got):
    check(what, bool(got), True)


# ------------------------------------------------------- the timer octets
#
# Every expected value below was worked out from the 3GPP unit tables by
# hand and written here before the functions were run against it, which is
# the only order in which a test can disagree with the code. Doing it the
# other way round produces a test that records what the program does.
#
# Timer 3, three bits of unit then five of count:
#   000 ten minutes, 001 one hour, 010 ten hours, 011 two seconds,
#   100 thirty seconds, 101 one minute, 110 320 hours, 111 deactivated.

check("TAU 00101000 is eight hours", T.decode_tau("00101000"), 8 * 3600)
check("TAU 00111000 is twenty-four hours", T.decode_tau("00111000"), 24 * 3600)
check("TAU 00100001 is one hour", T.decode_tau("00100001"), 3600)
check("TAU 00000110 is sixty minutes in ten minute units",
      T.decode_tau("00000110"), 6 * 600)
check("TAU 01000001 is ten hours", T.decode_tau("01000001"), 36000)
# Written as 01100001 first, which is unit 011 and therefore two seconds,
# not the 320 hours intended. The unit is the high three bits and 110 is
# the one wanted. Kept as a pair because the two octets differ by one bit
# and by a factor of 576,000, which is the whole reason these are decoded
# in the program rather than trusted where they are written.
check("TAU 01100001 is two seconds, not 320 hours",
      T.decode_tau("01100001"), 2)
check("TAU 11000001 is 320 hours", T.decode_tau("11000001"), 1152000)
check("TAU 11100000 is deactivated", T.decode_tau("11100000"), 0)
check("TAU refuses a short octet", T.decode_tau("0010100"), None)
check("TAU refuses a non-binary octet", T.decode_tau("0010100X"), None)
check("TAU refuses nothing at all", T.decode_tau(""), None)

# Timer 2 has a different table, which is the trap: 001 is one minute here
# and one hour there, so an implementation that shares one table between
# them is out by a factor of sixty and looks entirely plausible.
check("Active 00000001 is two seconds", T.decode_active("00000001"), 2)
check("Active 00100001 is one minute", T.decode_active("00100001"), 60)
check("Active 01000001 is six minutes", T.decode_active("01000001"), 360)
check("Active 11100000 is deactivated", T.decode_active("11100000"), 0)
check("the two tables genuinely differ at unit 001",
      (T.decode_tau("00100001"), T.decode_active("00100001")), (3600, 60))

# ------------------------------------------------------------- the parsers

reg = T.parse_cereg('+CEREG: 4,1,"1A2B","01234567",9,,,"00000001","00101000"')
check("CEREG reads the state", reg["stat"], 1)
check_true("CEREG 1 is registered", reg["registered"])
check("CEREG pulls the granted TAU off the URC", reg["granted_tau"],
      "00101000")
check("CEREG pulls the granted Active-Time off the URC",
      reg["granted_active"], "00000001")
check_true("CEREG 5 is registered roaming",
           T.parse_cereg("+CEREG: 2,5")["registered"])
check_true("CEREG 3 is a refusal", T.parse_cereg("+CEREG: 2,3")["denied"])
check("CEREG 2 is searching, not registered",
      T.parse_cereg("+CEREG: 2,2")["registered"], False)
check("CEREG with no timers reports none",
      "granted_tau" in T.parse_cereg("+CEREG: 2,1"), False)
check("CEREG ignores a line that is not CEREG",
      T.parse_cereg("+CSQ: 17,0"), None)

check("CSQ 17 is minus seventy-nine", T.parse_csq("+CSQ: 17,0")["dbm"], -79)
check("CSQ 0 is minus one hundred and thirteen",
      T.parse_csq("+CSQ: 0,0")["dbm"], -113)
# 99 is the value that matters most, because it is the one that must not be
# turned into a number. Mapped through the same arithmetic it reads as
# +85 dBm, which is a signal no terrestrial network produces and which
# would sit in a results table looking like an excellent reading.
check("CSQ 99 is unknown, not a reading", T.parse_csq("+CSQ: 99,99")["dbm"],
      None)

psm = T.parse_cpsms('+CPSMS: 1,,,"00101000","00000001"')
check("CPSMS reads the mode", psm["mode"], 1)
check("CPSMS reads the TAU back", psm["tau"], "00101000")
check("CPSMS reads the Active-Time back", psm["active"], "00000001")
check("CPSMS mode 0 is PSM refused", T.parse_cpsms("+CPSMS: 0")["mode"], 0)
check("CPSMS refused carries no timers", T.parse_cpsms("+CPSMS: 0")["tau"],
      None)

# parse_carecv exists because the first version of await_ack handed the
# whole line to the CoAP parser, prefix included. These are the assertions
# that would have caught it.
check("CARECV reads hex", T.parse_carecv("+CARECV: 2,6869"), b"hi")
check("CARECV reads raw bytes", T.parse_carecv("+CARECV: 2,hi"), b"hi")
check("CARECV refuses a length that disagrees with the payload",
      T.parse_carecv("+CARECV: 9,hi"), None)
check("CARECV ignores a line that is not CARECV",
      T.parse_carecv("OK"), None)
check("CARECV on an empty read returns nothing",
      T.parse_carecv("+CARECV: 0,"), b"")

# --------------------------------------------------------------- the CoAP
#
# The expected bytes were decoded by hand against RFC 7252 before being
# compared with the builder's output:
#   42        version 1, type 0 confirmable, token length 2
#   02        code 0.02, POST
#   beef      message id
#   1234      token
#   b5 ...    option delta 11 Uri-Path, length 5, "bench"
#   02 ...    delta 0, length 2, "16"
#   08 ...    delta 0, length 8, "position"
#   ff        payload marker

built = T.coap_build_post("bench/16/position", b"hi", 0xBEEF, b"\x12\x34")
check("a confirmable POST is byte for byte what RFC 7252 describes",
      built.hex(),
      "4202beef1234b562656e636802313608706f736974696f6eff6869")
check("a leading slash in the path adds no empty segment",
      T.coap_build_post("/bench", b"", 1, b""),
      T.coap_build_post("bench", b"", 1, b""))
check("no payload means no payload marker",
      T.coap_build_post("a", b"", 1, b"").hex().endswith("ff"), False)

# The option length extension, which only fires at thirteen and is
# therefore the branch a short test path never reaches. "thirteenchars" is
# exactly thirteen: length nibble 13, then one extension byte of 13 - 13.
option = T.coap_option(T.OPTION_URI_PATH, b"thirteenchars")
# Two bytes of header, not three: the nibble byte and one extension byte.
# The third byte is already the value, which is what the first version of
# this assertion accidentally included.
check("an option of thirteen bytes uses the nibble extension",
      option[:2].hex(), "bd00")
check("an option of twelve bytes does not",
      T.coap_option(T.OPTION_URI_PATH, b"twelvechars!")[:1].hex(), "bc")

ack = F.coap_ack(0xBEEF, b"\x12\x34")
parsed = T.coap_parse(ack)
check_true("an acknowledgement parses as one", parsed["ack"])
check_true("2.04 Changed is a success", parsed["success"])
check("the message id survives the round trip", parsed["message_id"], 0xBEEF)
check("a truncated datagram is refused rather than guessed at",
      T.coap_parse(b"\x42\x02"), None)

schedule = T.coap_retransmit_schedule(base=1.0, count=4)
check("the retransmission schedule has one delay per transmission",
      len(schedule), 4)
check_true("and every delay is twice the one before",
           all(abs(schedule[i + 1] - 2 * schedule[i]) < 1e-9
               for i in range(3)))
check_true("the first delay is randomised inside RFC 7252's factor",
           1.0 <= schedule[0] <= 1.5)


# ------------------------------------------------------- the state machine


class FakePort:
    """The scenario tables of fake-modem.py, without a pty.

    This is the same table the pty test serves, reached through a different
    door, which is the point: if the two ever disagree about what the modem
    said, the tables are shared so they cannot.
    """

    def __init__(self, scenario):
        self.modem = F.FakeModem(scenario)
        self.pending = []
        self.sent = []

    def command(self, text, timeout=10.0, collect=None):
        self.sent.append(text)
        lines = self.modem.handle(text)
        if lines == ["PROMPT"]:
            # This used to return ([], "OK"), answering a send prompt as
            # if it were a result line. The pty transport cannot do that:
            # command() there reads until OK or ERROR, and a modem sitting
            # at "> " sends neither, so it times out. This stub said OK,
            # 75 checks passed, and the first run over a real pty failed
            # on the first send with "no final result for
            # 'AT+CASEND=0,53' in 5s". A stub that is kinder than the
            # transport it stands in for hides exactly the defect the
            # transport would show. Now it refuses the same way.
            raise T.AtTimeout("no final result for %r: the modem answered "
                              "with a send prompt, which command() does "
                              "not read. Use prompt_command." % text)
        out = [line for line in lines if line not in ("OK", "ERROR")]
        if "ERROR" in lines:
            raise T.AtError("%s -> ERROR" % text)
        for line in out:
            if line.startswith("+CADATAIND"):
                self.pending.append(line)
        return [line for line in out
                if not line.startswith("+CADATAIND")], "OK"

    def prompt_command(self, text):
        # The one command whose answer is a prompt. The fake's table says
        # PROMPT for it, and anything else here is the stub and the pty
        # test disagreeing about what the modem said, which the shared
        # table exists to prevent.
        self.sent.append(text)
        lines = self.modem.handle(text)
        if lines != ["PROMPT"]:
            raise T.AtError("%s -> %s, expected a send prompt"
                            % (text, lines))

    def send_raw(self, payload, timeout=10.0):
        self.pending.extend(self.modem.take_datagram(payload))
        return "OK"

    def read_line(self, deadline):
        while self.pending:
            line = self.pending.pop(0)
            if line.startswith("+CADATAIND"):
                return line
        return None

    def close(self):
        pass


class Gpio:
    """The PATH seam, recorded rather than run."""

    def __init__(self):
        self.calls = []

    def pwrkey_pulse(self):
        self.calls.append("pwrkey")

    def mark(self, high):
        self.calls.append("mark %s" % ("1" if high else "0"))


def drive(scenario, conf=None):
    settings = dict(T.DEFAULTS)
    settings.update({
        "apn": "bench.test",
        "coap_host": "198.51.100.7",
        "attach_timeout_s": "5",
        "attach_poll_s": "0.01",
        "at_timeout_s": "1",
        "ack_timeout_s": "0.01",
        "max_retransmit": "2",
        # Seventeen hours, which no scenario grants. An assertion on the
        # granted value cannot then pass by matching the request.
        "psm_tau": "00110001",
    })
    settings.update(conf or {})
    port = FakePort(scenario)
    gpio = Gpio()
    machine = T.Tracker(settings, port, gpio=gpio, log=lambda m: None)
    machine.power_on()
    machine.wait_ready(timeout=2.0)
    if machine.state == "FAILED":
        return machine, port, gpio
    machine.configure()
    machine.attach()
    if machine.state == "FAILED":
        return machine, port, gpio
    machine.read_psm()
    machine.report(b"1,2")
    return machine, port, gpio


machine, port, gpio = drive("happy")
check("happy ends REGISTERED, acknowledged", machine.state, "REGISTERED")
check("happy pulsed PWRKEY through the seam", gpio.calls[0], "pwrkey")
check("the granted TAU is decoded, not echoed from the request",
      machine.granted["tau_s"], 8 * 3600)
check("and it is not the seventeen hours that were asked for",
      machine.granted["tau_s"] == T.decode_tau("00110001"), False)
check("the granted Active-Time is decoded too",
      machine.granted["active_s"], 2)
check_true("2G is locked out before the attach",
           port.sent.index("AT+CNMP=38") < port.sent.index("AT+CEREG?"))
check_true("PSM is requested before the attach, because the request "
           "rides on it",
           [s for s in port.sent if s.startswith("AT+CPSMS=")] and
           port.sent.index(next(s for s in port.sent
                                if s.startswith("AT+CPSMS="))) <
           port.sent.index("AT+CEREG?"))
check_true("the context is deactivated, so the modem may sleep",
           "AT+CNACT=0,0" in port.sent)
check_true("the socket is closed", "AT+CACLOSE=0" in port.sent)

machine, port, gpio = drive("denied")
check("a refused attach reaches FAILED", machine.state, "FAILED")
check_true("and never opens a socket",
           not any(s.startswith("AT+CAOPEN") for s in port.sent))

machine, port, gpio = drive("no-psm")
check("PSM refused still attaches", machine.state, "REGISTERED")
check("and reports no granted TAU at all",
      machine.granted.get("tau_s"), None)
check("the read back mode says plainly that it was refused",
      machine.granted["cpsms"]["mode"], 0)

machine, port, gpio = drive("stingy-psm")
check("a grant smaller than the request is recorded as granted",
      machine.granted["tau_s"], 3600)

machine, port, gpio = drive("slow-attach")
check("a slow attach still gets there", machine.state, "REGISTERED")
check_true("and really did poll more than once",
           port.sent.count("AT+CEREG?") >= 4)

machine, port, gpio = drive("no-ack")
check("an unacknowledged report reaches BACKOFF", machine.state, "BACKOFF")
check_true("and the socket is closed even so",
           "AT+CACLOSE=0" in port.sent)
check_true("and the marker went low again, or the trace has no end edge",
           gpio.calls[-1] == "mark 0")
check_true("the backoff is capped at the report interval",
           machine.backoff_delay() <=
           float(T.DEFAULTS["report_interval_s"]))

# --------------------------------------------------------------- the conf

import tempfile  # noqa: E402  imported here, used only by this section

with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "tracker.conf")
    # The three Windows traps at once: a byte order mark on the first key,
    # CRLF endings, and no final newline. Project 1 lost a board to the
    # third of these, where a plain read loop drops the last key silently.
    with open(path, "wb") as handle:
        handle.write("﻿apn=bench.test\r\ncoap_host=198.51.100.7\r\n"
                     "coap_path=bench/16/position".encode("utf-8"))
    conf = T.read_conf(path)
    check("a byte order mark does not corrupt the first key",
          conf["apn"], "bench.test")
    check("CRLF endings do not end up in the value",
          conf["coap_host"], "198.51.100.7")
    check("a final line with no newline is not dropped",
          conf["coap_path"], "bench/16/position")
    check("an absent file gives the defaults rather than an error",
          T.read_conf(os.path.join(tmp, "nope.conf"))["baud"], "115200")

# ------------------------------------------------------------------ report

for line in FAIL:
    sys.stderr.write("FAIL: %s\n" % line)
print("%d passed, %d failed" % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
