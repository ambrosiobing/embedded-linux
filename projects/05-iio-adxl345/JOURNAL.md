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
