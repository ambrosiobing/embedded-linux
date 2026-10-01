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

**It has been run.** An X-NUCLEO-IKS4A1 was wired to a Raspberry Pi 3B+ on
Wednesday 30 September 2026 and measured through Thursday 1 October 2026.
[docs/TIMELINE.md](docs/TIMELINE.md) is those two days in order and
[docs/RESUME.md](docs/RESUME.md) is the state the next session starts from.

To repeat it you need the shield, eight jumper wires, a Raspberry Pi 3B+ and
a USB to TTL cable for the console. The wiring is in
[docs/BRINGUP.md](docs/BRINGUP.md), confirmed three independent ways.

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

[docs/TIMELINE.md](docs/TIMELINE.md) is Wednesday 30 September 2026 minute
by minute, the day this project met hardware: every finding, correction and
withdrawn conclusion in the order it happened, timed by commit rather than
by memory. The [journal](JOURNAL.md) holds the reasoning; the timeline
holds the sequence, and what the day cost at each stage.

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
| 1 | `i2cdetect -y 1` shows the four addresses, and each IIO device reports the expected `name`; the SHT40 appears in `sensors` | `iio-probe -v` | **met**, Thursday 1 October 2026. Every address answers, four IIO devices report the expected names, `lsm6dsv16x_gyro`, `lsm6dsv16x_accel`, `lis2mdl` and `lps22df`, and the SHT40AD1B appears through hwmon. `st_lsm6dsx`, `st_sensors`, `st_magn` and `st_pressure` were all built out of tree against `linux-source-6.18` ([driver-build-2026-10-01.txt](docs/evidence/driver-build-2026-10-01.txt), [inventory-complete-2026-10-01.txt](docs/evidence/inventory-complete-2026-10-01.txt)). Closed further that evening: `0x6a` bound too, so there are **six** IIO devices and five `UU` where the morning had one. It was never a driver gap, `st_lsm6dsx` has carried `st,lsm6dso16is` all along; nothing had ever declared a device at that address ([inventory-all-bound-2026-10-01.txt](docs/evidence/inventory-all-bound-2026-10-01.txt)) |
| 2 | The inventory lists every sensor on the shield with its driver and status | `iio-probe -v`, [inventory-2026-10-01.txt](docs/evidence/inventory-2026-10-01.txt) | **met**, Thursday 1 October 2026, and three times over. In the morning it reported seven verdicts with four `no-driver-in-image`; in the afternoon, unedited, four `working` and none missing; in the evening, still unedited, five `working` and no `not-bound` at all ([inventory-complete-2026-10-01.txt](docs/evidence/inventory-complete-2026-10-01.txt)). The inventory changed because the image did, which is the property the criterion is about. The `-m` CSV is still to be captured |
| 3 | The hrtimer-triggered magnetometer buffer delivers timestamps with a standard deviation below 100 us at 100 Hz over 5 s | `iio-rate trigger lis2mdl 100`, [trigger-lis2mdl-2026-10-01.txt](docs/evidence/trigger-lis2mdl-2026-10-01.txt) | **met**, Thursday 1 October 2026. **3.341 us** over 10 s, thirty times inside the limit, 1003 samples where 1000 were asked for, 0.40 percent reader CPU. Source `iio-core`, so unlike the FIFO figure this one is a latency measurement. Zero interrupts: a software trigger never touches the line whose ringing makes criterion 4 unmeasurable |
| 4 | The IMU FIFO at 416 Hz with watermark 64 produces fewer than 8 interrupts per second and under 3 percent reader CPU, against more than 400 per second at watermark 1 | `iio-rate fifo`, [irq-storm-2026-10-01.txt](docs/evidence/irq-storm-2026-10-01.txt) | **half met**, Thursday 1 October 2026. 416 Hz does not exist on this part; 480 and 120 were used. **Reader CPU passes**: 0.80 percent at 480 Hz and 0.20 at 120, scaling exactly with sample rate, and batching halves it at identical throughput (0.40 to 0.20 percent). **The interrupt half fails, and now against a control.** 225.60 interrupts per second at 480 Hz with watermark 64, where 7.5 are expected, so 30 times too many. Unplugging the same wire at CN9 pin 6 gives **0.00 per second and 0 samples**, the counter not advancing one count, so the edges arrive down the wire and GPIO24 picks up nothing on its own. The FIFO path is entirely interrupt driven, which is why the sample count has never been able to tell a healthy line from a noisy one. Needs the wire shortened or a few hundred ohms in series at CN9 pin 6, not more runs ([irq-control-2026-10-01.txt](docs/evidence/irq-control-2026-10-01.txt), [irq-storm-2026-10-01.txt](docs/evidence/irq-storm-2026-10-01.txt)) |
| 5 | `iio-stream` produces identical CSV columns with `local:` and with `ip:`, and the sample counts over 10 s agree within 1 percent | `diff` of the two | **met**, Thursday 1 October 2026. Identical columns `magn_x,magn_y,magn_z,timestamp`, and 1000 samples each in 10.044 s and 10.074 s, so the counts are equal rather than within one percent. libiio 0.26 on both hosts, `iiod` on TCP 30431, the only differing argument `-u ip:192.168.92.154`. Measured on `lis2mdl` with a 100 Hz software trigger and **not** on the accelerometer, whose buffered path timed out. **The reason first recorded for that was wrong and is withdrawn in journal 47.** The timeout was not the interrupt: `iio-stream` does not set the sampling frequency, and the LSM6DSV16X powers up in power-down, so the buffer never filled. With `sampling_frequency` at 480 the identical command returned 1001 lines in 2.198 s. The substitution to `lis2mdl` was forced by that unstated precondition, not by the bench ([iio-stream-local-vs-ip-2026-10-01.txt](docs/evidence/iio-stream-local-vs-ip-2026-10-01.txt)) |
| 6 | The scan layout is computed from the kernel's declaration rather than hard-coded | `tests/iio-decode-test.sh`, 22 assertions | **met**, 16 Sep 2026: alignment, disabled channels, 12 bits in 16 with a shift, big endian, unsigned, and a timestamp that is never scaled |
| 7 | The inventory distinguishes a missing driver from an unbound one | `tests/iio-probe-test.sh`, 25 assertions, and on hardware Thursday 1 October 2026 | **met**, 16 Sep 2026: five verdicts, each asserted |
| 8 | The AHRS reads pitch and roll within 2 degrees of zero when flat, and within 3 degrees after a 90 degree rotation about each axis | `ahrs --selftest` on the board, then the shield by hand | **criterion defective**, Thursday 1 October 2026. Level passes: roll +0.770, pitch +0.302 degrees. The 90 degree halves cannot be met as written, for two reasons that are not the filter's. They measure the FIXTURE: a board propped on a free edge sits 2 to 12 degrees off the axis, and reporting that is the filter being right. And at a pitch near 90 degrees roll is ill-conditioned, so a tolerance on roll there is a tolerance on a number the geometry does not fix. What is measured: the filter's orientation agrees with trigonometry on the same samples to **under 2 degrees at every pose**, both rotations included ([ahrs-gravity-2026-10-01.txt](docs/evidence/ahrs-gravity-2026-10-01.txt)). A restatement is proposed there |
| 9 | The user-space polling baseline is measured, with a quiet noise floor and a vibration case above it | `i2ctransfer` loop, both captures in `docs/evidence` | **met**, Wednesday 30 September 2026. Floor 0.36 mg on X and Y and 0.47 mg on Z; a shaver against the board raises Z to 10.66 mg rms, a factor of 23. Magnitude 1.0068 g against a true 1.0000 g, so sensitivity is 0.68 percent high |

