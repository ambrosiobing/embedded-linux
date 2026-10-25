# Portfolio evidence

What goes here, and how each item is produced. Empty until the board has
actually run; nothing in this folder should be written from expectation.

**That opening sentence said the folder was empty and every row a plan,
and it said so while this directory held thirty files from three dated
sessions.** Corrected on Saturday 24 October 2026. Project 5's evidence
README needed exactly the same correction, which makes it a pattern
rather than an oversight: nothing in this repository reads a sentence,
so a claim about a directory goes stale the first time somebody adds a
file to it.

The rows below are still the plan for what is missing. The
[project README](../../README.md) marks criteria 6 and 7 met on a laptop,
because they are properties of the programs rather than of the board, and
those two are the only ones that do not need this folder.

## Taken on the bench

| File | What it settles |
|---|---|
| `accel-gravity-2026-10-25.md` | **The first measurement in this project that asks whether a number is correct**, rather than counting samples. The LSM6DSV16X against gravity, flat and inverted, both poses resting and square. Gain error -0.30 per cent and zero-g offset +9.5 mg, both inside the part's specification, with the driver applying the nominal 2g/32768 scale and no calibration. The point of the matched pair: one pose alone read 0.66 per cent HIGH and that was a positive offset masking a negative gain error, which the two poses separate and then reconstruct exactly. X and Y gain, cross-axis sensitivity and the gyroscope are all still untested | Sunday 25 October 2026 |
| `rates-2026-10-24.csv` and `.md` | **Criteria 3 and 4 RE-TAKEN under Yocto with mainline drivers**, both having been met on eplepi on Thursday 1 October 2026. Criterion 3 passes again at 7.088 us. **Criterion 4 fails one clause**: it demands under 8 interrupts per second at 480 Hz with watermark 64, and this driver's FIFO pattern of one sample plus one timestamp entry makes anything under 15 unreachable there, whatever the hardware does. The October run passed that clause at 2.30 per second, implying 208 samples per interrupt, which the same pattern does not permit, so the two figures disagree by five times and that is open. The project's three-path comparison on one apparatus. Trigger path timestamp spread 7.088 us against a 100 us threshold. FIFO with a watermark of 64 against a watermark of 1: same sample rate, forty times fewer interrupts, three times less CPU. It also contains the derivation of why `iio-rate`'s `expected` interrupt count is wrong for this driver family, half the FIFO entries being timestamps and the drain not being instantaneous, with one fitted constant and three predictions checked against it. **No sample value has been checked**: these runs count samples and interrupts, they do not ask whether the numbers are right | Saturday 24 October 2026 |
| `yocto-bind-2026-10-24.txt` | **The question the project opened with, answered.** `st_lsm6dsx` from the tree this repository builds binds at `0x6b` and produces two IIO devices sharing one hardware FIFO, under `bench-iio-image` from commit `b373892` on kernel 6.6.63-v8. Four of seven parts working, every previous record in this directory having been taken on eplepi with out-of-tree drivers loaded by `insmod`. It also records `iio_sysfs_trigger` present with no package behind it, which is the working side of the `do_rootfs` failure in decision 139. **No sample has been read**: this settles binding and nothing about the numbers. It also carries the magnetometer at `0x1e`, found `not-bound` and traced to a probe failing with `-22`: `st_magn` defaults every part to DRDY pin INT2 and the LIS2MDL declares only INT1, so the node needs `st,drdy-int-pin = <1>`. Read out of the 6.6.63 source, then **measured**: with the property the probe is clean and `0x1e` is `working`, which takes it to five of seven parts and unblocks the hrtimer path |
| `i2c-scan-2026-10-24.txt` | The shield on the Pi 3B+ on five leads. Six of the seven predicted addresses answered, and the two IMUs identified by `WHO_AM_I`: `0x6a` is the LSM6DSO16IS and `0x6b` the LSM6DSV16X, which is the question `docs/hardware.md` raised on Wednesday 7 October 2026. The LIS2DUXS12 at `0x19` is absent and the file says why. **No driver is bound**, because this card carries the project 5 image |

| File | How to produce it |
|---|---|
| `i2c-scan.txt` | `i2cdetect -y 1`, then `iio-probe -v`, on the board with the shield fitted. Settles criterion 1: the four addresses, each IIO device reporting the name the driver gives it, and the SHT40 in `sensors` |
| `inventory.txt` | `iio-probe -m`. Criterion 2, and it is the file that fills the empty status column in the sensor table in the project README |
| `trigger-rate.txt` | `iio-rate trigger lis2mdl 100`, 5 s at 100 Hz. Criterion 3 is the standard deviation of the timestamp interval, below 100 us |
| `fifo-rate.txt` | `iio-rate fifo` twice, at 416 Hz with watermark 64 and then without. Criterion 4 wants interrupts per second and reader CPU from both, since the point is the difference between them |
| `iiod-diff.txt` | `iio-stream` once with `local:` and once with `ip:`, then `diff` of the two CSVs. Criterion 5. Needs the network, which the board does not have while the shield is being read over the console |
| `ahrs-gravity.txt` | `ahrs --selftest` first, then the shield held flat and rotated 90 degrees about each axis by hand. Criterion 8 is **partly met** without this file: the filter is checked against known rotations in `tests/ahrs-test.sh` to within 0.06 degrees, and nothing has been checked against real gravity |

**The INT1 pin is settled, and by a document rather than by a trace.**
[DESIGN.md](../DESIGN.md) says it is not known from the drawing, and the
instruction here was to write down what was traced. It did not have to be
traced in the end: UM3239 Rev 5 Table 4 lists the whole Arduino connector,
and `CN9 pin 6` is the LSM6DSV16X's `INT1`, with `CN9 pin 5` its `INT2`
and `CN8 pin 6` the LSM6DSO16IS's `INT1`. The manual arrived as a file on
Saturday 24 October 2026; `st.com` still refuses this bench.

That is worth separating from what the board showed. The connector map is
read from a vendor document and the addresses are measured, and only the
second kind can contradict the first.
