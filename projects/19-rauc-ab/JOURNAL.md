# Journal: Project 19

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are Monday 21 September 2026 unless noted.

---

## 1. The specification first, and an ownership table that found five hazards

**What happened.** The specification is 357 lines in `sections/p19.tex`,
the same source the whole twenty-project book is built from. It was read in
full before a file existed, and the four figures it asks for were redrawn
as text before any recipe.

**What was done.** [docs/DESIGN.md](docs/DESIGN.md) carries five figures
rather than four: the boot chain, the card by partition and owner, the LED
and console wiring, the bench layout, and the slot state machine with the
update sequence. The numbers are written out, because partition sizes, GPIO
numbers, the 15 s watchdog clamp and the 120 s failsafe are what transfer
and an arrow in a diagram carries none of them.

The ownership table found five resources with two owners, against three in
Project 2:

| Resource | The two owners | Policy written down |
|---|---|---|
| `uboot.env` | U-Boot `saveenv`, Linux `fw_setenv` | `/boot` read-only in fstab, `fw_setenv` remounts |
| the device tree | shared on FAT, kernel is per slot | stated constraint: an update cannot carry a new DT |
| `/etc` | read-only lower, persistent overlay upper | overlay is for operator configuration only |
| `/data` | slot A, slot B | schema must not change between bundles |
| the boot partition | the flash, and nothing at runtime | not updatable at all, and the README must say so |

**Why that and not the alternative.** Building first and documenting after
is what Project 1 did, and the figures had to be asked for twice. It also
structurally cannot catch a drift between intent and implementation. Here
the table earned its place before any code existed: three of those five
rows are constraints that change what gets built, not observations about
something already built.

---

## 2. The journal format was nearly wrong for the second time

**What happened.** This journal was first written in the narrative style
used throughout Project 2, with `###` subsections and no bold leads. Then
`references/conventions.md` was read, which prescribes
**what happened**, **what was done**, **why that and not the alternative**,
and a check of the repository showed that **thirteen of the fourteen
existing journals use it**:

    projects/01-yocto-image/JOURNAL.md
    projects/03-boot-energy/JOURNAL.md
    ... eleven more ...

The only journal that does not is Project 2's, which is 21 entries long.

**What was done.** This file was rewritten in the house format before
anything else was built on top of it. Project 2 is left as it stands for
now, and the divergence is recorded here rather than quietly repeated.

**Why that and not the alternative.** Fixing it in the file that has one
entry costs nothing; fixing it in the file that has 21 is a separate
decision about churn on work already pushed, and it is Joseph's to make.
The thing worth noticing is the mechanism: the convention was written down,
was followed by thirteen projects, and was still missed, because the
reference was read after the writing rather than before it. The skill says
to read it first for exactly this reason, and that instruction was the one
skipped.

---

## 3. A comment in a shared file that is about to become false

**What happened.** `kas/bench-rpi3.yml` carries a comment written during
Project 1:

    Projects 5, 6 and 19 use the identical rootfs on a Raspberry Pi 3, so
    only the machine changes.

**What was done.** Nothing yet, beyond recording it. Project 19 needs
`meta-rauc`, `RPI_USE_U_BOOT`, a four-partition WIC, `read-only-rootfs` and
`overlayfs-etc`, so it gets its own `kas/bench-rpi3-ab.yml`, which is what
the conventions require of a new project anyway. The comment gets corrected
when that file is touched.

**Why that and not the alternative.** The alternative is to leave it, and
it would read as an instruction to a future reader that Project 19 needs no
kas file of its own. It is the shape the skill names directly: a claim
written when it was true, left standing after the thing it described
changed. It was a prediction about work that had not been done, and the
work turned out differently.

---

## 4. The boot script cannot be tested by running it

**What happened.** The most dangerous artefact in this project is
`boot.cmd`. A broken one takes out both slots at once, because the thing
that would roll back is the thing that broke, and it runs in U-Boot where
none of this repository's test machinery reaches.

