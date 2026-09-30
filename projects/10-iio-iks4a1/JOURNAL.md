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

---

## 10. The INT1 pin has a claimed answer, and a claim is not a measurement

Entry on Wednesday 30 September 2026. First entry written with the shield
wired to a board.

**What happened.** The five jumpers of the wiring table are in: 3V3 to Pi
header pin 1, GND to pin 6, SDA to pin 3, SCL to pin 5, and INT1 to pin 18
which is GPIO24. Four of those are fixed by the Arduino standard and need
no evidence. The fifth is the one `docs/BRINGUP.md` step 0 refuses to
guess, and an answer for it has now arrived.

**The claim.** LSM6DSV16X INT1 is on CN9 pin 6, which is Arduino D5, and
INT2 is on CN9 pin 5, which is D4. The reasoning given is that UM3239 puts
both on the D0 to D7 header rather than on CN5 or CN6.

**What is solid in it, and what is not.**

The header arithmetic is solid and can be checked without the board in
hand. On a Nucleo-144 in the Arduino Uno R3 arrangement, CN9 carries D0 to
D7 and CN5 carries D8 to D15, so counting from the end away from CN5 puts
D5 at CN9 pin 6. That part is a property of the connector standard.

Which shield signal lands on D5 is not solid, because it is a property of
this shield's solder-bridge defaults, which is the exact reason step 0
declines to take it from a table. The claim has the right shape and the
right source, and it still has not been measured on this board.

**What was done.** The pin is recorded here as **claimed, not measured**,
and the acceptance rows that depend on the interrupt stay at "not started"
until continuity is checked between the LSM6DSV16X INT1 pad and CN9 pin 6.
That check is a minute with a multimeter and it converts this entry from a
claim into an observation.

**Why that and not the alternative.** The alternative is to treat the table
as settled and move on. The cost of being wrong is not a failed boot, which
would announce itself. It is an interrupt that never fires, a FIFO
watermark path that silently falls back to nothing, and two thirds of this
project quietly becoming a compile test while looking finished. That is the
failure mode this repository treats as the expensive one, and it is
detectable for the price of one continuity test before it costs an evening.

**What does not depend on it.** The bus scan of step 1 uses SDA and SCL
only. It can be run now, and it decides whether the wiring is right at all,
which is the question worth answering first.

---

## 11. Two wires were sent to one pin, and the board found it

Entry on Wednesday 30 September 2026.

**What happened.** The shield went on, the console cable came out, and pin
6 was already full. The wiring table in `README.md` puts the shield's
ground on Pi header pin 6. Step 0 of `docs/BRINGUP.md` says the USB/TTL
cable sits on pins 8, 10 and 6. One header pin takes one jumper socket, so
the two instructions cannot both be followed.

**What was done.** Step 0 now sends the console ground to **pin 9**. The
40-pin header has eight grounds, at pins 6, 9, 14, 20, 25, 30, 34 and 39,
all the same net, so the choice is mechanical rather than electrical. Pin 9
is the one that sits beside pins 8 and 10, which keeps the three console
leads together.

**Why that and not the alternative.** The alternative is to move the
shield's ground and leave the console where the document had it. That is
worse for two reasons. The shield's four bus wires are a block at pins 1,
3, 5 and 6, and splitting them costs the visual check that the block is
seated correctly. And the console is the wire most often removed and
refitted, so it should be the one that moves.

**What this says about the documents.** Both were right in isolation and
wrong together, which is the failure mode of a pin table that lives in two
files. Neither review caught it because each was read on its own. The
repository already knows this shape: a claim that is true where it is
written and false beside its neighbour. The check that would have caught it
is reading every pin used by one project in one list, which is what the
wiring table is for and what step 0 should have deferred to instead of
restating.

---

## 12. The bus answered, and it corrects three documents

Entry on Wednesday 30 September 2026. **First hardware evidence in this
project.** Until now every claim here was reasoning; this is a reading.

**What happened.** The shield was wired to a Raspberry Pi 3B+ on the four
bus wires, Raspberry Pi OS trixie was written to a card, and `i2cdetect -y
1` was run. Six devices answered. The capture is in
`docs/evidence/i2cdetect-2026-09-30.txt`.

