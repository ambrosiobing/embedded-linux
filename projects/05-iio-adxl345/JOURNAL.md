# Journal: Project 5

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 18 September 2026 unless noted.

---

## 1. What the repository had already promised, before any of it was written

**What happened.** Project 5 had been a single row in the root README since
the repository began, and nothing under `projects/` existed for it. The
first useful hour was spent finding out that the repository had already
committed to several things about it, in four other files, and that none of
them had been read recently.

- `walkthrough/06-mechanism-policy.md` states that "Project 5's driver has
  such a seam at the regmap layer", as an example in a general argument
  about testability. That is a design decision about a driver nobody had
  started.
- `walkthrough/10-generalising.md` says the driver is IIO rather than a
  character device "precisely so that Project 10 can use the whole IIO
  ecosystem against it without further work".
- `kas/bench-rpi3.yml` names Project 5 in its first line as one of the
  three projects that want the identical rootfs on a Pi 3.
- `projects/10-iio-iks4a1/README.md` and its design document both open by
  positioning themselves against this project: "Project 5 writes an IIO
  driver. This one does the opposite."

**What was done.** All four were treated as constraints rather than as
suggestions, and the design document was written to satisfy them
explicitly. The regmap seam is not a choice this project made; it is a
promise it inherited and has now paid.

**Why that and not the alternative.** The alternative is to design from
first principles and then discover the contradictions later, which is how a
repository acquires two documents that disagree. The lesson here is the
reverse of Project 15's entry 1: there the specification existed and was not
consulted, and this time the specification was partly the repository's own
prose about a project that did not exist yet.

**A gap worth naming.** The root README says Project 5's driver is what
Project 10 exercises, and Project 10 as built exercises ST's in-tree drivers
on a different part. Nothing in Project 10 consumes an ADXL345. The claim
survives only because Project 10's tools are part-agnostic by construction:
`iio-rate` takes a device name, `iio-decode` reads `scan_elements`. That is
a fact about how those tools were written rather than a plan anyone made,
and it is recorded here so the dependency is not read as stronger than it is.

---

## 2. The kernel already has this driver, and that is useful rather than awkward

**What happened.** Writing an ADXL345 IIO driver "from scratch" invites an
obvious objection, which is that Linux has had one for years. The design
cannot pretend otherwise, and the repository's Decision 83 forbids working
from memory about a driver: a binding is cited to a driver line.

So it was cited. Linux v6.12,
`drivers/iio/accel/adxl345_core.c`, about 260 lines, exports

```
EXPORT_SYMBOL_NS_GPL(adxl345_core_probe, IIO_ADXL345);

int adxl345_core_probe(struct device *dev, struct regmap *regmap,
                       int (*setup)(struct device*, struct regmap*))
```

with channels `ADXL345_CHANNEL(0, X)`, `(1, Y)`, `(2, Z)` and
`regmap_bulk_read`, `regmap_read`, `regmap_write` and `regmap_update_bits`
throughout. The binding
`Documentation/devicetree/bindings/iio/accel/adi,adxl345.yaml` claims
`adi,adxl345`, `adi,adxl375` and `adi,adxl346`, and requires `compatible`,
`reg` and `interrupts`.

Two things follow from having read it rather than remembered it.

The first is reassuring: mainline arrives at exactly the seam the
walkthrough promised, a core taking `struct regmap *` with thin bus files
either side. The shape is a property of the problem.

The second is a hazard. If this project's overlay declared `adi,adxl345`,
two drivers would match one node and which bound would depend on module
load order. Both would probe, both would register an IIO device, and the
numbers would look plausible either way, so the failure would not announce
itself.

**What was done.** The overlay declares `bench,adxl345` and the driver
matches only that. The in-tree driver cannot bind to it, so no race exists.

**Why that and not the alternative.** The obvious alternative is to leave
`CONFIG_ADXL345` unset and take the mainline name. That works until someone
builds an image that turns it on, and the defect it then produces is
invisible.

The reason to prefer a private string is better than defensive, though.
With both drivers installable and only one matching, **changing one word in
the overlay swaps which driver owns the hardware.** Every number this
project produces can then have a control taken on the same board, the same
bus and the same afternoon. Project 8 needed two kernel builds to get a
control that honest; here it costs a string.

---

## 3. The schematic is not drawn, because the board has not been read

**What happened.** The part on this bench is a DFRobot SEN0032. The design
needs three facts about the breakout rather than about the chip: whether
SPI is exposed at all, which pin carries `INT1`, and what the supply does
to the logic levels. DFRobot's wiki gives the chip's capability,
`I2C / SPI (3 or 4 lines)` at `3.3~6V`, and publishes no pin list.

**What was done.** Nothing was drawn. The schematic section of the design
document says why it is empty and names the three facts it is waiting for.

**Why that and not the alternative.** A pin table assembled from a product
page would look exactly like a pin table read off hardware, and the
repository has already paid for that class of mistake more than once. The
specific hazard here is not a wasted afternoon: a board rated to 6 V
regulates, and a 5 V `INT1` into a Pi GPIO destroys the pin. Project 15
carries the same shape of risk on `PWRKEY` and handles it by keeping the
dangerous path disabled behind a flag until the offsets are confirmed
against a schematic.

**What is not blocked by it.** The driver is written for both buses
regardless, because that is the subsystem's shape rather than this bench's
wiring. What the board exposes decides which half gets hardware evidence
and which stays a compile-time claim, and the acceptance table will say
which is which.

---

## 4. A comment about the linter broke the linter, and the guard against that had a hole

**What happened.** The first push went red on shellcheck. One finding of six
was this project's: SC2013 on the loop that reads every `BENCH_ADXL345_*`
name out of the core and checks each is defined exactly once.

The finding was fair and its suggested fix was not. Shellcheck proposes
piping to a `while read` loop. That body increments two counters, and a
`while` loop fed by a pipe runs in a subshell, so both counters would come
back zero and the two assertions after the loop would pass whatever the
header contained. The suggestion would have turned a working check into one
that reports success because it counted in a scope nobody reads.

So it became a `disable` with the reasoning written above it. And the
second push went red on the same file.

**What was done.** The explanation began:

```
# shellcheck's suggested "while read" loop would be wrong rather than
```

A comment whose first word after the hash is the tool's name is parsed as a
directive. `shellcheck's` is not a directive key, so the file failed with
SC1073 before reaching the `disable` three lines below it. **The comment
explaining the fix disabled the fix.**

Reworded so the name never opens a line. Then the more useful half: this
repository already has `check_shellcheck_directives` in `scripts/lint.py`,
written after the same class of comment reached CI three times. It did not
catch this one. Its pattern was

```
^\s*#\s*shellcheck\s+(\S+)
```

which requires whitespace after the name. An apostrophe is not whitespace,
so the rule never matched, while the real tool still tried to parse the
line. The pattern now captures whatever is glued to the name instead of
requiring a space, because nothing glued to it can be a directive key.

**Why that and not the alternative.** The alternative was to reword the
comment and move on, which fixes this file and leaves the guard as narrow
as it was. That guard exists precisely because this keeps happening, and it
has now happened a fourth time with the guard watching.

Proved by construction rather than by assertion: five comment forms through
the rule, and the two prose forms are flagged while `disable=SC2013`,
`shell=sh` and a mid-sentence mention of the tool are accepted. The first
attempt at that proof was itself wrong, grepping for the probe file's name
and matching lint's untracked-scripts note instead of the directive
message, so every form came back FLAGGED including the legitimate ones.

**What this cost.** Two round trips to CI, about twenty minutes each,
for a defect that no check on the authoring machine can see, because there
is no shellcheck on it. The widened rule closes exactly that gap: it is the
part of shellcheck's judgement that can be reproduced without shellcheck.

## 5. A rebuild that could not start, then a recipe that had never compiled

Friday 9 October 2026. The i2c-dev packaging fix of the morning needed a
rebuilt image, and the build script refused before BitBake ran: the
Windows drive behind WSL had 16 GB free and the guard wants 25. The two
things the script's own warnings named, a stray build tree inside the
checkout and a stray layer clone, measured 4 KB and 7.9 MB. They were not
the problem.

