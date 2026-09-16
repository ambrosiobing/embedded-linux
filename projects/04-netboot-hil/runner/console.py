#!/usr/bin/env python3
"""Expect-style control of the DUT's serial console, over ser2net.

A serial console has no framing. Output arrives as a stream of bytes, there
is no end-of-message, and a shell prompt is just some characters that
usually turn up at the end. Every console automation problem comes from
that, so this module solves it once: each command carries its own unique
end marker and the exit status comes back with it.

    console = Console()
    rc, out = console.run("uname -r")

The transport is injectable so that the protocol can be tested without a
board, which is most of what can be verified on a laptop. See
tests/hil-console-test.sh.

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import os
import re
import time

DEFAULT_URL = "socket://localhost:4003"


def _open_serial(url: str, timeout: float):
    """Import pyserial lazily so the module can be exercised without it."""
    import serial

    return serial.serial_for_url(url, timeout=timeout)


class Console:
    def __init__(self, url: str = DEFAULT_URL, log: str | None = "console.log",
                 opener=_open_serial, read_timeout: float = 0.2) -> None:
        self.port = opener(url, read_timeout)
        self._sequence = 0
        self.log = open(log, "ab") if log else None

    def close(self) -> None:
        if self.log:
            self.log.close()
            self.log = None
        close = getattr(self.port, "close", None)
        if close:
            close()

    def _record(self, chunk: bytes) -> None:
        # Everything the DUT said, in order, whether or not a test asked for
        # it. When a run fails the question is almost always "what did the
        # board actually print", and an expect() that consumed the answer
        # and then timed out has thrown it away unless this file exists.
        if self.log:
            self.log.write(chunk)
            self.log.flush()

    def expect(self, pattern: bytes | str, timeout: float = 120) -> bytes:
        """Read until pattern matches, and return everything read.

        Raises TimeoutError with the tail of what did arrive, because
        "timed out waiting for login:" is not a diagnosis and the last few
        hundred bytes usually are.
        """
        if isinstance(pattern, str):
            pattern = pattern.encode()
        buffer, deadline = b"", time.monotonic() + timeout
        while time.monotonic() < deadline:
            chunk = self.port.read(4096)
            if not chunk:
                continue
            buffer += chunk
            self._record(chunk)
            if re.search(pattern, buffer):
                return buffer
        tail = buffer[-400:].decode(errors="replace")
        raise TimeoutError(
            f"no match for {pattern!r} within {timeout}s. Last bytes:\n{tail}"
        )

    def send(self, line: str) -> None:
        self.port.write(line.encode() + b"\n")

    def run(self, command: str, timeout: float = 30) -> tuple[int, str]:
        """Run one command, return its exit status and its output.

        The marker carries the exit status, and that detail is load-bearing
        rather than decorative.

        A console echoes what is typed, so the marker appears twice: once in
        the echo of the command line and once in the output. The echo reads

            uname -r; echo __END_3412_7__ $?

        with a literal "$?", because the shell has not expanded anything
        yet. The pattern below requires digits after the marker, so it
        cannot match the echo and only matches the real end. Loosen it to
        just the marker and every command appears to finish instantly, with
        empty output, which looks like a dead board rather than a bug here.
        """
        # A counter and the process id, not a timestamp. The first version
        # used time.monotonic_ns(), which looks unique and is not: the
        # monotonic clock has a resolution of about 15 ms on some hosts, so
        # two commands issued in quick succession got the same marker. The
        # rsplit below then finds the *previous* command's marker still in
        # the buffer and returns its output as this one's. A sequence
        # number cannot collide with itself, and the pid keeps two runners
        # on one console from colliding with each other.
        self._sequence += 1
        marker = f"__END_{os.getpid()}_{self._sequence}__"

        self.send(f"{command}; echo {marker} $?")
        raw = self.expect(rf"{marker} (\d+)".encode(), timeout)
        text = raw.decode(errors="replace")

        # rsplit, not split: with an echoing console the first occurrence is
        # the echo of the command line, and the last is the real end.
        body, tail = text.rsplit(marker, 1)
        status = int(tail.split()[0])

        # If the marker is still in what is left, the console echoed the
        # command and that echo is not output. Drop everything up to the
        # end of the echoed line.
        #
        # Only if. The first version dropped the first line unconditionally,
        # which is right for an echoing console and silently eats the first
        # line of real output on one that does not echo. ser2net can be
        # configured either way and a board in a strange state may stop
        # echoing without saying so.
        if marker in body:
            body = body.rsplit(marker, 1)[1]
            body = body.split("\n", 1)[1] if "\n" in body else ""
        return status, body

    def login(self, user: str, password: str | None = None,
              timeout: float = 60) -> None:
        """Get from a login prompt to a shell prompt.

        Separate from the fixture because logging in is the one step that
        differs between images: a bench image with debug-tweaks has no
        password at all, and Raspberry Pi OS wants one.
        """
        self.expect(rb"login: ", timeout)
        self.send(user)
        if password is not None:
            self.expect(rb"[Pp]assword: ", 15)
            self.send(password)
        self.expect(rb"[#$] ", 30)
