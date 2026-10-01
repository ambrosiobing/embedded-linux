# Timeline: Wednesday 30 September and Thursday 1 October 2026

The two days project 10 met hardware, minute by minute.

**What the times are.** Every time below is a real commit timestamp or a
file modification time, not a recollection. They therefore record when a
thing was **written down**, which trails when it happened at the bench by a
few minutes. Where an event has no timestamp of its own it is placed
between the two commits that bracket it, and said to be so.

The full reasoning for each finding is in [the journal](../JOURNAL.md),
whose entries are thematic. This file is the order they happened in.

## Afternoon: the paper bring-up, before any power

| Time | Event | Commit |
|---|---|---|
| 14:32 | The bench inventory was wrong and is corrected. All four ST boards and the nRF PPK2 are present, so nothing was blocked for want of a part, and three documents that rested on the old list are fixed | `81bcc30` |
| 15:34 | The INT1 pin is recorded as a claim rather than a measurement, after a screenshot asserted CN9 pin 6 without a source | `d8c545d` |
| 15:37 | Which end of CN5 is pin 1, and what counting it backwards costs: SDA on D9 and SCL on D8, neither on the shield's bus, giving an empty scan with nothing wrong in software | `33397d3` |
| 15:49 | Pin 6 was double booked. The wiring table gives it to the shield and the console ground was sent there too. The console ground moves to pin 9 | `2ea594b` |

**The first surprise of the day** is at 14:32 and it is not technical. A
stored inventory of the bench was wrong, and every document downstream of
it had inherited the error. Nothing on the bench had changed; the record of
it had.

**The pivot at 15:49** is small and would have cost an evening. Two wires
were routed to one header pin by two documents that were each correct on
their own. One header pin takes one jumper socket. Nothing catches that
except reading the two tables against each other.

## Late afternoon: four hours on a card, and none of it on the sensor

Between 15:49 and 19:53 there is no commit, because nothing was being
learned about the shield. The card was.

| Time | Event | Commit |
|---|---|---|
| 19:53 | The card runbook is written: which side owns the reader, an empty reader reading zero bytes, identifying the boot partition by `config.txt` beside `cmdline.txt` | `29d52dd` |
| 20:02 | The card belonged to project 20 and was reused. Nothing in project 20 depends on it | `ebd9570` |
| 20:04 | A sentence explaining the previous commit was flagged by the attribution guard, because it contained a forbidden phrase inside an innocent word. Reworded | `3bd91cb` |

**The surprise in that gap** is that the SD card reader was invisible to
Raspberry Pi Imager because it had been attached to WSL with `usbipd`, and
a device bound to WSL is not available to Windows. The board was fine, the
card was fine, the reader was fine, and the tool showed nothing.

**The lesson at 20:04 costs nothing and is worth having.** A safety check
that scans commit messages will flag a commit message that describes the
thing it is fixing. Describe the trigger, do not spell it.

## Evening: power on, and the bus answers

| Time | Event | Commit |
|---|---|---|
| 20:34 | `config.txt` has conditional sections, and an append inherits the last one. A line added at the end of the file lands under `[pi5]` and does nothing on a 3B+ | `2d4896c` |
| 20:53 | **The bus answers.** Six addresses, and the reading corrects three documents | `57e56b5` |
| 21:05 | **The single most valuable commit of the day.** The overlay bound the IMU at 0x6a. WHO_AM_I says 0x6a is 0x22 and 0x6b is 0x70, so the driver would have refused to bind and said nothing about why. Moved to 0x6b before it ever ran | `7a97811` |
| 21:38 | UM3239 Rev 5 confirms every pin of the wiring table, and Table 1 shows all seven addresses are factory defaults | `7f3aa2a` |
| 21:44 | A bus scan is not an inventory, and one scan misses a part | `0359f53` |

**The aha at 20:53.** Six devices answering is simultaneously a proof that
every wire is right and a refutation of the documents describing the board.
The bus is the authority and the paperwork was not.