**Where the space was.** The virtual disk file was 86.48 GB of the 109 GB
in the Windows profile's AppData. Inside it the guest used 80 GB, of which
`~/bench` held 55: `build/tmp` 16 GB, `downloads` 17, `sstate-cache` 17,
archived images 2.8, project 2's NEO Air root filesystem 3.4. Only
`build/tmp` is reproducible, and it held one image not yet archived, the
project 9 debug image of Monday 5 October 2026, which was archived first.

**What returned the space.** `rm -rf ~/bench/build/tmp`, then
`sudo fstrim -av`, then `wsl --shutdown` as the owning user with
`wsl --list --running` printing none, then `diskpart` with the file
attached read-only and `compact vdisk`. C: went from 15.44 to 26.2 GB
free and the file from 86.48 to 75.7 GB. On Friday 2 October 2026 the
same compaction returned 0.14 GB, and the difference is the trim: ext4
reports freed blocks on `fstrim`, not on `rm`, and the file size does not
move at the trim, so the trim looks like it did nothing until the
compaction collects it.

**Then the build found a defect the cache had been hiding.** With
`build/tmp` gone, `bench-iio` compiled from source for the first time in
this tree, and its link failed on every libiio symbol. The first line of
the log was the cause: `pkg-config: not found`. The recipe runs pkg-config
in `do_compile` and never inherited the `pkgconfig` class, so no native
pkg-config was in its sysroot; the shell substituted an empty string and
the compiler ran on without the flags. Three sibling recipes inherit the
class. This one had a comment explaining why pkg-config was the right
choice and no line making it available.

Fixed with `inherit pkgconfig`, and `scripts/lint.py` gained
`check_pkgconfig_inherit`: a recipe whose non-comment lines run pkg-config
must have an inherit line naming the class. Proved in both directions. The
first version of the rule flagged nine recipes, because the regex written
through a heredoc had lost its backslashes and `\b` had become a backspace
byte, which the linter's own control-byte rule reported in the same run.
Rebuilt with `chr(92)`, the rule flagged exactly `bench-iio` and no other,
which is the whole-tree check: the other seven recipes that run pkg-config
all inherit the class. After the fix it is quiet.

**One provenance note.** The archive made before the deletion was stamped
`2026-10-09_a4c0c08-dirty`, the checkout at archive time, not `c246665`,
the commit the image was built from. `scripts/archive.sh` records the
commit it finds, not the commit the build recorded. A late archive
therefore mislabels itself, and that is an open item for the script.

**The second run was refused by the guard the first run had satisfied.**
Recreating `build/tmp` for this configuration grew the virtual disk by
about 17 GB: the 11.7 GB of slack inside it first, then 6 GB of the
Windows drive, which went from 26.2 to 20 GB free. The second run needed
one recipe and an image assembly on a `tmp` that was now resident, and the
guard demanded 25 GB for it, the figure for a build from nothing. Nothing
left inside the guest could clear that, which is the shape the bench has
learned to distrust: a guard whose remedy cannot be run from where the
operator stands gets switched off.

So `scripts/build.sh` now asks which case it is in. With `build/tmp`
absent it wants 25 GB on the Windows drive, the cost measured today. With
`build/tmp` resident it wants a floor of 5 GB, a figure chosen rather than
measured, and the script prints which model applied so the number can be
argued with.

## 6. The recipe BitBake never scheduled

Friday 9 October 2026, later. With the disk freed and `bench-iio` fixed,
the image assembled for twenty minutes and `do_rootfs` refused three
packages: this project's own driver, `kernel-module-bench-adxl345-core`,
`-i2c` and `-spi`. The in-tree `kernel-module-adxl345-i2c` and `-spi`
were found. The first thought was a module that built under another
name, so the work directory was the place to look, and it did not exist.
`bitbake -g` then showed the recipe list for the image: `bench-iio` and
`linux-raspberrypi` on it, `bench-adxl345` not.

The mechanism is in decision 118. In one sentence: the packages exist
only after packaging, so at parse time BitBake matches their names
against dynamic patterns, the kernel declares the same pattern as every
module recipe and is a preferred provider, so the kernel won all three
and this recipe was never built. Project 9's `bench-buggy` carries the
one line that prevents it, `RPROVIDES:${PN}`, with a comment calling it
a convenience.

**The fix is that line, three names long**, and the comment in
`bench-buggy` corrected to say what the line is for. The linter gained
`check_module_rprovides`, which reads a module recipe's Makefile for its
`obj-m` targets and requires each as a provides; it fired three times
with the block removed and was quiet with it restored.

**What the sibling rule did and did not do here.** Reading `bench-buggy`
first found the difference in one pass, which is the rule working. Its
own comment then pointed away from the answer, which is the limit of the
rule: a sibling's explanation of itself is a claim like any other.

The image has still not been assembled. Next is a rebuild with the recipe
scheduled, then the flash and the three checks on the board.

## 7. The driver meets the kernel it will run on

Friday 9 October 2026, later still. With the recipe scheduled, the three
sources compiled against a real kernel tree for the first time, and the
core file stopped on three errors. Section 2 of this journal records
that the driver was written with Linux v6.12 as its cited reference. The
image carries 6.6.63. Every one of the three, and a fourth the compiler
had not reached, is a difference between those two kernels:

| Line | What 6.12 accepts | What 6.6 needs |
|---|---|---|
| the scan timestamp | the `aligned_s64` typedef | `s64` with `__aligned(8)`, which is how 6.6's own drivers write it |
| `dev_fwnode` and `fwnode_irq_get` | reached through another header | `linux/property.h` named directly |
| `devm_iio_kfifo_buffer_setup` | reached through another header | `linux/iio/kfifo_buf.h` named directly |
| the symbol namespace | a quoted string, which is the spelling from 6.13 | a bare identifier; 6.6 stringifies the argument itself, so the quotes would have become part of the name on the export and both imports |

The two bus files compiled; their only change is the namespace spelling,
which has to match the core's.

**None of this was knowable on the authoring laptop**, which has no
kernel tree and is not allowed to compile, and the file's own header has
said since it was written that it had never been compiled. That sentence
stays until a build proves it false; it is the next thing this journal
expects to record.

The fourth row is the one worth a sentence. It would not have stopped the
compile. With 6.6 stringifying a quoted argument, the export and the two
imports would all have carried the quote characters inside the namespace
name, matched each other, and loaded. A reader of `modinfo` would then
have seen a namespace with quotes in it and wondered what the author
meant. It was fixed because the version difference was known once the
other three had named the kernel, not because anything reported it.

## 8. The card, the board, and a line the alphabet removed

Friday 9 October 2026, evening. The image built at `b20546d`, was
archived with the right commit this time, and was flashed to the Pi 3B+
card over the project 9 image. Before the card left the reader the root
partition was mounted read-only and listed: the three project 5 modules
under `updates/`, mainline's three in the kernel tree, `i2c-dev` and
`spidev` in the builtin list, and the three tools. The credential file
was written as a derived key rather than a passphrase.

**The flash script found a defect before the board did.** Its overlay
check reported `vc4-kms-dsi-7inch` requested, which this project's kas
file says it replaces. The card's `config.txt` had the DSI line, had
`dtparam=i2c_arm=on`, and did not have the 400 kHz line. Decision 119
has the mechanism: kas orders the sections by name, `adxl345` sorts
before the shared `bench`, so the shared assignment won. The fix is a
remove and an append, a linter rule, and the same conversion in seven
other kas files, one of which, project 19's, had lost its lines the
same way. This card runs the bus at 100 kHz and that is recorded here;
the rebuild waits.

**On the board, three answers.** `/dev/i2c-1` exists on a freshly
flashed image with nothing loaded by hand, which is the proving check
written into the kernel fragment that morning and it passes. The scan
of bus 1 shows no device at any address. The read at 0x53 fails.

So the bus is up and nothing on it answers, and the question moves from
software to the eight pins of the breakout. The datasheet, revision G,
requires `CS` high for I2C mode and `SDO` low for address 0x53; a `CS`
left unconnected puts the part in SPI mode, which produces exactly this
scan. That is a candidate, not a diagnosis. The wiring is being read off
the board by eye before anything else is concluded, which is the rule
this bench learned from a mechanism invented about a HAT that did not
seat.

## 9. The part answers, and the record was six days stale

