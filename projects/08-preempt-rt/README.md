# Project 8: a PREEMPT_RT latency lab with the MCC 118 as the instrument

**Boards:** Raspberry Pi 4 Model B, and a Pi 3 Model B v1.2 as the second board (see below). **Theme:** real-time kernel,
cyclictest, IRQ affinity, jitter measurement.

Real-time Linux is usually argued about with cyclictest numbers, and
cyclictest measures the kernel from inside the task the kernel is
scheduling, on the kernel's own clock. That is a useful number and it is
not the number an actuator experiences. This project adds a second
instrument that shares nothing with the first except a wire: an MCC 118 DAQ
HAT samples the pin that the real-time task toggles, at 100 kS/s, on its own
crystal.

Comparing the two is the lesson, and the comparison is not the one it
first appears to be. The instrument measures the *interval* between edges,
so a constant cost between waking up and moving the pin appears in both
ends of that interval and cancels. What the wire sees is the **variation**
in the whole output path, which arrives as an excess over a factor of
sqrt(2) that comes out of the algebra rather than out of the hardware.
[docs/DESIGN.md](docs/DESIGN.md) derives it and `rt-compare` computes it.

That is a smaller claim than "the external number includes the system
call", which is what this project's own design notes said until the algebra
was done. It is also the useful one: it does not tell you what a GPIO write
costs, it tells you whether that cost is steady, which is the property a
control loop actually depends on.

The knobs are the ones an embedded interview asks about: the preemption
model, CPU isolation, interrupt affinity, the frequency governor and load.
Each is switched on alone and in combination, and each produces a
histogram rather than a single worst case.

Project 1 built the layer, the image and the cross SDK. This project is the
first to change the kernel itself.

## State

**The matrix is measured on both arms.** On 17 September 2026 between
12:49 and 15:23 the Pi 4 ran one image with the MCC 118 on the header and
produced the 18 rows in [results/results.csv](results/results.csv): eight
on the generic kernel and ten on PREEMPT_RT, matched configuration by
configuration, with repeats on four of them. The reading of those rows,
with every caveat that qualifies them, is in
[results/README.md](results/README.md).

This section previously said half the matrix was measured against a wrong
control, and that was true when it was written. The control was wrong
because `kas/bench-rt-generic.yml` omitted the whole kernel fragment rather
than one symbol of it, which the board said on its serial console and
nothing else could have: journal 57, decision 88. The fragment was split,
both kernels were rebuilt, and the paired matrix was taken.

The headline: **PREEMPT_RT bought nothing measurable at the pin until the
measured core was isolated.** The three pairs with CPU 3 still in the
scheduler's general pool differ by 2 percent or less, inside the spread
between repeats of one configuration. Every pair with `isolcpus` and
`nohz_full` covering that core improved `ext_p999_us` by between a third
and a half. Isolation is the precondition here and the real-time kernel is
the increment, which is the reverse of the order the two are usually
presented in.

The earlier generic-only matrix is preserved at
[results/2026-09-17_5ec99fd-dirty/](results/2026-09-17_5ec99fd-dirty). It
is superseded and it is not wrong: it is the generic arm alone, taken
before the card was reflashed, and it was never paired.

`bench-rt-image` was built on 16 September 2026, 78 MB compressed, with
`CONFIG_PREEMPT_RT=y` verified in the `.config` before the compile began.
That settles everything a build host can settle, including the four things
that had never executed until then: the vendor library's `do_install`, the
`-tools` package split, `python3-daqhats` through `setuptools3`, and the
image assembly, which is where a missing `RDEPENDS` would have surfaced.

What changed on 16 September 2026 is the riskiest part of the project, and
it was settled before the compile rather than after it: the 6.12 kernel is
in place, every line of both fragments names a real symbol, and every one
of them reached the `.config` that kconfig produced, `CONFIG_PREEMPT_RT=y`
included. That is criterion 7, and it took minutes because
`bitbake -c kernel_configme` merges the fragments without building
anything.

What is proven today, on a laptop and in CI:

