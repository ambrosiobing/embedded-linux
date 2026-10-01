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

> **Withdrawn the same evening, Wednesday 30 September 2026, and restored
> to the record on the same date after being deleted rather than
> superseded.** Photographs of the bench show a second board, marked
> STEVAL-SMKE and seated on the shield, and the X-NUCLEO-IKS4A1 carries a
> DIL24 socket for exactly that purpose. Two addresses on the bus
> therefore did not establish that both parts are on the shield. Entry 14
> has the state of the question and entry 15 closes it. The paragraph
> above is left standing because it records what was concluded and when.

**The honest limit of this reading.** WHO_AM_I values map to parts through
their data sheets, and the mapping above is taken from them rather than
from this board. The reading that closes it is the driver's own: once the
corrected overlay is applied, the `name` file of the registered IIO device
states which part the kernel matched, and that is a match made by code
rather than by a person reading a table.

---

## 14. Two boards were on the bus, and only one of them was being described

Entry on Wednesday 30 September 2026, later the same evening. Deleted when
entry 15 settled the question, and restored on the same date: a conclusion
that was withdrawn is part of the record, and entry 15 refers to this one
by number.

**What happened.** Photographs of the wired bench showed what the register
reads could not: a second board is seated on the X-NUCLEO-IKS4A1. Its
silkscreen reads STEVAL-SMKE and the shield underneath carries a socket
marked DIL24, which is the position ST provides for adding a further MEMS
part.

**What that costs.** Entry 13 concluded that the shield carries two
inertial units because two addresses answered with two different WHO_AM_I
values. That inference assumed every address on the bus belonged to the
shield. With a daughter board present the assumption does not hold, and
the conclusion is withdrawn rather than defended.

**What survives it, and why.** The overlay change does not depend on the
question at all. 0x6b answers 0x70 and 0x6a answers 0x22, and a driver
that requires 0x70 must be pointed at 0x6b whichever board the part is
soldered to. WHO_AM_I is a property of the chip, not of the board carrying
it. So `lsm6dsv16x@6b` is right either way, and that is the change that
would otherwise have cost an evening of debugging a probe failure.

**What is now open.** Which board owns 0x6a, which owns 0x6b, and
therefore what the X-NUCLEO-IKS4A1's own population actually is. The
inventory lines in both volumes stay untouched until that is known.

**The test that was proposed, and refused.** Power down, lift the daughter
board off, power up, rescan. It was refused on the bench because the two
boards are one assembly and separating them risks the assembly for a
question a document can answer. That refusal was right, and entry 15 is
the document answering it. A test that is cheap in commands is not cheap
if it puts the hardware at risk.

**The habit worth naming.** Two readings were taken and both were correct,
and the conclusion drawn from them was still wrong, because it rested on
an unstated assumption about what was physically present. A bus scan
enumerates a bus, not a board. The photograph was the instrument that
caught it, which is an argument for photographing a bench before reasoning
about it rather than after.

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

---

## 21. Gravity, through a chip the kernel cannot see

Entry on Wednesday 30 September 2026.

**What happened.** The LSM6DSV16X at 0x6b was started and read entirely
from user space, through `i2c-dev`, on a kernel that has no driver for it
and where `/sys/bus/iio` does not exist.

```
i2cset -y 1 0x6b 0x10 0x06      CTRL1: 120 Hz, high performance
i2cget -y 1 0x6b 0x10   -> 0x06 accepted
i2cget -y 1 0x6b 0x2c w -> 0x4078
```

0x4078 is 16504 counts. At the default two g full scale, 0.061 mg per
count, that is **1.007 g** on the axis normal to a board lying flat.
Gravity, to within a percent, from a part with no driver.

At rest the triple reads X about minus 5 mg, Y about plus 13 mg, Z about
1.006 g: a board not quite level plus the part's zero-g offset. Under a
tap, X and Y swing by several hundred counts and return. Signal when
disturbed, the resting triple when not.

