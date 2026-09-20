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

## 9. CI found what this host cannot run, and the fix nearly repeated journal 59

**What happened.** The first push went red. `shellcheck -s sh -e
SC1090,SC1091` in CI reported SC2154 three times against
`tests/boot-energy-analyze-test.sh`: `out_d1`, `out_d0` and `out_d2`
referenced but not assigned.

They were assigned, by `eval "out_$chan=$(...)"` inside a loop, which no
static checker can follow. The authoring laptop has no shellcheck, so the
suite had passed here 37 times without anyone being able to say that.

**What was done.** The `eval` is gone. The assertion happens inside the
loop and the label travels with the case that produced it, so each of the
three missing-edge cases now reads as one block instead of an assignment
here and an assertion forty lines later.

Then `scripts/lint.py` refused the comment explaining the fix, because it
began `# shellcheck cannot follow`, and a comment whose first word after
the hash is `shellcheck` is parsed as a directive with `cannot` as the
directive name. **That is journal 59 of Project 8, exactly**, which is why
that rule exists and why it fired within a minute of the defect being
introduced.

**Why that and not the alternative.** A `# shellcheck disable=SC2154`
would have made the run green in one line. It would also have kept a
construct that hides three variables from every reader, not only from the
tool, and the rule this repository keeps returning to is that a check
refusing is information rather than an obstacle.

The narrower lesson is about where a check lives. The CI log named the
file, the line and the variable, and reading it took one API call with the
credential git already holds. The prediction that it would fail was made
before the log was read and was right, but predicting is not knowing, and
there was no reason to guess when the run had already finished.

## 10. The blocker cleared, and the sentence about it went stale a second time

**What happened.** Project 2 reached Complete on hardware on Saturday
19 September 2026. Its board boots U-Boot 2025.10 and a 6.12 kernel from
its own eMMC to a login prompt on `ttyS0`, with a 522 line console capture
in `projects/02-neo-air-mainline/docs/bootlog-emmc.txt`.

This project's README, design document and journal entry 1 all said that
Project 2 was in flight and had produced no image, with `out/` and
`docs/evidence/` empty. Every word of that was true on Friday 18 September
2026 and false on Saturday 19 September 2026.

**What was done.** Corrected in all three places, in place, saying what the
earlier version claimed rather than replacing it silently. The empty
Measured column stayed empty, but its reason changed from "there is nothing
to boot" to "no board has been powered through the PPK2", which is a much
smaller and much more actionable statement.

**Why that and not the alternative.** Leaving it would have been defensible
on the grounds that the conclusion did not move. That is precisely the
reasoning decision 97 is about, and this is the second time in this
project's short life that the same sentence has gone stale: entry 7 records
the first, when another session created Project 2's tree twenty minutes
after this one had established it did not exist.

Twice in two days, on one sentence, is a pattern rather than an accident.
The sentence was load-bearing in a particular way: it was the justification
a reader was given for an empty column, so a reader who checked it would
have found a completed project and concluded the table was neglected rather
than blocked. A claim that explains an absence has to be re-read whenever
the absence is what changed.

**What this unblocks.** Everything in `docs/BRINGUP.md`. The first step is
the logic-level self-test, D3 against `SYS_3.3V` with the supply at 5.0 V,
because if the PPK2's logic inputs cannot see a 3.3 V marker then all three
channels fail at once and the method needs rethinking before any wiring is
worth doing.

## 11. The variant plan had no way into a build, and nothing said so

**What happened.** With Project 2 finished, the next thing to check was
whether this project's fragments could actually be fed to its build
scripts. They could not. `kernel/build.sh` and `uboot/build.sh` each
hardcode one path, `fragments/bench.cfg` and `fragments/bench.config`, and
die when it is missing. No argument, no environment override, no second
fragment.

So every variant in this project, the U-Boot trimming and all four kernel
fragments, had nowhere to go. `docs/DESIGN.md` described a workflow that
could not run.

**What was done.** Both scripts take an optional `NEO_EXTRA_FRAGMENT`.
Unset behaves exactly as before; set and unreadable is refused by name
with the path and a sentence saying how to build the baseline instead.
The merge argument list is built with `set --` so the empty case passes no
empty argument and neither path is word-split, and the verification loop
now checks both fragments rather than only the project's own.
`tests/neo-air-extra-fragment-test.sh`, 14 assertions across both scripts,
none of which needs a cross compiler; removing the guard from one script
fails exactly its three.

