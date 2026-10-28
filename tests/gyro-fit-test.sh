#!/bin/sh
#
# gyro-fit-test.sh - scripts/gyro-fit.py recovers a scale factor it was
# never told, and refuses the captures that cannot produce one.
#
# The program it exercises integrates a gyroscope across a there-and-back
# rotation between two static poses and compares the result against the
# angle the calibrated accelerometer measures between those poses. There
# is no standing reference for rotation rate on this bench, so the
# reference is built: see projects/10-iio-iks4a1/docs/gyro-method.md,
# which was written before any sample was taken.
#
# WHY A SYNTHETIC CAPTURE.
#
# Same reason as accel-fit-test.sh. The scale error and the bias are
# CHOSEN here, a capture is generated from them, and the question is
# whether the program finds numbers it was never given. Real bench data
# is the thing being measured and so cannot also be the answer.
#
# AND WHY THE TOLERANCE IS AS TIGHT AS IT IS.
#
# These fixtures are noiseless, so nothing stands between the program and
# exact recovery except its own arithmetic. The assertions below match a
# scale error printed to four decimal places, which is about half a part
# per million of the angle. That is deliberately far tighter than the
# 0.30 mg noise floor of the instrument, because a comfortable bound on a
# generated fixture is how a systematic error survives: accel-fit.py
# shipped a sign error that a 20 LSB tolerance accepted happily.
#
# The defect that caused this file to exist is assertion 16. The first
# version of gyro-fit.py integrated exactly the samples above its still
# threshold, which cut the gradual start and end off every rotation. A
# fixture built from a known 1.5000 per cent error came back as 1.3262.
# Truncation is one-sided and always reads low.
#
#   sh tests/gyro-fit-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIT=$ROOT/scripts/gyro-fit.py
POSES=$ROOT/projects/10-iio-iks4a1/docs/evidence/accel-poses-2026-10-26.csv

. "$ROOT/tests/lib/python.sh"
bench_python "scripts/gyro-fit.py went unchecked"

pass=0
fail=0

say() {
	if [ "$1" = yes ]; then
		pass=$((pass + 1))
		printf 'ok   %s\n' "$2"
	else
		fail=$((fail + 1))
		printf 'FAIL %s\n' "$2"
	fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

out=$TMP/out
status=0

run() { # args...
	status=0
	"$PYTHON" "$FIT" "$@" >"$out" 2>&1 || status=$?
}

said() { # description pattern
	if grep -q "$2" "$out"; then say yes "$1"; else say no "$1"; fi
}

refused() { # description pattern
	if [ "$status" -ne 0 ] && grep -q "$2" "$out"; then
		say yes "$1"
	else
		say no "$1 (exit $status)"
	fi
}

# ---------------------------------------------------------- the generator
#
# One capture is still, rotate, still, rotate back, still. Every quantity
# the program is meant to discover is set here by name.
#
# The rotation angle defaults to the reference angle the program itself
# computes between the two named poses, because the fixture has to rotate
# by the angle the reference claims or the comparison is against the wrong
# truth. That angle is separately asserted to be near a quarter turn,
# which is an independent check needing nothing transcribed.

cat >"$TMP/gen.py" <<'GENEOF'
import importlib.util
import math
import os
import random
import sys

root = os.environ["ROOT"]
spec = importlib.util.spec_from_file_location(
    "gf", os.path.join(root, "scripts", "gyro-fit.py"))
gf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gf)

out = sys.argv[1]
opt = dict(kv.split("=", 1) for kv in sys.argv[2:])


def num(key, default):
    return float(opt.get(key, default))


def flag(key, default):
    return int(opt.get(key, default))


poses = os.path.join(root, "projects", "10-iio-iks4a1", "docs", "evidence",
                     "accel-poses-2026-10-26.csv")
if opt.get("angle", "ref") == "ref":
    angle, _, _ = gf.reference_angle(poses, "flat-up", "long-edge-a",
                                     gf.load_accel_fit())
else:
    angle = num("angle", 90.0)

