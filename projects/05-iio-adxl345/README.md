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

**Written, not yet built.** The driver, its recipe, the kernel fragment,
the image and the build configuration exist, and 43 assertions pass with no
board and no kernel tree.

**Nothing here has been compiled.** BitBake has never parsed these recipes,
no kernel has built these modules, and no board has run them. That is a
rung below Software complete on purpose: the machine this was written on
has no kernel source, so the C has been checked for the things text can be
checked for and not for whether it compiles.

One piece is deliberately missing: **the device tree overlay**. It needs an
I2C address and an interrupt GPIO that are properties of how this bench's
breakout is wired, and the board has not been read. See
[Deferred, with reasons](#deferred-with-reasons).

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
| 1 | The driver compiles as an out-of-tree module against the image's kernel | `./go adxl345` completing, and three `.ko` in the work directory | **Not started.** No kernel tree on the authoring machine, so this has never been attempted |
| 2 | The part is identified before it is configured: probe reads `DEVID` and refuses on anything but `0xe5` | `dmesg` on a board with the part, and on one without | Configured. `bench_adxl345_core_probe` reads `DEVID` first and returns `-ENODEV` on a mismatch |
| 3 | `in_accel_x_raw` and its siblings read, and `in_accel_scale` reports a value that turns one g into 9.81 m/s^2 | the four sysfs files, and a reading with the board flat | Configured, and the arithmetic is asserted: `tests/adxl345-driver-test.sh` recomputes the scale from 3.9 mg/LSB and 9.80665 and fails on drift |
| 4 | The output data rate can be set and read back through `sampling_frequency` | write 100, read 100, and the same for 3200 | Configured. Nine rates, written with `regmap_update_bits` so the low power bit survives |
| 5 | A triggered buffer fills from the part's own FIFO on a watermark interrupt, and `iio-decode` turns it into CSV without knowing what the part is | a capture with `iio-rate`, decoded by Project 10's tool | **Not started.** Needs the interrupt wired, which needs the board read |
| 6 | Single tap, double tap and free fall arrive as IIO events rather than as an invention of this driver | `iio_event_monitor` output while the board is tapped | Configured. Three `iio_push_event` calls on the standard gesture and threshold codes |
| 7 | Swapping the compatible string in the overlay moves the same hardware onto mainline's driver, and the two agree | two `iio-rate` runs, one per driver, on the same board | **Not started**, and it is the criterion this project exists to make possible |
| 8 | Every symbol in the fragment is real, and every one reaches the built `.config` | `./go ksym -f adxl345` before, `./go kconfig -f adxl345` after | **Not started.** The fragment names one promptless symbol and marks it as a consequence, which `./go ksym` is built to check |

Beyond those, two things this repository asserts that the theme does not
ask for:

| # | Criterion | State |
|---|---|---|
| 9 | The core never learns what a bus is | Asserted: the test fails if `bench-adxl345-core.c` includes `i2c.h` or `spi.h` |
| 10 | Every module the recipe builds is named in the image | Asserted, and the test fails if any of the five is dropped |

## What is tested without hardware

| Check | Command | Covers |
|---|---|---|
| The driver as text | `sh tests/adxl345-driver-test.sh` | 43 assertions: the compatible string in both bus files and never mainline's, the seam, the namespace import, every register defined exactly once, the scale against its own derivation, the watermark below the FIFO depth, all five modules reaching the image, and the promptless symbol carrying its consequence marker |
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
| The device tree overlay | It needs an I2C address and an interrupt GPIO, and both are properties of how this bench's DFRobot SEN0032 is wired rather than of the part. DFRobot publishes the chip's capability, `I2C / SPI (3 or 4 lines)` at `3.3~6V`, and no pin list. A node with a guessed interrupt does not fail safely: it drives whatever else is on that pin | Read the silkscreen. Three facts: whether SPI is exposed at all, which pin carries `INT1`, and what the supply does to the logic levels |
| Anything on the SPI bus | The driver is written for both because that is the subsystem's shape, but whether this breakout exposes SPI at all is unknown | The same look at the board |
| The activity and inactivity events | The part detects them and the driver does not yet route them. They need threshold and time registers exposed as IIO event attributes, which is a larger surface than tap and free fall | Worth doing once the interrupt path is proven by the simpler events |

**The supply is the one that can cost you something.** A breakout rated to
6 V regulates, and if it is powered from 5 V and drives `INT1` at 5 V into
a Pi GPIO, that pin is gone. Powering it from the Pi's 3V3 removes the
question rather than answering it.
