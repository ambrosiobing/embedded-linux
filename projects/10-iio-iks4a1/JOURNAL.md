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

---

## 32. There is a ring, and a two second window was hiding it

Entry on Thursday 1 October 2026.

**Eight g full scale did its job.** Five taps, peaks from 2.42 to 3.71 g,
none at the rail. The two g set was clipped and its peaks were never
measured, which is now settled rather than suspected.

**And the ring was never absent.** The transient lasts about 0.25 s. In a
2 s window it occupies an eighth of the record and its amplitude is diluted
to match, which is how a 2 s FFT reports a flat scatter of 0.2 to 0.3 mg
where the ring itself is 49 to 107 mg.

| tap | peak above g | implied from zero crossings | 32-sample FFT |
|---|---|---|---|
| 3.40 s | 2.699 g | 38.5 Hz | 27.5 Hz, 75.7 mg |
| 10.01 s | 1.415 g | 38.5 Hz | 31.4 Hz, 49.0 mg |
| 15.84 s | 1.986 g | 34.4 Hz | 23.5 Hz, 101.1 mg |
| 21.86 s | 2.539 g | 24.3 Hz | 3.9 Hz, 74.7 mg |
| 27.28 s | 2.449 g | 20.2 Hz | 23.5 Hz, 107.1 mg |

**An analysis window is a claim about what is inside it.** That sentence
was written in entry 31 after my own window swallowed the next tap, and the
same mistake has now appeared from the other side: a window long enough to
hold the ring comfortably is long enough to bury it. Matching the window to
the thing is not a refinement, it is the measurement.

**The decay is the better number, and it explains the scatter.** Envelope
in 32 ms blocks after the first tap: 2.699, 1.194, 0.189, 0.029 g, a time
constant near 39 ms. At about 28 Hz that is roughly one cycle to 1/e, so Q
is near 3, and a resonance with Q near 3 has a fractional bandwidth near a
third: 19 to 37 Hz for a 28 Hz centre.

The spread observed across five taps is 20 to 38 Hz. So **the five numbers
are one heavily damped mode, not five modes**, and what looked like scatter
is the mode's own bandwidth.

**The tap does not support 57 Hz.** Transient energy centres near 25 to
30 Hz. The 57 Hz of the handheld shaver record is uncorroborated and is not
a tap-excitable mode of this assembly. It joins the list of things this
loop cannot settle.

**And the limit is stated rather than glossed.** At 125.55 Hz a 28 Hz
oscillation is 4.5 samples per cycle and the entire ring is two or three
cycles. The frequency carries a large uncertainty and the Q a larger one.
What is solid is that a ring exists, that it is short, that it repeats
across five impulses, and that it is nowhere near 57 Hz.

**The eight g noise cost was predicted at two percent and remains
untested.** The quiet stretches give 0.48, 0.41 and 0.52 mg against 0.42,
0.37 and 0.58 at two g, scattering in both directions. An RMS estimate from
a few thousand samples carries about one percent of standard error, so a
two percent effect sits at the edge of resolvable, and these stretches
carry tap tails besides. Unrefuted and unconfirmed is the honest verdict,
and it is worth writing down as such rather than claiming the prediction
held.

---

## 33. The first program to reach the board would not start, and the repository was right

Entry on Thursday 1 October 2026.

**What happened.** `iio-probe` was copied to the Pi, made executable, and
answered `cannot execute: required file not found`. The file was plainly
there. The message is about the **interpreter**, not the script: the first
line is `#!/bin/sh` followed by a carriage return, so the kernel looks for
a program called `/bin/sh<CR>` and does not find one.

**The repository is not at fault and that is the useful part.** The
committed blob begins `#!/bin/sh` and ends the line with a bare newline.
The working tree copy ends it with carriage return and newline. The
`.gitattributes` in this repository already says `* text=auto eol=lf`,
which is the correct instruction, and `core.autocrlf` is `true` on this
machine, which is the usual Windows default. The attribute was added after
these files were checked out and nothing has re-checked them out since, so
the working tree still carries the conversion the attribute exists to
prevent.

Thirty-one tracked files with a shebang are in this state, across eleven
recipes and five projects.

**What that implies about the two delivery routes, which is the finding.**
A Yocto build fetches from git and would have shipped a working script.
Copying from the working tree ships a broken one. The two paths disagree,
the repository is right, and the failure only appears on the path that was
never the designed one. Anyone debugging this from the error message alone
would look at the Pi, the permissions, the shell and the script, in that
order, and all four are fine.

**The immediate fix is one command on the board** and the durable one is to
refresh the working tree so it matches what is committed. The second is
worth doing before any other program from this repository is copied to any
board, because every one of the thirty-one will fail the same way and the
message will not say so.

**The habit worth naming.** The error named the thing that was missing and
it was still misleading, because the thing that was missing was invisible:
a character with no printed form, in a file that displays correctly in
every editor. `od -c` on the first line settles it in one command, and it
is worth reaching for whenever a file that looks right behaves as though it
is absent.

---

## 34. Criterion 2, met by a program reporting that four drivers are absent

Entry on Thursday 1 October 2026.

**The first run of `iio-probe` on hardware produced a complete inventory.**
Seven parts, seven verdicts, and every verdict is the one the last two
days' measurements predicted: one `working` through hwmon, four
`no-driver-in-image`, two `unsupported`.

**The criterion is met by a disappointing result, and that was the design.**
"The inventory lists every sensor on the shield with its driver and status"
does not require the drivers to exist. It requires the program to say
truthfully what is there, and `no-driver-in-image` is one of the five
verdicts it was written to distinguish. The finding of Wednesday 30
September 2026 has now arrived through the instrument built to detect it,
rather than through a journal entry.

That also corrects something I said yesterday. Criteria 2 through 5 were
all described here as blocked on the drivers. Only 3, 4 and 5 are. Criterion
2 needed a shell script copied over `scp`, and it had been sitting behind an
assumption rather than behind a dependency.

**And one scan now enumerates the whole board, which no scan did before.**
Entry 16 established that the two probe modes disagree: the default sees
0x44 and misses 0x19, and `-r` does the reverse. This scan shows all seven
under the default mode, because 0x44 no longer gets probed at all. It reads
`UU`: the sht4x driver has claimed it, and a claimed address is reported
without being probed.

So **binding a driver to the part that hid under one probe mode is what made
a single scan complete.** The `UU` that reads like a fault to anyone meeting
it for the first time is the reason the grid is now right, and the one
driver this image happens to carry is the one that fixes the one address
that needed fixing. That is luck rather than design, and worth writing down
as luck.

**Still open at one address.** 0x6a is listed with `st_lsm6dsx` because the
part is an LSM6 family device. Whether that driver carries a compatible for
the LSM6DSO16IS specifically has not been checked in any kernel, and the
row says so rather than implying it has.

---

## 35. Two IIO devices, from a driver that was not in the image this morning

Entry on Thursday 1 October 2026.

    /sys/bus/iio/devices/iio:device0  ->  lsm6dsv16x_gyro
    /sys/bus/iio/devices/iio:device1  ->  lsm6dsv16x_accel

**One chip, one FIFO, one interrupt line, two IIO devices.** That sentence
has been in this project's design document and in the overlay's comments
since they were written, and nobody had seen it.

**What was missing was narrower than it looked.** The IIO subsystem is
present and packaged in full on stock Raspberry Pi OS, including the
`trigger` and `buffer` directories criteria 3 and 4 depend on.
`/sys/bus/iio` was absent only because nothing had loaded `industrialio`.
Only the ST drivers and their shared framework are gone.

**The compatible was checked before anything was compiled**, because an
overlay naming a compatible the kernel lacks creates a node, binds nothing
and logs nothing, which is this project's documented silent failure. The
source carries `st,lsm6dsv16x` with `.wai = 0x70`, the value measured at
`0x6b` on Wednesday, so the probe would match rather than refuse.

**And one of Wednesday's inferences turns out to have been weaker than it
read.** `ST_LSM6DSV_ID` and `ST_LSM6DSV16X_ID` share `.wai = 0x70`, so the
plain LSM6DSV and the 16X answer the same WHO_AM_I. Reading `0x70` did not
name the part. UM3239 Table 1 named it and the register agreed with it.
Nothing practical changes and the record should not imply otherwise.

**`insmod` earned its place by failing.** It refused with `Unknown symbol
__devm_regmap_init_i2c`, because `depmod` has no record of out-of-tree
modules and `insmod` resolves nothing by design. That is why it is the
right tool here and the wrong one in general: it names what is missing
instead of quietly satisfying it.

**Four of the five verdicts, on hardware, in one run.**

| address | part | verdict |
|---|---|---|
| 0x19, 0x38 | LIS2DUXS12, STTS22H | `unsupported` |
| 0x1e, 0x5d | LIS2MDL, LPS22DF | `no-driver-in-image` |
| 0x6a | LSM6DSO16IS | `not-bound` |
| 0x44, 0x6b | SHT40AD1B, LSM6DSV16X | `working` |

Criterion 7 asks that the inventory distinguish a missing driver from an
unbound one. It has been met since 16 September by 25 assertions against
synthetic sysfs trees. It is now demonstrated on real hardware with the two
cases **at adjacent addresses on the same chip family**: `0x6a` has the
driver loaded and no node, `0x1e` has a node and no driver. A unit test
cannot produce that pairing and the shield did it by accident.