Friday 9 October 2026, late. Twenty-one scans of bus 1 before any wire
was touched: mostly empty, `0x53` on some, `0x1d` on two, and twice a
block of thirty or more phantom addresses. The datasheet gives the part
exactly those two addresses, chosen by `SDO`, so a part showing both in
one sitting has that pin connected to nothing; the empty scans fit a
floating `CS`, which page 17 says leaves the interface mode undefined;
the blocks fit a contact, not a device. That reading was written down
before the wiring was asked for, so it could be wrong.

It was not. Read off the board: `VCC` on pin 1, `GND` on 9, `SDA` on 3,
`SCL` on 5, and nothing on `CS`, `SDO`, `INT1` or `INT2`. The design
document's wiring table, headed "as built", showed seven leads including
both straps, copied from project 11's evidence of Saturday 3 October
2026 on this same board. Six days later four of them were there. The
heading is corrected to say what a wiring table is: an observation with
a date.

With power off, `CS` went to pin 17 and `SDO` to pin 6, and every jumper
was pressed home. Three scans: `0x53`, nothing else. Then

    i2cget -y 1 0x53 0x00
    0xe5

the device identification value the datasheet fixes. The part, both
straps, both bus leads and the supply are good, at 100 kHz on this card.

**Two slips of my own in the record.** The hand-over put `SDO` on pin 6
without first reading the table that says the console sits on pins 6, 8
and 10; the console kept working, so the console's ground is elsewhere,
and where is an open row. And the colours of the two strap wires were
not asked for at the time they were fitted, so they are open too. Both
are recorded as open rather than filled in.

**What the day proved, in order.** A device node on a fresh image with
nothing loaded by hand; a recipe scheduled that never had been; a driver
compiled against the kernel it runs on; a card whose config lines match
its kas file, for every project that had been winning by alphabet; and
a sensor identified by its own register. What it did not reach: the
overlay that binds the project 5 driver to the part. That is next, and
with `INT1` unconnected the probe will take its sysfs-only path, which
is the honest state until that lead is refitted.

## 10. The overlay, written from a measurement

Friday 9 October 2026, night. The kas file had held the overlay line
back with a sentence: the node needs an address and an interrupt GPIO
that are properties of how the breakout is wired, and a guessed
interrupt does not fail safely. Both properties were read off the board
this evening, so the sentence has done its job and the overlay exists.

One node on `i2c1`, `adxl345@53`, compatible `bench,adxl345`, no
interrupt property. The address is the one three clean scans and a
`0xe5` confirmed. The absent interrupt is the honest description of a
breakout whose `INT1` pin is connected to nothing; the driver's probe
asks the node for one, finds none, and registers the sysfs path only.
The overlay's own comment carries the two lines to add when `INT1` is
back on pin 16, level-triggered for the reason project 10 measured on
its IMU.

The recipe is project 10's, copied rather than varied: `dtc-native`,
`allarch`, a deploy task into `overlays/`, an empty package. The image
gained the recipe in its install list and the two lines that copy the
`.dtbo` onto the boot partition before assembly. The kas file's
`:append` gained `dtoverlay=bench-adxl345`.

`tests/adxl345-overlay-test.sh` holds the four files to their
agreements with no dtc, kernel or board: the compatible in the overlay
equals the one the bus file matches, the address equals the measured
one, the `.dtbo` name is the same in recipe, image and config.txt, and
the node declares no interrupt while the design's wiring table says
`INT1` is not connected. Sixteen assertions; flipping the compatible to
mainline's string in place made two of them fail and restoring it made
all sixteen pass. The last group is the one written to be replaced: when
`INT1` is refitted the assertion inverts, and the test says so.

What the board will say next is the first thing this project's driver
has ever been asked: whether its probe reads `0xe5` itself and
registers an IIO device. That is criterion 2, and the flash-time overlay
check will have already said whether the `.dtbo` reached the card.

## 11. The driver binds, reads, and sets its rate; the bus speed does not survive the wiring

Friday 9 October 2026, night. The card at `76d1e89` carried the overlay,
and the flash-time check said so: `bench-adxl345` requested and present.
It also said the DSI overlay was still requested, which the `:remove` in
the kas file was supposed to prevent. It could not: the lines of that
variable are joined by a literal backslash and n that only rpi-config's
`echo` turns into line breaks, so to BitBake the value is one token and
`:remove` found nothing. Decision 119 is amended; six kas files use
`:forcevariable` and the linter refuses the `:remove`.

**On the board, the overlay did everything an overlay does.** The device
`1-0053` existed, udev loaded all three modules unasked, and the probe
ran and asked the part for its identification. The part answered with a
NACK. At 400 kHz, which this card was the first to carry, two scans
showed nothing and `i2cget` failed where the same part had read `0xe5`
at 100 kHz an hour earlier. The baud rate line was removed by hand on
the card and nothing else was touched: `53` twice, `0xe5`. The kernel's
view of the bus, read from `of_node/clock-frequency`, was 400000 before
and 100000 after. So the speed was the variable, on this wiring. The
kas file now says 100 kHz, with the datasheet's consequence stated: the
output data rate at that bus speed tops out at 200 Hz, which serves
criteria 3 and 4 and not the FIFO rates of criterion 5. The way back to
400 kHz is shorter wires.

**The probe then failed once more and succeeded twice.** On the 100 kHz
boot the read at 7.09 s was a NACK while the same read from the shell
at 355 s succeeded, and a `bind` from sysfs probed cleanly: `no
interrupt, so sysfs only and no buffer`, `iio:device0`. A reboot with
nothing changed probed cleanly at 7.07 s. One failure in two boots at
this speed is an event, not a mechanism, and no retry goes into the
probe on its strength. Every further boot is an observation.

**Then three criteria in three commands.** `name` `bench-adxl345`,
`in_accel_scale` `0.038245935`, axes `-8`, `46`, `242` with the board
flat, which is 0.95 g on z. `in_accel_sampling_frequency` took 100 and
gave back `100.000000`, took 3200 and gave back `3200.000000`. The
acceptance table had named that file `sampling_frequency`, which does
not exist because the channel declares its rate shared by type; the row
is corrected, and the prefix is the one mainline's driver uses, which
the A/B comparison will want.

**One nag, fixed.** The SPI bus file logged "no spi_device_id for
bench,adxl345": the SPI core derives a fallback id by dropping the
vendor prefix and looks for `adxl345`, which the table lacked. It has it
now.

Four of eight criteria measured, on the first evening this driver has
run. The card carries a hand-edited `config.txt`; the next flash makes
the 100 kHz line the image's own.

## 12. The card that needs no hand edit

Friday 9 October 2026, late. The image at `ef8ef05` was built, archived
and flashed. The flash-time check requested two overlays, `bench-adxl345`
and `vc4-fkms-v3d`, and no DSI line: the `:forcevariable` did what the
`:remove` had not, and the linter's new refusal of `:remove` on that
variable now has a card behind it. The card's `config.txt` carries the
100 kHz line as the image's own, with no hand edit anywhere on it.

The board booted and the probe bound at 7.39 s on its own, with the SPI
id nag gone. `of_node/clock-frequency` read 100000. `iio:device0`
exists. At 100 kHz that is two clean boots against one failed; the
failed one stays on record as an event.

**The rebuild aborted once more before this, and the second observation
changed the diagnosis.** The pseudo abort in `do_package` of
`bench-adxl345` came back on a rebuild that followed a one-line source
edit, with no other configuration run in between and no kernel
recompile. So the earlier account, that the kernel's recompile was the
trigger, was at best half of it; what both aborts share is a rebuild of
this one recipe into a work directory that `RM_WORK_EXCLUDE` had kept,
while the kernel, kept the same way, rebuilt twice without complaint.
The mechanism inside pseudo is not established. The exclusion for the
module is dropped, with the reason that the files it kept for
inspection are on every card and in every archive, and the kas file
says in its own comment what would prove that change wrong: the same
abort on the next rebuild after it. The remedy that worked both times,
`cleansstate` on the recipe, is recorded for that case.

Four criteria measured, three images on the card today, and the next
work is wire rather than software: `INT1` back on pin 16 for the FIFO
path, and shorter leads before 400 kHz is tried again.

## 13. INT1 wired, and the FIFO path measured in two rounds

Friday 9 October 2026, 21:00 to 21:45. `INT1` went onto header pin 16,
GPIO23. The overlay gained its interrupt, level high for the reason
project 10 measured on its IMU, and the no-board test inverted its last
group: it now holds the overlay's interrupt to the design's wiring
table instead of asserting there is none.