**Why that and not the alternative.** The alternative was to write the
dependency into this project's design as a note for whoever picked up
Project 2 next. That would have left a document describing a workflow that
does not run, which is the defect decision 97 is about and which this
project has already committed once.

The change went into another project's files, which a concurrent session
owns. The tree was quiet and the change is additive, and the refusal is
the part that matters: a variant whose fragment was silently skipped would
be **built as the baseline and recorded as a change**, and the two rows
would differ by nothing with nothing to say why. That is the same failure
as measuring two images that turned out to be identical, which Project 8
spent a day on.

**What the check still cannot see.** The verification loop skips comment
lines, so a `# CONFIG_X is not set` option is merged and never confirmed.
The U-Boot variant here is almost entirely such lines. Left as it is, and
written into `docs/BRINGUP.md` as something to confirm on the board
instead, because widening that loop changes a check Project 2 relies on
and belongs to whoever owns it.

## 12. The wiring table is missing a pin, and the self-test would have lied about it

**What happened.** The first session with the instrument produced a
current trace and no answer, because the Power Profiler's digital channels
are off by default and the current plot looks the same either way. Joseph
then produced a wiring note saying the PPK2's logic port has a VCC pin
that goes to the board's 3.3 V rail, with D3 on some other 3.3 V pin.

That contradicted this project's own design document and
`docs/BRINGUP.md`, both of which said D3 goes to header pin 1
(`SYS_3.3V`) and said nothing about a logic VCC. Both were following the
specification's wiring table.

Nordic's documentation settles it. The logic port carries **VCC and GND of
its own** alongside D0 to D7; VCC is the level shifter's reference and is
required between 1.65 and 5.5 V.

**What was done.** Corrected in the design document, the bring-up order
and the acceptance table. Logic `VCC` to pin 1, logic `GND` to pin 6, and
D3 to pin 17, which is the same `SYS_3.3V` net as pin 1, so the input sits
at its own reference and must read high. Two pins rather than one wire
doubled back, because a single contact that has come loose looks exactly
like a level that cannot be read.

**Why this is the worst kind of error and not merely a wrong one.** The
design said the open question was whether 3.3 V markers could be read
while the supply was 5.0 V, and that if they could not, all three channels
failed at once. The supply domain and the logic domain are separate on
purpose, so that was never the risk. But **the specification's table omits
the reference pin**, and following it exactly produces precisely that
symptom: D0, D1 and D2 all reading nothing.

So the self-test would have failed, for a missing jumper, and confirmed a
prediction this project had written down in advance. It would have been
believed, and the method would have been abandoned or redesigned around a
fault that a single wire fixes. A check that can only confirm the
hypothesis that motivated it is not a check, and this one was two documents
deep before anyone looked at the instrument's manual.

**Why the documentation and not the note.** The note was right, but it
arrived as an image with no source, and this project had already committed
one mechanism written in the same voice as an observation. The Nordic user
guide is the authority for what the connector does, it took one search,
and the answer is now quoted with its numbers rather than paraphrased.

Step 1 of `docs/BRINGUP.md` now lists four wiring faults to rule out
before anything is concluded about the instrument. Every one of them is
more likely than a documented part not doing what it documents.

## 13. Criterion 0 is met, and it was settled by measuring the screenshot

**What happened.** With the logic port's VCC on `SYS_3.3V` and D3 on pin
17, the Power Profiler's eight digital rows are a few pixels tall and a
static line cannot be read by eye. Two people looking at the same image
could reasonably disagree about whether D3 was high.

Joseph measured the line centre inside each band as a percentage of the
band height. D3 sat at 62 percent, the other seven at 38 percent, about 14
pixels apart.

**What was done.** Recorded as a pass in
`docs/evidence/logic-selftest.txt`, with the wiring, the app settings and
the eight percentages. Criterion 0 is the first cell in this project's
Measured column.

**Why that and not the alternative.** The alternative was to ask for the
jumper to be moved to ground and back, watching for the row to step. That
would also have worked and it would have cost a round trip and an
uncertainty: a line that moves proves the channel switches, but a line
that does not move proves nothing about which of four wiring faults caused
it.

