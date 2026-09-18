# Project 03 journal

## 1. The project is blocked on a system to boot, so it was built from the other end

**What happened.** The specification's key facts line says "NanoPi NEO Air
with the mainline system from Project 2". Project 2 is in flight: a design
document, a U-Boot build script, a kernel build script with a fragment, an
eMMC flashing tool and a 32 assertion test suite, all uncommitted, with an
empty `out/`, an empty `docs/evidence/` and no board yet flashed. There is
no image, so there is nothing to boot.

**This entry originally said Project 2 "has not been done" and that there
was no U-Boot configuration anywhere in the repository.** That was true of
the working tree when it was checked at the start of the session and false
by the time the tests were written, because another session was building
Project 2 in the same tree at the same time. See entry 7.

**What was done.** Everything that does not depend on that system: the
design document with the four specified figures redrawn as text, the two
host programs with their tests, the board-side marker artefacts, and the
configuration fragments. Every measured cell in the acceptance table is
blank and the README says why in its second section rather than in a
footnote.

**Why that and not the alternative.** The alternative offered was to
retarget the project onto a Raspberry Pi, which the bench has several of.
It would have produced numbers sooner and they would have been numbers
about a different experiment: a Pi boots from firmware with no U-Boot, so
the D1 marker and the whole phase between it and the first console byte
simply do not exist. Two of the four reported quantities would have been
undefined. A project that measures three quarters of its subject is not the
project.

The parts are on the bench. The parts-to-project matrix in the
specification's appendix lists the NanoPi NEO Air against projects 2 and 3
and the nRF-PPK2 against 3 and 16, so the blocker is Project 2's software
and not the hardware.

## 2. Two documents disagree about how the PPK2 is wired, and the experiment settles it

**What happened.** The section specifies source-meter mode at 5.0 V, and
its measurement script switches the DUT supply on and off. The
specification's own appendix says of the PPK2 that it cannot power a Pi
with peripherals and directs it to "ampere-meter mode in series with the
supply of the NanoPi NEO Air". Both are in the same document.

**What was done.** Source-meter mode, with the reason written into
`docs/DESIGN.md` next to the decision rather than left as a preference.

**Why that and not the alternative.** Not because the section outranks the
appendix, but because of what is being measured. A boot measurement has to
start from a board that is genuinely off, and only source-meter mode can
switch the DUT rail. In ampere-meter mode the PPK2 cannot cut power, an
external switch sits in the path, and the interval `[0, t_done]` that the
energy figure is defined over has no defined start.

The appendix's caution survives as a limit rather than as a mode: the PPK2
sources at most 1 A. That is why `analyze.py` reports the peak current in
every summary. The limit is then checked by the data in each run instead of
being asserted once in a design document and never looked at again.

## 3. A test passed with the defect in place, and the reason was float formatting

**What happened.** The analysis suite had an assertion that the energy
figure must not contain the string `0.09`, which is what the integral comes
to if it is taken over the whole recording instead of over `[0, t_done]`.
Proving the suite by reintroducing that defect gave **one** failure where
two were expected. The string check had passed with the defect live,
because the wrong integral evaluates to `0.08999999999999998` and that does
not contain `0.09`.

**What was done.** Replaced it with a numeric assertion that the reported
energy is further than a tolerance from the whole-recording value.
Reintroducing the defect now gives two failures, both numeric.

**Why that and not the alternative.** Widening the string to match more
spellings of the number would have kept a check whose subject is how a
float happens to print. The assertion is about a quantity, so it is written
about the quantity.

This is the third time this repository has found a check that was right for
the wrong reason, and the first time one was found by the prove-by-breaking
step rather than by a later accident. That step earned its cost here.

## 4. An acceptance criterion that cannot fail, and what was done with it

**What happened.** The specification's fourth criterion reads: "Energy per
boot is reported in joules with the integration interval stated; the mean
current times the total time reproduces it within 2 percent."

Over the integration interval, `mean(I) * t_done` and `sum(I) * dt` are the
same arithmetic written twice. The second clause is exact by construction
and a check of it could only ever pass.

**What was done.** It is not implemented as a check. Both numbers are
printed, the interval is named in every summary, and the README says
plainly that the clause cannot fail as written.

**Why that and not the alternative.** Implementing it would have added a
green line to the output that carries no information, and this repository
has already shipped three rules that could not fire. A check that never
fails is indistinguishable from a check that passes, and it is worse than
no check because it is counted.

The first half of the criterion is real and is honoured: an energy figure
without its integration interval is not a measurement of anything, so the
interval is in the summary, in the JSON, and in the prose beside the
number.

## 5. Two defects inherited from the specification's own code, found by writing the tests

**What happened.** The section prints a working measurement script and a
sketch of the analysis. Two things in them do not survive being tested.

The marker detector reads `digital[-1][0] == 1`, the last sample of each
batch. The boot-complete edge can land anywhere inside a batch, and when it
lands anywhere but the end the run continues to its timeout with a complete
recording the script never noticed was complete.