**First round, image `5a97fe5`.** The probe took the interrupt: no
"no interrupt" line, and `buffer`, `scan_elements` and `dev` under the
device. `iio-rate fifo` at 100 Hz delivered 960 samples in ten seconds
at both watermarks, which is the FIFO path working on its first run.
Around that measurement, four things were wrong and none was in it:

1. the tool died at `date -I` mid-run, a GNU option BusyBox does not
   have; project 10 had only ever run on a Raspberry Pi OS card
2. it counted zero interrupts, because it looked for `lsm6`, the name
   the ST driver gives its line; ours was named after the bus address
3. the timestamp spread was 49 and 27 milliseconds, every sample in a
   batch carrying the interrupt time, where the design promises each
   spread back at the period
4. `buffer/watermark` was accepted and ignored: the driver had no hook,
   so the part ran at 24 whatever was written

And one before any of those: the tool wrote the rate to
`sampling_frequency`, which this driver, like mainline's, does not have;
its file is `in_accel_sampling_frequency`. The image recipe's "without
a line of change" was retired.

**Second round, image `6d41adc`.** Interrupt line named after the IIO
device, the tool matching it by default and saying so, the date spelled
out as a format, the hook in `iio_info` where this kernel looks for it,
and each FIFO sample pushed at the interrupt time minus its distance
from the newest at the cached period. Then the two runs that could fail:
40 interrupts at watermark 24 against 4.17 per second expected, 120 at
watermark 8 against 12.50, ratio 1.0 both, spread 1.7 and 0.96
milliseconds. The rows are in `docs/evidence/fifo-rates-2026-10-09.csv`.
Criterion 5 is measured.

**One more found by the run itself.** Both captures were asked for five
seconds and ran ten: the usage line had promised `-d SEC` since the
program was written and nothing read it. Parsed now, with a test.

Five of eight criteria measured. Open on the driver side: the tap and
free-fall events of criterion 6, which need the interrupt and now have
it, the A/B comparison of criterion 7, and the symbol check of
criterion 8. Open on the bench: the `INT1` wire colour, the console's
three pins, and shorter leads before 400 kHz.

## 14. The events that no hardware could have reached

Friday 16 October 2026. The open criterion was 6, the tap and free
fall events, and the obvious next step was to flash a card and tap the
breakout. Reading the driver first was cheaper and it is as well:
**the three events could not have fired.**

The handler reads `INT_SOURCE` and pushes single tap, double tap and
free fall. Nothing in the driver ever set those three bits in
`INT_ENABLE`, and nothing ever wrote `THRESH_TAP`, `DUR`, `Latent`,
`Window`, `THRESH_FF`, `TIME_FF` or `TAP_AXES`. The acceptance table
called that "Configured", which is what this bench means by a file
saying so, and no file said so.

**The datasheet settles it rather than leaving it as an inference.**
This repository had never recorded what the event registers mean, so
the datasheet was fetched again, from a mirror that serves Revision 0;
the project otherwise cites Revision G, and both revisions are now
named wherever they are used. Page 17 draws the distinction the defect
turned on: for data ready, watermark and overrun, `INT_ENABLE` enables
only the interrupt output and the functions are always enabled, and
`INT_SOURCE` reports them regardless. For every other bit, a clear
enable bit means the detection function does not run. So the part was
never asked to detect a tap. Three of the parameter registers reset to
zero as well, and zero disables tap outright in `DUR` and double tap in
`Latent` and `Window`, which would have been a second reason for
silence.

**What the driver does now.** It declares the three events in an
`iio_event_spec` on a channel of their own, which exists because an
event only reaches user space as a named attribute if some channel
declares it with the modifier the handler pushes, and no scan channel
carries `IIO_MOD_X_OR_Y_OR_Z`. It writes the seven parameter registers
at probe, two of them inside the ranges page 15 and page 16 recommend
and four of them this bench's own choice, said so on each line. It arms
nothing: `INT_ENABLE` is touched only from `write_event_config`, so an
event fires when somebody enables it and not before. And it drops the
event channel entirely when `INT1` is not wired, because an enable that
writes a register and then waits for a line nothing drives is the same
failure the overlay refuses for the same pin.

The tap threshold is readable and writable through the standard event
attribute, in the part's own counts rather than converted to the
channel's units: 62.5 mg per count against the channel's 3.9 mg is a
ratio of 16.03 that the datasheet does not bless, and a value that read
back as something other than what was written would be worse than a
count with its scale factor beside it in the header.

**Eighteen assertions, and the proof found a nineteenth defect.**
`tests/adxl345-driver-test.sh` now requires every `IIO_EV_DIR_` the
file names to be declared in an event spec, the seven registers to be
written at probe, the three timings to be non-zero, the two free fall
values to sit inside the datasheet's recommended ranges, and
`setup_events` never to touch `INT_ENABLE`. Breaking each of them fires
the matching assertion. Running that proof is what showed the block had
been appended **after** the suite's summary and its `[ "$fail" -eq 0 ]`,
so eighteen assertions were outside the count and could not fail the
run: with three of them failing the suite still exited zero and printed
"47 passed, 0 failed". The block now sits above the summary, the count
reads 65, and a single failure fails the run, which was checked both
ways.

Nothing here is measured. The next thing the board can say is whether a
tap on the breakout arrives as an IIO event, and that needs a build, a
flash and a hand on the part.

## 15. The evidence the criterion asked for was in no image

Friday 16 October 2026, same sitting. With the events declared, the
next step was to flash a card and tap the breakout while something
watched. Two documents name what should watch: `iio_event_monitor`.
**Nothing in this layer packages it.** It lives in the kernel tree
under `tools/iio`, no recipe builds it, and no bench image has ever
contained it, so criterion 6 asked for the output of a program that was
shipped to no board. That is decision 75 one storey up: the tool a
criterion depends on is as much a packaging question as the module a
device depends on.

Events cannot be read from the shell either. They do not come through
the buffer character device; the IIO core hands them out on a second
descriptor obtained with an ioctl, so reading them needs a program.

**`iio-events` is that program**, added to `bench-iio`, which is
Project 10's tooling and is already installed in Project 5's image. It
takes a device name, finds the number by reading each `name` attribute
rather than guessing a range, refuses a device that has no `events`
directory instead of waiting forever on a device whose driver declares
none, and prints one comma separated line per event with the kernel's
timestamp. It links against nothing: the ioctl and the uapi headers are
the whole interface, which matters because Project 5's image carries
this recipe and not libiio.

It arms nothing. An event fires only while its `_en` attribute is 1,
and deciding to arm one is a decision about hardware that belongs to
whoever is at the bench.

Both documents now name the tool that exists, and the suite has a rule
for the shape: the tool named in criterion 6's evidence column must
appear in a `do_install` line of a recipe the image installs. Pointing
the column at a tool nothing installs fails the run, which was checked.

Still not measured. The build is the first compile of the event code
and of this program, and the board is the only thing that can say
whether a tap arrives.

## 16. The step that was skipped once too often is now the script's

Friday 16 October 2026, late. The card was flashed with the new image
and the board came up on no network. The phone running the hotspot
showed no client, a sweep of the whole subnet from skyhorizon found no
Raspberry Pi, and the Pi 3B+ has no serial console on this bench, so
there was no way in at all. The cause was not subtle: flashing erases
the card, `wifi.conf` lives on the card, and the line in the hand-over
that says to write it again was skipped.

**It had been skipped before.** The repository has carried a note about
offering that file before a card leaves the reader since September. A
note is not a fix; it is a thing to skip.

So the file is no longer typed after every flash. It is typed once, on
the build laptop, into a store outside the repository and outside every
image, and `scripts/flash.sh` copies it onto the card while the card is
still in the reader:

    ./go credentials          once, ever
    ./go flash /dev/sdX ...   copies it from then on

`scripts/credentials-set.sh` prompts with the terminal's echo off,
stores the derived 64 character key rather than the passphrase, prints
only that each field is set, and restores the terminal on an interrupt
so that a cancelled prompt does not leave an invisible shell.
`scripts/credentials.sh` does the copying and the refusing, and it only
speaks when the rootfs actually carries the provisioning program, so an
image that configures no network is never nagged. A card that needs the
file and has no copy to take it from fails the flash, because an
unreachable board and a broken card are the same thing on a bench with
no console.

