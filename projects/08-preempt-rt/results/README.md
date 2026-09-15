# Results

`results.csv` has a header and no rows. That is the honest state of this
project: the code is written and no board has run it.

A row appears here by being measured on the board, written to
`/var/lib/bench/rt/results.csv` by `rt-run`, and copied back. Nothing is
typed into this file by hand, which is the point of having `rt-run` build
the row rather than a person.

## The schema

27 columns, in this order.

| Column | From | Meaning |
|---|---|---|
| `timestamp` | `date -u` | When the run finished, UTC |
| `label` | the configuration | Built from the flags, so the file names and the row agree |
| `kernel` | `uname -r` | Release, which distinguishes 6.6 from 6.12 |
| `kernel_version` | `uname -v` | Build string, which contains the preemption model |
| `realtime` | `/sys/kernel/realtime` | yes only if the file exists and reads 1 |
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

Three numbers describe the same run and they should not be equal:

```
  int_max_us   <   cyc_max_us  ~  int_max_us   <   ext_max_us
  the measured                     the reference     what the wire saw
  task's own                       task's own        = latency + the
  lateness                         lateness          GPIO ioctl
```

`ext_max_us - int_max_us` is the cost of one GPIO character-device ioctl
plus the instrument's own contribution. A few microseconds, and **stable
across rows** is the expected result. If it grows under load, the system
call itself is being delayed, which is a finding neither cyclictest nor the
toggler's own histogram could have produced.

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
