"""The pieces every figure generator in this repository needs.

Not a drawing library. This holds the four things that would otherwise be
written twice, and stops there:

    the palette          so two figures beside each other agree on what
                         "the real-time series" looks like
    escape               XML escaping, which is wrong in a different way
                         every time it is rewritten
    nice_ticks           tick positions at 1, 2 or 5 times a power of ten
    header               the opening element, the background and the
                         heading, which are byte-identical in both

Deliberately absent: axis emitters. `rt-plot.py` has a logarithmic count
axis and `rt-matrix.py` has a categorical one, and a shared axis function
that served both would take more flags than either needs. A shared helper
that has to be told what to be is two functions wearing one name.

The reason this file exists at all is decision 59. That decision was
written because the same "pick the newest build output" bug was written
five times, each fixed where it was found and nowhere else. Copying an XML
escaper into a second generator is the same mistake with a different
subject, and the second copy is where the ampersand gets forgotten.

Everything here is pure stdlib, and every caller writes ASCII, so a figure
is a text file that diffs.

SPDX-License-Identifier: MIT
"""

import math

# Categorical hues in fixed assignment order, never cycled, checked for
# colour-vision deficiency separation against the light surface the figures
# paint for themselves. A fifth series is a sign that the figure should be
# two figures, and both generators refuse rather than inventing a colour.
SERIES_COLOURS = ["#2a78d6", "#eb6834", "#3f8f4a", "#8a5cd0"]

INK = "#1f2328"
MUTED = "#57606a"
GRID = "#d8dee4"
SURFACE = "#ffffff"


def escape(text):
    """XML-escape the five characters that matter in an attribute or body."""
    return (text.replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


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


def non_ascii(value):
    """The first character a figure cannot carry, or None.

    Figures are written as ASCII, which is what lets `grep` find a label in
    one and what lets the repository's no-dash rule see inside it at all.
    The usual way to break it is a title pasted out of a document, arriving
    with a typographic dash or a curly quote that looks identical in a
    terminal.

    Checked against the finished drawing rather than against the arguments,
    so text that reaches the figure from a data column is covered too.
    Without it the failure is a UnicodeEncodeError from the write, naming a
    byte offset into a file that does not exist yet.
    """
    for char in value:
        if ord(char) > 127:
            return char
    return None


def header(width, height, title, heading_x):
    """The opening element, the background and the heading, as a list.

    `title` is used twice on purpose: once in `<title>`, which is what a
    screen reader announces and what the browser shows on hover, and once
    as visible text, because a figure pasted into a document arrives
    without its filename and has to say what it is.
    """
    return [
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
        'viewBox="0 0 %d %d" role="img">' % (width, height, width, height),
        '<title>%s</title>' % escape(title),
        '<rect width="%d" height="%d" fill="%s"/>' % (width, height, SURFACE),
        '<text x="%d" y="24" font-family="system-ui,sans-serif" '
        'font-size="14" font-weight="600" fill="%s">%s</text>'
        % (heading_x, INK, escape(title)),
    ]