**A correction to entry 18.** It recorded that binding is silent in both
directions, because the SHT40AD1B bound and logged nothing. `st_lsm6dsx`
logs three lines on a successful probe. So the silence is a property of the
driver, not of the kernel, and "look in dmesg" fails only sometimes, which
is worse than failing always: a habit that works most of the time is the
one people keep.

**And the bench has a power problem.** Eight `Undervoltage detected` events
over about eleven hours, from `rpi_volt`, each lasting six to eight
seconds. Every capture on Wednesday and Thursday was taken on that supply.
Nothing in the data points at corruption, the noise floor having matched
the part's own specification and the calibration having held across two
ranges to 36 parts per million. But it is the first physical candidate for
Wednesday's single free-fall sample, which was left as a corrupted read
with no mechanism, and it should be fixed before criterion 4 measures
interrupt rates on a board that browns out twice an hour.

---

## 36. The FIFO batches, and I confirmed a hypothesis with a number the kernel had stopped counting

Entry on Thursday 1 October 2026.

**The buffered path runs.** 467 samples a second at 480 Hz with a watermark
of 64, 0.80 percent reader CPU, and timestamps the program correctly refuses
to call a latency measurement.

**And then I got the analysis wrong in a way worth keeping.** The watermark
1 run reported 100001 interrupts and I treated that as a rate of 10000 a
second. 100001 is the kernel's spurious-interrupt threshold. The count did
not reach it because that many arrived; it stopped there because the
watchdog disabled the line. The run was aborted, not completed.

On that number I wrote that the multiplier was constant across a
sixty-fourfold change of edge rate, 20.8 against 22.9, and that this
confirmed the ringing hypothesis "by something other than its own
plausibility". It did not. It confirmed it by an artefact of the thing that
had gone wrong.

| rate | watermark | real assertions/s | measured | multiplier |
|---|---|---|---|---|
| 480 | 1 | 480 | capped | not a measurement |
| 480 | 64 | 7.5 | 171.5 | 22.9 |
| 120 | 1 | 120 | 3816.8 | 31.8 |
| 120 | 64 | 1.88 | 95.9 | 51.1 |

22.9, 31.8 and 51.1. Not a constant, so not a fixed per-edge effect, and
the multiplier **grows as the assertion rate falls**, which is the opposite
of what ringing does. The mechanism is not identified and the record should
not pretend it is.

**What survives is that spurious edges dominate everywhere**, by twenty to
fifty times, in all four configurations. That does not depend on the
multiplier being constant and is the part that matters for the criterion.

**And the clean result is the one the wiring could not touch.** Spurious
interrupts are dismissed by the primary handler and never wake the reader,
so reader CPU is uncontaminated, and it behaves exactly as it should in
both dimensions at once:

- four times the sample rate costs four times the CPU, 0.20 percent at
  120 Hz against 0.80 at 480
- batching by 64 halves it at identical throughput, 0.40 against 0.20

Throughput is 96 to 97 percent of nominal in every run, the shortfall being
the samples still in the FIFO when the buffer closes.

**So criterion 4 splits along what the wiring touches.** What batching costs
the reader is measured, cleanly, and is the first result in this project to
come out exactly as theory says in two independent directions. What batching
saves the interrupt controller is not measurable here, and more runs will
not fix it.

**The habit worth naming, and it is the second time today.** A number that
arrives from a failure is not a measurement of the thing that failed. The
watchdog's threshold looked like a count because it was printed in the
column where counts go. The tell was there to be seen: 100001 is a round
number with a one on the end, which is what a limit looks like and what a
measurement almost never does.

---

## 37. The test was not catching the bug, it was asserting it

Entry on Thursday 1 October 2026, after the push.

**CI failed on both of the day's pushes**, and not where I expected. I had
predicted shellcheck, found an unquoted expansion one line past its
exemption, fixed it, and that was a real defect and not the cause. The
failing step was Tests, seven assertions in `tests/iio-probe-test.sh`:

    FAILED  '0x6a,LSM6DSV16X,...,no-driver-in-image' not in output
    FAILED  '0x3c,STTS22H,none,none,absent' not in output
    FAILED  '0x44,SHT40,sht4x,hwmon,...,working' not in output

Those are the exact errors corrected in the program after the bus was read
on Wednesday. The test expected the wrong address map, so correcting the
program broke the test.

**Which means the suite was defending the bug.** Twenty-five assertions
passed for two weeks while stating that the fusion IMU sits at `0x6a`. The
overlay bound that address for a day, the probe would have refused in
silence, and the whole time there was a green suite behind it. A fixture
that encodes a wrong fact does not merely fail to catch the error. It
makes correcting it look like a regression.

**And `0x3c` was never an address this bus could carry.** It is the
eight-bit form of the magnetometer's `0x1e`. A seven-bit table held an
eight-bit value and nothing noticed, because the only thing checking it was
a fixture built from the same misunderstanding.

**This is the third version of the same lesson today** and the sharpest.
Entry 36 recorded that a test built from synthetic sysfs directories can
check what a program writes and never what the kernel would make of it.
This is worse: a test built from synthetic directories can also check that
a program writes something false, and pass.

**`iio-rate` has no test file at all.** That is the plainest explanation for
the three defects found in it this morning, and it is a better one than any
argument about what tests can and cannot see.

**What the acceptance table should say about this.** Criteria 6 and 7 are
marked met on a laptop, because they are properties of the programs. They
are. But criterion 7's 25 assertions were asserting a wrong address map at
the moment they were recorded as met, and nothing in the table distinguishes
an assertion that checks a program's logic from one that pins its data to a
fiction.

---

## 38. The one program nothing compiles, read instead of run

Entry on Thursday 1 October 2026.

**`iio-stream.c` is compiled by nothing but a full Yocto image build.** CI
compiles six C programs by name and not this one, because it needs
`libiio` and the runner has none. It has no test file either. That is 253
lines with 33 library calls which nothing on either laptop, and nothing in
CI, would notice had stopped compiling. Criterion 5 is measured with it.

So it was read, since it cannot be run. Three findings, one of them a
defect.

**The defect: an unparseable count becomes an unbounded run.**

```c
case 'n': refills = (unsigned int)strtoul(optarg, NULL, 10); break;
```

No end pointer, no `errno`. `-n 4O` with a letter O returns 0, and 0 is
the documented value for "until interrupted". So a typo in the one
argument that bounds the run does not fail, does not warn, and produces
the opposite of what was asked for. `-b` has the same shape and fails
later and more loudly, at `iio_device_create_buffer`, which is the better
of the two outcomes and still not an error message about the argument.

This is the class of fault this project exists to find: not a crash, a
plausible behaviour that is not the requested one.

**An unstated assumption: the convert-and-widen pair is little-endian
only.** `iio_channel_convert` writes exactly the channel's storage width
into a zero-filled `int64_t`, and `widen` then reads the low bytes back
through a pointer of that width. On a little-endian host those are the
bytes convert wrote. On a big-endian one they are not. Every target here
is little-endian, so this is correct today and silently wrong the day it
is not, and the comment that explains the scratch does not say so.

**And the usage text omits the default.** It says `-n` takes a count and
that 0 means until interrupted, and does not say that leaving it out gives
40. A reader has to find that in the source.

**What is not wrong, and is worth recording because it was checked.** The
scan walk looked suspicious and is right: `p` starts at the first sample
of channel 0, which is offset into the first scan, so the loop appears to
run one scan short. It does not. The iteration count is the ceiling of
`(end - base0) / step`, which is exactly the number of scans whenever that
offset is smaller than a step, and it always is.

**None of the three is fixed here.** Changing C that nothing compiles is
the same mistake as adding the untested `--capture` was this morning, one
step further along: at least that could be run. The fix belongs with a way
to compile it, and the recipe warns that `libiio` 1.0 removed
`iio_buffer_refill` entirely, so this is 0.x code that a current
`libiio-dev` may refuse outright. That is a port, not an afternoon, and it
is now written down rather than discovered again by the next reader.

---

## 39. Criterion 3, and the one path the bench's fault cannot reach

Entry on Thursday 1 October 2026, after the board came back to the bench.

**3.341 microseconds, against a limit of 100.** The hrtimer-triggered
magnetometer buffer delivered 1003 samples in ten seconds at 100 Hz, with
0.40 percent reader CPU and zero interrupts.

`st_sensors` and `st_magn` built out of tree exactly as `st_lsm6dsx` did
this morning, four modules rather than two because `st_magn` does not
stand alone. The compatible was checked before compiling, as it must be:
`st_magn_i2c.c` carries `st,lis2mdl` and the settings give `.wai = 0x40`
at `.wai_addr = 0x4f`, and the part on the bus returns `0x40` from `0x4f`.

**And the same lesson arrived a second time from a different part.**
`LSM303AGR`, `LIS2MDL` and `IIS2MDC` share `wai = 0x40` in that table,
just as `LSM6DSV` and `LSM6DSV16X` share `0x70`. WHO_AM_I confirms a
family and does not name a part. Twice in one day, from two unrelated
drivers, which makes it a property of how ST numbers its parts rather
than a coincidence.

**This number is a latency measurement and the FIFO's is not.** The IIO
core stamps each scan as it pushes it, so 3.341 us is kernel scheduling.
The FIFO path's 0.128 us is the driver interpolating backwards from one
interrupt at the watermark, which is its arithmetic agreeing with itself:
a clock that reports the time it was set to always does. `iio-rate` warns
beside one figure and not the other, and the two are now measured side by
side rather than only described.

