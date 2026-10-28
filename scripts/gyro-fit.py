#!/usr/bin/env python3
"""gyro-fit.py - gyroscope scale factor and zero-rate offset.

    python3 scripts/gyro-fit.py CAPTURE.csv --bias [--duration SEC]
    python3 scripts/gyro-fit.py CAPTURE.csv --axis x --poses POSES.csv
        --from LABEL --to LABEL [--full-scale DPS] [--still DPS]

--from and --to each take either a label from the pose CSV or three
comma-separated raw LSB values measured at the bench. The calibration
always comes from the CSV; a measured triple is for a propped endpoint
pose that no label names.

Add --scale, the rad/s per LSB from in_anglvel_scale, for a capture made
with iio-decode, whose columns are raw counts. Leave it off for one made
with iio-stream, whose columns are already rad/s. Both are guarded.

CAPTURE.csv is the output of `iio-stream -d lsm6dsv16x_gyro`, whose first
line names the channels, whose rate columns are rad/s and whose timestamp
column is nanoseconds. Columns are found by name, never by position: this
is the first capture in the project to enable the gyroscope's channels
instead of the accelerometer's, so every offset moves.

WHY THERE IS A REFERENCE AT ALL, WHICH IS THE WHOLE DIFFICULTY

A stationary board reads g, so the accelerometer has a standing reference
and needs no jig. Nothing on this bench turns at a known rate, so the
gyroscope has none. Its integral does: gravity's direction in the body
frame is an angle, and a calibrated accelerometer measures it. So a
rotation between two static poses is measured twice, once by integrating
rate and once by the angle between two gravity vectors.

The full argument, the error budget and the confounds are in
projects/10-iio-iks4a1/docs/gyro-method.md, written before any sample was
taken. This program implements it and refuses where that document says it
must.

WHY A THERE-AND-BACK PAIR AND NOT ONE ROTATION

One rotation cannot separate a scale error from a residual bias, exactly
as one accelerometer pose could not separate a gain error from an offset.
With true angle T, scale error e and residual bias b over t1 and t2:

    outward    = (1+e)(+T) + b*t1
    return     = (1+e)(-T) + b*t2
    sum        = b*(t1+t2)             the residual bias
    difference = 2(1+e)T + b*(t1-t2)   the scale, bias free

So the bias is recovered twice, once from the still intervals and once
from the sum, and the two must agree. That is the check that can fail.

WHY IT INTEGRATES ONE SIGNED AXIS AND NOT THE MAGNITUDE

The magnitude of the rate vector is strictly positive, so every wobble
accumulates into it and none of it cancels. A rotation that wanders two
degrees off axis and comes back adds about four degrees of path to a
ninety degree rotation, which is 4.4 per cent against a reference good to
0.035 per cent. The signed single-axis integral lets a there-and-back
excursion cancel to first order, and the other two axes' integrals are
reported as a direct measurement of what the excursion was.

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import importlib.util
import math
import os
import sys

# 360 degrees per sidereal day. This is the only free rate reference in
# the room and it is the floor on any zero-rate offset measured here: a
# board at rest on the bench really is turning this fast.
EARTH_RATE_DPS = 360.0 / 86164.1

# From the method document, which computes it from the accelerometer's
# 0.038 per cent post-calibration agreement and its 0.30 mg noise floor.
# It is the ceiling on the scale factor this method can produce, and it is
# fixed before any gyroscope sample exists.
REFERENCE_ANGLE_DEG = 0.03

DPS_PER_RAD_S = 180.0 / math.pi

# How far each integration window reaches into the still region beyond
# the end of the motion, and how much of each still run is set aside
# before its bias is read. See window() for why the padding exists at
# all; TRIM_S exceeds PAD_S so the two never share a sample.
PAD_S = 0.10
TRIM_S = 0.15


def die(message):
    sys.stderr.write("gyro-fit: %s\n" % message)
    raise SystemExit(1)


def load_accel_fit():
    """Import scripts/accel-fit.py, hyphen and all.

    The reference angle needs the accelerometer calibration, and the one
    thing that must not happen is transcribing those six numbers into this
    file. A transcribed figure is how a stale number survives a
    recalibration, which is the failure this repository keeps meeting in
    prose. So the calibration is refitted from the committed pose CSVs by
    the committed code, every run.
    """
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "accel-fit.py")
    if not os.path.exists(path):
        die("cannot find %s, which holds the accelerometer fit" % path)
    spec = importlib.util.spec_from_file_location("accel_fit", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_capture(path, scale=None):
    """Return (t_seconds, [wx, wy, wz]) in degrees per second.

    WHY THERE IS A SCALE ARGUMENT AT ALL, AND WHEN TO PASS IT.

    The two capture tools in this tree disagree about units and neither
    says so in its header. `iio-stream` applies the channel's scale, so
    its columns are rad/s and no `--scale` is wanted. `iio-decode` looks
    for a per-axis `in_anglvel_x_scale`, which `st_lsm6dsx` does not
    publish: it has one shared `in_anglvel_scale` for all three axes. So
    the decoder falls through to printing raw counts, and the CSV looks
    exactly the same either way.

    Getting that wrong is a factor of about sixteen thousand, which is
    why the caller guards against it rather than trusting the flag.

    The header is the layout. iio-stream prints the channel ids it
    actually enabled, so a capture with the accelerometer channels still
    on, or with an axis disabled, is detected here rather than producing
    plausible nonsense.
    """
    try:
        with open(path) as handle:
            lines = [line.strip() for line in handle if line.strip()]
    except OSError as exc:
        die("cannot read %s: %s" % (path, exc))
    if len(lines) < 2:
        die("%s has %d non-empty lines, so there is nothing to integrate"
            % (path, len(lines)))

    header = [cell.strip() for cell in lines[0].split(",")]
    wanted = {"x": None, "y": None, "z": None, "t": None}
    for index, name in enumerate(header):
        if "timestamp" in name:
            wanted["t"] = index
        for axis in "xyz":
            if name.endswith("anglvel_" + axis) or name == "anglvel_" + axis:
                wanted[axis] = index
    missing = [key for key, value in wanted.items() if value is None]
    if missing:
        die("capture header %r has no column for %s. Enable the three\n"
            "       anglvel channels and the timestamp, then capture again."
            % (",".join(header), ", ".join(sorted(missing))))

    times = []
    rates = [[], [], []]
    for number, line in enumerate(lines[1:], start=2):
        cells = line.split(",")
        if len(cells) != len(header):
            die("%s line %d has %d fields, header has %d"
                % (path, number, len(cells), len(header)))
        try:
            times.append(float(cells[wanted["t"]]) / 1e9)
            for slot, axis in enumerate("xyz"):
                value = float(cells[wanted[axis]])
                if scale is not None:
                    value *= scale
                rates[slot].append(value * DPS_PER_RAD_S)
        except ValueError:
            die("%s line %d is not numeric: %r" % (path, number, line))

    for index in range(1, len(times)):
        if times[index] <= times[index - 1]:
            die("timestamp does not increase at sample %d: %.9f then %.9f.\n"
                "       Integration needs real timestamps in order."
                % (index, times[index - 1], times[index]))
    return times, rates


def magnitude(rates, index, bias=(0.0, 0.0, 0.0)):
    return math.sqrt(sum((rates[axis][index] - bias[axis]) ** 2
                         for axis in range(3)))


def median(values):
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return 0.5 * (ordered[middle - 1] + ordered[middle])


def quantum(series):
    """The smallest step the data actually resolves, read from the data.

    A bias cannot be known better than one quantisation step, and the
    step is not knowable from the flags: an iio-decode capture is in raw
    counts, an iio-stream one in rad/s already multiplied by the
    channel's scale, and the quantum differs by that scale between them.
    The smallest positive gap between distinct values is the step in
    whatever units arrived, which is what the comparison needs.

    Returns 0.0 when every value is identical or the data is noisy
    enough that the gap is meaningless, and 0.0 contributes nothing to
    the tolerance it feeds, which is the right behaviour in both cases.
    """
    seen = sorted(set(series))
    if len(seen) < 2:
        return 0.0
    return min(seen[i + 1] - seen[i] for i in range(len(seen) - 1))


def provisional_bias(rates):
    """A bias estimate good enough to segment with, before the segments
    are known.

    This is not a refinement either. Segmentation originally thresholded
    the raw rate magnitude, and a part whose zero-rate offset exceeds the
    threshold is then never still at any point in the capture: the whole
    recording reads as one long rotation and the program reports three
    moving runs where there are two. A gentle rotation makes this certain
    rather than possible, because the threshold is a fraction of the peak
    and the peak is small.

    The median works because the still intervals are deliberately much
    longer than the rotations, so more than half the samples are at rest
    and the median of each axis is its bias whatever the motion did.
    """
    return [median(rates[axis]) for axis in range(3)]


def segment(times, rates, bias, still_dps, min_still_s, min_move_s):
    """Split the capture into still and moving runs.

    Returns a list of (kind, first, last) with kind "still" or "move".
    Runs shorter than the minimum for their kind are absorbed into their
    neighbour rather than reported, because a single noisy sample above
    the threshold is not a rotation.
    """
    kinds = ["still" if magnitude(rates, i, bias) < still_dps else "move"
             for i in range(len(times))]
    runs = []
    start = 0
    for index in range(1, len(kinds) + 1):
        if index == len(kinds) or kinds[index] != kinds[start]:
            runs.append([kinds[start], start, index - 1])
            start = index

    # A run at the very start that is too short for its kind has no
    # predecessor to be absorbed into, so it must be absorbed forwards.
    # Without this a capture beginning part way into a rotation opens
    # with a few samples below the threshold, and those few samples were
    # then taken as the still interval the bias is read from. The
    # program refused such a capture, but for the wrong reason and with
    # a bias error of ten per cent in the message.
    if len(runs) > 1:
        kind, first, last = runs[0]
        floor = min_still_s if kind == "still" else min_move_s
        if times[last] - times[first] < floor:
            runs[1][1] = first
            runs.pop(0)

    merged = []
    for run in runs:
        kind, first, last = run
        span = times[last] - times[first]
        floor = min_still_s if kind == "still" else min_move_s
        if span < floor and merged:
            merged[-1][2] = last
        else:
            merged.append(run)
    return [(kind, first, last) for kind, first, last in merged]


def trimmed(times, run, trim_s):
    """A still run with trim_s removed from each end.

    The bias is read from what is left. The integration windows are
    allowed to pad into the part removed, so the correction and the
    integral it corrects never share a sample.
    """
    _, first, last = run
    lo, hi = first, last
    while lo < hi and times[lo] - times[first] < trim_s:
        lo += 1
    while hi > lo and times[last] - times[hi] < trim_s:
        hi -= 1
    return lo, hi


def window(times, series, first, last, bias, edge_dps, pad_s, limit):
    """Widen a detected motion until it really has ended.

    THIS IS NOT A REFINEMENT, IT IS THE DIFFERENCE BETWEEN 1.33 AND 1.50
    PER CENT. The first version of this program integrated exactly the
    run of samples above the still threshold, and a synthetic capture
    built from a known 1.500 per cent scale error came back as 1.326.

    A hand rotation starts and ends gradually, so its first and last
    samples sit below any threshold able to reject bias and noise. Those
    tails carry little rate and real area: on the fixture, 0.055 degrees
    at each end of each rotation, which is 0.13 per cent of ninety
    degrees and four times the reference's own accuracy. Truncation is a
    one-sided error and it always reads low.

    Extending to a lower edge threshold shrinks it but does not remove
    it, so the window is also padded into the still region beyond the
    edge. The bias has already been subtracted, so a still sample
    contributes zero in expectation and only its noise in practice. A
    systematic deficit is traded for a random term about forty times
    smaller. `limit` keeps the padding out of the samples the bias was
    measured from, so the correction and the thing it corrects stay
    independent.
    """
    lo, hi = first, last
    while lo > limit[0] and abs(series[lo - 1] - bias) > edge_dps:
        lo -= 1
    while hi < limit[1] and abs(series[hi + 1] - bias) > edge_dps:
        hi += 1
    while lo > limit[0] and times[first] - times[lo] < pad_s:
        lo -= 1
    while hi < limit[1] and times[hi] - times[last] < pad_s:
        hi += 1
    return lo, hi


def integrate(times, series, first, last, bias, stride=1):
    """Trapezoidal and rectangular integrals of one axis, bias removed.

    WHAT THE TWO RULES DO AND DO NOT TELL YOU. An earlier version of this
    program compared them and called the difference a test of whether the
    sample rate had resolved the motion. It is not one. The difference
    telescopes:

        trap - rect = sum 0.5 (a[i+1] - a[i]) dt
                    = 0.5 dt (a[last] - a[first])

    which depends on the two endpoint values and on nothing else in
    between. No curvature, no rate adequacy, nothing about the shape of
    the rotation. What it does test is whether the window begins and ends
    at rest, which is worth knowing and is checked under that name.

    Sample-rate adequacy needs a different question, so `stride` exists:
    integrating the same window on every second sample and comparing is a
    Richardson estimate, since the trapezoid error falls as dt squared
    and decimating by two multiplies it by four.
    """
    trap = 0.0
    rect = 0.0
    index = first
    while index + stride <= last:
        step = times[index + stride] - times[index]
        a = series[index] - bias
        b = series[index + stride] - bias
        trap += 0.5 * (a + b) * step
        rect += a * step
        index += stride
    return trap, rect


def mean(values):
    return sum(values) / len(values)


def stdev(values):
    if len(values) < 2:
        return 0.0
    average = mean(values)
    return math.sqrt(sum((v - average) ** 2 for v in values)
                     / (len(values) - 1))


def allan_deviation(values, dt, taus):
    """Non-overlapping Allan deviation, which needs no reference at all.

    A still capture is enough: the question is how the average of the
    rate wanders as the averaging time grows, and that is a property of
    the part rather than of anything it is compared against.
    """
    out = []
    for tau in taus:
        width = int(round(tau / dt))
        if width < 1 or len(values) // width < 3:
            continue
        bins = [mean(values[i * width:(i + 1) * width])
                for i in range(len(values) // width)]
        diffs = [bins[i + 1] - bins[i] for i in range(len(bins) - 1)]
        out.append((tau, math.sqrt(sum(d * d for d in diffs)
                                   / (2.0 * len(diffs))), len(bins)))
    return out


def retime(times, duration):
    """Replace the driver's timestamps with a uniform grid of the measured
    length, and return the stretch factor that was found.

    THE DRIVER'S TIMESTAMPS ARE NOT REAL TIME ON THIS PART, MEASURED ON
    MONDAY 26 OCTOBER 2026. A capture of 28800 scans whose last sample
    was stamped 1793045626.094 was returned by a read that finished at
    1793045616: ten seconds of timestamp beyond the moment the data
    arrived. A timestamp cannot postdate the read that produced it.

    The error is a constant factor, not a drift. At a nominal 480 Hz the
    interval was 0.002472 s and at 240 Hz exactly 0.004944, double, so
    the stretch is independent of the output data rate: 1.1551 measured
    against the board's own clock to four decimal places.

    This matters more than its size. The method integrates rate against
    time, so a constant error in dt is the same constant error in every
    angle, and it is not separable from the gyroscope's own gain: what
    comes out is the product of the two. 15 per cent is four hundred
    times the reference's 0.035 per cent accuracy.

    So the time base is the duration of the read, measured on the board
    around it, and the timestamps are used only for ordering and for
    finding gaps. /proc/uptime gives 10 ms, which over a 60 second
    capture is 0.017 per cent and below the reference's own accuracy;
    `date` gives 1 s, which is not good enough and is why the first
    attempt at this measurement could not settle it.
    """
    count = len(times)
    observed = times[-1] - times[0]
    step = duration / (count - 1)
    return ([times[0] + index * step for index in range(count)],
            observed / duration if duration else 0.0)


def contiguous_runs(times, tolerance=3.0):
    """Split a capture at its gaps, and return the typical interval too.

    A CAPTURE IS NOT NECESSARILY CONTIGUOUS AND THE FIRST ONE TAKEN WAS
    NOT. Arming a buffer and reading it later hands back the stale ring
    contents first, timestamped when they were captured, then the live
    stream: 512 scans, a 161 second gap, then 28288 contiguous ones. The
    mean of a still capture does not care, but anything that treats the
    samples as evenly spaced does, and the Allan deviation here bins by
    sample count, so it was quietly binning across the gap and labelling
    the result with a tau it did not have.
    """
    steps = [times[i + 1] - times[i] for i in range(len(times) - 1)]
    typical = median(steps) if steps else 0.0
    runs = []
    start = 0
    for index, step in enumerate(steps):
        if typical > 0 and step > tolerance * typical:
            runs.append((start, index))
            start = index + 1
    runs.append((start, len(times) - 1))
    return runs, typical


def report_bias(path, times, rates):
    """A still capture: zero-rate offset, noise, and the Earth."""
    span = times[-1] - times[0]
    dt = span / (len(times) - 1)
    print("--- capture   %s" % path)
    print("--- samples   %d over %.3f s, mean interval %.4f ms (%.1f Hz)"
          % (len(times), span, dt * 1e3, 1.0 / dt))
    peak = max(magnitude(rates, i) for i in range(len(times)))
    print("--- peak |w|  %.4f degrees/s" % peak)
    print("---")
    print("--- axis   zero-rate offset      noise (1 sigma)   vs Earth rate")
    for slot, axis in enumerate("XYZ"):
        bias = mean(rates[slot])
        noise = stdev(rates[slot])
        print("---   %s      %+9.5f degrees/s   %8.5f         %8.1f x"
              % (axis, bias, noise, abs(bias) / EARTH_RATE_DPS))
    print("---")
    print("--- Earth rotates at %.7f degrees/s, which is the floor on any"
          % EARTH_RATE_DPS)
    print("--- offset above. An offset many times larger than it is the")
    print("--- part's own, and this bench cannot see the Earth through it.")
    # The Allan deviation bins by sample count, so it needs evenly
    # spaced samples and gets them only within one contiguous run.
    runs, typical = contiguous_runs(times)
    print("---")
    if len(runs) > 1:
        print("--- NOT CONTIGUOUS: %d runs separated by %d gap(s). The "
              "typical" % (len(runs), len(runs) - 1))
        print("---   interval is %.6f s (%.1f Hz) and the gaps are:"
              % (typical, 1.0 / typical if typical else 0.0))
        for index in range(len(runs) - 1):
            print("---     %.3f s between sample %d and %d"
                  % (times[runs[index + 1][0]] - times[runs[index][1]],
                     runs[index][1], runs[index + 1][0]))
        print("---   The offsets above are means and do not care about a")
        print("---   gap. The deviation below does, so it is computed on")
        print("---   the longest run alone and says which.")
    first, last = max(runs, key=lambda r: r[1] - r[0])
    count = last - first + 1
    print("--- Allan deviation, from this capture alone and no reference,")
    print("--- over %d samples spanning %.3f s at %.6f s"
          % (count, times[last] - times[first], typical))
    print("--- tau (s)    sigma (degrees/s)   bins")
    for slot, axis in enumerate("XYZ"):
        points = allan_deviation(rates[slot][first:last + 1], typical,
                                 [0.1, 1.0, 10.0])
        for tau, sigma, bins in points:
            print("---   %s %7.1f    %12.6f      %4d" % (axis, tau, sigma,
                                                         bins))
    return 0


def reference_angle(poses_path, label_from, label_to, accel_fit):
    """The angle between gravity at two poses, from calibrated readings.

    The calibration is refitted here from the same CSV rather than taken
    as six numbers on the command line, so it cannot go stale.
    """
    rows = accel_fit.read_poses(poses_path)
    triples = [t for _, t in rows]
    if len(triples) < 6:
        die("%s holds %d poses; the accelerometer calibration this "
            "reference\n       depends on needs at least six"
            % (poses_path, len(triples)))
    missing = accel_fit.spans_both_directions(triples)
    if missing:
        die("%s has no pose with %s pointing both ways, so the calibration\n"
            "       behind this reference angle is not determined"
            % (poses_path, " or ".join(missing)))
    sens, offs = accel_fit.fit(triples)

    # An endpoint is either a label in the pose CSV or three numbers
    # measured at the bench. A comma decides which, since the labels are
    # slugs and a triple cannot be one.
    #
    # WHY A MEASURED TRIPLE IS USUALLY THE RIGHT ONE. The labelled poses
    # are those that were stable enough to average during the
    # accelerometer calibration. A gyroscope endpoint has to hold still
    # for a whole still interval, and a board balanced on an edge on this
    # bench does not: one drifted 7.03 degrees in eight seconds on Monday
    # 26 October 2026 while every reading passed the magnitude test,
    # because a slow settle stays in quasi-static equilibrium and keeps
    # |a| equal to g. The magnitude test sees real acceleration and is
    # blind to a slow rotation, so a propped pose, measured at the time,
    # is what an endpoint usually is.
    found = {}
    for wanted in (label_from, label_to):
        if "," in wanted:
            parts = [piece.strip() for piece in wanted.split(",")]
            if len(parts) != 3:
                die("%r has %d comma-separated values, and an endpoint "
                    "triple\n       needs exactly three" % (wanted,
                                                            len(parts)))
            try:
                found[wanted] = [float(piece) for piece in parts]
            except ValueError:
                die("%r is not three numbers" % wanted)
            continue
        for label, triple in rows:
            if label.strip() == wanted.strip():
                found[wanted] = triple
        if wanted not in found:
            die("no pose labelled %r in %s, and it holds no comma so it is\n"
                "       not a triple either. Labels present:\n       %s"
                % (wanted, poses_path,
                   "\n       ".join(label for label, _ in rows)))

    units = {}
    for wanted in (label_from, label_to):
        triple = found[wanted]
        corrected = [(triple[i] - offs[i]) / sens[i] for i in range(3)]
        norm = math.sqrt(sum(v * v for v in corrected))
        # The same magnitude test the calibration poses got. A pose whose
        # corrected magnitude is not g was contaminated by real
        # acceleration, whatever else it looks like.
        if abs(norm - 1.0) > 0.002:
            die("pose %r reads |a| = %.5f g after correction, so it was "
                "moving.\n       It cannot be an endpoint." % (wanted, norm))
        units[wanted] = [v / norm for v in corrected]

    dot = sum(units[label_from][i] * units[label_to][i] for i in range(3))
    dot = max(-1.0, min(1.0, dot))
    return math.degrees(math.acos(dot)), sens, offs



def one_way(path, duration, trust, scale, slot, still_dps, full_scale,
            label):
    """One still-rotate-still capture: its integral, with its own bias.

    Returns a dict. Everything it needs is already in this file; this is
    the two-move analysis in main() with the count changed from two
    moves to one, and the bias and time base handled per capture rather
    than across the pair.
    """
    times, rates = read_capture(path, scale)
    peak_any = max(magnitude(rates, i) for i in range(len(times)))
    if peak_any > 5000.0:
        die("%s: peak %.0f degrees/s is faster than any part here can\n"
            "       report, so these columns are raw counts. Pass --scale."
            % (label, peak_any))

    if duration is not None:
        runs, _ = contiguous_runs(times)
        if len(runs) > 1:
            die("%s: --duration spreads %d samples evenly and this capture\n"
                "       has %d gaps, so they are not evenly spaced."
                % (label, len(times), len(runs) - 1))
        times, stretch = retime(times, duration)
    elif not trust:
        die("%s: needs --duration or --trust-timestamps. This part's\n"
            "       driver timestamps are stretched about 1.156." % label)
    else:
        stretch = 0.0

    dt = (times[-1] - times[0]) / (len(times) - 1)
    rough = provisional_bias(rates)
    peak = max(abs(rates[slot][i] - rough[slot]) for i in range(len(times)))
    if peak < 5.0:
        die("%s: peak on that axis is %.4f degrees/s, which is not a\n"
            "       rotation." % (label, peak))
    thresh = still_dps if still_dps is not None else 0.05 * peak
    runs = segment(times, rates, rough, thresh, 0.5, 0.2)
    moves = [r for r in runs if r[0] == "move"]
    stills = [r for r in runs if r[0] == "still"]

    print("--- %s" % label)
    print("---   samples   %d over %.3f s (%.1f Hz), peak %.2f degrees/s"
          % (len(times), times[-1] - times[0], 1.0 / dt, peak))
    if stretch:
        print("---   time base %.4f s measured, timestamps stretched %.5f"
              % (duration, stretch))
    print("---   segments  %s" % ", ".join(
        "%s %.3f s" % (k, times[b] - times[a]) for k, a, b in runs))

    if len(moves) != 1:
        die("%s: found %d moving runs, not 1. A one-way capture is still,\n"
            "       rotate once, still." % (label, len(moves)))
    if len(stills) != 2:
        die("%s: found %d still runs, not 2. The bias before and after are\n"
            "       what bound the drift the correction could not catch."
            % (label, len(stills)))
    if full_scale is not None and peak > 0.9 * full_scale:
        die("%s: peak %.2f is within 90 per cent of full scale %.1f, so\n"
            "       samples may be clipped." % (label, peak, full_scale))

    first = trimmed(times, stills[0], TRIM_S)
    last = trimmed(times, stills[1], TRIM_S)
    bias_before = mean(rates[slot][first[0]:first[1] + 1])
    bias_after = mean(rates[slot][last[0]:last[1] + 1])
    bias = 0.5 * (bias_before + bias_after)
    drift = abs(bias_after - bias_before)
    sigma = stdev(rates[slot][first[0]:first[1] + 1])
    edge = max(0.002 * peak, 4.0 * sigma, drift)
    position = runs.index(moves[0])
    limit = (trimmed(times, runs[position - 1], TRIM_S)[1] + 1,
             trimmed(times, runs[position + 1], TRIM_S)[0] - 1)
    lo, hi = window(times, rates[slot], moves[0][1], moves[0][2], bias,
                    edge, PAD_S, limit)

    for index in range(lo, hi):
        if times[index + 1] - times[index] > 3.0 * dt * 3.0:
            die("%s: a %.4f s gap sits inside the integration window. That\n"
                "       is lost angle." % (label,
                                           times[index + 1] - times[index]))

    trap, _ = integrate(times, rates[slot], lo, hi, bias)
    half = integrate(times, rates[slot], lo, hi, bias, 2)[0]
    off = []
    for other in range(3):
        if other == slot:
            continue
        o_bias = 0.5 * (mean(rates[other][first[0]:first[1] + 1])
                        + mean(rates[other][last[0]:last[1] + 1]))
        off.append(("XYZ"[other],
                    integrate(times, rates[other], lo, hi, o_bias)[0]))

    span = times[hi] - times[lo]
    print("---   bias      before %+9.5f, after %+9.5f, drift %.5f"
          % (bias_before, bias_after, drift))
    print("---   integral  %+9.4f degrees over %.3f s, mean rate %.1f"
          % (trap, span, abs(trap) / span))
    print("---   rate      trapezoid error %.6f degrees by decimation"
          % (abs(trap - half) / 3.0))
    print("---   off axis  %s" % ", ".join("%s %+.4f" % o for o in off))
    return {"integral": trap, "span": span, "bias": bias, "drift": drift,
            "sigma": sigma, "off": off, "peak": peak,
            "noise_int": sigma * math.sqrt(dt * span),
            "richardson": abs(trap - half) / 3.0}


def main(argv):
    if not argv:
        print(__doc__.split("SPDX")[0].rstrip())
        return 2

    path = argv[0]
    rest = list(argv[1:])
    bias_only = False
    axis = None
    poses = None
    label_from = None
    label_to = None
    full_scale = None
    still_dps = None
    scale = None
    duration = None
    trust = False
    second = None
    second_duration = None
    second_from = None
    second_to = None
    while rest:
        flag = rest.pop(0)
        if flag == "--bias":
            bias_only = True
        elif flag == "--axis":
            axis = rest.pop(0) if rest else die("--axis needs x, y or z")
        elif flag == "--poses":
            poses = rest.pop(0) if rest else die("--poses needs a CSV")
        elif flag == "--from":
            label_from = rest.pop(0) if rest else die("--from needs a label")
        elif flag == "--to":
            label_to = rest.pop(0) if rest else die("--to needs a label")
        elif flag == "--full-scale":
            full_scale = (float(rest.pop(0)) if rest
                          else die("--full-scale needs degrees/s"))
        elif flag == "--second":
            # The return leg, as its own capture. See one_way().
            second = (rest.pop(0) if rest
                      else die("--second needs a capture CSV"))
        elif flag == "--second-from":
            second_from = (rest.pop(0) if rest
                           else die("--second-from needs a label or a triple"))
        elif flag == "--second-to":
            second_to = (rest.pop(0) if rest
                         else die("--second-to needs a label or a triple"))
        elif flag == "--second-duration":
            second_duration = (float(rest.pop(0)) if rest
                               else die("--second-duration needs seconds"))
        elif flag == "--trust-timestamps":
            # The deliberate alternative to --duration: saying out
            # loud that this capture's timestamps are a usable time
            # base. On this part they are not, which is exactly why
            # neither of the two is the default.
            trust = True
        elif flag == "--duration":
            # Wall-clock seconds the read took, measured on the board.
            # See retime() for why the timestamps cannot supply this.
            duration = (float(rest.pop(0)) if rest
                        else die("--duration needs the wall-clock seconds "
                                 "the capture took"))
        elif flag == "--scale":
            # rad/s per LSB, the value of in_anglvel_scale. Pass it for an
            # iio-decode capture, leave it off for an iio-stream one.
            scale = (float(rest.pop(0)) if rest
                     else die("--scale needs the rad/s per LSB from "
                              "in_anglvel_scale"))
        elif flag == "--still":
            still_dps = (float(rest.pop(0)) if rest
                         else die("--still needs degrees/s"))
        else:
            die("unknown option %r" % flag)

    if second is not None:
        if axis not in ("x", "y", "z"):
            die("--axis must be x, y or z, not %r" % axis)
        if not (poses and label_from and label_to):
            die("a scale factor needs a reference angle: --poses with "
                "--from and --to")
        slot = "xyz".index(axis)
        out = one_way(path, duration, trust, scale, slot, still_dps,
                      full_scale, "outward   %s" % path)
        back = one_way(second, second_duration, trust, scale, slot,
                       still_dps, full_scale, "return    %s" % second)
        if out["integral"] * back["integral"] >= 0:
            die("outward %+.4f and return %+.4f have the same sign, so one "
                "of\n       them is not the return leg"
                % (out["integral"], back["integral"]))

        accel_fit = load_accel_fit()
        reference, sens, offs = reference_angle(poses, label_from, label_to,
                                                accel_fit)
        # The return leg's own endpoints. Reversing the first leg's is
        # right only if the board came back to the same pose, which on
        # this bench it does not: two placements on one tilted support
        # measured 13.49 degrees apart.
        ref_back = reference_angle(
            poses, second_from if second_from else label_to,
            second_to if second_to else label_from, accel_fit)[0]
        a, b = abs(out["integral"]), abs(back["integral"])

        # What the two legs should agree to, from their own bias drift and
        # noise. This is the check that can fail, and it is the reason the
        # pair is taken at all now that each leg carries its own bias.
        # A floor matters here for the same reason it did for the two
        # bias routes: built from the drift alone this is zero on a
        # noiseless capture, and a fixture whose two legs differed by
        # 3.15 degrees was accepted because zero is not exceeded. The
        # integral noise is a real limit on how well two legs can agree,
        # and the last term keeps the noiseless case refusing rather
        # than comparing against nothing.
        tol = 3.0 * math.sqrt(
            sum((leg["drift"] * leg["span"]) ** 2 for leg in (out, back))
            + sum(leg["noise_int"] ** 2 for leg in (out, back)))
        tol = max(tol, 1e-6 * reference)
        print("---")
        print("--- outward   %+9.4f degrees" % out["integral"])
        print("--- return    %+9.4f degrees" % back["integral"])
        e_out = a / reference - 1.0
        e_back = b / ref_back - 1.0
        print("--- outward   %.4f degrees measured against %.4f reference, "
              "%+.4f per cent" % (a, reference, 100 * e_out))
        print("--- return    %.4f degrees measured against %.4f reference, "
              "%+.4f per cent" % (b, ref_back, 100 * e_back))
        print("--- the two scale factors differ by %.4f per cent, against "
              "%.4f allowed" % (100 * abs(e_out - e_back),
                                100 * tol / reference))
        if abs(e_out - e_back) * reference > tol:
            die("the two legs give scale factors %.4f and %.4f per cent,\n"
                "       differing by more than the %.4f per cent their own "
                "bias\n       drift and noise allow. One of the four "
                "endpoint poses is\n       not the pose its capture "
                "actually started or ended in."
                % (100 * e_out, 100 * e_back, 100 * tol / reference))

        print("---")
        print("--- poses     %s, calibration refitted: s = %.1f %.1f %.1f"
              % (poses, sens[0], sens[1], sens[2]))
        worst = max(abs(o[1]) for leg in (out, back) for o in leg["off"])
        print("--- off axis  worst %.4f degrees, %.4f per cent of the "
              "smaller angle" % (worst, 100 * worst / min(reference,
                                                          ref_back)))
        print("---")
        print("--- error budget, per cent:")
        print("---   reference      %.4f  and  %.4f"
              % (100 * REFERENCE_ANGLE_DEG / reference,
                 100 * REFERENCE_ANGLE_DEG / ref_back))
        print("---   leg agreement  %.4f" % (100 * abs(e_out - e_back) / 2))
        print("---   wobble bound   %.4f"
              % (100 * worst / min(reference, ref_back)))
        scale_error = 0.5 * (e_out + e_back)
        print("---")
        print("--- the gyroscope reads %+.4f per cent against the "
              "accelerometer" % (100 * scale_error))
        print("--- so a correction of %.6f applies to axis %s"
              % (1.0 / (1.0 + scale_error), axis.upper()))
        return 0

    times, rates = read_capture(path, scale)

    # THE UNIT GUARD. Raw counts fed in as rad/s come out about sixteen
    # thousand times too large, and no real part reaches 4000 degrees/s,
    # so anything past 5000 is not a measurement of this world. Caught
    # here rather than trusted to the flag, because the two capture
    # tools in this tree disagree about units and neither header says.
    peak_any = max(magnitude(rates, i) for i in range(len(times)))
    if peak_any > 5000.0:
        die("peak rate %.0f degrees/s is faster than any part on this bench\n"
            "       can report, so these columns are almost certainly raw\n"
            "       counts. iio-decode prints counts for this device because\n"
            "       st_lsm6dsx has no per-axis in_anglvel_x_scale. Pass\n"
            "       --scale with the value of in_anglvel_scale." % peak_any)

    if duration is not None:
        runs, _ = contiguous_runs(times)
        if len(runs) > 1:
            die("--duration spreads %d samples evenly over %.3f s, and this\n"
                "       capture has %d gaps in it, so they are not evenly\n"
                "       spaced. Capture again, starting the reader straight\n"
                "       after arming the buffer."
                % (len(times), duration, len(runs) - 1))
        times, stretch = retime(times, duration)
        print("--- time base  %.4f s measured on the board, so %.6f s per "
              "sample" % (duration, duration / (len(times) - 1)))
        print("---            the driver's own timestamps span %.4f s, "
              "which is" % (duration * stretch))
        print("---            a stretch of %.5f. They are used for ordering "
              "only." % stretch)

    if bias_only:
        return report_bias(path, times, rates)

    if axis not in ("x", "y", "z"):
        die("--axis must be x, y or z, not %r. It names the axis the board\n"
            "       was turned about; the other two bound the wobble."
            % axis)
    if not (poses and label_from and label_to):
        die("a scale factor needs a reference angle: --poses with --from and\n"
            "       --to, naming two poses in the accelerometer pose CSV")

    slot = "xyz".index(axis)
    span = times[-1] - times[0]
    dt = span / (len(times) - 1)
    rough = provisional_bias(rates)
    peak = max(abs(rates[slot][i] - rough[slot]) for i in range(len(times)))

    # The other half of the unit guard. A capture passed --scale when its
    # columns were already rad/s comes out about sixteen thousand times
    # too small, and the method needs a mean rate above about 50
    # degrees/s for the bias term to be tolerable, so a peak of a few
    # degrees/s is not a rotation whatever else it is.
    if peak < 5.0:
        die("peak rate on %s is %.4f degrees/s, which is not a rotation.\n"
            "       Either the board did not move, or --scale was passed\n"
            "       for a capture whose columns were already rad/s, which\n"
            "       divides everything by about sixteen thousand."
            % (axis.upper(), peak))

    if still_dps is None:
        # Five per cent of the peak, measured from the provisional bias
        # rather than from zero. Well above the part's noise, well below
        # any hand rotation. Overridable, and the segmentation is printed
        # either way so the choice is visible rather than buried.
        still_dps = 0.05 * peak

    runs = segment(times, rates, rough, still_dps, 0.5, 0.2)
    stills = [r for r in runs if r[0] == "still"]
    moves = [r for r in runs if r[0] == "move"]

    print("--- capture   %s" % path)
    print("--- samples   %d over %.3f s, mean interval %.4f ms (%.1f Hz)"
          % (len(times), span, dt * 1e3, 1.0 / dt))
    print("--- axis      %s, peak |w| %.2f degrees/s, still below %.3f"
          % (axis.upper(), peak, still_dps))
    print("--- segments  %s" % ", ".join(
        "%s %.3f s" % (kind, times[last] - times[first])
        for kind, first, last in runs))

    if len(moves) != 2:
        die("found %d moving runs, not 2. The method is one there-and-back\n"
            "       pair in one capture: still, rotate, still, rotate, "
            "still.\n       A single rotation cannot separate scale from "
            "bias." % len(moves))
    if len(stills) < 3:
        die("found %d still runs, not 3. The bias before and the bias after\n"
            "       are what bound the drift the correction could not catch."
            % len(stills))

    if full_scale is None:
        print("--- NOT CHECKED: clipping. Pass --full-scale, from")
        print("---              in_anglvel_scale_available, to check it. A")
        print("---              clipped sample integrates low and reads as")
        print("---              a scale error of the opposite sign to wobble.")
    elif peak > 0.9 * full_scale:
        die("peak %.2f degrees/s is within 90 per cent of full scale %.1f,\n"
            "       so samples may be clipped. Raise the range or turn the\n"
            "       board more slowly." % (peak, full_scale))

    # The bias is read from the interiors of the first and last still
    # runs, trimmed, so that the integration windows padded below cannot
    # reach the samples the correction was derived from.
    first_still = trimmed(times, stills[0], TRIM_S)
    last_still = trimmed(times, stills[-1], TRIM_S)
    bias_before = mean(rates[slot][first_still[0]:first_still[1] + 1])
    bias_after = mean(rates[slot][last_still[0]:last_still[1] + 1])
    bias = 0.5 * (bias_before + bias_after)
    drift = abs(bias_after - bias_before)
    still_sigma = stdev(rates[slot][first_still[0]:first_still[1] + 1])

    print("---")
    print("--- bias on %s   before %+8.5f, after %+8.5f degrees/s, "
          "drift %.5f" % (axis.upper(), bias_before, bias_after, drift))

    # Low enough to catch the tails of the rotation, high enough not to
    # wander off into the still region. Drift belongs in it because the
    # edge of a rotation cannot be located more finely than the bias is
    # known: a capture whose bias moved by d is one in which a sample
    # reading d is indistinguishable from a sample at rest.
    edge_dps = max(0.002 * peak, 4.0 * still_sigma, drift)
    limits = []
    for move in moves:
        position = runs.index(move)
        before = trimmed(times, runs[position - 1], TRIM_S)
        after = trimmed(times, runs[position + 1], TRIM_S)
        limits.append((before[1] + 1, after[0] - 1))

    windows = [window(times, rates[slot], moves[i][1], moves[i][2], bias,
                      edge_dps, PAD_S, limits[i]) for i in (0, 1)]
    print("--- windows   edge %.4f degrees/s, pad %.2f s: detected "
          "%.3f s and %.3f s," % (edge_dps, PAD_S,
                                  times[moves[0][2]] - times[moves[0][1]],
                                  times[moves[1][2]] - times[moves[1][1]]))
    print("---           integrated over %.3f s and %.3f s"
          % (times[windows[0][1]] - times[windows[0][0]],
             times[windows[1][1]] - times[windows[1][0]]))

    if duration is None and not trust:
        die("a scale factor needs a time base. Either --duration, the\n"
            "       capture took, measured on the board around the read.\n"
            "       This part's driver timestamps are stretched by about\n"
            "       1.155, constant across output data rates, and a\n"
            "       constant error in dt is the same error in every angle.\n"
            "       Bracket the read with /proc/uptime, not date: 1 s\n"
            "       resolution cannot settle 0.035 per cent. Or pass "
            "--trust-timestamps to say deliberately that this capture's "
            "own are a usable time base.")

    # A GAP INSIDE A ROTATION IS LOST ANGLE AND CANNOT BE RECOVERED.
    # Trapezoidal integration across one draws a straight line through
    # whatever the board actually did, and during a rotation that is the
    # part of the motion carrying the most rate. The first still capture
    # taken on this bench had a 161 second gap in it, from reading a
    # buffer that had been armed and left, so this is not hypothetical.
    _, typical_step = contiguous_runs(times)
    for lo, hi in windows:
        for index in range(lo, hi):
            step = times[index + 1] - times[index]
            if typical_step > 0 and step > 3.0 * typical_step:
                die("a %.4f s gap sits inside an integration window, where "
                    "the\n       typical interval is %.6f s. That is lost "
                    "angle and no\n       integration recovers it. Capture "
                    "again, starting the reader\n       immediately after "
                    "arming the buffer." % (step, typical_step))

    outward = integrate(times, rates[slot], windows[0][0], windows[0][1],
                        bias)
    back = integrate(times, rates[slot], windows[1][0], windows[1][1], bias)
    t1 = times[windows[0][1]] - times[windows[0][0]]
    t2 = times[windows[1][1]] - times[windows[1][0]]

    print("--- outward   %+9.4f degrees over %.3f s (rectangular %+9.4f)"
          % (outward[0], t1, outward[1]))
    print("--- return    %+9.4f degrees over %.3f s (rectangular %+9.4f)"
          % (back[0], t2, back[1]))

    # Does the window begin and end at rest? If the padding ran into its
    # limit the window is truncated, and a truncated integral always
    # reads low. This is the guard on the defect window() describes.
    ends = []
    for lo, hi in windows:
        ends.append(max(abs(rates[slot][lo] - bias),
                        abs(rates[slot][hi] - bias)))
    print("--- endpoints %.4f and %.4f degrees/s, against an edge of %.4f"
          % (ends[0], ends[1], edge_dps))
    if max(ends) > edge_dps:
        die("an integration window ends at %.4f degrees/s, above the "
            "%.4f edge\n       threshold, so it was cut off before the "
            "rotation had finished.\n       A truncated integral always "
            "reads low. Leave longer still\n       intervals at each end "
            "of the capture." % (max(ends), edge_dps))

    # Was the sample rate enough? Richardson, by decimating the same
    # window. The trapezoid error falls as dt squared, so halving the
    # rate quadruples it and the gap between the two estimates is three
    # times the error of the full-rate one.
    richardson = 0.0
    for index, (lo, hi) in enumerate(windows):
        full = (outward if index == 0 else back)[0]
        half = integrate(times, rates[slot], lo, hi, bias, 2)[0]
        richardson = max(richardson, abs(full - half) / 3.0)
    print("--- rate check %.6f degrees of trapezoid error estimated by "
          "decimation" % richardson)
    if richardson > 0.0005 * 0.5 * (abs(outward[0]) + abs(back[0])):
        die("the trapezoid error is %.5f degrees, over 0.05 per cent, so\n"
            "       %.1f Hz did not resolve this motion. Raise the output\n"
            "       data rate or turn the board more slowly."
            % (richardson, 1.0 / dt))

    if outward[0] * back[0] >= 0:
        die("outward %+.4f and return %+.4f have the same sign, so this is\n"
            "       not a there-and-back pair on axis %s"
            % (outward[0], back[0], axis.upper()))

    measured = 0.5 * (abs(outward[0]) + abs(back[0]))
    bias_from_sum = (outward[0] + back[0]) / (t1 + t2)

    off_axis = []
    for other in range(3):
        if other == slot:
            continue
        o_bias = 0.5 * (
            mean(rates[other][first_still[0]:first_still[1] + 1])
            + mean(rates[other][last_still[0]:last_still[1] + 1]))
        o_out = integrate(times, rates[other], windows[0][0], windows[0][1],
                          o_bias)[0]
        o_back = integrate(times, rates[other], windows[1][0], windows[1][1],
                           o_bias)[0]
        off_axis.append(("XYZ"[other], o_out, o_back))

    accel_fit = load_accel_fit()
    reference, sens, offs = reference_angle(poses, label_from, label_to,
                                            accel_fit)

    print("---")
    print("--- reference %.4f degrees, between %r and %r"
          % (reference, label_from, label_to))
    print("--- from      %s, calibration refitted here: s = %.1f %.1f %.1f"
          % (poses, sens[0], sens[1], sens[2]))
    print("---           b = %+.1f %+.1f %+.1f LSB"
          % (offs[0], offs[1], offs[2]))
    print("--- worth     about %.2f degrees, so %.4f per cent of this angle"
          % (REFERENCE_ANGLE_DEG, 100 * REFERENCE_ANGLE_DEG / reference))

    print("---")
    print("--- off-axis integrals, which bound the wobble:")
    for name, o_out, o_back in off_axis:
        print("---   %s     outward %+8.4f, return %+8.4f degrees"
              % (name, o_out, o_back))
    excess = max(abs(o_out) + abs(o_back) for _, o_out, o_back in off_axis)
    print("---   worst sum %.4f degrees, %.4f per cent of the angle"
          % (excess, 100 * excess / reference))

    mean_rate = measured / (0.5 * (t1 + t2))
    bias_error = drift / mean_rate if mean_rate else float("inf")
    asym = abs(t1 - t2) / max(t1, t2)
    bias_routes = abs(bias_from_sum)

    print("---")
    print("--- bias, two independent routes to one number:")
    print("---   from the still intervals   %+9.5f degrees/s" % bias)
    print("---   from the reversal sum      %+9.5f degrees/s"
          % (bias + bias_from_sum))
    print("---   they differ by             %9.5f, against a drift of %.5f"
          % (bias_routes, drift))
    # The two routes have to agree within what either of them could
    # resolve, and on a noiseless capture that is neither five times a
    # drift of zero nor five times a drift of 1e-16. Comparing two
    # near-zero quantities without a floor refused every clean fixture
    # this program was first given.
    n_still = ((first_still[1] - first_still[0] + 1)
               + (last_still[1] - last_still[0] + 1))
    step = quantum(rates[slot])
    bias_tol = max(5.0 * drift,
                   4.0 * still_sigma / math.sqrt(max(n_still, 1)),
                   0.5 * step,
                   1e-6 * peak)
    print("---   agreeing within            %9.5f is required, from a "
          "quantum of %.5f" % (bias_tol, step))
    if bias_routes > bias_tol:
        die("the two bias routes differ by %.5f degrees/s, more than the\n"
            "       %.5f this capture can resolve, from a drift of %.5f and\n"
            "       a still noise of %.5f. The model is wrong and no scale\n"
            "       factor should be quoted."
            % (bias_routes, bias_tol, drift, still_sigma))

    print("---")
    print("--- error budget, as a fraction of the angle:")
    print("---   reference      %.4f per cent" %
          (100 * REFERENCE_ANGLE_DEG / reference))
    print("---   residual bias  %.4f per cent  (drift %.5f / rate %.1f)"
          % (100 * bias_error, drift, mean_rate))
    print("---   wobble bound   %.4f per cent" % (100 * excess / reference))
    print("---   duration asym  %.4f per cent of t1" % (100 * asym))

    ceiling = REFERENCE_ANGLE_DEG / reference
    if bias_error > 10.0 * ceiling:
        die("the residual bias contributes %.3f per cent, more than ten\n"
            "       times the reference's own %.4f per cent. This run would\n"
            "       report bias and not scale. Turn the board faster: the\n"
            "       bias term is drift divided by mean rate, so a brisk\n"
            "       rotation is what shrinks it."
            % (100 * bias_error, 100 * ceiling))
    if bias_error > ceiling:
        print("--- WARNING: bias-limited, not reference-limited. The bias")
        print("---          term is %.4f per cent against the reference's"
              % (100 * bias_error))
        print("---          %.4f. A faster rotation would improve it."
              % (100 * ceiling))

    scale_error = measured / reference - 1.0
    print("---")
    print("--- measured  %.4f degrees, bias free, from the reversal"
          % measured)
    print("--- reference %.4f degrees" % reference)
    print("--- the gyroscope reads %+.4f per cent against the "
          "accelerometer" % (100 * scale_error))
    print("--- so a correction of %.6f applies to axis %s"
          % (1.0 / (1.0 + scale_error), axis.upper()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
