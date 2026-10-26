# The accelerometer calibrated in six positions, and checked against another day

Monday 26 October 2026, Raspberry Pi 3 Model B Plus, `bench-iio-image`
from commit `8ae1ada`, kernel 6.6.63-v8, LSM6DSV16X at `0x6b` reporting as
`lsm6dsv16x_accel`. Board clock read `Mon Oct 26 08:53:19 UTC 2026`.

This continues [`accel-gravity-2026-10-25.md`](accel-gravity-2026-10-25.md),
which measured the Z axis alone from a flat and inverted pair on Sunday 25
October 2026 and could say nothing about X or Y.

## The result

| axis | sensitivity | vs 9.80665 | zero-g offset |
|---|---|---|---|
| X | 16373.6 LSB/g = 9.7948 m/s2 | -0.121 % | -24.6 LSB = -1.50 mg |
| Y | 16403.2 LSB/g = 9.8125 m/s2 | +0.060 % | +86.5 LSB = +5.28 mg |
| Z | 16350.5 LSB/g = 9.7809 m/s2 | -0.262 % | +153.1 LSB = +9.34 mg |

Sixteen orientations whose measured magnitudes spanned **1.90 per cent**
agree to **0.038 per cent** once those six numbers are applied.

The part is specified for roughly +-20 mg of zero-g offset, so all three
are inside it, and sub-half-per-cent sensitivity error is ordinary for an
uncalibrated consumer MEMS device. `in_accel_scale` reads `0.000598205`,
which is exactly `2 x 9.80665 / 32768`: the driver applies the nominal
+-2 g conversion and no calibration whatever, so these errors are the
part's own and are present in every number this project has read from it.

## Method, which needs no knowledge of the orientations

For a stationary board the acceleration vector has magnitude `g` whichever
way the board is pointing. With `m` the measured LSB triple, a per-axis
sensitivity `s` and offset `b`:

    a = (m - b) / s        and        |a| = 1 g for every static pose

Six unknowns. Each settled pose is one equation, and **no pose's
orientation has to be known, estimated or assumed.** That matters because
the obvious alternative, resolving each pose's tilt from its own
components, uses the offsets it is trying to measure. The earlier file
does exactly that and says so; this does not.

Fitted by least squares on the residual `|(m - b)/s| - 1` over all poses.

## The six positions

Twenty-five to thirty readings each, taken with:

    d=/sys/bus/iio/devices/iio:device5
    for i in 1 2 3 4 5; do
      x=$(cat $d/in_accel_x_raw); y=$(cat $d/in_accel_y_raw)
      z=$(cat $d/in_accel_z_raw)
      awk -v x=$x -v y=$y -v z=$z 'BEGIN{m=sqrt(x*x+y*y+z*z);
        printf "%7d %7d %7d   |a| %8.1f  %+6.2f %%\n", x,y,z,m,100*(m/16400-1)}'
      sleep 1
    done

**The magnitude column is a validity test for each pose and it is the
reason the procedure works without a jig.** A reading whose magnitude is
not close to `g` is contaminated by real acceleration, whatever it looks
like otherwise. Two hand-held attempts were rejected on the spot by it, at
`1.28 g` and `1.01 g`, before any of them reached this table.

| Position | X | Y | Z | n |
|---|---|---|---|---|
| lying flat, components up | -75.9 | 148.9 | **16505.3** | 25 |
| lying flat, components down | -625.0 | -136.8 | **-16187.8** | 25 |
| standing, long edge A | -49.0 | **-16316.6** | 204.0 | 30 |
| standing, long edge B | -67.0 | **16486.9** | -150.6 | 12 |
| standing, long edge B prime | -92.2 | **16483.6** | -295.0 | 12 |
| standing, short edge A | **16350.9** | 188.8 | -18.7 | 30 |
| standing, short edge B | **-16323.4** | 253.1 | -1402.0 | 25 |

Every axis sees gravity both ways, which is the whole point of a
six-position set: a single direction cannot separate a gain from an
offset, because a positive offset and a negative gain error produce the
same reading.

**One position is split in two and was not averaged.** During "long edge
B" the board moved between the twelfth and thirteenth readings: Z steps
from about -150 to about -295 and X from -67 to -92, then holds steady
again. Both halves are individually quiet, so they are recorded as two
orientations. Averaging across a shift that visibly happened would have
invented a pose that never existed.

## The check that could have failed

Leave-one-out inside a six-position set is weak and the reason is
structural: remove the only pose in which an axis points one way and that
axis's offset is no longer determined at all. Dropping "long edge A", the
single negative-Y pose, costs 39.65 mg. That is the fit extrapolating, not
a bad reading, and it would be misleading to quote it as an error.

The honest test uses two independent sessions. Sunday's ten poses and
Monday's seven were taken hours apart with the board handled repeatedly in
between. **Fit one, predict the other.**

    fitted on Monday's seven      X 16375.3   Y 16403.3   Z 16353.0
    fitted on Sunday's ten        X 16372.7   Y 16403.0   Z 16349.3
    difference                       0.016 %     0.002 %     0.022 %
    offsets differ by                2.0 LSB     0.1 LSB     0.8 LSB

    Monday's fit predicting Sunday's ten poses    worst 0.38 mg, rms 0.20
    Sunday's fit predicting Monday's seven        worst 0.28 mg, rms 0.16

The noise floor from repeat readings of a motionless board is about
0.30 mg. So each session's parameters predict the other session's
orientations to within the sensor's own noise. A model that merely
absorbed its own data could not do that.

## What this does NOT establish

- **Local gravity was not measured.** The percentages are against standard
  gravity 9.80665. If local gravity is nearer 9.8086 every sensitivity
  shifts by the same -0.02 per cent, giving -0.141, +0.040 and -0.282.
  **The spread between axes, 0.32 per cent, does not depend on that
  assumption; the absolute figures do.** Calibrating against the part
  rather than against the Earth would need the local value.
- **Cross-axis sensitivity is not measured.** The model is three
  independent axes, a diagonal matrix. Real parts have small off-diagonal
  terms, and nothing here would separate them from the residual.
- **The gyroscope is untouched.** Gravity is a standing reference for
  acceleration and there is no equivalent for rotation rate, so that is a
  different kind of measurement.
- **One part, one day, one temperature.** Zero-g offset moves with
  temperature and nothing here characterises that.
- **No correction has been applied anywhere.** These numbers describe the
  part; the driver still reports uncorrected values, and every other
  measurement in this project was taken through them.