**Zero interrupts, and that is the finding worth keeping.** A software
trigger never touches GPIO24, so this path is the only part of the project
the bench's ringing interrupt line cannot reach. The design document chose
the magnetometer because it has no FIFO to confuse the comparison with.
That reason was good and it bought a second thing nobody planned: when the
interrupt wiring turned out to be the bench's worst fault, one criterion
was already immune to it.

**Throughput beat the buffered path.** 1003 samples where 1000 were asked,
against 96 to 97 percent on every FIFO run. The FIFO shortfall was samples
still in the hardware when the buffer closed; a software trigger has
nothing in flight to lose.

**The supply was checked either side.** Two undervoltage events before the
run and two after, so no brownout sits inside a figure measured in
microseconds. That check costs one command and is the difference between a
latency measurement and a story about one.

**And a fix from this morning was exercised on the device it was written
for.** `iio-rate` was corrected to discover scan elements rather than name
them, and the reason given at the time was that a hard-coded `in_accel_`
list would silently read nothing on the magnetometer. The channels line of
this run reads `in_magn_x in_magn_y in_magn_z in_timestamp`. First run on a
device with different channel names, and it found them.

## 40. Criterion 1, and four parts where the morning had one

*Thursday 1 October 2026, late afternoon.* `st_pressure` built into
`/root/build-magn` beside `st_sensors` and `st_magn`, which already shared
one `Module.symvers` there, and the LPS22DF bound. `iio-probe -v` now
returns four `working` rows where this morning it returned one:

    0x1e  LIS2MDL      st_magn      iio   claimed  loaded  lis2mdl
    0x44  SHT40AD1B    sht4x        hwmon claimed  loaded  sht4x
    0x5d  LPS22DF      st_pressure  iio   claimed  loaded  lps22df
    0x6b  LSM6DSV16X   st_lsm6dsx   iio   claimed  loaded  lsm6dsv16x_gyro lsm6dsv16x_accel

Four IIO devices, two triggers, `0x19` and `0x38` still `unsupported` and
`0x6a` still `not-bound`. Criterion 1 is met, recorded in
`docs/evidence/inventory-complete-2026-10-01.txt`.

**The six modules were one build, not three.** `st_sensors`, `st_magn` and
`st_pressure` are siblings in the same subtree of the kernel source, so one
Makefile naming all the targets produced all six `.ko` files against one
`Module.symvers`. The first two had been built that way in the morning and
the third was a target added to a list, not a new build. The afternoon's
work was four lines and a `grep` for the compatible string, after the
morning had spent hours getting the first one to link.

**`insmod` reported `File exists` and that was the right answer.** The
module was already loaded, which is a success indistinguishable in its
wording from a failure. The thing that settled it was `ls
/sys/bus/iio/devices`, which is the state rather than the report. This is
the same lesson as the `dd` entry in Project 2, arriving by a different
route: ask the system what it holds, not the tool what it did.

**And the criterion that was already met got better evidence than it had.**
Criterion 2 asks that the inventory list every sensor with its driver and
its status. It was marked met in the morning on a run reporting four
`no-driver-in-image` rows. The afternoon run of the same unedited program
reports four `working` and none missing. The inventory tracked the image
because it reads the system rather than a table, which is the property the
criterion is actually about, and the morning run alone could not have shown
that. Both files are cited now, and the README says why there are two.

## 41. The card is the build output, and it existed in one copy

*Thursday 1 October 2026, evening.* Asked to put a flash image of the card
on the skyhorizon desktop the way the finished projects do. The finished
projects do it with `./go archive`, and that turned out to be the wrong
tool for a reason worth writing down.

`archive.sh` keeps the OUTPUT OF A BUILD: a `.wic.bz2` BitBake wrote, with
a `.bmap`, a `.manifest` and a kas lock file beside it, and a rebuild line
that is one `git checkout` and one `kas build`. Everything it stores can be
made again from a commit. What it is really saving is the three hours.

Project 10's card is none of that. Raspberry Pi OS written by Imager, then
changed by hand on the board: a `linux-source-6.18` tree unpacked into
`/usr/src`, four out-of-tree ST drivers compiled against it, modules loaded
by `insmod` rather than by any recipe, programs placed by hand, and
measurements accumulating under `/var/lib/bench`. No commit here describes
it and no command here rebuilds it.

**So for this project the card is not a copy of the artefact, it is the
artefact**, and it existed in exactly one place, in one reader, on one
bench. That is the same position Project 2 was in on Saturday 19 September
2026, when the only board that booted was the only project whose work
existed nowhere but inside a WSL virtual disk.

`scripts/card-archive.sh` stores it with the same layout, the same stamp
and the same `PROVENANCE.txt` fields as the Yocto side, so the two sort and
read together, and with a `-card` suffix on the directory because the two
are put back by different tools. `tests/card-archive-test.sh` exercises it
with a regular file as the source, so it needs no card, no reader, no
`usbipd` and no root: 52 assertions.

### conv=noerror,sync was in the first draft and had to come out

Both halves were wrong, and both were wrong silently.

`noerror` turns an unreadable block into zeros and carries on. A card with
a failing sector would be archived as a card with a hole in it, and nothing
would say so. Worse: the verification reads the source a second time the
same way, gets the same zeros, and AGREES. The check would pass on a
corrupt archive. A read error has to be a refusal, because the one moment
the operator can act on it is before the card is reused.

`sync` pads the final short read out to the block size. A card is rarely a
whole multiple of 4 MiB, so the archive would be a few megabytes larger
than the card it came from, and `dd` writing it back reports a failure on
the last block. The operator then has to decide whether a restore that
ended in an error worked.

**And the archive is compared against the card, not against itself.**
Decompressing what was written proves the gzip stream is complete; it does
not prove it is a copy of anything. So the source is read a second time and
hashed, and the two are compared. It costs a second full pass and it is on
by default, because Project 2 recorded `dd` reporting complete success
three times while the bytes went to three different places.

### The test proved itself by failing, and failed to report it

`conv=sync` was put back on purpose to watch the round-trip assertion
catch it. The assertion never ran. The program refused first, which is
correct, and the suite was running the archive as a bare command
substitution under `set -eu`, so the whole file stopped at that line and
printed ten green `ok` lines with no tally and no `FAILED`.

A suite whose output on a real defect is a short green list is worse than
no suite, because a short green list reads as a pass. It now has a
`must_succeed` beside its `refuses`, which reports the refusal, prints the
program's own output and exits with the tally. Re-running the broken
version then gives `10 passed, 1 failed` and the reason.

That is the second time today a test has been found to be shaped so that it
could not report the thing it was written for. Entry 37 was a test
asserting the bug; this one was a test that could not speak.

## 42. The backup that looked like a backup

*Thursday 1 October 2026, evening.* The first real run of
`scripts/card-archive.sh` was launched in a foreground WSL shell. The tab
was closed while it worked. `dd` reached 6,677,331,968 of 15,728,640,000
bytes, forty-two per cent, at a steady 15 MB/s, and died without printing
anything.

What it left behind was a 1.55 GB file called
`10-iio-iks4a1-card-2026-10-01.img.gz`, in the right store directory, under
the right stamp, **named exactly as a finished archive is named**. No
`PROVENANCE.txt`. No `SHA256SUMS`.

Then came the message: *now we are ready to wipe out and replace the
contents of sd card, we go ahead.*

**The only thing standing between that and the loss of the four built
drivers was checking for the record files rather than for the image.** A
directory listing shows a plausible multi-gigabyte `.img.gz` and nothing
about it says incomplete. In a week it would say even less. 1.55 GB is not
even a suspicious size: a 14.6 GB card whose rootfs is largely unwritten
compresses to about that, so the number argues for completeness rather than
against it.

### The defect was mine and it was in the naming

A program whose failure leaves something that looks like success. That is
the same shape as journal 36, where a count that had stopped increasing was
read as a rate, and as the `insmod File exists` of journal 40, where a
success is worded like a failure. This one is worse than both, because the
thing it misleads about is whether a backup exists, and the moment it
misleads you is the moment before you destroy the original.

The fix is not a line in a document. The image is now written as
`<name>.img.gz.partial` and renamed only after the comparison against the
card succeeds, so an interrupted run leaves a file that cannot be read as
an archive. `.partial` is also invisible to the duplicate-image guard,
because `*.img.gz` does not match `*.img.gz.partial`, so a killed run does
not block its own retry.

**And the definition is now written down where it was previously assumed:**
an archive is finished when `PROVENANCE.txt` and `SHA256SUMS` are both
present and `sha256sum -c SHA256SUMS` reports `OK`. The image file alone
counts for nothing.

### Three diagnostics, and what each one could and could not say

Worth recording because two of them were inconclusive and saying so was the
useful part.

`ls -l` showed only the image, which looked like a clean partial. It was
hiding `.dd.log`, a dotfile, and `ls -la` found it.

The presence of `.dd.log` was inconclusive. The script deletes it on the
line after the `dd` finishes, so a run killed *during* `dd` leaves it
exactly as a failed read would. It separates nothing on its own.

What separated them was the log's own last lines, read through
`tr '\r' '\n'` because `status=progress` rewrites one line with carriage
returns. The last entry was a progress figure at forty-two per cent with
**no I/O error above it**. A failing sector prints one. So the card was
healthy and the cause was the terminal, which is the difference between a
retry and a replacement.

