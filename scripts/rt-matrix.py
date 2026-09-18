#!/usr/bin/env python3
"""Plot a paired results matrix as a standalone SVG.

    scripts/rt-matrix.py -o FIG.svg results.csv
    scripts/rt-matrix.py -o FIG.svg --metric ext_max_us results.csv

One row per configuration, two marks per row: the generic kernel and the
real-time one, at the same isolation, affinity, governor and load. The
question the figure answers is the one the results table asks in numbers,
which is whether the real-time kernel moved the metric at all, and where.

**Every repeat run is drawn, and nothing is averaged.** Four configurations
in the first real matrix were run more than once, and the project's main
caution rests on them: several differences between the two kernels are
smaller than the spread between two runs of the same kernel. A figure that
collapsed repeats to a mean would delete exactly the evidence that makes
the finding honest, and would look more convincing for having done so. The
marks are the runs. Where two marks of one colour sit far apart, the pair
they belong to is not telling you much.

**An unpaired configuration is refused.** A row with one arm is not a
comparison, and a figure that quietly drew it would invite the reader to
compare it against the row above. The message names the configuration and
the missing arm; the fix is another run, not a flag.

Columns are read by name, never by position. The schema is 28 wide and has
already been wrong once: a shipped results.csv was a column short of what
the board writes, which is harmless until something reads by index and then
is a silent shift across every column after the second.

The output embeds no timestamp and no input path, so regenerating from an
unchanged results.csv gives a byte-identical file and a rebuilt figure is
not a diff.

SPDX-License-Identifier: MIT
"""

import argparse
import csv
import sys

from svgkit import (GRID, INK, MUTED, SERIES_COLOURS, escape, header,
                    nice_ticks, non_ascii)

# The columns this figure cannot be drawn without. Named here rather than
# discovered, so a renamed column fails with a sentence instead of with a
# KeyError halfway through drawing.
REQUIRED = ("label", "realtime", "isolated", "affinity", "governor", "load")

WIDTH = 720
MARGIN_LEFT = 196
MARGIN_RIGHT = 24
MARGIN_TOP = 44
MARGIN_BOTTOM = 62

ROW_HEIGHT = 32
GROUP_GAP = 24

# Each arm sits on its own half of the row rather than both on the centre
# line. This is not decoration and it was not the first attempt.
#
# Drawn on one line, two runs that agree land on the same coordinate and the
# second mark covers the first: the reader sees one dot and cannot tell a
# coincidence from a missing run. The rows where that happens are the rows
# where the two kernels agree, which is the finding. The figure was hiding
# its own argument, and no assertion in the test caught it because every
# assertion asked whether a mark was present, and it was.
#
# Offset, the pair always shows two marks, and the connector between them
# carries the meaning: near vertical is no effect, a long diagonal is a
# large one.
ARM_OFFSET = 7

ARMS = ("no", "yes")
ARM_NAMES = {"no": "generic", "yes": "PREEMPT_RT"}


class PlotError(Exception):
    """Anything that should reach the user as a message, not a traceback."""


def read_rows(path, metric):
    """Return the CSV as a list of dicts, with the metric already a float."""
    try:
        handle = open(path, "r", encoding="ascii", errors="replace",
                      newline="")
    except OSError as error:
        raise PlotError("%s: %s" % (path, error.strerror))
    with handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise PlotError("%s: no header line" % path)
        missing = [name for name in REQUIRED + (metric,)
                   if name not in reader.fieldnames]
        if missing:
            raise PlotError(
                "%s: no column named %s. The header has: %s"
                % (path, ", ".join(missing), ", ".join(reader.fieldnames)))
        rows = []
        # start=2 because the header is line 1, so a reported line number is
        # the one an editor shows.
        for number, row in enumerate(reader, start=2):
            raw = (row.get(metric) or "").strip()
            if not raw:
                raise PlotError("%s:%d: %s is empty" % (path, number, metric))
            try:
                row[metric] = float(raw)
            except ValueError:
                raise PlotError(
                    "%s:%d: %s is not a number: %r"
                    % (path, number, metric, raw))
            for name in ("realtime", "isolated", "affinity", "load"):
                if row[name] not in ARMS:
                    raise PlotError(
                        "%s:%d: %s is %r, wanted yes or no"
                        % (path, number, name, row[name]))
            rows.append(row)
    if not rows:
        raise PlotError("%s: no data rows" % path)
    return rows


