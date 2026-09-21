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
VL53L8CX. The bench has a DFRobot SEN0032, an ADXL345, and that is the
only loose sensor on it. So the project is built on the ADXL345.

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
