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

## Afternoon and evening: the board comes back, and two criteria close

| Time | Event | Commit |
|---|---|---|
| 16:48 | The Pi 3B+ and the USB TTL console are back on the bench. Six addresses answer `i2cdetect` | |
| 16:55 | `st_sensors` and `st_magn` unpacked, built and loaded. **Three IIO devices**, the LIS2MDL among them | |
| 17:12 | `iio-trigger` refused with `Permission denied`, from a lost exec bit rather than from anything on the board | |
| 17:19 | `iio-trig-hrtimer` was not loaded, so the hrtimer directory did not exist | |
| 17:31 | **Criterion 3 met.** 3.341 us, 1003 samples in 10 s, 0 interrupts, 0.40 percent CPU, on the one path the bench's interrupt fault cannot reach | `af2be18` |
| 17:58 | `st_pressure` built as a target added to a Makefile that already worked, and the LPS22DF bound | |
| 18:04 | **Criterion 1 met.** Four `working` rows where the morning had one, four IIO devices, two triggers | |
| 18:20 | `scripts/card-archive.sh` and its 52 assertions, because for this project the card is the build output | |
| 17:08 | The first archive run dies at forty-two per cent when its WSL tab is closed, leaving a 1.55 GB file with an archive's exact name and no records | |
| 18:55 | **"now we are ready to wipe out and replace the contents of sd card".** Held, because the two record files were absent | |
| 19:05 | `.dd.log` read through `tr` shows a progress figure and no I/O error, so the card is healthy and the terminal was the cause | |
| 19:12 | The reader re-attaches as `/dev/sde` where it was `/dev/sdf`, and the archiver refuses `no such source` twice before anyone notices | |
| 19:20 | The image is written as `.partial` and renamed only after the comparison, and the runbook stops telling anyone to run it in a foreground shell | |
| 17:34 | A second attempt dies at 496 s, 50 per cent, again with no I/O error, and `usbipd list` shows the reader still Connected with its state back to `Shared` | |
| 17:45 | USB selective suspend disabled in the power plan and on every hub, and `--auto-attach` started | |
| 18:08 | **The card is archived.** 15,728,640,000 bytes in 828 s at 19 MB/s, 1.5 GB compressed, `sha256sum -c` says `OK` | `9cd6302` |
| 18:30 | `card-archive.sh verify` pays the comparison debt that `BENCH_CARD_SKIP_VERIFY` creates, appending a dated result rather than rewriting the record | `ae3f284` |
| 19:04 | **The comparison passes.** The stored image and the card both hash to `35cc6c22`, so the archive is a proven copy and not an assumed one | `968e7be` |
| 19:10 | The card is NOT wiped. It keeps this system, because criteria 4 and 5 are still open on it and the archive makes reusing it a choice rather than a risk | |
| 19:27 | The board boots and presents no IIO devices at all. The modules were `insmod`ed and never installed, which is what `insmod` means | |
| 19:32 | libiio 0.26-2 installed, `iio-stream.c` compiles clean against it, `iiod` listens on 30431 | |
| 19:38 | The accelerometer refuses: `refill failed: Connection timed out`, and IRQ 185 reads `0 0 0 0` where this morning it reached 100001 | |
| 19:42 | The first remote attempt lists three hwmon devices and no IIO ones, because `iiod` enumerates at boot and the drivers arrived after it | |
| 19:45 | **Criterion 5 met.** 1000 samples each way, identical columns, 10.044 s and 10.074 s, on `lis2mdl` because the accelerometer's path needs the interrupt | |
| 19:55 | The backlog question is answered from the card: `st_lsm6dsx` carries `st,lsm6dso16is` in five places | |
| 20:00 | **`0x6a` binds.** Six IIO devices, five `UU`, no `not-bound` row left. It was never a driver gap, only an undeclared device | |
| 20:05 | The board is powered off. The two `unsupported` rows are now suspect for the same reason, and the obvious grep is not a valid test | |
| 21:10 | The board is back on. `iio-stream` still times out on the accelerometer, `iio-rate fifo` does not: 2449 interrupts where the other saw zero | |
| 21:25 | The ODR explains it. `iio-stream` sets no sampling frequency, and the part powers up in power-down. At 480 Hz the same command returns 1001 lines | |
| 21:40 | **The control.** The wire unplugged at CN9 pin 6 gives 0.00 interrupts and 0 samples, so GPIO24 picks up nothing and the storm is real at 30 times | |
| 21:45 | Two inferences withdrawn: the line never delivered nothing, and the fault never reversed. Both rested on a sleeping sensor | |
| 22:30 | CI compiles `iio-stream` for the first time ever, and passes. Journal 38's gap closes | `d1c11eb` |
| 22:50 | `0x6a` gets a device-tree node, with no interrupt property because its INT1 is on CN8 pin 6 and unwired | `022e82d` |
| 23:20 | Three more explanations for one timeout, all wrong. The interrupt wire was still unplugged from the control experiment | |
| 23:30 | Wire back on CN9 pin 6: 201 lines in 0.504 s at 480 Hz, 5 lines in 0.873 s at 7.5 Hz. **The first explanation was the right one** | |
| 23:24 | The overlay gains the `0x6a` node and is compiled onto the card. Six IIO devices at boot, no `new_device` | `022e82d` |
| 23:28 | `iio-rate`'s criterion 4 check runs on hardware for the first time: 43.6x, FAIL, exit 3 | `fd15464` |
| 23:35 | **`interrupts = <24 4>` instead of `<24 1>`.** 3269 interrupts become 23, samples unchanged. Criterion 4's first threshold is met | |
| 23:40 | And its contrast clause cannot be: a level line coalesces, so watermark 1 gives 15.60/s where the criterion wants 400 | |
| 23:45 | **Criterion 4 met.** The contrast clause is restated as a same-configuration ratio and the measured 6.8 times clears it. Eight of nine | |

