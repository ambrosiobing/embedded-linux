#!/usr/bin/env python3
"""accel-fit.py - per-axis sensitivity and offset from static poses.

    python3 scripts/accel-fit.py POSES.csv [--scale 0.000598205]
    python3 scripts/accel-fit.py POSES.csv --holdout OTHER.csv

POSES.csv is label,x,y,z in raw LSB, one row per static orientation, with
an optional header line. Each row should be the mean of several readings
taken with the board at rest.

WHAT IT USES, WHICH IS ONE FACT AND NOT A JIG

A stationary board's acceleration vector has magnitude g whichever way the
board points. With m the measured triple, s a per-axis sensitivity and b a
per-axis offset:

    a = (m - b) / s        and        |a| = 1 g for every static pose

Six unknowns, one equation per pose. **No pose's orientation has to be
known, estimated or assumed.** That is the point. The obvious alternative,
resolving each pose's tilt from its own components, uses the offsets it is
trying to measure, which is circular; see
projects/10-iio-iks4a1/docs/evidence/accel-gravity-2026-10-25.md, which
does it that way and says so.

WHY THIS IS A LINEAR SOLVE AND NOT AN ITERATION

Expanding the constraint turns it linear in a changed set of unknowns:

    sum_k ((m_k - b_k)/s_k)^2 = 1
    sum_k A_k m_k^2  -  2 sum_k B_k m_k  +  C  =  0
    A_k = 1/s_k^2    B_k = b_k/s_k^2     C = sum_k b_k^2/s_k^2 - 1

Fixing C = -1 makes it an ordinary least squares in six unknowns, then
s_k = 1/sqrt(A_k) and b_k = B_k/A_k. Fixing C = -1 asserts that
sum b^2/s^2 is zero when it is really about 9e-5 for a part like this, so
the solution is refined once: the sensitivities come back a factor
sqrt(1 - k) too SMALL and are corrected upward. The offsets are
unaffected, because b = B/A is invariant under the rescaling.

No iteration, no starting guess, no convergence to check.

WHAT IT CANNOT DO

Three axes with no cross terms, so a real part's off-diagonal sensitivity
is absorbed into the residual rather than reported. The poses must cover
both directions of every axis or that axis's offset is not determined at
all: this refuses rather than returning a number in that case, because the
failure is silent otherwise and the number looks ordinary.

SPDX-License-Identifier: MIT
"""

import csv
import math
import sys


def die(message):
    print("accel-fit: " + message, file=sys.stderr)
    sys.exit(1)


def read_poses(path):
    """label,x,y,z rows. A header line is detected and skipped."""
    rows = []
    try:
        with open(path, newline="") as handle:
            for fields in csv.reader(handle):
                if not fields or fields[0].lstrip().startswith("#"):
                    continue
                if len(fields) < 4:
                    die("%s: need label,x,y,z, got %r" % (path, fields))
                try:
                    triple = [float(v) for v in fields[1:4]]
                except ValueError:
                    continue  # the header
                rows.append((fields[0].strip(), triple))
    except OSError as error:
        die(str(error))
    if not rows:
        die("%s: no usable rows" % path)
    return rows


def solve(matrix, vector):
    """Gaussian elimination with partial pivoting. Six by six here."""
    n = len(vector)
    aug = [list(matrix[i]) + [vector[i]] for i in range(n)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(aug[r][col]))
        if abs(aug[pivot][col]) < 1e-12:
            return None
        aug[col], aug[pivot] = aug[pivot], aug[col]
        for row in range(n):
            if row == col:
                continue
            factor = aug[row][col] / aug[col][col]
            for k in range(col, n + 1):
                aug[row][k] -= factor * aug[col][k]
    return [aug[i][n] / aug[i][i] for i in range(n)]


def spans_both_directions(triples):
    """Every axis must see gravity both ways, or its offset is free.

    Checked as a property of the data rather than of anybody's labels: for
    each axis, is there a pose where it dominates positively and one where
    it dominates negatively. Without that the solve still returns numbers,
    and they are meaningless for that axis.
    """
    missing = []
    for k, axis in enumerate("XYZ"):
        plus = minus = False
        for triple in triples:
            biggest = max(range(3), key=lambda j: abs(triple[j]))
            if biggest != k:
                continue
            if triple[k] > 0:
                plus = True
            else:
                minus = True
        if not (plus and minus):
            missing.append(axis)
    return missing


