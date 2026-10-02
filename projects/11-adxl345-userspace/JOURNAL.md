# Journal: Project 11

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are Monday 21 September 2026 unless noted.

---

## 1. The part decided the project, and it is the part on the bench

**What happened.** The specification names an X-NUCLEO-53L8A1 with a
VL53L8CX. The project is built on a DFRobot SEN0032, an ADXL345, instead.

> **Corrected on Wednesday 30 September 2026.** As written on Monday 21
> September 2026 this entry said the ADXL345 was the only loose sensor on
> the bench and that the X-NUCLEO-53L8A1 was not here. Both statements
> were false: the shield is on the bench, and so are the X-NUCLEO-IKS4A1,
> the X-NUCLEO-IKS5A1 and the STWIN.box. The entry is left standing
> because it records what was believed at the time. The two reasons below
> were the real grounds for the choice and are untouched by the
> correction. Entry 12 re-examines the decision without the false premise.

The choice is better than a substitution, for two reasons found while
reading rather than assumed:

**The register map is public.** The ADXL345's registers are in its
datasheet, so there is no vendor blob, no licence gate and nothing to
download before building. Every line of this project compiles from the
first commit, including the tests, which is what lets CI exercise it with
nothing plugged in. A time-of-flight sensor with a closed register map
would have put its vendor library inside the test binary as well as the
real one, so even the hardware-free half would have needed a download.

**Project 5 drives the same chip from inside the kernel.** That was not
available before and it is the more interesting half: one part, two
routes, and a direct answer to the question this project opens with, which
is why a sensor needs a kernel driver at all. Neither project has to argue
by analogy.

**What was done.** The design and this journal are written for the ADXL345
throughout. The four specified figures are redrawn for it; the six
acceptance criteria are rewritten around gravity, which is a reference
that needs no instrument.

**Why that and not the alternative.** The alternative was to write the
project for a part nobody has and mark its rows deferred. That produces
something that looks finished in the table and cannot be exercised by
anyone, including its author.

---

## 3. The schematic was not drawn, on purpose, for the second time

**What happened.** Project 5 drives the same SEN0032 and its design says
"Not drawn yet, and deliberately not guessed": the DFRobot wiki gives
`I2C / SPI (3 or 4 lines)` at `3.3~6V` and publishes no pin list, so the
address, the interrupt pin and the supply are all unknown until somebody
reads the board.

**What was done.** Project 11's Figure 2 makes the same refusal and links
to Project 5's section rather than repeating the reasoning. The library
takes the I2C address as an argument instead of compiling one in, and
accepts a negative interrupt GPIO meaning "not wired, poll instead".

**Why that and not the alternative.** Copying the pin table into a second
document creates a second place for it to be wrong, and this repository has
already been bitten by a claim that was true when written and stale
afterwards. One unanswered question in one place is better than two
answers that can disagree.

The supply is the part that can do damage rather than merely fail: a board
rated to 6 V that drives an interrupt line at 5 V into a Pi GPIO destroys
the pin.

---

## 4. Two projects can drive one chip, and nothing stops them

**What happened.** Writing the ownership table turned up a hazard that is
new to this bench. Project 5 binds an in-kernel driver to the ADXL345;
Project 11 drives the same chip from user space through `i2c-dev`. Nothing
in either project prevents both from being present in one image.

**What was done.** The ownership table names it, and the two projects never
share an image. It is the first row of that table because it is the only
one that produces wrong readings rather than absent ones.

**Why that and not the alternative.** The alternative is to rely on the
kernel refusing, which it partly does: a bound driver claims the address
and `i2c-dev` then returns `EBUSY`. That is the good case. The bad case is
permitted by the kernel and gives numbers that are wrong rather than
missing, which is the failure mode this repository treats as the expensive
one.

**What this entry does not claim.** The `EBUSY` behaviour is reasoning
about how the I2C core claims addresses. Nobody has tried it. It is written
in the design as a prediction, and it is cheap to settle once Project 5 has
a module that loads.

---

## 5. The library, and a test that asserts on what was written

**What happened.** The CMake project, the platform layer, the library, the
fake bus, the test and the application were written. Two decisions in it
are worth the ink.

**The test seam is at link time, not behind a function pointer.** Two
targets, each with one implementation of `platform.h`: the library gets
`src/platform.c` and `test_api` gets `tests/fake_platform.c`. A vtable
would be swappable at run time, which nothing needs, and it would put an
indirect call in the read path and a pointer in the handle for the tests
to set up. The cost is that one binary cannot hold both, so there is no
`--fake` flag on the shipped tool. That is the right way round: a
production library that can be told to fabricate readings is a worse
thing than a second test binary.

**The tests assert on what the library wrote to the part.** A suite that
checks return codes proves the error paths and nothing about the
configuration, and a wrong `DATA_FORMAT` byte returns success every time.
So the fake records every transfer, and the assertions read like the
datasheet:

```
ok  DATA_FORMAT has FULL_RES and the 2 g bits
ok  FIFO_CTL is stream mode with a watermark of 16
ok  measurement is enabled AFTER the configuration, not before
ok  the interrupt is disabled BEFORE measurement stops
```

The last two are ordering claims, which are the ones no return code can
carry and the ones that produce intermittent faults on real hardware.

**A defect found in my own test while writing it.** One case read
`adxl_read(d, NULL, 1, 10)` after `adxl_stop` and asserted `EPARAM`,
calling it "reading after stop is refused". The library checks its
arguments before the running flag, so that assertion passes even if the
library forgot the flag entirely. It now passes a valid array, so it
tests what its name claims. This is the check that is right for the wrong
reason, caught before it shipped rather than after.

**What was done about the compiler.** The authoring laptop has neither
`gcc` nor `cmake`, so none of this has been compiled. Rather than write a
README claiming otherwise, `tests/adxl345-build-test.sh` does the
compiling, and it is a test rather than a CI step so that one file serves
both CI and `./go check`. `cmake` was added to the CI package list and to
`scripts/host-setup.sh` in the same edit, because the test's own skip
message says CI compiles it, and Project 7 shipped exactly that sentence
while it was false.

**The checks were proved by breaking what they check.** Four defects
introduced deliberately, five findings, each naming the fault:

| Defect | What fired |
|---|---|
| `ADXL_API` removed from `adxl_stop` | "declares 5 exported functions, not six" and "adxl_stop is not marked ADXL_API" |
| `C_VISIBILITY_PRESET hidden` deleted | "visibility is not hidden by default" |
| `src/platform.c` added to the test target | "the test target links src/platform.c, then the fake replaces nothing" |
| `adxl_plat_wait` renamed in the fake | "is in real=1 fake=0, the two implementations have diverged" |