| Address | Part | Status against what was written here |
|---|---|---|
| 0x1e | LIS2MDL | expected, present |
| 0x38 | STTS22H | expected, present |
| 0x44 | SHT40 | expected, present |
| 0x5d | LPS22DF | expected at 5d rather than 5c, and 5d is what answered |
| 0x6a | an LSM6 class part | expected, present |
| 0x6b | a second LSM6 class part | **not described anywhere in this project** |

**Three corrections fall out of it.**

**There is a second inertial measurement unit.** Nothing in this project,
its overlay or its design mentions an address 0x6b. The overlay binds one
IMU at 0x6a and stops. Which two parts these are is the next measurement,
not a guess: the shield's two candidates are named differently in the two
volumes this bench keeps, and their `WHO_AM_I` registers separate them.

**The LIS2DUXS12 did not answer.** Nothing is at 0x18 or 0x19. The
overlay's own comment states that the STTS22H and the LIS2DUXS12 "answer
on the bus and have no node", and half of that sentence is now known to be
false. The STTS22H does answer. The LIS2DUXS12 does not, on this board.

**The pressure sensor address is settled.** `docs/BRINGUP.md` expected
0x5d and the kit volume's map said 0x5c. 5d answered, so the SA0 pin is
high on this shield and the overlay's `lps22df@5d` node is correct as
written.

**What this does not tell us.** Nothing about INT1, which this scan does
not use and which is still a claim rather than a continuity measurement.
Nothing about whether the drivers bind. And nothing about which of the two
LSM6 class parts is at which address.

**Two things about the host that cost time and are worth keeping.**
`dtparam=i2c_arm=on` enables the controller and does not create
`/dev/i2c-1`. The `i2c-dev` module is what creates it, and hand-editing
`config.txt` skips the half that `raspi-config` does silently. And a line
appended to `config.txt` inherits whatever conditional section the file
ended in, so it is read back for the section header above it as much as
for the line itself. Both are now in `docs/CARD.md`.

---

## 13. The two inertial units are the other way round

Entry on Wednesday 30 September 2026, minutes after entry 12.

**What happened.** Register 0x0f is WHO_AM_I across the ST LSM6 family, so
both addresses were asked who they are.

```
i2cget -y 1 0x6a 0x0f   ->  0x22
i2cget -y 1 0x6b 0x0f   ->  0x70
```

0x22 is the LSM6DSO16IS, the part with the in-sensor processing unit. 0x70
is the LSM6DSV16X, the part with sensor fusion. So the shield carries both,
and **the fusion part is at 0x6b while the processing part is at 0x6a.**

**Why that matters more than a label.** `bench-iks4a1-overlay.dts` bound
`st,lsm6dsv16x` at 0x6a. The driver reads WHO_AM_I during probe, so that
node would have found 0x22 where it required 0x70 and refused to bind. The
symptom is the one this project's own bring-up table calls
`bound-no-device`: the part answers `i2cdetect` perfectly, `dmesg` carries
a probe failure that nobody reads unless they suspect one, and the device
never appears under IIO. Every later step, the buffers, the triggers, the
FIFO watermark and the fusion filter, is built on a device that is not
there.

**What was done.** The IMU node moved to 0x6b. The header comment now
carries the measured address map, so the next reader does not have to
rediscover it. The interrupt property stays on that node, which is correct
for a second reason: the claimed INT1 belongs to the LSM6DSV16X, and the
LSM6DSV16X is the node that moved.

**What was deliberately not done.** No node was added for the LSM6DSO16IS
at 0x6a. This overlay's own rule says why: a node naming a compatible the
kernel does not know is created, binds to nothing, and leaves the part
invisible with no message anywhere. Whether `st_lsm6dsx` in the running
kernel lists a matching compatible is a question to answer before writing
the node, not while writing it.

**What this settles beyond this project.** Two volumes on this bench
disagreed about the X-NUCLEO-IKS4A1. One lists a single LSM6 part and puts
the LSM6DSO16IS on the IKS5A1 instead. The other lists both on the IKS4A1.
Two addresses answering two different WHO_AM_I values decides it: both are
on this shield, and the inventory line that names one is wrong.

