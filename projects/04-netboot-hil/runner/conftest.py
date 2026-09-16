#!/usr/bin/env python3
"""Fixtures: deploy a build, reboot the DUT, log in, hand over a console.

One session fixture does the whole cycle once and every test then costs a
second or two. The tests themselves read like a checklist, which is the
shape worth aiming for: a test that has to know how to reboot a board is a
test nobody writes a second one of.

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "server"))

import leds  # noqa: E402
from console import Console  # noqa: E402

# Overridable so a run can point at a second DUT or a deployment that has
# already happened, without editing anything.
CONSOLE_URL = os.environ.get("HIL_CONSOLE", "socket://localhost:4003")
DUT_USER = os.environ.get("HIL_USER", "root")
DUT_PASSWORD = os.environ.get("HIL_PASSWORD") or None
SKIP_DEPLOY = os.environ.get("HIL_SKIP_DEPLOY") == "1"


def pytest_addoption(parser):
    parser.addoption(
        "--no-reboot",
        action="store_true",
        help="use the DUT as it is; do not deploy or reboot it",
    )


@pytest.fixture(scope="session")
def dut(request):
    """A logged-in console on a freshly network-booted DUT."""
    here = Path(__file__).resolve().parent

    if not (SKIP_DEPLOY or request.config.getoption("--no-reboot")):
        subprocess.run(["sh", str(here / "deploy.sh")], check=True)

    leds.set("yellow")
    console = Console(CONSOLE_URL, log=str(here / "console.log"))

    if not request.config.getoption("--no-reboot"):
        _reboot(console)
        # The line the whole project exists to see. If this times out, the
        # answer is in the dnsmasq journal rather than here: either the
        # offer never arrived, or a TFTP file is missing, or the export is
        # not reachable. docs/netboot-flow.md walks the eight steps.
        console.expect(rb"Mounted root \(nfs filesystem\)", timeout=120)

    console.login(DUT_USER, DUT_PASSWORD)

    yield console

    # Green or red stays lit until the next run, which is the whole value
    # of an indicator: it answers "how did the last run go" without anyone
    # opening a terminal. It is also the part that is deferred on this
    # bench, so leds.set says so once and returns False.
    leds.set("green" if request.session.testsfailed == 0 else "red")
    console.close()


def _reboot(console: Console) -> None:
    """Ask the DUT to reboot, and say plainly when a human is needed.

    The bench has no relay, no switched hub and no smart plug, so this is a
    soft reboot over the console. It works because the boot ROM runs on
    every reset, so the board re-enters network boot rather than looking
    for a card it does not have.

    What it cannot do is recover a DUT wedged badly enough not to answer
    its own console. That case is the one manual step in the loop, and it
    is printed rather than hidden so the run log can count how many of
    twenty boots needed a hand.
    """
    console.send("")
    try:
        console.expect(rb"login: |[#$] ", timeout=8)
    except TimeoutError:
        print("\n*** DUT is not answering its console. Power-cycle it now."
              "\n*** This is the lab's known manual step; record it in the"
              " run log.\n", flush=True)
        return
    console.send("reboot")