def configuration(row):
    """The key a generic row and a real-time row share.

    Everything except which kernel ran. Two rows with the same key are the
    same experiment on different kernels, which is the whole basis of the
    figure.
    """
    return (row["isolated"], row["affinity"], row["governor"], row["load"])


def describe(key):
    """A short, readable name for a configuration."""
    isolated, affinity, governor, load = key
    knobs = []
    if isolated == "yes":
        knobs.append("iso")
    if affinity == "yes":
        knobs.append("aff")
    parts = [" + ".join(knobs)] if knobs else []
    parts.append(governor)
    parts.append("load" if load == "yes" else "idle")
    return ", ".join(parts)


def group(rows, metric):
    """Configurations in first-appearance order, each with both arms.

    First appearance rather than sorted, because results.csv is written in
    the order the runs happened and that order is somebody's afternoon. A
    sort would reorder the figure whenever a governor is renamed.
    """
    order = []
    found = {}
    for row in rows:
        key = configuration(row)
        if key not in found:
            found[key] = {"no": [], "yes": []}
            order.append(key)
        found[key][row["realtime"]].append(row[metric])

    unpaired = []
    for key in order:
        for arm in ARMS:
            if not found[key][arm]:
                unpaired.append((key, arm))
    if unpaired:
        lines = ["no %s run for %r" % (ARM_NAMES[arm], describe(key))
                 for key, arm in unpaired]
        raise PlotError(
            "every configuration needs both kernels, and %d does not:\n       %s"
            % (len(unpaired), "\n       ".join(lines)))
    return [(key, found[key]) for key in order]


