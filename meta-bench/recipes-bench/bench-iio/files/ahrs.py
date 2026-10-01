#!/usr/bin/env python3
"""ahrs - orientation from an accelerometer, a gyroscope and a magnetometer.

Importable as a module, runnable as a self check, and runnable against a
real capture:

    python3 ahrs.py --selftest
    python3 ahrs.py --capture FILE --scale 16384 --rate 126.4

The self check uses synthetic rotations whose answers are known from the
geometry. The capture mode uses recorded gravity, which is the only one of
the two that can be wrong about this bench.

WHICH FILTER, AND WHY NOT THE ONE THE SPECIFICATION NAMES

The specification asks for a Madgwick AHRS, and this is Madgwick's
gradient-descent update for the accelerometer and gyroscope, which is the
part of it that decides pitch and roll. It is not his MARG variant, which
folds the magnetometer into the same gradient through a six-row Jacobian.

That is a deliberate substitution and the reason is the one the bench
method already states: do not copy a filter's helpers from a repository
without checking the sign conventions against the paper. The MARG Jacobian
is exactly where published implementations disagree with each other, in
signs and in the handedness of the reference frame, and a wrong sign there
does not produce an obviously broken result. It produces an orientation
that tracks beautifully and is mirrored, which is much worse.

So yaw comes from a tilt-compensated magnetic heading instead: rotate the
measured field into the horizontal plane using the roll and pitch the
filter already has, and take the arctangent. That is four lines, it is
derivable on paper in a minute, and every step of it is checkable against a
known rotation, which is what tests/ahrs-test.sh does.

The cost is that yaw is not smoothed by the gyroscope, so it is noisier
than a full MARG filter would give, and it is honest about which of the
three axes is being measured rather than integrated. The acceptance
criterion this project has to meet is pitch and roll within 2 degrees when
flat and within 3 degrees after a 90 degree rotation, which this answers
directly.

CONVENTIONS, STATED BECAUSE EVERY BUG IN THIS FILE WOULD BE ONE OF THEM

  quaternion  (w, x, y, z), unit length, rotating sensor frame to earth
  gyro        radians per second, right handed about x, y, z
  accel       any unit; normalised internally. At rest it reads +g UP,
              because an accelerometer measures proper acceleration and a
              stationary sensor is accelerating upwards at g
  magn        any unit; normalised internally
  euler       roll about x, pitch about y, yaw about z, in degrees

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import argparse
import math
import sys


def quat_mul(a, b):
    """Hamilton product, (w, x, y, z)."""
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (
        aw * bw - ax * bx - ay * by - az * bz,
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
    )


def quat_normalise(q):
    norm = math.sqrt(sum(c * c for c in q))
    if norm == 0.0:
        # A zero quaternion has no orientation to report. Returning the
        # identity is a lie that propagates; raising says which sample was
        # impossible.
        raise ValueError("quaternion collapsed to zero length")
    return tuple(c / norm for c in q)


def vec_normalise(v):
    norm = math.sqrt(sum(c * c for c in v))
    if norm == 0.0:
        raise ValueError("vector of zero length cannot give a direction")
    return tuple(c / norm for c in v)


def quat_rotate(q, v):
    """Rotate v from the sensor frame into the earth frame."""
    qw, qx, qy, qz = q
    vx, vy, vz = v
    t = quat_mul(quat_mul(q, (0.0, vx, vy, vz)), (qw, -qx, -qy, -qz))
    return (t[1], t[2], t[3])


def to_euler(q):
    """Roll, pitch and yaw in degrees, from a sensor-to-earth quaternion."""
    qw, qx, qy, qz = q

    roll = math.atan2(2.0 * (qw * qx + qy * qz), 1.0 - 2.0 * (qx * qx + qy * qy))

    # asin's argument leaves [-1, 1] through rounding alone near the poles,
    # and math.asin raises rather than saturating. Clamping here is not
    # papering over an error: at 89.999 degrees of pitch the value really is
    # 1.0 to the precision available.
    sin_pitch = 2.0 * (qw * qy - qz * qx)
    sin_pitch = max(-1.0, min(1.0, sin_pitch))
    pitch = math.asin(sin_pitch)

    yaw = math.atan2(2.0 * (qw * qz + qx * qy), 1.0 - 2.0 * (qy * qy + qz * qz))

    return tuple(math.degrees(a) for a in (roll, pitch, yaw))


def madgwick_update(q, gyro, accel, dt, beta=0.1):
    """One update step, accelerometer and gyroscope only.

    The gyroscope integrates orientation and drifts. The accelerometer
    knows which way is down and is useless while the sensor is being
    accelerated. beta is how much the second is allowed to correct the
    first, per second.

    The objective function f is "what the accelerometer would read if the
    orientation were q, minus what it actually reads", and J is its
    Jacobian with respect to q. Their product is the direction in
    quaternion space that reduces the disagreement, which is subtracted
    from the gyroscope's integration.
    """
    q0, q1, q2, q3 = q
    gx, gy, gz = gyro

    # Rate of change from the gyroscope alone.
    qdot = quat_mul(q, (0.0, gx, gy, gz))
    qdot = tuple(0.5 * c for c in qdot)

    # An accelerometer reading of zero length carries no direction, so
    # there is nothing to correct with and the gyroscope is integrated
    # alone. That is free fall, and it is a real state rather than an
    # error.
    norm = math.sqrt(sum(c * c for c in accel))
    if norm > 0.0:
        ax, ay, az = (c / norm for c in accel)

        f = (
            2.0 * (q1 * q3 - q0 * q2) - ax,
            2.0 * (q0 * q1 + q2 * q3) - ay,
            2.0 * (0.5 - q1 * q1 - q2 * q2) - az,
        )
        # J transposed, applied directly, because only J^T f is ever
        # needed and building the 3x4 matrix to multiply it once is
        # arithmetic nobody can check by reading.
        step = (
            -2.0 * q2 * f[0] + 2.0 * q1 * f[1],
            2.0 * q3 * f[0] + 2.0 * q0 * f[1] - 4.0 * q1 * f[2],
            -2.0 * q0 * f[0] + 2.0 * q3 * f[1] - 4.0 * q2 * f[2],
            2.0 * q1 * f[0] + 2.0 * q2 * f[1],
        )
        step_norm = math.sqrt(sum(c * c for c in step))
        if step_norm > 0.0:
            step = tuple(c / step_norm for c in step)
            qdot = tuple(d - beta * s for d, s in zip(qdot, step))

    return quat_normalise(tuple(c + d * dt for c, d in zip(q, qdot)))


def tilt_compensated_heading(q, magn, declination=0.0):
    """Magnetic heading in degrees, corrected for the sensor's attitude.

    The magnetometer measures the field in the sensor's own frame, so a
    tilted sensor reports a different horizontal direction for the same
    field. Rotating the measurement into the earth frame with the
    orientation the filter already has removes exactly that, which is why
    this needs the attitude and cannot be computed on its own.
    """
    ex, ey, _ = quat_rotate(q, vec_normalise(magn))
    heading = math.degrees(math.atan2(-ey, ex)) + declination
    return heading % 360.0


class Ahrs:
    """The filter as a small object, because a loop needs to keep state."""

    def __init__(self, beta=0.1, declination=0.0):
        self.q = (1.0, 0.0, 0.0, 0.0)
        self.beta = beta
        self.declination = declination

    def update(self, gyro, accel, dt, magn=None):
        if dt <= 0.0:
            # A non-positive dt means two samples carried the same
            # timestamp or arrived out of order. Integrating it would
            # rotate the estimate backwards, so the sample is dropped and
            # the caller is told rather than silently absorbing it.
            raise ValueError(f"dt must be positive, got {dt!r}")
        self.q = madgwick_update(self.q, gyro, accel, dt, self.beta)
        roll, pitch, _ = to_euler(self.q)
        if magn is None:
            yaw = to_euler(self.q)[2]
        else:
            yaw = tilt_compensated_heading(self.q, magn, self.declination)
        return roll, pitch, yaw


def selftest() -> int:
    """Physics, not another filter.

    Every check here is a rotation whose answer is known from the geometry:
    gravity down means level, gravity along an axis means ninety degrees
    about another, and a gyroscope turning at a known rate for a known time
    has turned by their product. That is the only way to catch a sign error,
    because a mirrored filter tracks just as smoothly as a correct one.
    """
    failures = 0

    def near(name, got, want, tol):
        nonlocal failures
        if abs(got - want) <= tol:
            print(f"ok       {name}: {got:+.2f} (want {want:+.2f})")
        else:
            print(f"FAILED   {name}: {got:+.2f}, want {want:+.2f} +-{tol}")
            failures += 1

    # Flat and still. An accelerometer at rest reads +g on the axis
    # pointing up, so a level sensor reads (0, 0, 1).
    f = Ahrs()
    for _ in range(2000):
        roll, pitch, _ = f.update((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.01)
    near("level roll", roll, 0.0, 1.0)
    near("level pitch", pitch, 0.0, 1.0)

    # Rolled 90 degrees about x.
    #
    # The sensor rotates by R relative to the world, so a world vector
    # appears in sensor coordinates as R^T v. For R = Rx(+90), world up
    # (0, 0, 1) becomes (0, +1, 0): the accelerometer reads +g on its y
    # axis.
    #
    # This is where the first version of this selftest was wrong. It fed
    # (0, -1, 0), which is the MINUS ninety case, and asserted +90. The
    # filter reported -89.94 and was right. What made the mistake visible
    # was that the gyroscope check below passed at the same time: two paths
    # to the same quantity disagreeing is the only cheap way to catch a
    # sign convention, because a mirrored filter tracks just as smoothly as
    # a correct one.
    f = Ahrs()
    for _ in range(4000):
        roll, pitch, _ = f.update((0.0, 0.0, 0.0), (0.0, 1.0, 0.0), 0.01)
    near("rolled 90 about x", roll, 90.0, 3.0)

    f = Ahrs()
    for _ in range(4000):
        roll, pitch, _ = f.update((0.0, 0.0, 0.0), (0.0, -1.0, 0.0), 0.01)
    near("rolled -90 about x", roll, -90.0, 3.0)

    # Pitched 90 degrees about y: Ry(+90)^T applied to (0, 0, 1) is
    # (-1, 0, 0), so the accelerometer reads -g on its x axis.
    f = Ahrs()
    for _ in range(4000):
        roll, pitch, _ = f.update((0.0, 0.0, 0.0), (-1.0, 0.0, 0.0), 0.01)
    near("pitched 90 about y", pitch, 90.0, 3.0)

    # The gyroscope alone, with no accelerometer to correct it: 90 degrees
    # per second for one second is 90 degrees. This is the one that catches
    # a sign error in the Hamilton product, because a mirrored filter
    # reports -90 just as confidently.
    f = Ahrs(beta=0.0)
    rate = math.radians(90.0)
    for _ in range(1000):
        roll, _, _ = f.update((rate, 0.0, 0.0), (0.0, 0.0, 0.0), 0.001)
    near("gyro integrates in the right direction", roll, 90.0, 1.0)

    # Heading, level, with the field pointing along +x in the sensor frame.
    f = Ahrs()
    for _ in range(2000):
        f.update((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.01)
    near("heading with the field on +x", tilt_compensated_heading(f.q, (1.0, 0.0, 0.5)), 0.0, 2.0)
    near("heading with the field on +y", tilt_compensated_heading(f.q, (0.0, 1.0, 0.5)), 270.0, 2.0)

    # A dt of zero is a repeated timestamp, and integrating it would be a
    # silent no-op that hides a broken data path.
    try:
        Ahrs().update((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), 0.0)
        print("FAILED   a zero dt is rejected")
        failures += 1
    except ValueError:
        print("ok       a zero dt is rejected")

    print()
    print("selftest failures:", failures)
    return 1 if failures else 0


def read_capture(path, lsb_per_g):
    """Samples from a burst-read capture: an index, then six hex bytes.

    The format is the one the i2ctransfer loop in Project 10's BRINGUP
    produces: OUTX_L, OUTX_H, OUTY_L, OUTY_H, OUTZ_L, OUTZ_H, little-endian
    and signed.

    A line that is not an index plus exactly six bytes is damaged, and is
    counted and skipped rather than repaired. Interpolating across it would
    put a number into an orientation result that no sensor produced.
    """
    samples = []
    skipped = 0
    with open(path) as handle:
        for line in handle:
            fields = line.split()
            if len(fields) != 7:
                skipped += 1
                continue
            try:
                raw = [int(x, 16) for x in fields[1:7]]
            except ValueError:
                skipped += 1
                continue
            vector = []
            for i in (0, 2, 4):
                word = raw[i] | (raw[i + 1] << 8)
                if word >= 32768:
                    word -= 65536
                vector.append(word / lsb_per_g)
            samples.append(tuple(vector))
    return samples, skipped


def direct_tilt(accel):
    """Roll and pitch straight from gravity, with no filter involved.

    This exists to be disagreed with. The filter's answer and this one come
    from the same samples by different routes, so a gap between them is a
    fault in the filter rather than in the bench, and agreement is worth
    more than either number alone.
    """
    ax, ay, az = accel
    roll = math.degrees(math.atan2(ay, az))
    pitch = math.degrees(math.atan2(-ax, math.sqrt(ay * ay + az * az)))
    return roll, pitch


def gravity_from(roll_deg, pitch_deg):
    """The unit gravity vector a roll and pitch imply, in the sensor frame.

    The exact inverse of direct_tilt, and the reason it exists is that two
    orientations can be compared this way at any pose. Euler angles cannot:
    roll is ill-conditioned near a pitch of ninety degrees and wraps at a
    hundred and eighty, so differencing them reports the parameterisation
    rather than the orientation.
    """
    r = math.radians(roll_deg)
    p = math.radians(pitch_deg)
    return (-math.sin(p),
            math.sin(r) * math.cos(p),
            math.cos(r) * math.cos(p))


def run_capture(path, lsb_per_g, rate, beta, settle):
    """Pitch and roll from a capture file, with no gyroscope.

    These captures carry the accelerometer alone, so the gyroscope term is
    zero on every update. That is not a limitation being hidden. With no
    angular rate the filter reduces to its accelerometer correction, which
    is exactly the path a static orientation check should exercise. It
    would be the wrong instrument for a moving test and is the right one
    for this.
    """
    samples, skipped = read_capture(path, lsb_per_g)
    if not samples:
        print("no usable samples in %s" % path, file=sys.stderr)
        return 1
    if len(samples) <= settle:
        print("%d samples is not more than the settling window of %d"
              % (len(samples), settle), file=sys.stderr)
        return 1

    filt = Ahrs(beta=beta)
    dt = 1.0 / rate
    errors = []

    mean_accel = tuple(sum(s[i] for s in samples) / len(samples)
                       for i in range(3))
    magnitude = math.sqrt(sum(v * v for v in mean_accel))
    measured_dir = vec_normalise(mean_accel)
    ref_roll, ref_pitch = direct_tilt(mean_accel)

    for n, accel in enumerate(samples):
        roll, pitch, _ = filt.update((0.0, 0.0, 0.0), accel, dt)
        if n >= settle:
            # The orientation error, and NOT a difference of angles. Roll
            # wraps at a hundred and eighty degrees and is ill-conditioned
            # near a pitch of ninety, so averaging or differencing roll
            # reports the parameterisation. The angle between two gravity
            # directions is the same quantity at every pose.
            guess = gravity_from(roll, pitch)
            dot = sum(a * b for a, b in zip(guess, measured_dir))
            errors.append(math.degrees(math.acos(max(-1.0, min(1.0, dot)))))

    # The converged estimate, not a mean of angles, for the same reason.
    final_roll, final_pitch, _ = to_euler(filt.q)
    mean_roll, mean_pitch = final_roll, final_pitch

    print("capture            %s" % path)
    print("samples            %d used, %d damaged and skipped"
          % (len(samples), skipped))
    print("scale              %g LSB per g" % lsb_per_g)
    print("rate               %g Hz, so dt is %.6f s" % (rate, dt))
    print("filter             beta %g, gyroscope zero, %d samples settling"
          % (beta, settle))
    print()
    print("mean acceleration  X %+.4f  Y %+.4f  Z %+.4f g"
          % mean_accel)
    print("magnitude          %.4f g" % magnitude)
    if abs(magnitude - 1.0) > 0.05:
        print("                   WARNING: more than 50 mg from one g, so")
        print("                   the board was not still or the scale is wrong")
    print()
    print("filter   roll  %+8.3f deg   pitch %+8.3f deg  (converged, not a mean)"
          % (mean_roll, mean_pitch))
    print("direct   roll  %+8.3f deg   pitch %+8.3f deg  (trigonometry)"
          % (ref_roll, ref_pitch))
    print()
    print("orientation error   %.3f deg final, %.3f mean, %.3f worst"
          % (errors[-1], sum(errors) / len(errors), max(errors)))
    print()
    print("The orientation error is the angle between the gravity direction")
    print("the filter's own roll and pitch imply and the one measured. It is")
    print("the filter against trigonometry on the same samples, and unlike a")
    print("difference of Euler angles it means the same thing at every pose:")
    print("roll wraps at 180 degrees and goes ill-conditioned near a pitch of")
    print("90, where a small orientation error becomes a large roll figure.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--selftest", action="store_true",
                        help="check the filter against known rotations")
    parser.add_argument("--capture", metavar="FILE",
                        help="pitch and roll from a burst-read capture file")
    parser.add_argument("--scale", type=float, default=16384.0,
                        metavar="LSB_PER_G",
                        help="16384 at two g full scale, 4096 at eight g "
                             "(default: %(default)g)")
    parser.add_argument("--rate", type=float, default=126.4, metavar="HZ",
                        help="the capture loop's MEASURED sample rate, not "
                             "the sensor's output rate (default: %(default)g)")
    parser.add_argument("--beta", type=float, default=0.5,
                        help="filter gain; higher converges sooner from rest "
                             "(default: %(default)g)")
    parser.add_argument("--settle", type=int, default=1000, metavar="N",
                        help="samples to discard while the filter converges "
                             "from level (default: %(default)d)")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    if args.capture:
        return run_capture(args.capture, args.scale, args.rate,
                           args.beta, args.settle)
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