**What was done.** Not settled, and deliberately left open in the design
document with three options named:

1. build U-Boot's `sandbox` target on the host and run the real script
   against real U-Boot semantics with a fake environment
2. test only the derived facts on the target from the console after each
   change, with the second microSD card as the recovery path
3. accept it as untested and lean on the second card

**Why that and not the alternative.** The tempting fourth option is to
reimplement the script's logic in shell and assert on that. It is the trap
decision 98 names: it would test the reimplementation rather than the
artefact, and a passing suite would say nothing about the file that
actually runs. Option 1 is the only one that tests the thing itself, and
whether it is practical is a host-only question needing no hardware and no
Yocto build, which makes it the cheapest next step.

---

## 5. The disk blocker was real and my reason for it was wrong

**What happened.** The design document called the schedule blocked on the
strength of one sentence: that a `raspberrypi3-64` build is "a new machine
and two new layers". That sentence came from the shape of the project
rather than from the repository. `references/traps.md` says a machine
change costs a near-total sstate miss, and I matched Project 19 to the trap
without checking whether this bench had already paid it.

It had. `git log -L54,54:kas/bench-rt.yml` gives three commits: `a3070f6`
moved Project 8 to `raspberrypi3-64` because that is what the HAT fits,
`cb928b0` corrected the clock and memory figures that travelled with it,
and `d7c6295` moved it back to `raspberrypi4-64`. Between the first and the
last, a full cortexa53 build ran on Wednesday 16 September 2026, at the
price the trap file quotes, 1721 of 1921 objects missed. Project 8's own
cleanup table then records `sstate-cache | 13 G | kept`.

**What was done.** The paragraph in [docs/DESIGN.md](docs/DESIGN.md) was
rewritten. The blocker survives, for a different and smaller reason: not a
machine change, but a kernel fragment, which forces a kernel rebuild, which
is what `require_host_disk_gb 25` in `scripts/build.sh` guards on. The last
recorded 18 GB is below 25, so the build refuses at the start rather than
filling the disk in the middle. Two figures settle the schedule and neither
needs a build started: the exact free space, and whether the cortexa53
objects are still in `sstate-cache`.

**Why that and not the alternative.** The alternative was to leave it,
since the conclusion did not change, only the reason. That is the failure
the skill names as worse than a wrong conclusion: a claim that explains an
absence, right for the wrong reason, surviving review because the answer
looks correct. It would also have cost real time. "Budget for a machine
change" and "budget for a kernel rebuild on a warm cache" are different
schedules, and the second may be affordable this week where the first is
not.

Two smaller things fell out of reading that history. `kas/bench-rt.yml` is
clean: `d7c6295` moved the explanatory comment back along with the machine
line, which is exactly the discipline entry 3 found missing in
`kas/bench-rpi3.yml`. The same repository holds one instance of the habit
and one instance of its absence, a week apart. And Project 8 recorded that
its disk guard passed on 38 GB against a 25 GB test while the build peaked
at 28 GB. The guard checks once, at the start, before it can know what the
build will cost, so clearing it is not the same as having enough.

---

## 6. Reading one upstream unit file changed the design

**What happened.** The plan was a health check that runs some tests and
then calls `rauc status mark-good` itself. Before writing it, meta-rauc's
own `rauc-mark-good.service` was fetched and read, because the layer ships
one and two services calling mark-good would be two owners of one
decision.

It does ship one, it is installed by default through `RRECOMMENDS`, and it
carries two lines that settle the whole question:

    After=boot-complete.target
    Requires=boot-complete.target

`boot-complete.target` is a systemd synchronisation point that is not
reached unless something pulls it in and every unit required by it has
succeeded. So the stock service is already health-gated, and the gate is a
target rather than a script.