**The honest limit of this reading.** WHO_AM_I values map to parts through
their data sheets, and the mapping above is taken from them rather than
from this board. The reading that closes it is the driver's own: once the
corrected overlay is applied, the `name` file of the registered IIO device
states which part the kernel matched, and that is a match made by code
rather than by a person reading a table.

---

## 15. The manual closed every open question, and opened one

Entry on Wednesday 30 September 2026. ST's UM3239 Rev 5 and DB5091 Rev 4
were read after the bus had already been measured, which is the right
order: the readings were taken blind and then checked.

**INT1 is settled, and the whole wiring table with it.** UM3239 Table 4
tabulates the Arduino R3 UNO connectors of this board. CN9 pin 6 is
LSM6DSV16X INT1, which is exactly what was claimed and wired. CN5 pin 9
and pin 10 are I2C SDA and SCL, CN6 pin 4 is 3.3 V, CN6 pins 6 and 7 are
ground. Every one of the five wires is now confirmed by the manufacturer
rather than inferred, and the entry 10 caveat is discharged.

The table also shows the trap that was waiting: **the other IMU's INT1 is
on CN8 pin 6.** Two connectors, both pin 6, two different chips. Wiring
the wrong one gives a driver waiting on a line that another part drives.

**Every address is a factory default.** UM3239 Table 1 lists the solder
bridge that sets each sensor's address, and all seven measured addresses
are the bold default: LIS2DUXS12 at 33h, LIS2MDL 3Ch, STTS22H 71h,
SHT40AD1B 89h, LPS22DF BBh, LSM6DSO16IS D5h, LSM6DSV16X D7h. Nothing on
this shield has been modified.

**Entry 13 was right, and entry 14's doubt is discharged without lifting
anything.** DB5091 lists the seven sensors on the main board of the kit,
the X-NUCLEO-IQS4A1. The detachable board on top is the STEVAL-MKE001A1
and it carries the Qvar swipe electrodes, which are not I2C devices. So
the shield does carry both inertial units, the daughter board contributes
nothing to this bus, and the volume that lists a single LSM6 part on the
IKS4A1 is wrong. Joseph was also right to refuse the lift-and-rescan test
I proposed: the board does not detach by hand, and the answer was in a
document.

**Mode 1 is confirmed by observation rather than by inspecting jumpers.**
UM3239 section 3.2 says Mode 1 puts every sensor on the host bus, with J4
and J5 at 1-2 and 11-12, while the sensor-hub modes move the
environmental parts behind an IMU. Six parts answering on every scan is
that proof.

**The question the manual opened.** Across three scans with nothing
touched, 0x19 answered once. The other six answered every time. The
LIS2DUXS12 is therefore present and intermittent under `i2cdetect`, which
is a different state from absent and a different state from working.
DB5091 notes that the LIS2DUXS12, the LSM6DSV16X and the LPS22DF are MIPI
I3C capable, and an I3C-capable part can sit in a state where it does not
answer a plain I2C probe. That is a hypothesis and not a reading. The
reading that would settle it is a direct register access rather than a
scan, because `i2cdetect` probes with a transaction the part may decline
while still being perfectly addressable.

**A second blocker cleared the same evening.** The serial console came up
through `picocom` inside WSL, on the Renkforce PL2303HXA that the Windows
driver refuses, attached with `usbipd`. Project 1's bring-up document
predicted exactly that route and Project 2 cannot proceed without it. The
boot log is captured.

---

## 16. A bus scan is not an inventory

Entry on Wednesday 30 September 2026, closing the question entry 15
opened.

**What happened.** Two commands separated the two explanations for the
part that came and went.

```
i2cget -y 1 0x19 0x0f   ->  0x47
i2cdetect -y -r 1       ->  0x19 present, 0x44 absent
```

0x47 is the LIS2DUXS12 identity register. It answers a direct register
read, repeatably. The part was never intermittent.

**What was intermittent was the question being asked.** `i2cdetect`
chooses a probe transaction per address, and the two it uses are not
equivalent:

| Probe | Sees | Misses |
|---|---|---|
| default, SMBus quick-write | 0x44 | 0x19, on most runs |
| `-r`, SMBus read-byte | 0x19 | 0x44 |
| both together | all seven | nothing |

