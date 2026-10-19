# The two drivers on one part, Saturday 17 October 2026

The comparison this project was arranged around before a line of its
driver existed. One ADXL345, one breadboard, one orientation, two
drivers, eleven minutes apart. The only thing that changed between the
two readings is one word in `/boot/config.txt`:

    dtoverlay=bench-adxl345        ->   dtoverlay=bench-adxl345-adi

Both overlays travel on the card and differ in one property, the
compatible string, generated from the one source at build time so they
cannot drift: decision 123.

| | this project's driver | mainline's |
|---|---|---|
| `name` | `bench-adxl345` | `adxl345` |
| `in_accel_scale` | 0.038245935 | 0.038300 |
| x, y, z | -13, 56, 240 | -14, 57, 239 |
| magnitude | 246.79 counts | 246.10 counts |
| | 9.4387 m/s^2, 0.9625 g | 9.4257 m/s^2, 0.9612 g |

`dmesg | grep -i adxl` returned nothing under mainline: it bound
silently, as ours does.

## And back again, which is what makes it a control

The overlay was swapped back the same evening and the part read a third
time: x -14, y 56, z 240, magnitude 246.84 counts, against 246.79 before
the swap and 246.10 under mainline.

A before and an after can always be explained by the hour between them.
A before, an after and a return cannot: the part is where it started, so
the 0.28 per cent between the two arms belongs to the readings rather
than to drift, temperature or a knocked breadboard.

## The axes agree and say nothing surprising

A count on each axis, 0.28 per cent on the magnitude, which is this
part's own noise: the triggered capture earlier the same day varied by
up to three counts between consecutive scans with nothing touching the
board. Both drivers read the same six registers over the same bus and
sign-extend the same 13 bits, so agreement here was the expected result
and its value is that it was checked rather than assumed.

Both magnitudes sit about 3.8 per cent under one g. That is the part,
not the drivers, and it is consistent with every other reading taken on
this bench since Friday 9 October 2026.

## The scales disagree, and both derivations are written down

0.141 per cent apart, and neither number is wrong by its own reasoning.

**Ours** is derived in `bench-adxl345.h` from the datasheet's quoted
scale factor for full-resolution mode:

    3.9 mg/LSB * 9.80665 m/s^2/g = 0.038245935

**Mainline's** is derived in `drivers/iio/accel/adxl345_core.c` from the
span rather than from the sensitivity, and its comment says so:

    /*
     * At +/- 16g with 13-bit resolution, scale is computed as:
     * (16 + 16) * 9.81 / (2^13 - 1) = 0.0383
     */
    static const int adxl345_uscale = 38300;

Measured against the datasheet's typical sensitivity of 256 LSB per g
with standard gravity, which is 0.03830723:

| | value | against 256 LSB/g |
|---|---|---|
| ours | 0.038245935 | -0.160 % |
| mainline, reported | 0.038300 | -0.019 % |
| mainline, before rounding | 0.03832499 | +0.046 % |

**Mainline is closer, and partly by luck.** Using `2^13 - 1` rather than
4096 counts per 16 g adds 0.012 per cent, and 9.81 rather than 9.80665
adds another 0.034 per cent; rounding the result to three significant
figures then takes 0.065 per cent back off. The errors happen to cancel.

**Ours is low because 3.9 is a rounded number.** The datasheet prints
3.9 mg/LSB in its table and 256 LSB/g in its specifications, and those
are the same quantity: 1/256 g is 3.90625 mg. Deriving from the rounded
form costs 0.16 per cent.

## What follows from that, and what does not

Nothing here says either driver is defective. Both figures are inside
the part's own sensitivity tolerance, and this part is 3.8 per cent off
nominal anyway, which is twenty times the disagreement.

What it does say is that the more defensible constant is 1/256 rather
than 3.9, because one is the specification and the other is the
specification rounded for a table. Changing ours would move
`in_accel_scale` from 0.038245935 to 0.038307226, make every figure this
project has published 0.16 per cent larger, and require
`tests/adxl345-driver-test.sh` to recompute the constant from the new
pair. It is left unchanged here, and recorded, so that the choice is
made deliberately rather than as a side effect of this capture.

## Correction applied, Monday 19 October 2026

The change was made. `BENCH_ADXL345_SCALE_NANO` went from 38245935 to
38307227, which is 9.80665 / 256 rounded onto IIO's one nano grid. The
paragraph above says 0.038307226; that is the same number truncated
rather than rounded, and the constant takes the nearer grid point.

**Every figure above is left exactly as it was measured.** The numbers
in this file were produced by the driver as it stood on Saturday 17
October 2026, and rewriting them would destroy the only record of what
that driver reported. To read them against the corrected driver:

| as printed here | corrected | change |
|---|---|---|
| `in_accel_scale` 0.038245935 | 0.038307227 | +0.160 % |
| 9.4387 m/s^2 | 9.4538 m/s^2 | +0.160 % |
| 0.9625 g | 0.9641 g | +0.160 % |

Raw counts are untouched, because the scale never reached them: x -8,
y 46, z 242 are what the part converted and they still are.

**The disagreement this capture measured is now 0.019 per cent, not
0.141.** Ours was 0.160 per cent low and mainline 0.019 per cent low
against 256 LSB/g; with ours corrected to the specification the two
differ only by mainline's own rounding to three significant figures.

**One thing fell out of it that is worth more than the 0.16 per cent.**
The driver's comment on the tap threshold had called the ratio between
the threshold scale and the channel scale "16.03, which the datasheet
does not bless". With the channel derived from 256 LSB/g the two are
1/16 g and 1/256 g, so the ratio is exactly 16. The awkward number was
an artefact of the rounded 3.9, and the part's two scale factors are
exact binary fractions of g. The limit on converting thresholds stays,
for the other reason the comment gives: a converted value reads back as
something other than what was written.