| Proven | How |
|---|---|
| `rt-toggle` compiles clean with `-Wall -Wextra -Werror` against libgpiod v2 | `./go check` and CI |
| `rt-analyze` recovers a known jitter from a synthesised waveform to 0.3 us | `tests/rt-analyze-test.sh`, 21 assertions |
| An unresolved edge is detected and reported rather than silently trusted | the same test, both regimes |
| The run protocol keeps its order and refuses every invalid claim | `tests/rt-run-test.sh`, 51 assertions against stubs |
| Movable and kernel-owned interrupts are distinguished correctly | `tests/rt-irq-affinity-test.sh`, 14 assertions |
| The relationship between the two instruments is the one the algebra predicts | `tests/rt-compare-test.sh`, 22 assertions against a simulation whose answer is known first |
| `PREEMPT_RT` is selectable on this kernel at all | read out of `kernel/Kconfig.preempt` and `arch/arm64/Kconfig` in `rpi-6.12.y`, see below |
| The fragment check catches a kernel built without it | `./go kconfig -f rt-common -f rt` against a deliberately broken config |
| Every symbol in `rt.cfg` and `bench.cfg` is real, and two are promptless | `./go ksym -f rt-common -f rt` against the unpacked 6.12.93 tree, 21484 declarations indexed. **Run before the 17 Sep fragment split; the symbols are the same and the grouping is not, so it needs repeating** |
| The version pin took: the tree is 6.12.93, not the BSP default 6.6 | the kernel's own `Makefile`, read after `kernel_configme` |
| **Every option of both fragments reached the `.config`, `CONFIG_PREEMPT_RT=y` included** | `./go kconfig -f rt-common -f rt`, evidence for [the Pi 4](docs/evidence/kconfig-check-raspberrypi4-64.txt) and [the Pi 3B](docs/evidence/kconfig-check-raspberrypi3-64.txt). **Both captures are of the real-time arm only, and predate the split; the control was never checked, which is how it came to have no fragment at all** |
| The image builds: 6258 tasks, all succeeded, 78 MB | `./go rt`, 16 Sep 2026 |
| The vendor library cross-compiles, packages and installs | the same build, after three defects only building could find |

