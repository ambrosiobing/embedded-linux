#!/usr/bin/env python3
"""Plot the latency histograms this bench produces, as a standalone SVG.

    scripts/rt-plot.py -o FIG.svg FILE[:LABEL] [FILE[:LABEL] ...]

The three instruments write three files per run and all three have the same
shape: comment lines beginning with "#", then one "<bin> <count>" pair per
occupied bin.

    rt-toggle            LABEL-toggle.txt          bin_us count
    rt-analyze --hist    LABEL-external-hist.txt   deviation_us count
    cyclictest -h        LABEL-cyclictest.txt      latency_us count

So one parser reads all three, which is the only reason this script is
short. If a fourth instrument arrives, make it write that shape too rather
than teaching this file a second format.

**The count axis is logarithmic and there is no option to make it linear.**
That is a statement about the data, not a preference. On the first smoke
run 4413 of 10000 cyclictest samples sat in a single bin and 99.6 percent
were under 30 us, so a linear axis renders one spike and a flat line, and
the flat line is the whole argument: the tail out to 100 us is what a
real-time kernel is for. An axis that hides the finding is not a default.

Bins with no samples are drawn at the baseline rather than skipped, because
a gap in a sparse file means zero and joining across it would invent a
slope that the data does not have.

The output embeds no timestamp and no input path, so regenerating a figure
from unchanged inputs gives a byte-identical file and a rebuilt figure does
not show up as a diff.

SPDX-License-Identifier: MIT
"""

import argparse
import math
import os
import sys

# Two categorical hues, checked for colour-vision deficiency separation
# against the light surface this SVG paints for itself. Assigned in fixed
# order, never cycled: a third and fourth series take the later entries,
# and a fifth is a sign that the figure should be two figures.
SERIES_COLOURS = ["#2a78d6", "#eb6834", "#3f8f4a", "#8a5cd0"]

INK = "#1f2328"
MUTED = "#57606a"
GRID = "#d8dee4"
SURFACE = "#ffffff"

WIDTH = 720
HEIGHT = 360
MARGIN_LEFT = 62
MARGIN_RIGHT = 18
MARGIN_TOP = 42
MARGIN_BOTTOM = 52


class PlotError(Exception):
    """Anything that should reach the user as a message, not a traceback."""


def read_histogram(path):
    """Return {bin: count} for one instrument file.

    Every line that is not a comment must be two numbers. A line that is
    not is an error rather than something to skip: silently ignoring
    unparseable lines is how a plot of half a file comes to look like a
    plot of the file.
    """
    bins = {}
    try:
        handle = open(path, "r", encoding="ascii", errors="replace")
    except OSError as error:
        # A missing or unreadable file is the commonest way to call this
        # wrongly, usually a label typed into the path or a run whose
        # results were never copied back. It gets the same one-line
        # message as every other refusal rather than a traceback.
        raise PlotError("%s: %s" % (path, error.strerror))
    with handle:
        for number, line in enumerate(handle, start=1):
            text = line.strip()
            if not text or text.startswith("#"):
                continue
            fields = text.split()
            if len(fields) < 2:
                raise PlotError(
                    "%s:%d: expected '<bin> <count>', got %r"
                    % (path, number, text))
            try:
                where = float(fields[0])
                count = int(float(fields[1]))
            except ValueError:
                raise PlotError(
                    "%s:%d: not a number: %r" % (path, number, text))
            if count < 0:
                raise PlotError(
                    "%s:%d: negative count %d" % (path, number, count))
            if count:
                bins[where] = bins.get(where, 0) + count
    if not bins:
        raise PlotError("%s: no occupied bins" % path)
    return bins


def infer_step(bins):
    """The bin width, taken from the data rather than from a flag.

    cyclictest and rt-toggle use 1 us, rt-analyze defaults to 2. Reading it
    off the smallest gap between occupied bins means the caller does not
    have to know which file they handed over, and a file with one occupied
    bin still plots, at width 1.
    """
    keys = sorted(bins)
    gaps = [b - a for a, b in zip(keys, keys[1:]) if b > a]
    if not gaps:
        return 1.0
    return min(gaps)