**What this settles about the register map.** It was taken from the LSM6
family convention and is now confirmed by measurement rather than
assumption: WHO_AM_I at 0x0f, CTRL1 at 0x10 which reads back what was
written, and little-endian output words at 0x28, 0x2a and 0x2c. The
gravity check is what confirms it, because a wrong map does not produce
one g on exactly one axis.

**Why this is the more interesting of tonight's two working sensors.** The
humidity sensor works because this kernel happens to carry its driver. The
accelerometer works because it does not need one. Its device tree node
binds to nothing, the IIO subsystem is absent, and eight bytes of i2c-dev
traffic deliver correct three-axis acceleration anyway. That is the
argument Project 11 opens with, demonstrated on hardware instead of
asserted: not every sensor needs a kernel driver.

**What it is not.** Roughly five samples a second, from three separate
processes per sample and a sleep, against a part configured for 120. No
timestamps. Nothing here touches the hardware FIFO, the watermark
interrupt on GPIO24, or any buffered path. Those are what this project
exists to compare and they need the drivers this kernel does not carry.
The gap between five hertz of shell and a timestamped buffered stream is
the whole subject of Project 10, and tonight measured the bottom of it.

**One artefact.** The serial console emitted binary garbage partway
through the capture and recovered. Project 1 recorded that this Renkforce
PL2303HXA dropped its USB connection twice during bring-up, and this is
consistent. Readings either side are self-consistent so the values stand,
but evidence captures belong over ssh rather than over this cable.

---

## 22. One g, to nine parts in a thousand

Entry on Wednesday 30 September 2026. The capture was plotted and reduced.

| Axis | mean | min | max |
|---|---|---|---|
| X | -0.001 g | -0.15 g | +0.25 g |
| Y | +0.013 g | -0.67 g | +0.17 g |
| Z | +1.007 g | +0.55 g | +1.21 g |
| magnitude | 1.009 g | | |

**The magnitude is the result.** A stationary accelerometer must report a
vector magnitude of one g, and it reports 1.009. Nine parts in a thousand,
inside a MEMS part's ordinary sensitivity tolerance, from a chip with no
driver read by a shell loop. Gravity is the right acceptance test for a
bench with no calibration rig precisely because it is free, always
present, and known.

**It also checks the assumption the plot was drawn under.** The axes were
scaled assuming a two g full scale at 16384 counts per g. A wrong
full-scale setting would have produced a magnitude near half a g or near
two g. One number confirms the register map and the full-scale default
together.

**Two events are visible**: a single knock at about 24.5 seconds, and a
burst of oscillation between 28 and 31 seconds.

**And the extremes in that table are not the peaks of those events.** At
five samples a second a knock lasting a few milliseconds is caught by at
most one sample and usually by none. The -0.67 g on Y is one sample of a
transient rather than its maximum, and a real desk tap peaks several g
higher. The min and max columns describe the capture, not the events.

**That is the sharpest statement of this project's subject so far.** The
part was configured for 120 samples a second and delivered five, unevenly
spaced, with no timestamps, through three processes per sample. The
hardware FIFO and the watermark interrupt on the wire already run to
GPIO24 exist to take all 120 with a timestamp on each. Tonight measured
the floor that the rest of this project is a comparison against.

---

## 23. The burst read outruns the sensor, and finds a torn sample

Entry on Wednesday 30 September 2026.

**What happened.** Reading all six output bytes in one `i2ctransfer`
instead of three separate `i2cget` calls took the loop from about five
samples a second to about 180.

2905 reads yielded 1905 unique samples. That third of duplicates is itself
the measurement: the loop is now reading faster than the part is producing
at 120 Hz, so **no sensor sample is being missed.** The previous capture
was aliased and this one is complete, which is a change of kind and not
only of degree.

| Axis | mean | min | max |
|---|---|---|---|
| X | -0.008 g | -0.066 g | +0.098 g |
| Y | +0.013 g | -0.112 g | +0.065 g |
| Z | +1.006 g | +0.013 g | +1.133 g |
| magnitude | 1.006 g | 0.018 g | 1.134 g |

