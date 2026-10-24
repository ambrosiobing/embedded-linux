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