Thirteen assertions in `tests/credentials-check-test.sh`, including the
two it must stay silent for. The case it exists for is the first one in
the file.

## 17. Criterion 6 measured, and the evening it cost to get there

Friday 16 October 2026, late. Two double taps and a free fall arrived
through the IIO character device, decoded by `iio-events`. The evidence
and its caveats are in `docs/evidence/events-2026-10-16.md`: one
interrupt carried two of the three, the bus was NACKing writes minutes
either side of the run, and single tap did not appear on its own
because the part reports the double tap when both are enabled and both
are satisfied.

**The hour before it is worth more than the result**, because none of
it was about the driver.

| What cost time | Why | What now carries it |
|---|---|---|
| the build ran on last week's commit | the pull between the push and the build was skipped; caught only by reading the commit in the build banner | nothing yet, see below |
| the flash erased `wifi.conf` and nobody wrote it again | it was a line in a hand-over, and that line had been skipped before | `./go credentials` once, and `scripts/flash.sh` copies it onto every card |
| the board was then unreachable | no network, and this board has no usable serial console | the same change; a card that needs the file and has no copy now fails the flash |
| `bmaptool` refused the card | a mount from an earlier step was left open, and the failure named errno 16 rather than the mount | `scripts/flash.sh` refuses a mounted target up front and prints the `umount` line |
| three subnet sweeps found nothing | the ping objects were discarded before their operations completed, so nothing populated the ARP table | the sweep that works keeps the tasks and waits for them |
| `i2cget` reported the part busy | the driver was bound to it, which is `UU` in a scan and is correct | nothing to fix; read through sysfs while a driver owns the address |

**The mount and the credential file are the same mistake twice**, and
it is mine: a step that changes state was handed over with its undo
further down a list, and the middle of the list was overtaken. Both are
now the script's business rather than the operator's.

**What is deliberately not fixed tonight.** The card cycle is still
eight steps across two shells: find the bus id, attach, read the device
letter, unmount leftovers, flash, unmount, detach, and the letter and
the bus id both move between sessions. A `./go card flash` that does
all of it is drafted and untested, and an untested script that erases a
card has no business in this tree. It is the next thing to finish.

## 18. The part remembers, and a probe that merges bits cannot know

Friday 16 October 2026, after the events. Three sysfs reads returned
EIO, then returned numbers: minus 1344, minus 320, minus 3776, the same
five times running. Steady, so not noise, and every one an exact
multiple of 64.

That multiple is the whole thread. `DATA_FORMAT` has a Justify bit that
left-aligns the sample in its word, which multiplies a thirteen bit
reading by eight and a ten bit one by sixty four. Rebinding the driver
restored resolution and range, because probe writes those, and the
readings became multiples of eight instead: the bit probe does not
write stayed set.

Reading the register settled it at `0xaf`. Three bits that should be
zero were set: SELF_TEST, which applies an electrostatic force that
deflects the beam, INT_INVERT, which makes the interrupt active low
while the overlay asks for level high, and Justify. A dump of the
surrounding registers found three more things: the offset trim held up
to 1.9 g, `BW_RATE` held 12.5 Hz while the driver's cached sample
period said 100, and `INT_ENABLE` had data ready, activity and
inactivity on.

**None of it could have come from this driver**, and all of it survived
every reboot of the evening. The ADXL345 has no reset pin and no
software reset: only removing power returns its registers to the
datasheet's defaults. So a probe inherits whatever the last session
left, including a session that was writing to a bus that was NACKing,
and `regmap_update_bits` over a partial mask leaves every bit outside
the mask exactly as it found it.

Every one of those produces readings that look like data. That is the
shape this bench keeps meeting and it is worth naming once more: a
wrong number that is obviously wrong costs an hour, and a wrong number
that is plausible costs a conclusion.

**The fix is coverage rather than cleverness.** Probe now writes
`DATA_FORMAT`, `POWER_CTL`, `BW_RATE` and `INT_ENABLE` whole, clears
the three offset registers, and takes its cached sample period from the
same constant it writes to `BW_RATE`, so the two cannot drift apart.
Fourteen assertions hold it there, and they read the probe alone rather
than the file, because `bench_adxl345_powerdown` clears one bit with
`update_bits` on remove and that is correct; the first version of the
rule flagged it.

The event evidence of an hour earlier now carries this as a caveat: it
proves the path end to end and it was taken with the interrupt polarity
inverted relative to what the device tree declares.

**The offsets were the cause, and the experiment that seemed to
contradict it was reading a stale sample.** Writing the three registers
to zero by hand appeared to change nothing: the axes still read minus
358, minus 230 and 729, so the claim was withdrawn. A dump taken a
minute later settled it the other way. The offsets read `00 00 00`, and
the data registers held minus 9, 57 and 242, which is gravity and is
the same reading this board gave on Friday 9 October 2026. Through
sysfs a moment later: minus 10, 55, 241.

**Why the first read lied.** Unbinding the driver runs its powerdown
action, which clears the measure bit, and a part that is not measuring
keeps its last conversion in the data registers. The rebind set
measuring again and the sysfs reads in the same command line ran within
microseconds, before the first new sample existed: at 100 Hz that takes
10 ms. So the values returned were the ones taken before the offsets
were cleared. **A read immediately after a bind can be older than the
configuration it is being used to test**, which is a trap worth the
sentence it costs.

The withdrawal is itself withdrawn, and the sequence is left in this
entry rather than tidied away, because the shape is the useful part: a
claim, an experiment that seemed to refute it, and a second measurement
showing the experiment was the thing at fault.

The arithmetic that pointed at it was the magnitude. Minus 358, minus
230 and 729 make 844 counts, which is 3.3 g, and a part at rest cannot
see that at any orientation. A reading whose length is wrong is wrong
whatever its direction looks like.

## 19. The storm, measured, and single tap on its own

Friday 16 October 2026, close to midnight. Two numbers finish the
evening.

**The interrupt storm was real.** With `INT_ENABLE` holding the `0xba`
it inherited, the line at `/proc/interrupts` gained 5,726 counts across
four processors in five seconds, about 1,100 a second, with nothing
touching the board. Data ready asserts `INT1` on every sample and this
handler never clears it, because it reads the data registers only when
the watermark bit is set, so a level-triggered line stays asserted and
the threaded handler runs again and again, each time doing an I2C read
for nothing. Clearing that register by hand, which is what the fixed
probe now does, took the next five seconds to zero additional
interrupts. That is the defect of section 18 priced: a driver that
cannot put the part into a known state had been spending about a
thousand interrupts a second for an evening.

**Single tap on its own works**, which the first event run could not
show because double tap was armed beside it and absorbs the second of a
pair. With only single tap enabled: 33 events in 20 seconds from of the
order of a dozen knocks, in
`docs/evidence/events-singletap-2026-10-16.csv`.

**One knock is not one event.** The 33 fall into about fourteen
clusters, two to four events each, one to seven milliseconds apart
inside a cluster and a second or more between them. That is the
breadboard ringing: the acceleration crosses 3 g several times as it
decays and each crossing that satisfies `DUR` is a tap by the part's
definition. The ADXL345 has no refractory period for single taps; the
suppress bit governs double taps only. An application that treats one
event as one tap will see three, and that belongs in the record rather
than in the surprise of whoever writes it.

Criterion 6 is measured, and with it six of eight. What remains needs
no new hardware: criterion 7 is the one word swap to mainline's driver,
which currently means a rebuild because the compatible string lives in
the overlay source, and criterion 8 is the symbol check on the build
host.

## 20. Double tap is the quiet one, and the poll path was reporting a zero nobody measured

Saturday 17 October 2026, just after midnight. Two more runs on the
wired part, and the second one found a defect in the instrument rather
than in the driver.

**Double tap alone: 17 events in 20 seconds, one per pair.** The gaps
are between 0.93 and 1.20 seconds, which is the hand knocking. Nothing
clusters, where single tap on the same mount gave two to four events
per knock milliseconds apart. The reason is the gesture's own
definition: a tap, 100 ms of quiet, then a second tap inside 300 ms.
Breadboard ringing inside the latency window is not a second tap. So
the more complicated gesture is the better behaved one on a noisy
mount, which is worth measuring rather than guessing. Evidence in
`docs/evidence/events-doubletap-2026-10-16.md`.