hz = num("hz", 960.0)
err = num("e", 0.015)
bx, by, bz = num("bx", 0.8), num("by", -0.35), num("bz", 0.12)
dur = num("dur", 0.6)
rest = num("still", 3.0)
drift = num("drift", 0.0)
noise = num("noise", 0.0)
wobble = num("wobble", 0.0)
profile = opt.get("profile", "cos")
moves = flag("moves", 2)
lead = flag("lead", 1)
sign2 = flag("sign2", -1)
# Nonzero writes raw counts instead of rad/s, which is what iio-decode
# produces for this device: st_lsm6dsx publishes one shared
# in_anglvel_scale and the decoder wants a per-axis in_anglvel_x_scale,
# so it falls through to counts and the CSV looks identical either way.
rawscale = num("rawscale", 0.0)
# Multiplies every timestamp, modelling the driver defect measured
# on this part: a constant 1.1551 too long, identical at 480 and
# 240 Hz. A constant error in dt is the same error in every angle.
stretch = num("stretch", 1.0)

random.seed(flag("seed", 7))
rows = []
dt = 1.0 / hz
clock = [0.0]


def push(wx, wy, wz):
    rows.append((clock[0], wx, wy, wz))
    clock[0] += dt


def still(span):
    for _ in range(int(span * hz)):
        push(0.0, 0.0, 0.0)


def shape(frac):
    if profile == "tri":
        return 4.0 * frac if frac < 0.5 else 4.0 * (1.0 - frac)
    return 1.0 - math.cos(2.0 * math.pi * frac)


def move(sign):
    total = angle * (1.0 + err)
    count = int(dur * hz)
    norm = sum(shape((i + 0.5) / count) for i in range(count)) * dt
    for i in range(count):
        frac = (i + 0.5) / count
        push(sign * total * shape(frac) * dt / norm / dt,
             wobble * math.sin(math.pi * frac), 0.0)


if lead:
    still(rest)
if moves > 0:
    move(flag("dir", 1))
if moves > 1:
    still(rest)
    move(sign2)
still(rest)

span = clock[0] if clock[0] else 1.0
rad = math.pi / 180.0
header = ["anglvel_x", "anglvel_y", "anglvel_z", "timestamp"]
if opt.get("drop") == "z":
    header = ["anglvel_x", "anglvel_y", "timestamp"]

with open(out, "w") as handle:
    handle.write(",".join(header) + "\n")
    for index, (when, wx, wy, wz) in enumerate(rows):
        slide = drift * (when / span)
        values = [wx + bx + slide, wy + by, wz + bz]
        if noise:
            values = [v + random.gauss(0.0, noise) for v in values]
        stamp = int(when * stretch * 1e9)
        if flag("backwards", 0) and index == len(rows) // 2:
            stamp = int((when - 1.0) * 1e9)
        if rawscale:
            cells = ["%.0f" % (v * rad / rawscale) for v in values]
        else:
            cells = ["%.9f" % (v * rad) for v in values]
        if opt.get("drop") == "z":
            cells = cells[:2]
        handle.write(",".join(cells + ["%d" % stamp]) + "\n")

print("fixture %s: e=%+.4f%% bias_x=%+.3f angle=%.6f duration=%.6f"
      % (os.path.basename(out), 100.0 * err, bx, angle,
         (len(rows) - 1) * dt))
GENEOF

export ROOT

gen() { # name key=value...
	name=$1
	shift
	"$PYTHON" "$TMP/gen.py" "$TMP/$name.csv" "$@" >"$TMP/gen.log" 2>&1 \
		|| { printf 'generator failed for %s\n' "$name"; cat "$TMP/gen.log"; exit 1; }
	DUR=$(sed -n 's/.*duration=//p' "$TMP/gen.log")
}

# ------------------------------------------------- the recovery, exactly

gen base
run "$TMP/base.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
say "$([ "$status" -eq 0 ] && echo yes || echo no)" \
	"a clean there-and-back capture produces a result"
said "recovers the chosen 1.5000 per cent scale error" \
	'reads +1.5000 per cent'
said "recovers the chosen 0.800 degrees/s bias" \
	'before +0.80000, after +0.80000'
said "both bias routes agree, which is the check that can fail" \
	'they differ by  *0\.00000'
said "reports the correction to apply" 'correction of 0.985222'
said "names the window it actually integrated" 'integrated over'
said "reports the endpoint rates against the edge threshold" 'endpoints '
said "estimates the trapezoid error by decimation" 'rate check'

