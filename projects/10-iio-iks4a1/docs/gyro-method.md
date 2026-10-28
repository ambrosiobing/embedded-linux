# Measuring the gyroscope, and why the accelerometer had to come first

Written Monday 26 October 2026, before any gyroscope sample has been read,
because the method decides what the numbers can mean and writing it
afterwards would let the numbers decide the method.

## The problem, stated exactly

Every accelerometer measurement in this project rests on one free fact: a
stationary board reads `g`, whichever way it points. That is a standing
reference. It needs no jig, no known orientation and no second instrument,
and it is what
[`evidence/accel-sixposition-2026-10-26.md`](evidence/accel-sixposition-2026-10-26.md)
used to pin three sensitivities and three offsets to 0.038 per cent.

**There is no such fact for rotation rate.** A board at rest on the bench
is not turning at a convenient known rate; it is turning with the Earth, at

    360 degrees / 86164.1 s = 0.0041781 degrees/s = 15.041 degrees/hour

That is a real rotation and it is the only free rate reference in the room.
Whether this part can see it is decided by its own bias stability, which is
not yet measured here. **The prediction is that it cannot**, by about two
orders of magnitude, and that prediction is written down so the stationary
capture below can contradict it.

So the reference has to be built rather than found.

## The rejected alternative, named

**A known rate source.** A turntable at 33 1/3 rpm is 200.0 degrees/s
exactly and at 45 rpm is 270.0 degrees/s exactly, which would be a direct
rate reference needing no integration and no accelerometer. Nothing on this
bench turns at a known rate: see the parts list in
[`hardware.md`](hardware.md). A fan, a shaver or a hand cannot state its
own speed, and an instrument that cannot state its reference is not a
reference.

That is worth recording rather than omitting, because it is the method this
project would use if one more object were on the bench, and it is the one
that would measure rate directly instead of inferring it from angle.

## What is used instead: angle, which does have a reference

Rate has no standing reference. Its integral does. Gravity's direction in
the body frame is an angle, and the accelerometer now reports it to a known
accuracy. So:

    rotate the board from one static pose to another
    the gyroscope integrates to an angle
    the accelerometer measures the same angle from its two endpoints

This chains one instrument onto another, which is only honest because the
first one's error is now characterised and bounded. **That is the reason
the accelerometer work came first**, and it would have been worth doing for
this reason alone.

### What the reference is worth, computed before the measurement

Per-reading accelerometer noise is 0.30 mg, so one reading fixes gravity's
direction to about 3.0e-4 rad, or 0.017 degrees. Averaging 25 readings per
pose takes that to 0.0034 degrees, below the systematic residual, so the
systematic term dominates: 0.038 per cent of magnitude is about 3.8e-4 rad,
or 0.022 degrees. Two endpoints in quadrature:

    reference angle accuracy  about 0.03 degrees
    on a 90 degree rotation   about 0.035 per cent

**That is the ceiling on this method's scale factor result**, fixed before
any gyroscope sample exists. No amount of care downstream improves it.

## The three parameters, and which need a reference at all

| Parameter | Reference needed | How |
|---|---|---|
| Zero-rate offset | none | the board is still, so true rate is Earth rate, 0.0042 degrees/s, which is the floor on the answer and not a correction to it |
| Scale factor | angle, from the accelerometer | integrate one axis across a rotation between two static poses |
| Noise, and its random walk | none | Allan deviation of a long still capture |
| Cross-axis sensitivity | not measured | the model is three independent axes and nothing here separates off-diagonal terms from residual |
| Rate nonlinearity | not measured | hand speed is uncontrolled; repeating at several speeds is a diagnostic, not a sweep |
| Temperature | not measured | one part, one day, one temperature |

The bias is the easy one here and the offset was the hard one for the
accelerometer, which is the reverse of the usual intuition. Zero rate is
physically available on a bench; zero acceleration is not.

## The reversal, which is the structural core