The SHT40AD1B at 0x44 is command-based and has no register map, so a bare
read-byte is not a transaction it answers. The LIS2DUXS12 at 0x19
declines a zero-length write. Neither part was ever missing, and neither
probe mode ever enumerated this board.

**Why this matters more than the detail.** Step 1 of `docs/BRINGUP.md`
says a missing address is wiring or bus speed and that no driver work will
fix it. That is now known to be incomplete: a missing address can also be
a probe that the part declines. Three times in one evening a correct
reading produced a wrong conclusion, and each time the fault was in what
the reading was assumed to mean rather than in the reading.

**What this vindicates.** `iio-probe`, the inventory tool this project
specifies, exists precisely because `ls /sys/bus/iio/devices` cannot
distinguish five different failures. The same argument applies one layer
down: a scan enumerates what answers one kind of probe, and an inventory
needs a per-part question. The honest enumeration of this shield is seven
direct register reads, not a grid.

**The three identity values now measured**, all stable on repeat: 0x19
answers 0x47, 0x6a answers 0x22, 0x6b answers 0x70. The remaining four
use different identity registers and are not yet read.

---

## 17. The distribution kernel has none of the drivers, and that is the answer to a question this project had already answered

Entry on Wednesday 30 September 2026.

**What happened.** Before applying the overlay, the running kernel was
asked whether it carries the four drivers the overlay names. It carries
one.

| Sensor | Address | Driver on stock Raspberry Pi OS 6.18.50 |
|---|---|---|
| LSM6DSV16X | 0x6b | absent |
| LIS2MDL | 0x1e | absent |
| LPS22DF | 0x5d | absent |
| SHT40AD1B | 0x44 | present, `sht4x`, hwmon rather than IIO |

There is no `drivers/iio/magnetometer` directory at all. The pressure
directory holds `bmp280` and `ms5637`. The inertial directory holds
`bno055` and `inv_mpu6050`. `modules.builtin` lists none of them either,
so they are not compiled in. The capture is in
`docs/evidence/drivers-rpios-2026-09-30.txt`.

**What that means for the overlay.** It compiled cleanly with `dtc`, and
applying it would create four nodes of which three bind to nothing. That
is exactly the outcome this overlay's own header comment warns about: a
node naming a compatible the kernel does not know is not an error, the
node is created, nothing binds, and the part is invisible with no message
anywhere.

**What it means for the project.** Step 1 of the bring-up is complete and
step 2 cannot run here. The verdict its own table calls
`no-driver-in-image` is the true one, reached before wasting a reboot on
it.

**What it vindicates.** `kas/bench-iio.yml` and the kernel fragment
`meta-bench/recipes-kernel/linux/files/iio.cfg` exist to turn these four
drivers on. Until today that was a precaution written from reading. It is
now a requirement with a measurement behind it, and the project's decision
to build its own image rather than lean on a distribution is no longer a
matter of taste.

**The useful experiment that remains on this card.** Applying the overlay
anyway binds the SHT40AD1B and leaves the other three unbound, which
demonstrates both halves at once: that the overlay and `dtc` path works on
this host, and what a silent non-binding looks like from the outside. One
reboot buys evidence for the working case and the failing case together,
which is worth more than skipping it.

---

## 18. The overlay applied, bound nothing, and said nothing

Entry on Wednesday 30 September 2026. The last measurement of the evening,
and the one worth keeping.

**What happened.** The overlay was compiled on the board with `dtc`,
installed, added to `config.txt` under `[all]`, and the board rebooted
cleanly. All four nodes are in the live device tree:

```
/proc/device-tree/soc/i2c@7e804000/
  lis2mdl@1e  lps22df@5d  lsm6dsv16x@6b  sht4x@44
```

`/sys/bus/iio/devices/` does not exist. Not empty, absent: nothing pulled
the IIO core in, because none of the three ST drivers is in this kernel.
And `dmesg` filtered for every part name, the overlay name and the word
overlay returns **nothing at all**.