What that does not prove is any latency number whatsoever. See
[Acceptance criteria](#acceptance-criteria) for which rows are evidence and
which are still plans, and the [journal](JOURNAL.md) for the decisions and
the places where this departs from the original scope on purpose.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/rt.cfg` | The variable, and nothing else: `CONFIG_PREEMPT_RT` plus the three other members of its choice named off |
| `meta-bench/recipes-kernel/linux/files/rt-common.cfg` | Everything the lab needs that is not the variable, applied to **both** arms: `NO_HZ_FULL`, `RCU_NOCB_CPU`, `CPU_ISOLATION`, `HIGH_RES_TIMERS`, the default governor and the debug options that have to be off |
| `kas/bench-rt.yml` | Both fragment switches, the kernel version that can honour them, SPI, `meta-python` |
| `meta-bench/recipes-core/images/bench-rt-image.bb` | `bench-image` plus both instruments and the load generator |
| `meta-bench/recipes-bench/bench-rt/` | `rt-toggle`, `rt-capture`, `rt-analyze`, `rt-compare`, `rt-run`, `rt-irq-affinity` and their configuration |
| `meta-bench/recipes-bench/daqhats/` | The vendor library and its Python bindings, pinned to a commit, cross-compiled |
| `scripts/rt-kernel-install.sh` | Puts the RT kernel on a card beside the generic one, with a one-line way back |
| `scripts/check-kernel-config.sh` | Extended: `-f rt-common -f rt` checks the real-time fragments too |
| `scripts/check-kernel-symbols.sh` | The check that runs before a build: is each fragment line a symbol the kernel can receive |
| `tests/rt-analyze-test.sh` and two more | What can be proven without the instrument |

## What a clone gives you

**No image is published.** `bench-rt-image` was built here on 16 September
2026, 78 MB compressed, and it is not downloadable from this repository:
`.gitignore` excludes `*.wic*` on purpose.

**What the board produced is published.** The generic half of the matrix
ran on 17 September 2026 and its eight rows, twenty-four histograms,
figures and provenance are in
[results/2026-09-17_5ec99fd-dirty/](results/2026-09-17_5ec99fd-dirty).
The figures regenerate from those histograms with `./go plot`, so nothing
in them has to be taken on trust.

**If the software and the method are what interest you, no HAT is
required.** Three test suites and two static checks run on any machine, and
are listed under
[what is tested without hardware](#what-is-tested-without-hardware).
[docs/DESIGN.md](docs/DESIGN.md) derives the relationship between the two
instruments, which is the part of this project most worth reading and needs
no hardware at all: the external instrument measures an interval between
two edges, so a constant output cost cancels and what survives is its
variation. [docs/METHOD.md](docs/METHOD.md) is what each instrument can and
cannot resolve, including the place where the usual recipe flatters the
result.

**If you want to boot it, this is not a small addition to Project 1.** It
compiles its own kernel, and a different one: `CONFIG_PREEMPT_RT` needs
`ARCH_SUPPORTS_RT`, which arm64 gained in 6.12, so this image is on 6.12
where the rest of the bench is on 6.6. None of that kernel can come from
Project 1's shared state. The wall clock for this build was not recorded,
so no figure is given here; from the fact that it is a full kernel compile
plus a vendor library, expect it to behave like a first build rather than a
warm one. `./go rt-kernel install` exists so that you can put the RT kernel
on a card beside the generic one, with a one-line way back, rather than
committing a board to it.

**Hardware, specifically.** A Raspberry Pi 4 Model B, with a Pi 3 Model B
v1.2 as a second board, and an adapter so the MCC 118 stacks on either.
The comparison this project makes needs the DAQ HAT: without it
the internal instrument still runs and the external one has nothing to
measure, which is half the point missing. `./go ksym -f rt-common -f rt` before the
kernel compiles is the check that catches a fragment line the kernel cannot
receive, and it is worth running even if you never flash anything.

## Running it

```sh
./go check                   # about 2 minutes, no board and no HAT
./go ksym -f rt-common -f rt # after the kernel unpacks, before it compiles
./go rt                      # bench-rt-image, with the PREEMPT_RT kernel
./go flash /dev/sdX          # or install beside the generic kernel:
./go rt-kernel install /mnt/boot /mnt/root
```

On the board, one configuration per invocation:

```sh
rt-run -i -a -g performance -L        # RT, isolated, affinity, load
cat /var/lib/bench/rt/results.csv
```

[docs/DESIGN.md](docs/DESIGN.md) is the methodology: architecture,
schematic, bench layout, the activity diagram of one run, the data flow and
the sequence that shows where the two instruments diverge. Read it first.

[docs/METHOD.md](docs/METHOD.md) is what the instruments can and cannot
resolve, including the one place where the usual recipe is wrong in a way
that flatters the result.

[docs/BRINGUP.md](docs/BRINGUP.md) is the board work in order, from the
first `daqhats_list_boards` to the sixteenth row.

## Two boards, and which one the thresholds belong to

This settled in three moves, and the journal has the account in entries 32
to 37. Scoped for a Pi 4. Moved to a Pi 3B v1.2 when the MCC 118 would not
stack on the Pi 4 with the parts to hand. Moved back when an adapter
arrived, because keeping the absolute thresholds honest was worth more than
the rebuild.

**The Pi 4 is the primary board.** `machine: raspberrypi4-64` in
`kas/bench-rt.yml`, and it is the board the acceptance thresholds were
written for, so a number measured there is a criterion rather than a
criterion with an asterisk.

**The Pi 3B is the second board, not the fallback.** Its image is built,
verified and archived. `raspberrypi3-64` covers the 3B and the 3B+ alike,
because meta-raspberrypi names the whole BCM2837 family that way, and the
64 bit build is what `ARCH_SUPPORTS_RT` requires. To build for it, change
one line.

Nothing in the design objects to either. Both are quad-core arm64, so
`ARCH_SUPPORTS_RT` and `isolcpus=3` mean the same thing on each, the pin
numbers in the wiring table are header positions rather than board
properties, and `rt-toggle` opens `/dev/gpiochip0` by path without ever
matching the SoC label.

What differs is what the numbers will say:

| | Pi 4 Model B | Pi 3B v1.2 |
|---|---|---|
| Core | Cortex-A72, 1.5 GHz | Cortex-A53, 1.2 GHz |
| Memory | 2 to 8 GB | 1 GB |
| Ethernet and USB | separate buses | 100 Mbit Ethernet behind the same USB hub, so more interrupt traffic on one controller |
| GPIO label | `pinctrl-bcm2711` | `pinctrl-bcm2835` |
| Thermal headroom | more | less, so the throttle gate fires sooner under `stress-ng` |

The 3B is the harder real-time target, which makes it the more interesting
half rather than the weaker one: if the preemption model shows up anywhere
it shows up where the machine is under pressure.

**The thresholds do not move with the board.** A 99.9th percentile below
50 us and a maximum below 150 us were written for the Pi 4 and stay as
written. If the 3B misses them that is a measurement, and every results row
records which board it was taken on. A threshold chosen after seeing the
hardware is not a threshold, it is a description.

The relative criterion is the one that carries the argument anyway: the
generic kernel several times worse than the real-time one, under the same
load, on the same hardware, with the same userspace. That is a property of
the preemption model and it holds on either board.

## The one thing to check before building anything

`PREEMPT_RT` is not selectable on the kernel this repository has been using.

```
kernel/Kconfig.preempt      config PREEMPT_RT
                              depends on EXPERT && ARCH_SUPPORTS_RT
arch/arm64/Kconfig          select ARCH_SUPPORTS_RT      (in 6.12, not 6.6)
meta-raspberrypi scarthgap  PREFERRED_VERSION_linux-raspberrypi ??= "6.6.%"
```

So a fragment containing `CONFIG_PREEMPT_RT=y` on the default BSP kernel
asks for a symbol that has no prompt. kconfig drops it without a word, the
build succeeds, and the board boots a kernel that is not preemptible. That
is why `kas/bench-rt.yml` sets the kernel version as well as the switch,
and why `uname -v` and `./go kconfig -f rt-common -f rt` are both in the acceptance
list rather than one of them.

## What is in the image beyond Project 1, and why

| Package | Why it is there | What breaks without it |
|---|---|---|
| `rt-tests` | cyclictest, the reference instrument everybody quotes | no internal reference to compare the wire against |
| `stress-ng` | the load. CPU, memory and disk at once, which is what makes a generic kernel's tail appear | a latency lab that only measures an idle board, which is the easy case |
| `util-linux-taskset` | confines the load and the capture to the housekeeping cores | they land on the isolated core and the run measures itself |
| `python3-numpy` | 6 million samples per run, and the analysis runs on the board | a feedback loop that goes through an SD card reader |
| `libdaqhats` | the vendor library; there is no in-kernel IIO driver for this HAT | no instrument |
| `python3-daqhats` | the ctypes wrapper the capture script uses | the same |
| `kernel-module-spidev` | `bench.cfg` builds spidev as a module, and `core-image-minimal` installs no modules at all | the HAT is present, the EEPROM is read, and every scan fails. This repository has paid for this exact mistake once already, with `brcmfmac` |
| `libgpiod`, `libgpiod-tools` | already in `bench-image`; `gpioset` is how the wiring is confirmed by hand before any run | nothing, but the bring-up gets much harder |

`vcgencmd` is a recommendation rather than a dependency. It reports the
throttle state, and the scripts record "unknown" without it, which is the
right behaviour when the same lab is repeated on hardware that is not a Pi.

## Acceptance criteria

The criteria this project is held to, what would count as evidence for
each, and where that stands today.

| # | Criterion | Evidence | State |
|---|---|---|---|
| 1 | `/sys/kernel/realtime` reads 1 on the RT kernel and is absent on the generic one | the `realtime` column of every row, and `uname -v` beside it | **superseded, and the criterion as worded cannot be met.** That file came from the out-of-tree RT patches and did not survive the merge into mainline for 6.12, so it is absent on **both** kernels here. `uname -v` is the authority instead, per decision 74, and the `realtime` column is derived from it: 10 rows `yes`, 8 rows `no` |
| 2 | A 60 s capture at 100 kS/s with zero overruns, and 30000 +/- 1 rising edges | `ext_edges` in the row; `rt-capture` voids the run on any overrun | **measured, and the tolerance is not met.** No run was voided, so the overrun half holds across all 18 rows. `ext_edges` never reaches 30000: the 16 sound rows run 29984 to 29997, and two rows are genuinely short at 28941 and 29124 and both have repeats. A tolerance of +/- 1 was never achievable on this instrument and no cause is offered for the 3 to 16 edge shortfall, because none was investigated |
| 3 | The external histogram reproduces the internal one in shape: spread a factor of sqrt(2) larger, maxima agreeing, and any excess reported as write-path variation | `rt-compare` per run, which `rt-run` calls at the end of one | **measured**, `rt-compare` ran at the end of every run and the ratio is discussed across the matrix in [results/README.md](results/README.md). One row, `rt-iso-aff-performance`, returns a ratio of 12.430 and a write-path figure of 7.653 us that are arithmetically correct and not usable, because its standard deviation is carried by a handful of excursions rather than by a distribution. That is recorded as a gap in `rt-compare` |
| 4 | RT, isolated, affinity, under load: external p99.9 below 50 us and maximum below 150 us; the generic kernel at least five times worse | two rows of `results.csv` | **measured, and not met on any of its three clauses.** RT `ext_p999_us` is 71.084 and 63.916 against a target below 50. `ext_max_us` is 1054.020 and 989.682 against a target below 150, and no row in the file is under 150 because of the unattributed pin excursion. The generic counterpart is 99.316, which is 1.4 times worse rather than five. The improvement PREEMPT_RT does deliver on this pair is a third, and the criterion set a bar this bench has not reached |
| 5 | cyclictest agrees with the toggler's own histogram, and both agree with the wire by the sqrt(2) relationship | the `cyc_*`, `int_*` and `ext_*` columns of one row, and `rt-compare`'s ratio | **columns present in all 18 rows, agreement not assessed.** The second clause is criterion 3 and is measured there. The first clause, `cyc_max_us` against `int_max_us`, is not evaluated anywhere in [results/README.md](results/README.md), and the two disagree substantially in the rows spot-checked. Whether that is instrument disagreement or the ordinary instability of a maximum is an open question and needs the series RC that criterion 5 already calls for |
| 6 | Every row names kernel, isolation, affinity, governor, load and the throttle status before and after | the CSV header has 27 columns and `rt-run` fills all of them | **met in the code**, proven by `tests/rt-run-test.sh`, unproven on a board |
| 7 | The kernel fragment actually reached the kernel | `./go kconfig -f rt-common -f rt` against the `.config` kconfig produced, and later against `/proc/config.gz` from the running board | **met on the build host for both machines**, 16 Sep 2026: all 31 options of both fragments present in the 6.12.93 `.config`, `CONFIG_PREEMPT_RT=y` among them and the other three members of its choice block excluded. Evidence for [`raspberrypi4-64`](docs/evidence/kconfig-check-raspberrypi4-64.txt) and [`raspberrypi3-64`](docs/evidence/kconfig-check-raspberrypi3-64.txt), each named for the machine it was captured on. Not yet confirmed against a running kernel. **Both captures are of the real-time arm and predate the 17 Sep fragment split. The control was never checked at all, which is how it came to receive no fragment, and re-running this criterion against both arms is part of the next cycle** |
| 8 | Every fragment line is a symbol this kernel has | `./go ksym -f rt-common -f rt` | **met**, against the real `rpi-6.12.y` Kconfig text: 31 symbols, all declared, 2 promptless and recorded as such |

Criterion 4 is the one with a caveat attached, and it is in
[METHOD.md](docs/METHOD.md): a 150 us threshold measured through an
unresolved edge carries 10 us of quantisation, which is fine, and the same
method cannot support a claim about the few microseconds of system-call
cost, which is criterion 5. Criterion 5 needs the series RC.

## Results

All 18 rows are measured, eight generic and ten PREEMPT_RT, taken in one
session on 17 September 2026 and living in
[results/results.csv](results/results.csv). The full reading of them, the
`ext_p999_us` comparison table, the two short rows, the one row where the
standard deviation is not a summary, and the two rows deliberately not
taken, are all in [results/README.md](results/README.md).

**Read that file before quoting any number from this matrix.** Three
things in it qualify what can be said. The excursion of several hundred
microseconds to over a millisecond that appears at the pin in every single
row, and in neither internal instrument, is **not attributed**: the
candidates are the SPI path to the HAT, the recorder, and firmware
activity under the kernel, and separating them needs an experiment this
matrix does not contain. The 51 percent gain on the affinity-without-
isolation pair rests on one generic row that reads as bad rather than as
an effect. And the earlier generic-only matrix at
[results/2026-09-17_5ec99fd-dirty/](results/2026-09-17_5ec99fd-dirty) is
superseded, not deleted.

### The whole matrix in one figure

![ext_p999_us for every configuration, generic against PREEMPT_RT](results/ext-p999-matrix.svg)

Seven configurations, eighteen runs, drawn from
[results/results.csv](results/results.csv) by `./go matrix`. Each row is one
configuration; the upper mark of a pair is the generic kernel and the lower
one PREEMPT_RT, so the **slope of the connector is the effect**: near
vertical is no effect, a long diagonal is a large one.

**Every repeat is its own mark, and nothing is averaged.** That is what
makes the figure readable against the caution above rather than around it.
Where a row shows two marks of one colour far apart, the spread between two
runs of the same kernel is doing more work than the difference between the
two kernels, and the pair is not evidence of much.

Three things to read off it, in the order they matter:

1. **The top band is flat.** With CPU 3 still in the scheduler's general
   pool, the connectors are vertical or nearly so. `performance, load` is
   the extreme case: both kernels at exactly 100.419, drawn as two marks in
   the same column.
2. **The bottom band separates.** Every configuration with `isolcpus` and
   `nohz_full` covering the measured core shows a visible diagonal.
   Isolation is the precondition and the real-time kernel is the increment,
   which is the reverse of the order the two are usually presented in.
3. **The longest diagonal is the one to distrust.** `aff, performance,
   load` spans from 110 to 227 us and sits in the *unisolated* band. It is
   the 51 percent pair, and it rests on a single generic row with no repeat.
   The figure draws it at full length because that is what was measured; the
   reason not to quote it is in [results/README.md](results/README.md).

### Isolation is the whole story on this board

The two figures in this section are from the **superseded** generic-only run
of 17 September, kept because they are the only per-configuration histograms
this project has. See the note at the end of
[results/README.md](results/README.md).

![cyclictest wake-up latency under load](results/2026-09-17_5ec99fd-dirty/cyclictest-loaded.svg)

Two 60 second runs at 1 kHz, `stress-ng --cpu 3 --vm 2 --vm-bytes 128M
--hdd 1` on the housekeeping cores in both. The count axis is logarithmic
because 99 percent of the samples sit in the first few bins and the
argument is entirely in the tail.

| | `cyc_avg_us` | `cyc_max_us` | `int_max_us` |
|---|---|---|---|
| stock, loaded | 14 | 277 | 324 |
| `isolcpus` + IRQ affinity, loaded | 6 | **116** | 151 |

The four configurations together, idle and loaded:

![cyclictest wake-up latency, four configurations](results/2026-09-17_5ec99fd-dirty/cyclictest-isolation.svg)

The worst case across the eight rows, in order taken:

| Row | Isolation | Affinity | Governor | Load | `cyc_max_us` |
|---|---|---|---|---|---|
| 1 | no | no | ondemand | no | 77 |
| 2 | no | no | ondemand | yes | 277 |
| 3 | no | no | performance | yes | 488 |
| 4 | no | yes | performance | yes | 483 |
| 5 | **yes** | no | performance | yes | 99 |
| 6 | **yes** | yes | performance | no | **42** |
| 7 | **yes** | yes | performance | yes | 116 |
| 8 | **yes** | yes | force_turbo | yes | 125 |

Under load, 277 to 488 us without isolation and 99 to 125 us with it.
Governor and IRQ affinity move nothing outside the run-to-run spread, and
that spread is itself larger than the effect: rows 2, 3 and 4 differ only
in settings that should not matter and their `int_max_us` reads 324, 277
and 514. A maximum is a single observation of a rare event, so the rows
that matter need repeats before any of them is quoted as a figure.

### Regenerating the figures

```
./go plot -o FIG.svg -t TITLE FILE[:LABEL] ...
./go matrix -o FIG.svg RESULTS.CSV
```

`plot` draws a histogram from one instrument's own file; `matrix` draws the
paired comparison from a whole `results.csv`. Neither is ever drawn by hand,
so a figure can always be traced back to the capture that produced it. See
decision 86.

To regenerate the matrix figure in this README:

```
./go matrix -o projects/08-preempt-rt/results/ext-p999-matrix.svg \
    projects/08-preempt-rt/results/results.csv
```

and `tests/rt-matrix-test.sh` fails if the committed figure and the
committed `results.csv` have drifted apart, so a figure cannot go stale
quietly. `--metric` draws any other column of the schema the same way.

### The schema

The schema is documented in [results/README.md](results/README.md), and
the file on the board lives at `/var/lib/bench/rt/results.csv`; copying it
here is the last step of a campaign.

The sixteen rows the matrix is made of:

| Kernel | Isolation | Affinity | Governor | Load |
|---|---|---|---|---|
| generic | no | no | ondemand | no |
| generic | no | no | ondemand | yes |
| generic | no | no | performance | yes |
| generic | no | yes | performance | yes |
| generic | yes | no | performance | yes |
| generic | yes | yes | performance | no |
| generic | yes | yes | performance | yes |
| generic | yes | yes | fixed (force_turbo) | yes |
| rt | no | no | ondemand | no |
| rt | no | no | ondemand | yes |
| rt | no | no | performance | yes |
| rt | no | yes | performance | yes |
| rt | yes | no | performance | yes |
| rt | yes | yes | performance | no |
| rt | yes | yes | performance | yes |
| rt | yes | yes | fixed (force_turbo) | yes |

Isolation changes need a reboot, so the order that minimises reboots is
the one grouped by kernel and then by isolation, which is the order above.

## What is tested without hardware

| Check | Command | Covers |
|---|---|---|
| Edge timing arithmetic | `sh tests/rt-analyze-test.sh` | Period recovery against a synthesised wave with known edges, both edge regimes, the clock offset, a single late edge, the no-edges error |
| The run protocol | `sh tests/rt-run-test.sh` | Ordering, core confinement, both directions of the isolation claim, the throttle gate, an overrun voiding the run, and every column of the row |
| Interrupt affinity | `sh tests/rt-irq-affinity-test.sh` | Movable against kernel-owned interrupts, ranges in a CPU list, the failure that matters |
| Host compile | `./go check` | `rt-toggle` with `-Werror` against host libgpiod v2 |
| Fragment symbols | `./go ksym -f rt-common -f rt` | That every line names a real Kconfig symbol, and that a promptless one is declared as a consequence rather than presented as a request |
| The fragments | `./go kconfig -f rt-common -f rt CONFIG` | Every line of both, including the ones that ask for an option to stay off |
| Instrument comparison | `sh tests/rt-compare-test.sh` | That a constant write cost is invisible, that 2 us of write jitter is recovered as 2 us, that correlated latencies are refused rather than interpreted, and that all three file formats parse |
| The symbol checker itself | `sh tests/kernel-symbols-test.sh` | All five Kconfig declaration shapes against a six-file kernel, including the two that the checker got wrong first |

Not covered, and only a board can cover it: that a PREEMPT_RT kernel boots
on this hardware, that the HAT enumerates, that the vendor library
cross-compiles, that a 100 kS/s scan sustains without overrunning, and
every number in the results table.

## Departures from the original scope

| # | As originally scoped | Here | Why |
|---|---|---|---|
| 1 | Build the kernel by hand from a git clone, with `merge_config.sh` | A Yocto fragment and a kas file | It is the same fragment mechanism Project 1 already uses, and it keeps the rootfs identical between the two kernel rows, which is what the comparison needs |
| 2 | `kernel=kernel8-rt.img` in `config.txt` | The same, plus `device_tree=` and `overlay_prefix=` pointing at the RT build's own dtbs | A 6.12 kernel with the 6.6 BSP's overlays is a combination nobody has tested, and a device tree mismatch does not announce itself |
| 3 | Interpolation works because the edge is fast | Interpolation works because the edge is slow; both regimes are supported and measured | Arithmetic, in [METHOD.md](docs/METHOD.md). A fast edge makes the interpolated fraction a constant |
| 4 | No resistor or capacitor in the parts list | A 1 kohm and a 10 nF are recommended for the rows that need sub-sample resolution, and are **not on this bench**, so the matrix runs at 10 us per-edge resolution | The same reason. Measured rather than assumed: the first hardware run reported `subsample_fraction=0.150` and `sample_us=10.000`, so `sd`, `p99.9` and `max` carry that quantisation while the mean and the clock offset do not. The comparison survives, because both kernels are quantised identically; absolute claims finer than 10 us do not. See [BRINGUP step 4](docs/BRINGUP.md) |
| 5 | `daqhats/install.sh` on the board | Two Yocto recipes, pinned to a commit | The image has no compiler, no git and no pip. Also, the vendor makefile hardcodes `gcc` and `-I/usr/include`, which in a cross build silently takes host headers |
| 6 | `rt_toggle` takes positional arguments | `rt-toggle` takes options, writes a self-describing header, and handles signals | It is driven by a script that has to record what it ran, and a run interrupted by hand should still release the line |
| 7 | The matrix script sets the knobs | `rt-run` sets them and then verifies the kernel agrees | `isolcpus=3` in a file is not isolation, and a row labelled wrongly makes the whole table unusable |

## Pitfalls, and what guards each one

| Pitfall | Guard |
|---|---|
| The capture or the load runs on the isolated core | `rt-run` starts both under `taskset -c $RT_HOUSEKEEPING`; the test asserts it |
| The scan overruns silently and the run has a gap | `rt-capture` checks both overrun flags per chunk and exits non-zero; `rt-run` then voids the run and writes no row |
| Thermal throttling changes the clock mid-run | `vcgencmd get_throttled` before and after, both in the row; a throttling board refuses to start |
| `isolcpus` without `nohz_full` and `rcu_nocbs` | the refusal message names all three, and `rt.cfg` carries the reason |
| Interrupts that cannot be moved are reported as failures | `rt-irq-affinity check` writes an interrupt's own affinity back to it: succeeding means it was movable and is a real finding, failing means the kernel owns it |
| The SD card is written by the stressor and the capture at once | the capture goes to `/dev/shm`, and only the histogram is kept |
| `CONFIG_PREEMPT_RT` is silently dropped | the kernel version is pinned in the kas file, and `./go kconfig -f rt-common -f rt` checks the built config |
| A switch meant to gate one symbol gates a whole fragment | the variable is alone in `rt.cfg`; everything else is in `rt-common.cfg` behind `BENCH_RT_LAB`, which both arms set. Eight rows were measured before this was found, and only the serial console found it |
| The 10 us sample period is mistaken for the resolution | `subsample_fraction` is measured, warned about and recorded in every row |

---

[Journal](JOURNAL.md) | [Design](docs/DESIGN.md) |
[Method](docs/METHOD.md) | [Bring-up](docs/BRINGUP.md) |
[Results](results/README.md)