Then restored, and the suite went green again. Both directions.

**What is still unproven.** Nothing here has been compiled anywhere. The
27 assertions that pass on this laptop are all about agreement between
files; the compile, the `-Werror` clean, the fake-bus run and the
six-exported-symbols count all wait for a host with a toolchain. The
suite says so out loud rather than reporting a pass.

> **Corrected Friday 2 October 2026.** "Nothing here has been compiled
> anywhere" was false by the end of the paragraph above it, which added
> `cmake` to CI so that the suite would compile it. The host with a
> toolchain was the CI runner, and it did all four of those things on the
> next push and on every push after. See entry 13.

---

## 6. Packaging twice, and three checks that were right for the wrong reason

**What happened.** The Yocto recipe, the image, the kas file, the `./go`
target, the ctypes bindings and the whole `debian/` directory were
written, over the one `CMakeLists.txt` that already existed. Three
assertions written along the way turned out to prove nothing, and all
three were found by trying to break them rather than by reading them.

**The first.** `bench-userdrv-image.bb` carried a comment saying the test
suite asserts no in-kernel adxl driver appears in it. The suite asserted
no such thing. That is the same defect as Project 7's README claiming
`./go check` compiled `drmfill`: a sentence about a check, written in the
same hour as the check, describing a check that was never added. Three
assertions were added behind the comment.

**The second.** One of those new assertions was `grep -q "libadxl345"` over
the whole image recipe. The `DESCRIPTION` line names the library, so the
check passed with the package removed from `IMAGE_INSTALL` entirely. It
now reads the `IMAGE_INSTALL` block only, and the defect version fails.

**The third.** The soname check compared nothing. It was
`grep -q "SOVERSION ${PROJECT_VERSION_MAJOR}"`, which confirms that
CMakeLists mentions the variable and passes whatever the two numbers are.
It now extracts both majors and compares them, and bumping the project to
2.0.0 while the symbols file says `.so.1` produces:

```
FAILED   soname mismatch: CMake '2', symbols '1'
```

**The editing hazard, three times in one session.** The first attempt to
break the image recipe silently did nothing, because the anchor contained
a backslash continuation and the replacement ran through a heredoc, which
ate it. The skill file says to use the editing tool for anything with a
backslash and to assert the anchor was found; both were skipped, and the
result was a defect injection that looked successful and changed nothing,
so a check appeared to fire when it had never been tested. The same
mechanism then mangled three line continuations in the test itself into
literal tabs, and a `sed` capture group into an empty substitution that
printed an empty string and still looked like a value.

Everything with a backslash was rewritten: the `sed` extraction became
`awk`, which splits instead of substituting and needs none.

**Why packaging twice and not once.** The specification's deliverable is
three Debian packages; the bench builds images with BitBake. Both are
produced over one `CMakeLists.txt`, which is what stops them drifting.
The cost is two file lists to keep in step, so the suite asserts the
`debian/` set exists and that the symbols file matches the header.

**What the Yocto side does NOT ship, deliberately.** The udev rule and the
`i2c` group are in `debian/` only. The bench images have passwordless root
from `debug-tweaks`, so a group rule there would change nothing while
looking like security. On a plain Debian it does real work, which is where
it lives.

---

## 7. The design named three things that did not exist

**What happened.** Auditing the documents against the tree, as the method
asks when work is called finished, found three artefacts named in
`docs/DESIGN.md` and in the README that were nowhere in the source:
`adxl-motion`, `adxl-motion.service` and `adxl_motion.py`. The figures
showed them, the product table listed them, and the systemd unit was
described in the ownership discussion.

This is Project 3's failure repeated: a document describing a program
that does not exist, written in the same hour as the code, by the same
hand, and wrong the moment it was written. Sixty-odd assertions passed
while the design described a service nobody had built.

**What was done.** Written, rather than deleted from the design. The
method says to fix in the direction the document points, because editing
the document to match the code is always the faster option and silently
lowers what the project set out to do.

So: `adxl-motion`, a detector with a running median baseline; its systemd
unit, hardened line by line with a comment on why each restriction is
survivable; the udev rule extended to `gpiochip` because the unit asks
for the `gpio` group and without the rule that membership grants nothing;
and the `postinst` extended to create both groups and the service user.

**And then the test taught me something about my own design.** The suite
for the detector was written expecting that three over-threshold bursts
after a reset would fire. They do not. A running baseline is a high-pass
filter, so sustained movement is absorbed: the moved readings become the
median, the difference falls to zero, and the detector goes quiet with
the sensor still moving.

That is correct for "tell me when something changed" and wrong for "tell
me while something is moving". The assertion was rewritten to state the
property deliberately, and the program's own docstring now says it, with
a pointer to the test rather than a description that could go stale:

```
ok  movement is reported once
ok  and then goes quiet as the new level becomes normal
```

**Why that and not the alternative.** The alternative was to change the
detector to a fixed reference so the test's original expectation held.
That trades a property nobody had thought about for one that needs
calibrating to the angle the board is lying at, which is the thing the
running baseline exists to avoid. The behaviour is right; the expectation
was wrong; the documentation was missing.

**One more mislabelled assertion, caught on the way.** A case named "but
the third is" asserted `None` and was only the second burst after a
reset. Its name lied in the direction of passing. Renamed and split.

**The editing hazard, a fourth time.** Writing the detector's test through
a heredoc turned `print("\n--- ...")` into `print("` followed by a
literal newline, a syntax error. Earlier in the same session the same
mechanism ate a `\1` in a sed script, three line continuations, and a
backslash in a defect injection that then silently did nothing. Every one
was in content routed through a heredoc. The rule in the skill file is to
use the editing tool for anything containing a backslash; it has now been
worth four separate repairs.

---

## 8. Three packaging defects, each of which installs and then does not work

**What happened.** Auditing the Yocto recipe against what CMake installs
found three faults at once, and none of them would have failed a lint, a
test or a review. Each produces a package that builds, installs, and then
does not work.

**`EXTRA_OECMAKE` was assigned twice.** A `+=` carrying the python
directory, then a `=` carrying the build type. In BitBake the later plain
assignment discards the earlier append, so the override was silently
gone and the bindings would have installed to Debian's `dist-packages`
inside a Yocto image: present on disk, never importable. This is the same
shape as the two `PACKAGECONFIG:remove` lines the bench notes already
warn about, met in a different variable.