def fit(triples):
    nominal = max(abs(v) for t in triples for v in t) or 1.0
    scaled = [[v / nominal for v in t] for t in triples]

    # C fixed at -1: sum A m^2 - 2 sum B m = 1
    columns = []
    for m in scaled:
        columns.append([m[0] ** 2, m[1] ** 2, m[2] ** 2,
                        -2 * m[0], -2 * m[1], -2 * m[2]])
    normal = [[sum(r[i] * r[j] for r in columns) for j in range(6)]
              for i in range(6)]
    rhs = [sum(r[i] for r in columns) for i in range(6)]
    answer = solve(normal, rhs)
    if answer is None:
        die("the poses do not determine a solution: they are degenerate,\n"
            "       which usually means too few orientations or several\n"
            "       that are nearly the same")
    for value in answer[:3]:
        if value <= 0:
            die("the solve returned a non-positive 1/s^2, so these poses do\n"
                "       not describe a sensor reading a constant magnitude")

    s = [1.0 / math.sqrt(a) for a in answer[:3]]
    b = [answer[3 + k] / answer[k] for k in range(3)]

    # The one refinement, and its SIGN is the thing to get right.
    #
    # Fixing C = -1 asserts that sum b^2/s^2 is zero. Writing k for its
    # true value, the solve returns s' = s * sqrt(1 - k), which is SMALLER
    # than the truth, so recovering s means dividing rather than
    # multiplying. Only the primed values are in hand, and
    # k' = sum (b/s')^2 relates to k by k' = k/(1 - k), which rearranges
    # to the form used here, s = s' * sqrt(1 + k').
    #
    # This multiplied by sqrt(1 - k) when it was first written on Monday
    # 26 October 2026, which DOUBLED the error it was meant to remove
    # rather than removing it: a noiseless fixture came back 1.03 LSB low
    # where the uncorrected solve was 0.51 low. tests/accel-fit-test.sh
    # caught it, and only because its tolerance is tight enough to see a
    # bias thirty parts per million wide, far below anything the bench
    # itself could resolve.
    #
    # Offsets need no correction: b = B/A is invariant under the rescaling.
    k = sum((b[i] / s[i]) ** 2 for i in range(3))
    s = [v * math.sqrt(1.0 + k) for v in s]

    return [v * nominal for v in s], [v * nominal for v in b]


def magnitudes(triples, s, b):
    out = []
    for m in triples:
        a = [(m[i] - b[i]) / s[i] for i in range(3)]
        out.append(math.sqrt(sum(v * v for v in a)))
    return out


def main(argv):
    if not argv:
        print(__doc__.split("SPDX")[0].rstrip())
        return 2
    path = argv[0]
    scale = None
    holdout = None
    rest = argv[1:]
    while rest:
        flag = rest.pop(0)
        if flag == "--scale":
            if not rest:
                die("--scale needs a value, the m/s^2 per LSB from "
                    "in_accel_scale")
            scale = float(rest.pop(0))
        elif flag == "--holdout":
            if not rest:
                die("--holdout needs a CSV of poses to predict")
            holdout = rest.pop(0)
        else:
            die("unknown option %r" % flag)

    rows = read_poses(path)
    triples = [t for _, t in rows]
    if len(triples) < 6:
        die("%d poses is not enough: six unknowns need at least six "
            "orientations" % len(triples))
    missing = spans_both_directions(triples)
    if missing:
        die("no pose has %s pointing both ways, so that axis's offset is\n"
            "       not determined. Turn the board over and read it again."
            % " or ".join(missing))

    s, b = fit(triples)
    print("--- poses     %d from %s" % (len(triples), path))
    print("--- axis      sensitivity LSB/g        zero-g offset LSB")
    for i, axis in enumerate("XYZ"):
        print("---   %s         %10.1f                 %+8.1f"
              % (axis, s[i], b[i]))
    if scale:
        g = 9.80665
        print("---")
        print("--- against in_accel_scale %g and standard gravity %g:" %
              (scale, g))
        for i, axis in enumerate("XYZ"):
            print("---   %s    %8.4f m/s2  (%+6.3f %%)   offset %+8.5f m/s2"
                  "  (%+5.2f mg)"
                  % (axis, s[i] * scale, 100 * (s[i] * scale - g) / g,
                     b[i] * scale, 1000 * b[i] * scale / g))

    before = [math.sqrt(sum(v * v for v in t)) for t in triples]
    after = magnitudes(triples, s, b)
    print("---")
    print("--- magnitude spread, which is the thing being flattened:")
    print("---   before  %.1f to %.1f LSB   (%.2f %%)"
          % (min(before), max(before),
             100 * (max(before) - min(before)) / (sum(before) / len(before))))
    print("---   after   %.5f to %.5f g   (%.3f %%)"
          % (min(after), max(after),
             100 * (max(after) - min(after)) / (sum(after) / len(after))))

    if holdout:
        # The check that can fail. Poses the fit never saw, ideally from a
        # different session: if the parameters only absorbed their own
        # data, they will not predict these.
        other = read_poses(holdout)
        predicted = magnitudes([t for _, t in other], s, b)
        print("---")
        print("--- predicting %d held-out poses from %s"
              % (len(other), holdout))
        worst = 0.0
        for (label, _), value in zip(other, predicted):
            worst = max(worst, abs(value - 1))
            print("---   %-20s |a| = %.5f g   %+7.2f mg"
                  % (label[:20], value, 1000 * (value - 1)))
        rms = math.sqrt(sum((v - 1) ** 2 for v in predicted) / len(predicted))
        print("---   worst %.2f mg, rms %.2f mg" % (1000 * worst, 1000 * rms))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