### The reader does not keep its device letter

The card came back from a usbipd re-attach as `/dev/sde` where it had been
`/dev/sdf` forty minutes earlier, same reader, same laptop, same port. The
re-run was handed over with the letter re-read rather than reused, which is
the only reason it did not image whatever `sdf` had become.

`/dev/sdf` had by then stopped existing at all, and the archiver refused
with `no such source` twice before the attachment was noticed. Both
refusals were correct and cost nothing.

### And a test that credited the wrong mechanism

The new assertion "the stale .partial was discarded" passed. Removing the
`rm -f "$staging"` it was supposed to pin left it passing, because the
write redirects onto the same path and truncates the file regardless. The
cleanup line is a notice, not a mechanism.

Removing the whole notice block did fail an assertion, the one checking that
the run says a previous attempt died, so that part is pinned. The test now
says in its own comment which half is load-bearing and that the discard is
true by truncation.

**Three tests in one day, each shaped so it could not do its job.** Journal
37 asserted the bug. Journal 41 could not report a failure. This one gave
credit to the wrong line. The common cause is writing the assertion from
what the code does rather than from what would have to break.

## 43. A complete archive the same size as a 42 per cent one

*Thursday 1 October 2026, evening.* Two numbers, and they are the reason
the `.partial` naming of journal 42 is not merely tidy.

| | bytes | what it was |
|---|---|---|
| Attempt 2, killed at 42 per cent | 1,546,649,600 | less than half a card |
| Attempt 3, complete | 1,562,322,561 | the whole card |

**One per cent apart.** The finished archive is barely larger than the
fragment, because the written data on a Raspberry Pi OS card sits near the
front and the remaining 58 per cent is unwritten ext4 free space, which is
zeros, which gzip collapses to almost nothing.

So for a card image, **file size carries no information about
completeness.** Not "little", none that can be acted on. A directory
listing of a half-read card and a listing of a finished one are the same
listing to within a rounding error, and `du -h` prints `1.5G` for both.

This also kills the reasoning I used at the time. When the first partial
appeared I argued that 1.55 GB "is not even a suspicious size, a 14.6 GB
card whose rootfs is largely unwritten compresses to about that, so the
number argues for completeness rather than against it". That was right about
the compression and wrong about what follows from it: the number argues for
nothing in either direction. Only `PROVENANCE.txt` and `SHA256SUMS` carry
that information, which is exactly why they are written last and why they,
not the image, are now the definition of a finished archive.

## 44. The link was being told to save power

Three attempts at the same seventeen minute read.

| Attempt | Reached | Elapsed | Rate | Ended by |
|---|---|---|---|---|
| 1 | 6,677,331,968 bytes, 42 per cent | 448 s | 15 MB/s | the link dropped |
| 2 | 7,860,125,696 bytes, 50 per cent | 496 s | 16 MB/s | the link dropped |
| 3 | 15,728,640,000 bytes, all of it | 828 s | 19 MB/s | finished |

**Neither failure printed an I/O error**, which is what separated a dying
card from a dying link and was the only diagnostic that distinguished them.
`usbipd list` showed the reader still under `Connected` with its state back
to `Shared`, so the device was never lost to Windows, only to WSL.

Between attempt 2 and attempt 3, one setting changed: USB selective suspend
disabled in the active Windows power plan, with `powercfg`, plus clearing
*Allow the computer to turn off this device to save power* on every USB hub
in Device Manager.

**The rate is the corroboration, not just the completion.** 15 and 16 MB/s
became 19. A link being periodically told to power down is slower before it
is cut, so the throughput moved for the same reason the read survived. One
observation would have been a coincidence; the two together are a
mechanism.

**`--auto-attach` is worth having and does not solve this.** It re-attaches
the reader within seconds of it reappearing, which it did. It cannot rescue
a read already in flight, because the file descriptor dies with the device
and `dd` has already failed by the time the device is back. Resumability
would have solved it; that is a different program, and it was not needed in
the end.

### Two smaller facts worth not rediscovering

**The reader does not keep its device letter.** Same reader, same port,
same laptop: `/dev/sdf`, then `/dev/sde` forty minutes later. The archiver
refused `no such source` twice before anyone noticed the attachment had
gone, and both refusals were correct and cost nothing. Every hand-over now
re-reads the letter with `lsblk` instead of reusing the one from the last
command.

**Tailing the wrong log looks exactly like a program that has stopped.**
`card-archive-2026-10-01.log` had been complete for twenty minutes while it
was being watched for progress that was going to `card-verify-2026-10-01.log`,
and the verify had not in fact been started. A finished log is
indistinguishable from a stalled one, which is the same shape as the two
entries above: the absence of new information read as information.

## 45. Criterion 5, across the network, on the wrong sensor for the right reason

*Thursday 1 October 2026, 19:45.* Identical columns, 1000 samples each way,
10.044 s locally and 10.074 s from the laptop. The counts are equal rather
than within the one per cent the criterion allows, and the only argument that
differed between the two runs was `-u ip:192.168.92.154`.

libiio 0.26 on both hosts, which is worth more than it looks: a difference in
the column set would then be the program's doing rather than a library
difference, and that is the property the criterion exists to establish. The
`iio_buffer_refill` concern written into `bench-iio_0.1.bb` is settled for
0.26, the last of the 0.x line, and still open for any host on 1.x.

**The timestamps corroborate the wall clock.** 9,994,330 ns between
consecutive samples locally, 9,989,105 ns remotely, 9,989,990,862 ns from
first to last over 999 intervals. All 100 Hz to better than a part in a
thousand, from the kernel's own clock rather than from the shell's. Two
independent clocks agreeing is the reason to believe either.

### It was measured on the magnetometer, and that is stated rather than glossed

`iio-stream` defaults to `lsm6dsv16x_accel`. The accelerometer was tried
first and answered `refill failed: Connection timed out`, and
`/proc/interrupts` says why without ambiguity:

    185:   0   0   0   0   pinctrl-bcm2835  24 Edge   lsm6dsx

Zero on all four CPUs, including during the attempt. The LSM6DSV16X has a
hardware FIFO and its own interrupt, so `st_lsm6dsx` registers a trigger of
its own and the buffered path uses that rather than any software trigger.
With the line delivering nothing, that path cannot complete a refill and no
software change reaches it.

So criterion 5 is met for the local-against-remote property it is about, and
it is **not** evidence that the accelerometer streams over the network. The
criterion names no device and `-d` exists, so the substitution is legitimate;
what would not be legitimate is leaving it unsaid.

**The fault has reversed direction, and that is the finding.** This morning
IRQ 185 reached 100001, the kernel's spurious-interrupt threshold, and the
watchdog disabled the line. Tonight it reads 0 and the line is silent. Same
jumper, same shield, same pin, opposite failure. A wire that both rings and
goes open is a connection problem, not a threshold problem, which argues for
shortening it or adding series resistance rather than for filtering in
software. Three entries have now circled criterion 4's wiring; this is the
first one that constrains the mechanism.

### The first remote attempt failed on an ordering trap

It connected, answered, and listed three devices: `cpu_thermal`, `rpi_volt`
and `sht4x`. All three are hwmon devices libiio surfaces through its hwmon
backend, and not one of the four IIO devices appeared.

`iiod` enumerates once, at startup. systemd had started it at boot, which was
before any of the out-of-tree modules existed. `systemctl restart iiod` fixed
it in two seconds.

**That is guaranteed to bite the next person following RESUME.md**, because
that document loads drivers after boot and systemd starts `iiod` at boot. The
symptom reads as a network problem and the fault is a stale service. The
local run was unaffected because a local context is rebuilt every time a
program starts, which is exactly why the local half passed first and made the
remote failure look like the network.

`systemctl restart iiod` is now the last line of the reload sequence.

### What the archive does not contain

The card image was taken at 18:08 and this work happened between 19:30 and
19:45, so libiio, `iiod`, the compiled `iio-stream` and `local.csv` are not in
it. Nothing irreplaceable sits outside it: the install is one `apt-get`, the
source is one `curl` from the repository, the compile is one `cc` line, and
the numbers are in the evidence file. Said here because an archive with a
timestamp invites the assumption that it holds everything, and this one holds
everything that cost anything.

## 46. The part that was never unsupported, only undeclared

*Thursday 1 October 2026, about 20:00.* `0x6a` binds. Six IIO devices, five
`UU` in `i2cdetect` where the morning had one, and **no `not-bound` row left
in the inventory**.

The backlog question since Wednesday 30 September 2026 was whether
`st_lsm6dsx` carries a compatible for the LSM6DSO16IS. The source on the card
answers it five ways: `st_lsm6dsx_i2c.c:126` has
`.compatible = "st,lsm6dso16is"`, line 161 has it in the I2C ID table,
`st_lsm6dsx_core.c:1448` has the settings entry, `st_lsm6dsx.h:38` has the
name, and `Kconfig:27` lists it.

So the driver already loaded on that board could always have driven that part.
**What was missing was any statement that a device is there.** I2C does not
probe blind: a client comes from a device-tree node, from board info, or by
hand. No node declares `0x6a`, so no client was ever created, so nothing was
ever probed. One line fixed it:

    echo lsm6dso16is 0x6a > /sys/bus/i2c/devices/i2c-1/new_device