The percentages are better evidence than a toggle, because **four of the
seven low channels have nothing attached at all.** D4 to D7 are the
control. The comparison is against a known-unconnected input rather than
against an assumption about where the renderer draws "low", which is
exactly the question that made the image unreadable in the first place.

A measurement with its own control, from a screenshot nobody could read.

**What is not settled.** The same window shows a maximum of 0.96 A against
the PPK2's 1 A ceiling, where an earlier window that evening showed
416.45 mA under the same supply setting. That is four percent of headroom
and it is written into the evidence file as observed and unexplained. If
demand reaches the ceiling the instrument limits rather than supplies, the
board can brown out, and a run taken while it is limiting is invalid
rather than merely high. It is to be understood before a 60 second
measurement, not after one.

## 14. A comment that was parsed as a directive, and it worked by accident of line order

**What happened.** The first U-Boot build with `marker.config` succeeded
and its own check reported every fragment option present. In the middle of
the output, `merge_config.sh` said this:

    Value of CONFIG_PREBOOT is redefined by fragment marker.config:
    Previous value: CONFIG_PREBOOT="usb start"
    New value: # CONFIG_PREBOOT runs before the boot delay and before any
    storage is CONFIG_PREBOOT="gpio set PG11" # Without this, "gpio" is not
    a command U-Boot has, CONFIG_PREBOOT names

It had swallowed two paragraphs of prose into the value. The fragment
opened its explanation with `# CONFIG_PREBOOT runs before the boot
delay`, and **in a kconfig fragment a line beginning `# CONFIG_` is not a
comment**: it is how an option is turned off, so the parser read the
sentence as a directive.

**The produced `.config` was correct**, checked on the board machine:
`CONFIG_PREBOOT="gpio set PG11"`. The build is usable and was not redone.

**That is luck, and naming it as luck is the point.** The prose line came
BEFORE the real assignment in the file, and the last value wins. Written
the way explanations usually are, underneath the setting they explain,
`CONFIG_PREBOOT` would have become that sentence, U-Boot would have run a
command that does not exist, D1 would never have risen, and the build
would still have reported success. The project would have debugged a
marker on the board.

**What was done.** A lint rule: in `*.cfg` and `*.config`, a line matching
`^# CONFIG_` must be exactly `# CONFIG_X is not set`. Anything else is
prose in directive position and is refused by name.

It found **five**, and only two were mine. The other three are in
`meta-bench` fragments that go into built images: `bench.cfg` line 41
opening `# CONFIG_PREEMPT_RT belongs to Project 8`, `debug.cfg` line 109,
and `iio.cfg` line 61. All five reworded so the symbol is not the first
word after the hash.

The worst was in my own `fast.config`:

    # CONFIG_AUTOBOOT_KEYED is NOT set. Setting it, with a key sequence, makes

which differs from a real directive by a capital letter and a full stop.

**Why a rule and not care.** This is the third shape of its kind in this
repository, after two rounds of `# shellcheck` comments being parsed as
shellcheck directives, which `scripts/lint.py` already has a rule for. A
comment whose first token is a name the tool parses is not a comment. Care
did not catch the first two and did not catch this one; it was caught by
reading a diagnostic that scrolled past inside a successful build.

Proved in both directions: reintroducing the prose comment fires the rule,
and a legitimate `# CONFIG_X is not set` line still passes.

## 15. The build discarded the device tree change and reported success

**What happened.** The marker node went into the kernel tree as a commit,
`git format-patch` saved it into this project, and `./go neo-air kernel`
was run. It printed

    --- tree is at 'no tag', wanted v6.12, re-fetching

and then about eleven thousand lines ending in `zImage`, the dtb, the
modules and `brcmfmac present`. Every sign of a good build.

Both of these came back zero:

    grep -c boot-marker .../sun8i-h3-nanopi-neo-air.dts
    strings .../sun8i-h3-nanopi-neo-air.dtb | grep -c boot-marker

**Why.** `kernel/build.sh` pins the tree with
`git describe --tags --exact-match`, and when that does not match
`$KERNEL_TAG` it re-fetches, checks the tag out and runs
`git clean -qxdf`. A commit of your own is precisely what makes
`--exact-match` fail, so **the act of saving the change is what guarantees
it is thrown away.**

