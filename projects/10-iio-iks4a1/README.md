# Project 10: IIO in depth with the X-NUCLEO-IKS4A1

**Board:** Raspberry Pi 3B+. **Theme:** IIO buffers and triggers, hardware
FIFO, libiio, `iiod` over the network, sensor fusion in user space.

Project 5 writes an IIO driver. This one does the opposite: the drivers are
in the tree already and the work is to use the subsystem properly. There
are three ways to get data out of a sensor and most code only ever uses the
slowest, reading `in_accel_x_raw` in a loop, which is also the only one that
carries no timestamps at all.

The comparison is measured rather than asserted, and one part of it is
**deliberately not made**. The IMU's hardware FIFO produces timestamps that
the driver reconstructs by interpolating backwards from one interrupt, so
their regularity is a property of the driver's arithmetic rather than of
the system. Put beside the hrtimer path it wins by a wide margin, for the
same reason a clock that reports the time it was set to always agrees with
itself. [docs/DESIGN.md](docs/DESIGN.md) sets out which three comparisons
are sound and why that one is not.

## What a clone gives you

**No image is published.** This directory carries the recipes, the overlay,
the programs, the tests and the evidence, and `.gitignore` excludes `*.wic*`
on purpose.

**If the software is what interests you, no sensors are required.** Four
suites run on any machine in seconds, 85 assertions between them: the
inventory against a fake I2C bus with a stubbed `i2cdetect` and a directory
tree shaped like sysfs; the scan decoder against synthetic buffers
including the cases that break a remembered layout; the trigger tools
against a fake configfs, including the branch where it is not mounted; and
the orientation filter against rotations whose answers come from geometry.
`iio-probe`, `iio-decode`, `iio-stream.c` and `ahrs.py` all read on their
own, and `docs/DESIGN.md` is the architecture.

**If you want to run it, you need the shield.** An X-NUCLEO-IKS4A1, five
jumper wires and a Raspberry Pi 3B+.

## What this project adds to the repository

| Piece | What it is |
|---|---|
| `meta-bench/recipes-kernel/linux/files/iio.cfg` | four sensor drivers, the hrtimer trigger, configfs, the I2C controller |
| `meta-bench/recipes-bench/bench-iks4a1/` | the device tree overlay, compiled with `dtc -@` and deployed to the boot partition |
| `meta-bench/recipes-bench/bench-iio/` | `iio-probe`, `iio-trigger`, `iio-rate`, `iio-decode`, `iio-stream` |
| `meta-bench/recipes-core/images/bench-iio-image.bb` | the image, and the nine `kernel-module-*` lines that put the drivers in the rootfs |
| `kas/bench-iio.yml` | Pi 3B+, I2C at 400 kHz, the overlay, and no DSI panel |
| four suites under `tests/` | 85 assertions, no hardware |

## Running it

```sh
./go check                   # the suites, no board and no shield
./go ksym -f iio             # after the kernel unpacks, before it compiles
./go iio                     # bench-iio-image
./go flash /dev/sdX
```

On the board, in this order:

```sh
iio-probe                    # the inventory, before anything else
iio-trigger list
iio-rate poll    lis2mdl
iio-rate trigger lis2mdl 100
iio-rate fifo    lsm6dsv16x_accel 416 64
```

[docs/DESIGN.md](docs/DESIGN.md) is the methodology: architecture, the
ownership table, the schematic, the bench layout, the three paths and the
libiio object model. Read it first.

[docs/BRINGUP.md](docs/BRINGUP.md) is the board work in order, from the
first `i2cdetect` to the orientation test.

## The sensor inventory

The specification asks for an honest list of which sensors of the shield
work with which driver, and that list is a deliverable rather than a
footnote. `iio-probe -m` generates it, so the table below is produced
rather than remembered.

**Nothing has been run on hardware yet, so the status column is empty.**
The expected addresses are from the specification and are confirmed with
`i2cdetect -y 1` rather than assumed.

| Address | Part | Driver | Subsystem | Status |
|---|---|---|---|---|
| `0x6a` | LSM6DSV16X | `st_lsm6dsx` | IIO | |
| `0x1e` | LIS2MDL | `st_magn` | IIO | |
| `0x5d` | LPS22DF | `st_pressure` | IIO | |
| `0x44` | SHT40 | `sht4x` | **hwmon** | |
| `0x3c` | STTS22H | none | | expected unsupported, no mainline driver |
| `0x19` | LIS2DUXS12 | none | | driver may be absent from 6.12.93 |

Two of those rows matter more than they look.

**The SHT40 is not an IIO device.** `sht4x` is a hwmon driver, so it appears
under `/sys/class/hwmon` and in `sensors(1)` and never under
`/sys/bus/iio/devices`. A program that enumerates IIO devices looking for
humidity finds nothing and reports no error.

**The LSM6DSV16X is two IIO devices.** `st_lsm6dsx` registers
`lsm6dsv16x_accel` and `lsm6dsv16x_gyro` separately and they share one
hardware FIFO and one interrupt line. Enabling both at different output
data rates changes the FIFO packet pattern and with it the driver's
timestamp reconstruction, so the bring-up order is one device first.