Magnitude 1.006 g, confirming the two g scale again on better statistics.
Resting noise is now a few tens of milli-g, where the sparse capture had
suggested hundreds. Those earlier extremes were single samples of
transients, not noise, which is what the previous entry warned they were.

**One sample is not physics.** Near index 1660 the magnitude falls to
0.018 g. That is free fall, and a board on a desk is not in free fall. The
magnitude is the discriminator: real motion adds to one or more axes and
leaves the magnitude near or above one g, whereas only genuine free fall
or a corrupted read drives all three to zero together, and genuine free
fall would last hundreds of samples at this rate rather than one.

**A testable mechanism.** Block data update is off by default on this
family, so the output registers can be refreshed between the reading of a
low byte and its high byte and one sample can be assembled from two
measurements. That produces a single wild value among correct ones, which
is the shape observed. CTRL3 at 0x12 carries the bit. If the artefact
disappears from a recapture with it set, the diagnosis is proven. If it
survives, the cause is elsewhere and worth finding before these numbers
are used for anything.

**Why this belongs in the journal rather than being cleaned out of the
data.** A single bad sample in nineteen hundred is easy to delete and easy
to justify deleting. It is also the only evidence of a defect that would
corrupt every buffered capture this project goes on to take, and at 120 Hz
with a watermark of 64 it would corrupt them silently. The cheap test is
one register write.

---

## 24. The mechanism proposed in entry 23 is wrong, and that narrows it

Entry on Wednesday 30 September 2026, later the same evening.

**What happened.** Entry 23 proposed that the single near-zero sample came
from the output registers being refreshed between the low byte and the high
byte of a read, which block data update prevents, and gave the register
write as the test. CTRL3 at 0x12 read `0x44` before that write. Bit 6 is
block data update and it was already set, because `0x44` is this part's
reset value for the register. The write changed nothing and the mechanism
cannot be the cause.

**Why the disproof is worth as much as the hypothesis was.** The reason for
naming a specific mechanism rather than listing three possibilities is that
a mechanism can be tested in one command, and this one was, and it is now
out. A list of possibilities cannot be tested at all, which is why the
previous entry declined to leave the fault as one.

**What is left, ordered by evidence rather than by plausibility.** The
leading candidate is not the sensor and not the bus: it is the path from
the board to the file. The three-axis run earlier the same evening contains
a block of visible serial corruption, so that path has already been
observed damaging characters on this bench. A flipped character inside a
hex field yields a number that still parses. Behind that, an I2C frame
damaged on the wire, which `i2c-dev` cannot detect because it carries no
integrity check and hands a wrong byte back as data. Behind that, the parse
or the deduplication.

**The next test is structural and not statistical.** Read the offending
line of the raw dump, the six hex bytes rather than the number they became.
Six well-formed bytes that genuinely decode near zero put the damage at or
before the bus read. A short line, a long line or a character that is not
hex puts it in the transport, and clears both the sensor and the bus.

So the capture loop now carries a line index and a fixed field count. A
damaged line then arrives as a damaged line, instead of arriving as a
measurement.

**The habit worth naming.** Two mechanisms were proposed from the same
single sample, and the first was wrong for a reason that one register read
settled in a second. Guessing at a cause is cheap when the guess is
specific enough to be killed. It is only expensive when it is vague enough
to survive.

---

## 25. A quiet run, and what it says about every number before it

Entry on Wednesday 30 September 2026, later the same evening.

**What happened.** Two captures of 4000 reads each, identical in every
respect except one: a shaver held against the board in the second. Both
written to a file on the board and copied off with `scp`, so nothing in
this pair passed through a terminal.

| | quiet | shaver |
|---|---|---|
| X mean, rms | -5.3 mg, 0.36 mg | -5.4 mg, 4.69 mg |
| Y mean, rms | +13.5 mg, 0.36 mg | +13.2 mg, 3.87 mg |
| Z mean, rms | +1.0067 g, 0.47 mg | +1.0068 g, 10.66 mg |
| magnitude | 1.0068 g | 1.0069 g |
| malformed lines, read errors | 0, 0 | 0, 0 |

