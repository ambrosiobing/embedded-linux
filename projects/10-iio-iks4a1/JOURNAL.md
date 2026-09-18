# Project 10: journal

In order, including the things that were wrong first.

## 1. The headline comparison this project must not make

**What happened.** Before writing any code, the three paths out of a sensor
were written down side by side in `docs/DESIGN.md`, and one of them does
not measure what it appears to.

The project compares sysfs polling, a hrtimer trigger, and the IMU's
hardware FIFO. The tempting headline is "the FIFO path has better timestamp
regularity". It would be a real number, it would be dramatic, and it would
be meaningless.

**Why.** In the hrtimer path the timestamp is taken by the IIO core when
the scan is pushed, so its jitter is genuinely kernel latency: hrtimer
wake-up plus the I2C transaction plus whatever delayed either.

In the FIFO path the sensor timestamps nothing. The driver gets one
interrupt at the watermark, drains N samples in a burst, and **assigns**
timestamps by interpolating backwards from the interrupt time using the
configured output data rate. The intervals are therefore close to exactly
`1 / ODR` by construction. Their standard deviation measures the driver's
arithmetic and the stability of the sensor's oscillator. It says nothing
about the kernel.

Put the two in one column and the FIFO path wins by a wide margin, for the
same reason a clock that reports the time it was set to always agrees with
itself.

**What was done.** The design document names the three comparisons that are
sound: interrupt rate and CPU load across all three paths, timestamp
regularity *within* the hrtimer path against the rate it was asked for, and
sample count over a fixed interval against the configured rate. The FIFO
timestamp spread is still recorded, labelled as a property of the
reconstruction.

**Why that and not the alternative.** The alternative is to print the
column and let the reader decide. That is not neutrality: it is the most
quotable number in the project and the least meaningful, and an unlabelled
figure in a portfolio is a claim.

This is Project 8's mistake, found before rather than after. That project
stated in five documents that the difference between its two instruments
was the cost of a GPIO write, until the algebra showed a constant cost
cancels in an interval measurement. Same shape: a quantity that looks like
a measurement of the system and is really a measurement of how the number
was produced.

## 2. A silent exit that deleted exactly the honest rows

**What happened.** `iio-probe` builds the sensor inventory, which is an
acceptance criterion: the specification asks for an honest list of which
sensors of the shield work with which driver. Run against a fake bus, it
printed four rows of six and stopped, with no error and exit status 0.

```
0x6a    LSM6DSV16X   st_lsm6dsx   iio      present   missing    -
0x1e    LIS2MDL      st_magn      iio      present   missing    -
0x5d    LPS22DF      st_pressure  iio      present   missing    -
0x44    SHT40        sht4x        hwmon    present   missing    -
```

The two missing rows were the STTS22H and the LIS2DUXS12: the only parts
with `driver=none`, and the only two the inventory exists to be honest
about.

**What was wrong.** One line:

```sh
[ "$_mod" = none ] && return 1
```

Under `set -e`, a false test at the end of an and-list ends the script. The
non-zero return travelled out through a command substitution and killed the
subshell running the loop. Every part before the first `none` printed;
nothing after it did.

**Why it matters more than an ordinary crash.** The output was not
truncated in a visible way. There was no error, no partial line, and the
exit status was 0. What remained was a complete-looking inventory in which
every sensor had a driver. The failure did not break the table; it deleted
the parts that would have made it honest.

**What was done.** `module_present` now always echoes and always returns 0.
The test asserts that all six parts produce a row, which is the regression,
and separately that the program exits 0.

**Why that and not `set +e`.** Because the surrounding `set -e` is what
catches the next mistake. The fix is to stop writing `A && B` as a
statement, which `rt-run` carries a comment about, in this same repository,
for this same reason. Reading that comment is not the same as having met
it.

## 3. The test found a bug in my model of sysfs, not in my code

**What happened.** With `iio-probe` printing all six rows, the test suite
still failed three assertions: a chip that the fixture said was bound came
back as `not-bound` with no devices.

The function looked the driver up like this:

```sh
_link=$(readlink -f "$d/../driver")
```

where `$d` was `/sys/bus/iio/devices/iio:device0`. So `$d/..` is
`/sys/bus/iio/devices`, and that directory has no `driver` link. In sysfs
the driver link belongs to the **i2c client**, not to the bus directory.

**The aha.** The first instinct was that the fixture was unrealistic. It
was, but the script was wrong in the same place, and the fixture was
unrealistic in a way that hid it: I had built the fixture from the same
wrong mental model as the code, so the two agreed with each other.

**What was done.** Everything is now keyed on the I2C address, through a
path, with no `readlink` anywhere:

```
/sys/bus/i2c/devices/1-006a/driver          bound?
/sys/bus/i2c/devices/1-006a/iio:device0/name what it registered
/sys/bus/i2c/devices/1-006a/hwmon/hwmon0/name  ... if it is a hwmon driver
```

