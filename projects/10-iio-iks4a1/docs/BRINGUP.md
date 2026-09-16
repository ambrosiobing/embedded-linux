# Bring-up: from a flashed card to an orientation

In order. Each step ends with something that either works or says why not,
because the alternative is arriving at the fusion filter with a fault
introduced at the wiring.

Nothing below has been performed. It is the plan, written while the code
was written, and it will be corrected in the [journal](../JOURNAL.md) as
soon as it meets hardware.

## 0. Before the power goes on

Power off, shield off.

| Check | Why |
|---|---|
| The shield is fed from **pin 1 (3V3)**, never pin 2 or 4 | Those are 5 V. The Arduino header on this board is 3.3 V logic and the sensors are 3.3 V parts |
| No pull-ups added on the Pi side | The 4k7 pull-ups are on the shield. Two sets on one bus is a slower rise time, not a safer one, and at 400 kHz it looks like NACKs from a driver bug |
| Jumpers are short | 400 kHz over 20 cm of loose wire is the documented limit, and the failure is intermittent rather than clean |
| The magnetometer is where it will stay | Hard-iron calibration is valid for one physical arrangement. Moving the shield afterwards invalidates it |
| The USB/TTL cable is on pins 8, 10 and 6, red lead not connected | The console is how a board that does not boot gets diagnosed |

**Which Arduino pin carries INT1 is not settled by this repository.** It
depends on the shield's solder-bridge defaults. ST's user manual UM3239 has
the table; a multimeter between the IMU's INT1 pad and the D pins settles
it. Write what you measured into the journal as an observation, not as a
guess, and only then wire it to GPIO24.

## 1. The bus before the drivers

Flash, boot, and ask what is there before asking whether anything works.

```sh
i2cdetect -y 1
```

Expect `6a`, `1e`, `5d`, `44`, and the STTS22H and LIS2DUXS12 answering
too. Anything missing here is wiring or bus speed, and no amount of driver
work will fix it.

If the grid is empty or ragged, drop the bus to 100 kHz before suspecting
anything else: edit `dtparam=i2c_arm_baudrate=100000` in `config.txt` and
reboot. A bus that works at 100 and not at 400 is a wire length problem
and the answer is shorter jumpers, not a different driver.

**`UU` is not an error.** It means a driver has claimed that address and
`i2cdetect` will not probe it. Once the overlay is applied, that is the
expected state for the four supported parts, and `iio-probe` reports it as
`claimed` rather than leaving you to remember.

## 2. The inventory, before anything else is believed

```sh
iio-probe
iio-probe -v
```

This is the step that decides what the rest of the bring-up can even
attempt, and it distinguishes five outcomes that all look identical from a
bare `ls /sys/bus/iio/devices`:

| Verdict | Where to look |
|---|---|
| `working` | nowhere, it bound and registered devices |
| `not-bound` | the overlay: the driver is installed and nothing matched it |
| `no-driver-in-image` | `bench-iio-image.bb`: configured in the kernel is not installed in the rootfs |
| `bound-no-device` | `dmesg`: the driver matched and its probe failed |
| `not-on-bus` | step 1, the wiring |

Save it as evidence while it is true:

```sh
iio-probe -m > /tmp/inventory.csv
iio-probe -v > /tmp/inventory.txt
```

Those two files are what fills the inventory table in the
[README](../README.md), and they are worth keeping even when a row is
disappointing. A part with no driver is a finding.

## 3. The slow path, and what it does not give you

```sh
D=$(ls -d /sys/bus/iio/devices/iio:device* | head -1)
cat $D/name
cat $D/in_accel_x_raw $D/in_accel_x_scale
cat $D/sampling_frequency_available
iio-rate poll lsm6dsv16x_accel
```

Every read is an open, a read, a close and an I2C transaction started from
user space. The number that comes back is what a program gets for doing the
obvious thing, and it is the baseline the other two paths are measured
against.

**There are no timestamps on this path.** Not inaccurate ones: none. That is
the first argument for the buffered paths and it is worth seeing rather
than being told.

## 4. Software triggers

```sh
mount -t configfs none /sys/kernel/config
iio-trigger add hrtimer t100 100
iio-trigger list
iio-rate trigger lis2mdl 100
```

The magnetometer, deliberately: it has no FIFO of its own, so there is no
hardware path to confuse the comparison with.

**If `/sys/kernel/config` is empty, configfs is not mounted.** The directory
exists in any image built with `CONFIG_CONFIGFS_FS` and says nothing about
whether anything was mounted on it. A `mkdir` there will succeed, create an
ordinary directory, and produce a trigger that does not exist as far as the
kernel is concerned. `iio-trigger` checks `/proc/mounts` and refuses rather
than letting that happen.

This is the path whose timestamp regularity **is** a measurement: the IIO
core stamps each scan as it pushes it, so the spread is kernel latency.
Acceptance criterion 3 is a standard deviation below 100 us at 100 Hz.

## 5. The fast path, and the number not to quote

```sh
iio-rate fifo lsm6dsv16x_accel 416 1
iio-rate fifo lsm6dsv16x_accel 416 64
cat /proc/interrupts | grep -i lsm6
```

Twice, because the comparison is between watermarks and not against the
other paths. At 416 Hz a watermark of 1 is an interrupt per sample and a
watermark of 64 is one per 64: about 6.5 a second against more than 400,
for the same data.

**The timestamps on this path are reconstructed.** The sensor stamps
nothing. The driver takes one interrupt at the watermark, drains the FIFO
in a burst, and assigns timestamps by interpolating backwards using the
configured rate. Their spread measures the driver's arithmetic and the
sensor's oscillator.

`iio-rate` prints a warning under that number every time it produces it.
Do not put it in the same column as the hrtimer figure.

**Start with one device.** The accelerometer and the gyroscope share the
chip's single FIFO, so enabling both at different rates changes the packet
pattern and the reconstruction with it. Measure one, then both, and record
the difference rather than averaging it away.

## 6. The network path

```sh
systemctl start iiod
ss -ltnp | grep 30431
```

Then from the PC, with the same programs:

```sh
iio_info -u ip:raspberrypi3-64.local | head -40
iio-stream -u ip:raspberrypi3-64.local -n 4 > /tmp/remote.csv
```

and on the board:

```sh
iio-stream -n 4 > /tmp/local.csv
```

Criterion 5 is that those two have identical columns and sample counts
within one percent. That is the whole claim of the libiio object model:
the URI is the only difference.

**`iiod` is started by hand and not enabled at boot.** It exposes every
device with no authentication whatsoever. On a bench LAN that is a
convenience; on anything else it is a sensor feed anybody can read.

**One reader at a time.** An IIO buffer has a single reader. While a PC
client has a buffer open on the accelerometer, `iio-stream local:` on the
board will fail to create one, and the reverse is equally true. That is
what a character device is, not a bug to be worked around, and it is why
the local and remote rate measurements are taken in separate runs.

## 7. Fusion, once the data path is trusted

Not before. A filter fed by a path that drops samples or mislabels
timestamps produces a plausible orientation that is wrong in a way no plot
will show.

Calibrate the magnetometer first, in the position it will stay in, and
record the layout with the numbers.

## 8. What gets written down

The inventory from step 2, the three rows from steps 3 to 5 with their
interrupt counts and CPU figures, the two CSV files from step 6, and the
orientation results. Each with the command that produced it.

And the INT1 pin you actually measured in step 0, because the next person
to build this will have a shield with different solder bridges.

---

Back to the [project README](../README.md), or the
[design](DESIGN.md).