**What was done.** `NEO_EXTRA_PATCH` in `kernel/build.sh`, symmetric with
`NEO_EXTRA_FRAGMENT`: an optional patch, validated at configuration time,
made absolute because `git -C` runs from the tree, applied after the tag
is checked out and before anything is configured. `git apply --check`
first, so a patch made against another version fails loudly instead of
half applying. Tracked files are restored to the tag before applying, so a
second run is not an error and the rebuild stays incremental: a
device-tree patch recompiles a dtb, not a kernel.

Six assertions in `tests/neo-air-extra-fragment-test.sh`, 20 in total now.
Removing the guard fails three of them.

**Why that and not the alternative.** The alternative was to remember to
re-apply the edit before every build. That is the same class of thing as
"comment the trimming lines back in", which this project already got wrong
within a day, and worse here because there is no diff to inspect: the
evidence of the edit is destroyed by the process that needs it.

**The part worth keeping.** The build was not wrong. It did what it says
it does, loudly, in a line that scrolled past two seconds before a
successful compile. What was missing was a check on the artefact rather
than on the exit status, and `docs/BRINGUP.md` now ends that step with one:
count `boot-marker` in the dtb. This is the same lesson as the firmware in
Project 1 that was installed and unreachable. **Every build artefact
answers "did it build". None of them answers "did it build what I asked
for."**

## 16. The markers work, and watching them work found a defect in the capture

**What happened.** Saturday 19 September into Sunday 20 September 2026,
the first time all four logic channels were wired and the board was
powered from the PPK2 alone.

With the board booted and idle, D0, D1, D2 and D3 all read high: the
boot-complete marker on PA6, U-Boot's preboot marker on PG11, the console
TX idling, and the reference. Every link in the chain from
`marker.config` through the device-tree patch to `boot-marker.service`,
visible at the instrument at once.

Then a power cycle was watched live, and **D0 goes high, low, then high**.

The fall is early, before the console has said much. The reading, and it
is inference rather than observation: nothing owns PA6 through BROM, SPL
and U-Boot, so it reads high; the kernel's `gpio-leds` driver probes and
applies `default-state = "off"` from the device tree, driving it low; the
marker unit raises it at the end. Only the third of those is the event
this project measures.

**What that broke.** `ppk2_boot.py` asked whether D0 was high **anywhere**
in a batch of samples. That is true in the very first batch. The capture
would have stopped about half a second after power on, written a CSV
holding the beginning of a boot, and reported success. `analyze.py` would
then have found its rising edge in that fragment and reported a boot that
completed before the kernel started.

**What was done.** `rising_edge()` replaces it, carrying the previous
level across batches because an edge is a property of two samples and
those two are not always delivered together. The level starts as `None`
rather than `0`: an unknown starting level is not a low one, and assuming
low would turn "D0 was already high when we started looking" into a
transition that never happened.

A third stub mode in `tests/boot-energy-capture-test.sh` reproduces what
the board does: high, falling, rising. Reverting to the level check fails
**one** of the two new assertions, and it is worth saying which. `MARKER
yes` still passes, because the broken detector does report a marker,
instantly and wrongly. What catches it is the row count: 3 instead of 9,
the capture ending in the first batch.

**Why this is the entry worth keeping.** Nothing in the test suite could
have found this. The stubs were written from the design, and the design
said the marker rises once. The board says otherwise, and it only says so
across a power cycle: a running board shows levels, and levels looked
perfect.

`default-state = "off"` is why the pin falls at all, and the comment in
`boot-marker-led.dtsi` already argued for it on the grounds that an LED
in an undefined state gives the analysis no rising edge to find. That
reasoning was right and incomplete. It produces a **falling** edge as
well, in a place nobody predicted, and the capture had to learn about it.

**Still to check on the next capture.** The peak current. Idle is 112 mA
with a 424 mA maximum, but a window containing a boot showed 0.96 A
against the PPK2's 1 A ceiling. If a boot ever demands more than the
instrument can source, it limits rather than supplies, the board may
brown out, and that run's energy figure is wrong rather than merely high.
`analyze.py` reports `peak_ma` on every run for this reason and it is to
be read on the first real capture, not at the end of the matrix.