**The quiet run is the more valuable of the two.** The floor is 0.36 mg on
X and Y, about six counts, which is the part's own noise and not anything
this bench is adding. The previous entry read X and Y extremes near 0.1 g
as a noise floor of a few tens of milli-g. Against 0.36 mg that is out by a
factor of some hundreds, and those extremes were the bench being disturbed
during the capture rather than the sensor being noisy. Every figure taken
before this one was compared against a floor that had never been measured.

**The near-zero sample did not reproduce.** None below 0.5 g in 8000, no
malformed line, no read error. At the one in 1905 that entry 23 appeared to
show, about four would be expected and the chance of none is around one and
a half percent. The one thing that changed is that this pair was written to
a file and copied as a file. That is not proof and the fault is not closed,
but the evidence now points at the terminal path and away from the bus,
which is where entry 24 put it on quite different grounds.

**The duplicate fraction fell, and that is a loss rather than a gain.** 1.4
percent against 34 percent. The arithmetic that turned 34 percent into a
read rate only holds when the reads outrun the sensor: below that, samples
are skipped rather than repeated and the fraction sits near zero whatever
the rate. So this says the loop is at or under 120 Hz and nothing more.
Writing each sample through a command substitution and a redirect costs
what the tight loop did not pay. The rate has to be timed, not inferred.

**The waveform in the plot is not the shaver's waveform.** At or below 120
reads a second nothing above 60 Hz can be represented, and a mains-driven
shaver runs near 100 Hz. The oscillation packets are folded artefacts of a
frequency that was never present. The RMS figures survive, as a lower
bound, because the part band-limits before it samples.

**What survives, and is worth keeping.** Vibration is separable from the
floor by a factor of 23 on Z, which is a running-or-not verdict and not a
spectrum. Z responds two and a half times as much as X and Y, which is a
PCB on header pins being more compliant out of plane than in it, and is
mechanics rather than sensor. The magnitude is 1.0068 g where truth is
1.0000 g, so sensitivity is 0.68 percent high, inside tolerance, and that
is the number a calibration step nulls. The three means agree between two
independent runs to under half a milli-g, which is both the proof that the
shaver added acceleration without tilting the board and a bias stability
figure in its own right.

**And this is the measurement that earns the buffered path.** The case for
FIFO and hardware timestamps has been an assertion in this project's
documents since it was written. It is now a demonstrated need: the shaver's
actual frequency content cannot be recovered from user-space polling at any
loop speed, because each sample costs a process, a syscall and a bus
transaction, and the ceiling that imposes is below the frequency of a
household appliance. The comparison the project exists to make now has a
measured slow end and a reason to build the fast one.

---

## 26. A spectrum with no time base, and two clocks instead of one

Entry on Wednesday 30 September 2026, last of the day.

**What happened.** An FFT of both 4000-sample captures, Hann windowed with
the mean removed. The shaver puts a clear tone into the board at 0.0270
cycles per sample and the quiet record has no tone at all.

| | quiet strongest bin | shaver strongest bin | shaver peak |
|---|---|---|---|
| X | 0.0285, 0.044 mg | 0.0270 | 1.100 mg |
| Y | 0.0415, 0.040 mg | 0.0270 | 1.333 mg |
| Z | 0.0258, 0.051 mg | 0.0270 | 4.788 mg |

**The tone is real.** All three axes peak in the same bin, one part in two
thousand, where the quiet record's strongest bins are scattered and reach
only 0.05 mg. The shaver puts one forcing frequency into the board, which
is what a motor does, and the amplitudes follow the compliance measured in
entry 25: most responsive normal to the board's plane.

**The output rate is 120 Hz and it does not scale that axis.** CTRL1 reads
0x06, which is 120 Hz. But this record is indexed by poll, not by sensor
sample, and the loop's rate is unmeasured, jittery and unlocked from the
sensor's oscillator. There are two clocks here and the axis belongs to the
wrong one. That is why the answer to "relabel it in hertz" is that nobody
can, from this file.