**Why that is better and not just different.** Three reasons, and the
third was not the goal.

Paths traverse symlinks transparently, so the same expression works on a
real board where the middle component is a link and in a fixture where it
is an ordinary directory. This host's shell turns `ln -s` into a copy, so a
symlink-based fixture could not have been run here at all.

It asks a better question. Not "which devices did this module create" but
"did anything bind to the part at this address, and what did it produce",
which is what the table is organised around.

And it separated a verdict that had been hiding: a driver that binds and
registers nothing is now `bound-no-device`, which points at a probe failure
in `dmesg`, rather than being lumped in with `not-bound`, which points at
the overlay.

## 4. My own test died the way I had written up an hour earlier

**What happened.** Following the rule from `walkthrough/DECISIONS.md`, the
defect from entry 2 was reintroduced to check the suite caught it. The
suite exited 1, correctly.

It also printed **nothing at all**. An empty log.

**Why.** `run()` was `sh "$SUT" "$@" 2>&1`. With a crashing program under
test, the first assertion's command substitution fails, `set -e` ends the
test script, and no assertion is ever reported. CI shows FAIL from the exit
status, and a developer sees a blank screen.

**What was done.** `run()` ends in `|| true`, so a crash surfaces as the
content assertions failing by name, and a separate `run_status` asserts the
exit code so a crash is still reported as a crash. With the defect
reintroduced it now says:

```
FAILED   the inventory runs to completion
FAILED   STTS22H has a row: 'STTS22H' not in output
FAILED   LIS2DUXS12 has a row: 'LIS2DUXS12' not in output
```

which is the diagnosis rather than the symptom.

**Why this entry exists.** Project 8's journal entry 44, written earlier the
same day, is about a test whose failure branch was "some other error
occurred" and which therefore reported a new refusal as a pass. This is the
same family: a test that cannot distinguish "the program is wrong" from
"the program is gone". Writing that up did not prevent writing it again an
hour later, which is worth knowing about how much a journal entry actually
protects.

## 5. Two bugs in the C client that no test here can reach

**What happened.** `iio-stream.c` is the libiio client, and there is no
compiler and no `iio.h` on the authoring machine, so it cannot be compiled
until the build runs. Reading it back rather than trusting it found two
defects, one of which would have produced plausible wrong numbers forever.

**The first is ordinary.** `getopt`, `optarg` and `optind` need
`<unistd.h>`, which was missing. That fails at compile time, which is the
right place, and it would have cost one build cycle.

**The second is the interesting one.**

```c
int64_t value = 0;
iio_channel_convert(channels[i], &value, base[i] + advance);
```

`iio_channel_convert()` writes exactly the channel's storage width: two
bytes for an `s16`, four for an `s32`. Handing it an `int64_t` and reading
the whole variable back leaves six bytes of whatever was on the stack.

That does not crash. It does not warn. Most of the time the stack slot
happens to hold zeros and the value is right, and occasionally it does not
and the accelerometer reports a number in the billions for one sample. A
fault that is usually invisible and rarely spectacular is worse than one
that is always wrong, because the rare case gets explained away as a
glitch in the sensor.

**What was done.** A `widen()` helper converts into a scratch of the
channel's own width and widens deliberately, consulting `is_signed` rather
than assuming it. It is fifteen lines to say what the one-liner was
pretending.

**Why this entry exists.** The same file's own header explains at length
why it contains no hard-coded byte offsets, and then hard-coded a width.
Getting the interesting half of a problem right is not the same as getting
the problem right, and the boring half is where this one was.

## 6. The recipe was invisible to a safety check because of a plus sign

**What happened.** `bench-iio-image.bb` was written with

```
IMAGE_INSTALL += "\
```

