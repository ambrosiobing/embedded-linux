# Project 8: a PREEMPT_RT latency lab with the MCC 118 as the instrument

**Board:** Raspberry Pi 4. **Theme:** real-time kernel, cyclictest, IRQ
affinity, jitter measurement.

Real-time Linux is usually argued about with cyclictest numbers, and
cyclictest measures the kernel from inside the task the kernel is
scheduling, on the kernel's own clock. That is a useful number and it is
not the number an actuator experiences. This project adds a second
instrument that shares nothing with the first except a wire: an MCC 118 DAQ
HAT samples the pin that the real-time task toggles, at 100 kS/s, on its own
crystal. The period it reports includes the wake-up latency **and** the cost
of the system call that moved the pin.

Comparing the two is the lesson. When they agree, the GPIO write is cheap
and constant and the internal number was trustworthy. When they disagree by
a changing amount, something is delaying the system call itself, and no
amount of cyclictest would have shown it.

The knobs are the ones an embedded interview asks about: the preemption
model, CPU isolation, interrupt affinity, the frequency governor and load.
Each is switched on alone and in combination, and each produces a
histogram rather than a single worst case.

Project 1 built the layer, the image and the cross SDK. This project is the
first to change the kernel itself.

## State

**Everything is written and nothing has been run.** No image has been
built, no kernel has been compiled, no board has been booted and the HAT
has never been on the header. The results table below is empty on purpose;
it has a schema and no rows.

What is proven today, on a laptop and in CI:

| Proven | How |
|---|---|
| `rt-toggle` compiles clean with `-Wall -Wextra -Werror` against libgpiod v2 | `./go check` and CI |
| `rt-analyze` recovers a known jitter from a synthesised waveform to 0.3 us | `tests/rt-analyze-test.sh`, 21 assertions |
| An unresolved edge is detected and reported rather than silently trusted | the same test, both regimes |
| The run protocol keeps its order and refuses every invalid claim | `tests/rt-run-test.sh`, 51 assertions against stubs |
| Movable and kernel-owned interrupts are distinguished correctly | `tests/rt-irq-affinity-test.sh`, 14 assertions |
| `PREEMPT_RT` is selectable on this kernel at all | read out of `kernel/Kconfig.preempt` and `arch/arm64/Kconfig` in `rpi-6.12.y`, see below |
| The fragment check catches a kernel built without it | `./go kconfig -f rt` against a deliberately broken config |
| Every symbol in `rt.cfg` and `bench.cfg` is real, and two are promptless | `./go ksym -f rt` against the `rpi-6.12.y` Kconfig text |

What that does not prove is any latency number whatsoever. See
[Acceptance criteria](#acceptance-criteria) for which rows are evidence and
which are still plans, and the [journal](JOURNAL.md) for the decisions and
the places where this departs from the original scope on purpose.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/rt.cfg` | The opt-in kernel fragment: `PREEMPT_RT`, `NO_HZ_FULL`, `RCU_NOCB_CPU`, and the debug options that have to be off |
| `kas/bench-rt.yml` | The fragment switch, the kernel version that can honour it, SPI, `meta-python` |
| `meta-bench/recipes-core/images/bench-rt-image.bb` | `bench-image` plus both instruments and the load generator |
| `meta-bench/recipes-bench/bench-rt/` | `rt-toggle`, `rt-capture`, `rt-analyze`, `rt-run`, `rt-irq-affinity` and their configuration |
| `meta-bench/recipes-bench/daqhats/` | The vendor library and its Python bindings, pinned to a commit, cross-compiled |
| `scripts/rt-kernel-install.sh` | Puts the RT kernel on a card beside the generic one, with a one-line way back |
| `scripts/check-kernel-config.sh` | Extended: `-f rt` checks the real-time fragment too |
| `scripts/check-kernel-symbols.sh` | The check that runs before a build: is each fragment line a symbol the kernel can receive |
| `tests/rt-analyze-test.sh` and two more | What can be proven without the instrument |

## Running it

```sh
./go check                   # about 2 minutes, no board and no HAT
./go ksym -f rt              # after the kernel unpacks, before it compiles
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
and why `/sys/kernel/realtime` and `./go kconfig -f rt` are both in the
acceptance list rather than one of them.

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
| 1 | `/sys/kernel/realtime` reads 1 on the RT kernel and is absent on the generic one | the `realtime` column of every row, and `uname -v` beside it | **not started**, needs a board |
| 2 | A 60 s capture at 100 kS/s with zero overruns, and 30000 +/- 1 rising edges | `ext_edges` in the row; `rt-capture` voids the run on any overrun | **not started** |
| 3 | The external histogram reproduces the internal one in shape, and the difference is a stable offset | both histograms are kept per run, and the sequence diagram in DESIGN.md says what the offset is | **not started** |
| 4 | RT, isolated, affinity, under load: external p99.9 below 50 us and maximum below 150 us; the generic kernel at least five times worse | two rows of `results.csv` | **not started** |
| 5 | cyclictest alone agrees with the external measurement to within the system-call cost | the `cyc_*` and `ext_*` columns of the same row | **not started** |
| 6 | Every row names kernel, isolation, affinity, governor, load and the throttle status before and after | the CSV header has 27 columns and `rt-run` fills all of them | **met in the code**, proven by `tests/rt-run-test.sh`, unproven on a board |
| 7 | The kernel fragment actually reached the kernel | `./go kconfig -f rt` against `/proc/config.gz` from the running board | **tooling ready**, exercised against a synthetic config |
| 8 | Every fragment line is a symbol this kernel has | `./go ksym -f rt` | **met**, against the real `rpi-6.12.y` Kconfig text: 31 symbols, all declared, 2 promptless and recorded as such |

Criterion 4 is the one with a caveat attached, and it is in
[METHOD.md](docs/METHOD.md): a 150 us threshold measured through an
unresolved edge carries 10 us of quantisation, which is fine, and the same
method cannot support a claim about the few microseconds of system-call
cost, which is criterion 5. Criterion 5 needs the series RC.

## Results

```
projects/08-preempt-rt/results/results.csv
```

Empty, with a header. The schema is documented in
[results/README.md](results/README.md), and the file on the board lives at
`/var/lib/bench/rt/results.csv`; copying it here is the last step of the
matrix.

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
| Fragment symbols | `./go ksym -f rt` | That every line names a real Kconfig symbol, and that a promptless one is declared as a consequence rather than presented as a request |
| The fragment | `./go kconfig -f rt CONFIG` | Every line of `rt.cfg`, including the ones that ask for an option to stay off |
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
| 4 | No resistor or capacitor in the parts list | A 1 kohm and a 10 nF are recommended for the rows that need sub-sample resolution | The same reason |
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
| `CONFIG_PREEMPT_RT` is silently dropped | the kernel version is pinned in the kas file, and `./go kconfig -f rt` checks the built config |
| The 10 us sample period is mistaken for the resolution | `subsample_fraction` is measured, warned about and recorded in every row |

---

[Journal](JOURNAL.md) | [Design](docs/DESIGN.md) |
[Method](docs/METHOD.md) | [Bring-up](docs/BRINGUP.md) |
[Results](results/README.md)