# The reference angle is nominally a quarter turn: flat-up has gravity
# along +Z and long-edge-a has it along -Y. Checked without transcribing
# any calibration number, so this cannot go stale with a recalibration.
said "the reference angle is near a quarter turn" 'reference 90\.0'

# ------------------------- the assertion above can fail, which it must
#
# A different chosen error has to produce a different answer, or the
# first assertion is matching something that does not depend on the data.

gen other e=0.03
run "$TMP/other.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
said "a fixture built from 3.0000 per cent reads 3.0000, not 1.5000" \
	'reads +3.0000 per cent'

# ----------------------------------------------- the truncation defect
#
# The one that caused this file. A long, gentle rotation spends many
# samples below any usable still threshold at each end, so a program that
# integrates only the above-threshold run loses that area and reads low.

gen long dur=1.5
run "$TMP/long.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
said "a long gentle rotation still recovers 1.4998, not 1.3 something" \
	'reads +1\.499[0-9] per cent\|reads +1\.500[0-9] per cent'

# ------------------------------------------------------------- the noise
#
# Noise should widen the result, not move it. Half a degree per second of
# it, which is of the order of the real part, must not shift the answer
# by more than a hundredth of a per cent.

gen noisy noise=0.5
run "$TMP/noisy.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
# Half a degree per second of noise integrates to about 0.014 degrees
# over one window, which is 0.015 per cent of the angle, and the bias
# estimate carries a little more. So a few sigma is 0.05 per cent, and
# that is the bound: wide enough not to be a lottery, narrow enough that
# a systematic shift could not hide inside it. The fixture is seeded, so
# the figure is deterministic rather than merely probable.
said "noise widens but does not move the recovered scale factor" \
	'reads +1\.4[5-9][0-9][0-9] per cent\|reads +1\.5[0-4][0-9][0-9] per cent'

# ------------------------------------------------------- the wobble bound
#
# An off-axis excursion is the confound that can ruin this measurement,
# and the program reports it as a number rather than assuming it away.

gen wobbly wobble=20
run "$TMP/wobbly.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
said "an injected off-axis excursion is reported, not swallowed" \
	'worst sum [1-9]'

# ------------------------------------------------------------- the refusals
#
# Each of these produces an ordinary-looking number from a naive
# integration, which is why they are refusals in the program and not
# cautions in a document.

gen single moves=1
run "$TMP/single.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
refused "refuses a single rotation, which cannot separate scale from bias" \
	'not 2'

gen nolead lead=0
run "$TMP/nolead.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
refused "refuses a capture with no still interval at one end" \
	'still runs, not 3'

run "$TMP/base.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 200 --trust-timestamps
refused "refuses when a sample is within 90 per cent of full scale" \
	'may be clipped'

gen samesign sign2=1
run "$TMP/samesign.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
refused "refuses two rotations the same way round" 'same sign'

gen dropped drop=z
run "$TMP/dropped.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
refused "refuses a capture missing an anglvel channel" 'has no column for'

gen reversed backwards=1
run "$TMP/reversed.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
refused "refuses timestamps that do not increase" 'does not increase'

run "$TMP/base.csv" --axis x --poses "$POSES" --from flat-up \
	--to no-such-pose --full-scale 1000 --trust-timestamps
refused "refuses a pose label that is not in the CSV" 'no pose labelled'

run "$TMP/base.csv" --poses "$POSES" --from flat-up --to long-edge-a
refused "refuses without an axis, since one must be named" \
	'must be x, y or z'

run "$TMP/base.csv" --axis x
refused "refuses without a reference angle" 'needs a reference angle'

head -6 "$POSES" >"$TMP/five.csv"
run "$TMP/base.csv" --axis x --poses "$TMP/five.csv" --from flat-up \
	--to long-edge-a --trust-timestamps
refused "refuses a pose CSV too small to calibrate the reference" \
	'needs at least six'

# A slow rotation with a drifting bias: the bias term is drift divided by
# mean rate, so this is the regime the method document says to avoid.
gen slow dur=12 drift=0.6
run "$TMP/slow.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
refused "refuses a slow rotation whose answer would be mostly bias" \
	'report bias and not scale'