def build_svg(pairs, title, xlabel):
    """pairs is [(configuration key, {arm: [values]})] in draw order."""
    # The isolated configurations are banded together and captioned,
    # because "isolation first, the kernel second" is the finding and a
    # figure that leaves the reader to notice the grouping has buried it.
    bands = []
    for isolated in ARMS:
        members = [pair for pair in pairs if pair[0][0] == isolated]
        if members:
            bands.append((isolated, members))

    rows = sum(len(members) for _, members in bands)
    plot_height = rows * ROW_HEIGHT + (len(bands) - 1) * GROUP_GAP
    height = MARGIN_TOP + plot_height + MARGIN_BOTTOM
    plot_width = WIDTH - MARGIN_LEFT - MARGIN_RIGHT

    every = [value for _, arms in pairs for arm in ARMS for value in arms[arm]]
    # The axis starts at zero and is not asked to be clever about it. These
    # are latencies, zero is a real quantity rather than a convention, and
    # an axis that starts at the smallest sample makes a 2 percent
    # difference look like the width of the page.
    high = max(every) * 1.05
    ticks = nice_ticks(0.0, high)

    def x_of(value):
        return MARGIN_LEFT + value / high * plot_width

    out = header(WIDTH, height, title, 24)
    add = out.append

    for value in ticks:
        x = x_of(value)
        add('<line x1="%.1f" y1="%d" x2="%.1f" y2="%.1f" stroke="%s" '
            'stroke-width="1"/>'
            % (x, MARGIN_TOP, x, MARGIN_TOP + plot_height, GRID))
        add('<text x="%.1f" y="%.1f" text-anchor="middle" '
            'font-family="system-ui,sans-serif" font-size="11" fill="%s">'
            '%g</text>' % (x, MARGIN_TOP + plot_height + 18, MUTED, value))

    y = MARGIN_TOP
    for index, (isolated, members) in enumerate(bands):
        if index:
            y += GROUP_GAP
        caption = ("CPU 3 isolated" if isolated == "yes"
                   else "CPU 3 in the general pool")
        add('<text x="24" y="%.1f" font-family="system-ui,sans-serif" '
            'font-size="11" font-weight="600" fill="%s">%s</text>'
            % (y - 6, INK, escape(caption)))

        for key, arms in members:
            middle = y + ROW_HEIGHT / 2.0
            add('<text x="%d" y="%.1f" text-anchor="end" '
                'font-family="system-ui,sans-serif" font-size="11" '
                'fill="%s">%s</text>'
                % (MARGIN_LEFT - 12, middle + 4, INK, escape(describe(key))))

            # The joining line runs between the two arms' means, so the
            # pair reads as one comparison, while the marks stay individual
            # runs. Mean here is a drawing device and never a claim: no
            # number in this figure is an average of anything.
            centres = [sum(arms[arm]) / float(len(arms[arm])) for arm in ARMS]
            add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                'stroke-width="1.5"/>'
                % (x_of(centres[0]), middle - ARM_OFFSET,
                   x_of(centres[1]), middle + ARM_OFFSET, GRID))

            for position, arm in enumerate(ARMS):
                colour = SERIES_COLOURS[position]
                cy = middle + (ARM_OFFSET if position else -ARM_OFFSET)
                for value in sorted(arms[arm]):
                    add('<circle cx="%.1f" cy="%.1f" r="4.5" fill="%s" '
                        'fill-opacity="0.85"/>'
                        % (x_of(value), cy, colour))
            y += ROW_HEIGHT

    add('<line x1="%d" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
        'stroke-width="1"/>'
        % (MARGIN_LEFT, MARGIN_TOP + plot_height, MARGIN_LEFT + plot_width,
           MARGIN_TOP + plot_height, MUTED))
    add('<text x="%.1f" y="%.1f" text-anchor="middle" '
        'font-family="system-ui,sans-serif" font-size="11" fill="%s">%s</text>'
        % (MARGIN_LEFT + plot_width / 2.0, MARGIN_TOP + plot_height + 36,
           MUTED, escape(xlabel)))

    # Identity is never colour alone, so both arms are named.
    x = MARGIN_LEFT
    baseline = height - 12
    for position, arm in enumerate(ARMS):
        name = ARM_NAMES[arm]
        add('<rect x="%.1f" y="%.1f" width="10" height="10" rx="2" '
            'fill="%s"/>' % (x, baseline - 9, SERIES_COLOURS[position]))
        add('<text x="%.1f" y="%.1f" font-family="system-ui,sans-serif" '
            'font-size="11" fill="%s">%s</text>'
            % (x + 15, baseline, MUTED, escape(name)))
        x += 20 + 7 * len(name)
    add('</svg>')
    return "\n".join(out) + "\n"


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Plot a paired results matrix as a standalone SVG.")
    parser.add_argument("results", metavar="RESULTS.CSV",
                        help="a results.csv the board wrote")
    parser.add_argument("-o", "--out", required=True, help="SVG to write")
    parser.add_argument("-m", "--metric", default="ext_p999_us",
                        help="the column to plot (default: ext_p999_us)")
    parser.add_argument("-t", "--title", default=None,
                        help="figure title (default: names the metric)")
    parser.add_argument("-x", "--xlabel", default=None,
                        help="x axis label (default: the metric and its unit)")
    return parser.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    rows = read_rows(args.results, args.metric)
    pairs = group(rows, args.metric)

    title = args.title
    if title is None:
        title = "%s, generic against PREEMPT_RT" % args.metric
    xlabel = args.xlabel
    if xlabel is None:
        xlabel = ("%s (us)" % args.metric if args.metric.endswith("_us")
                  else args.metric)

    drawing = build_svg(pairs, title, xlabel)
    bad = non_ascii(drawing)
    if bad is not None:
        raise PlotError(
            "the figure text carries %r (U+%04X) and a figure is written as "
            "ASCII. A dash or a quote pasted out of a document is the usual "
            "cause; check --title and --xlabel." % (bad, ord(bad)))

    # newline="\n" rather than the platform default. See the same line in
    # rt-plot.py: text mode on Windows writes CRLF, which makes a figure
    # regenerated there differ from the committed one in every line while
    # git quietly normalises the difference away on commit.
    with open(args.out, "w", encoding="ascii", newline="\n") as handle:
        handle.write(drawing)
    runs = sum(len(arms[arm]) for _, arms in pairs for arm in ARMS)
    sys.stderr.write("%s: %d configurations, %d runs\n"
                     % (args.out, len(pairs), runs))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except PlotError as error:
        sys.stderr.write("rt-matrix: %s\n" % error)
        sys.exit(1)