**`FILES:${PN}-tools` listed only `adxl-map`.** CMake installs
`adxl-motion` and the bindings as well, and a file installed by the build
and claimed by no package is an unpackaged file, which Yocto treats as an
error. Nothing else pulled an interpreter in either, so the image would
have carried a Python program whose first line fails.

**The systemd unit was named `adxl-motion.service`.** With three binary
packages debhelper only finds `<package>.<unit>.service`, so it was
ignored: the package would have built, installed, and shipped no service
at all. Renamed to `adxl345-tools.adxl-motion.service`.

**What was done.** All three fixed, and eight assertions added so none
can come back. The assertions were then proved by reintroducing every
defect and watching each fire.

**And the proof caught a flaw in the proof.** Two of the new checks used
`grep` over the whole recipe, and the recipe's own comments name
`adxl-motion` and the bindings, so both passed with the package list
emptied. That is the second time in this suite that a check has been
right for the wrong reason, and the second time it was found by trying to
break it rather than by reading it. Both now read only the `FILES` block.

**Also corrected in the same pass.** The design's figures named
`adxl345.py`; the bindings are a package, `python/adxl345/__init__.py`.
The figures now name what exists.

**Why the audit is worth its time.** Every one of these five faults was
invisible to `lint`, to both test suites and to a careful read of the
file in isolation. All five came from comparing a document or a recipe
against the tree rather than against itself.

---

## 9. The bring-up notes, and a design decision that was never written down

**What happened.** Two gaps were left after the packaging audit, and the
second one was found by the fix for the first.

**The bring-up notes did not exist.** Every hardware project here has
`docs/BRINGUP.md`, and this one deferred three unanswered questions to
"when the board has been read" without saying who reads it or in what
order. One of those questions can destroy a GPIO: a breakout rated to 6 V
that drives `INT1` at 5 V into a Pi pin.

So the notes are written before the board is touched, which is the only
time they are worth writing, and their order is a safety ordering rather
than a convenience one. The supply comes first and alone; the interrupt,
the only step that puts a breakout signal into a Pi pin, comes last.

They also carry the ownership check that is specific to this project.
Reading `/sys/bus/i2c/devices/1-0053/driver` says whether Project 5's
kernel driver has claimed the address, which is the difference between
`adxl-map` reading a free device and reading one somebody else is also
driving. The second produces numbers that look right.

**Then the design and the code were cross-checked**, the way Project 7's
overlay suite checks every GPIO against its wiring table. Six assertions:
both strap addresses in the design and enforced in the argument check,
all six exported functions named in the design, the supply named in the
bring-up notes, and the fixed-scale claim.

The last one failed immediately. `adxl_start` always sets `FULL_RES`, so
the scale stays 3.9 mg per count at every range and only the clipping
point moves. **The design never said so.** The header said it, the README
said it, and the document that is supposed to be the design of record did
not.

That matters beyond tidiness: it is the reason `adxl_read` returns raw
counts rather than milli-g, and the reason a stored sample needs no range
tag to be interpretable later. A reader of the design alone would have
seen a range argument and reasonably assumed the scale moved with it.

**What was done.** Written into the design rather than the check weakened,
then proved by removing `FULL_RES` from the code and watching the
assertion fire.

**Why that and not the alternative.** The alternative is to delete the
assertion, on the grounds that a design document cannot be expected to
repeat every register bit. But this is not a register bit; it is the
decision that fixes the meaning of every number the library returns. The
check found a hole in the design, which is what a cross-check between a
document and code is for.

---

## 10. The suite could not see a wrong register number, and now it can

**What happened.** Looking for what was left, the honest answer kept being
"nothing has been compiled". Hunting for a compiler on the authoring
laptop found only a runtime DLL, and that search turned up something
worse than the missing compiler.

**The fake platform layer uses the same register numbers as the library.**
So the whole fake-bus suite passes whether those numbers are right or
not. Change `REG_POWER_CTL` from `0x2d` to `0x2c` and the library writes
to `0x2c`, the fake stores at `0x2c`, the assertion reads back `0x2c` and
agrees with itself. The part would never leave standby. Fifty-six
assertions would stay green.

Internal consistency is not correctness, and every test written for this
project so far was testing the first.

**What was done.** `tests/adxl345_datasheet.py`, the register map
transcribed from the datasheet rather than from the code, and
`tests/adxl345-registers-test.sh`, which parses the constants out of
`src/adxl.c` and compares the two. Thirty-five assertions: every register
address, every fixed value, all nine rate codes, all four range codes,
both strap addresses and the FIFO depth the header promises.

The rate ladder is the part most worth having. The codes are not a
function of the frequency, so each of the nine is its own chance to
transcribe wrongly, and a wrong one gives a sample interval that is
silently off by a factor with nothing anywhere to say so.

**Proved by breaking it, and the proof is the argument for the whole
file:**

```
POWER_CTL corrupted to 0x2c
  registers suite:  FAILED  code says 0x2c, datasheet says 0x2d
  fake-bus suite:   56 passed, 0 failed
```

**The check found a real question on its first run.** It reported that
`INT_SOURCE` (0x30) is in the map and not named in the code. That is not
a typo, and the first instinct, adding the register to make the check
pass, would have been the wrong repair.

The watermark bit clears when the FIFO is read back below the threshold,
which `adxl_read` already does. INT_SOURCE only matters for the OVERRUN
latch, which is cleared by reading it and by nothing else. If the caller
falls far enough behind, that latch stays set, the line can sit asserted,
no further rising edge arrives, and the interrupt is useless until
something clears it. Survivable only because a timeout is not an error
here: the code reads FIFO_STATUS anyway and samples keep coming.

So the model now separates the registers the library MUST name from the
full map, the unused one is printed as a note rather than a failure, and
`src/adxl.c` carries the reasoning and the condition under which it
should change. Comparing against the full map instead would have made
"the library does not use this register" look like a defect, which is how
a linter teaches people to add code they do not need.

**Why that and not the alternative.** The alternative was to skip this
suite because the library is uncompiled anyway. But a wrong constant is
exactly the class of fault a compiler cannot see either: it compiles, it
links, it runs, and only the part disagrees. This is the one check that
could have been written at any point in the last three rounds and was
not, because every earlier suite was written from the same source it was
checking.

---

## 11. The project never answered its own question

**What happened.** The design opens by saying that Project 5 drives the
same chip from inside the kernel, so the pair answers the question this
project starts with: why does a sensor need a kernel driver at all.

Nothing in the project answered it. The pairing was cited as motivation
in three places and the comparison was never written, which makes it a
claim about a document that does not exist, one step removed from the
three artefacts entry 7 found.

