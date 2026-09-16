#!/usr/bin/env python3
"""Assertions about hardware rather than about software.

The loopback is the one test in this repository that cannot pass without a
wire being physically present, which is why it is here. Pull the jumper and
it fails; that is the point, and it is one of the project's acceptance
criteria.

SPDX-License-Identifier: MIT
"""

import time

import pytest

SERVER_INPUT = 23  # server pin 16, the receiving end of the loopback
DUT_OUTPUT = 17    # DUT pin 11. A different board's GPIO17, not the server's


@pytest.fixture
def loopback_in():
    """The server's end of the loopback wire, as an input."""
    gpiod = pytest.importorskip("gpiod")
    from gpiod.line import Direction

    config = {SERVER_INPUT: gpiod.LineSettings(direction=Direction.INPUT)}
    try:
        with gpiod.request_lines("/dev/gpiochip0", consumer="bench-hil",
                                 config=config) as request:
            yield request
    except OSError as error:
        pytest.skip(f"cannot request GPIO{SERVER_INPUT}: {error}")


def _dut_drive(dut, value):
    """Hold a line on the DUT at a value, and return when it is settled.

    libgpiod v2 releases a line when the program that requested it exits,
    so "gpioset 17=1" sets the line and immediately gives it back. The
    backgrounded sleep is what holds the request open long enough for the
    other board to read it. This is the same property lte-gpio's
    flight-hold relies on in Project 15, met from the other side.
    """
    dut.run(f"gpioset -t0 -c gpiochip0 {DUT_OUTPUT}={value} & sleep 0.3")
    time.sleep(0.1)


def test_gpio_loopback(dut, loopback_in):
    from gpiod.line import Value

    _dut_drive(dut, 1)
    assert loopback_in.get_value(SERVER_INPUT) == Value.ACTIVE, (
        "the DUT drove GPIO17 high and the server read low. Either the "
        "jumper is out, or the 1 kOhm resistor is open, or the two boards "
        "have no common ground"
    )

    dut.run("pkill gpioset")
    _dut_drive(dut, 0)
    assert loopback_in.get_value(SERVER_INPUT) == Value.INACTIVE
    dut.run("pkill gpioset")


def test_i2c_bus_present(dut):
    rc, _ = dut.run("test -e /dev/i2c-1")
    assert rc == 0, "no /dev/i2c-1; the i2c-dev module or the overlay is missing"


def test_gpio_chip_present(dut):
    rc, out = dut.run("gpiodetect")
    assert rc == 0 and "gpiochip0" in out
