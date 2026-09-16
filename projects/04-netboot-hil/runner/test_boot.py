#!/usr/bin/env python3
"""Did the right image boot, over the network, without complaint.

Four assertions, each a line of shell on the DUT. That is the shape a
hardware in the loop test should have: the fixture knows how to reach the
board, and the test knows one fact about it.

SPDX-License-Identifier: MIT
"""

from pathlib import Path

BUILD = Path(__file__).resolve().parent / "build"


def test_root_is_nfs(dut):
    """The point of the lab. A DUT booted from a forgotten card passes
    every other test in this file and proves nothing."""
    rc, out = dut.run("findmnt -n -o FSTYPE /")
    assert rc == 0
    assert out.strip() == "nfs"


def test_no_local_disk_was_used(dut):
    """Stronger than the above: there is no card in the slot at all.

    findmnt says what is mounted now; this says the board never had the
    option. mmcblk0 absent means the SD controller found no card.
    """
    rc, _ = dut.run("test -e /dev/mmcblk0")
    assert rc != 0, "an SD card is present in the DUT; remove it"


def test_kernel_is_the_one_we_deployed(dut):
    """Guards against the deploy step being a no-op.

    deploy.sh writes the release string it copied; if the DUT reports a
    different one, the TFTP directory and the NFS export have drifted
    apart, which is a real failure mode when one rsync succeeds and the
    other does not.
    """
    release = BUILD / "kernel-release"
    if not release.exists():
        import pytest
        pytest.skip("no build/kernel-release; run deploy.sh first")
    rc, out = dut.run("uname -r")
    assert rc == 0
    assert release.read_text().strip() in out


def test_no_failed_units(dut):
    rc, out = dut.run("systemctl --failed --no-legend | wc -l")
    assert rc == 0
    assert out.strip() == "0"
