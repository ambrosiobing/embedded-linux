# Project 5: an IIO driver for the ADXL345 written from scratch

**Board:** Raspberry Pi 3. **Theme:** kernel driver model, regmap, threaded
IRQ, IIO events.

The kernel already has an ADXL345 driver. This one is written anyway, and
the interesting question is not whether that is worth doing but how to say
anything honest about the result. The answer here is that both drivers are
installed and the device tree decides which one binds, so mainline becomes
the control rather than the competition.

Everything else follows from one structural decision the repository made
before this project started: `walkthrough/06-mechanism-policy.md` says
"Project 5's driver has such a seam at the regmap layer". One core that
speaks only `struct regmap *`, an I2C file and an SPI file either side of
it, and the core does not know which is loaded.

## State

**Built, bound and measured, with nothing open.** As of Saturday 17
October 2026: the module compiles against the image's 6.6.63 kernel,
binds to the part on the bench through this project's own overlay, and
every criterion below has been read on the board, including the one this
project exists to make possible, which is the same hardware under
mainline's driver as a control. 95 assertions pass with no board and no
kernel tree.

Three sentences of this section said the opposite until today, and they
were true when they were written. **Nothing holds a sentence.** What
replaced them:

- the driver first compiled on Friday 9 October 2026 and the modules
  were packaged and installed the same day
- the overlay this section used to call deliberately missing is
  `meta-bench/recipes-bench/bench-adxl345-dt/`, written once the bench
  had been read: `0x53` on `i2c-1`, `INT1` on header pin 16, GPIO23
- every criterion is measured. The last of them, 7, took one word in
  `config.txt` and a reboot, which is what the design document promised
  the A/B pair would cost