One rotation cannot separate a scale error from a residual bias, for the
same reason one accelerometer pose could not separate a gain error from an
offset. Let the true angle be `T`, the scale error `e` and the residual
bias `b`, with the two runs taking `t1` and `t2`:

    outward   integral = (1+e)(+T) + b*t1
    return    integral = (1+e)(-T) + b*t2

    sum        = b*(t1 + t2)          gives the residual bias
    difference = 2(1+e)T + b*(t1-t2)  gives the scale, bias free

**So the unit of measurement is a there-and-back pair, not a single
rotation.** This is the flat-and-inverted pair of
[`evidence/accel-gravity-2026-10-25.md`](evidence/accel-gravity-2026-10-25.md)
transposed into the rate domain.

It also produces the check that can fail. The bias recovered from the sum
must agree with the bias measured directly from the still intervals at each
end of the capture. Two independent routes to one number. **If they
disagree, the model is wrong and no scale factor should be quoted.**

### Two operational rules fall straight out of the algebra

The leftover term in the difference is `b*(t1-t2)`, so:

- **Make the return take about as long as the outward trip**, and report
  how well that held, as `(t1-t2)/t1`.
- The relative error contributed by a residual bias is `b/(mean rate)`,
  with no dependence on the angle or the duration. That single expression
  sets the usable speed band below.

## The usable speed band, also computed first

Lower bound from bias, upper bound from clipping:

    relative error from bias  =  b / mean_rate
    for 0.04 per cent with b = 0.05 degrees/s  gives
                                                  mean_rate > 125 degrees/s

    a hand rotation's peak is roughly 1.6 times its mean, and a sample
    within 90 per cent of full scale is suspect, so
                                                  mean_rate < 0.56 * FS

So the measurement wants a brisk rotation, not a careful slow one, which is
the opposite of the instinct. **A slow rotation is where bias wins.** The
upper edge needs `in_anglvel_scale_available` read off the part rather than
assumed, and the full scale chosen from it before anything is turned.

## The confound that can ruin this, and how it is bounded

**Path versus chord.** The accelerometer measures the angle between two
endpoints. The gyroscope integrates the path actually travelled. They are
equal only for a rotation about one fixed axis. A rotation that wanders two
degrees off axis and comes back adds about four degrees of path to a ninety
degree rotation, which is **4.4 per cent**, against a reference good to
0.035 per cent. This confound is more than a hundred times the reference's
accuracy and it is the reason the method could produce a confident wrong
number.

Three things hold it down, and the third is the one that matters:

1. **Rotate about a physical edge resting on the bench.** The edge
   constrains the axis mechanically. These are the poses already used and
   already validated by the six-position set, so no new fixture is needed.
2. **Integrate the one signed axis, not the magnitude.** The magnitude is
   strictly positive, so every wobble accumulates into it and none of it
   cancels. The signed single-axis integral lets a there-and-back excursion
   cancel to first order. This is a design decision, not a detail.
3. **Bound it from the data.** For a rotation about body X, the integrals
   of the other two channels should be near zero, and their size is a
   direct measurement of the off-axis excursion. So the confound is
   reported as a number beside the result rather than assumed away.

Note that clipping pushes the scale factor the other way, since a clipped
sample integrates low. Two confounds of opposite sign mean a naive run can
be accidentally right, which is why both are checked explicitly.

## The data path, which the project already has

The poll path is unusable here. Reading raw sysfs attributes costs 16.4 ms
per read at 960 Hz, so the motion would be aliased beyond recovery.
Integration needs real timestamps, so it needs the buffered path, whose
timestamp spread is already measured at 7.088 us in
[`evidence/trigger-lis2mdl-2026-10-01.txt`](evidence/trigger-lis2mdl-2026-10-01.txt).

    enable the three anglvel channels and the timestamp
    capture one still-rotate-still window to a file
    iio-decode DEVICE_DIR < buffer.bin > capture.csv

`iio-decode` reads the layout from `scan_elements` rather than assuming it,
which matters more than usual here: this is the first capture in the
project that enables the gyroscope channels rather than the
accelerometer's, so every byte offset moves.

