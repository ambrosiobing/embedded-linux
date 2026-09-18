#!/usr/bin/env python3
"""analyze.py - phase times and energy for one variant of Project 3.

    analyze.py RESULTS_DIR [--json] [--plot current.png]

RESULTS_DIR holds boot-01.csv ... boot-NN.csv as written by ppk2_boot.py,
each one row per sample:

    t_s,i_ua,d0,d1,d2

The three logic channels are the whole point of this project, because none
of the timing comes from the board:

    D1  U-Boot marker, PG11, set by CONFIG_PREBOOT before anything is
        scanned. Rising edge.
    D2  console TX, idle high, falls on the start bit of the first
        character the board prints. FALLING edge, and the asymmetry is
        deliberate: reading it as a rising edge would place "first console
        byte" at an arbitrary point inside the first printed line.
    D0  boot-complete marker, PA6, raised by boot-marker.service when the
        systemd startup job queue empties. Rising edge.

THE DISCARD RULES ARE NOT NEGOTIABLE AFTER SEEING THE DATA, which is why
they live here and in docs/DESIGN.md rather than being applied by hand:

  - a run whose D1 does not rise within 0.5 s of the supply coming on is
    discarded. The bootloader did not start, and averaging it in reports a
    slow boot for a board that did not boot at all;
  - the first run of every variant is discarded, because a filesystem
    change can trigger a long fsck on the next mount and that is a property
    of the previous run rather than of this variant.

Every discarded run is named in the output with its reason. A run that
vanishes silently from an average is the failure this whole repository is
arranged against.

matplotlib is imported inside plot_run() and nowhere else, so that this
program runs where only numpy exists. CI is such a place.

SPDX-License-Identifier: MIT
"""

import argparse
import glob
import io
import json
import os
import sys

import numpy as np

# 100 kS/s, the rate the PPK2 samples at in source-meter mode.
SAMPLE_DT = 1e-5

# The source-meter setting. The PPK2 measures CURRENT and not voltage, so
# this is an assumption about the rail at the header rather than a
# measurement of it, and docs/DESIGN.md says so beside the energy figure.
SUPPLY_V = 5.0

# A bootloader that has not raised its marker within half a second has not
# started. From the specification's first acceptance criterion.
D1_DEADLINE_S = 0.5

COLUMNS = ("t_s", "i_ua", "d0", "d1", "d2")


class Discarded(Exception):
    """A run that is not a measurement. Carries the reason, for printing."""


def first_edge(values, rising=True):
    """Index of the first sample AT the new level, or None.

    np.diff gives +1 where a 0 becomes a 1, so the index in the original
    array is one past the difference. Returning the sample at the new level
    rather than the last one at the old level matters at 10 us resolution
    only in that it has to be the same convention everywhere, and this is
    the convention.
    """
    d = np.asarray(values).astype(int)
    diff = np.diff(d)
    idx = np.flatnonzero(diff == (1 if rising else -1))
    return int(idx[0]) + 1 if idx.size else None


def read_run(path):
    """One CSV to a dict of arrays, with the columns checked by name.

    genfromtxt with names=True will happily return whatever header it
    finds, so a file with the right shape and the wrong columns would be
    read as a measurement. The names are checked instead of assumed.
    """
    a = np.genfromtxt(path, delimiter=",", names=True)
    if a.dtype.names is None:
        raise Discarded("%s: no header row" % os.path.basename(path))
    missing = [c for c in COLUMNS if c not in a.dtype.names]
    if missing:
        raise Discarded("%s: missing column(s) %s"
                        % (os.path.basename(path), ", ".join(missing)))
    if a.size == 0:
        raise Discarded("%s: header but no samples" % os.path.basename(path))
    return a


def phases(path):
    """The four numbers of one boot, or Discarded with the reason why."""
    a = read_run(path)
    name = os.path.basename(path)

    n_uboot = first_edge(a["d1"], rising=True)
    if n_uboot is None:
        raise Discarded("%s: D1 never rose, so U-Boot never started" % name)
    t_uboot = n_uboot * SAMPLE_DT
    if t_uboot > D1_DEADLINE_S:
        raise Discarded("%s: D1 rose at %.3f s, past the %.1f s deadline, so "
                        "the bootloader did not start"
                        % (name, t_uboot, D1_DEADLINE_S))

    n_done = first_edge(a["d0"], rising=True)
    if n_done is None:
        raise Discarded("%s: D0 never rose, so the startup job queue never "
                        "emptied" % name)

    n_console = first_edge(a["d2"], rising=False)
    if n_console is None:
        raise Discarded("%s: D2 never fell, so the board printed nothing"
                        % name)

    # Integrated over [0, t_done] and not over the whole recording, because
    # ppk2_boot.py keeps a short tail after the marker and that tail is
    # idle current, not boot current.
    i_a = a["i_ua"][:n_done] * 1e-6
    energy_j = SUPPLY_V * float(i_a.sum()) * SAMPLE_DT

    return {
        "run": name,
        "t_uboot": t_uboot,
        "t_console": n_console * SAMPLE_DT,
        "t_done": n_done * SAMPLE_DT,
        "energy_j": energy_j,
        "mean_ma": float(i_a.mean()) * 1e3,
        # The 1 A source-meter limit is checked by the data rather than
        # asserted once in the design document.
        "peak_ma": float(i_a.max()) * 1e3,
        "samples": int(a.size),
    }