# PROVING THIS GUARD CAN FIRE NEEDED A DIFFERENT FIXTURE FROM THE
# OTHERS, and the first attempt did not. A raised cosine integrated over
# a whole period is almost exact under the trapezoid rule at any usable
# sample rate, so a cosine at 30 Hz passed cleanly and the guard looked
# like one of the rules this repository has shipped that never fire. A
# triangle has a kink, where the trapezoid error is real and falls as dt
# squared, so what actually breaks it is a brisk triangular flick: a
# quarter turn in a quarter second, sampled fifteen times.
gen coarse hz=60 dur=0.25 profile=tri
run "$TMP/coarse.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 2000 --trust-timestamps
refused "refuses a rate too low to resolve the motion" \
	'did not resolve this motion'

# --------------------------------------------------------- the gaps
#
# A CAPTURE IS NOT NECESSARILY CONTIGUOUS. The first still capture taken
# on the bench, on Monday 26 October 2026, held 512 stale scans from a
# buffer that had been armed and left, then a 161 second gap, then the
# live stream. A gap inside a rotation is lost angle: trapezoidal
# integration draws a straight line through the part of the motion
# carrying the most rate, and nothing recovers it.

"$PYTHON" - "$TMP/base.csv" "$TMP/gappy.csv" <<'GAPEOF'
import sys
lines = open(sys.argv[1]).read().splitlines()
head, rows = lines[0], lines[1:]
# Push everything from the middle of the first rotation onwards forward
# by 90 seconds, which puts one gap inside an integration window. The
# index matters: the default fixture is 3 s of still at 960 Hz, so 2880
# samples, then 576 of rotation. A gap at a quarter of the file lands in
# the still interval instead, where it is harmless and the guard is
# right not to fire, which is how this fixture was wrong first.
out = [head]
for index, row in enumerate(rows):
    cells = row.split(",")
    if index > 3100:
        cells[-1] = str(int(cells[-1]) + 90 * 10 ** 9)
    out.append(",".join(cells))
open(sys.argv[2], "w").write("\n".join(out) + "\n")
GAPEOF
run "$TMP/gappy.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
refused "refuses a gap inside an integration window, which is lost angle" \
	'lost angle'

# ------------------------------------------------------------ the units
#
# THE TWO CAPTURE TOOLS IN THIS TREE DISAGREE ABOUT UNITS AND NEITHER
# HEADER SAYS SO. iio-stream applies the channel scale, so its columns
# are rad/s. iio-decode looks for a per-axis in_anglvel_x_scale, which
# st_lsm6dsx does not publish, so it prints raw counts. Confusing them is
# a factor of about sixteen thousand, in either direction, and the CSV
# looks the same both ways. Guarded rather than documented.

gen rawcap rawscale=0.000610865
run "$TMP/rawcap.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
refused "refuses raw counts read as rad/s, 16000 times too large" \
	'almost certainly raw'

run "$TMP/rawcap.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --scale 0.000610865 --trust-timestamps
said "the same raw capture recovers 1.5000 once --scale is given" \
	'reads +1\.49[0-9][0-9] per cent\|reads +1\.50[0-9][0-9] per cent'

run "$TMP/base.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --scale 0.000610865 --trust-timestamps
refused "refuses rad/s scaled a second time, 16000 times too small" \
	'not a rotation'

# ------------------------------------------------ endpoints as triples
#
# A gyroscope endpoint has to hold still for a whole still interval, and
# a board balanced on an edge on this bench does not: one drifted 7.03
# degrees in eight seconds while every reading passed the magnitude
# test, because a slow settle keeps |a| equal to g. So an endpoint is
# usually a propped pose that no label names, measured at the time.
#
# flat-up's own triple, passed as numbers, must give the same answer the
# label gives. That is the check: the two routes agree.

run "$TMP/base.csv" --axis x --poses "$POSES" \
	--from -75.92,148.88,16505.32 --to long-edge-a \
	--full-scale 1000 --trust-timestamps
said "an endpoint given as a raw triple matches the label it came from" \
	'reference 90\.0373'
said "and recovers the same scale error" 'reads +1\.5000 per cent'

run "$TMP/base.csv" --axis x --poses "$POSES" \
	--from 0,0,8000 --to long-edge-a \
	--full-scale 1000 --trust-timestamps
refused "refuses an endpoint triple whose magnitude is not g" \
	'it was moving'