and when `st_lsm6dsx_i2c` loaded afterwards it probed the waiting client, with
regulator and mounting-matrix notes and **no WHO_AM_I complaint**. That
absence is the positive evidence: the driver reads the identity register and
refuses a mismatch, so a clean probe says the part really is an LSM6DSO16IS.
Two earlier entries recorded that WHO_AM_I names a family and not a part;
here the driver's own check is the discriminator that a raw register read
could not be.

### The program had been pointing at this for two days

`iio-probe` called `0x6a` `not-bound`, and its own help text for that state
reads: *driver present, nothing matched it: look at the overlay, not the
image.* That verdict was right, that advice was right, and the overlay is
exactly where the gap was. It printed that line in the morning, in the
afternoon and again this evening before anyone followed it.

Worth sitting with, because the lesson is not about I2C. The tool had already
done the diagnosis and the failure was in reading its output as a status
rather than as an instruction. Three criteria were closed in between by
building drivers, which was real work, and none of it was what this row
needed.

### What it corrects, and what it does not

The row's own expectation note still reads "ISPU part, confirm the compatible
exists", which is now satisfied and stale. Left alone tonight on purpose:
`tests/iio-probe-test.sh` asserts on that table, so changing the note means
changing the test in the same commit, and that is not work to start while a
board is being packed away.

And it does not survive a reboot. `new_device` creates a client that lives
until the next boot, so the line now sits in the reload sequence in
`RESUME.md`. The durable form is a device-tree node for `st,lsm6dso16is` at
`0x6a` in the shield's overlay, beside the ones already declaring `0x1e`,
`0x5d` and `0x6b`. That is not written.

### The two remaining rows are now suspect, and the obvious test is invalid

`0x19` LIS2DUXS12 and `0x38` STTS22H are marked `unsupported`, and that
verdict was reached the same way `0x6a`'s was: nothing bound, so nothing was
assumed to exist. `0x6a` has just demonstrated that "nothing bound" can mean
"nothing was declared".

**The obvious check is not available and that matters more than the question.**
Grepping `/usr/src/linux-source-6.18` would be wrong, because only selected
directories were ever extracted from it with `tar --wildcards`. A missing file
there means the file was not extracted, and reading that as "no such driver
exists" would be precisely the same error as reading `not-bound` as
"unsupported", in a new place, on the same evening it was learned.

The valid questions are different ones: `modules.alias` and the module tree in
`/lib/modules` say what this kernel can bind, and the source tarball says what
6.18 contains. Neither was asked before the board came off the bench, and both
are on the backlog rather than guessed at here.

## 47. The control, and two of my inferences it kills

*Thursday 1 October 2026, late evening.* One command, three times, differing
only in whether the wire was plugged in at the shield end.

| run | green wire at CN9 pin 6 | interrupts/s | samples in 10 s |
|---|---|---|---|
| A | connected | 244.90 | 4672 |
| B | connected | 225.60 | 4672 |
| **C** | **disconnected** | **0.00** | **0** |

In run C the Pi end stayed on header pin 18 and the shield end hung in air.
`/proc/interrupts` did not advance one count.

**That is the first measurement of this fault with a floor under it**, and it
should have been the first measurement of it at all. Everything before it
compared two runs that both had the fault in them.

Three things fall out:

**GPIO24 picks up nothing on its own.** An unconnected input on this header,
beside a 400 kHz bus, gives exactly zero edges in ten seconds. So the hundreds
counted in A and B are not an antenna effect, they arrive down the wire.

**The FIFO path is entirely interrupt driven.** No interrupts gives no
samples, not fewer samples. So the sample count can never distinguish a
healthy line from a noisy one, and reading 4672 as reassurance would have been
a mistake.

**The storm is real and it is thirty times.** 7.5 per second expected at 480 Hz
with watermark 64, 225.60 measured, against a floor now known rather than
assumed.

### What it kills, both mine

**"The interrupt line delivers nothing."** Written a few hours earlier when
`iio-stream` timed out on the accelerometer with IRQ 185 at `0 0 0 0`. The zero
was real and the inference was wrong. The part was in power-down, where it
never asserts INT1, because `iio-stream` does not set the sampling frequency
and nothing else had. **A quiet line and a dead line produce the same count**,
and nothing in that observation separated them. The separating experiment is
run C, which I did not think to do until the numbers stopped making sense.

**"The fault has reversed direction."** Built on the first, and worse for
being more interesting. It said 100001 edges in the morning and zero in the
evening were one wire failing two opposite ways, and concluded that something
which both rings and goes open is a connection problem rather than a threshold
problem. The premise was an artefact of a sleeping sensor. There was no
reversal. One continuous fault, measured twice awake and once asleep.

The conclusion survives, because run C points the same way. But it survives on
run C and not on that reasoning, and **an argument that reaches a right answer
from a false premise is worth less than no argument**, because it will be
trusted the next time it is wrong. Two entries ago I wrote that confirming a
hypothesis with a number the kernel had stopped counting was the worst
analytical error of the two days. This is the same error with the sign
flipped: a number the sensor had never started producing.

### The wiring slip that made it visible

Joseph noticed mid-session that the jumper had gone back onto header **pin 16,
GPIO23**, rather than **pin 18, GPIO24**, one position along the same row. I
took that at face value and built an explanation on it: a floating GPIO24
picking up noise, which would have explained 244.90/s neatly.

Run C refutes it. A floating GPIO24 reads zero. So the line was electrically
complete in runs A and B whatever the pin label said, and my floating-input
story lasted about four minutes before its own control destroyed it. Worth
recording as the third wrong explanation of the same observation in one
evening, all three of them plausible and two of them mine.

### The defect it uncovered on the way

`iio-stream` does not configure the device. It opens a buffer on whatever the
part is already set to, and the LSM6DSV16X powers up in power-down, so on a
freshly loaded driver the buffer never fills and the refill times out. Once
`iio-rate` had left `sampling_frequency` at 480, the identical command
returned 1001 lines in 2.198 s.

That precondition is real, unstated, and it is what sent criterion 5 to the
magnetometer. **The substitution was never forced by the wiring.** Criterion 5
is unaffected, since the local-against-remote comparison never depended on
which sensor it used, but the reason recorded against it was wrong and is
corrected in the row and in the evidence file.

### What is still unknown

The mechanism. Thirty extra edges per real assertion is a number, not a cause.
Reflection on an unterminated line, contact bounce at either connector and
coupling from the adjacent SCL wire all produce it. Ruled out: pickup by the
GPIO pin, at zero.

Next, in order of cost: the same run with the wire as short as it physically
goes, then with a few hundred ohms in series at the CN9 pin 6 end. If those
move the number the cause is the wire; if they do not it is a connector or the
shield. One capture on a scope at CN9 pin 6 would answer it outright, and
there is no scope on this bench.

## 48. Criterion 4 names both rates, and 416 Hz may not have been a mistake

*Thursday 1 October 2026.* Joseph settled the wording: the criterion names
**416 Hz or 480 Hz**, whichever the part under test offers.

Both satisfy its own arithmetic, which is the only thing that was ever at
risk. At watermark 64, 416/64 = 6.5 and 480/64 = 7.5 interrupts per second,
both under the limit of 8. At watermark 1, 416 and 480 per second, both over
the floor of 400. The thresholds were never rate-specific; one number in the
prose was.

**And 416 Hz looks less like an error than it did this morning.** It is the
classic ST IMU ladder, 12.5/26/52/104/208/416/833, which the LSM6DSV16X does
not use. For three days the entry in the journal read as a criterion written
from the wrong datasheet. The shield carries a second IMU, and `0x6a` only
started producing `lsm6dso16is_accel` and `lsm6dso16is_gyro` a few hours
earlier, after two days of being recorded as unbound and then as unsupported.

So the likelier story is that the criterion was written for a part that was on
the board the whole time and had no driver attached to it. **Which is worth
noticing as a pattern rather than a coincidence**: the same undeclared device
produced a wrong inventory row, an open backlog question, and what looked like
a wrong number in an acceptance criterion. One missing device-tree node, three
symptoms, none of which pointed at each other.

### What is not claimed here

That the LSM6DSO16IS offers 416 Hz. It is the classic ladder and that part
usually carries it, and this project has already recorded twice that a family
is not a part. One command answers it on the board:

    cat /sys/bus/iio/devices/iio:device3/sampling_frequency_available

Until that is read, 416 Hz in the criterion is a rate the criterion permits,
not a rate anything here has been measured at.

And its FIFO half would need wiring that does not exist. UM3239 Rev 5 Table 4
puts the LSM6DSO16IS INT1 on **CN8 pin 6** and its INT2 on CN9 pin 8, while the
only interrupt wire on this bench runs from CN9 pin 6, the LSM6DSV16X INT1, to
Pi header pin 18. Measuring the second IMU's watermark interrupts needs a
second jumper to a free GPIO and an overlay entry declaring it, on top of the
device-tree node that `0x6a` already needs to bind at boot.

Recorded as a route rather than a plan. The first thing criterion 4 needs is
still the 30 times storm on the wire that already exists.

## 49. Criterion 8 was not defective, and the data had said so for a day

*Thursday 1 October 2026.* Asked whether to restate criterion 8 or leave it
marked defective, Joseph answered neither: *i can wobble it within 3 degrees.*

He is right, and the project's own captures already proved it. **`roll90b`
passes.** Held 2.2 degrees off axis, it reads roll +91.33 and pitch +0.32,
both inside the 3 degree tolerance. One of the four poses met the criterion
as written and nobody noticed, because the verdict had been reached from the
other three.