The analysis sketch has no discard logic at all. Its `first_edge` returns
`None` when an edge is missing, and the next line multiplies it by `dt`, so
a run where the bootloader never started ends in a `TypeError` rather than
in a discarded run with a reason.

**What was done.** `boot_complete()` looks at every sample in the batch,
and has a test that puts the edge in the middle of one. `analyze.py` raises
`Discarded` with a sentence naming which rule fired and what it saw, and
every discarded run is printed in the summary with that sentence.

**Why that and not the alternative.** The discard rules could have been
applied by hand at the bench, which is what "discard the first run of every
variant" sounds like it means. A rule applied by hand is a rule invented
after seeing the numbers. Both rules are in the program, both are in
`docs/DESIGN.md`, and both were written before any data exists.

The first-run rule is deliberately applied before any file is read, so that
a bad first run is reported as "first run of the variant" and not as a D1
failure. Which rule fired is part of the finding.

## 6. What the tests cannot reach, said here rather than discovered later

**What happened.** 39 assertions pass and none of them has been near a
PPK2.

**What was done.** Written down, in the README's acceptance table as
criterion 0 and here.

The untested surface is exactly the boundary between `record_boot()` and
the `ppk2-api` package: `get_data`, `get_samples` and `digital_channels`
are stubbed, and the stub returns the shapes this code expects rather than
the shapes the library returns. The package has renamed its
digital-channel helpers between releases, `measure/requirements.txt` pins
nothing because no version has been verified here, and the first run
against real hardware is where that is found out.

Above that sits something no software can settle. The PPK2's logic inputs
are referenced to the voltage domain of the device it powers. Every marker
in this project is 3.3 V and the supply is 5.0 V. If the thresholds are not
met then all three channels fail at once, and the answer is a self-test
with D3 against `SYS_3.3V` before anything else is trusted.

## 7. A fact about the repository went stale inside one session

**What happened.** The first thing this project did was establish that
Project 2 had not been started: `ls projects/` returned nine directories
and no `02-`, and a search for the board found four mentions in prose and
no configuration. That went into the README, the design document and
journal entry 1 as the reason every measured cell is blank.

Twenty minutes later `scripts/lint.py` printed a list of untracked scripts
that included `projects/02-neo-air-mainline/uboot/build.sh`. Three project
trees had appeared in the working tree while this one was being written:
02, 05 and 07. Another session was writing them.

**What was done.** Corrected the three places, in place, saying so rather
than editing silently. The conclusion did not change, because Project 2
still has no image and there is still nothing to boot, but the stated
reason was wrong and a reader would have checked it and found a directory
full of work.

**Why that and not the alternative.** The tempting reading is that nothing
needed changing, since the blank cells are blank either way. That is the
reasoning this repository has already been caught by: a claim written when
it was true and left standing after the thing it described changed. No test
holds a sentence, and the sentence here was load-bearing, because it is the
justification a reader is given for a table with an empty column.

The narrower lesson is about a shared working tree. Two sessions editing
one checkout with nothing committed means neither can tell which files are
its own, and `git status` is the only thing that can. It should be read
again before any claim about what the repository does or does not contain,
and not only at the start.

## 8. The design document described a program that did not exist yet

**What happened.** Asked whether the project was finished software-wise,
the answer turned out to be no, and two of the four gaps were claims in
`docs/DESIGN.md` that the code did not honour.

Its data flow said `analyze.py -> results/<variant>/summary.md`.
`analyze.py` printed the summary to stdout and wrote nothing. The same
block named `docs/before-after.md`, which did not exist. The
specification's step 9 loop driver had not been written, and `plot_run()`
had no test of any kind.

**What was done.** `analyze.py` writes `summary.md` into the variant
directory, with `--no-summary` to suppress it and `--json` implying it,
since a machine-readable mode should not leave files behind as a side
effect. `measure/Makefile` runs the loop. `docs/before-after.md` exists
with every cell empty. Ten more assertions, including both branches of the
plotting path: matplotlib is not in CI, so the test exercises whichever
branch this host can reach and prints which one it took.

**Why that and not the alternative.** The alternative was to change the
data-flow diagram to describe what the program did. That would have been
the faster fix and the wrong one: the file is what the Makefile needs and
what `before-after.md` is assembled from, so the document was right and the
program was behind it.

The shape of this is the one the method file warns about in a different
form: a claim written when it was intended, left standing while the thing
it described was never built. It was written in the same hour as the code
and was still wrong, which is the argument for the design document being
checked against the tree rather than only read. Nothing here was caught by
a test, because no test asserted on a document. It was caught by being
asked a direct question and going to look.

The Makefile's own default is worth keeping: it runs **six** boots, not
five. The specification asks for five per variant and the first run of
every variant is discarded by rule, so asking for five leaves four. That is
the kind of quiet shortfall nobody notices until the standard deviations
are being compared.