Criteria 6 and 7 are met on a laptop because they are properties of the
programs rather than of the board. That distinction is narrower than it
reads: three defects in `iio-rate` and one in `iio-probe` were also
properties of the programs, sat in the same files, and were invisible to
every assertion made against a synthetic sysfs tree. Journal entry 37 has
the detail.

Criteria 2 and 9 are met **on the shield**, and criterion 8's level half
is too. What is left needing hardware is 3 and 5, and the half of 4 the
interrupt wiring prevents. The rows say which rather than being left blank
in a way that reads like a gap.

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

**The live reader is not written.** `ahrs` is importable, has a selftest,
and since Thursday 1 October 2026 reads a recorded capture through
`--capture`, which is how its filter first met real gravity. Reading three
devices live through libiio at 104 Hz still needs two drivers that are not
built yet: `st_magn` for the magnetometer and `st_pressure` for the
barometer. The IMU has one, built out of tree, and
[docs/RESUME.md](docs/RESUME.md) carries the procedure for the other
two.

**`iiod` is installed and not enabled.** It exposes every device with no
authentication. Starting it is a decision taken on a bench with a known
network, which is what `docs/BRINGUP.md` says and why the image does not
make it for you.

**libiio 1.0 is not supported.** It replaced buffers with blocks and
`iio_buffer_refill` no longer exists, so `iio-stream.c` is 0.x code against
whatever meta-oe pins for this release. A build against 1.0 fails at
compile time, which is the right place for it to fail.