| pose | off axis | roll | pitch |
|---|---|---|---|
| flat | | +0.77 | +0.32 |
| roll90 | 4.4 deg | +94.40 | +0.10 |
| **roll90b** | **2.2 deg** | **+91.33** | **+0.32** |
| pitch90 | 12.1 deg | +148.73 | -77.93 |
| pitch90b | 6.8 deg | +177.24 | -82.43 |

So "a board propped on a free edge sits 2 to 12 degrees off the axis" was a
description of the worst poses presented as a property of the method. The best
one is inside tolerance. The fixture was never the limit; the propping was.

### And the ill-conditioning argument was right in mechanism and wrong in size

The second reason given for calling the criterion defective was that roll is
ill-conditioned near a pitch of 90 degrees, so a tolerance on it is a tolerance
on a number the geometry does not fix. The mechanism is real: at exactly 90,
gravity lies along the roll axis and roll is unobservable.

But the size was never checked against this bench's own noise floor, which is
**0.36 mg on X and Y**, measured on Wednesday 30 September 2026. At an angle
d away from exact 90 the horizontal component is sin(d) g, so the roll
uncertainty is about noise over sin(d):

    d = 3 deg    0.052 g      0.40 deg
    d = 1 deg    0.0175 g     1.18 deg
    d = 0.5 deg  0.0087 g     2.37 deg
    d = 0.2 deg  0.0035 g     5.9 deg

**Roll exceeds a 3 degree tolerance only inside about 0.4 degrees of exact
90**, which no hand-held pose will reach. The argument blocks a 0.1 degree
criterion and says nothing about a 3 degree one.

That is the second time today an objection of mine has been right about a
mechanism and wrong about whether it matters, the first being the interrupt
line. Both had the same shape: a real effect, named correctly, with no
arithmetic put against the actual numbers on this bench. **A mechanism without
a magnitude is a hypothesis wearing a conclusion's clothes**, and it is
more persuasive than a wrong number because it cannot be checked at a glance.

### The verdict changes, the count does not

Criterion 8 moves from **criterion defective** to **not met, re-measurement
pending**. Project 10 still reads seven of nine, but the eighth is now an
honest "we have not taken this measurement properly" rather than "this
criterion cannot be satisfied", and those are very different statements about
whose fault it is.

The restatement proposed in the evidence is not adopted and not withdrawn. It
remains a better criterion in one respect, since orientation error against
measured gravity does not care how squarely the board was held, and it is no
longer needed to make this one passable.

### What the re-measurement needs

Four poses held by hand rather than propped: flat, 90 about roll each way, 90
about pitch each way. The pose-quality check is already printed beside each
capture, the gravity magnitude, which reads 1.0055 and 1.0059 g on the two
good poses and 0.9960 on the worst. A pose whose magnitude is within a few mg
of 1 g and whose off-axis figure is under 3 degrees is a pose worth scoring.

The board is dismantled, so this waits for the next bench session, alongside
the two wire experiments criterion 4 needs.

## 50. Three addresses, one class of miss, and the program nothing compiled

*Thursday 1 October 2026, late.* Joseph brought the straps, the compatibles
and ST's own overlay, and they turn `0x6a` from a one-off into a pattern.

| 7-bit | part | strap | compatible | state |
|---|---|---|---|---|
| `0x6a` | LSM6DSO16IS | SB35, ADD D5h | `st,lsm6dso16is`, mainline | **node added** |
| `0x19` | LIS2DUXS12 | SB20, SA0 high, ADD 33h | `st,lis2duxs12` | node pending a check |
| `0x38` | STTS22H | only address, ADD 71h | `st,stts22h`, **not mainline** | node deliberately not added |

ST's shield overlay instantiates `lis2duxs12@19` and `stts22h@38` beside the
four this repository already declares. **None of the three ever needed a
driver written. All three needed a node.** The inventory called two of them
unsupported and one not-bound, and `unsupported` was wrong twice.

### The node that went in, and the two corrections to the snippet

`lsm6dso16is@6a` is added, because the condition this overlay set for itself
has been met rather than waived: confirm the compatible is in the running
kernel rather than assuming it. Confirmed against the source on the card and
then demonstrated by `new_device` and a clean probe.

Two things in the proposed node did not survive.

**`interrupts = <IRQ_TYPE_EDGE_RISING>` is one cell where the binding takes
two**, a GPIO number and a flag, and the macro is unavailable in an overlay
compiled without the C preprocessor. The working node above it reads
`interrupts = <24 1>`.

**More seriously, the node must have no interrupt property at all.** UM3239
Rev 5 Table 4 puts this chip's INT1 on CN8 pin 6 and its INT2 on CN9 pin 8,
and neither is wired. The only interrupt jumper on this bench runs from CN9
pin 6, which is the LSM6DSV16X's INT1, to GPIO24. Pointing this node at
GPIO24 would claim a line this chip does not drive **and** share an IRQ with a
node that does, so it would break a part that currently works in order to
half-enable one that does not. Without the property, the sysfs read path
works and the buffered FIFO path does not, which is the honest state.

### Why 0x38 is not getting a node tonight

`st,stts22h` is in ST's IIO tree rather than in mainline. On a mainline-only
kernel the node would be created, nothing would bind to it, and the part
would be invisible with no message anywhere. **That is exactly the failure
this overlay's own header warns about**, and adding the node would trade an
honest inventory row for a silent one. The row stays as it is until either
the driver is in the running kernel or the tree is.

`0x19` waits on the lighter version of the same check, and the check is
`modules.alias` and the module tree, **not** a grep of `/usr/src`: only
selected directories were extracted from `linux-source-6.18`, so a missing
file there means a missing extraction.

### The ODR defect, and the gap that let it ship

`iio-stream` armed a buffer on a part in power-down. The kernel accepts that
without complaint: scan elements enabled, buffer created, no sample ever
produced, FIFO never reaching its watermark, interrupt never firing,
`iio_buffer_refill` blocking until it times out. The program then reported
`refill failed: Connection timed out`, **which names the symptom of the
symptom and points the reader at the hardware**, and that is what it did: an
evening, two wrong journal entries and a withdrawn claim about the interrupt
line.

It now reads `sampling_frequency`, takes `-r HZ`, and when it finds a part
stopped it sets the lowest rate the part offers and says so on stderr, loudly,
with the available list. A device with no such attribute is left alone,
because a trigger-driven part is clocked by its trigger and this is not its
precondition.

Setting it rather than refusing is a deliberate choice and not obviously the
right one. A measurement program that quietly reconfigures the thing it
measures is how a capture becomes unexplainable a week later. The compromise
is that it never does it silently and the operator can pin the rate, and the
alternative, a refusal, leaves the common case needing two commands where one
would do.

**And the gap underneath all of it: nothing compiled this file.** Journal
entry 38 was titled "the one program nothing compiles, read instead of run",
and it stayed true for another day. CI builds six C programs with `-Werror`
and this was not among them. It was first compiled by hand on the board and
in WSL, both times after the defect had already cost its evening. A C file in
a repository whose CI compiles six other C files is not covered by that CI, it
is surrounded by it. CI now builds it, with a version guard that fails on
libiio 1.x, where `iio_buffer_refill` no longer exists.

**This change has not been compiled.** There is no C toolchain on the
authoring laptop, so CI is its first build, which is the ordering this bench
has agreed to and is worth stating rather than implying.

## 51. One cause, three wrong mechanisms, and a withdrawal that was itself wrong

*Thursday 1 October 2026, late.* The accelerometer's buffered path failed,
and over one evening I gave it three different explanations. All three were
wrong. The cause was a wire I had asked to be unplugged for a control
experiment and never asked to be plugged back in.

| | explanation | killed by |
|---|---|---|
| 1 | the interrupt line delivers nothing | iio-rate driving 2449 interrupts |
| 2 | the part is in power-down, iio-stream sets no rate | sampling_frequency reads 7.500000 after a reload |
| 3 | the buffer takes longer to fill than libiio's timeout | 4 samples at 7.5 Hz failing too |
| 4 | something rate-dependent | 4 samples at 480 Hz failing too |

And then the wire went back on CN9 pin 6, and every one of those commands
worked: 201 lines in 0.504 s at 480 Hz, and 5 lines in 0.873 s at 7.5 Hz
with a four-sample buffer.

**Explanation 1 was right.** I withdrew it in journal 47 and the withdrawal
was the error. Worse, I withdrew it on good evidence: `iio-rate` really did
drive 2449 interrupts down that line, so the line really does work. What I
concluded from that was "therefore the line was not the problem", and the
correct conclusion was "therefore the line works when it is connected".

### What was actually established, and when

The control run is the only measurement that ever mattered here, and it
said everything on its first printing:

    wire connected      225.60 interrupts/s   4672 samples
    wire unplugged        0.00 interrupts/s      0 samples

**Zero interrupts gives zero samples, not fewer samples.** I wrote that
sentence into the evidence file myself, three explanations ago, and then
spent the rest of the evening proposing mechanisms that all required the
interrupt to be working.

### Two things the detour did establish, both by accident

**`sampling_frequency` never reads 0 on `st_lsm6dsx`.** After `rmmod` and
`insmod` it reads 7.500000. The driver initialises its cached rate rather
than reporting the chip's reset state, so the power-down premise was not
merely unproven, it was false, and it had been published in a commit message
and a code comment before anyone looked at the attribute.

