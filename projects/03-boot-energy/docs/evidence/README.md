# Portfolio evidence

What goes here, and how each item is produced. **Empty until the board has
actually run; nothing in this folder should be written from expectation.**

That rule carries more weight in this project than in most, because the
deliverable is a table of numbers and a plausible table is easy to write
and impossible to tell apart from a measured one after the fact. The
specification's own example table says the same thing in its caption.

| File | How to produce it |
|---|---|
| `logic-selftest.txt` | The answer to acceptance criterion 0, and the first thing done with the hardware. D3 wired to header pin 1 `SYS_3.3V`, source meter at 5000 mV, supply on, and what the Power Profiler app showed for D3. **Written whether it reads high or low**, because a low reading is a finding about the instrument and the rail rather than a failure of the project |
| `baseline-summary.md` | `results/00-baseline/summary.md`, copied here so the starting point is fixed even if the directory is re-run later |
| `final-summary.md` | `results/40-final/summary.md`, the same for the end point |
| `before-after.md` | A copy of [../before-after.md](../before-after.md) once every cell is filled |
| `current-baseline.png` | `make plot VARIANT=00-baseline`. Plot on a logarithmic count axis where a histogram is involved; the current trace itself is linear in time |
| `current-final.png` | `make plot VARIANT=40-final`. The pair is the picture of the whole project |
| `systemd-analyze.txt` | On the board: `systemd-analyze time`, `systemd-analyze blame \| head -20`, `systemd-analyze critical-chain`. The cross-check for acceptance criterion 2, which wants this within 0.2 s of the electrical number |
| `boot-plot.svg` | `systemd-analyze plot` on the board, copied to the host |
| `bootgraph.svg` | `perl scripts/bootgraph.pl` over a `dmesg` taken with `initcall_debug`, from the kernel tree of Project 2 |
| `ppk2-api-version.txt` | `pip show ppk2-api` on the Windows host. The package has renamed its digital-channel helpers between releases and `measure/requirements.txt` pins nothing until a version has been verified here, so the version that worked is itself evidence |

Two things deliberately **not** in this list.

The raw captures are not kept. A 60 second run at 100 kS/s is tens of
megabytes of CSV, and a run worth re-examining is cheaper to repeat than to
store. The same reasoning as Project 8.

There is no "it boots" artefact. Every number in
[before-after.md](../before-after.md) is one, and a screenshot of a login
prompt would prove less than the table above it.