**What was done.** `docs/kernel-or-userspace.md`, written from what the
two projects actually contain rather than from general principles, on
four criteria: whether anything else needs the data, where timestamps are
taken, who arbitrates access, and what it costs to ship a change.

**The conclusion does not flatter this project, which is why it is worth
having.** For the ADXL345 the kernel driver is the right one. The part
has a public register map, an in-tree driver already exists, it produces
a timestamped stream and other tools would want it; all four criteria
point at Project 5.

That makes Project 11 the answer to a different question, and the
specification said so all along: the accelerometer is the excuse and the
subject is what shipping a userspace driver properly involves. Writing
the comparison honestly turns that from a line in a specification into a
conclusion somebody reached.

**The sharpest technical row is the timestamps**, and it is the one this
bench could settle and has not. Project 5 timestamps in the interrupt
handler. This library cannot: by the time `adxl_read` returns, the
samples have crossed a scheduler, an ioctl and a process that may have
been preempted between any two of them. A burst of 16 samples at 100 Hz
covers 160 ms, and knowing which 160 ms is the difference between data
you can integrate and data you can only look at. What the jitter actually
is here is a number Project 8's instruments could take.

**Also corrected in the same pass.** The README's own tables had gone
stale: "43 assertions" when there are 113, one suite listed when there
are three, and no mention of the register comparison or the documents. A
table that counts things is a claim that ages every time the thing it
counts changes, which is the third time this project has had to fix one.

---

## 12. The premise was wrong and the decision survives it

Entry on Wednesday 30 September 2026.

**What happened.** Joseph said plainly that the X-NUCLEO-53L8A1 is on the
bench, along with the X-NUCLEO-IKS4A1, the X-NUCLEO-IKS5A1 and the
STWIN.box. Entry 1 of this journal, decision 108 in the walkthrough, and
the first journal entries of Projects 16 and 18 all rest on the opposite
belief. It came from an inventory note that was wrong, and it went
unchallenged for nine days because it was never checked against the
drawer, only against itself.

**What this does not change.** Nothing in the library. Not one line of
`libadxl`, not a test, not a packaging rule. The re-target to the ADXL345
had three stated grounds and only one of them is now false.

| Ground | Status |
|---|---|
| The X-NUCLEO-53L8A1 is not on the bench | **False.** It is here |
| The VL53L8CX register map is closed, so the driver needs ST's licence-gated STSW-IMG040, and the specified CMake links that library into the test binary as well as the real one | **Holds.** Nothing about owning the shield opens the register map |
| Project 5 drives the same chip from inside the kernel, so one part answers this project's opening question on hardware rather than by analogy | **Holds.** It is a property of the pairing, not of the parts drawer |

**Why the second ground is the one that decides it.** This project's
distinguishing property is that every line compiles and every test runs
with nothing plugged in, which is what lets continuous integration
exercise it. A licence-gated vendor library inside the test binary takes
that away. Owning the shield does not restore it, because the gate is on
the download and its terms, not on the hardware. So the decision stands
on ground two alone, and ground three makes it the better project rather
than merely the possible one.

**What does change.** Three things, none of them in this directory.

1. The shield is available, so the VL53L8CX port is a real option again
   for a project that wants it. It is not this one.
2. Projects 10 and 17 were described as specified around absent hardware.
   They are not. Their own READMEs never claimed it, so only the journals
   and the decisions log needed the correction.
3. The habit that Projects 16 and 18 recorded, checking the inventory
   before the design, was the right habit applied to a wrong inventory.
   The lesson survives with one addition: an inventory note is a claim
   like any other, and the drawer outranks it.

**What was done.** Entry 1 keeps its text with a dated correction beside
the false sentence. The README's "Where this differs from the original
plan" section drops the parts reason and keeps the two that hold.
Decision 108 and the two journals are corrected the same way, in place,
without rewriting what was decided or why.

---

## 13. The project had been compiling for eleven days and said it never had

**Friday 2 October 2026.** Picked this up as the next project after 10,
read the README to find where to start, and the first line of the state
paragraph was wrong.

**What happened.** The README said "Nothing here has been compiled, on
any machine." CI run 36934729926, on `488438d`, pushed the night before:

```
--- compile and run
ok       cmake configures
ok       everything builds with -Werror
ok       the fake-bus suite passes (48 checked)
ok       the built library exports exactly six symbols

60 passed, 0 failed, 0 skipped
```

That is acceptance criterion 4 met on a host, a `-Werror` clean build and
a 48-check test run, printed on every push since Monday 21 September
2026. 103 commits.

**The part worth keeping is where the false sentence came from**, because
it was not carelessness and it was not drift. Entry 10's own text, five
paragraphs above, says `cmake` was added to the CI package list
deliberately, and gives the right reason: the skip message claims CI
compiles it, and a skip message that lies is what Project 7 shipped. That
reasoning is correct and the edit was correct.

Then the next paragraph of the same entry says "Nothing here has been
compiled anywhere."

Both were written in the same sitting by the same hand. The first is
about CI. The second is about the authoring laptop. Neither sentence is
confused on its own; what is wrong is that the second was filed under the
project's state, and **the state of a project is not the state of the
machine you happen to be typing on.** The `5167220` commit title says it
in three words: "three projects written, none yet built", added in the
same commit as the thing that builds one of them.

No test can catch this. The suite was green and correct throughout; it
was the only thing in the project telling the truth, and it was telling
it to a log nobody read.

**What was done.**

1. The state line, the criteria table and the assertion count corrected
   against the CI run, which is named so the claim can be checked.
2. The top-level README row corrected. Second day running that this table
   was the stale one: the project 10 row was fixed on Thursday 1 October
   2026 for the same reason, that every document inside a project
   directory was current and the table nobody opens was not.
3. The count was wrong too, in a smaller way: 113 assertions across three
   suites, crediting the build suite with 56. It is 60, 35 and 22, which
   is 117. The four that made the difference are the compile-and-run
   assertions, so the number went stale in the same edit that made the
   sentence false.
4. Entries 1 and 10 keep their text, with a dated correction beside the
   two sentences that are wrong, the way entry 1 was already corrected on
   Wednesday 30 September 2026 and entry 12 re-examined.

**And then the actual work, which the false sentence had been hiding.**
Two acceptance criteria need no hardware at all and nothing anywhere ran
them.

Criterion 3 asks for `ctest` in the sanitizer build. `ADXL_SANITIZE`
existed as a CMake option and nothing had ever switched it on: the build
in CI is `RelWithDebInfo`. Eleven days of green runs say nothing whatever
about ASan. The suite now configures a second build tree with the
sanitizers on and runs `ctest` in it. A second tree rather than a
reconfigure, because ASan changes the layout of everything it touches and
a directory already holding an unsanitized `libadxl345.so.1` would link a
mixture of the two.