**What was done.** `bench-health.service` is ordered `Before` that target
and declares `RequiredBy=boot-complete.target` in its `[Install]` section.
It exits zero or non-zero and calls nothing. A failure means the target is
never reached, so the stock mark-good never runs, so the counter U-Boot
decremented stays spent and the third failure moves the board to the other
slot.

**Why that and not the alternative.** The alternative was the obvious
design, and it would have shipped a second mark-good alongside one that was
already installed, already enabled, and already correct. Whichever ran
first would have won, and on a healthy board both would run and nothing
would look wrong. The project whose design document contains an ownership
table would have introduced a two-owner bug into the one decision the
whole project exists to make.

The general shape is worth more than this instance: the upstream layer had
already solved this, and the only way to find that out was to read the
file rather than the documentation about the file. It cost one fetch.

---

## 7. A unit deleted before it ever ran

**What happened.** `data.mount` was written, reviewed and installed by the
recipe before the `overlayfs-etc` class was read. That class generates a
preinit which mounts `OVERLAYFS_ETC_DEVICE` at `OVERLAYFS_ETC_MOUNT_POINT`
before `/sbin/init` starts, because `/etc` has to be an overlay before the
process that reads `/etc` exists. The device is p4 and the mount point is
`/data`, which is exactly what the new unit also claimed.

**What was done.** The unit was deleted, and the recipe now says in a
comment where p4 is mounted and why there is no unit for it. The mount
options moved to `OVERLAYFS_ETC_MOUNT_OPTIONS` in the image recipe, which
is now the single place that decides them. `boot.mount` stays, because
nothing else touches p1.

**Why that and not the alternative.** The alternative, keeping both, would
mostly have worked: systemd finds the path already mounted and the unit
goes active without doing anything. Mostly working is the problem. The
conflict would have surfaced on the boot where the ordering came out
differently, and the symptom would have been an `/etc` overlay assembled
over a mount that a unit had replaced underneath it.

This is the third hazard in this project found by asking who owns a
resource, and the first of the three that was found after writing the code
rather than before it. The ownership table in the design document listed
`/etc` and `/data` as hazards and still did not catch this one, because it
recorded which components share a resource and not which line of which
class performs the mount.

---

## 8. Two tools read my prose as code, in one afternoon

**What happened.** Two separate silent-wrong-answer failures, both from the
hazard the skill file documents, both while writing about that hazard.

The first: `grep -c $'\r'` was used to test some files for CRLF endings and
returned 316, 175 and 16. The Bash tool consumed the backslash, leaving
`grep -c ''`, which matches every line, so those were line counts presented
as evidence of a line-ending problem. There was no line-ending problem. The
second: a Python edit script in a quoted heredoc failed its own
`assert old in text` because the anchor contained a backslash continuation
that never arrived. That one was caught, by the assertion the skill file
insists on, which is the difference between the two.

The third was a different tool with the same shape. `scripts/lint.py` reads
fetch URIs with a regex, and a comment in the RAUC bbappend mentioned the
scheme with a comma after it. The linter reported a missing file whose name
was a comma. The comment was explaining that very trap.

**What was done.** The CR counts were retracted and replaced with a byte
comparison in Python; the files were LF all along. The edit was redone with
the Write tool. The comment was reworded, and now says that the regex reads
prose and that the scheme should only appear in running text with a space
after it.

**Why that and not the alternative.** The alternative for the linter was to
widen the regex so it stops treating punctuation as a filename. That rule
has caught real mistakes in this repository, including two in this session,
and the cost of leaving it strict is one sentence in one comment. The rule
stays; the prose moves.

What is worth keeping from the first failure is not the fix. It is that a
wrong answer arrived as a plausible number rather than as an error, three
times, and that the only one caught in the act was the one with an
assertion in front of it.

---

## 9. The log explaining the reboot is destroyed by the reboot

