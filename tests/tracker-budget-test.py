#!/usr/bin/env python3
"""tracker-budget-test - the charge arithmetic, against traces with known answers.

The synthesised traces here have answers that were worked out first and
written into the assertions before the program was run against them, which
is the only order in which a test can disagree with the code. The arithmetic
is deliberately in round numbers so it can be checked by hand:

    1000 samples at 10 us is 0.01 s
    100 mA held for 0.01 s is 1 mC

If either of those two lines is wrong the whole suite is wrong, and they are
short enough to argue with.

The refusals get as much attention as the arithmetic, because the refusals
are what this program is mostly for. A charge figure from a clipped trace,
or from a capture that dropped samples, is worse than no figure: it is a
number, it has units, and nothing about it looks wrong.

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

loader = importlib.machinery.SourceFileLoader(
    "budget", os.path.join(ROOT, "projects", "16-nbiot-tracker", "measure",
                           "budget.py"))
spec = importlib.util.spec_from_file_location("budget", loader.path,
                                              loader=loader)
B = importlib.util.module_from_spec(spec)
spec.loader.exec_module(B)

DT = 1e-5  # 100 kS/s, the PPK2's rate and Project 3's SAMPLE_DT

PASS = []
FAIL = []


def check(what, got, want, tolerance=1e-9):
    ok = (abs(got - want) <= tolerance
          if isinstance(want, float) and isinstance(got, (int, float))
          else got == want)
    (PASS if ok else FAIL).append(
        what if ok else "%s\n      wanted: %r\n      got:    %r"
        % (what, want, got))


def check_refuses(what, path, marker="d0", because=""):
    try:
        B.analyse(path, marker=marker)
    except B.Refused as why:
        if because and because not in str(why):
            FAIL.append("%s\n      refused, but not for the stated reason."
                        "\n      wanted text: %r\n      said:        %s"
                        % (what, because, why))
        else:
            PASS.append(what)
        return
    except Exception as why:  # noqa: BLE001  a wrong exception is a failure
        FAIL.append("%s\n      raised %s instead of refusing: %s"
                    % (what, type(why).__name__, why))
        return
    FAIL.append("%s\n      it did not refuse" % what)


def write_capture(path, samples, dt=DT, header="t_s,i_ua,d0,d1,d2",
                  times=None):
    """samples is a list of (i_ua, d0). d1 and d2 are written as zero."""
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(header + "\n")
        for index, (i_ua, d0) in enumerate(samples):
            t = times[index] if times else index * dt
            handle.write("%.5f,%.1f,%d,0,0\n" % (t, i_ua, d0))


def trace_one_report(idle_ua=10.0, active_ua=100_000.0, marked=1000,
                     lead=500, tail=500):
    """Idle, then one marked report, then idle again.

    By hand: 1000 marked samples at 100000 uA and 1e-5 s is
    1000 * 100000 * 1e-5 = 1e6 uC / 1000 = 1 mC, over 0.01 s, so a mean of
    100 mA and a peak of 100 mA. Outside the marker every sample is 10 uA,
    so the median idle is 10 uA.
    """
    return ([(idle_ua, 0)] * lead + [(active_ua, 1)] * marked
            + [(idle_ua, 0)] * tail)


with tempfile.TemporaryDirectory() as tmp:
    # ------------------------------------------------------- the arithmetic
    path = os.path.join(tmp, "one-report.csv")
    write_capture(path, trace_one_report())
    got = B.analyse(path)

    check("one report costs 1 mC", got["charge_mc"], 1.0, 1e-9)
    check("over an interval of 10 ms", got["duration_s"], 0.01, 1e-9)
    check("at a mean of 100 mA", got["mean_ma"], 100.0, 1e-9)
    check("with a peak of 100 mA", got["peak_ma"], 100.0, 1e-9)
    check("and 10 uA outside it", got["idle_ua"], 10.0, 1e-9)
    check("the sample interval is derived, not assumed",
          got["sample_dt_s"], DT, 1e-12)
    check("all 2000 samples were read", got["samples"], 2000)
    check("and the marker went high once", got["marked_runs"], 1)

    # Halving the current halves the charge and nothing else. A scaling
    # assertion catches the class of error where a constant has been
    # folded in somewhere: the absolute check above would pass just as
    # happily with the wrong unit conversion if the trace were chosen to
    # suit it.
    half = os.path.join(tmp, "half.csv")
    write_capture(half, trace_one_report(active_ua=50_000.0))
    got_half = B.analyse(half)
    check("half the current is half the charge",
          got_half["charge_mc"], 0.5, 1e-9)
    check("and the same duration", got_half["duration_s"], 0.01, 1e-9)

    # Doubling the duration doubles the charge.
    longer = os.path.join(tmp, "longer.csv")
    write_capture(longer, trace_one_report(marked=2000))
    check("twice as long is twice the charge",
          B.analyse(longer)["charge_mc"], 2.0, 1e-9)

    # The idle median, against a tail that has one wake-up in it. A mean
    # would be dragged by the spike; the median is why this column is a
    # median. By hand: 999 samples at 10 uA and one at 500000 uA has a
    # median of 10 and a mean of about 510.
    spiky = os.path.join(tmp, "spiky.csv")
    samples = trace_one_report(tail=999)
    samples.append((500_000.0, 0))
    write_capture(spiky, samples)
    got_spiky = B.analyse(spiky)
    check("the idle figure is a median, so one wake-up does not move it",
          got_spiky["idle_ua"], 10.0, 1e-9)

    # A second marked run is reported rather than silently averaged in.
    twice = os.path.join(tmp, "twice.csv")
    write_capture(twice, trace_one_report() + trace_one_report(lead=0))
    got_twice = B.analyse(twice)
    check("two reports in one capture are counted",
          got_twice["marked_runs"], 2)
    check("and only the first is integrated",
          got_twice["charge_mc"], 1.0, 1e-9)

    # --------------------------------------------------------- the refusals
    #
    # Acceptance criterion 7. Project 3 published a 1233 mA peak against an
    # instrument rated to 1 A and had to withdraw it. One sample is enough.
    clipped = os.path.join(tmp, "clipped.csv")
    samples = trace_one_report()
    samples[700] = (1_200_000.0, 1)
    write_capture(clipped, samples)
    check_refuses("a trace with one clipped sample is refused, not totalled",
                  clipped, because="ceiling")

    # And just below the threshold is not refused, so the check has a
    # boundary rather than a slope. 989 mA is under 99% of 1 A; 991 is over.
    near = os.path.join(tmp, "near.csv")
    samples = trace_one_report()
    samples[700] = (989_000.0, 1)
    write_capture(near, samples)
    try:
        B.analyse(near)
        PASS.append("a peak just below the ceiling is still integrated")
    except B.Refused as why:
        FAIL.append("a peak just below the ceiling is still integrated\n"
                    "      but it refused: %s" % why)

    over = os.path.join(tmp, "over.csv")
    samples = trace_one_report()
    samples[700] = (991_000.0, 1)
    write_capture(over, samples)
    check_refuses("and just above it is refused", over, because="ceiling")

    # A capture that dropped samples. The timestamps jump at sample 700,
    # which an average dt would smooth over and integrate as if the missing
    # current had been zero.
    gappy = os.path.join(tmp, "gappy.csv")
    times = [i * DT for i in range(2000)]
    for i in range(700, 2000):
        times[i] += 0.05
    write_capture(gappy, trace_one_report(), times=times)
    check_refuses("a capture with a gap in it is refused",
                  gappy, because="not uniform")

    # A marker that never goes high. This is the ordinary first-run
    # failure, and the message has to name the configuration key, because
    # the cause is almost always marker_gpio being unset.
    flat = os.path.join(tmp, "flat.csv")
    write_capture(flat, [(10.0, 0)] * 100)
    check_refuses("a capture with no marker is refused",
                  flat, because="marker_gpio")

    # The wrong channel named. Different from the above: the column is not
    # there at all, and saying "never goes high" would send the reader to
    # the wiring instead of to the argument.
    path_d0 = os.path.join(tmp, "one-report.csv")
    check_refuses("a channel the capture does not have is refused by name",
                  path_d0, marker="d7", because="no d7 column")

    # A header that does not carry the current column.
    wrong = os.path.join(tmp, "wrong-header.csv")
    write_capture(wrong, [(10.0, 0)] * 100,
                  header="time,current,d0,d1,d2")
    check_refuses("a capture with the wrong header is refused, by name",
                  wrong, because="i_ua")

    # One sample cannot give an interval, and saying so beats dividing by
    # zero three functions later.
    single = os.path.join(tmp, "single.csv")
    write_capture(single, [(10.0, 1)])
    check_refuses("a one sample capture is refused", single,
                  because="sample interval")

    empty = os.path.join(tmp, "empty.csv")
    open(empty, "w", encoding="utf-8").close()
    check_refuses("an empty file is refused", empty, because="empty")

    # Non-numeric data, which is what a half-written capture looks like
    # when the recording process was interrupted.
    torn = os.path.join(tmp, "torn.csv")
    with open(torn, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("t_s,i_ua,d0,d1,d2\n0.00000,10.0,0,0,0\n"
                     "0.00001,,0,0,0\n")
    check_refuses("a truncated capture is refused with its line number",
                  torn, because="line 3")

for line in FAIL:
    sys.stderr.write("FAIL: %s\n" % line)
print("%d passed, %d failed" % (len(PASS), len(FAIL)))
sys.exit(1 if FAIL else 0)
