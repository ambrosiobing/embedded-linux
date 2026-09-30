# Timeline: Wednesday 30 September 2026

The day project 10 met hardware, minute by minute.

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

## What the day cost, and where

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

## What was wrong at the start of the day and right at the end

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