Criterion 5 is about the packaging, and every assertion the project had
about `debian/` compared one file against another. The suite now runs
`dpkg-buildpackage`, checks the three binary packages exist and that each
carries what its `.install` promises, and runs `lintian` for errors.
`debhelper`, `dpkg-dev`, `fakeroot` and `lintian` were added to the CI
package list in the same edit, which is the rule entry 10 got right and
is worth getting right twice.

**What that check does not ask, said here because the suite says it too.**
It passes `-d`, which skips dpkg's build-dependency verification, because
`Build-Depends` asks for `libgpiod-dev (>= 2.0)` and both hosts that run
this build libgpiod v2 from source under `/usr/local` rather than
installing it as a package. So a wrong build-dependency would pass. And
nothing is installed or purged, which is the rest of criterion 5 and
wants a board or a container.

Lintian warnings are printed and not scored. A suite that failed on style
notes for a package that is not going to a Debian archive is a suite
people switch off, and a guard that trains you to bypass it has done more
damage than the failure it prevents.

**Neither new check has run anywhere yet**, so the assertion count in the
README is left at the measured 117 rather than raised to the 124 these
should produce. A number that has not been printed by a run is a
prediction, and this entry is about what happens when a prediction is
filed as a state.

---

## 14. The packaging check failed on its first run, and so did the check watching it

**Friday 2 October 2026, the same day, one push later.** CI run
36976709299 on `af91824`, the first run of the two checks entry 13 added.

**What the sanitizer check did.** Passed, first time.

```
--- the sanitizer build, acceptance criterion 3
ok       the library and its test compile under ASan and UBSan
ok       ctest passes under the sanitizers with no sensor
```

Criterion 3's hardware-free half is met on a host, after eleven days of
green runs that could not have told anyone anything about ASan because
nothing had ever switched it on.

**What the packaging check did.** Failed, with a precise error:

```
dpkg-shlibdeps: error: no dependency information found for
/usr/local/lib/libgpiod.so.3 (used by
debian/libadxl345-1/usr/lib/x86_64-linux-gnu/libadxl345.so.1.0.0)
```

**This is not a surprise mechanism. It is a known fact applied to one of
the two places it applies to.** Entry 13 and the suite's own comment both
say that libgpiod v2 is built from a pinned tag into `/usr/local` because
Ubuntu packages v1, and that a library under `/usr/local` belongs to no
package. That fact was then used to justify `dpkg-buildpackage -d`, which
addresses dpkg asking about packages **before** the build, when it
verifies `Build-Depends`. dpkg asks a second time **after** the build,
when `dh_shlibdeps` resolves what the built library actually links
against in order to fill `${shlibs:Depends}`. `-d` does nothing for that
one, and it is a hard error rather than a warning.

Having written the right sentence and used half of it is a worse failure
than not knowing, because the knowledge was in the file.

**The repair, and where it is allowed to live.** `--ignore-missing-info`
is appended to `debian/rules` **in the test's own copy of the tree**,
never to the committed file. On any host where this package would really
be built, Debian trixie or the Yocto target, libgpiod v2 comes from a
package and the committed `debian/rules` is correct as it stands. Putting
`--ignore-missing-info` in it permanently would discard a genuine missing
runtime dependency forever, on every host, to accommodate one
unrepresentative runner. The weakening is scoped to the host that needs
it and announced in the file that does it.

**AND THE CHECK WATCHING THE CHECK REPORTED A PASS.**

```
FAILED   the package build failed
FAILED   libadxl345-1 was not produced
FAILED   libadxl345-dev was not produced
FAILED   adxl345-tools was not produced
ok       lintian reports no errors
```

No packages were built, so there was no `.changes` file. `lintian`
failed, `|| true` swallowed it, and `grep -q "^E:"` found no errors in an
empty log. A clean bill of health on a build that produced nothing at
all. Had the three content assertions not been there, that `ok` would
have been the only thing the packaging section said.

This repository has now shipped this shape four times: a check defined
and never added to the linter's list, a regex that matched its own file's
comments and silenced itself, a test whose failure branch was "some other
error occurred", and this. The shape is identical every time. **The thing
being inspected is chosen by a glob, a `find`, a `pgrep` or a wildcard,
and whether anything was chosen is never asked.** The suite now looks for
the `.changes` file, and refuses by name when there is none.

Which makes the right reading of this run: the packaging check found a
real defect in the packaging on its first run, and the first run also
found a real defect in the packaging check. Both are what a first run is
for, and neither would have been visible from reading the files.

---

## 15. The first successful package build found four real defects, and the checks for them found two of their own

**Friday 2 October 2026, run 36981388527 on `9f721af`.** The packaging
built. `dpkg-buildpackage` drove debhelper and CMake to three binary
packages and each carried what its `.install` file promises. Then lintian
read them.

```
E: adxl345-tools: missing-dependency-on-libc needed by usr/bin/adxl-map
E: adxl345-tools: python-package-missing-depends-on-python
E: adxl345-tools: python3-script-but-no-python3-dep [usr/bin/adxl-motion]
E: adxl345-tools: maintainer-script-lacks-home-in-adduser [postinst:19]
E: adxl345 changes: bad-distribution-in-changes-file unstable
```

**Four of those five are real and would fail on any host.** The
`adxl345-tools` stanza read

```
Depends: libadxl345-1 (>= ${source:Version}), ${misc:Depends}
```

while shipping a compiled ELF, a python3 module under
`usr/lib/python3/dist-packages/adxl345`, and a python3 script. No
`${shlibs:Depends}`, so the package that installs `adxl-map` declared no
dependency on libc. No python3 dependency of any kind, so a machine
without an interpreter would install it and both python programs would
fail at exec. And `adduser --system --no-create-home` with no `--home`
assigns `/home/adxl345` and never creates it.

Every one of those is the kind of fault that a file-against-file
assertion cannot see, because no file disagrees with any other file. It
took building the thing.

**The asymmetry that let the python one survive.** This suite has
asserted "the tools package depends on an interpreter" since the Yocto
recipe was written. It asked one packaging system a question and never
asked the other. Four new assertions now ask `debian/control` the same
questions, so the next time this is wrong it is the suite that says so
and not a tool that only exists on two hosts.

**AND TWO OF THOSE FOUR NEW ASSERTIONS DID NOT FIRE WHEN BROKEN.**