run "$TMP/base.csv" --axis x --poses "$POSES" \
	--from 1,2 --to long-edge-a \
	--full-scale 1000 --trust-timestamps
refused "refuses a triple that is not three numbers" \
	'needs exactly three'

# ------------------------------------------------------- the time base
#
# THE DRIVER'S TIMESTAMPS ARE NOT REAL TIME ON THIS PART. Measured on
# Monday 26 October 2026: a read that finished at 1793045616 returned a
# last sample stamped 1793045626.094, ten seconds into the future, which
# no real clock can do. The error is a constant 1.1551, identical at a
# nominal 480 and 240 Hz, where the interval came out exactly double.
#
# It is the worst kind of error for this method. A constant factor in dt
# is the same factor in every angle, and it is NOT separable from the
# gyroscope's own gain: what comes out is the product of the two. So the
# fixture below carries 1.5 per cent of real gain and 1.1551 of fake
# time, and 1.015 x 1.1551 is 1.1724.

gen stretched stretch=1.1551
STRETCHED_DUR=$DUR

run "$TMP/stretched.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --trust-timestamps
said "trusting stretched timestamps reads 17.24 per cent, not 1.50" \
	'reads +17\.2[0-9][0-9][0-9] per cent'

run "$TMP/stretched.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --duration "$STRETCHED_DUR"
said "a measured duration undoes the stretch exactly" \
	'reads +1\.5000 per cent'
said "and says what stretch it found" 'stretch of 1\.1551'

run "$TMP/stretched.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000
refused "refuses to integrate with no time base chosen either way" \
	'needs a time base'

run "$TMP/gappy.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --duration 10.2
refused "refuses to spread samples evenly over a capture with a gap" \
	'not evenly'

# ----------------------------------------------------- the one-way pair
#
# WHY THIS MODE EXISTS. The endpoint pose has to be measured in the
# capture's own hold, and a there-and-back capture ends where it started,
# so the endpoint can only be read by putting the board back afterwards.
# On Monday 26 October 2026 that re-placement was measured: two
# placements on the same tilted support, each internally stable to 0.008
# degrees, were 13.49 degrees apart. On a 58 degree rotation that is 23
# per cent, against a reference worth 0.05.
#
# A one-way capture ends ON the support, so the reading taken straight
# after is that capture's own endpoint with nothing moved. Two of them
# give the reversal, and because each carries its own bias from its own
# still intervals, the pair stops being the mechanism for removing bias
# and becomes a check that can fail instead.

gen oneup moves=1
UPDUR=$DUR
gen onedown moves=1 dir=-1
DNDUR=$DUR

run "$TMP/oneup.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --duration "$UPDUR" \
	--second "$TMP/onedown.csv" --second-duration "$DNDUR"
said "a one-way pair recovers 1.5000 with no re-placement anywhere" \
	'reads +1\.5000 per cent'
said "and says how well the two legs agree as SCALE FACTORS, since" 'the two scale factors differ by'
said "and names each leg's own bias" 'before  *+0\.80000'

run "$TMP/oneup.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --duration "$UPDUR" \
	--second "$TMP/oneup.csv" --second-duration "$UPDUR"
refused "refuses two legs that turn the same way" 'same sign'

run "$TMP/base.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --duration 10.2 \
	--second "$TMP/onedown.csv" --second-duration "$DNDUR"
refused "refuses a there-and-back capture used as a one-way leg" 'not 1'

gen onedownbad moves=1 dir=-1 e=0.05
BADDUR=$DUR
run "$TMP/oneup.csv" --axis x --poses "$POSES" --from flat-up \
	--to long-edge-a --full-scale 1000 --duration "$UPDUR" \
	--second "$TMP/onedownbad.csv" --second-duration "$BADDUR"
refused "refuses legs that disagree by more than their bias drift allows" \
	'more than the'

# ----------------------------------------------------- the bias mode
#
# A still capture needs no reference at all, which is the one gyroscope
# parameter that does not.

gen stillonly moves=1 lead=0 dur=0.001 still=6
run "$TMP/stillonly.csv" --bias
said "a still capture reports the zero-rate offset" 'zero-rate offset'
said "and compares it against the rotation of the Earth" \
	'Earth rotates at 0\.0041781'
said "and reports an Allan deviation, which needs no reference" \
	'Allan deviation'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