**Aliasing is not suspected, it is measured.** The shaver record sits 10.4,
10.5 and 8.1 times above the quiet one in the top half of the band, and
over a quarter of the X axis AC energy is up there with no structure in it.
A narrowband source cannot lift an entire half-band uniformly. That is real
vibration arriving at frequencies it never had.

**A prediction, written before the test.** Under the 120 Hz assumption the
tone is near 3.2 Hz, far below any mechanism in a foil shaver. The reading
that fits is a beat between a mechanical line near 117 to 123 Hz and the
sensor's own 120 Hz sampling, and a one percent change in motor speed would
move that beat by about a hertz, which is the wandering already noticed.
Changing the output rate to 240 Hz and leaving the loop alone separates the
two: a genuine 3.2 Hz signal keeps its position in cycles per sample, and a
beat against the sensor's rate cannot.

**The deeper finding, and it is the project's own thesis arriving from an
unexpected direction.** There are two sampling stages in this measurement.
The sensor decimates to its output rate with a filter in front of it. Then
the loop resamples those registers at an unlocked rate with no filter at
all, and none is possible, because the second stage is a program asking
rather than a part delivering. Every fold and every beat above comes from
that second stage, and no amount of loop tightening removes it, because it
is not a speed problem.

The FIFO removes the stage rather than speeding it up. Samples are taken on
the sensor's clock, uniformly, and read out in bursts afterwards. This
project has argued for buffered acquisition since it was written, on
grounds of interrupt count and CPU. Tonight it turns out the stronger
argument is one the documents never made: **without it there is no valid
frequency axis at all.**

**The habit worth naming.** The prediction above is written down with its
falsifier before the command is run, because entry 24 is what happens when
a mechanism is proposed and tested in the wrong order. One register read
killed that one in a second. This one has its register read waiting for it.

---

## 27. The noise floor scales as the square root of bandwidth, to one percent

Entry on Wednesday 30 September 2026, later still.

**The loop rate is measured rather than inferred.** 4000 samples in 31.653
seconds and again in 31.501, so 126.4 and 127.0 reads a second, half a
percent apart. Every frequency in entry 26 multiplies by 126.7: the tone at
0.0270 cycles per sample is **3.42 Hz** and the axis runs to 63.35 Hz.

**The first attempt to time it measured the wrong loop.** Timing
`i2ctransfer ... >/dev/null` gave 185 reads a second, while the loop that
writes the file wraps the command in a substitution and forks a subshell on
every sample. 185 is the speed of a loop that throws the data away. Timing
an imitation of the thing measures the imitation.

It also resolves a contradiction that had been sitting unexamined: the
first burst capture implied 183 reads a second from its duplicate fraction,
and the 4000-sample captures implied 120 or below. Both were right. They
are different loops.

**And then the result of the evening.** Doubling the output rate doubles
the measurement bandwidth, so white noise should rise by the square root of
two.

| axis | 120 Hz | 240 Hz | ratio | predicted |
|---|---|---|---|---|
| X | 0.36 mg | 0.51 mg | 1.417 | 1.414 |
| Y | 0.36 mg | 0.51 mg | 1.420 | 1.414 |
| Z | 0.47 mg | 0.68 mg | 1.432 | 1.414 |

One comparison confirms four separate things: the noise is white, the rate
change reached the part, the floor is the sensor's own noise and not
anything on this bench, and the chain from register to number is
quantitatively sound. A prediction from first principles landing inside one
percent is worth more than any number taken alone, and this project had not
produced one until now.

The bias is unmoved across the change and the duplicate fraction is 0.0
percent at 240 Hz, which is what it must be when a 126.7 Hz loop reads a
240 Hz part: samples skipped, not repeated.