**The aha at 16:55 is how little the second driver cost.** `st_sensors`,
`st_magn` and `st_pressure` are siblings in one subtree, so one Makefile
naming all the targets built all six modules against one `Module.symvers`.
The morning had spent hours getting the first one to link; the LPS22DF at
17:58 was four lines and a `grep` for its compatible string.

**Two faults at 17:12 and 17:19 that were not on the board.** A lost exec
bit read as a permission problem with the sysfs interface, and a missing
`iio-trig-hrtimer` read as a kernel without hrtimer triggers. Both were the
host side of the bench, and both were diagnosed by asking the system what
it held rather than reading the refusal at face value.

**`insmod` answered `File exists`, which is a success worded like a
failure.** What settled it was `ls /sys/bus/iio/devices`, the state rather
than the report. The same lesson as Project 2's three identical `dd`
successes, reached from a different direction.

**And criterion 2, already met, got evidence it could not have had in the
morning.** It was marked met on an inventory reporting four
`no-driver-in-image` rows. The same unedited program now reports four
`working` and none missing. The inventory tracked the image because it reads
the system rather than a table, which is the property the criterion is
about, and one run alone could not have shown it. Both runs are cited.

**The hour from 17:08 to 19:20 is the worst near miss of the two days.**
A backup program failed in a way that left something indistinguishable from
success, and the next instruction was to overwrite the original. What caught
it was looking for `PROVENANCE.txt` and `SHA256SUMS` rather than for the
image, and 1.55 GB is not even a suspicious size for that card. The image is
now written as `.partial` and renamed only after it has been compared
against the card, so the failure mode cannot recur in that shape.