The repository's rule is to prove a check by reintroducing the defect.
Doing that: deleting `dh-sequence-python3` from `Build-Depends` left the
check green, and deleting `--home /nonexistent` from the postinst left
its check green. Both greps were matching **the explanatory comments
this same edit had just added**. The comment in `debian/control` contains
the string `dh-sequence-python3`; the comment in the postinst contains
`home /nonexistent`. Remove the directive, keep the comment, and the
grep is satisfied by the prose describing the thing that is no longer
there.

That is item two on this repository's own list of checks that pass for
the wrong reason, a regex matching its own file's comments, reintroduced
by the very commit that cites the list. Writing a good comment made the
check worse, which is not an obvious failure mode and is now a reason to
strip comments before grepping anything, every time.

Both now strip comment lines first, and all four fire with the fault
named:

```
shlibs         FAILED   the Debian tools package does not substitute shlibs:Depends
python3sub     FAILED   the Debian tools package does not substitute python3:Depends
dh-sequence    FAILED   nothing runs dh_python3, so ${python3:Depends} is empty
adduser home   FAILED   --no-create-home without --home assigns an absent home
```

**And the control experiment was left in place, again.** The first run of
that break-and-watch used a backup path that was never written, because
the fallback `cp` sat behind a `||` after a first `cp` that had
succeeded. Four breakages accumulated into `debian/control` instead of
each being undone, and the suite's own summary is what showed it. The
repository already has this rule, from Project 10 four days ago: a
control is finished when the system is put back, not when it produces its
number. The second attempt verified each backup was non-empty before
breaking anything and checked the restore after every case.

**The fifth lintian error is not settled and is suppressed as such.**
`bad-distribution-in-changes-file unstable` has two explanations that fit
the one observation: the runner is Ubuntu and its lintian may not list
Debian's suite names, in which case a Debian-targeted package trips this
on any Ubuntu host while being correct; or `unstable` is simply wrong
here. Nothing available separates them, so the tag is suppressed by name,
the suppression is printed on every run so it cannot become a quiet
drawer for unwanted findings, and the host's `dpkg-vendor --query Vendor`
is printed beside it. If a future run shows the vendor is Debian and the
tag still fires, the first explanation is dead and the changelog is what
to change.

---

## 16. The build dependency was right, the host did not have it, and -d had switched off the thing that says so

**Friday 2 October 2026, run 36982754403 on `9f8180e`.** The packaging
build failed before it compiled anything:

```
dh: error: unable to load addon python3: Can't locate
Debian/Debhelper/Sequence/python3.pm in @INC
```

`dh-sequence-python3` is a virtual package provided by `dh-python`, and
`dh-python` was not on the runner. Entry 15 added the build dependency
and did not add the package that satisfies it, so the whole thing stopped
at `debian/rules clean`.

**The interesting part is not the missing package. It is how the message
arrived.** `dpkg-buildpackage -d` skips the build-dependency check.
Without `-d`, dpkg would have said, in these words:

```
Unmet build dependencies: dh-sequence-python3
```

With `-d`, the first sign was a perl module that could not be found,
which says nothing about packaging to anyone who has not met it before.

And note which way round this is. The `-d` comment in the suite warns
that **a wrong `Build-Depends` would pass here**. What actually happened
is the mirror of that: the `Build-Depends` was correct, the host was
missing it, and the check that would have named the gap had been turned
off wholesale to excuse one entry that genuinely cannot be satisfied.
Switching off a check to accommodate its one false positive loses every
true positive with it, which is obvious written down and was not obvious
while writing it.

**What was done.** `dh-python` added to the CI package list and to
`scripts/host-setup.sh`. Then the part that matters: the suite now runs
`dpkg-checkbuilddeps` itself before building, excuses `libgpiod-dev` by
name because that one is unsatisfiable on both hosts for a reason already
written down, and refuses by name if anything else is missing.

So `-d` still skips dpkg's own gate, and the gap it leaves is now a
single named exception rather than a blanket. A guard that refuses names
what it wanted, which is this repository's rule after three guards
refused without saying.

The branch logic was checked on this laptop against the three real
message shapes rather than reasoned about, because `dpkg-checkbuilddeps`
does not exist here and the suite skips that assertion:

```
in : Unmet build dependencies: dh-sequence-python3 libgpiod-dev (>= 2.0)
out: [dh-sequence-python3 ]    refuses, naming it
in : Unmet build dependencies: libgpiod-dev (>= 2.0)
out: []                        passes
in : Unmet build dependencies: libgpiod-dev
out: []                        passes
```

**And one thing worked exactly as intended.** Entry 14 added a guard
because the lintian assertion had reported a pass on a build that
produced no package. This run produced no package, and the guard said so:

```
FAILED   there is no .changes file, so lintian inspected nothing
```

The same situation, one run apart, read as a clean bill of health the
first time and as a refusal naming the reason the second. That is the
whole value of fixing a check that passes for the wrong reason, and it
took one run to demonstrate it.

---

## 17. Shellcheck caught the same fault, in the code written to fix it

**Friday 2 October 2026, run 36983258562 on `ed320b0`.** No test failed.
The run died in the shellcheck step, on a line from entry 16:

```
In tests/adxl345-build-test.sh line 627:
    unmet=$(cd "$WORK/deb/adxl345-1.0.0" &&
    ^-- SC2015 (info): Note that A && B || C is not if-then-else.
```

**It is not a style note.** If that `cd` had failed, `|| true` would have
made `unmet` empty, the "Unmet build dependencies:" line would have been
absent, and the check would have reported **every dependency present**
about a directory it had never entered.

That is the identical shape as the lintian assertion in entry 14, which
reported a clean bill of health on a build that produced no package. The
check chooses what it inspects, the choice silently fails, and the empty
result reads as good news. Entry 14 named that shape and called it the
fourth instance. This is the fifth, written roughly an hour after naming
the fourth, in the code added to fix the fourth.

Knowing the name of a failure mode does not stop you writing it. What
stops it is a tool that reads the code, which is what shellcheck did.

**What was done.** The command substitution now fails loudly rather than
quietly: `cd` on its own with an explicit failure marker, and the marker
checked before the dependency list is read, so the two outcomes report
once each rather than a refusal followed by a false pass. All four
branches were exercised by hand, because `dpkg-checkbuilddeps` does not
exist on this laptop:

```
ENTERFAIL                                   FAILED could not enter the tree
Unmet: dh-sequence-python3 libgpiod-dev     FAILED missing: dh-sequence-python3
Unmet: libgpiod-dev (>= 2.0)                ok
(nothing unmet)                             ok
```

