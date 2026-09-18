# Results

`results.csv` holds 18 rows: the completed matrix, taken on 17 September
between 12:49 and 15:23, eight on the generic kernel and ten on
PREEMPT_RT. Same image, same board, same session, matched configuration by
configuration, with repeats on four of them.

It was empty for a long time and the reason is worth keeping. The first row
ever written was removed because a BusyBox incompatibility left every
external column empty, so it recorded nothing (journal 50), and the smoke
runs after it were taken on two images built at different times, which
makes them an observation about a board rather than a comparison between
kernels (journal 53). Those numbers live in the journal, where their
conditions are stated beside them, and not here.

The distinction is the point. A row in this file is a measurement of a
named system. A number that cannot say which system produced it belongs in
the narrative, where it can be qualified, rather than in a table, where it
cannot.

A row appears here by being measured on the board, written to
`/var/lib/bench/rt/results.csv` by `rt-run`, and copied back. Nothing is
typed into this file by hand, which is the point of having `rt-run` build
the row rather than a person.

**This copy was transcribed over the serial console, not `scp`'d**, which
is the one exception and is recorded rather than glossed. The card was
flashed without a `/boot/wifi.conf`, so the board had no route at any
point during the matrix. It was verified afterwards by checksum from the
console:

```
md5sum /var/lib/bench/rt/results.csv; wc -lc /var/lib/bench/rt/results.csv
9a6a04dd2fc8d71c4affa296fcb86869  /var/lib/bench/rt/results.csv
      19      4678
```

which is what this file gives. Identical, byte for byte. The rule above
is about a person composing a row rather than about the transport, and a
checksum is how the distinction is kept honest when the transport has to
change.

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

## What the matrix says

`ext_p999_us` is the column to read. It is the tail the whole argument is
about, and unlike `ext_max_us` it reproduces: where a repeat exists the two
values agree to within a few percent, while the maxima do not agree at all.

| isolated / affinity / governor / load | generic | PREEMPT_RT | change |
|---|---|---|---|
| no / no / schedutil / no | 29.64 | 29.19 | -2% |
| no / no / schedutil / yes | 93.95 | 98.11, 94.28 | +2% |
| no / no / performance / yes | 100.42 | 100.42 | 0% |
| no / yes / performance / yes | 226.75 | 110.43 | -51%, see below |
| **yes** / no / performance / yes | 119.16, 149.44 | 68.05, 70.49 | **-48%** |
| **yes** / yes / performance / no | 16.81 | 10.16 | **-40%** |
| **yes** / yes / performance / yes | 99.32 | 71.08, 63.92 | **-32%** |

**PREEMPT_RT bought nothing measurable at the pin until the core was
isolated.** The three pairs with the measured core still in the scheduler's
general pool differ by 2 percent or less, which is well inside the spread
between repeats of one configuration. Every pair with `isolcpus` and
`nohz_full` covering CPU 3 improved by between a third and a half.

This is worth stating in the order the measurements put it, because it is
not the order the two are usually presented in. Isolation is normally
described as tuning applied on top of a real-time kernel. Here isolation is
the precondition and the real-time kernel is the increment, and a reader
who applied PREEMPT_RT to this workload without `isolcpus` would have
measured nothing and concluded, correctly for what they did, that it made
no difference.

**The fourth row is not evidence and is not counted.** Affinity without
isolation shows the largest apparent gain in the table, and it rests on a
single generic row whose `ext_p999_us` of 226.75 is more than double both
of its neighbours: 100.42 with nothing applied and 119.16 with isolation
instead. No repeat was taken on that arm. It reads as a bad generic row
rather than as an effect of the kernel, and the 51 percent is left in the
table with this note beside it rather than removed, for the reason the
last section of this file gives.

**The strongest pair is the one with repeats on both arms.** Isolated
without affinity was run twice on each kernel: 119.16 and 149.44 against
68.05 and 70.49. The arms do not overlap at all, and the RT pair reproduces
to 3.5 percent while the generic pair spreads 22 percent, which is itself
part of the result. A kernel that gives a more repeatable tail is making a
different claim from one that gives a lower tail, and here it does both.

**Neither arm had a wireless interface at all.** Not an idle one: there
is no `wlan0` on this image. `brcmfmac` loads, finds the chip, asks for
`brcm/brcmfmac43455-sdio.bin` and gets ENOENT, because
`/lib/firmware/brcm` does not exist in the rootfs. `ip addr show wlan0`
answers `can't find device`.

That matters more than it sounds, and it is worth being precise about
why. An associated interface generates interrupts and softirqs on a
schedule nobody in this experiment controls, and even an unassociated one
scans. An arm that had either while the other did not would make every
pair in this table unreadable. Here neither arm had either, and the two
arms share one rootfs and one `/lib/modules`, so this is not an
assumption about symmetry: it is the same absent file on both sides.

This was found on 17 September while trying to get the board back on the
network after the matrix, and an earlier version of this section said the
card had been flashed without a `/boot/wifi.conf`. That was wrong.
`wifi.conf` is present, `bench-wifi-setup` parses it and reports success
at every boot, and none of it can matter while the driver has no
firmware to attach to.