**What happened.** `IMAGE_FEATURES += "read-only-rootfs"` was written and
its consequence for logging was noticed a few lines later. poky's default
with a read-only root is `VOLATILE_LOG_DIR = "yes"`, which makes
`/var/log` a symlink into tmpfs.

In most read-only designs that is the right trade. In this one it removes
the project's own evidence. Every interesting event in an A/B system is
followed immediately by a reboot: the health check fails and the board
reboots, the watchdog fires and the board reboots, the failsafe timer gives
up and the board reboots. In all three the record of why is deleted by the
event it describes, and the acceptance table would have had to be filled in
from a serial console somebody happened to be watching.

**What was done.** `VOLATILE_LOG_DIR = "no"` in the image, a build-time
symlink from `/var/log/journal` onto the shared data partition, a
`tmpfiles.d` entry to make the directory behind it, and a journald drop-in
setting `Storage=persistent` with a 64 MiB cap.

**Why that and not the alternative.** The cap is the part that needed
deciding rather than the persistence. The data partition is 512 MiB and
also holds RAUC's status, the `/etc` overlay and downloaded bundles, so an
uncapped journal would eventually break the update mechanism in order to
preserve the logs about the update mechanism. 64 MiB is one eighth of the
partition and several hundred boots of this workload.

The alternative of a bind mount over `/var/log` was rejected for a smaller
reason: it needs ordering against `systemd-journald.service`, which starts
very early, and a symlink made at build time needs no ordering at all.

---

## 10. One variable name, two meanings, in two recipes

**What happened.** The bundle recipe needs three pieces of signing
material: a private key, its certificate, and a keyring to verify against.
meta-rauc names the last one `RAUC_KEYRING_FILE`, and so does
`rauc-conf.bb`, which this project already bbappends.

They do not mean the same thing. `bundle.bbclass` documents it as a path on
the build machine and uses it to verify the bundle it has just signed.
`rauc-conf.bb` uses it as a bare filename inside `WORKDIR`, as
`${WORKDIR}/${RAUC_KEYRING_FILE}`, and installs it to `/etc/rauc` on the
board.

**What was done.** Both are set per recipe and neither is set globally.
`rauc-conf.bbappend` keeps the bare name `ca.cert.pem` and points
`RAUC_KEYRING_URI` at the absolute path; `bench-bundle.bb` sets the same
variable name to an absolute path, because that is what its class wants. A
comment in the bundle recipe says why the two differ, since they look like
a copy-paste error side by side.

**Why that and not the alternative.** The natural thing is to set it once
in `local.conf`, because it looks like a global and the name is identical
in both places. That breaks whichever of the two was not being thought
about: an absolute path makes `rauc-conf` install a file whose name is a
path, and a bare name makes the bundle class look for a keyring in the
build directory. Neither fails at the point of the mistake.

This is the same shape as the boot script bbappend from the previous
session, and it is worth naming as a class rather than as two incidents: a
name that is shared between two consumers who each believe they define it.
The defence is the same both times, which is to set it where only one
consumer can see it.

---

## 11. Fifty-eight assertions, and the three that were wrong were mine

**What happened.** Almost nothing in Project 19 is code. It is a boot
script, a partition table, a RAUC configuration, some units and an image
recipe, and the defects available are nearly all of one kind: two files
that must agree about a number or a string, and do not. BitBake cannot see
any of them. So [tests/ab-config-test.sh](../../tests/ab-config-test.sh)
asserts the agreements directly, against the real files rather than
fixtures, because the thing that can be wrong is the real file's content.

First run: 52 passed, 3 failed, and all three failures were faults in the
test rather than in the project.

1. A `sed` range ended at a tab. The boot script is indented with spaces,
   so the range ran to the end of the file and the check read both
   partition numbers as one answer.
2. A check called "the health check does not call mark-good itself"
   counted the string anywhere in the file, and `bench-health` explains at
   length why it does not call it. It counted the explanation.
3. A check on the failsafe counted every mention of the unit in the
   recipe, including the comment explaining its absence.

