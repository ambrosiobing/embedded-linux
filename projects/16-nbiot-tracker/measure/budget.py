#!/usr/bin/env python3
"""budget.py - the charge one position report costs, from a PPK2 capture.

    budget.py CAPTURE.csv [--marker d0] [--supply-v 3.8]

Reads the capture schema that
projects/03-boot-energy/measure/ppk2_boot.py already writes,
which is t_s, i_ua, d0, d1, d2 at a fixed sample interval. Reusing that
schema rather than inventing one means a capture taken by either project
can be read by either tool, and it is the reason this program exists before
its own capture program does.

WHAT IT REPORTS, AND WHY EACH NUMBER IS THERE.

    charge_mc     the number the project exists to produce. Millicoulombs
                  per report, integrated between the marker's edges.
    duration_s    the interval that was integrated. A charge without the
                  interval it covers is not a measurement, it is a number.
    mean_ma       charge over duration, which is the current a battery
                  sizing calculation actually wants.
    peak_ma       the largest single sample, checked against the
                  instrument's ceiling below.
    idle_ua       the median outside the marker, which is what PSM is
                  supposed to buy. The median and not the mean, because one
                  wake-up in the tail would drag a mean and leave no trace
                  in the figure.

NOTHING HERE ASSUMES THE SAMPLE INTERVAL. It is derived from the t_s column
and then checked for uniformity, and a capture whose interval varies is
refused rather than integrated. Project 8 stated for five documents that
the difference between its two instruments was the cost of a GPIO write,
which turned out to cancel; the habit that catches that class of error is
deriving the relationship rather than asserting it.

THE CEILING CHECK IS ACCEPTANCE CRITERION 7, AND IT REFUSES.

The PPK2 measures to 1 A. Project 3 published a 1233 mA peak and had to
withdraw it, because a sample at the ceiling is not a reading: the real
current was above it by an unknown amount, and the instrument reported the
largest number it can represent. A trace with any sample at the ceiling
cannot be integrated honestly either, since every clipped sample makes the
charge an underestimate. So this program refuses the file and says how many
samples clipped, rather than printing a total that looks fine.

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import argparse
import csv
import statistics
import sys

# The instrument, not the device. Both numbers are Project 3's, recorded
# there from the PPK2's own documentation and from a measurement that had
# to be withdrawn for exceeding the first of them.
PPK2_MAX_UA = 1_000_000.0
# Source-meter mode above this needs the second micro-USB connector, so
# that the PPK2 is not trying to supply the device through the one cable
# that is also its data link.
PPK2_SECOND_CONNECTOR_UA = 400_000.0
# A sample this close to the ceiling is treated as clipped. Not equality:
# an instrument at its limit rarely reports the limit exactly, and a check
# that only catches the exact value is a check that usually misses.
CLIP_FRACTION = 0.99


class Refused(Exception):
    """The capture cannot be integrated honestly. Says why, with numbers."""


def read_capture(path):
    """Rows as (t_s, i_ua, digitals), with the header read by name.

    By name and not by position, because Project 8's results schema was a
    column short of the board's for a while and nothing noticed. A header
    that does not carry the columns this program needs is an error here
    rather than an IndexError three functions later.
    """
    with open(path, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise Refused("%s is empty" % path)
        missing = {"t_s", "i_ua"} - set(reader.fieldnames)
        if missing:
            raise Refused("%s has no %s column; its header is %s"
                          % (path, " or ".join(sorted(missing)),
                             ", ".join(reader.fieldnames)))
        rows = []
        for number, row in enumerate(reader, start=2):
            try:
                rows.append((float(row["t_s"]), float(row["i_ua"]), row))
            except (TypeError, ValueError):
                raise Refused("%s line %d is not numeric: t_s=%r i_ua=%r"
                              % (path, number, row.get("t_s"),
                                 row.get("i_ua")))
    if len(rows) < 2:
        raise Refused("%s has %d sample(s); at least two are needed to "
                      "derive a sample interval" % (path, len(rows)))
    return rows


def sample_interval(rows, tolerance=0.01):
    """Derive dt from the timestamps, and refuse a capture that varies.

    A varying interval is not a rounding problem, it is usually a capture
    that dropped samples, and integrating it with an average dt quietly
    invents the current that was not recorded.
    """
    deltas = [b[0] - a[0] for a, b in zip(rows, rows[1:])]
    first = deltas[0]
    if first <= 0:
        raise Refused("the first two samples are %.9f s apart; timestamps "
                      "must increase" % first)
    worst = max(abs(d - first) / first for d in deltas)
    if worst > tolerance:
        index = max(range(len(deltas)),
                    key=lambda i: abs(deltas[i] - first))
        raise Refused(
            "the sample interval is not uniform: %.9f s at the start and "
            "%.9f s at sample %d, which is %.1f%% apart. A capture that "
            "dropped samples cannot be integrated as if it had not."
            % (first, deltas[index], index + 1, worst * 100))
    return first


def marked_span(rows, marker):
    """The first contiguous run where the marker channel is high.

    The first run and not every run, because one capture is meant to hold
    one report. A file with two is usually two reports in one recording,
    and averaging them would hide exactly the variation the project is
    looking for. The count is reported so that case is visible.
    """
    levels = []
    for _, _, row in rows:
        if marker not in row or row[marker] in (None, ""):
            raise Refused("the capture has no %s column, so there is no "
                          "marker to integrate between. Its columns are %s"
                          % (marker, ", ".join(k for k in row if k)))
        levels.append(row[marker].strip() not in ("0", "", "0.0", "false"))
    if not any(levels):
        raise Refused(
            "%s never goes high in this capture, so there is no report "
            "interval to integrate. Check that marker_gpio is set in "
            "/etc/bench/tracker.conf and that the PPK2's logic channel is "
            "on that pin." % marker)

    runs, start = [], None
    for index, high in enumerate(levels):
        if high and start is None:
            start = index
        elif not high and start is not None:
            runs.append((start, index))
            start = None
    if start is not None:
        runs.append((start, len(levels)))
    return runs, levels


def check_ceiling(rows):
    """Acceptance criterion 7, as a refusal rather than a warning."""
    clipped = [i_ua for _, i_ua, _ in rows
               if i_ua >= PPK2_MAX_UA * CLIP_FRACTION]
    if clipped:
        raise Refused(
            "%d of %d samples are at or above %.0f mA, which is %.0f%% of "
            "the PPK2's 1 A ceiling. Those samples are not readings: the "
            "real current was higher by an unknown amount, so the charge "
            "below them is an underestimate and cannot be published. "
            "Lock the modem out of GPRS with AT+CNMP=38 and capture again."
            % (len(clipped), len(rows),
               PPK2_MAX_UA * CLIP_FRACTION / 1000.0, CLIP_FRACTION * 100))


def analyse(path, marker="d0"):
    rows = read_capture(path)
    check_ceiling(rows)
    dt = sample_interval(rows)
    runs, levels = marked_span(rows, marker)
    start, end = runs[0]

    inside = [i_ua for _, i_ua, _ in rows[start:end]]
    outside = [i_ua for index, (_, i_ua, _) in enumerate(rows)
               if not levels[index]]

    # The rectangle rule, which is what Project 3's analyze.py uses on the
    # same schema. At 100 kS/s against a report lasting seconds the choice
    # between this and the trapezium is far below the instrument's own
    # accuracy, and using the same rule as the sibling project means two
    # numbers from this bench can be compared.
    charge_uc = sum(inside) * dt

    report = {
        "samples": len(rows),
        "sample_dt_s": dt,
        "marker": marker,
        "marked_runs": len(runs),
        "duration_s": (end - start) * dt,
        "charge_mc": charge_uc / 1000.0,
        "mean_ma": (sum(inside) / len(inside)) / 1000.0 if inside else 0.0,
        "peak_ma": max(inside) / 1000.0 if inside else 0.0,
        "idle_ua": statistics.median(outside) if outside else None,
    }
    if report["peak_ma"] * 1000.0 > PPK2_SECOND_CONNECTOR_UA:
        # Reasoning about the setup, not a measurement of it, and labelled
        # as such. Project 3 recorded that source-meter mode above 400 mA
        # needs the PPK2's second micro-USB connector; whether it was
        # actually connected for this capture is not in the file.
        report["note"] = (
            "peak is above 400 mA, where source-meter mode needs the "
            "PPK2's second micro-USB connector. If it was not connected "
            "for this capture, the supply sagged and every number here is "
            "about a different device. This is a reminder, not a reading: "
            "the capture does not record which connectors were in use.")
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="charge per position report, from a PPK2 capture")
    parser.add_argument("capture")
    parser.add_argument("--marker", default="d0",
                        help="the logic channel the report marker is on")
    args = parser.parse_args(argv)

    try:
        report = analyse(args.capture, marker=args.marker)
    except Refused as why:
        sys.stderr.write("budget.py: refusing %s\n  %s\n"
                         % (args.capture, why))
        return 1
    except OSError as why:
        sys.stderr.write("budget.py: %s\n" % why)
        return 1

    note = report.pop("note", None)
    if report["marked_runs"] > 1:
        sys.stderr.write(
            "budget.py: %s goes high %d times in this capture and only the "
            "first is integrated. One capture is meant to hold one report.\n"
            % (report["marker"], report["marked_runs"]))
    for key in ("charge_mc", "duration_s", "mean_ma", "peak_ma", "idle_ua",
                "sample_dt_s", "samples", "marked_runs"):
        value = report[key]
        if value is None:
            print("%-12s (no samples outside the marker)" % key)
        elif isinstance(value, int):
            print("%-12s %d" % (key, value))
        else:
            print("%-12s %.6g" % (key, value))
    if note:
        sys.stderr.write("budget.py: %s\n" % note)
    return 0


if __name__ == "__main__":
    sys.exit(main())