def parse_input(argument):
    """Split FILE:LABEL, keeping Windows drive letters intact."""
    head, sep, tail = argument.rpartition(":")
    if sep and len(head) > 1 and tail:
        return head, tail
    return argument, os.path.basename(argument)


def nice_ticks(low, high, target=8):
    """Tick positions at 1, 2 or 5 times a power of ten."""
    if high <= low:
        return [low]
    raw = (high - low) / float(target)
    magnitude = 10.0 ** math.floor(math.log10(raw))
    for multiple in (1.0, 2.0, 5.0, 10.0):
        if raw <= magnitude * multiple:
            step = magnitude * multiple
            break
    first = math.ceil(low / step) * step
    ticks = []
    value = first
    while value <= high + step * 0.001:
        ticks.append(round(value, 10))
        value += step
    return ticks


def escape(text):
    return (text.replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def build_svg(series, title, xlabel):
    """series is a list of (label, {bin: count}) in draw order."""
    plot_width = WIDTH - MARGIN_LEFT - MARGIN_RIGHT

    # A legend needs a band of its own. Without this the legend swatches
    # are drawn 4 px below the x axis label and overlap it, which the
    # first real figure showed and no test would have: every assertion
    # about the legend asks whether it is present, and it was.
    margin_bottom = MARGIN_BOTTOM + (20 if len(series) > 1 else 0)
    plot_height = HEIGHT - MARGIN_TOP - margin_bottom

    lows = [min(bins) for _, bins in series]
    highs = [max(bins) for _, bins in series]
    steps = [infer_step(bins) for _, bins in series]
    step = min(steps)
    x_low = min(lows)
    x_high = max(highs) + step
    top_count = max(max(bins.values()) for _, bins in series)
    decades = max(1, int(math.ceil(math.log10(top_count + 1))))

    def x_of(value):
        span = x_high - x_low
        if span <= 0:
            span = 1.0
        return MARGIN_LEFT + (value - x_low) / span * plot_width

    def y_of(count):
        # The axis spans decades + 1 bands, not decades, so that a count of
        # one sits a full band above the baseline instead of on it.
        #
        # The obvious mapping, log10(count) over decades, puts one sample at
        # height zero, which is the same place as no samples. The first
        # render of this script lost all four of the tail bins that way: the
        # single samples at 44, 69, 76 and 100 us drew flat along the axis
        # and read as empty. Those four bins are the finding. A scale that
        # cannot distinguish "once" from "never" is the wrong scale for a
        # histogram whose whole subject is rare events.
        if count <= 0:
            return MARGIN_TOP + plot_height
        return (MARGIN_TOP + plot_height
                - (math.log10(count) + 1.0) / (decades + 1.0) * plot_height)

    out = []
    add = out.append
    add('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
        'viewBox="0 0 %d %d" role="img">' % (WIDTH, HEIGHT, WIDTH, HEIGHT))
    add('<title>%s</title>' % escape(title))
    add('<rect width="%d" height="%d" fill="%s"/>' % (WIDTH, HEIGHT, SURFACE))
    add('<text x="%d" y="24" font-family="system-ui,sans-serif" '
        'font-size="14" font-weight="600" fill="%s">%s</text>'
        % (MARGIN_LEFT, INK, escape(title)))

    # Horizontal grid at each decade, drawn first so marks sit above it.
    for decade in range(decades + 1):
        count = 10 ** decade
        y = y_of(count)
        add('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
            'stroke-width="1"/>'
            % (MARGIN_LEFT, y, MARGIN_LEFT + plot_width, y, GRID))
        add('<text x="%.1f" y="%.1f" text-anchor="end" '
            'font-family="system-ui,sans-serif" font-size="11" fill="%s">'
            '%d</text>' % (MARGIN_LEFT - 8, y + 4, MUTED, count))

    for value in nice_ticks(x_low, x_high):
        x = x_of(value)
        label = ("%g" % value)
        add('<text x="%.1f" y="%.1f" text-anchor="middle" '
            'font-family="system-ui,sans-serif" font-size="11" fill="%s">'
            '%s</text>' % (x, MARGIN_TOP + plot_height + 18, MUTED, label))

    add('<line x1="%d" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
        'stroke-width="1"/>'
        % (MARGIN_LEFT, MARGIN_TOP + plot_height, MARGIN_LEFT + plot_width,
           MARGIN_TOP + plot_height, MUTED))

    for index, (label, bins) in enumerate(series):
        colour = SERIES_COLOURS[index % len(SERIES_COLOURS)]
        own_step = infer_step(bins)
        points = []
        baseline = MARGIN_TOP + plot_height
        keys = sorted(bins)
        previous_end = None
        for where in keys:
            start = x_of(where)
            end = x_of(where + own_step)
            if previous_end is not None and start - previous_end > 0.01:
                # A gap in the file is a run of empty bins, so the outline
                # goes down to the baseline and back rather than across.
                points.append((previous_end, baseline))
                points.append((start, baseline))
            elif previous_end is None:
                points.append((start, baseline))
            y = y_of(bins[where])
            points.append((start, y))
            points.append((end, y))
            previous_end = end
        points.append((previous_end, baseline))
        path = " ".join("%.1f,%.1f" % point for point in points)
        add('<polygon points="%s" fill="%s" fill-opacity="0.14"/>'
            % (path, colour))
        add('<polyline points="%s" fill="none" stroke="%s" '
            'stroke-width="2" stroke-linejoin="round"/>' % (path, colour))

    if len(series) > 1:
        # A legend is present whenever identity is not obvious from the
        # title, so colour is never the only thing carrying it.
        x = MARGIN_LEFT
        y = HEIGHT - 12
        for index, (label, _) in enumerate(series):
            colour = SERIES_COLOURS[index % len(SERIES_COLOURS)]
            add('<rect x="%.1f" y="%.1f" width="10" height="10" rx="2" '
                'fill="%s"/>' % (x, y - 9, colour))
            add('<text x="%.1f" y="%.1f" font-family="system-ui,sans-serif" '
                'font-size="11" fill="%s">%s</text>'
                % (x + 15, y, MUTED, escape(label)))
            x += 20 + 7 * len(label)

    add('<text x="%.1f" y="%.1f" text-anchor="middle" '
        'font-family="system-ui,sans-serif" font-size="11" fill="%s">%s</text>'
        % (MARGIN_LEFT + plot_width / 2.0, MARGIN_TOP + plot_height + 36,
           MUTED, escape(xlabel)))
    add('<text x="14" y="%.1f" text-anchor="middle" '
        'font-family="system-ui,sans-serif" font-size="11" fill="%s" '
        'transform="rotate(-90 14 %.1f)">samples (log)</text>'
        % (MARGIN_TOP + plot_height / 2.0, MUTED,
           MARGIN_TOP + plot_height / 2.0))
    add('</svg>')
    return "\n".join(out) + "\n"


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Plot bench latency histograms as a standalone SVG.")
    parser.add_argument("inputs", nargs="+", metavar="FILE[:LABEL]",
                        help="histogram files, in draw order")
    parser.add_argument("-o", "--out", required=True,
                        help="SVG to write")
    parser.add_argument("-t", "--title", default=None,
                        help="figure title (default: the single series' "
                             "label, or 'Latency histogram')")
    parser.add_argument("-x", "--xlabel", default="latency (us)",
                        help="x axis label")
    return parser.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    if len(args.inputs) > len(SERIES_COLOURS):
        raise PlotError(
            "%d series, and only %d hues are assigned. Draw two figures "
            "rather than inventing a colour."
            % (len(args.inputs), len(SERIES_COLOURS)))
    series = []
    for argument in args.inputs:
        path, label = parse_input(argument)
        series.append((label, read_histogram(path)))
    # One series carries no legend, because a legend of one is a label with
    # extra steps. The title carries the identity instead, so a single
    # series defaults its title to its own label. Without this the label
    # was parsed and then drawn nowhere at all, which a test caught only
    # because it looked in the figure rather than at the exit status.
    title = args.title
    if title is None:
        title = series[0][0] if len(series) == 1 else "Latency histogram"

    with open(args.out, "w", encoding="ascii") as handle:
        handle.write(build_svg(series, title, args.xlabel))
    total = sum(sum(bins.values()) for _, bins in series)
    sys.stderr.write("%s: %d series, %d samples\n"
                     % (args.out, len(series), total))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except PlotError as error:
        sys.stderr.write("rt-plot: %s\n" % error)
        sys.exit(1)