**What was done.** All three were rewritten to ask the question their own
sentence claims. The ordering checks now anchor on branch conditions rather
than on indentation; the mark-good check strips comments and looks for a
command at the start of a line; the failsafe check reads the
`SYSTEMD_SERVICE` assignment rather than the whole file.

Then each was broken deliberately and watched to fail: eight faults
injected one at a time, each restored and the suite confirmed green again.
Seven were caught on the first attempt. The eighth found a fourth bad
check: deleting `kernel-image-image` from `IMAGE_INSTALL` left the suite
green, because the name also appears in the long comment beneath
explaining why the line matters. That check now reads the assignment.

**Why that and not the alternative.** Writing the suite and stopping at
green would have shipped four checks, three of which reported the opposite
of the truth and one of which could never fail. The one that could never
fail is the dangerous kind, because it is indistinguishable from a check
that passes, and it was guarding the single line in the image recipe whose
absence produces a reboot loop with a correct-looking boot log.

The fault is the same one three times over, in a suite written to catch
exactly it: a check that reads prose as if it were code. The skill file
names it, the linter in this repository has been bitten by it twice, one of
those was earlier in this same session, and it still happened four times in
one file. What caught it was not care. It was breaking the thing on purpose
and watching.

---

## 12. Rereading the specification after building, and two deviations found

**What happened.** The specification was read in full before any file
existed, which is the order the method asks for. It was read again after
the software was written, to fill in the acceptance table, and the second
reading was worth as much as the first.

Five decisions taken independently turned out to match it exactly, which is
reassuring rather than interesting: the watchdog at 14 s against a clamp
near 15, copying the firmware's command line out of the device tree before
`booti` discards it, checking the environment size against
`CONFIG_ENV_SIZE`, keeping the network out of the health check, and tying
boot confirmation to the application rather than to a systemd target.

Two things did not match, and both were mine.

The specification says to mount `/boot` read-only and let `fw_setenv`
remount. `boot.mount` mounts it `rw,sync` instead, for the reason already
recorded: RAUC calls `fw_setenv` itself from `PATH`, so a remount would
need a shadow binary over u-boot-fw-utils'. The specification also lists a
bind mount for `/var`, where this uses a symlink for `/var/log/journal`
alone.

**What was done.** Both are written into
[README.md](README.md) under a heading that says they are deviations, with
the reasoning, rather than left for a reader comparing the two documents to
find. Acceptance criterion 3 asks only that `/var/log/journal` be on the
data partition, which the symlink satisfies, so the second is a deviation
from a best-practice list rather than from a criterion. The first is a
deviation from an explicit instruction and is labelled as one.

A third thing came out of checking that the documents name things that
exist. `docs/BRINGUP.md` told the reader to run `./go flash`, and
`flash.sh` chooses the newest `.wic.bz2` by modification time. That rule
exists to stop a Pi 4 image reaching a Pi 3 and it does that well. It does
not separate two images built for the same machine, and this project
creates exactly that case: `bench-image` and `bench-ab-image` are both
`raspberrypi3-64` and land in one directory. Flashing the wrong one
produces a card that boots, reaches a login, looks entirely correct, and
has no slots at all. BRINGUP now names the image explicitly and says why.

**Why that and not the alternative.** The alternative for the deviations
was to quietly implement what was implementable and let the acceptance
table read as though everything matched. That is the failure the skill file
describes as worse than a wrong conclusion: the conclusion holds, the
stated reason is false, and it survives review because the answer looks
right.

For the flash hazard the alternative was to change `flash.sh` to
disambiguate by image name. It was not taken, because that script is shared
by nineteen other projects and this is the first configuration in the
repository that puts two images for one machine in one directory. Changing
a shared selection rule to fix a situation only one project creates is how
a script acquires behaviour nobody can explain later. Naming the file in
one document is the smaller change, and if a second project ever creates
the same situation the rule becomes worth revisiting with two examples
instead of one.

