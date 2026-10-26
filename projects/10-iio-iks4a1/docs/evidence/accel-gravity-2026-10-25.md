# The accelerometer measured against gravity

Sunday 25 October 2026, Raspberry Pi 3 Model B Plus, `bench-iio-image`
from commit `8ae1ada`, kernel 6.6.63-v8, X-NUCLEO-IKS4A1, LSM6DSV16X at
`0x6b` reporting as `lsm6dsv16x_accel`.

**SUPERSEDED IN PART on Monday 26 October 2026** by
[`accel-sixposition-2026-10-26.md`](accel-sixposition-2026-10-26.md), which
measures all three axes from six positions and validates the result against
this session. Nothing below is withdrawn: the Z figures here agree with the
six-position fit to 0.022 per cent. What changes is the method. This file
resolves each pose's tilt from its own components, which uses the offsets it
is trying to measure; the six-position fit needs no orientation at all.

**This is the first measurement in this project that asks whether a number
is correct.** Every earlier run counted samples, interrupts and CPU, and
none of them would have noticed a sensor returning plausible nonsense.

## The scale, which is a fact about the driver

    in_accel_scale  0.000598205

`2 x 9.80665 / 32768 = 0.00059856`, so the part is on its **+-2 g full
scale** and the driver applies the **nominal** conversion with no
calibration of any kind. Whatever gain and offset the individual part has,
they are still in the numbers.

## The readings

Raw LSB, `in_accel_{x,y,z}_raw`.

**Flat, resting on the bench, four readings:**

| X | Y | Z |
|---|---|---|
| -27 | 192 | 16501 |
| -22 | 189 | 16503 |
| -21 | 191 | 16500 |
| -22 | 193 | 16502 |
| mean -23.0 | mean 191.3 | **mean 16501.5** |

Tilt from the horizontal components: **0.67 degrees.**

**Inverted, resting on the bench, five readings:**

| X | Y | Z |
|---|---|---|
| 360 | -11 | -16191 |
| 361 | -13 | -16194 |
| 365 | -11 | -16191 |
| 368 | -8 | -16190 |
| 371 | -8 | -16187 |
| mean 365.0 | mean -10.2 | **mean -16190.6** |

Tilt: **1.29 degrees.** Spread on Z across five readings is 7 LSB, about
0.004 m/s2, which is the noise floor at this output data rate.

## Gain and offset, which one pose cannot separate

With the board square both ways up, Z sees `+g` then `-g` and the two
unknowns fall out:

    offset  = (z_flat + z_inverted) / 2 = (16501.5 - 16190.6) / 2 =  155.5 LSB
    gravity = (z_flat - z_inverted) / 2 = (16501.5 + 16190.6) / 2 = 16346.1 LSB

    gravity    16346 LSB  x 0.000598205  =  9.7783 m/s2
    Z zero-g     155 LSB  x 0.000598205  =  0.0930 m/s2  =  +9.5 mg

Against standard gravity 9.80665 the gain error is **-0.30 per cent**. The
LSM6DSV16X is specified for roughly +-20 mg of zero-g offset, so 9.5 mg is
inside it, and a sub-one-per-cent gain error is ordinary for an
uncalibrated consumer MEMS part.

**The arithmetic reconstructs the single reading it replaces.** The first
flat pose alone looked 0.66 per cent HIGH, at 9.8717 m/s2, and that was
read at the bench as a gain error. It is not:

    9.7783 (gain, low)  +  0.0930 (offset, high)  =  9.8713 m/s2

which is the flat reading back again to four digits. One pose reported the
sum of two errors of opposite sign as though it were one quantity. Two
opposite poses separate them, and nothing else does.

## Gravity does not depend on which way up the board is, and that is the test

A static board reads `g` in any orientation, so magnitude is the invariant
to watch. Three hand-held poses taken while establishing that the sysfs
value tracks the sensor:

| Pose | X | Y | Z | magnitude |
|---|---|---|---|---|
| flat | -22 | 193 | 16502 | 16502, 9.872 m/s2 |
| edge, X down | -16366 | 760 | -921 | 16410, 9.816 m/s2 |
| edge, Y down | 69 | -15927 | -3407 | 16287, 9.743 m/s2 |
| inverted, tilted | 2747 | 3030 | -15471 | 16002, 9.573 m/s2 |

**Those four are NOT calibration data and must not be quoted as such.**
They were taken in the hand, so each carries real acceleration on top of
gravity, and a wobble is indistinguishable from a gain error in a single
sample. They are here because the 3.1 per cent spread in magnitude is
itself the signature being measured: tilt cannot change a magnitude, and a
per-axis offset can, because it adds in one direction and subtracts in the
other. The spread pointed at an offset before the matched pair measured
one.

## Four identical readings that were not a stuck value

Before the board was moved, four consecutive reads returned Z within 3 LSB
of each other. That is what a quiet sensor on a motionless bench looks
like, and it is also exactly what a stale or cached value would look like.
The two were separated by reading again while the board was plainly being
tilted, and the numbers swung across the full range.

Worth keeping because the ambiguity was real: repeatability and staleness
produce the same evidence until something moves.

## What this does NOT establish

- **X and Y gain are not measured.** In the flat and inverted poses both
  read near zero, and a reading near zero cannot test a scale factor. They
  need their own matched pairs, resting on each edge.
- **Cross-axis sensitivity is untested.**
- **The gyroscope is untested.** Nothing here says anything about it.
- **Local gravity was not used.** Standard gravity 9.80665 is the
  reference above, and local gravity ranges from about 9.78 to 9.83 with
  latitude and altitude, which is the same size as the gain error quoted.
  A bench-grade statement of gain wants the local value; this is good
  enough to show the part is in tolerance and not good enough to calibrate
  against.
- **It is one part on one day at one temperature.** Zero-g offset moves
  with temperature, and nothing here characterises that.