**The polled path: 98 reads a second, and a CPU figure that was never
taken.** `iio-rate poll` printed `reader cpu 0%` and wrote a zero into
`rates.csv`. It had measured nothing: the poll path passed an empty
value and `emit` defaulted it with `${cpu_pct:-0}`. A number nobody
measured sitting in a results file beside numbers somebody did is the
thing this repository's own rules call worse than a blank, and it was
in its own tooling.

Two fixes. `emit` now prints "reader cpu not measured on this path" and
writes an empty column, so nothing is invented. And the poll path
measures itself, counting children: its loop forks a `date` and a `cat`
every iteration, so the work is in the forks, and `cpu_ticks_of` was
reading only fields 14 and 15 of `/proc/PID/stat`, which exclude them.
A loop that keeps a core busy was reporting nothing at all.

**And the 98 is not what it looks like either.** It is the rate at
which this board can fork two processes, not what the bus or the part
can do. The comment above that loop already said the naive loop is the
thing being measured, which is fair, but the number must not be read
beside the FIFO path's 96 samples a second as though they were
comparable: the FIFO delivers 96 distinct samples, and the poll loop
re-reads one register 98 times.

Three assertions hold the fix, including one that greps the source for
the default that invented the zero.

## 21. The third path does not exist

Saturday 17 October 2026. The next thing to run on the wired part was
the trigger path, to put all three of the design's paths beside each
other. It cannot be run: the driver has no trigger support at all. The
word does not appear in the source, and the device listing taken an
hour earlier has no `trigger` directory, which is why nothing noticed.

`docs/DESIGN.md` has carried a table of three paths since before the
driver was written. Two of them are real: polled sysfs reads, and the
hardware FIFO drained by the threaded interrupt. The middle row,
a triggered buffer, was a plan that the table states as a fact, and the
table has been read as a description ever since.

The gap is now in that table rather than in nobody's head. Implementing
it means `iio_triggered_buffer_setup` and a pollfunc that reads one
scan, and it is worth doing because the comparison Project 10 exists to
make is only interesting across three paths: an hrtimer trigger
timestamps in the IIO core, where the FIFO path assigns timestamps from
arithmetic and will always look better for a reason that has nothing to
do with the hardware.

Same shape as the events of section 14 and as every other claim this
bench has had to correct: written as an intention, read as a fact,
checked by nothing.

## 22. The red CI was mine, and a week old

Saturday 17 October 2026. Four red runs in an hour turned out to be
two separate things, and shellcheck was only the smaller one.

**The one that had been red for a week.** `tests/lcd35a-overlay-test.sh`
asserts that Project 7's kas file does not inherit the DSI panel
overlay, and it checked that by looking for the literal string
`RPI_EXTRA_CONFIG =`. Decision 119 replaced every plain assignment in
those files with `:forcevariable` on Friday 9 October 2026, so the
string went away and the test has failed on every push since. Nobody
read a run for a week, which is the part worth noticing: a check that
nobody reads is a check that is not running.

The assertion was about the spelling of an override rather than about
the thing it cared about. It now requires an override, because a plain
assignment loses to section ordering, and separately requires that the
value does not carry the DSI overlay. Putting that overlay back fires
both.

**The smaller one.** Three shellcheck findings in scripts written here,
on a laptop with no shellcheck. Guessing fixed two of six; running it
on skyhorizon named all six in one command. That command now sits in
the working notes and belongs in front of every push.

**And a gap found while looking.** CI compiles every C program in this
layer by name, which is thorough and has one failure mode: a new
program is invisible until a line is added. `iio-events` was written,
packaged, installed on a card and run on a board before anyone noticed
the list did not mention it. It has a line now.

The whole evening's shape, three times over: a claim with nothing
reading it. The events that could not fire, the design table's third
path, and a test asserting a string that had moved.

## 23. The third path exists, and the helper for it cannot be reached

Saturday 17 October 2026, later the same day. Section 21 named the
missing middle path and said what implementing it would take:
`iio_triggered_buffer_setup` and a pollfunc that reads one scan. The
pollfunc was right. The helper is not available to this driver, and
finding out why is the useful part of the afternoon.

That helper does three things: attaches a kfifo, allocates a pollfunc,
and sets `INDIO_BUFFER_TRIGGERED` in the device's modes. It lives behind
`CONFIG_IIO_TRIGGERED_BUFFER`, which `drivers/iio/Kconfig` declares with
no prompt, so nothing can ask for it and only an in-tree `select` can
turn it on. This driver is out of tree and selects nothing. Putting the
symbol in `adxl345.cfg` would be a line kconfig drops without a word,
after which the module builds, packages, installs and then fails at
`modprobe` with an unknown symbol, which reads like a corrupt `.ko`
rather than like a missing kernel option. The other way round, enabling
some unrelated in-tree driver that happens to select it, would make this
driver's buffer a side effect of another driver's presence.

**That is reasoning from how the symbol is declared, not a
measurement**, and `./go ksym -f adxl345` on the build host is what
would settle it. The reason it is safe to leave open is that the driver
no longer depends on the answer: it calls the three underlying exported
functions itself, and those need only `CONFIG_IIO_TRIGGER`, which
`bench.cfg` has set built in for every image in this repository since
Project 1. The capability is already on the board that is on the bench.

**One buffer, two paths into it.** The core decides which path a buffer
enable is for, in `iio_verify_update`, and its condition is that the
device declares `INDIO_BUFFER_TRIGGERED` and has a trigger attached;
failing that it falls back to `INDIO_BUFFER_SOFTWARE`, which is this
driver's FIFO path. So the buffer's `postenable` returns early when a
trigger is attached, leaving the part's FIFO in bypass with its
watermark interrupt off. Without that branch both paths fill one buffer
and a capture carries twice the samples either path produced, in an
order that reads as jitter rather than as a defect.

