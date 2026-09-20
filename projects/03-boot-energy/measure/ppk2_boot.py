#!/usr/bin/env python3
"""ppk2_boot.py - record one boot of the NanoPi NEO Air with the PPK2.

    ppk2_boot.py PORT OUT.csv [--timeout 60] [--tail 0.5]

PORT is the PPK2's serial port: COM5 or similar on the Windows host, where
this program runs, because that is where the PPK2 is attached.

CLOSE THE POWER PROFILER DESKTOP APP FIRST. It holds the port open, and the
failure is an unhelpful "access denied" from the serial layer rather than
anything mentioning the app.

THE ORDER OF THE FIRST FOUR CALLS IS THE MEASUREMENT.

    power OFF  ->  settle  ->  start_measuring  ->  power ON

Recording has to begin while the board is still off, or sample zero is
somewhere inside the BROM and t=0 means nothing. Every phase time in this
project is measured from that sample, so an ordering mistake here does not
produce an error, it produces a whole table of numbers that are wrong by an
unknown constant. The settle wait is there for the same reason: a board
whose rails have not discharged does not run its BROM again.

This is the same shape of defect as Project 8's rt-capture, where setting a
thread priority after starting the scan raised the wrong thread. It is
tested the same way: with a stub that records the calls it receives, so the
order is observable with no PPK2 and no board.

SPDX-License-Identifier: MIT
"""

import argparse
import csv
import sys
import time

SAMPLE_DT = 1e-5          # 100 kS/s
SOURCE_MV = 5000          # source-meter setting, millivolts
SETTLE_S = 2.0            # let the board discharge before recording
DIGITAL = ("d0", "d1", "d2")


def rising_edge(batch, previous):
    """Find a LOW to HIGH transition on D0. Returns (found, last_level).

    A LEVEL IS NOT AN EVENT, and on this board the difference decides
    whether a capture is a boot or a fraction of one.

    D0 is PA6. Watched through a whole power cycle on 20 September, it
    goes HIGH, then LOW, then HIGH:

        high   nothing owns the pin yet, through BROM, SPL and U-Boot
        low    the kernel's gpio-leds driver probes and applies
               default-state = "off" from the device tree
        high   boot-marker.service writes brightness, which is the event
               this project measures

    The first version of this asked whether D0 was high anywhere in a
    batch. That is true in the very first batch, so the capture would have
    stopped about half a second after power on with a CSV holding the
    beginning of a boot, and analyze.py would have reported a boot that
    completed before the kernel started.

    Carrying `previous` across batches is what makes the edge detectable
    at a batch boundary; an edge is a property of two samples and those
    two are not always delivered together. previous is None until the
    first sample is seen, so a capture that opens with D0 already high
    waits for it to fall before any rise can count.
    """
    found = False
    for sample in batch:
        level = int(sample[0])
        if previous == 0 and level == 1:
            found = True
        previous = level
    return found, previous


def record_boot(ppk, timeout_s=60.0, tail_s=0.5, clock=time.monotonic,
                sleep=time.sleep):
    """Power-cycle the board and stream until D0 rises. Returns the samples.

    ppk is injected rather than constructed here so that the call order can
    be asserted without hardware. clock and sleep likewise, so a test does
    not spend a minute of wall time proving a timeout.
    """
    ppk.get_modifiers()
    ppk.use_source_meter()
    ppk.set_source_voltage(SOURCE_MV)

    ppk.toggle_DUT_power("OFF")
    sleep(SETTLE_S)
    ppk.start_measuring()
    ppk.toggle_DUT_power("ON")

    currents, digital = [], []
    started = clock()
    marker_seen = False
    tail_until = None

    # None, not 0. An unknown starting level is not a low one, and
    # assuming low would turn "D0 was already high when we started
    # looking" into a rising edge that never happened.
    d0_level = None

    while clock() - started < timeout_s:
        buf = ppk.get_data()
        if buf:
            samples, raw = ppk.get_samples(buf)
            currents.extend(samples)
            batch = list(zip(*ppk.digital_channels(raw)))
            digital.extend(batch)
            found, d0_level = rising_edge(batch, d0_level)
            if not marker_seen and found:
                marker_seen = True
                tail_until = clock() + tail_s
        if tail_until is not None and clock() >= tail_until:
            break
        sleep(0.01)

    ppk.toggle_DUT_power("OFF")
    ppk.stop_measuring()
    return currents, digital, marker_seen


def write_csv(path, currents, digital):
    """One row per sample. Truncated to the shorter of the two streams.

    They can differ by a sample or two at a batch boundary, and zipping
    silently would hide a larger mismatch, so the count that was written is
    returned and the caller reports it.
    """
    n = min(len(currents), len(digital))
    # lineterminator is given explicitly because the csv module's default
    # is "\r\n", not "\n". The pair of newline="" and csv.writer is the
    # documented idiom and it produces a CRLF file on every platform,
    # which for a measurement file written on a Linux board is wrong: a
    # reader doing "head -n 1" gets a trailing carriage return, and the
    # mismatch prints identically to what it wanted, so the diagnostic
    # looks like a tool that cannot compare two equal strings.
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["t_s", "i_ua"] + list(DIGITAL))
        for i in range(n):
            writer.writerow(["%.5f" % (i * SAMPLE_DT),
                             "%.1f" % float(currents[i])]
                            + [int(v) for v in digital[i][:len(DIGITAL)]])
    return n


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("port")
    p.add_argument("out")
    p.add_argument("--timeout", type=float, default=60.0)
    p.add_argument("--tail", type=float, default=0.5)
    args = p.parse_args(argv)

    # Imported here and not at the top, so that the pure parts of this file
    # can be tested on a machine that has never seen a PPK2. The package
    # has renamed its digital-channel helpers between releases; if this
    # import or a call below fails, check the installed version against
    # measure/requirements.txt before changing anything else.
    from ppk2_api.ppk2_api import PPK2_API

    ppk = PPK2_API(args.port)
    currents, digital, marker_seen = record_boot(
        ppk, timeout_s=args.timeout, tail_s=args.tail)

    n = write_csv(args.out, currents, digital)
    print("samples %d  wrote %s" % (n, args.out))

    if not marker_seen:
        # Not an average-it-in situation. analyze.py would discard this run
        # anyway; saying so here saves reading the CSV to find out why.
        print("D0 never rose within %.0f s: the startup job queue did not "
              "empty, so this run is not a measurement and analyze.py will "
              "discard it." % args.timeout, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
