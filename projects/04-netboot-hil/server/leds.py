#!/usr/bin/env python3
"""Status indication for a test run: yellow running, green pass, red fail.

Optional by design. This bench's LED parts are Joy-IT LinkerKit LK-LED10
modules with a 2.0 mm socket that standard 2.54 mm jumper wires cannot mate
with, which is the same blocker Project 1 recorded. So nothing here may be
allowed to fail a test run: if there is no GPIO chip, or the lines are
busy, or libgpiod is not installed, this says so once and carries on.

That is a deliberate inversion of the usual rule. Most of this repository
treats a skipped check as a failure, because a check that silently does
nothing is worse than no check. An indicator lamp is the exception: it
reports a result, it does not produce one. The result is the pytest exit
status, the JUnit XML and the console log, all of which exist whether or
not anything is wired to the header.

Written against the libgpiod v2 Python bindings, which is what Raspberry Pi
OS Bookworm packages as python3-libgpiod.

    python3 leds.py yellow
    python3 leds.py off

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import sys

# Server header lines, from the wiring table in docs/DESIGN.md. These are
# the server's GPIOs; the DUT's GPIO17 is a different pin on a different
# board that happens to share a number.
LINES = {"yellow": 27, "green": 17, "red": 22}

CHIP = "/dev/gpiochip0"  # the 40-pin header on a Pi 4; gpiochip4 on a Pi 5


def _unavailable(why: str) -> None:
    print(f"leds: {why}, indication skipped", file=sys.stderr)


def set(state: str) -> bool:
    """Light one lamp and extinguish the others. True if anything happened.

    The return value exists so a caller can record in the run log whether
    the lamps were actually driven, rather than leaving a reader to wonder
    why a green LED is not mentioned.
    """
    if state != "off" and state not in LINES:
        raise ValueError(f"unknown state {state!r}, want one of "
                         f"{sorted(LINES)} or 'off'")
    try:
        import gpiod
        from gpiod.line import Direction, Value
    except ImportError:
        _unavailable("python3-libgpiod is not installed")
        return False

    wanted = {
        name: Value.ACTIVE if name == state else Value.INACTIVE
        for name in LINES
    }
    config = {
        offset: gpiod.LineSettings(
            direction=Direction.OUTPUT,
            output_value=wanted[name],
        )
        for name, offset in LINES.items()
    }

    try:
        # The request is released as soon as this returns, which turns the
        # lines back into inputs and extinguishes the lamps. Holding them
        # would mean a daemon; instead the caller sets a state and the
        # lamps follow only while something holds the request, which for a
        # test session is the fixture in conftest.py.
        with gpiod.request_lines(CHIP, consumer="bench-hil", config=config):
            pass
    except (OSError, PermissionError) as error:
        _unavailable(f"{CHIP}: {error}")
        return False
    return True


def main(argv: list[str] | None = None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    if len(arguments) != 1:
        print(__doc__.strip().splitlines()[0], file=sys.stderr)
        print("usage: leds.py yellow|green|red|off", file=sys.stderr)
        return 2
    try:
        set(arguments[0])
    except ValueError as error:
        print(f"leds: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