**A claim from entry 26 is withdrawn.** It says the shaver's tenfold
broadband rise in the top half of the band is folded content, measured
rather than suspected. That is not established. At 120 Hz the part
band-limits to 60 Hz and the loop can represent 63.35 Hz, so the second
sampling stage adds almost no folding at that setting. The rise is equally
consistent with the shaver genuinely exciting the board broadband, which a
mechanism rattling against a circuit board does. Aliasing inside the part's
own decimation is still possible. Neither is shown, and the sentence should
not have said measured.

**The habit worth naming, again.** Entry 26 was written with care, with its
prediction and falsifier stated in advance, and it still contains an
over-claim: a plausible mechanism promoted to a measured fact because the
number supporting it was real. The number was real. The inference from it
was not tested. Being careful about one claim in an entry is not being
careful about the entry.

---

## 28. The test was inconclusive, and the reason is how it was specified

Entry on Wednesday 30 September 2026, last of the day.

**The prediction, and what came back.** Entry 27 predicted that the tone at
0.0270 cycles per sample either stays, meaning a real 3.42 Hz vibration, or
moves to 0.0797, meaning a beat. At 240 Hz output it did neither cleanly.
The sharp line of the 120 Hz record, a narrow cluster from 0.0267 to 0.0280
on all three axes, became a spread from 0.052 to 0.117 with several
comparable peaks and no dominant one.

**The test cannot decide, because two things changed.** The excitation was
not held constant.

| | X | Y | Z |
|---|---|---|---|
| AC rms, 120 Hz record | 4.7 mg | 3.9 mg | 10.7 mg |
| AC rms, 240 Hz record | 15.6 mg | 28.5 mg | 58.5 mg |

Between three and seven times stronger, and continuous where the first was
intermittent. The output rate changed and so did the shaver. That is not a
comparison, and the instruction that produced it was mine: "roughly the
same portion of the run" is not a control, and one line of this bench's own
method says a comparison differs in one variable or it is not one.

**What the run produced instead, which is worth more than the test was.**
Raising the output rate made the measurement worse, and the mechanism is
exact.

The part band-limits before it decimates. At 120 Hz output it passes
nothing above 60 Hz, and the loop at 126.7 can represent 63.35, so the
second sampling stage folds almost nothing: **the sensor's own anti-alias
filter was acting as the loop's anti-alias filter.** At 240 Hz output the
part passes up to 120 Hz, and everything between 63.35 and 120 folds down
into the band with nothing to stop it.

| | share of Z energy above 0.25 cyc/sample | peak over rms |
|---|---|---|
| 120 Hz output | 3.9 % | 0.45 |
| 240 Hz output | 9.8 % | 0.15 |

So the 120 Hz setting was accidentally near-ideal for this loop, and the
rule that follows is worth more than the beat question: **for a polled
capture, set the output rate at or just below the poll rate**, and let the
part's filter protect the stage that cannot have one.

**Why the ODR ladder cannot settle the beat, and what can.** The available
rates are all 120 Hz times a power of two, so 120 is a harmonic of every
one of them and a line near 117 or 123 Hz beats to the same 3.4 Hz at every
setting. Moving the rate cannot move that beat.

Lowering it far enough removes it instead. At 30 Hz output the part's
filter cuts near 15 Hz: a real 3.42 Hz vibration passes, and a 117 Hz line
is rejected before decimation, so it never reaches the decimator to alias.

  the tone survives at 3.42 Hz    it is real
  the tone disappears             it was a beat from a line near 120 Hz

That is a cleaner instrument than moving a peak, because the two outcomes
are presence and absence rather than two positions to argue about.

**The habit worth naming.** The prediction was written before the command,
with its falsifier, which is what entry 26 said to do. It still produced
nothing, because the care went into the prediction and not into the
protocol. Stating what will count as a refutation is worthless if the run
that follows changes two things at once.

---

## 29. The tone is real, the hypothesis is dead, and the strongest line is probably the operator

Entry on Thursday 1 October 2026.

**The test worked, and it refuted me.** Two captures back to back, same
grip, output rate the only deliberate change. At 30 Hz output the part
band-limits near 15 Hz, so a mechanical line near 117 or 123 Hz is rejected
before the decimator and cannot alias to anything at all.