**The pivot at 21:05** is the one that justifies the whole practice of
reading identity registers before trusting an address. The overlay had
carried 0x6a since it was written, from an assumption. The failure it would
have produced is the silent kind: node created, probe refused, no message.

**The correction at 21:44 is one I had to make against myself twice.**
First I concluded from a single scan that the LIS2DUXS12 was absent and
committed it. It is not absent: it declines the zero-length write that
`i2cdetect` probes with by default, and answers `i2cdetect -r` and a direct
register read. Separately the SHT40AD1B does the reverse, appearing under
the default probe and vanishing under `-r`. Two probe modes, two different
pictures, both parts present throughout.

**And one proposal was refused at the bench, correctly.** To settle which
board owned which address I proposed lifting the daughter board off the
shield. The two are one assembly. The refusal was right, and the datasheet
DB5091 answered the same question at no risk half an hour later.

## Evening: the drivers are not there

| Time | Event | Commit |
|---|---|---|
| 21:54 | **The distribution kernel has none of the ST drivers.** Not a missing module, not a configuration: they are not packaged | `8e416b8` |
| 22:00 | The overlay applied, bound one of four, and logged nothing either way | `fd303a5` |
| 22:06 | 22.1 degrees and 54.0 percent: the first real reading, through hwmon | `368c4e7` |
| 22:09 | The breath test. Humidity 55.9 to 64.6 percent and back. The reading responds to the world | `459f041` |
| 22:12 | No accelerometer driver either, which also bears on project 5 | `104a9ad` |

**The biggest single finding of the day is at 21:54,** and it turns a
precaution into a requirement. Project 10's Yocto kernel fragment existed
because the drivers might be missing. They are missing, measured, on the
distribution this board is running.

**The sharpest surprise is at 22:00.** The project's own documents warn
that a node whose compatible string the kernel does not know is created,
binds nothing, and reports nothing. That was demonstrated on hardware. The
finding nobody had written down is that **the successful binding was
equally silent**: the SHT40AD1B bound and appeared under hwmon with no
kernel message either. Silence distinguishes nothing from nothing.

## Night: gravity, without a driver

| Time | Event | Commit |
|---|---|---|
| 22:17 | Gravity, read from a chip the kernel has no driver for, straight off the registers over `i2c-dev` | `9cbb6c6` |
| 22:26 | The magnitude is one g to nine parts in a thousand | `5b9a60e` |
| 22:28 | The burst read outruns the sensor at 120 Hz, and finds one sample that is not physics | `0ae6077` |
| 22:35 | **That mechanism is disproved by one register read.** Block data update was already on, because 0x44 is this part's reset value for CTRL3 | `d76ede2` |
| 22:54 | A quiet run, and what it says about every number before it | `2898387` |
| 22:58 | The new acceptance row collided with an existing criterion number. Renumbered | `c0b2d24` |

**The aha at 22:17** is that the missing driver stopped being a blocker.
The chip answers register reads whether or not Linux has a driver for it,
and a shell loop over `i2c-dev` produced real orientation data from a part
the kernel could not see.

**The pivot at 22:35** is the most instructive failure of the day. I
proposed a specific mechanism for a single bad sample, gave the register
that would test it, and the register read `0x44` before the write: the
mechanism had never been off. One command, one second, hypothesis dead.
That is the argument for guessing specifically. A vague guess cannot be
killed and therefore never leaves.

**The most valuable measurement of the day is at 22:54 and it is the
boring one.** A quiet capture with nothing happening. The floor is 0.36 mg,
where the previous capture had been read as a floor of a few tens of
milli-g. That earlier spread was the bench being disturbed. Every number
taken before 22:54 had been compared against a floor nobody had measured.

The near-zero sample from 22:28 did not recur: none below 0.5 g in 8000
samples, no malformed line, no read error, where four would have been
expected at the rate it appeared to show. The difference is that this pair
was written to a file on the board and copied off as a file, so nothing
crossed a terminal.

## What Wednesday cost, and where

