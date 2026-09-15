# Measurement method, and what it cannot resolve

Every number this project produces has an uncertainty, and two of those
uncertainties are large enough to change what the results mean. This
document states them before any results exist, so that they are a property
of the method rather than an excuse attached to an inconvenient number.

## The three instruments

| Instrument | Measures | Clock | Sees the GPIO write |
|---|---|---|---|
| `rt-toggle`'s own histogram | wake-up latency of the measured task | the kernel under test, CLOCK_MONOTONIC | no |
| `cyclictest` | wake-up latency of a reference task | the same | no |
| MCC 118 through `rt-capture` | the interval the outside world sees between edges | its own crystal | yes |

The first two answer "was the task woken on time". The third answers "did
the pin move on time", which is the question an actuator asks. The
difference between them is the cost of one ioctl on the GPIO character
device, and it is the reason this project exists.

## Uncertainty 1: the edge has to be slower than the sample period

This is the one the usual recipe gets wrong, and the mistake flatters the
result.

The instrument samples every 10 us. The jitter worth resolving is smaller
than that, so the edge time is recovered by interpolating the threshold
crossing between the two samples either side of it:

```
        v[i+1]  o                  frac = (thr - v[i]) / (v[i+1] - v[i])
                |                  t_edge = (i + frac) / fs
    thr  - - - -x- - -
                |
        v[i]  o |
              |<->| one sample, 10 us
```

That arithmetic is correct. Whether it means anything depends entirely on
where `v[i]` and `v[i+1]` sit.

**A fast edge carries no information.** A 3.3 V CMOS output into a 10 cm
jumper settles in tens of nanoseconds. The probability that a sample lands
during the transition is about 10 ns over 10 us, one in a thousand. So for
essentially every crossing `v[i]` is 0 V and `v[i+1]` is 3.3 V, the
fraction is (1.65 - 0) / 3.3 = 0.5 exactly, and the recovered edge time is
`(i + 0.5) / fs`. The interpolation returns a constant. The resolution is
one sample period, dressed up in decimals.

**A slowed edge carries the information.** Put 1 kohm in series with the
jumper and 10 nF from CH0 to AGND. The time constant is 10 us, the
transition spans two or three samples, and the sample that lands on the ramp
records where in the interval the edge happened. The interpolation is then
doing what its name says.

### How to tell which one you have

`rt-analyze` measures it rather than assuming it. `subsample_fraction` is
the proportion of crossings whose two straddling samples differ by less
than 80 percent of the full logic swing, meaning at least one of them was
taken on the ramp.

| `subsample_fraction` | What it means | What to trust |
|---|---|---|
| below 0.2 | the edge is faster than the instrument; nothing was interpolated | mean and offset only |
| above 0.9 | the edge spans samples; interpolation is real | everything |
| in between | a partly resolved edge, usually a marginal RC | repeat with a larger capacitor |

Below 0.2 the program prints a warning on stderr and the column goes into
the results row, so a reader can see which regime each row was measured in.

### What survives quantisation and what does not

The toggle period and the sample period are not commensurate, and the two
crystals differ by tens of parts per million, so the crossings drift
through the sample interval over a run. That drift is what saves the mean:

| Quantity | Fast edge (unresolved) | Slowed edge (resolved) |
|---|---|---|
| mean period | good to nanoseconds over 30000 edges | the same |
| clock offset in ppm | the same | the same |
| standard deviation | inflated: each period carries the difference of two rounding residuals, adding about 4.1 us in quadrature | true |
| 99.9th percentile | carries the same inflation | true |
| maximum | one sample period of uncertainty, 10 us | about 1 us |

`tests/rt-analyze-test.sh` demonstrates exactly this, against a synthesised
wave with known edge times: the same 2.0 us of injected jitter reads as
4.2 us through an ideal edge and as 2.0 us through a slowed one.

### Does it matter for the acceptance criteria