**`iio-stream` is not an option, measured rather than assumed.** On
Monday 26 October 2026 it failed to refill a buffer on this image for
**both** the gyroscope and the accelerometer, while `iio-rate` drove the
same FIFO on both devices at 448 and 460 samples/s with 59 interrupts
each. It also exits 0 after printing `refill failed`, which is worse than
the failure. Both are recorded in
[`evidence/gyro-path-2026-10-26.txt`](evidence/gyro-path-2026-10-26.txt).

**And the two capture tools disagree about units while their CSVs look
identical.** `iio-stream` applies the channel's scale, so its columns are
rad/s. `iio-decode` looks for a per-axis `in_anglvel_x_scale`, which
`st_lsm6dsx` does not publish, having one shared `in_anglvel_scale`, so it
falls through to printing raw counts. Confusing them is a factor of about
sixteen thousand in either direction. `gyro-fit.py` takes `--scale` for a
decoded capture and guards both directions rather than trusting the flag,
because nothing in either header says which it is holding.

**The single-shot sysfs path is worse than slow for this part, it is
wrong.** Eight reads of a motionless board scattered over hundreds of
degrees per second where the truth is 0.0042. That is measured; the
likely cause, a turn-on settling time far longer than the 2 ms the
driver's one-shot read waits, is inferred and untested. It went unnoticed
because every sysfs reading this project has taken was from the
accelerometer.

Integration is trapezoidal on the timestamp column. Rectangular and
trapezoidal are both computed and compared, as a free check on whether the
sample rate was adequate for the motion: at 960 Hz and 225 degrees/s a
sample is 0.23 degrees apart and the two rules should agree closely. If
they do not, the rate was too low and the result is not usable.

## What a run consists of

One capture, in this order, with nothing detached between the parts:

    still at pose A      several seconds, gives the bias before
    rotate A to B        brisk, about a constrained edge
    still at pose B      several seconds
    rotate B to A        brisk, similar duration
    still at pose A      several seconds, gives the bias after

The still intervals are not padding. The bias measured before and the bias
measured after bound the drift that the correction could not catch, and
that difference is the uncertainty quoted on the scale factor.

Three starting poses are needed to reach three axes, because **a rotation
about gravity itself is invisible to the reference**: turning the board
about a vertical axis leaves gravity unchanged in the body frame, so the
accelerometer measures nothing while the gyroscope measures the whole
rotation. Flat on the bench, gravity lies along body Z, so rotations about
X and Y are visible and rotations about Z are not. Standing on an edge puts
Z horizontal and makes Z visible. The pose set is therefore the same one
the six-position fit used.

## What will refuse rather than return a number

By the same standard as
[`../../../scripts/accel-fit.py`](../../../scripts/accel-fit.py), each of
these produces ordinary-looking output from a naive integration:

- no still interval at one end, so no bias and no endpoint pose
- any sample within 90 per cent of full scale, so clipping is possible
- mean rate below the bias-limited floor, where bias dominates the answer
- off-axis integrals large enough to make the path exceed the chord by more
  than the quoted uncertainty
- the two bias routes, from the still intervals and from the reversal sum,
  disagreeing by more than their own spread
- outward and return durations differing enough for the bias term to leak
  into the difference

## What this will not establish, written in advance

- **Rate linearity.** Hand speed spans maybe 50 to 500 degrees/s and is not
  controlled. Repeating at several speeds tests whether a confound is
  active, since the fitted scale must not depend on speed, but it does not
  measure nonlinearity.
- **Low rate behaviour.** The method has a floor, computed above, and the
  region below it is exactly where a gyroscope is hardest to trust.
- **Cross-axis terms, local gravity, temperature.** As for the
  accelerometer, and for the same reasons.
- **Anything about the accelerometer's correctness.** Its errors are now
  inside this measurement's reference. A systematic error there appears
  here as a scale error, which is the price of chaining and is why the
  chained figure can never be better than 0.035 per cent.