The sibling images use `IMAGE_INSTALL:append = " \`. Both work in
BitBake, so this looked like a style difference.

It is not. `scripts/lint.py` has `check_image_packages`, which exists
because Project 1 lost a round to a wireless driver described in three
paragraphs of comments and named in no image at all. It finds what an
image installs with this regex:

```python
re.findall(r'IMAGE_INSTALL:append\s*=\s*"([^"]*)"', body)
```

So with `+=`, the new image contributed **nothing** to the set of installed
packages, and any `kernel-module-*` it named in a comment would have been
compared against a list its own nine module lines were absent from.

**What was done.** Switched to `:append`, then broke it on purpose:
appended a comment naming `kernel-module-nonesuch-test` and watched the
rule fire, then removed it and watched it go quiet.

**The wider finding, which is not about syntax.** A check that recognises
one spelling of a thing silently does not cover the others. This one has
been in the repository for months, it is correct about every recipe that
happens to use the spelling it knows, and a new file written in a different
valid style would have been exempt from it without anyone choosing that.

It is the same shape as everything else found this week: the rule reported
success about a file it had not really looked at. The difference is that
here the tool was right and the input selection was wrong, which is the
harder version to notice, because nothing is broken until somebody writes
the file that slips through.

**Why the rule was not widened to match `+=` as well.** It should be, and
that is a change to a shared check used by seven images, which belongs in
its own commit with its own break-test rather than buried in a new
project's recipe. Recorded here so it is not lost.

## 7. Checking that python exists is not checking that python runs

**What happened.** `tests/iio-decode-test.sh` needs an interpreter, so it
began with the obvious guard:

```sh
command -v python3 >/dev/null 2>&1 || { echo skip; exit 0; }
```

On this laptop that succeeds. Windows ships a `python3` stub in
`WindowsApps` which is a real file, is on `PATH`, satisfies `command -v`,
and when run prints a German advertisement for the Microsoft Store and
exits non-zero.

So the suite did not skip. It ran, and every assertion failed with that
advertisement quoted back as the diff.

**What was done.** The guard now tries each candidate by running it:

```sh
if "$candidate" -c 'import struct, sys' >/dev/null 2>&1; then
```

and falls back from `python3` to `python`, which is what this host actually
has. The skip message says "a python3 that only exists is not a python3".

**Why it is worth an entry.** It is the same distinction the whole project
is built around, in one line of shell. `iio-probe` exists because a sensor
that answers on the bus is not a sensor with a driver, and a driver that is
configured is not a driver that is installed. The test guard asked whether
a file was present when the question was whether a program worked.

Project 8's journal has the same lesson from the other end, where a module
was configured, compiled, deployed and absent from the rootfs. Existence
and capability are different facts, and almost every cheap check tests the
first one.

## 8. The filter was right and my physics was inverted

**What happened.** `ahrs.py` has a `--selftest` that checks the orientation
filter against rotations whose answer comes from geometry rather than from
another program. First run:

```
ok       level roll: +0.00
ok       level pitch: +0.00
FAILED   rolled 90 about x: -89.94, want +90.00
FAILED   pitched 90 about y: -89.94, want +90.00
ok       gyro integrates in the right direction: +90.00
```

Two failures, both off by exactly a sign, and the obvious conclusion was a
sign error in the Madgwick update.

**What it actually was.** The filter was correct. The test expectations
were inverted.

If a sensor is rotated by R relative to the world, a world vector appears
in sensor coordinates as **R transposed** times that vector. For a +90
degree roll about x that turns world up, `(0, 0, 1)`, into `(0, +1, 0)`.
I had fed the filter `(0, -1, 0)`, which is the minus ninety case, and then
asserted +90. It answered -89.94 and was right.

**What made it visible, and this is the part worth keeping.** The
gyroscope check passed at the same moment the accelerometer checks failed.
Both measure the same angle by completely different routes: one integrates
a rate, the other reads a direction. When two independent paths to one
quantity disagree, one of them is wrong and you have to look. When there is
only one path, a mirrored filter tracks smoothly, responds correctly to
movement, and agrees with itself forever.

That is also why these checks are rotations rather than recorded output. A
reference file captured from the same broken filter would have passed every
time.

**What was done.** The expectations corrected, with the transpose written
into the comment so the next reader does not have to rederive it, and a
`rolled -90 about x` case added so both signs are pinned rather than one.

**And the thing that was avoided.** The specification asks for Madgwick's
MARG filter, which folds the magnetometer into the same gradient through a
six-row Jacobian. That is precisely where published implementations differ
from each other in sign and in frame handedness, and a wrong sign there
gives an orientation that is mirrored rather than obviously broken.

So yaw comes from a tilt-compensated magnetic heading instead: rotate the
field into the horizontal plane with the attitude the filter already has,
and take the arctangent. Four lines, derivable on paper, and every step
checkable against a known rotation. The header says this is a substitution
and why, because a filter that silently differs from the one it is named
after is worse than one that says so.

## 9. The acceptance table pointed at a folder that did not exist

**What happened.** A review across the repository found this project citing
evidence by path without the path existing. There was no `docs/evidence/`
here at all, and the sensor inventory and the three-paths table are both
committed with empty measurement columns, which is correct and which left
a reader nowhere to look for what would fill them.

**What was done.** `docs/evidence/README.md` added, in the shape Project 1
uses: one row per criterion, the command that produces it, and the header
that says the folder is empty until the board has run. It also records the
one thing no criterion asks for, which Arduino pin carries INT1, because
`DESIGN.md` states plainly that it is not known from the drawing and the
first session with the shield is when that gets settled.

**Why that and not the alternative.** The alternative was to leave the
folder absent until there was something to put in it. An absent folder and
an empty one say different things: absent reads as not thought about, empty
with an index reads as a plan with its captures named. The rows in the
acceptance table stay at "not started", because creating the index proves
nothing about the shield.