**What the board is running, since Saturday 17 October 2026:** the image
built at `8d17d9b`, flashed that morning, which is the first card to
carry the probe that writes whole registers and the first to carry the
triggered path. Read on the board immediately after the first boot,
`DATA_FORMAT` was `0x0b`, the three offset registers `0x00`, `BW_RATE`
`0x0a` and `INT_ENABLE` `0x00`: the part in a known state from a cold
start rather than by hand. The rows measured before that date name the
commit they were taken on, which was `e3574c8` with its registers
corrected by hand.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/adxl345.cfg` | The regmap glue the driver needs, and mainline's ADXL345 driver as its control |
| `meta-bench/recipes-bench/bench-adxl345/` | The driver: a bus independent core, an I2C file, an SPI file, and the first recipe in this layer that compiles kernel code |
| `meta-bench/recipes-core/images/bench-adxl345-image.bb` | The image, naming all five module packages |
| `kas/bench-adxl345.yml` | `./go adxl345` |
| `tests/adxl345-driver-test.sh` | What can be proven about a driver that cannot be built here |

## Running it

```sh
./go check                 # about 2 minutes, no board and no kernel tree
./go ksym -f adxl345       # after the kernel unpacks, before it compiles
./go adxl345               # bench-adxl345-image for the Raspberry Pi 3
./go kconfig -f adxl345    # did the fragment reach the .config
./go flash /dev/sdX
```

[docs/DESIGN.md](docs/DESIGN.md) is the methodology: what the three files
are and why there are three, where the seam is, how the two drivers avoid
each other, and what userspace sees. Read it before the code.

The [journal](JOURNAL.md) has the path that produced it, including the two
things the repository had already decided about this project before anyone
started writing it.

## Two drivers for one part, on purpose

The overlay names which driver it wants:

| Overlay says | Driver that binds | What it is |
|---|---|---|
| `compatible = "bench,adxl345"` | this project's | the thing under test |
| `compatible = "adi,adxl345"` | `drivers/iio/accel/adxl345_*` | the control |

Neither can bind to the other's node, so both are installed and no load
order decides anything. Swapping the string is an edit to one line on the
FAT partition and a reboot.

**Why that is worth the trouble.** A driver written from scratch invites one
question, which is whether it does the same thing as the one everybody else
uses. Without a control, the answer is a shrug and some plausible numbers.
With one, every reading this project takes has a counterpart taken on the
same board, the same bus, the same afternoon and the same temperature.
Project 8 needed two kernel builds to get a control that honest; here it
costs a string.

The cost is that the overlay is not portable to a machine running the
in-tree driver. That is correct rather than unfortunate: an overlay
describes one bench, and a node asking for a driver nobody has is a node
that does not probe.

## What is in the image beyond Project 1, and why

| Package | Why | What breaks without it |
|---|---|---|
| `kernel-module-bench-adxl345-core` | the bus independent half, and where the probe lives | both bus modules load and find no `bench_adxl345_core_probe` |
| `kernel-module-bench-adxl345-i2c` | binds the node when the part is on I2C | the node is described and nothing claims it |
| `kernel-module-bench-adxl345-spi` | the same for SPI | as above, on the other bus |
| `kernel-module-adxl345-i2c`, `-spi` | mainline's driver, the control | the comparison needs a second image and a second build |
| `bench-iio` | Project 10's `iio-probe`, `iio-rate`, `iio-decode` | nothing reads the buffer, and the inventory that says which driver bound has to be done by hand |

**Five module lines, and every one of them is a package rather than a
kernel option.** `adxl345.cfg` compiles all five; naming them here is what
puts them in the rootfs. This repository has lost a board to that
distinction twice, which is Decision 75 and why `scripts/lint.py` has
`check_image_packages`.

## Acceptance criteria

The criteria this project is held to, what would count as evidence for
each, and where that stands. "Configured" means a file says so; "measured"
means a board did.

| # | Criterion | Evidence | State |
|---|---|---|---|
| 1 | The driver compiles as an out-of-tree module against the image's kernel | `./go adxl345` completing, and three `.ko` in the work directory | **Measured**, Friday 9 October 2026: `./go adxl345` completed at commit `b20546d` and the flashed card carries `bench-adxl345-core.ko.xz`, `-i2c` and `-spi` under `lib/modules/6.6.63-v8/updates/`. The first attempt stopped on four differences between the v6.12 the driver was written from and the 6.6 it runs on; journal section 7 |
| 2 | The part is identified before it is configured: probe reads `DEVID` and refuses on anything but `0xe5` | `dmesg` on a board with the part, and on one without | **Measured**, Friday 9 October 2026: on the card at `76d1e89` the probe at 7.07 s logged `no interrupt, so sysfs only and no buffer` and registered `iio:device0`. The refusal half was measured the same evening by accident: at 400 kHz the bus answered nothing and the probe logged `cannot read DEVID` and failed with `-121`; journal section 11 |
| 3 | `in_accel_x_raw` and its siblings read, and `in_accel_scale` reports a value that turns one g into 9.81 m/s^2 | the four sysfs files, and a reading with the board flat | **Measured**, Friday 9 October 2026, board flat: `name` `bench-adxl345`, `in_accel_scale` `0.038245935`, x `-8`, y `46`, z `242`, which is 0.95 g on z. The arithmetic is still asserted by `tests/adxl345-driver-test.sh` |
| 4 | The output data rate can be set and read back through `in_accel_sampling_frequency` | write 100, read 100, and the same for 3200 | **Measured**, Friday 9 October 2026: `100.000000` and `3200.000000` read back. This row used to name the file `sampling_frequency`, which does not exist: the channel declares the rate shared by type, so the attribute carries the `in_accel_` prefix, as mainline's does |
| 5 | A triggered buffer fills from the part's own FIFO on a watermark interrupt, and `iio-decode` turns it into CSV without knowing what the part is | a capture with `iio-rate`, decoded by Project 10's tool | **Measured**, Friday 9 October 2026, `INT1` on GPIO23 level high: `iio-rate fifo bench-adxl345 100 24` gave 960 samples in 10 s and 40 interrupts, 4.00 per second against 4.17 expected; watermark 8 gave 120 interrupts, 12.00 against 12.50; timestamp spread 1.7 ms and 0.96 ms once the driver spread each batch back from the interrupt. Journal sections 13 and 14  **And a figure nobody had taken, Saturday 17 October 2026:** every capture of this path has been made through `iio-rate`, which writes `buffer/watermark` first, so the default was never measured. It is 1, because the IIO core initialises the buffer's watermark to 1 and overwrites what probe put there. Measured: 96.7 interrupts a second against 4.0 with 24 written, a factor of 24.2 on a 32 sample FIFO. `docs/evidence/fifo-watermark-2026-10-17.md` |
| 6 | Single tap, double tap and free fall arrive as IIO events rather than as an invention of this driver | `iio-events` output while the board is tapped | **Measured**, Friday 16 October 2026, twice. The second run is the one to read: with the registers put right and only single tap armed, 33 events in 20 seconds, in `docs/evidence/events-singletap-2026-10-16.csv`. The first run, `events-2026-10-16.csv`, carried two double taps and a free fall and was taken with the interrupt polarity inverted. This row read "Configured" for two weeks while the three events could not fire at all; journal sections 14, 17, 18 and 19 |
| 7 | Swapping the compatible string in the overlay moves the same hardware onto mainline's driver, and the two agree | two captures, one per driver, on the same board | **Measured**, Saturday 17 October 2026, eleven minutes apart on one part with one word changed in `config.txt`. The axes agree to a count and the magnitudes to 0.28 per cent, which is this part's own noise. The scales differ by 0.141 per cent, and both derivations are written down: ours takes the datasheet's rounded 3.9 mg/LSB, mainline takes the 13-bit span with g as 9.81. Against the datasheet's own 256 LSB/g, ours is 0.160 per cent low and mainline 0.019 per cent low. `docs/evidence/drivers-ab-2026-10-17.md` |
| 8 | Every symbol in the fragment is real, and every one reaches the built `.config` | `./go ksym -f adxl345` before, `./go kconfig -f adxl345` after | **Measured**, Saturday 17 October 2026, both halves. `./go ksym` against the 6.6.63 tree, 20854 declarations indexed: every line of `bench.cfg` and `adxl345.cfg` names a symbol that exists, and three are promptless rather than the one this project had thought about. `./go kconfig` then read the `.config` the build wrote at 07:44 and found every option of both fragments present. `CONFIG_REGMAP_I2C=y` and `CONFIG_REGMAP_SPI=y`, so the two predictions are true in this image and are now evidence rather than reasoning; `CONFIG_ADXL345=m` beside the two bus modules; `CONFIG_INPUT_ADXL34X` off, which is what keeps those two satisfiable; and `CONFIG_IIO_TRIGGER=y`, which is the one kernel symbol row 11's triggered path needs |
| 11 | A trigger drives the buffer: one scan per trigger through `/dev/iio:device0`, which is the middle of the three paths `docs/DESIGN.md` compares | a capture whose scans carry timestamps the core took, spaced by the trigger and not by arithmetic | **Measured**, Saturday 17 October 2026, on the first card to carry this driver: five scans fired one second apart came back 1.015137, 1.015712, 1.015848 and 1.015909 seconds apart, each timestamped when its trigger fired. x -10, y 54, z 241 counts, a magnitude of 247.1 against the 246.5 the same board read through sysfs on Friday 9 October 2026. `docs/evidence/triggered-2026-10-17.md`. A sysfs trigger rather than an hrtimer one, because this image sets `BENCH_ADXL345_KERNEL` and not `BENCH_IIO_KERNEL`, so it has no `CONFIG_IIO_HRTIMER_TRIGGER`; a trigger faster than the part's output rate is therefore still unmeasured |

This row is numbered 11 rather than 9 because 9 and 10 are the asserted
pair below, and renumbering them would break the references in
`JOURNAL.md` and `walkthrough/DECISIONS.md`. It was added on Saturday 17
October 2026, the day the path it describes was written: for the three
weeks before that, `docs/DESIGN.md` claimed three paths out of the part,
no criterion covered the middle one, and nothing noticed.

Beyond those, three things this repository asserts that the theme does
not ask for:

| # | Criterion | State |
|---|---|---|
| 9 | The core never learns what a bus is | Asserted: the test fails if `bench-adxl345-core.c` includes `i2c.h` or `spi.h` |
| 10 | Every module the recipe builds is named in the image | Asserted, and the test fails if any of the five is dropped |
| 12 | The two buffer paths cannot fill one capture together | Asserted: both halves of the buffer setup ops branch on an attached trigger, and the test fails if either stops asking |

## What is tested without hardware

| Check | Command | Covers |
|---|---|---|
| The driver as text | `sh tests/adxl345-driver-test.sh` | 95 assertions, counted from the suite's own summary line on Saturday 17 October 2026: the compatible string in both bus files and never mainline's, the seam, the namespace import, every register defined exactly once, the scale against its own derivation, the watermark below the FIFO depth, all five modules reaching the image, the promptless symbol carrying its consequence marker, every configuration register written whole rather than merged, the event defaults against the datasheet's recommended ranges, and the seven silent failures of the triggered path |
| Static layer checks | `./go lint` | The recipe's `SRC_URI`, ASCII, line length, the kas file's YAML |

**What none of it proves.** That the driver compiles, that it probes, or
that a single reading is correct. The suite reads text and asserts that the
claims files make about each other are true. It cannot see a logic error
inside a function, and it has no opinion about whether `regmap_bulk_read`
was given the right length. The compile is CI's job once there is a kernel
tree, and the numbers are the board's.

## Deferred, with reasons

| What | Why | What would close it |
|---|---|---|
| ~~The device tree overlay~~ | **Closed Friday 9 October 2026.** It needed an I2C address and an interrupt GPIO, both properties of how this bench's DFRobot SEN0032 is wired rather than of the part, and DFRobot publishes the chip's capability and no pin list. The board was read instead of guessed: `0x53` on `i2c-1`, `INT1` to header pin 16, GPIO23, level high | `meta-bench/recipes-bench/bench-adxl345-dt/` |
| Anything on the SPI bus | The driver is written for both because that is the subsystem's shape. The breakout does expose all four lines, which was read off the board on Sunday 4 October 2026 and is in `docs/DESIGN.md` with the strapping hazard attached, so what is deferred is now the measuring rather than the question | A second overlay on `spi0`, and the three straps moved. Nothing in the driver changes: that is what the regmap seam is for |
| The activity and inactivity events | The part detects them and the driver does not yet route them. They need threshold and time registers exposed as IIO event attributes, which is a larger surface than tap and free fall | Worth doing once the interrupt path is proven by the simpler events |

**The supply is the one that can cost you something.** A breakout rated to
6 V regulates, and if it is powered from 5 V and drives `INT1` at 5 V into
a Pi GPIO, that pin is gone. Powering it from the Pi's 3V3 removes the
question rather than answering it.