**And a board with no interrupt stops being a board with no buffer.**
The kfifo setup used to sit inside the `if (st->irq > 0)` branch, which
was right when the only way to fill it was the watermark interrupt. The
triggered path needs the buffer and not the interrupt, so the setup
moved out and the `INDIO_BUFFER_SOFTWARE` mode the helper declares is
taken back again when nothing can interrupt: a reader who enabled it
would otherwise wait on a buffer nothing can push into, with no error
anywhere. The probe's message changed with it, from `no interrupt, so
sysfs only and no buffer` to `no interrupt: no events, no fifo, buffer
needs a trigger`. The old wording is still quoted in the README and in
`docs/DESIGN.md` where it is evidence of what the board printed on
Friday 9 October 2026, with a note saying so.

**Seven assertions, and three of them were wrong first.** The suite now
reads the handler and the probe for the ways this path fails without
saying anything: a pollfunc with no hard-irq half, which leaves
`pf->timestamp` unwritten so every sample carries whatever was in that
field; an early return that skips `iio_trigger_notify_done`, which stops
the trigger for good after one failed bus read; either mode bit missing;
the buffer back inside the interrupt branch; either half of the setup
ops no longer asking which path it is for; and the promptless symbol
appearing in the fragment or the helper in the driver.

Each was then broken on purpose and watched to fail. Three needed
repair. The assertion refusing the helper matched the driver's own
comment explaining why it calls no helper, which is the third rule in
this repository to have been silenced by its own prose; it now carries
the open bracket of a call. The one-exit count was anchored to the start
of a line and the realistic defect, an indented `if (ret) return`, went
straight past it; unanchored, it then counted the `irqreturn_t` in the
function's own signature and read two before anything was wrong. Both
are in the test's comments, because the next person to write a text
assertion will reach for both spellings.

**What is not measured.** Nothing here has run. The card carries the
image built at `e3574c8`, which has neither the probe that writes whole
registers nor any of this, so the README's row 11 says configured and
names the commit the board is actually running. Attaching an hrtimer
trigger and reading one scan per trigger is the next thing the bench
owes this project, and it is behind the same rebuild as criterion 7.

**And the README's own state section had gone stale.** It opened with
"Written, not yet built" and "Nothing here has been compiled", both
true when written on Saturday 3 October 2026 and both false since
Friday 9 October 2026, when the driver compiled, bound and read
gravity. It also still called the overlay deliberately missing. Three
documents in this project have now had to be corrected for the same
reason, which is that no check in this repository reads a sentence.

## 24. Two lines that were never requests, and the check that said so

Saturday 17 October 2026, the build host. `./go ksym -f adxl345` had
never been run, which is half of criterion 8 and the only check in this
repository that can be run before a kernel is compiled. It indexed 20854
declarations in the 6.6.63 tree and refused the fragment.

Every symbol exists. Three have no prompt, where the fragment's own
header said one:

    PROMPTLESS  CONFIG_REGMAP_I2C   selected from 63 places in the tree
    PROMPTLESS  CONFIG_REGMAP_SPI   selected from 37
    consequence CONFIG_ADXL345      marked, selected by accel/Kconfig

`CONFIG_REGMAP_I2C` and `CONFIG_REGMAP_SPI` are the seam this whole
project is built on. The core reaches the part only through a struct
regmap, and those two symbols are what turn a bus into one. Both lines
have been in the fragment since the first day, both were written as
requests, and kconfig has been dropping both without a word ever since.

**They were right anyway, and that is the uncomfortable part.** The
modules loaded on Friday 9 October 2026 and the part bound and read
gravity, so `devm_regmap_init_i2c` resolved at modprobe and
`REGMAP_I2C` was certainly on in that build. Something in the BSP
defconfig selects it. So the fragment contained two lines that did
nothing, in a build that worked, and nothing in this repository could
have told the two situations apart until the check that exists for
exactly that was finally run.

Note the shape, because it is the same as this afternoon's
`CONFIG_IIO_TRIGGERED_BUFFER` question answered from the other end: a
promptless symbol is a prediction, and a prediction that comes true is
indistinguishable from a request until something reads the tree. That
one was reasoned about and worked around before it could cost anything.
These two were not reasoned about at all.

**What changed.** Both lines keep their place, because they are the
requirement and because a fragment with no line for a symbol is a
fragment `./go kconfig` cannot check. Both now carry a consequence
marker. The marker names the mechanism rather than a Kconfig path, so
the script reports the claim as unchecked, which is the honest answer:
it can verify that a named file selects the symbol, and that says
nothing about whether the driver in that file is enabled in this image.
Naming one of the 63 to make the output go quiet would have been the
kind of claim this week has been spent removing.

The `CONFIG_ADXL345` marker did name symbols rather than a file, so it
was reported unchecked too. It now names `drivers/iio/accel/Kconfig`,
which is the selector the run itself printed, so that claim is checked
against the tree from here on.

The suite gained an assertion per promptless symbol, which replaces one
that read the first marker in the file through `grep -n` and `cut`. The
moment a second marker appeared, that became arithmetic on three line
numbers, and under `set -eu` it ended the whole run mid-way: the proof
was watching it happen. Each of the three was then stripped of its
marker in turn and watched to fail, and a blank line inserted between
marker and symbol fails it too, which is `check-kernel-symbols.sh`'s own
rule about a marker's reach.

**What is still open.** Whether those two symbols are set in the
`.config` a build produces. `./go ksym` cannot answer it by
construction, and `./go kconfig -f adxl345` after the rebuild is the
second half of criterion 8.

## 25. Criterion 8 closed, and the kernel work directory that carries state both ways

Saturday 17 October 2026, 08:35 on the build host. `./go kconfig -f
adxl345` read the `.config` the kernel had produced at 07:44 and
reported every option of both fragments present:

    ok  CONFIG_REGMAP_I2C=y        the first prediction, now measured
    ok  CONFIG_REGMAP_SPI=y        and the second
    ok  CONFIG_ADXL345=m           with its two bus modules beside it
    ok  CONFIG_INPUT_ADXL34X off   which is what keeps those two satisfiable
    ok  CONFIG_IIO_TRIGGER=y       the one symbol the triggered path needs

That closes criterion 8, both halves on the same day. The two promptless
regmap lines of section 24 were predictions when they were written and
are evidence now: something in this configuration does select them, and
the check that can see it has run. `CONFIG_IIO_TRIGGER=y` is the other
one worth naming, because decision 120 rests on it. This morning it was
a line in `bench.cfg` and a claim in a comment; it is now a symbol read
out of the `.config` the image is built from.

**The build itself failed**, and not in anything this project wrote.
`linux-raspberrypi` `do_package` was stopped by pseudo:

    path mismatch [3 links]: ino 762980
      db  '.../packages-split/kernel-module-ad714x-6.6.63-v8'
      req '.../packages-split/kernel-module-cm109-6.6.63-v8'

Two different module package directories sharing one inode in pseudo's
database. The cause is visible in the hour before it: the earlier run
reached 5380 of 5423 tasks with `do_package` running, and the window it
ran in closed. A packaging task killed part way leaves `packages-split`
and the pseudo database describing different things, and the next run's
first act is to remove that directory, which is the operation pseudo
refused.

**The two halves of this are the same decision.** `kas/bench-adxl345.yml`
carries `RM_WORK_EXCLUDE += "linux-raspberrypi"` so that the kernel's
work directory survives, because `./go kconfig` reads the `.config` from
it and that is the only evidence criterion 8 can be measured from. The
same persistence is what carried a half-written `packages-split` from a
killed run into the next one. Tonight it paid both ways in one hour:
criterion 8 could be measured from a build that had failed, and the
build failed because the directory had been kept.

That is worth stating rather than fixing in a hurry. The alternative,
letting the kernel work directory go, would have left this morning with
no `.config` to read and criterion 8 still open.

## 26. The triggered path compiles, and the evidence for it is indirect

Saturday 17 October 2026, 09:00. The question left open since the
afternoon was whether the three IIO trigger primitives this driver now
calls are where it expects them in 6.6, since nothing on the authoring
laptop can compile a kernel module.

They are. The build tree's deploy directory carries two documents
stamped 08:25:56 today:

    runtime-kernel-module-bench-adxl345-i2c-6.6.63-v8.spdx.json
    runtime-kernel-module-bench-adxl345-spi-6.6.63-v8.spdx.json

**That is indirect and is reported as such.** The `.ko` itself is not
there to look at, because this recipe was dropped from
`RM_WORK_EXCLUDE` last week and its work directory is removed once it
completes, which is why the earlier `find` for `bench-adxl345*.ko`
returned nothing and proved nothing. What those documents do establish
is that the recipe got as far as packaging, and packaging is downstream
of `do_compile` and of modpost.

The inference from there is about modpost rather than the compiler, and
it is the half worth naming: a C file that calls an undeclared function
fails to compile, which covers the headers, and a module that calls an
exported-nowhere symbol fails at modpost, which covers the exports.
Modern kernels make that an error rather than a warning unless
`KBUILD_MODPOST_WARN` is set, and nothing here sets it. So
`iio_alloc_pollfunc`, `iio_dealloc_pollfunc` and
`iio_pollfunc_store_time` are both declared and exported in this kernel,
which is what decision 120 depends on and what makes the choice to reach
past `iio_triggered_buffer_setup` a working one rather than a plausible
one.

What remains is the board. `iio-rate trigger` against an hrtimer
trigger, one scan per trigger, with both the trigger's rate and
`in_accel_sampling_frequency` printed, on a card carrying this build
rather than `e3574c8`.

## 27. The card that carries the fix, and the third path measured

Saturday 17 October 2026, late morning. The image built at `8d17d9b`
went onto the card, and it is the first one to carry three things
together that the bench has only ever had separately: the probe that
writes whole registers, the three events declared on a channel so they
reach userspace, and the triggered path.

**The flash was one command and it did the step that cost Friday
evening.** Among its output:

    --- credentials  wifi.conf copied from /home/bing/bench/credentials

No editor, no retyping, nothing to forget. The overlay check passed on
the card itself rather than on the recipe: two overlays requested,
`bench-adxl345` and `vc4-fkms-v3d`, both among the 68 on the boot
partition.

**The probe, read off the part from a cold start:**

    0x1e 0x00    OFSX, the trim gone
    0x1f 0x00    OFSY
    0x20 0x00    OFSZ
    0x2c 0x0a    BW_RATE, 100 Hz
    0x2e 0x00    INT_ENABLE, nothing armed
    0x31 0x0b    DATA_FORMAT, FULL_RES and 16 g and nothing else

Friday's part held `0xaf`, `0xa9 0xba 0x7a`, `0x07` and `0xba`. The same
six reads, on the same wiring, with the only difference being which
image the card carries. `dmesg | grep -i adxl` returns one line, the
taint message, which is a probe that found what it expected and said
nothing.

**And the third path.** The capture and its arithmetic are in
`docs/evidence/triggered-2026-10-17.md`. Five scans, fired a second
apart through a sysfs trigger, came back 1.015137, 1.015712, 1.015848
and 1.015909 seconds apart, each carrying the moment its own trigger
fired. The axes read x -10, y 54, z 241 counts, a magnitude of 247.1
against the 246.5 the same board read through sysfs on Friday 9 October
2026: two paths, three weeks apart, agreeing to within a count.

The spacing is the whole point. The FIFO path assigns its timestamps by
arithmetic, counting back from one interrupt at the configured rate, so
its samples are evenly spaced by construction and would look identical
whatever the hardware did. These were measured by the core when
`iio_pollfunc_store_time` ran, and they carry the shell loop's own
overhead, about 15 milliseconds growing by a few hundred microseconds a
time. A number that could not have been predicted from the source is
the only kind worth capturing.

**What the image cannot do, found by trying.** `iio-trigger list` said
`/sys/kernel/config/iio/triggers/hrtimer does not exist`, and it is
right: `kas/bench-adxl345.yml` sets `BENCH_ADXL345_KERNEL` and not
`BENCH_IIO_KERNEL`, so `iio.cfg` and its `CONFIG_IIO_HRTIMER_TRIGGER`
are in Project 10's images and not this one. The sysfs trigger is in
`bench.cfg` for every image and was enough to prove the path.

It is not enough for the next question. A trigger faster than the part's
output rate re-reads one conversion, slower skips conversions, and
neither is an error or a report; measuring that wants a trigger at a
known rate. So does the criterion's own evidence line, which named
`iio-rate trigger DEVICE HZ`, a command this image cannot run. Both now
say so. Adding the switch is one line and a rebuild, and it is the right
thing to do before the three paths are compared rather than merely
listed.

## 28. The watermark nothing writes

Saturday 17 October 2026, afternoon, still on the card from section 27.
The triggered capture had left a buffer enabled, so reading two
registers off the part was free, and the first of them was the point:
with a trigger attached, `INT_ENABLE` read `0x00` and `FIFO_CTL` read
`0x00`. The core had chosen the triggered mode, the driver's
`postenable` had returned early, and the part's own FIFO was in bypass
with its watermark interrupt disarmed. Detaching the trigger and
enabling the buffer again gave `0x02`. That is today's two path branch,
measured on the hardware rather than asserted in a test.

**The second register was not what I predicted.** `FIFO_CTL` read
`0x81`, stream mode with a watermark of one, where the driver writes 24
at probe and I had said `0x98` out loud beforehand.

The IIO core calls `hwfifo_set_watermark` when a buffer is enabled and
passes the buffer's own watermark attribute, which it initialises to 1.
That call lands before `postenable` reads the field, so the probe's
value is overwritten every time. A 32 sample FIFO, and the default path
interrupts once per sample.

It had never been measured because of how it has always been measured.
Every capture of this path has gone through Project 10's `iio-rate`,
which writes `buffer/watermark` before it starts, so every published
number was taken at 24 and the path a plain program takes was invisible.

**Three windows per arm, with an accidental control.**

| Arm | `FIFO_CTL` | interrupts in 10 s |
|---|---|---|
| nothing written | `0x81` | 967, three times |
| buffer disabled | `0x00` | 0 |
| 24 written | `0x98` | 40, three times |

967 against 40 is 24.18, and the watermark is 24. The zero came from a
shell `&&` chain that stopped at a failed write and left the buffer
disabled, which is a better control than one anybody would have
thought to take.

The two arms also agree about the part: 96.7 interrupts a second at one
sample each, 4.0 a second at 24 samples each, which is 96.0 samples a
second. Both about three per cent under the 100 Hz the rate register
was set to. The agreement is the useful part, because a late handler
draining more than its watermark would distort the fast arm and not the
slow one, and it does not.

**The failed write is its own small lesson.** `echo 24 >
buffer/watermark` returned `Invalid argument`, because the core refuses
a watermark larger than `buffer/length` and the length was still 16
from the triggered capture. `iio-rate` writes the length first and
`tests/iio-rate-test.sh` asserts that order. The sequence here was
hand-rolled and walked into exactly what the tool was built to avoid,
which is an argument for using the tool rather than for adding a check.

**What changed.** The driver is not wrong; its documentation was.
`bench-adxl345.h` called 24 a default, which it has never been on any
board. The header now says what the constant is, which is the value
held if that hook is never called and the ceiling the clamp works
against, and names the measurement. No kernel interface lets a driver
set the buffer's initial watermark, so a program that wants batching
has to ask for it, and the honest thing is to say so where somebody
reading the driver will see it.

Evidence in `docs/evidence/fifo-watermark-2026-10-17.md`.

## 29. The claim that neither driver can bind to the other's node

Saturday 17 October 2026, evening. Criterion 7 wants the same hardware
under mainline's driver, and the obvious route was to skip the reboot: a
sysfs `unbind` from our driver and a `bind` to mainline's, which needs
no rebuild and is reversible in one write.

The unbind worked. The bind returned `Invalid argument`.

**That error is the finding.** A refused match makes a sysfs `bind`
return `ENODEV` and print nothing. The log read
`adxl345_i2c: probe of 1-0053 failed with error -22`, and the driver
core prints that line only after a probe has run. So mainline's driver
matched a node whose compatible it has never heard of.

The compatible had nothing to do with it. An I2C client created from a
device tree node is named after the compatible with the vendor prefix
stripped: `bench,adxl345` gives a client called `adxl345`, and
mainline's `i2c_device_id` table carries that exact string.
`i2c_device_match` tries OF, then ACPI, then the name. Ours is the
third case and it does not care who claims the compatible.

`docs/DESIGN.md` has said since before either driver existed that
"the in-tree driver cannot bind to our node, because it does not claim
that string. No load-order race exists to lose." The first sentence is
false and is struck out. The second is true, and the reason given for
it was wrong.

**Why the race does not happen anyway.** The device reports

    MODALIAS=of:Nadxl345T(null)Cbench,adxl345

which is what udev autoloads from. Mainline's module declares
`of:*Cadi,adxl345*` and `i2c:adxl345`, and neither matches that string,
so nothing ever loads it for this node; it took a manual `modprobe` to
get it onto the bus at all. The protection is the module alias, not the
compatible, and it holds exactly as long as nothing else loads that
module. Once both are registered, one client matches both drivers and
the first to register holds it.

**And why the shortcut can never work.** Mainline's probe builds a
regmap and calls `adxl345_core_probe`, which does:

    type = (uintptr_t)device_get_match_data(dev);
    switch (type) {
    case ADXL345: name = "adxl345"; break;
    case ADXL375: name = "adxl375"; break;
    default:      return -EINVAL;
    }

`device_get_match_data` consults the OF and ACPI tables and not the I2C
one. Our compatible is in neither, so it returns NULL, the type is zero,
and the switch falls through to `-EINVAL`. The `ADXL345` that its own
`i2c_device_id` table carries as driver data for the name it just
matched on is never read. The match path and the data path ask different
questions, on any board, not only on this one.

So criterion 7 needs the compatible changed, which means a rebuilt
overlay or a second one selected from `config.txt`, and the shortcut is
closed with a reason rather than left as an untried idea.

**A footnote on what mainline's 6.6 driver is.** Reading it to answer
this showed it has no FIFO, no events and no watermark hook. The
control this project has been arranging for compares raw axes, scale
and sampling frequency, and nothing else. That is still a control worth
having and it is narrower than the design implies.

**And the bench bit nobody planned.** The unbind left the part bound to
nothing, and the first attempt to put our driver back failed:

    bench-adxl345-i2c 1-0053: error -EREMOTEIO: cannot read DEVID

The same `-121` this bench last saw on Friday 9 October 2026 at 400 kHz,
except this card runs at 100 kHz. `i2cdetect -y 1` then showed `53`
answering and nothing holding it, and the next bind succeeded. The
likeliest reading is a bus left wedged by an interrupted transfer, with
the detection sweep clocking it free, and the honest statement is that
one probe failed and the next one did not. The afternoon's forced reads,
`i2cget -f` against an address a driver held, are the one new thing this
bench has been doing today and belong on the list of candidates.