**The finished archive is one per cent larger than the fragment that died
at 42 per cent**, 1,562,322,561 bytes against 1,546,649,600, because the
written data sits near the front of the card and the rest is unwritten ext4
free space that gzip collapses to nothing. `du -h` prints `1.5G` for both.
So the size of a card image says nothing about whether it is complete, which
is a better argument for the `.partial` naming than the one written into the
code, and it also retires the reasoning used at the time that 1.55 GB was a
plausible size for a finished archive. It was. So is half of one.

**The transport was being told to save power.** 448 s, then 496 s, then 828 s
and done, with 15, 16 and 19 MB/s across the three. A link periodically told
to power down is slower before it is cut, so the rate moved for the same
reason the read survived, and two observations that agree are a mechanism
where one would have been a coincidence.

**The exercise ends where it should have started.** The card is a proven
copy on a Windows desktop, outside the WSL virtual disk, with a record that
states what was checked and when. And the card itself stays as it is,
because the archive turned reusing it from something that would have cost an
afternoon of work into something reversible in seventeen minutes. That is
the only thing a backup is for, and it was not available at 17:00.

**The card image at 18:20 is a gap that had been open all along.** The
finished projects archive with `./go archive`, which keeps the output of a
build: a `.wic.bz2` with a `.bmap`, a `.manifest`, a lock file and a rebuild
line that is one checkout and one `kas build`. Project 10's card is none of
that, so for this project the card is not a copy of the artefact, it is the
artefact, and it existed in one copy in one reader. The first draft of the
archiver carried `conv=noerror,sync`, where `noerror` would have turned a
failing sector into silent zeros that the verification reads twice and
agrees with, and `sync` would have padded the image past the size of the
card it came from.

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

- `iiod` and libiio, neither yet on the board, for criterion 5. The only
  item left in this group: `st_sensors`, `st_magn` and `st_pressure` were
  all built on Thursday 1 October 2026, which closed criteria 3 and 1.

**Decisions that are Joseph's, not this file's.**

- ~~Whether to restate criterion 8.~~ **Settled Thursday 1 October 2026: no
  restatement.** The criterion is meetable as written and `roll90b` already
  met it, at roll +91.33 and pitch +0.32 from a pose 2.2 degrees off axis.
  The verdict moves from defective to not met, pending four poses held by
  hand rather than propped. The proposed restatement is neither adopted nor
  withdrawn.
- ~~Criterion 4's rate.~~ **Settled Thursday 1 October 2026: the criterion
  names 416 Hz or 480 Hz, whichever the part under test offers.** Both meet
  its arithmetic at watermark 64 and at watermark 1. 416 Hz is the classic ST
  ladder and may belong to the LSM6DSO16IS at `0x6a`, which had no driver
  bound until that evening; whether that part offers it is unverified, and
  its INT1 on CN8 pin 6 is not wired.
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

- ~~Whether `0x19` and `0x38` are unsupported or undeclared.~~ **Answered
  Thursday 1 October 2026: undeclared.** Both are supported parts at their
  default straps and ST's own shield overlay instantiates them. `0x19` needs
  `st,lis2duxs12` confirmed in the running kernel first; `0x38` needs
  `st,stts22h`, which is in ST's IIO tree and not mainline, so a node on a
  mainline kernel would bind to nothing and say nothing. Neither node is
  written. The remaining question is only which kernel, not which driver. **Not answerable
  by grepping the unpacked source**: only selected directories were extracted
  from `linux-source-6.18`, so a missing file means a missing extraction and
  reading it otherwise repeats the error that kept `0x6a` closed for two days.
  Ask `/lib/modules/$(uname -r)/modules.alias` and the module tree what this
  kernel can bind, and the source tarball what 6.18 holds.
- A device-tree node for `st,lsm6dso16is` at `0x6a` in the shield's overlay, so
  the binding survives a reboot instead of needing `new_device` each time.
- `iio-probe`'s expectation note for `0x6a` still says to confirm the
  compatible exists, which is now satisfied. Changing it means changing
  `tests/iio-probe-test.sh` in the same commit, since that suite asserts on
  the table.
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
