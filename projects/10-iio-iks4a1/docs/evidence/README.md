# Portfolio evidence

What goes here, and how each item is produced. Empty until the board has
actually run; nothing in this folder should be written from expectation.

The shield has never been on a header, so every row below is a plan. The
[project README](../../README.md) marks criteria 6 and 7 met on a laptop,
because they are properties of the programs rather than of the board, and
those two are the only ones that do not need this folder.

| File | How to produce it |
|---|---|
| `i2c-scan.txt` | `i2cdetect -y 1`, then `iio-probe -v`, on the board with the shield fitted. Settles criterion 1: the four addresses, each IIO device reporting the name the driver gives it, and the SHT40 in `sensors` |
| `inventory.txt` | `iio-probe -m`. Criterion 2, and it is the file that fills the empty status column in the sensor table in the project README |
| `trigger-rate.txt` | `iio-rate trigger lis2mdl 100`, 5 s at 100 Hz. Criterion 3 is the standard deviation of the timestamp interval, below 100 us |
| `fifo-rate.txt` | `iio-rate fifo` twice, at 416 Hz with watermark 64 and then without. Criterion 4 wants interrupts per second and reader CPU from both, since the point is the difference between them |
| `iiod-diff.txt` | `iio-stream` once with `local:` and once with `ip:`, then `diff` of the two CSVs. Criterion 5. Needs the network, which the board does not have while the shield is being read over the console |
| `ahrs-gravity.txt` | `ahrs --selftest` first, then the shield held flat and rotated 90 degrees about each axis by hand. Criterion 8 is **partly met** without this file: the filter is checked against known rotations in `tests/ahrs-test.sh` to within 0.06 degrees, and nothing has been checked against real gravity |

One thing to record here that no criterion asks for: which Arduino pin
carries INT1. [DESIGN.md](../DESIGN.md) says plainly that it is not known
from the drawing, and the first session with the shield settles it. Write
what was traced and how, not what the pin was assumed to be.