**The ladder is eight rates, not nine.** The driver offers
`7.5 15 30 60 120 240 480 960`. This project had been writing 1.875 at the
front of it since Wednesday, from the datasheet rather than from the driver.

### What the code keeps and what its comment now says

The `-r` flag stays: an explicit rate is worth having and costs nothing. The
zero-rate branch stays too, because the condition is real for a driver that
does expose a stopped state, and the policy is now the first rate at or
above 100 Hz rather than the lowest available, so a forgotten `-r` cannot
"succeed" into a 1.875 Hz stream that reads as a hang.

What changed most is the comment above it. The first version told a
confident story about an evening it did not cause. It now says the branch
has never fired on this bench, names all three wrong diagnoses, and points
at the wire. **Code that carries a false account of why it exists is worse
than code with no comment**, because the next reader inherits the
conclusion without the evidence.

### The thing to take from this

Every one of the three wrong mechanisms was plausible, internally consistent
and testable, and I tested each one and moved on to the next without ever
re-establishing the baseline. The baseline had changed under me because I
changed it, deliberately, as an experiment, and then forgot.

A control is not finished when it produces its number. It is finished when
the system is put back.

## 52. The tool that was right, taught to say so, and a criterion that now fails itself

*Thursday 1 October 2026, late.* Three changes, and the first is the one
that would otherwise have reopened a two-day mistake on every run.

### iio-probe calls undeclared parts undeclared

`PARTS` carried `driver=none` for `0x19` and `0x38`, and `driver=none` was
wired straight to `unsupported`. Both parts are supported. ST's own shield
overlay instantiates `lis2duxs12@19` and `stts22h@38`. The word was wrong
twice and the table would have kept printing it.

Four verdicts where there were two: `undeclared`, `out-of-tree`,
`no-driver-in-image`, `unsupported`. The table gained the device-tree
compatible and which tree the driver lives in, and `client_at` was added,
which asks the question nothing had asked: **has anything ever created an
I2C client at this address at all?** No client means no node, and no node
means the overlay.

`out-of-tree` is asked before the image question, because "built without the
module" is the wrong answer for a driver no mainline image could carry. It
is declared in the table rather than probed, since an absent module cannot
distinguish "not in this image" from "not in any image".

### The 0x19 check was run and it failed

The condition the overlay set for adding a node, confirm the compatible is
in the running kernel, was honoured for `0x6a` and has now been honoured for
`0x19` with the opposite result:

    grep -iE "lis2duxs12|stts22h" /lib/modules/$(uname -r)/modules.alias
    find /lib/modules/$(uname -r) -iname "*lis2dux*" -o -iname "*stts22*"

Both empty. `st_lis2duxs12` is in mainline and **not in this image**, so the
node stays out: it would be created, bind to nothing, and leave the part
silent rather than absent. Same failure as `0x38`, different cause, and the
two now read differently because the fixes differ. One needs an image that
carries the module; the other needs the driver vendored the way
`st_lsm6dsx` was.

This is the first time on this bench that a check set as a precondition has
been run and come back negative, and the node was not written anyway. That
is the whole value of writing the precondition down.

### Criterion 4 is now arithmetic the program does itself

A hardware FIFO at rate R with watermark W interrupts R/W times a second.
`iio-rate` printed the measurement beside it and left the division to
whoever was reading, on a bench where the two are thirty times apart. It now
prints `expected`, prints the ratio, and **exits 3 above a ratio of 2**.

Two is loose deliberately. The point is to catch a line that rings, not to
fail a run that batched slightly differently, and the only fault this has
ever seen is a factor of thirty.

The failure message says what a healthy line reads, 0.00 per second and no
samples with the wire unplugged, because that control is the thing that
turned this from an argument into a measurement and the next person should
not have to rediscover it.

### The storm test needed a concurrent writer, and that needed care

`iio-rate` reads `/proc/interrupts`, backgrounds `dd`, sleeps for the
duration, and reads again. The only lever on a counter the program reads
itself is to change the file during that sleep. A first attempt put the
write in the `iio-decode` stub, which runs outside the window and changed
nothing: the ratio stayed at 0.0 and the assertion failed for the wrong
reason.

The working version is a writer that increments the counter every tenth of
a second throughout, killed afterwards. **Written as a monotonic series
rather than one timed write on purpose:** a single write has to land after
the first read and before the second, which is a race against setup time,
whereas a series cannot miss, because whenever the first read happens the
next write is larger. This suite has already shipped one flaky assertion and
that is one more than it should have.

## 53. The wire was never the fault, the request was

*Thursday 1 October 2026, 23:35.* One word in the device tree, `<24 1>` to
`<24 4>`, rising edge to level high. Same wire, same pin, same shield, same
ten minutes:

| | edge | level |
|---|---|---|
| interrupts | 3269 | **23** |
| per second | 326.90 | **2.30** |
| ratio to expected | 43.6x | 0.3x |
| samples | 4672 (73 x 64) | 4608 (72 x 64) |
| reader CPU | 0.50 % | 0.60 % |

**A 142-fold reduction with sample delivery unchanged**, both counts exact
multiples of the watermark. The 3246 edges that vanished were never carrying
data.

INT1 is push-pull and stays asserted while the FIFO is above its watermark.
An edge-triggered request counts every transition in the bounce train on a
long unterminated wire. A level-sensitive one asks whether the line is high
when it looks, and a ring that settles before the handler runs is invisible
to it.

**For four days this project recommended a shorter jumper or a few hundred
ohms in series at CN9 pin 6.** That recommendation appears in the README, in
`RESUME.md`, in three journal entries and in two evidence files. It was
wrong. The wire was fine. What was wrong was asking the kernel to count
edges on a line whose information is in its level.

### What the measurements had already said, and what they had not

The control, wire unplugged, 0.00 per second and zero samples, proved the
edges were real and arrived down the wire rather than being picked up by the
GPIO. That was correct and it is unaffected.

What it could not say, and what nothing asked, is **whether a real edge and
a useful edge are the same thing.** A ring is real. It is on the wire. It is
also not information, and the way to stop counting it was never to make the
wire quieter.

The 23 to 51 times figure, and tonight's 43.6, were all measuring the same
thing correctly and attributing it to the wrong place. The number that
should have been suspicious is the one this project printed on its first day
and never interrogated: **the factor was never constant.** A reflection on a
fixed length of wire into a fixed impedance has no reason to vary by a factor
of two between runs. A bounce train sampled by an edge detector does.

### Criterion 4, half met in a new place

The first threshold is now met with room to spare: 2.30 interrupts per
second against a limit of 8, and 0.60 per cent reader CPU against 3.

The contrast clause is not, and cannot be. It asks for **more than 400 per
second at watermark 1**, and a level-sensitive line gives 15.60, because it
coalesces: 4684 samples over 156 interrupts is 30 samples each. Batching is
still demonstrated, 15.60 down to 2.30 per second and 1.50 down to 0.60 per
cent CPU with the sample count unchanged, but the number 400 assumes one
interrupt per sample, and that is a property of edge triggering rather than
of the hardware.

**So the clause can only be satisfied by the configuration that was just
shown to be broken.** That is the same shape as criterion 8: a number
written from an assumption rather than from a measurement, which the
measurement then contradicts. It is a decision for Joseph and not a thing to
be measured harder.

### And the ratio check earned itself on its first real run

`iio-rate` grew a criterion 4 check an hour before this experiment, printing
expected against measured and exiting 3 above a ratio of 2. It exited 3 on
the edge-triggered baseline and 0 on the level-triggered run, with no human
dividing anything. The experiment that found this fix was scored by a
program written before anybody knew there was a fix to find.

## 54. Criterion 4 is met, and the clause that could not be was restated

*Thursday 1 October 2026, 23:45.* Joseph ruled on the contrast clause and
criterion 4 closes. Eight of nine.

The clause asked for more than 400 interrupts per second at watermark 1. His
reasoning, kept because it is better than a verdict:

> A contrast that can be satisfied only by the broken setup is not a
> criterion.

400 assumes one interrupt per sample, which is edge semantics. A
level-triggered line coalesces, so watermark 1 reads 15.60 per second,
4684 samples over 156 interrupts, 30 samples each. That is the handler
draining the FIFO, not batching failing. The only way to reach 400 is to go
back to rising edge, which is the configuration that gave 326.90 per second
at watermark 64 against an expected 7.5.

Restated to a same-configuration ratio: **at the same output data rate and
the same trigger type, watermark 64 produces at least 5 times fewer
interrupts than watermark 1.** Measured 6.8 times. The absolute halves are
untouched, because 8 interrupts per second and 3 per cent reader CPU do not
depend on how the interrupt is requested.

**The reader-CPU contrast was offered and rejected, and the reason is worth
keeping.** 1.50 per cent at watermark 1 against 0.60 at 64 is real and
survives both trigger types, and it is *a second view of the reader-CPU half
the criterion already has* rather than a substitute for the interrupt claim.
A criterion with two clauses measuring the same quantity looks like two
pieces of evidence and is one.

### Where the four rows live

`/var/lib/bench/iio/rates.csv` carried the whole experiment in four lines, and
they are now in `docs/evidence/irq-level-vs-edge-2026-10-01.txt` verbatim
rather than paraphrased. That file was written from the CSV rather than from
the console output, which matters: the console output was read by a person
who already believed the conclusion.

### Two criteria restated in one evening, by the same person, for the same reason