| Activity | Rough share | Produced |
|---|---|---|
| Preparing and flashing a card | Four hours | A runbook, and no knowledge of the sensor |
| Wiring, scanning, identifying | About an hour | Seven parts identified, the overlay corrected before it ran |
| Reading the manual | About half an hour | Every open question closed, one risky test avoided |
| Measuring | About an hour | A noise floor, a calibration figure and a vibration case |

**The lesson in that table** is that the four hours went to the part of the
work with no theory in it, and the half hour with the manual settled more
than the four hours did. Neither is avoidable, and the ratio is worth
remembering when estimating the next one.

## What was wrong at the start of Wednesday and right at the end

1. The bench inventory, which omitted four boards that were present.
2. The overlay's IMU address, 0x6a for a part at 0x6b.
3. The console ground, sent to a pin the shield already held.
4. The claim that the LIS2DUXS12 was absent, from a single probe mode.
5. The claim that both IMUs were on the shield, right by luck from an
   argument that did not hold, then established properly from DB5091.
6. The belief that the ST drivers were present and merely unbound.
7. The noise floor, overstated by a factor of some hundreds.
8. A proposed torn-read mechanism, disproved by the register it named.

Six of those eight were caught by a measurement rather than by review, and
two, the third and the seventh, were caught only because something else was
being checked at the time.

---

Back to the [project README](../README.md), the [journal](../JOURNAL.md)
or the [bring-up](BRINGUP.md).

# Thursday 1 October 2026

## Early morning: closing out the vibration thread

| Time | Event | Commit |
|---|---|---|
| 06:44 | The 30 Hz test refutes the beat hypothesis. The tone survives where a 117 Hz line could not, so it is real vibration and never was a sampling artefact | `e40c924` |
| 06:48 | The duplicate fraction turns out to be an output-rate meter: 0x04 gives 30.3 Hz measured and 0x06 gives 121.3, settling the register map with no data sheet | `109f678` |
| 06:59 | **Taping the shaver down refutes the operator reading**, and one more claim of mine with it | `73b1332` |
| 07:18 | The tap does not ring at 3 to 6 Hz, which is the sharpest constraint of the two days | `58b1ced` |
| 07:24 | Eight g full scale confirmed by a predicted count, and one calibration constant fits both ranges to 36 parts per million | `f93b4b3` |
| 07:35 | There is a ring, and a two second window was hiding it | `4b482bc` |

**The pivot at 06:59.** I had concluded the 3 Hz line was the hand holding
the shaver. Taping it down made the tone four times larger and moved it
from 2.71 to 4.87 Hz. The hand was damping the assembly, not driving it.
The shape of the argument survived and the attribution did not.

**And a second claim went with it.** The two-sources argument from the
previous entry rested on comparing records taken at different output rates,
which this journal had spent four entries warning against. I wrote the
warning and then built a conclusion on exactly what it warned about.

**The surprise at 07:24** was free. Gravity reads 1.00680 g at two g full
scale and 1.00684 at eight, 36 parts per million apart across a fourfold
change of range. So the 0.68 percent error is one sensitivity constant, not
a per-range table, and that also disposes of local gravity and of tilt as
explanations.

**The correction at 07:35 was mine, twice over.** My ring-down windows were
2.0 s and the taps were 1.5 s apart, so each window swallowed the next tap
and produced a number that looked like a finding. The one clean window
showed no ring at 3 to 6 Hz at all, which is the constraint that still
stands.

## Morning: the programs meet hardware for the first time

| Time | Event | Commit |
|---|---|---|
| 07:43 | Project 03 audited before starting it: two contradictory claims about the PPK2, a file table pointing at a moved file, and a stale open item | `689af20` |
| 07:46 | **`iio-probe`'s parts table carried the same 0x6a address bug the overlay shed on Wednesday**, plus a seven-bit table holding an eight-bit address, plus a missing part | `3998952` |
| 07:53 | The first program to reach the board would not start: a carriage return in the shebang, and the repository was right all along | `ea09c15` |
| 07:56 | **Criterion 2 met**, by a program correctly reporting that four drivers are absent | `66d8713` |
| 08:00 | `ahrs` gains a way to read a capture, and meets real gravity at level for the first time | `d496adf` |
| 08:33 | The ninety degree criterion measures the fixture, and roll is not a determined quantity there | `31254da` |