`iio-probe` reports five different verdicts, because the ways this can fail
have different fixes: `working`, `not-bound` (look at the overlay),
`no-driver-in-image` (look at the image), `bound-no-device` (look in
`dmesg`) and `not-on-bus` (look at the wiring).

## The three paths

The measurement this project exists to make. **No numbers yet.**

| Path | Rate | IRQ/s | Reader CPU | Timestamp SD | Source of timestamps |
|---|---|---|---|---|---|
| sysfs polling | | | | none | there are none |
| hrtimer trigger, 100 Hz | | | | | IIO core, at capture |
| hardware FIFO, 416 Hz, watermark 1 | | | | | driver, interpolated |
| hardware FIFO, 416 Hz, watermark 64 | | | | | driver, interpolated |

The last column is not decoration. Two of those rows contain a number that
is not a latency measurement, and `iio-rate` prints a warning beside it
every time rather than leaving the reader to remember.

## Acceptance criteria

| # | Criterion | Evidence | State |
|---|---|---|---|
| 1 | `i2cdetect -y 1` shows the four addresses, and each IIO device reports the expected `name`; the SHT40 appears in `sensors` | `iio-probe -v` | **not started**, needs the shield |
| 2 | The inventory lists every sensor on the shield with its driver and status | `iio-probe -m` | **not started**, needs the shield |
| 3 | The hrtimer-triggered magnetometer buffer delivers timestamps with a standard deviation below 100 us at 100 Hz over 5 s | `iio-rate trigger lis2mdl 100` | **not started** |
| 4 | The IMU FIFO at 416 Hz with watermark 64 produces fewer than 8 interrupts per second and under 3 percent reader CPU, against more than 400 per second at watermark 1 | `iio-rate fifo` twice | **not started** |
| 5 | `iio-stream` produces identical CSV columns with `local:` and with `ip:`, and the sample counts over 10 s agree within 1 percent | `diff` of the two | **not started**, needs the network |
| 6 | The scan layout is computed from the kernel's declaration rather than hard-coded | `tests/iio-decode-test.sh`, 22 assertions | **met**, 16 Sep 2026: alignment, disabled channels, 12 bits in 16 with a shift, big endian, unsigned, and a timestamp that is never scaled |
| 7 | The inventory distinguishes a missing driver from an unbound one | `tests/iio-probe-test.sh`, 25 assertions | **met**, 16 Sep 2026: five verdicts, each asserted |
| 8 | The AHRS reads pitch and roll within 2 degrees of zero when flat, and within 3 degrees after a 90 degree rotation about each axis | `ahrs --selftest` on the board, then the shield by hand | **partly met**, 16 Sep 2026: the filter is checked against known rotations in `tests/ahrs-test.sh`, level and both signs of 90 degrees, within 0.06 degrees. Nothing has been checked against real gravity |

Criteria 6 and 7 are met on a laptop because they are properties of the
programs rather than of the board. Everything else needs the shield, and
the rows say so rather than being left blank in a way that reads like a
gap.

## What is tested without hardware

| Suite | Assertions | What it pins |
|---|---|---|
| `tests/iio-probe-test.sh` | 25 | every part gets a row even when its driver is `none`; the five verdicts; hwmon is not IIO; `UU` in `i2cdetect` means claimed rather than broken |
| `tests/iio-decode-test.sh` | 22 | a 64-bit timestamp is aligned to 8 and not packed at 6; disabling a channel moves the ones after it; 12 bits inside 16 sign extend from bit 11; a timestamp is never scaled |
| `tests/iio-trigger-test.sh` | 28 | an unmounted configfs is refused rather than silently producing a trigger the kernel never heard of; a failed create removes its own object; a hrtimer trigger cannot be fired by hand |
| `tests/ahrs-test.sh` | 10 | the filter against rotations whose answer comes from geometry, both signs, with the gyroscope and the accelerometer as independent paths to the same angle |

Both suites were checked by reintroducing the defect they were written for
and watching them fail, which is the only way to tell a rule that works
from a rule that has never been exercised.

## Deferred, with reasons

**The AHRS is written and is not Madgwick's MARG filter.** The
accelerometer and gyroscope half is his gradient-descent update. Yaw comes
from a tilt-compensated magnetic heading rather than from folding the
magnetometer into the same six-row Jacobian, because that Jacobian is
exactly where published implementations differ in sign and in frame
handedness, and a wrong sign there gives an orientation that is mirrored
rather than obviously broken. The substitution is stated in the file's own
header and the cost is a noisier yaw.

**The live reader is not written.** `ahrs` is importable and has a
selftest; reading three devices through libiio at 104 Hz and printing yaw,
pitch and roll needs the shield to be worth writing against.

**`iiod` is installed and not enabled.** It exposes every device with no
authentication. Starting it is a decision taken on a bench with a known
network, which is what `docs/BRINGUP.md` says and why the image does not
make it for you.

**libiio 1.0 is not supported.** It replaced buffers with blocks and
`iio_buffer_refill` no longer exists, so `iio-stream.c` is 0.x code against
whatever meta-oe pins for this release. A build against 1.0 fails at
compile time, which is the right place for it to fail.