The tone is still there.

| output rate | poll clock | unique | Z AC rms | Z peak |
|---|---|---|---|---|
| 120 Hz | 126.1 Hz | 3848/4000 | 6.56 mg | 2.71 Hz, 3.85 mg |
| 30 Hz | 126.7 Hz | 957/4000 | 1.79 mg | 2.98 Hz, 0.94 mg |

So it is a real low-frequency vibration of the board and never was a
sampling artefact. Entry 26 proposed the beat, entry 27 predicted where it
would move, entry 28 explained why moving it could not work, and this one
closes it the other way: the idea was wrong.

**It survives normalisation too, which is the part that makes it stick.**
The excitation was weaker again in the second run, by a factor of nearly
four. The tone scaled with it: peak over record AC rms is 0.59 at 120 Hz
output and 0.53 at 30 Hz. The spectral shape held while the level moved.
That is the comparison entry 28's run could not make, and it works here
only because the ratio is taken **inside** each record instead of between
two of them. When an experiment cannot hold a variable still, the next best
thing is a quantity that does not care about it.

**Neither file is at the rate in its name.** Both have a poll clock near
126.4, measured. Reading the 30 Hz file as though it were sampled at 30
makes every frequency 4.2 times too low and the record 133 seconds instead
of 31.6. The filename records what the sensor was told; only the stopwatch
records what the file is.

**And the finding worth more than the one we went looking for.** The tone
sits between 2.7 and 3.4 Hz across every capture and wanders from one to
the next. That is far too slow for a motor or a cutter. A quantity that
wanders between runs of the same apparatus is usually the part of the
apparatus that is not bolted down, and here that is the hand. A hand
pressing an object against a surface modulates the contact force at a few
hertz.

**The strongest line in this spectrum is most likely the person holding the
shaver**, and this project has spent an evening characterising it. The test
is free: tape or clamp the shaver to the board so no hand touches it, and
capture again. If the tone weakens sharply or moves, it was the grip.

**A correction carried over from the earlier reading.** The advice to raise
the output rate to resolve the 12 to 25 Hz band is backwards for this
setup. At 120 Hz the part band-limits to 60 Hz and the loop represents
63.35, so that band is resolved with no folding, and the 120 Hz record does
show it at 0.299 mg and 18.71 Hz. Raising the rate only lets content above
the loop's Nyquist fold in. For this loop, 120 Hz output is the right
setting, and it is the one that was accidentally chosen first.

**The habit worth naming.** A hypothesis was proposed, predicted, defended,
redesigned and finally killed by a test built around presence and absence
rather than position. Four entries on something that turned out to be
wrong, and the cost was right: the alternative was carrying it as an
unexamined doubt behind every number this project goes on to produce.

---

## 30. Taping the shaver down refuted the operator reading, and one more of mine

Entry on Thursday 1 October 2026.

**The test was clean and it went the other way.** Shaver taped to the
board, no hand on it, both output rates.

| mount | Z AC rms | strongest Z | X bias |
|---|---|---|---|
| hand, 0x06 | 6.56 mg | 2.71 Hz, 3.85 mg | -5.2 mg |
| taped, 0x06 | 24.70 mg | 4.87 Hz, 14.61 mg | -33.0 mg |

Taping did not remove the low-frequency tone. It made it nearly four times
larger and moved it up by two hertz. **The hand was damping the assembly,
not driving it.**

The shape of the argument survives and the attribution does not. The line
still belongs to the part of the apparatus that is not bolted down, but
that part is the whole board-and-shaver assembly on whatever it rests on.
Taping stiffened the coupling and removed damping, so the resonance rose
and the amplitude with it, which is a mass on a spring behaving ordinarily.

**A second claim goes, and it is the one I was pleased with.** Entry 29
argued that 2 to 4 Hz and 12 to 25 Hz are two sources because their balance
flips with contact pressure. That rested on comparing the 0x07 record
against the 0x04 and 0x06 ones, across a change of output rate that this
journal has already documented as folding 63 to 120 Hz down into the band.
The mid-band dominance of that record may be folded content, and the
comparison cannot tell which.