Criterion 8's ninety-degree clauses measured the fixture. Criterion 4's
contrast clause measured the trigger type. Both were numbers written from an
assumption about how the measurement would be made, and in both cases the
measurement, once taken properly, contradicted the assumption rather than the
hardware.

That is now three criteria of nine whose wording has been corrected by
measurement: 4, 8 and the 416 Hz in 4's first half. **A criterion written
before the first measurement is a hypothesis about what will be easy to
measure**, and this project would have been better off writing the acceptance
table after the first week than before it.

## 55. The overlay broke the captures, and the symptom was two identical results

*Friday 2 October 2026, after midnight.* Criterion 8 re-measured by hand.
The level clause is met. The ninety clause reaches 3.3 degrees against a
tolerance of 3, repeatably, and the limit is the brace.

### Making the driver bind correctly broke the method that had worked all week

Thursday's captures were raw burst reads with nothing bound to `0x6b`. The
part was free-running and the reads were live. Tonight the overlay declares
it, `st_lsm6dsx` owns it, and **the driver keeps the part in power-down when
no buffer is enabled.**

`i2ctransfer` refused the address outright, which was informative. `-f` got
past that, which was not: it skips the claimed-address check but not the bus
lock, and it returned a frozen register, silently.

**The symptom was not an error. It was two captures scoring identically to
four decimal places.** A flat board and a board on its edge both reporting
`X -0.0026 Y +0.0101 Z +1.0070` and roll +0.877. `CTRL1` read `0x00`,
confirming power-down, and `0x06` put the part at 120 Hz, after which five
spaced reads all differed.

The identical result is the only thing that caught it. Had the second pose
differed slightly, from noise or from a stale value changing once, the
capture would have been scored and written up.

### A claim made and withdrawn within two measurements

The first ninety-degree attempt gave filter +92.795 against trigonometry
+95.266, and doubling the settling window changed neither. I wrote that up as
a steady-state bias in the filter, and added that scoring the filter alone
would pass a pose that was out of tolerance by under-reporting it. That was
stated to Joseph as a finding.

The next two attempts refute it. At a square pose the routes agree to 0.21
degrees, as they do flat. The gap belonged to that one capture.

**What survives is the method rather than the conclusion.** The orientation
error between the two routes is the number that says whether a capture is
worth scoring, and 2.471 degrees should have been read as "this capture is
suspect" and not as "the filter is biased". The project built that metric
precisely so a bad pose would announce itself, and then I read its output as
a statement about the filter.

That is the fourth time in two days that a correct measurement has been
attributed to the wrong cause, and the pattern in all four is the same: one
observation, one plausible mechanism, no second measurement before writing it
down.

### Where criterion 8 stops, and why that is a result

    attempt  Z (g)     filter roll   direct roll   agreement   off axis
    1        -0.0923   +92.795       +95.266       2.471 deg   5.27 deg
    2        -0.0571   +93.163       +93.257       0.207 deg   3.25 deg
    3        -0.0581   +93.217       +93.312       0.210 deg   3.31 deg

Two braced holds landing within one per cent of each other. The measurement
is repeatable and **the brace is 3.3 degrees off vertical**, 0.3 from the
tolerance. Pitch was never the problem: +0.294, -0.078, +0.110.

So it is a number to decide on in daylight, not an argument to continue past
midnight. Either a square reference is found, a wall or a shim rather than
anything standing on a bench, or the tolerance is restated at 3.5 degrees
with this measurement as the reason. Both are defensible.

Three of the four poses were not taken, and the record says so rather than
implying the pose was unlucky.

### And a second independent source for the address map

ST's own Arduino examples at github.com/stm32duino/X-NUCLEO-IKS4A1 carry the
same address map this project measured: the LSM6DSV16X at its default
address, the LSM6DSO16IS forced to the low address `0x6a`, and LIS2DUXS12,
STTS22H, LIS2MDL, LPS22DF and SHT40 all constructed. **That sketch expects
`0x19` and `0x38` on the bus**, which is a second reason, independent of the
straps and of `modules.alias`, not to call them unsupported.

The sketches also enable every part except the humidity sensor before the
first read and do not treat an unenabled part as a wiring fault, which is the
same rule as `iio-stream`'s. And their fusion example sets all three rates to
120 Hz, which is where `iio-stream`'s "first rate at or above 100" policy
independently lands on this part's ladder.

Two things in that tree not to copy, recorded so nobody does: `HelloWorld`
calls `GetHumidity` with no `begin()` and no `Enable()`, and no sketch there
wires INT1 at all, so none of them is evidence about the CN9 pin 6 interrupt
in either direction.

## 56. A second card archive, and nohup does not outlive a virtual machine

*Friday 2 October 2026, morning.* The card is archived again, verified byte
for byte, at `proj10-iio-iks4a1-card\2026-10-02_af91824`. The question that
started it was whether one copy was enough. It was not, and the reason is a
gap of twenty-eight minutes.

### The first archive is a copy of the card from before the thing it needs most

The comparison passed at 19:04. **libiio 0.26-2 and `iiod` were installed at
19:32.** Criterion 5 is the libiio criterion, so the one archive that existed
was a copy of the system from before the apparatus that proves criterion 5
was on it.

Four other things also landed afterwards: `iio-stream` compiled against that
libiio, the overlay recompiled onto `/boot` with the `lsm6dso16is@6a` node at
23:24, `interrupts = <24 4>` at 23:35, and the `rates.csv` rows and criterion
8 captures. All four come back from this repository with three commands and a
reboot.

**The libiio install does not.** `iio-stream.c` calls `iio_buffer_refill`,
which libiio 1.0 removed, and it compiles because Debian trixie packages
0.26-2. A restore that runs `apt install libiio-dev` after the distribution
moves gets a library the program will not build against. The recipe's own CI
version guard says this already; what was not noticed is that the guard
describes a risk the archive had taken on.

The second reason is smaller and sharper: **a restore of the Thursday
1 October 2026 archive comes back edge-triggered.** It reproduces the 3269-interrupt storm that
entry 53 closed, and whoever meets it next could spend an evening on a solved
problem.

Both archives are kept. The Thursday 1 October 2026 one is the only copy of
the configuration that
every measurement before 19:04 was taken on, so neither is a duplicate of the
other.

### The stamp names a commit, and the commit is from another project

The directory stamp is HEAD of the clone at archive time plus `-dirty`. Two
things nearly spoiled it before any imaging started: the clone on the win11
skyhorizon demo laptop was seven commits behind, and an untracked zero-byte
file named `cd`, left by a mistyped redirect, would have appended `-dirty` and
recorded a modified working tree that did not exist.

Both were fixed, and the stamp came out `2026-10-02_af91824`. **`af91824` is
a project 11 commit**, the tip that morning, and it describes nothing on this
card. The commit whose contents the card matches is `488438d`. The two are
written down together in `docs/RESUME.md`, because a stamp that names one and
a card that matches the other is exactly the kind of thing a date alone leaves
to be inferred.

### nohup was the wrong fix for the right problem

The first run, on Thursday 1 October 2026, died at 42 per cent in a foreground
shell whose tab was closed, and `nohup` went into `docs/CARD.md` as the remedy. This morning a
nohup'd run died anyway. `wsl -l -v` reported the Ubuntu distro `Stopped` and
`usbipd list` showed the reader back at `Shared`.

**nohup blocks SIGHUP from a terminal. It cannot keep a process alive when the
virtual machine hosting it stops.** The remedy was never nohup; it was leaving
the window alone, and nohup made that look unnecessary.

What stopped the distro is not recorded here, because one line of output does
not distinguish a closed terminal, an explicit `wsl --shutdown`, a
`Stop-Process` on `wsl.exe` and WSL's own idle timeout. The ordering that
preserved even that much is worth keeping: **`wsl -l -v` was run from
PowerShell before anything re-entered WSL**, because entering a stopped distro
starts it and destroys the evidence that it was stopped.

The monitoring moved to the Windows side as a result. The image is written to
a path on `C:`, so `Get-ChildItem` reads its growth with no WSL session
involved, and the WSL window has nothing to do but exist.

### A plateau that looks exactly like a stall

At 10:05 the file stopped growing at 1,547,436,032 bytes with seven minutes of
reading still to go, because the written data is near the front of the card
and the remaining 14 GB of unwritten ext4 free space compresses to nothing.

**That number is within 786,432 bytes of 1,546,649,600, the size of the
fragment abandoned on Thursday 1 October 2026.** A live archive seven minutes from done and a dead one
killed at 42 per cent were under a megabyte apart, and `du -h` prints `1.5G`
for both. The discriminator is `.dd.log`, whose size and timestamp advance in
both cases, which is why the plateau is now written into `docs/CARD.md` beside
the size warning rather than left to be re-learned.

### Two smaller things

`usbipd attach --wsl --busid 6-4 --auto-attach` was proposed while the second
read was in flight and declined. It manipulates the attachment the running
`dd` reads through, and by the time a dropped device is back, `dd` has already
failed. It addresses a USB drop; this was not one. Declining it was not a
judgement call about risk appetite, it was that the action could not help and
could end the run.

And the remedy in `docs/CARD.md` for USB selective suspend had one of the two
values it needs. `/setacvalueindex` writes the mains value; the battery value
read `Enabled` all week, so the fix depended on the laptop staying plugged in
and that dependency was written down nowhere. Both values are now in the
document, with the read-back command that shows them.