The criterion is a 99.9th percentile below 50 us and a maximum below 150 us
for the RT kernel under load, against a generic kernel at least five times
worse. Both regimes can decide that: 10 us of quantisation on a 150 us
threshold is 7 percent. What the fast edge cannot do is compare an RT
kernel at 20 us with a well-tuned generic one at 30 us, and it cannot
support any claim about the GPIO system call cost, which is a few
microseconds. Those are the measurements that need the RC.

**The departure from the original scope:** that scope has no resistor and
no capacitor in its parts list, and justifies the interpolation by saying
the edge is fast. The interpolation works because the edge is slow. Both
regimes are supported here, and the results table records which one each
row used.

## Uncertainty 2: the two clocks

The MCC 118 samples on its own crystal and the Pi schedules on its own.
Tens of parts per million between them is normal, and at a nominal 2000 us
period that is tens of nanoseconds per period, which is nothing, and
2000 us x 30 ppm = 0.06 us of systematic offset in the mean, which is also
nothing. The offset matters for a different reason: it is a **constant**,
and subtracting the wrong constant turns into apparent jitter.

So deviations are measured from the mean of the run, not from the nominal
1000 us or 2000 us. The offset itself is reported as
`clock_offset_ppm`, and it has a job: it should be the same in every row.
A row whose offset moved by hundreds of ppm was measured on a board whose
clock changed during the run, which on a Pi means throttling, and that row
has to be repeated rather than explained.

## Uncertainty 3: what the histogram is a histogram of

`rt-toggle` bins its own lateness in microseconds, with 2000 bins and an
overflow counter. Three consequences:

- a latency of 2 ms or more lands in the overflow bucket and is reported
  as a count, not as a value. A run with a non-zero overflow has a maximum
  that is only a lower bound, and the row should say so
- the percentiles are read off the histogram rather than from a sorted
  list, because sorting means allocating, and that costs one microsecond of
  quantisation, which is below what the rest of the method can resolve
- the mean is accumulated in a double from exact nanosecond differences,
  so it does not carry the binning error

## What is not measured, and would matter in a product

| Not measured | Why it is left out | Where it would go |
|---|---|---|
| Interrupt to wake-up latency | needs a second GPIO wired as an input and a source of edges | a stretch goal, and the natural sequel with `gpiomon` |
| The cause of a late wake-up | needs a trace, not a histogram | Project 9: ftrace, `trace-cmd`, `sched_switch` |
| Worst case rather than observed maximum | needs static analysis or a far longer run; 60 s at 1 kHz is 60000 samples and says nothing about the hour you did not measure | stated as a limit, not fixed |
| Energy cost of PREEMPT_RT | needs the PPK2 from Project 3 | a row in Project 3's table |
| The same matrix on a Pi 3B+ | different interrupt routing and memory bandwidth | a stretch goal |

The third row is the one to say out loud in an interview. A 60 s run
produces an observed maximum, and an observed maximum is not a guarantee.
Real-time means a bound that holds always, and nothing measured on a
general-purpose SoC with a shared memory controller and an SD card can
establish one. What this lab produces is evidence that the configuration
does what it claims, and a number that can be compared like for like
between configurations.

## Why 60 s, 1 kHz and SCHED_FIFO 80

| Choice | Reason | What would change it |
|---|---|---|
| 60 s per run | 30000 rising edges makes a 99.9th percentile mean something; longer and a bare Pi 4 under `stress-ng` starts throttling mid-run | a heatsink, and then 300 s runs for the rows that matter |
| 1 kHz toggling | one edge per millisecond is the classic control loop rate, and it is the rate cyclictest is usually quoted at, so the two are comparable | a 10 kHz row would show where the system call cost starts to dominate |
| SCHED_FIFO 80 | above everything ordinary, below the 99 that kernel threads such as the timer softirq use. Going above them is a good way to hang the board | nothing, unless the application under study has its own priority scheme |
| Priority 80 for cyclictest too | the same priority on the same core, so the comparison is between instruments and not between priorities | nothing |

---

Back to the [design](DESIGN.md), or on to the
[project README](../README.md).