def summarise(directory):
    """Every boot-*.csv in one variant directory, with the rules applied."""
    paths = sorted(glob.glob(os.path.join(directory, "boot-*.csv")))
    if not paths:
        raise SystemExit("analyze.py: no boot-*.csv in %s" % directory)

    kept, discarded = [], []

    # The first run goes before anything is read, so that a bad first run
    # is reported as "first run of the variant" and not as a D1 failure.
    # Which rule fired is part of the finding.
    discarded.append({"run": os.path.basename(paths[0]),
                      "why": "first run of the variant, discarded by rule"})

    for path in paths[1:]:
        try:
            kept.append(phases(path))
        except Discarded as exc:
            discarded.append({"run": os.path.basename(path),
                              "why": str(exc).split(": ", 1)[-1]})

    report = {
        "directory": os.path.basename(os.path.normpath(directory)),
        "runs_found": len(paths),
        "runs_kept": len(kept),
        "discarded": discarded,
        "supply_v": SUPPLY_V,
        "sample_dt_s": SAMPLE_DT,
        "integration_interval": "[0, t_done]",
        "runs": kept,
    }

    for key in ("t_uboot", "t_console", "t_done", "energy_j",
                "mean_ma", "peak_ma"):
        col = np.array([r[key] for r in kept], dtype=float)
        if col.size:
            report[key + "_mean"] = float(col.mean())
            # ddof=1 needs two runs. One kept run has no spread to report,
            # and reporting 0.0 would read as "perfectly repeatable".
            report[key + "_sd"] = (float(col.std(ddof=1))
                                   if col.size > 1 else None)
        else:
            report[key + "_mean"] = None
            report[key + "_sd"] = None

    return report


def plot_run(path, out):
    """Current trace with the three markers as vertical lines."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    a = read_run(path)
    t = np.arange(a.size) * SAMPLE_DT
    fig, ax = plt.subplots(figsize=(10, 4))
    ax.plot(t, a["i_ua"] * 1e-3, linewidth=0.5)
    for chan, rising, colour, label in (("d1", True, "tab:green", "U-Boot"),
                                        ("d2", False, "tab:orange", "console"),
                                        ("d0", True, "tab:red", "complete")):
        n = first_edge(a[chan], rising=rising)
        if n is not None:
            ax.axvline(n * SAMPLE_DT, color=colour, linestyle="--",
                       linewidth=1, label=label)
    ax.set_xlabel("time since power on (s)")
    ax.set_ylabel("current (mA)")
    ax.legend(loc="upper right")
    fig.tight_layout()
    fig.savefig(out, dpi=120)
    return out


def as_markdown(report):
    out = []
    out.append("# %s" % report["directory"])
    out.append("")
    out.append("%d run(s) found, %d kept."
               % (report["runs_found"], report["runs_kept"]))
    out.append("")
    out.append("Energy is integrated over %s at an assumed %.1f V at the "
               "header. The PPK2 measures current, not voltage."
               % (report["integration_interval"], report["supply_v"]))
    out.append("")
    out.append("| Quantity | Mean | SD | n |")
    out.append("|---|---|---|---|")
    rows = (("time to U-Boot marker (s)", "t_uboot", "%.3f"),
            ("time to first console byte (s)", "t_console", "%.3f"),
            ("time to boot complete (s)", "t_done", "%.3f"),
            ("energy per boot (J)", "energy_j", "%.2f"),
            ("mean current (mA)", "mean_ma", "%.0f"),
            ("peak current (mA)", "peak_ma", "%.0f"))
    for label, key, fmt in rows:
        mean, sd = report[key + "_mean"], report[key + "_sd"]
        out.append("| %s | %s | %s | %d |"
                   % (label,
                      "not measured" if mean is None else fmt % mean,
                      "not measured" if sd is None else fmt % sd,
                      report["runs_kept"]))
    out.append("")
    if report["discarded"]:
        out.append("## Discarded runs")
        out.append("")
        for d in report["discarded"]:
            out.append("- `%s`: %s" % (d["run"], d["why"]))
        out.append("")
    return "\n".join(out)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("directory")
    p.add_argument("--json", action="store_true")
    p.add_argument("--no-summary", action="store_true",
                   help="print the summary without writing summary.md")
    p.add_argument("--plot", metavar="PNG",
                   help="also plot the first kept run to this file")
    args = p.parse_args(argv)

    report = summarise(args.directory)

    if args.json:
        print(json.dumps(report, sort_keys=True))
        return 0

    text = as_markdown(report)
    print(text)

    # WRITTEN, not only printed. docs/DESIGN.md's data flow says this
    # program produces results/<variant>/summary.md, and for a while it
    # did not: it printed to stdout and the claim stood in the document
    # unchallenged. The Makefile in this directory relies on the file
    # existing, and so does docs/before-after.md, which is assembled from
    # the summaries of every variant.
    if not args.no_summary:
        out = os.path.join(args.directory, "summary.md")
        with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text + "\n")
        print("wrote %s" % out)

    if args.plot:
        if not report["runs"]:
            print("no kept run to plot", file=sys.stderr)
            return 1
        first = os.path.join(args.directory, report["runs"][0]["run"])
        try:
            print("plot %s" % plot_run(first, args.plot))
        except ImportError:
            print("matplotlib is not installed, so no plot was drawn",
                  file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
