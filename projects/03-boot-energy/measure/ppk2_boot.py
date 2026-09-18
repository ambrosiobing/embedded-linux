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


def boot_complete(batch):
    """True if D0 went high anywhere in this batch of samples.

    ANYWHERE, not "at the end of it". Checking only the last sample of a
    batch, which is the obvious way to write this, drops the marker
    whenever the batch boundary happens to fall after the edge has been
    read into a later position, and the run then times out with a complete
    recording that the script never noticed was complete.
    """
    return any(int(sample[0]) == 1 for sample in batch)


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

    while clock() - started < timeout_s:
        buf = ppk.get_data()
        if buf:
            samples, raw = ppk.get_samples(buf)
            currents.extend(samples)
            batch = list(zip(*ppk.digital_channels(raw)))
            digital.extend(batch)
            if not marker_seen and boot_complete(batch):
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
    with open(path, "w", newline="") as handle:
        writer = csv.writer(handle)
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