**One of the four did bind.** The SHT40AD1B at 0x44 is now `hwmon1`,
beside the Pi's own `cpu_thermal` and `rpi_volt`. It is the only part with
a driver in this kernel, and it is hwmon rather than IIO, exactly as this
overlay's comment said it would be. So the board now has one working
sensor and three described ones.

**Why this is worth a journal entry rather than a shrug.** The header
comment of `bench-iks4a1-overlay.dts` has said from the day it was written
that a node naming a compatible the kernel does not know is not an error:
the node is created, nothing binds, the part is invisible, and no message
appears anywhere. That was reasoning. It is now a capture, in
`docs/evidence/overlay-applied-2026-09-30.txt`.

**The shape of the trap, and it is sharper than expected.** An engineer
who checks `dmesg` sees a clean boot with no errors. An engineer who
checks the device tree sees four sensors correctly described. The result
is one sensor working out of four, and neither view contains a hint.

The sharpest part is that **the success was as silent as the failures**.
`dmesg` has no line for the sht4x that bound either. So the log cannot
separate the working part from the three broken ones, and the only
question that can is whether a device appeared. Only a third question, whether
anything bound, distinguishes them, and that is precisely the question
`iio-probe` was written to ask.

**What this closes.** Step 1 of the bring-up is complete with evidence.
Step 2 cannot run on a stock distribution kernel and the reason is
measured rather than assumed. The remaining steps need the project's own
image, which is a fresh evening rather than a next command.

**What the evening produced, beyond this project.** The card procedure in
`docs/CARD.md`. The serial console working through the WSL route that
Project 1 predicted, which unblocks Project 2. A corrected bench
inventory. And four corrections to this project's own documents, every one
of them found by a measurement contradicting something that had been
written from reading.

---

## 19. A number, at last

Entry on Wednesday 30 September 2026.

```
/sys/class/hwmon/hwmon1/temp1_input      22112
/sys/class/hwmon/hwmon1/humidity1_input  53968
```

22.112 degrees Celsius and 53.968 percent relative humidity, from the
SHT40AD1B at 0x44, through the `sht4x` hwmon driver, bound by a node in
this project's own overlay.

**Why one sensor of four is still worth recording as a milestone.** Every
link in the path is now exercised at least once: five flying leads to a
Pi header, a bus that enumerates, an address confirmed against the
manufacturer's table, an overlay compiled and applied, a driver that
bound, a device that appeared, and a value that is neither zero nor
absurd. Before today the whole of that was written and none of it had been
run.

**What it does not claim.** Nothing about the three parts with no driver.
Nothing about buffers, triggers, the hardware FIFO or the interrupt on
GPIO24, which is still an unexercised wire. Nothing about the comparison
this project exists to make, which needs all of that.

**The honest description of where project 10 stands.** Step 1 complete
with evidence. Step 2 attempted, and its outcome measured: one of four.
Steps 3 to 8 require the project's own image, for a reason that is now a
capture rather than an assumption.

---

## 20. The reading responds to the world

Entry on Wednesday 30 September 2026. Acceptance test for the one bound
sensor, and the last of the evening.

**What happened.** A one-second sampling loop, breathed on from a few
centimetres.

| Channel | Floor | Peak | Change |
|---|---|---|---|
| Humidity | 55.910 percent | 64.625 percent | 8.7 percentage points |
| Temperature | 22.205 degrees | 22.406 degrees | 0.201 degrees |

Humidity rose in about three seconds and decayed back past its starting
floor over the following twelve, still falling when the capture ended.
Temperature rose a fifth of a degree and did not return within the
capture.

**Why the asymmetry is the finding rather than the absolute values.**
Breath is both warm and wet. A working humidity channel must move far more
than the temperature channel on that stimulus, and it moved by nearly nine
percent against two tenths of a degree. A sensor stuck at a constant would
show neither, and a sensor returning noise would show both equally and
without a decay curve. The shape is the evidence.

This is the first acceptance criterion in this project met on hardware.

**One artefact worth writing down.** Every line of the capture appears
twice, in identical pairs, on a loop that prints once per iteration with a
one-second sleep. The likeliest cause is two copies of the loop running
from a duplicated paste into the serial console. It does not affect the
values and it would quietly halve any rate computed from such a capture,
so it is named here before a log like this is used as timing evidence.