---

## 13. Three LEDs with two claimants, and the kernel as the way out

**What happened.** Criterion 4 wants the LED colour to change when the
board switches slots, and figure 3 assigns GPIO 17, 27 and 22 to green,
yellow and red. Those are the same three lines, on the same three modules,
that Project 12's `bench-status` daemon already drives on every other image
in this repository, where they mean healthy, starting and failed.

`bench-image` installs `bench-status`, and `bench-ab-image` requires
`bench-image`, so this project had inherited a daemon that would fight it
for the hardware.

**What was done.** Three `dtoverlay=gpio-led` lines, so the LEDs become
ordinary kernel LED class devices, and `bench-slot-leds`, a script that
writes `brightness` and `trigger` files. `bench-ab-image.bb` removes
`bench-status` from this image. The red light is driven from RAUC's own
`[handlers]` section: `pre-install` makes it steady, `post-install` clears
it, and because `post-install` runs only after a **successful** install, a
failure leaves the light on by doing nothing at all. That asymmetry is the
entire error handling.

**Why that and not the alternative.** Two alternatives were considered.

Teaching `bench-state` two more words was the obvious one, and it would
have left a yellow LED meaning either "a watched unit is starting" or "you
are on slot B" depending on which image was flashed. An indicator that
needs the image name to interpret is not an indicator.

Writing a second daemon was the other, and it is not actually available: the
overlays claim those lines in the device tree, so libgpiod cannot open them
and `bench-status` would fail at start on a board where nothing is wrong.
The conflict is not resolvable by agreement between two userspace programs,
which is why the image removes one of them rather than configuring both.

The kernel driving the LEDs matters for exactly one of the four states.
Red blinking means the slot is running and not yet confirmed, which is
precisely the window in which userspace may be wedged. A blink driven by a
shell loop stops blinking at the moment it becomes worth watching; the
kernel's timer trigger does not.

**Two mistakes on the way, both of the same kind.**

`RPI_EXTRA_CONFIG` was written into `bench-ab-image.bb` first. It is read
by `rpi-config_git.bb`, which is what writes `config.txt`, so an assignment
in an image recipe is scoped to that recipe and would have been read by
nobody. The result would have been a card with no LED devices, no error
anywhere, and a bring-up document telling the reader to look at
`/sys/class/leds`. It now lives in the kas file, where `local.conf` puts it
in front of the recipe that consumes it.

The second was mechanical and is the third instance this session. The
overlay line needs literal backslash-n escapes, because `rpi-config` writes
the value with `printf`. Written through a heredoc, the backslashes were
consumed and real newlines went into the YAML instead, producing an
unterminated BitBake string. Rewritten with `chr(92)`, which is what the
skill file says to do and what I had already been caught by twice today.

**And the guard that matters most is one line long.** `bench-health` runs
under `set -e` and its exit status is the rollback decision, so the call
that turns the red LED off ends in `|| true`. Without it, a board whose
overlays never reached `config.txt` would fail its health check, never be
marked good, and roll back after three boots. An unplugged indicator would
have become a software fault, and the console would have blamed the
application. `tests/ab-config-test.sh` asserts that guard is still there,
and the assertion was proved by removing it and watching the suite fail.

---

## 14. Building the two bundles that are supposed to fail

**What happened.** Criteria 5 and 7 were marked "configured" and neither
had any software behind it. Both ask for a demonstration rather than an
assertion, and each needs a bundle that nothing in the project would
otherwise produce: one carrying a broken application, one claiming to be
for a different system.

**What was done.** `kas/bench-ab-bundle-broken.yml` and
`kas/bench-ab-bundle-wrong.yml`, both including the good bundle's
configuration and each overriding exactly one thing. `./go ab-broken` and
`./go ab-wrong`.