## What the external instrument saw and the internal ones did not

`ext_max_us` runs from 649.8 to 1229.7 across all 18 rows. `int_max_us`
never exceeds 462.7. **In every row an excursion of several hundred
microseconds to over a millisecond appears at the pin and appears in
neither internal instrument.**

It is insensitive to everything the matrix varies. It is present on both
kernels, at both governors, loaded and quiet, isolated and not. It is
present in the quietest row in the file, `generic-iso-aff-performance`,
where the pin shows 649.8 us and the toggler's own worst wake-up in that
same minute was 43.6 us.

**It is not attributed here.** The candidates are the SPI path to the HAT,
the recorder, and firmware activity underneath the kernel, and separating
them needs an experiment this matrix does not contain. Naming it as
unattributed is the finding rather than a gap in it: this is the one
quantity no amount of cyclictest would have revealed, and it is the reason
the project has an external instrument at all.

## One row where the standard deviation is not a summary

`rt-iso-aff-performance` is the only row in the file where `ext_p999_us`
(10.163) is **below** `ext_sd_us` (10.906). For any distribution without
extreme outliers, p99.9 sits at roughly three times the standard deviation.
Below it means fewer than 30 samples in 30000 exceed 10 us while at least
one reaches 920, so the standard deviation is carried almost entirely by a
handful of excursions and is not a summary of the distribution it came
from.

`rt-compare` reported `sd ratio 12.430` and `write-path variation 7.653 us`
for that row. Both are arithmetically correct and neither is usable. The
sqrt(2) derivation assumes a write cost that varies in a stationary way,
not one that is flat with a single millisecond spike in it, and the ratio
test guards the ratio without ever asking whether the standard deviation it
divides into is meaningful. That is a gap in `rt-compare` rather than in
the row, and it is the same class of defect as the one `rt-compare` was
written to fix.

## Two rows to read with their repeats

- **13:15:10, `generic-iso-performance-load`.** `ext_ppm` is -509.333
  against -53 to -233 in every other row, `ext_mean_us` is 1998.981, the
  only mean below 1999.5 in the file, and it found 28941 edges. By the rule
  in the schema above, a row whose ppm moved is a row where the board's
  clock changed during the run. Its repeat at 13:20:32 is the one to read.
- **14:52:48, `rt-iso-performance-load`.** 29124 edges, roughly 900 short.
  It also has a repeat, at 14:58:24, and the two agree to 3.5 percent.

Both short rows are the same configuration on opposite arms, isolated
without affinity. That is worth noticing and is not explained.

## What was not taken, and why

Two rows of the planned matrix, generic and PREEMPT_RT with
`force_turbo=1`, **were not taken.** `force_turbo=1` permanently sets the
warranty bit in the SoC and does not clear when the line is removed from
`config.txt`.

The question it would have answered is whether the residual tail has a
component the `performance` governor does not remove, since `performance`
pins the cpufreq policy while the firmware can still move the clock
underneath it. That is a secondary question, the matrix answers its primary
one without it, and this board is the bench for the rest of the portfolio.
Recorded here as a decision with its reason rather than left as a silent
hole in the table.

## The earlier matrix

An earlier eight row matrix taken the same day between 03:55 and 05:09 is
preserved at `2026-09-17_5ec99fd-dirty/results.csv`. It is superseded but
it is not wrong: it is the generic arm only, taken before the card was
reflashed, and it was never paired.

Three of its rows ran at `ondemand`, and **the RT kernel has no `ondemand`
governor, so those three have no counterpart that can be taken at all.**
`rt-common.cfg` sets `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE`, which
chooses the default and compiles none of the others in; this kernel offers
conservative, userspace, powersave, performance and schedutil. That is why
the current matrix uses `schedutil` where the earlier one used `ondemand`,
and why `rt-run` now reads `scaling_available_governors` and refuses by
name instead of failing inside an `echo`.

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

## The figures, and the ones that cannot be drawn

Two kinds of figure are drawn from this directory.

**The matrix**, [ext-p999-matrix.svg](ext-p999-matrix.svg), comes from
`results.csv` and is regenerated by `./go matrix`. Every row of the file
becomes a mark, repeats included, so the spread between two runs of one
kernel and the difference between the two kernels are read off the same
picture at the same scale. `tests/rt-matrix-test.sh` fails if the committed
figure and this `results.csv` disagree, which is what stops a figure quietly
outliving the numbers under it.

**The histograms** come from the per-run instrument files, and this is the
gap worth stating plainly: **the 18-row matrix has no per-run histograms
saved.** Only the superseded generic-only run of 17 September kept its
`-cyclictest.txt`, `-toggle.txt` and `-external-hist.txt` triples, which is
why the two histogram figures in the project README are from that run and
labelled as such.

The consequence follows from decision 86 rather than from preference. A
figure is a rendering of a named capture, so a histogram of the paired
matrix cannot be drawn at all: the captures were not kept, and drawing one
from the summary columns would be inventing a distribution from its
moments. The fix is not a flag. It is to copy the three files per run back
alongside the row next time, the way the superseded directory already does.

That directory is therefore worth more than its supersession suggests. It
is the only place in this project where the distribution behind a number
can still be looked at.
