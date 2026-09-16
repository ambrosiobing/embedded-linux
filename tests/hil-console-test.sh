#!/bin/sh
#
# hil-console-test.sh - the console protocol, without a board.
#
# Everything Project 4's runner does rests on one idea: a serial console
# has no framing, so each command carries a unique end marker and the exit
# status comes back attached to it. That idea is testable on a laptop,
# because Console takes its transport as an argument and a fake can pretend
# to be a Raspberry Pi as convincingly as one needs for this.
#
# What is proven here: that the marker is not matched by the console's own
# echo of the command, that the exit status is read correctly including
# non-zero ones, that the echoed command line is stripped from the output,
# that a timeout says what did arrive, and that the log captures bytes the
# caller never sees.
#
# What is not proven: that a real DUT echoes the way the fake does. Only a
# board shows that, which is what docs/BRINGUP.md is for.
#
#   sh tests/hil-console-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNNER=$ROOT/projects/04-netboot-hil/runner
PYTHON=${PYTHON:-python3}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

"$PYTHON" - "$RUNNER" "$WORK" <<'PYTEST'
import sys
from pathlib import Path

runner, work = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(runner))
from console import Console

passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        print(f"ok       {label}")
        passed += 1
    else:
        print(f"FAILED   {label}: wanted {want!r}, got {got!r}")
        failed += 1


class FakeDut:
    """A board that echoes what it is sent, then answers.

    The echo is the interesting part. A real console echoes the command
    line back before running it, so the marker string appears twice, and a
    naive expect() matches the echo and concludes the command finished
    instantly with no output.
    """

    def __init__(self, replies=None, echo=True, status=0):
        self.replies = dict(replies or {})
        self.echo = echo
        self.status = status
        self.pending = b""
        self.written = []

    def write(self, data):
        self.written.append(data)
        line = data.decode().rstrip("\n")
        command, _, rest = line.partition("; echo ")
        marker = rest.split()[0] if rest else None
        if self.echo:
            self.pending += line.encode() + b"\r\n"
        body = self.replies.get(command)
        if body:
            self.pending += body.encode() + b"\r\n"
        if marker:
            self.pending += f"{marker} {self.status}\r\n".encode()
        self.pending += b"root@dut:~# "

    def read(self, size):
        chunk, self.pending = self.pending[:size], self.pending[size:]
        return chunk

    def close(self):
        pass


def console(dut, log=None):
    return Console("fake://", log=log, opener=lambda url, timeout: dut)


# --------------------------------------------- the echo must not match

dut = FakeDut({"uname -r": "6.6.63-v8"})
c = console(dut)
status, out = c.run("uname -r")
check("the command's own echo does not end the read", out.strip(), "6.6.63-v8")
check("exit status comes back", status, 0)

# --------------------------------------------------- non-zero status

dut = FakeDut({"false": ""}, status=1)
status, _ = console(dut).run("false")
check("a non-zero exit status is not swallowed", status, 1)

dut = FakeDut({"exit 42": ""}, status=42)
status, _ = console(dut).run("exit 42")
check("a status above 1 survives", status, 42)

# ------------------------------------------- multi-line output is whole

dut = FakeDut({"cat /etc/os-release": "NAME=Poky\nVERSION=5.0.20"})
_, out = console(dut).run("cat /etc/os-release")
check("multi-line output is kept whole", out.strip(),
      "NAME=Poky\nVERSION=5.0.20")

# ------------------------------------------- a board that does not echo

dut = FakeDut({"uname -r": "6.6.63-v8"}, echo=False)
_, out = console(dut).run("uname -r")
check("a console without echo still parses", out.strip(), "6.6.63-v8")

# --------------------------------------------------- empty output

dut = FakeDut({"true": ""})
status, out = console(dut).run("true")
check("a command with no output returns empty, not junk", out.strip(), "")
check("and still reports its status", status, 0)

# -------------------------------- output that looks like a shell prompt

# The reason for markers rather than prompt matching, in one case.
dut = FakeDut({"echo hi": "root@dut:~# not really a prompt"})
_, out = console(dut).run("echo hi")
check("output containing a prompt does not truncate the read",
      out.strip(), "root@dut:~# not really a prompt")

# ------------------------------------------------------- the timeout

class Silent:
    def write(self, data):
        pass

    def read(self, size):
        return b""

    def close(self):
        pass


try:
    console(Silent()).expect(b"login: ", timeout=0.3)
    check("a silent board raises TimeoutError", "no exception", "TimeoutError")
except TimeoutError as error:
    check("a silent board raises TimeoutError", type(error).__name__,
          "TimeoutError")
    check("and the message names what it waited for",
          "login" in str(error), True)


class Noisy(Silent):
    def __init__(self):
        self.sent = False

    def read(self, size):
        if self.sent:
            return b""
        self.sent = True
        return b"U-Boot 2024.01\nstarting kernel\n"


try:
    console(Noisy()).expect(b"login: ", timeout=0.3)
    check("a timeout shows the tail", "no exception", "TimeoutError")
except TimeoutError as error:
    check("a timeout shows what did arrive", "starting kernel" in str(error),
          True)

# ------------------------------------------------------------ the log

log = work / "console.log"
dut = FakeDut({"uname -r": "6.6.63-v8"})
c = console(dut, log=str(log))
c.run("uname -r")
c.close()
recorded = log.read_bytes().decode()
check("the log holds the board's own echo", "uname -r" in recorded, True)
check("the log holds the output", "6.6.63-v8" in recorded, True)

# ------------------------------------------------ markers are unique

dut = FakeDut({"true": ""})
c = console(dut)
c.run("true")
c.run("true")
markers = {w.decode().split("; echo ")[1].split()[0] for w in dut.written}
check("every command gets its own marker", len(markers), 2)

print()
print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PYTEST