Within matched output rates the balance does not flip. The low to mid ratio
is 4.36 against 5.75 at 0x04, and 3.58 against 6.24 at 0x06: rigid coupling
raises the low band relatively, both times, same direction. There is no
evidence here for two sources with opposing pressure dependence.

I spent several entries warning against cross-rate comparisons and then
built a conclusion on one, in the entry immediately after writing the
warning. The warning was not wrong and it was not enough.

**A third variable moved too.** The X bias went from -5.3 to -34.1 mg, a
tilt of about 1.6 degrees. Taping changed the assembly's attitude as well
as its stiffness, so this pair is not single-variable either, even though
the AC analysis is unaffected.

**And a verification silently did not happen.** After the write of 0x04,
`i2cget -y 1 0x6b 0x10` returned an empty line instead of a value, and the
capture went ahead on a readback that had produced nothing. What confirmed
the write was the duplicate fraction: 76.1 percent, identical to every other
0x04 run, putting the rate at 30.3 Hz.

So the output-rate meter stood in for a check that failed without being
noticed. That is a better argument for it than not needing a data sheet: it
measures what the part does, where a readback reports only what a register
holds, and it still works when the readback does not.

**The habit worth naming.** Two hypotheses of mine died today, the beat and
the operator, and both died to a measurement that cost one capture. The
pattern in both is the same: a mechanism that explained the data was
promoted to the mechanism that produced it, without the alternative being
tried. The cheap test is not the one that confirms the story. It is the one
that would look different if the story were wrong.

---

## 31. The tap does not ring, and that is the sharpest constraint of the day

Entry on Thursday 1 October 2026.

**What the tap test settles.** Shaver removed, four taps, and between them a
floor of 0.42, 0.37 and 0.58 mg with **no 2.7 to 4.9 Hz hump at all**. That
line needs the shaver running. It is not the board sitting there.

**A ring-down search, and the first version of it was mine and wrong.**
Taking 256 samples after each tap and looking in 3 to 6 Hz gave 1.21, 1.53,
26.83 and 0.08 mg. The 26.83 is an artefact of my own window: the taps are
1.5 s apart and a 2.0 s window swallows the next one. Only the fourth
window holds a single impulse and nothing else.

| | 3 to 6 Hz |
|---|---|
| tap 4, the one clean window | 0.08 mg |
| a quiet stretch, the floor | 0.06 mg |
| taped shaver running | 28.28 mg at 4.96 Hz |

**So a two g impulse does not excite the thing the shaver excites.** At
126.85 Hz a 5 Hz oscillation is 25 samples per cycle, so unlike the 57 Hz
question this absence is a measurement rather than a sampling limit.

**And that is a constraint rather than an answer.** It sits awkwardly beside
yesterday's taped result, and both are sound:

- the frequency moves with the mounting, 2.71 Hz held and 4.87 Hz taped,
  which is what a resonance does
- an impulse does not excite it, which is what a resonance does not do

A lightly damped mode would do both. A self-excited contact oscillation,
where the shaver rattles or sticks and slips against the board at a rate
set by the contact stiffness, would do the first and not the second, and so
would a mode damped heavily enough that an impulse cannot sustain it.
Nothing here chooses between them.

Three readings of this line have now been proposed and two are dead: a
sampling beat, and the operator. The third is still standing only because
it has not yet been tested properly.

**The clipping is worth naming.** Raw Z reaches 32764 against a rail of
32767. The tap peak is not measured, only bounded below at about two g, and
those four samples are not data. Moving to eight g full scale costs about
two percent of the noise floor, by the arithmetic in the evidence file, and
buys four times the headroom, which is a good trade for an impulse and a
bad one for a floor.

**The habit worth naming.** My ring-down windows overlapped the next tap and
produced a number that looked like a finding. It was caught by checking the
tap spacing against the window length, which takes one line of arithmetic
and was not done first. Every analysis window is a claim about what is
inside it.