**The aha at 07:46** is about how a fix fails to travel. Wednesday's
measurement corrected the overlay's IMU address in commit `7a97811`. The
identical error sat in `iio-probe`'s parts table for a day because nothing
connects the two files, and it was found only because the program was about
to be run for the first time.

**The surprise at 07:53** is that the repository was correct and the working
tree was not. `.gitattributes` already says `text=auto eol=lf`; it was added
after these files were checked out and `core.autocrlf` is `true`, so 31
tracked files with a shebang still carry a carriage return. A Yocto build
fetches from git and ships a working script; `scp` from the working tree
ships a broken one. The failure exists only on the path that was never the
designed one.

**The correction at 07:56 is to something said hours earlier.** Criteria 2
through 5 had all been described here as blocked on the drivers. Only 3, 4
and 5 were. Criterion 2 needed a shell script copied over `scp` and had been
sitting behind an assumption rather than a dependency.

**And at 08:33 an acceptance criterion was found defective rather than
failed.** "Pitch and roll within 3 degrees after a 90 degree rotation"
measures how squarely the board was propped, and at a pitch near 90 degrees
roll is not determined at all. The filter itself agrees with trigonometry to
under 2 degrees at every pose.

## Morning: the drivers, and three bugs in programs that had never run

| Time | Event | Commit |
|---|---|---|
| 09:21 | **Two IIO devices**, from a driver that was not in the image an hour earlier. `st_lsm6dsx` built out of tree against 6.18.50 | `0036ce9` |
| 09:25 | The interrupt registered on GPIO24, and criterion 4 names a rate this part does not have | `02cc709` |
| 09:36 | `iio-rate` called a 4.5 kB FIFO absent, from one attribute name | `80340c7` |
| 09:44 | The buffer held a timestamp and no data, which the kernel refuses with `EIO` | `0a51073` |
| 09:53 | The interrupt storm that disabled IRQ 185, and what it confirms about the wiring | `aa95f69` |
| 10:01 | The watermark was written before the buffer length | `75acb9d` |
| 10:06 | **The FIFO batches.** 467 samples a second, 0.80 percent reader CPU | `48912c7` |
| 10:11 | **A hypothesis confirmed by a number the kernel had stopped counting.** Withdrawn | `f8546c0` |
| 10:14 | The state the next session starts from | `3ac0b85` |
| 10:16 | The rate rows and every capture, recovered before power down | `4f99413` |

**The aha at 09:21** is how narrow the blocker turned out to be. The IIO
subsystem was present and packaged in full, trigger and buffer directories
included; `/sys/bus/iio` was absent only because nothing had loaded
`industrialio`. And `linux-source-6.18` matched the running kernel exactly,
so no tag had to be guessed and only one driver directory had to be
unpacked.

**Three bugs between 09:36 and 10:01, all in the same program, none of them
findable by its tests.** It looked for one of two watermark conventions and
declared the hardware absent when it found the other. It enabled a buffer
holding a timestamp and no data channel. It wrote the watermark before the
buffer length, which only fails on a freshly loaded driver and had worked
once by accident on a dirty one.

**And the reason all three survived is the same.** Every fixture these
programs are tested against is a synthetic sysfs tree, where writing to
`buffer/enable` writes to an ordinary file and no kernel is there to object.
A test built from directories can check what a program writes and never what
the kernel would make of it. That bears directly on criteria 6 and 7, which
are marked met on a laptop because they are properties of the programs, and
so were these.

**The pivot at 10:11 is the worst analytical error of the two days.** The
watermark 1 run reported 100001 interrupts and it was read as a rate. 100001
is the kernel's spurious-interrupt threshold: the count stopped there
because the watchdog disabled the line. On that number a multiplier was
declared constant across a sixty-fourfold range and called confirmed "by
something other than its own plausibility". The three usable points give
22.9, 31.8 and 51.1.