**And `scripts/lint.py` could not have caught it, which is now written in
its own output.** Its SC2015 rule is one regular expression against one
line. The `&&` was on one line and the `||` on the next, so nothing
matched, and the run reported "lint: clean" on a file CI then rejected.

The rule this repository follows is to grow a narrow rule when a blind
spot ships twice and to prove the rule fires. That is the wrong move
here: catching a construct split across lines means parsing shell, which
this tool is not and should not become. Writing a rule that looks like it
covers the case and does not would be a fifth check that passes for the
wrong reason, which is a strange way to respond to the fifth check that
passed for the wrong reason.

So the limitation is stated instead. `lint.py` now says, on every host
without shellcheck, that each of its eight approximations is single-line
and that a construct spanning lines is invisible to all of them. A clean
result that does not say which questions were never asked is the failure
this repository keeps finding in its own tools, and the file's own
comments already said so about a different gap.

---

## 18. The suite ran on a host Joseph can see, and the loop stopped costing a push each

**Friday 2 October 2026.** Five consecutive red CI runs, five notification
emails, and every one of those failures was reproducible on the WSL build
laptop JPTOUPM678, which has shellcheck, a compiler and now debhelper,
dh-python and lintian. The authoring laptop has none of it, which is why
nothing was caught before pushing. **CI was being used as the first test,
and CI is a slow first test that emails somebody.**

Running `scripts/host-setup.sh` there and then the suite gave, on the
first attempt, 72 passed and 1 failed. Three results worth keeping.

**The four packaging defects of entry 15 are fixed.** `${shlibs:Depends}`,
`${python3:Depends}`, `dh-sequence-python3` and `--home /nonexistent` all
hold up against a real `dpkg-buildpackage` and a real `lintian`.

**A fifth defect, which only a built package shows.**

```
E: adxl345-tools: aliased-location [lib/udev/rules.d/60-adxl345.rules]
```

`debian/adxl345-tools.install` shipped the udev rule to `lib/udev/rules.d`.
On every current Debian and Ubuntu `/lib` is a symlink to `/usr/lib`, so
the package was writing through a symlink into a directory another package
owns. It installs. It works. The rule loads. It is still wrong, and no
file in this repository disagreed with any other file about it.

Fixed to `usr/lib/udev/rules.d`, and the suite now checks **every**
destination in **every** `.install` file for a top-level `lib`, `bin`,
`sbin` or `lib64`, rather than the one line that was wrong. The next
`.install` line anybody adds will be copied from the shape of the existing
ones, so the check has to cover the shape. Proved by restoring the old
path and watching it fire, then restoring:

```
FAILED   adxl345-tools.install ships into an aliased location: lib/udev/rules.d
```

**And a claim of mine that the host falsified.** The suite's comment said
"both hosts that run this have libgpiod v2 built from source under
/usr/local". True of the CI runner, which is Ubuntu noble and packages v1.
False of JPTOUPM678, which is Ubuntu resolute and packages libgpiod-dev
2.2.1. So `--ignore-missing-info` was being applied unconditionally,
weakening a host that needed no weakening and ready to hide any genuinely
unpackaged library the code picked up later.

It is conditional now: dpkg is asked who owns the libgpiod that
`pkg-config` points at, and the host is told which way it went.

```
note     libgpiod belongs to a package here, so dh_shlibdeps runs strict
note     libgpiod is unpackaged here, so dh_shlibdeps gets --ignore-missing-info
```

That is the second time today a sentence about "both hosts" was written
from one host. Entry 13 was the same error about compilation.

**What the run did not settle.** `dpkg-vendor --query Vendor` printed
`Ubuntu`, which was the expected answer and therefore separates nothing:
the vendor explanation for `bad-distribution-in-changes-file` survives and
so does the alternative. A Debian host would decide it. Recording that the
measurement was taken and came back uninformative, rather than quietly
dropping the question.

---

## 19. Green on a real host, with nothing waived to get there

**Friday 2 October 2026, on the WSL build laptop JPTOUPM678.**

```
76 passed, 0 failed, 0 skipped
```

Every branch of the suite executed. No tool was missing, so no assertion
skipped, which has not been true of this project on any machine before
today.

**The line worth reading twice is not the total.**

```
note     libgpiod belongs to a package here, so dh_shlibdeps runs strict
ok       lintian reports no errors
```

That host packages `libgpiod-dev` 2.2.1, so the conditional added in
entry 18 took the strict branch: `dh_shlibdeps` resolved every shared
library the built package links against, against real packages, with
nothing excused. The `lintian` clean is therefore a clean on a fully
resolved package rather than on one whose hardest question was waived.

Had the override stayed unconditional, this result would have looked
identical and meant less, and nobody would have known the difference.
That is the argument for scoping a concession to the host that needs it
rather than applying it everywhere it does no visible harm.

**Where criterion 5's build half ends up: met on a host.** What remains
is installing and purging, which wants a board or a container.

**What it cost to get there, as a list, because the list is the finding.**
Five defects, none of which any file-against-file assertion could see,
because in every case no file disagreed with any other file:

| | Found by |
|---|---|
| `dh_shlibdeps` could not resolve a `/usr/local` library | the first package build |
| the tools package shipped a compiled ELF with no `${shlibs:Depends}` | lintian |
| it shipped two python3 programs and depended on no interpreter | lintian |
| `adduser --no-create-home` with no `--home` | lintian |
| the udev rule went to `lib/udev/rules.d`, through the merged `/usr` symlink | lintian |

Against that, three defects in the checks themselves: a lintian
assertion passing on a build that produced nothing, two greps matching
their own comments, and an `A && B || C` that would have reported success
about a directory it never entered. Five real and three self-inflicted,
and the self-inflicted ones were all found by breaking the check on
purpose or by a tool that parses, never by reading.

**And the loop changed.** Five consecutive red CI runs preceded this,
each costing a push and an email. One run on a host with the tools gave
72 passed and 1 failed and found the fifth defect, and the next gave 76
and 0. The authoring laptop cannot run any of this; the build laptop can
run all of it. CI is now the confirmation rather than the first test.

**Still open, and recorded rather than quietly dropped.** `lintian`
reports four warnings that this suite prints and does not score, and
nobody has read them. The decision not to score them was made for a good
reason, that a suite refusing on archive-policy style notes gets switched
off, but "not scored" was never meant to mean "not looked at once".

---

## 20. Printing the warnings found a sixth defect within a minute of printing them

**Friday 2 October 2026.** The suite had been reporting "4 warnings, not
scored" and showing none of them. Changed to list them, run once, and the
first two lines were this:

```
W: adxl345-tools: maintainer-script-needs-depends-on-adduser adduser (does not satisfy adduser) [postinst:26]
W: adxl345-tools: maintainer-script-needs-depends-on-adduser adduser (does not satisfy adduser) [postinst:39]
```

**Not a style note.** The postinst calls `addgroup` at line 12 and
`adduser` at lines 25 and 30, both from the `adduser` package, and it
runs under `set -e`. `adduser` stopped being essential in Debian trixie.
On a minimal system without it the postinst dies, the package fails to
configure, and the service account the systemd unit runs as is never
created.

That is **criterion 5's own first clause**, "the packages install
cleanly", and it had been sitting in a counted-but-unread line.

**The order of events is the whole entry.** The decision not to score
lintian's warnings was made for a sound reason and is still right: a
suite that refuses on archive-policy style notes gets switched off. But
"not scored" quietly became "not printed", and in that state the
distinction between a style note and a package that will not install
could not be drawn by anyone, because nobody could see either. One day
in that state, and the thing hiding there was a real install failure.

Not scoring a finding decides whether it fails the suite. It was never
meant to decide whether anyone can read it.

**What was done.** `adduser` added to `Depends`. An assertion added that
reads the maintainer script for `adduser` or `addgroup` calls and
requires the dependency when it finds one, so a script that grows a new
command is covered by the same check rather than by a hard-coded name.
Proved by removing the dependency and watching it fire, then restored.

**And the other two warnings were triaged rather than fixed**, which is
the point of being able to read them. `no-manual-page` for `adxl-map` and
`adxl-motion` is fair, and no acceptance criterion asks for a man page,
while the `adduser` warning in the same list went straight to criterion
5. Decision 117 records that and says they are the first thing to add if
this package ever goes near an archive.

A warning is triaged against what the project said it would do. That is
only possible once the warnings are on the screen.

---

## 21. git add -A published another session's work under this project's commit message

**Friday 2 October 2026.** A second session was editing project 10 in the
same working tree while this project was being committed from it. Every
commit here used `git add -A`.

`15b2da4`, whose subject is "docs(11): criterion 5's build half is met on
a host, with nothing waived", contains:

```
docs/CARD.md                            +35
projects/10-iio-iks4a1/JOURNAL.md      +102
projects/10-iio-iks4a1/docs/RESUME.md   +93
projects/10-iio-iks4a1/docs/TIMELINE.md +28
```

258 lines of project 10 documentation, written by nobody in this session,
committed under a subject that mentions none of it, and pushed.

**What was not damaged**, established before deciding anything: the other
session finished its own work six minutes later in `ca2c0f0`, adding the
remaining 23 lines to the two files it was still editing. Nothing was
lost, nothing was truncated, and the only other commit of this session
that touched anything outside project 11 is this one. `8009360` was
checked and is clean.

**What is damaged** is the record. `git log --oneline -- projects/10-iio-iks4a1`
now shows a project 11 subject against the bulk of a project 10 write-up,
and anyone tracing when the card archive was documented will find the
wrong story first.

**Not rewritten.** The commits are pushed, the content is correct and
complete, and this repository has already spent a day cleaning up after a
history rewrite that left orphaned commits on GitHub. Trading a confusing
subject line for that is a bad exchange. The note here is the fix: it
names the commit so a search finds the explanation.

**The practice that caused it is the thing to change.** `git add -A` in a
shared working tree stages whatever anyone else happens to have open. It
is the same shape as every other failure this project hit today, a tool
choosing its own inputs and never saying what it chose, except this one
chose files rather than findings. Staging is explicit from here: the paths
this session actually edited, named on the command line.

And "tree clean" after a commit meant less than it sounded. It was true,
and it was true partly because everybody else's work had just been
committed too.

## 22. Criterion 5's second half, and a gate that counted instead of naming

*Saturday 3 October 2026.* Stage 2 of `tests/adxl345-install-test.sh` ran
for the first time anywhere, on the wsl laptop JPTOUPM678, and criterion 5
is met.

**It had never run because nothing could run it.** That host has neither
podman nor docker, and `scripts/host-setup.sh` installs neither, so the
test skipped and said clearly why. One `apt-get install -y podman` was the
entire gap. Worth knowing for the next person: the test prints its stage 1
heading and then says nothing for several minutes while it pulls a 124 MB
image and runs apt inside the container, which reads exactly like a hang.
It is not one.

**Then the gate failed on a by-product.** It reported `5 .deb files came
out, wanted 3`, named none of the five, and the `trap` deleted the build
directory on the way out, so the evidence left with it. `debian/control`
declares three binary packages, and debhelper additionally emits an
automatic `-dbgsym` for each one carrying ELF objects, which here is the
shared library and the tools binary; `libadxl345-dev` ships headers and a
symlink and produces none. Three declared plus two automatic is five.
Nothing in the packaging was wrong. The assertion was.

The gate now lists what it found and asserts the three declared packages by
name, which is what `scripts/adxl345-install-purge.sh` had been doing one
stage later all along. The two stages disagreed about what a finished build
looks like, and only one of them had ever executed. It was proved against
fixture directories in four directions before going near a container: the
three declared alone, the three plus two dbgsym, a stray that is neither,
and a declared package missing. The run afterwards named all five, and they
were the two dbgsym packages, so the reading is now evidence rather than
arithmetic.

**What stage 2 proved**, inside `debian:trixie-slim`, in 30 assertions:
apt resolved every `Depends` and configured all three packages; each
`.install` file's promise is on the filesystem; the udev rule landed at
`/usr/lib/udev/rules.d/60-adxl345.rules` through the merged `/usr` symlink
and still names both groups; the postinst created `i2c`, `gpio` and the
`adxl345` account with `/nonexistent` as its home; `ldconfig` knows the
soname and `adxl345.pc` agrees with the package on 1.0.0; `adxl-map` exits
1 with no bus present and its message names the bus it could not open; and
purge leaves none of the 12 shipped files, no bytecode, and nothing in
`ldconfig`.

**Three residues, named as residues.** The `i2c` and `gpio` groups and the
`adxl345` user survive the purge. Policy permits it and no `postrm` undoes
it, and the prover says so in three notes rather than counting them as a
clean removal. A test that called that clean would be wrong in the
direction that is hardest to notice.

**Still open from this.** `scripts/host-setup.sh` installs no container
runtime while a test in `tests/` requires one. The test skips honestly
rather than passing silently, which is the right failure, but the build
laptop should have the runtime from setup rather than from somebody
noticing.
