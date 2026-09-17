# Results

`results.csv` has a header and no rows, which is still the honest state of
this file but no longer the honest state of the project. Both kernels have
booted and both have been measured. What has not happened is a measurement
worth keeping: the first row written was removed because a BusyBox
incompatibility left every external column empty, so it recorded nothing
(journal 50), and the smoke runs after it were taken on two images built at
different times, which makes them an observation about a board rather than
a comparison between kernels (journal 53). Those numbers live in the
journal, where their conditions are stated beside them, and not here.

The distinction is the point. A row in this file is a measurement of a
named system. A number that cannot say which system produced it belongs in
the narrative, where it can be qualified, rather than in a table, where it
cannot.

A row appears here by being measured on the board, written to
`/var/lib/bench/rt/results.csv` by `rt-run`, and copied back. Nothing is
typed into this file by hand, which is the point of having `rt-run` build
the row rather than a person.

## The schema

28 columns, in this order.

| Column | From | Meaning |
|---|---|---|
| `timestamp` | `date -u` | When the run finished, UTC |
| `label` | the configuration | Built from the flags, so the file names and the row agree |
| `image_build` | `/etc/timestamp` | Which image produced this row. poky writes it during rootfs assembly and it is unique per build. **The kernel columns do not answer this:** two images can carry the same kernel and differ in everything else, and on this project they did, twice in one day. A row without it can only be placed in time, not attributed. `./go archive list` maps a build to its commit |
| `kernel` | `uname -r` | Release, which distinguishes 6.6 from 6.12 |
| `kernel_version` | `uname -v` | Build string, which contains the preemption model |
| `realtime` | `uname -v` contains `PREEMPT_RT` | The kernel's own statement about its preemption model. `/sys/kernel/realtime` came from the out-of-tree RT patches and did not survive the merge into mainline for 6.12, so it is absent on both kernels here. Where it does exist it must agree, and `rt-run` refuses the run if it does not |
| `isolated` | the flag, **checked** against `/sys/devices/system/cpu/isolated` | A claim the kernel agreed with |
| `affinity` | the flag | Whether every movable interrupt was moved before the run |
| `governor` | read back after setting | What the board was actually running, not what was asked for. `fixed` means cpufreq had nothing to offer, which is what `force_turbo=1` looks like |
| `load` | the flag | `stress-ng --cpu 3 --vm 2 --vm-bytes 128M --hdd 1` on the housekeeping cores |
| `duration_s`, `toggle_us` | the configuration | 60 and 1000 unless stated |
| `ext_edges` | the instrument | Rising edges found. 30000 for a 60 s run at 1 kHz toggling |
| `ext_mean_us` | the instrument | Mean interval between rising edges. Nominally 2000 |
| `ext_sd_us` | the instrument | Standard deviation of the deviation from that mean |
| `ext_p999_us` | the instrument | 99.9th percentile of the absolute deviation |
| `ext_max_us` | the instrument | Largest absolute deviation |
| `ext_ppm` | the instrument | Difference between the DAQ clock and the Pi clock. Should be the same in every row; a row where it moved is a row where the board's clock changed during the run |
| `ext_subsample` | the instrument | Proportion of edges that were genuinely interpolated. Near 0 means the per-edge resolution of that row is one sample period, 10 us. See [METHOD.md](../docs/METHOD.md) |
| `int_min_us`, `int_mean_us`, `int_max_us`, `int_p999_us` | `rt-toggle` | Its own wake-up latency, the same quantity cyclictest reports |
| `cyc_min_us`, `cyc_avg_us`, `cyc_max_us` | `cyclictest` | The reference instrument, same core, same period, run after the toggler |
| `throttled_before`, `throttled_after` | `vcgencmd get_throttled` | `0x0` or the run is suspect. A non-zero `after` leaves a warning on stderr and the row is kept, flagged, and repeated |

## Reading a row

**This section originally said that `ext_max_us - int_max_us` is the cost
of the GPIO write. It is not, and `rt-compare` exists because the correct
comparison is not one to do in your head.**

The three columns do not measure the same quantity. `int_*` and `cyc_*` are
wake-up latencies. `ext_*` is the deviation of the interval between two
edges, and an interval carries the *difference* of two latencies, so a
constant write cost cancels out of it entirely.

What to expect between the columns:

| Comparison | Expected | What a departure means |
|---|---|---|
| `cyc_max_us` against `int_max_us` | about equal | the two internal instruments disagree, so one of them is wrong |
| `ext_sd_us` against `int_sd_us` | a factor of sqrt(2), 1.414 | see below |
| `ext_max_us` against `int_max_us` minus the typical latency | about equal | an isolated late wake-up makes one period long and the next short |

The sqrt(2) is the interesting one. A period is the difference of two
latencies, so its standard deviation is sqrt(2) times theirs when those
latencies are independent and the write cost is constant. Excess over that
factor is variation in the write path:

```
  var(ext) = 2 var(int) + 2 var(write path)
```

which `rt-compare` solves and reports as `write_path_sd_us`. A figure that
grows with load is the finding, and it is one neither cyclictest nor the
toggler's own histogram could produce, because it happens after the task
has already been scheduled.

A ratio *below* sqrt(2) says the opposite of what it looks like: under load
late wake-ups arrive in bursts, consecutive latencies correlate, and the
factor falls. That is a statement about correlation and supports no claim
about the write path at all. `rt-compare` says so rather than computing a
number from it.

## Histograms

`rt-run` also leaves, per run:

| File | What |
|---|---|
| `LABEL-toggle.txt` | The internal histogram, one line per occupied microsecond bin, with a summary in comment lines above it |
| `LABEL-external-hist.txt` | The external histogram, deviation from the mean period in 2 us bins |
| `LABEL-cyclictest.txt` | cyclictest's own output, including its `-h 400` histogram |

Plot them on a logarithmic count axis. A linear axis shows the peak, and
the peak is the part nobody needs: the whole argument about real-time
kernels is in the last three decades of the tail.

The capture itself is not kept. It is 24 MB per run in tmpfs, and a run
worth re-examining is cheaper to repeat than to store.

## Rows are not deleted for being unflattering

Every attempt is recorded, planned or not, and stays recorded until it is
superseded rather than removed. A run that produced a bad number, a run
taken on an image that turned out to have a defect, a run interrupted by a
throttle: all of them are part of how the number that ends up quoted was
arrived at, and a table that contains only the acceptable attempts is a
table that has been edited into agreement with its conclusion.

This is what `image_build` is for. When an image is rebuilt mid-matrix,
which happened twice on the first day of bring-up, the earlier rows are not
wrong: they are measurements of a different system. Marked by their build
stamp, they can be read as such, compared against the later ones, and left
in place. Without that column the only honest option would be to delete
them, and deleting a measurement because a later one is better is the
habit this whole project is arranged against.

Two things follow:

- **A row is deleted only when it is not a measurement at all.** The first
  row ever written here was removed because a BusyBox incompatibility left
  every external column empty; it recorded nothing. That is different from
  recording something inconvenient, and journal entry 50 says so at length
  precisely because the distinction is easy to blur after the fact.
- **The discussion says which rows were superseded and why.** Not the CSV,
  which stays a log, and not by removal.
