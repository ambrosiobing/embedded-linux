# Project 10: design

The drawings before the code. Five views, each answering a question the
others cannot, and one piece of arithmetic that decides what the headline
measurement is allowed to claim.

| View | Question |
|---|---|
| [Architecture](#architecture) | Which layer owns what, and who is allowed to open the buffer |
| [Schematic](#schematic) | What is wired, and what is deliberately not |
| [Bench layout](#bench-layout) | What it looks like on the table |
| [The three paths](#the-three-paths-out-of-a-sensor) | What is actually being compared |
| [Object model](#the-libiio-object-model) | Why the same program runs on the Pi and on the PC |

Project 5 writes an IIO driver. This project does the opposite: the drivers
are in the tree already, and the work is to use the subsystem properly.
Most code that touches IIO reads `in_accel_x_raw` in a loop, which is the
slowest of the three ways out of a sensor and the only one that carries no
timestamps.

## Architecture

```
  user space on the Pi
  +---------------------+  +---------------------+  +---------------------+
  | sysfs readers       |  | iio-stream, ahrs    |  | iiod                |
  |  cat *_raw, scale   |  |  libiio, local:     |  |  TCP 30431          |
  +----------+----------+  +----------+----------+  +----------+----------+
             |                        |                        |
             |                        |                        |  Ethernet
             |                        |                        v
             |                        |             +---------------------+
             |                        |             | PC client           |
             |                        |             |  iio_info -u ip:    |
             |                        |             |  same programs      |
             |                        |             +---------------------+
  - - - - - -|- - - - - - - - - - - - |- - - - - - - - - - - - - - - - - -
  kernel     |                        |
  +----------+------------------------+------------------------------+
  |                            IIO core                              |
  |        sysfs, /dev/iio:deviceN, kfifo buffer, triggers,          |
  |        scan elements, timestamps                                  |
  +---+-------------------+-------------------+----------------+-----+
      ^                   ^                   ^                ^
      |                   |                   |                |
  +---+--------+   +------+-----+   +---------+--+   +---------+-----+
  | hrtimer /  |   | st_lsm6dsx |   | st_magn    |   | st_pressure   |
  | sysfs trig |   | hw FIFO,   |   | LIS2MDL    |   | LPS22DF       |
  | (configfs) |   | watermark  |   |            |   |               |
  +------------+   +-----+------+   +-----+------+   +-------+-------+
                         ^                ^                  ^
                         |   INT1         |                  |
                         |   GPIO24       |                  |
                   +-----+----------------+------------------+-----+
                   |              i2c-bcm2835, I2C1, 400 kHz       |
                   +-----------------------+-----------------------+
                                           |
  hwmon, a different subsystem entirely    |
  +----------------+                       |
  | sht4x          |<----------------------+
  | /sys/class/hwmon                       |
  +----------------+                       |
  - - - - - - - - - - - - - - - - - - - - -|- - - - - - - - - - - - - - - -
  X-NUCLEO-IKS4A1 on I2C1                  |
  +---------------+ +----------+ +---------+-+ +--------+ +--------------+
  | LSM6DSV16X    | | LIS2MDL  | | LPS22DF   | | SHT40  | | STTS22H,     |
  | 0x6a, FIFO,   | | 0x1e     | | 0x5d      | | 0x44   | | LIS2DUXS12   |
  | INT1          | |          | |           | |        | | see inventory|
  +---------------+ +----------+ +-----------+ +--------+ +--------------+
```

Two things in that drawing are easy to miss and both cost time later.

**The SHT40 is not an IIO device.** It is driven by `sht4x`, which is a
hwmon driver, so it appears under `/sys/class/hwmon` and in `sensors`, and
never under `/sys/bus/iio/devices`. A program that enumerates IIO devices
and expects to find humidity will not find it, and nothing will report an
error. It is on the same I2C bus and in a different subsystem.

**The IMU is two IIO devices sharing one hardware FIFO.** `st_lsm6dsx`
registers `lsm6dsv16x_accel` and `lsm6dsv16x_gyro` separately, and they
share the chip's single FIFO and its single INT1 line. Enabling both at
different output data rates changes the FIFO's packet pattern and therefore
the driver's timestamp reconstruction. The bring-up order is one device
first, both afterwards, and the difference is recorded rather than averaged
away.

### Ownership

The table that prevents the commonest class of bug here, which is two
managers on one resource.

| Resource | Owner | Everyone else |
|---|---|---|
| I2C1 bus | `i2c-bcm2835` | no user-space `i2cget` while drivers are bound |
| Sensor registers | the four ST drivers | never touched directly |
| `/dev/iio:deviceN` buffer | **exactly one** reader at a time | a second `open()` gets `EBUSY` |
| Buffer enable, scan elements, watermark | whoever is about to read | must be left disabled afterwards |
| `current_trigger` of a device | the consumer setting up that capture | changing it under a live buffer is refused |
| hrtimer trigger objects | configfs, created by `iio-trigger` | removed by the same, not by hand |
| INT1 on GPIO24 | `st_lsm6dsx` through the overlay | no `gpioset`, no `libgpiod` |
| `iiod` | systemd, when enabled | see below |
| SHT40 | `sht4x` under hwmon | not an IIO device |

**The one that will actually bite: `iiod` and a local client cannot both
read the same device.** An IIO buffer has a single reader. If `iiod` is
running and the PC has a buffer open on `lsm6dsv16x_accel`, then
`iio-stream local:` on the Pi fails, and the reverse is equally true. This
is not a bug to be worked around; it is what a character device is. The
consequence for the measurements is that the local and network rate tables
are taken in separate runs, and the run protocol says so.

## Schematic

Five jumpers. The shield is 3.3 V only on this header.

```
   Raspberry Pi 3B+                              X-NUCLEO-IKS4A1
   40-pin header                                 Arduino header, 3.3 V logic
  +-------------------------+                   +--------------------------+
  |                         |                   |                          |
  | pin 1   3V3       o-----+---- red ----------+-o CN6-4  3V3             |
  |                         |                   |                          |
  | pin 3   GPIO2 SDA1 o----+---- blue ---------+-o CN5-9  D14 SDA         |
  |                         |          |        |          |               |
  | pin 5   GPIO3 SCL1 o----+-- yellow-+--------+-o CN5-10 D15 SCL         |
  |                         |     |    |        |          |               |
  | pin 18  GPIO24     o----+-- green -+--------+-o Dx     INT1 LSM6DSV16X |
  |                         |     |    |        |                          |
  | pin 6   GND        o----+-- black -+--------+-o CN6-6  GND             |
  |                         |                   |                          |
  | pin 8   GPIO14 TXD o----+--> USB/TTL        |  4k7 pull-ups to 3V3 are |
  | pin 10  GPIO15 RXD o----+--> USB/TTL        |  ON THE SHIELD, not here |
  | pin 6   GND        o----+--> USB/TTL        |                          |
  +-------------------------+                   +--------------------------+

  INT1 is push-pull at 3.3 V, rising edge. No pull-up needed on the Pi side.
```

**The pull-ups are on the shield.** Do not add any. Two sets of pull-ups on
one bus is a slower rise time, not a safer one, and at 400 kHz it shows up
as NACKs that read like driver bugs.

**Do not power the shield from pin 2 or pin 4.** Those are 5 V. The Arduino
header on this board is 3.3 V logic and the sensors are 3.3 V parts.

**Which Arduino pin carries INT1 is not known from the drawing.** It
depends on the shield's solder-bridge defaults, which the ST user manual
UM3239 tabulates. This design says GPIO24 on the Pi side because that is a
free pin; the shield side is settled with the manual and a multimeter
between the IMU's INT1 pad and the D pins, and the answer is written into
the bring-up notes as an observation rather than carried here as a guess.

## Bench layout

```
            microSD
              |
   +----------+------------------------------+
   |  o o o o o o o o o o o o o o o o o o o  |   40-pin header
   |  o o o o o o o o o o o o o o o o o o o  |
   |                                         |
   |        Raspberry Pi 3B+                 +--[ETH]---> Ethernet to PC
   |                                         |            iiod, TCP 30431
   |                                         +--[USB]
   +-------+---------------------------------+
           |
      micro-USB 5 V

           five short jumpers, all from the header
           3V3, GND, SDA, SCL, INT1
                  |
                  v
   +------------------------------------------+
   | CN5: SDA, SCL, INT1                      |
   | CN6: 3V3, GND                            |
   |                                          |
   |   [LSM6DSV16X]  [LIS2MDL]                |
   |   [LPS22DF]     [SHT40]                  |
   |                                          |
   |        X-NUCLEO-IKS4A1                   |
   +------------------------------------------+
```

**Keep the jumpers short.** 400 kHz over 20 cm of loose wire is the limit,
and the failure is intermittent rather than clean.

**The magnetometer is the reason the layout is part of the experiment.**
It sits centimetres from the Pi's Ethernet jack, its magnetics, and a
USB/TTL cable. Hard-iron calibration is valid for one physical arrangement,
so moving the shield invalidates it, and the results table records the
layout with the numbers.

## The three paths out of a sensor

This is the measurement the project exists to make, and it needs stating
precisely before any of it is run, because two of the three paths do not
produce the same kind of timestamp.

| Path | Who decides when a sample is taken | Timestamp comes from |
|---|---|---|
| sysfs polling | the reading process, whenever it gets scheduled | nowhere; there is none |
| hrtimer trigger | the kernel, at a fixed rate | the IIO core, at the moment the scan is pushed |
| hardware FIFO | the sensor's own oscillator | **the driver, reconstructed** |

### The claim this project is allowed to make, and the one it is not

The tempting headline is "the FIFO path has better timestamp regularity
than the hrtimer path". That comparison is not sound, and it is worth
writing down why before any data exists to be over-read.

In the hrtimer path, the timestamp is taken when the IIO core pushes the
scan, so its jitter is a real measurement of kernel latency: hrtimer
wake-up, plus the I2C transaction, plus whatever delayed either.

In the FIFO path, the sensor timestamps nothing. The driver receives one
interrupt at the watermark, drains N samples in a burst, and then
**assigns** timestamps by interpolating backwards from the interrupt time
using the configured output data rate. So the intervals between FIFO
timestamps are close to exactly `1 / ODR` by construction. Measuring their
standard deviation measures the driver's arithmetic and the stability of
the sensor's oscillator, and tells you nothing about kernel latency.

Put the two side by side and the FIFO path "wins" by a wide margin, for the
same reason a clock that reports the time it was set to always agrees with
itself.

So the sound comparisons are:

- **interrupt rate and CPU load**, across all three paths. These are real,
  directly measurable, and they are the reason the FIFO exists: at 416 Hz
  with a watermark of 64 the driver is woken about 6.5 times a second
  instead of 416.
- **timestamp regularity within the hrtimer path**, against the rate it was
  asked for. This measures the kernel.
- **sample count over a fixed interval**, across all three paths, against
  the configured rate. This catches dropped samples, which is what actually
  goes wrong at high rates, and it is comparable across paths because a
  sample either arrived or did not.

The FIFO timestamp spread is still worth recording, clearly labelled as a
property of the reconstruction rather than of the system. An unlabelled
number in that column would be the most quotable and least meaningful
figure in the project.

This is the same trap as Project 8's, which stated in five documents that
the difference between its two instruments was the cost of a GPIO write,
until the algebra showed a constant cost cancels. The shape repeats: a
quantity that looks like a measurement of the system, which is really a
measurement of how the number was produced.

### Data flow

```
  sensors (I2C1 @ 400 kHz)        kernel                        consumers

  LSM6DSV16X 0x6a ----+--> st_lsm6dsx: hw FIFO ----+
    FIFO, INT1 -------+      watermark IRQ on      |
                      |      GPIO24, threaded,     +--> sysfs: *_raw, scale
                      |      drains N in a burst   |     (no timestamps)
                      |                            |
  LIS2MDL    0x1e ----+--> st_magn ----------------+--> /dev/iio:deviceN
  LPS22DF    0x5d ----+--> st_pressure ------------+     libiio local:
                      |      both polled, or       |     iio-stream, ahrs
                      |      driven by a trigger   |
                      |                            |
  SHT40      0x44 ----+--> sht4x (hwmon) ----------+--> /sys/class/hwmon
                                                   |     sensors(1)
   hrtimer trigger (configfs) --------------------+
   sysfs trigger  (configfs) ---------------------+
                                                   |
                                                   +--> iiod, TCP 30431
                                                         PC: same programs,
                                                         different URI
```

## The libiio object model

Four objects, and the reason the fusion program runs unchanged on the Pi
and on the PC.

```
  +---------------------------+        +----------------------------+
  | iio_context               | 1..*   | iio_device                 |
  |---------------------------|<>------|----------------------------|
  | uri: "local:" | "ip:host" |        | id, name                   |
  | description, version      |        |   lsm6dsv16x_accel         |
  |---------------------------|        | sample_size                |
  | create_context_from_uri() |        |----------------------------|
  | find_device(name)         |        | find_channel(id, output)   |
  | get_devices_count()       |        | attr_read / attr_write     |
  +---------------------------+        | create_buffer(n, cyclic)   |
                                       +------+---------------+-----+
                                              | 1..*          |
                                              v               v
  +---------------------------+   +---------------------------+
  | iio_channel               |   | iio_buffer                |
  |---------------------------|   |---------------------------|
  | id: accel_x, timestamp    |   | samples_count, step       |
  | data_format               |   | kfifo on the Pi,          |
  |   le:s16/16, le:s64/64    |   | socket on the PC          |
  | attrs: raw, scale, offset |   |---------------------------|
  |---------------------------|   | refill()                  |
  | enable() / disable()      |   | first(channel) / end()    |
  | attr_read_double("scale") |   | destroy()                 |
  | convert(dst, src)         |   +------------+--------------+
  +-------------+-------------+                ^
                ^                              | current_trigger
                |                   +----------+----------------+
                |                   | iio_device as trigger     |
                |                   |   t100, iio_sysfs_trigger |
                |                   |   attr sampling_frequency |
                |                   +---------------------------+
                |
       implements|
  +-------------+-------------------------------------------+
  | backend                                                 |
  |   local:   sysfs + /dev/iio:deviceN                     |
  |   network: iiod, TCP 30431                              |
  |   the API above this line is identical                  |
  +---------------------------------------------------------+
```

**The URI is the only difference between local and remote.** That is the
design claim, and the acceptance table tests it directly: the same program
must produce identical CSV columns from `local:` on the Pi and from `ip:`
on the PC, with sample counts agreeing within one percent.

### The offsets that must not be hard-coded

The specification's example C client walks the buffer with literal offsets
of 2, 4 and 8 bytes. Those are correct for three 16-bit channels followed
by a 64-bit timestamp aligned to 8 bytes, and they are wrong the moment a
channel is disabled, a different sensor is read, or a driver reports a
different storage size.

This project computes them from `iio_channel_get_data_format` instead. The
cost is a dozen lines; the benefit is a client that does not silently
misparse when the scan changes, which is a failure that produces plausible
numbers rather than an error.

## What gets built

| Piece | Where | Why there |
|---|---|---|
| kernel fragment `iio.cfg` | `meta-bench/recipes-kernel/linux/files/` | Yocto requires it in the layer |
| device tree overlay | `meta-bench/recipes-bench/bench-iks4a1/` | built with `dtc` at do_compile, deployed to the boot partition |
| `iio-probe`, `iio-trigger`, `iio-rate` | `meta-bench/recipes-bench/bench-iio/files/` | shell, policy, testable with stubs |
| `iio-stream.c` | same | the libiio C client |
| `ahrs.py`, `calib-mag.py` | same | fusion, numpy |
| `bench-iio-image.bb` | `meta-bench/recipes-core/images/` | one image per project variant |
| `kas/bench-iio.yml` | `kas/` | a project that needs a different kernel adds its own kas file |
| narrative, wiring, evidence | `projects/10-iio-iks4a1/` | so the project reads as a unit |

## The sensor inventory is a deliverable, not a footnote

The shield carries six sensor parts and the kernel does not support all of
them. The specification is explicit that the honest inventory is part of
what this project delivers, and the acceptance table has a row for it.

The rule for filling that table: **`./go ksym` against the kernel tree
before the build, not `modinfo` afterwards and not a web page.** A driver
that exists upstream is not a driver that exists in 6.12.93, and a symbol
that exists is not a driver that binds to this part number. Each row gets
the command that produced it.

Expected addresses, to be confirmed with `i2cdetect -y 1` rather than
assumed: `0x6a` LSM6DSV16X, `0x1e` LIS2MDL, `0x5d` LPS22DF, `0x44` SHT40,
with the STTS22H and LIS2DUXS12 also answering. Answering the bus and
having a driver are different facts and the table keeps them in different
columns.