The broken one swaps in a complete `bench-app-broken.service` rather than
editing the real unit with a `sed`, so the two builds differ by which file
is installed and by nothing else. The mismatched one overrides a new
`BENCH_AB_COMPATIBLE`, which the bundle recipe now reads, because
`RAUC_BUNDLE_COMPATIBLE` was assigned with `=` and a recipe assignment
wins over `local.conf`.

Both name their own output. Three bundles land in one deploy directory and
two of them are meant to fail; distinguishing them by timestamp is how the
wrong one gets installed in front of an audience.

**Why that and not the alternative.** Editing the unit on the board was the
obvious cheaper route and it proves nothing about the update path. The
claim under test is that a BUNDLE carrying a broken application installs
successfully, boots, fails three times and is abandoned. The fault has to
travel the whole mechanism for the demonstration to be about the
mechanism.

The compatible string is `bench-rpi4` rather than something obviously
wrong, for the same reason. A bundle claiming to be for the Pi 4 on this
same bench is the mistake a person would actually make. A string like
`xxx` would show that RAUC compares strings and nothing about the risk the
comparison exists to remove.

**The switch had to go into the task signature**, and that is the line most
easily left out. Without `do_install[vardeps] += "BENCH_AB_BREAK_APP"`,
flipping it is served the previous package from sstate: the build reports
success, the bundle carries a working application, and criterion 5 fails to
fail. A test that cannot fail is the most expensive kind in a project whose
entire subject is the failure paths.

---

## 15. The boot script now runs, in a U-Boot that is not on the board

**What happened.** The open question in the design document was how to test
`boot.cmd`, the one file that can take out both slots at once. Three
options were named; option 1 was building U-Boot's `sandbox` target and
running the real script against real U-Boot semantics, and the doubt was
whether a sandbox could deal with a FAT `uboot.env` conveniently enough to
be worth it.

That doubt was misplaced. The decision logic reads and writes ordinary
environment variables; where they are persisted is a separate concern the
sandbox does not have to reproduce.

**What was done.**
[tests/ab-bootscript-test.sh](../../tests/ab-bootscript-test.sh) makes the
same token substitution the recipe makes, stubs the two commands that need
an arm64 target and a real card, and runs the result in a sandbox binary.
Five scenarios: a fresh environment, an exhausted slot A, both slots
exhausted, a reordered `BOOT_ORDER`, and a slot on its last attempt.

The substitution is asserted rather than trusted, so a later edit cannot
widen it into a test of something else. Without a sandbox binary the test
exits zero and prints the list of questions it could not ask, because a
skip that reads as a pass is a failure this repository has shipped three
times.

**Why that and not the alternative.** The tempting fourth option was always
to reimplement the counter logic in shell and assert on that. It is
decision 98's trap: the suite would pass and would say nothing about the
file that actually runs. Stubbing two terminal actions is a much smaller
compromise than reimplementing the decision, and it is one that can be
stated precisely and then checked.

**And the checks caught me twice more, in the same family as before.**

The first: a check called "and nothing else was touched" counted `ext4load`
and `booti` anywhere in the file, so it counted the script's own comments.
Stripping comments was not enough either, because `booti` is a substring of
`rebooting` and the script says "Rebooting to try the other" on its failure
path. The pattern now asks whether either name is at the start of a line,
in the position a command occupies.

The second was worse and was found by injection. A loop checked that every
decision-making keyword "still contains" what it should, by comparing the
stubbed file against the pre-stub file. Both are derived from the source,
so deleting `saveenv` from the source removed it from both sides and the
check stayed green. It could catch damage done by the substitution and
nothing else, while its sentence claimed more. It now asks two questions
per keyword: does the script contain it at all, and did the substitution
leave it alone.

Thirty faults have now been injected into this project's files one at a
time, restored, and the suites confirmed green again. Two of the thirty
found checks that could never have failed. Both of those were mine, both
were written the same afternoon as the code they guard, and neither would
have been found by reading them.