## 17. The instrument was under-supplied all along, and the discard rule proved itself

Sunday 20 September 2026, the session that got the board onto its eMMC and
the PPK2 onto a COM port.

**The discard rule stopped being an argument and became a measurement.**
Three boots of the same image, same kernel, same marker:

| Boot | Kernel | Userspace | Total |
|---|---|---|---|
| Card, first, after an unclean shutdown | 2.405 s | 18.217 s | 20.623 s |
| Card, second, clean | 2.593 s | 10.564 s | 13.157 s |
| eMMC, first | 1.871 s | 9.357 s | 11.229 s |

The first two differ by **57 percent**, and the difference is one thing:
`EXT4-fs (mmcblk0p2): recovery complete` and
`system.journal corrupted or uncleanly shut down, renaming and
replacing`. The rule that discards the first run of every variant was
written into `analyze.py` and `docs/DESIGN.md` before any data existed,
on the argument that a filesystem change is a property of the previous
run rather than of the variant being measured. It would have swallowed
7.5 seconds into the baseline.

It also means I was wrong to call the 20.623 s figure "the baseline" when
it appeared. It was the number the rule exists to throw away.

**And that opens a problem with the method itself.** `ppk2_boot.py` ends
every capture by cutting VOUT, because a boot measurement has to start
from a board that is genuinely off. So **every measured run leaves the
filesystem unclean and every following boot pays recovery**. The variants
are at least consistently affected, but the baseline is systematically
inflated and the variance is worse, which criterion 3 cares about: it
wants a standard deviation under 5 percent.

`Storage=volatile` for journald is already listed in
`board/units-disabled.txt` as part of the `30-systemd` variant. Part of
the saving it shows will therefore be an artefact of how this project
measures rather than a property of the system. That has to be said in the
write-up rather than claimed as an optimisation.

## 18. The PPK2 has two USB connectors and only one was ever plugged in

**What happened.** Asked to be specific about which USB port to use, I
went and read the documentation instead of recalling it. The PPK2 has
two micro-USB connectors:

    DATA/POWER       communication and the instrument's own power
    USB POWER ONLY   supplies the DUT, required in source-meter mode
                     above 400 mA

Only DATA/POWER has ever been connected, in this session and every
earlier one. This board idles with a 424 mA peak and showed 0.96 A in a
window containing a boot. **Both are over the threshold**, so the
instrument has been sourcing an over-400 mA load from a single USB port
throughout.

**What that costs.** Every current figure taken so far is suspect. The
0.96 A that looked like the board approaching the PPK2's 1 A ceiling is
more likely the USB port running out. Those numbers were observations
rather than results, but they were already in
`docs/evidence/logic-selftest.txt`, which is corrected in place.

**What survives.** Criterion 0 and the marker verification. D3 high, and
D0, D1, D2, D3 all high, are logic levels read through the level shifter
against its own 3.3 V reference, which does not depend on supply
headroom. The board booted to a login repeatedly, so it was not badly
starved.

**Why this was found by a question rather than by a check.** Nothing in
the project could have caught it. `analyze.py` reports `peak_ma` on every
run precisely so that a limiting instrument becomes visible in the data,
and it would have shown the symptom without ever naming the cause. It took
Joseph asking which connector, and the answer being in a document neither
of us had read.

The same shape as the logic port's own VCC pin two days earlier: a
connector on the instrument that the specification's wiring table does
not mention, whose absence produces a plausible wrong reading rather than
an error. **Twice now, the fault was a pin nobody had been told about.**

## 19. Two smaller corrections from the same session

**Power down before unplugging.** Joseph stopped me mid-instruction to
ask whether the board should be powered off rather than pulled, and he
was right. We had just measured what a hard cut costs on this board:
7.5 seconds of recovery on the next boot. The H3 has no power-off path,
so `poweroff` ends at `reboot: Power off not available: System halted
instead`, which is fine: the filesystems are unmounted and synced by
then, and that is the part that matters.

**The PPK2's serial port is not called what I said.** It enumerates as
`nRF Connect USB CDC ACM`, not `JLink CDC UART Port`, which is the name
on Nordic's development kits. `docs/BRINGUP.md` says the right one now.

## 20. The peak was inrush, and my explanation for it was wrong