**What stands from the FIFO work** is the half the wiring could not reach.
Spurious interrupts never wake the reader, so reader CPU is clean, and it
lands on theory from two directions at once: four times the sample rate
costs four times the CPU, and batching by 64 halves it at identical
throughput.

## What Thursday cost, and where

| Activity | Rough share | Produced |
|---|---|---|
| Finishing the vibration measurements | Under an hour | Two refuted hypotheses, a cross-range calibration constant, a measured ring |
| Fixing programs so they could run at all | About an hour | Four defects, none findable by their own tests |
| Building and loading one driver | About half an hour | Two IIO devices, and criterion 2 met on the way |
| Chasing the interrupt | About half an hour | A storm, a wiring confirmation, and one measurable half of criterion 4 |

**The ratio worth remembering.** More time went to repairing the tools than
to using them, and the repairs were only possible because the tools were
being used. None of those four defects had surfaced in two weeks of unit
tests.

## What was withdrawn across the two days

1. That the LIS2DUXS12 was absent, from a single probe mode.
2. That reading two WHO_AM_I values proved both IMUs sit on the shield.
3. That block data update explained the single free-fall sample.
4. That the broadband rise under the shaver was measured aliasing.
5. That the 3 Hz line was a beat against the sensor's own sampling.
6. That the 3 Hz line was the hand holding the shaver.
7. That 2 to 4 Hz and 12 to 25 Hz are two sources with opposing pressure
   dependence.
8. That the interrupt multiplier is constant.

Eight withdrawals, every one killed by a measurement rather than by review,
and six of the eight by a measurement that cost a single command.

## Backlog

**Bench, and nothing in software substitutes for either.**

- The interrupt jumper. Spurious edges outnumber real FIFO assertions by 23
  to 51 times, the factor is not constant, and the mechanism is not
  identified. This is the only thing between criterion 4 and passing as
  written.
- The supply. Eight `Undervoltage detected` events in eleven hours, under
  every capture taken.

**Build, each the same procedure as `st_lsm6dsx`.**

- `st_sensors` plus `st_magn`, which gives the LIS2MDL a device and unblocks
  criterion 3.
- `st_pressure`, which completes criterion 1.
- `iiod` and libiio, neither yet on the board, for criterion 5.

**Decisions that are Joseph's, not this file's.**

- Whether to restate criterion 8 so it tests the filter rather than the
  fixture. A wording is proposed in the evidence.
- Whether to edit criterion 4's rate from 416 Hz, which this part does not
  offer, to 480, which preserves both its thresholds.
- Whether to refresh the working tree so its 31 shebang files match what is
  committed. Every one of them fails the same way when copied to a board.
- 49 commits sit unpushed on `main`.

**Known gaps in the programs, recorded rather than invisible.**

- `iio-stream.c` is compiled by nothing but a full Yocto image build. CI
  compiles six C programs by name and not this one, and it has no test
  file. Criterion 5 is measured with it. Journal entry 38 is the review
  that stood in for running it, and names one defect: an unparseable `-n`
  returns zero, which is the documented value for "until interrupted", so
  a typo in the one bounding argument silently produces an unbounded run.
- Compiling it in CI needs `libiio-dev` on the runner, and the recipe
  warns that `libiio` 1.0 removed `iio_buffer_refill`, so a current
  package may refuse this 0.x code outright. That is a port rather than a
  CI line, and whether CI should go red until it is done is Joseph's call.

**Open questions with no owner yet.**

- Whether `st_lsm6dsx` carries a compatible for the LSM6DSO16IS at `0x6a`.
  The source is unpacked on the card and the answer is a grep.
- The 57 Hz seen under the handheld shaver and not corroborated by the tap.
- The single free-fall sample of Wednesday, whose only remaining physical
  candidate is the undervoltage.
- Volume one's inventory line for the X-NUCLEO-IKS4A1, which still omits the
  LSM6DSO16IS although the measurement to correct it now exists.
- The chapter 11 divergence between the book, which says VL53L8CX, and the
  repository, which says ADXL345.

---

Back to the [project README](../README.md), the [journal](../JOURNAL.md),
the [bring-up](BRINGUP.md) or the [resume note](RESUME.md).