Sunday 20 September 2026. The first capture that ever completed,
1,597,440 samples over 15.974 seconds, written from the board with both
PPK2 USB connectors attached for the first time.

The number this project was waiting on was the peak current, because
everything else depends on the instrument not having been limiting while
it measured. Entry 18 predicted the peak would fall once the DUT had its
own supply connector, on the reasoning that 0.96 A was the single USB
port running out.

It did not fall. It came back at **1015.2 mA**, slightly higher.

The prediction was wrong and the reason it was wrong is visible in the
same file. The peak lasts **two samples, twenty microseconds**, at
1.41 ms after the supply comes on. That is the board's bulk capacitance
charging, not the board drawing. Past the first ten milliseconds nothing
in the entire boot goes above 804 mA:

    first 10 ms, inrush                peak 1015.2 mA   mean  90.3 mA
    10 ms to first console byte        peak  206.9 mA   mean  84.8 mA
    first console byte to complete     peak  804.2 mA   mean 183.6 mA
    the 0.5 s tail, idle               peak  564.2 mA   mean 144.9 mA

So the 0.96 A seen in the Power Profiler two nights ago was this same
transient, seen in a ten second window that happened to contain a power
on. The under-supply was real and connecting USB POWER ONLY was still
the right call, but it was never what that number meant.

What the measurement does settle is better than what I was looking for.
During the boot itself the instrument had about twenty percent of
headroom, so it was not limiting while it worked. That is the claim the
project actually needs, and it is now made from data rather than from an
argument about connectors.

**THAT LAST PARAGRAPH IS WRONG AND IS CORRECTED IN ENTRY 22.** It was
written from one run. Five more arrived within the hour and three of them
reach 942 to 994 mA inside the boot with no inrush involved, so the
headroom claimed here does not exist.

**The lesson is one this repository keeps relearning.** A number at the
edge of an instrument's range invites an explanation about the
instrument. The explanation was available, plausible, and wrong, and it
survived two days because nobody had looked at where in time the peak
sat. Twenty microseconds and fifteen seconds are different phenomena and
a single maximum cannot tell them apart. `analyze.py` reports `peak_ma`
per run, which was right, but a peak with no time attached to it is
still an invitation to guess.

## 21. D1 is stuck high, and the deadline rule cannot tell the difference

The same file, read one channel further.

    d0   starts 0, ends 1, one rising edge at 15.45212 s, no falls
    d2   starts 1, first falling edge at 1.06975 s, 78,998 edges after
    d1   starts 1, ends 1, ZERO rising edges, ZERO falling edges

D1 is the U-Boot marker on PG11, and it is high in all 1,597,440 samples.
It is high at sample zero, ten microseconds after the supply comes on,
when the SoC is still in the boot ROM and U-Boot is several seconds away
from existing.

`phases()` discards the run for it, with the reason **"D1 never rose, so
U-Boot never started"**. That is the correct behaviour drawn from a
channel that is not telling the truth, and it is the worst kind of
correct: the sentence names a cause, the cause is wrong, and the run is
gone. A reader of the output would go looking at the bootloader.

Everything else in the capture is sound and agrees with the board:

    first console byte, D2 falling         1.070 s
    boot complete, D0 rising              15.452 s
    tail after the marker                  0.522 s   (0.5 s by design)
    energy over [0, t_done]               13.660 J   at 5.0 V

15.452 less the 11.229 s that `systemd-analyze` reports leaves 4.2 s of
U-Boot, which is the right size for `bootdelay=2` plus loading. The
`rising_edge()` rewrite from entry 16 is doing on real data exactly what
it was written for: D0 rose once, at the marker, and never fell.

`docs/BRINGUP.md` anticipated the opposite failure and says to check with
`gpio set PG11` typed by hand when **"the board boots normally and D1
stays low"**. It stays high, so the check written there does not reach
this. Pin 7 is PG11 on the NEO Air header, so the wiring table is not
wrong; what is unsettled is whether the wire is seated on pin 7 and what
the pin does coming out of reset.

**If PG11 idles high, a rising-edge marker cannot work on it at all**,
and the preboot has to drive it low instead, or the marker has to move
to a pin that is genuinely low out of reset. That is a design change and
it gets written down before it is made, not after.

One thing not to do, and it is tempting: D2's first falling edge is a
perfectly good "the bootloader is alive" signal sitting right there at
1.070 s. Substituting it for D1 would make the discard stop and the
table fill in. It would also silently redefine `t_uboot` from "BROM plus
SPL, before any storage is scanned" into "first console byte", which is
a later and different event. The rule in `docs/DESIGN.md` is that
discard rules are not negotiable after seeing the data. A definition is
not negotiable after seeing the data either.

## 22. Six runs, and the one-run conclusion in entry 20 does not hold

Sunday 20 September 2026. Five more captures, taken in a loop with ten
seconds of rails-down between them, joined the first. `analyze.py` over
the directory:

    6 run(s) found, 0 kept.

    - boot-00.csv: first run of the variant, discarded by rule
    - boot-01.csv: D1 never rose, so U-Boot never started
    - boot-02.csv: D1 never rose, so U-Boot never started
    - boot-03.csv: D1 never rose, so U-Boot never started
    - boot-04.csv: D1 never rose, so U-Boot never started
    - boot-05.csv: D1 never rose, so U-Boot never started

Five identical reasons and no sixth kind of failure. The capture path is
now proven on five independent boots and D1 is the only thing between
these six files and a filled-in table. The first-run rule and the D1 rule
also fired separately and said which was which, which is the whole reason
the first discard is applied before any file is read.

**The correction.** Entry 20 said that past the first ten milliseconds
nothing in the boot goes above 804 mA, and concluded that the instrument
had about twenty percent of headroom while it measured. That was written
from `boot-00` alone. Splitting inrush from the rest, per run:

    run          inrush    after 10 ms   at        above 900 mA
    boot-00     1015.2 mA     804.2 mA   15.325 s     0.020 ms
    boot-01      910.6 mA     800.8 mA   11.315 s     0.010 ms
    boot-02      942.7 mA     840.9 mA   14.854 s     0.040 ms
    boot-03      886.5 mA     994.1 mA   14.658 s     0.190 ms
    boot-04      958.3 mA     959.2 mA   15.161 s     0.300 ms
    boot-05      912.4 mA     861.5 mA   15.229 s     0.010 ms

Three of the six reach 942 to 994 mA **inside the boot**, in the last
second before the marker, with no capacitor charging involved. `boot-03`
comes within six milliamps of the source limit. There is no twenty
percent of headroom. There is, at those instants, no headroom worth
naming.

The energy figure survives this and the peak figure does not. The whole
time spent above 900 mA is at most 0.30 ms inside a 15.5 second
recording, so if the meter were hard-clipping through every one of those
samples the error in a 14 J integral is under a hundredth of a percent.
`peak_ma` is a different matter: at those moments the number may be a
property of the PPK2 rather than of the board, and the write-up has to
say so rather than quoting it as the board's maximum demand.

**This is the second time in one evening that one run produced a
confident wrong sentence**, and the first time was three hours earlier in
the same journal. Project 8 did this too, at row 3 of eighteen. The
pattern is not carelessness about arithmetic, it is that a single run
reads like a measurement and behaves like an anecdote, and the discard
rules exist because the project knew that before the hardware did.

**What the six runs do establish.** With D1 set aside, the other two
channels give real numbers over six boots:

    t_console   1.07440 s   sd 0.00410 s
    t_done     15.48606 s   sd 0.19162 s
    energy      14.087 J    sd 0.288 J

Four milliseconds of spread on the first console byte. That is the
measurement quality the project was built for, and it is a strong
argument for the marker method over reading timestamps off the board:
`systemd-analyze` cannot see anything before the kernel, and the interval
from power on to the bootloader printing is where this variant's savings
are supposed to come from.

**And entry 16's rewrite paid for itself.** In five of the six runs `d0`
starts HIGH, falls once, then rises once: the pin is undriven through
BROM, SPL and U-Boot, the kernel's `gpio-leds` applies
`default-state = "off"`, and the marker unit raises it. `boot-00` starts
low because the board had been off long enough to discharge, while each
of the other five began ten seconds after a power cut. The original
detector asked whether D0 was high anywhere in a batch and would have
ended five of these six captures in the first batch, half a second after
power on, with a CSV full of BROM. It was rewritten before any of this
data existed, on the strength of watching one power cycle, and five runs
have now exercised the case it was rewritten for.
