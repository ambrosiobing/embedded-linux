# Journal: Project 07

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 18 September 2026 unless noted.

---

## 1. The design was written first, and it found two things

**What happened.** The specification and its four figures were read before
any recipe existed, which is the order Projects 15, 04 and 06 established.
Reading them against this bench rather than against a Raspberry Pi OS
install turned up two things that would otherwise have been found during a
build or on a board.

The first is that six of the specification's steps do not survive contact
with a Yocto image at all. It installs tools with `apt`, runs `dtc` on the
target, and edits `/boot/firmware/config.txt` and `cmdline.txt` by hand.
None of those exist here: there is no package manager on the target, a board
that compiles its own device tree has a boot that depends on a tool being
installed, and a hand-edited boot partition does not survive a reflash. The
translation is a table in [docs/DESIGN.md](docs/DESIGN.md) rather than six
surprises.

The second is in the next entry, because it deserves its own.

**What was done.** [docs/DESIGN.md](docs/DESIGN.md), with all four specified
figures redrawn as text, an ownership table, and the six acceptance criteria
written out in full. No recipe yet.

**Why that and not the alternative.** The alternative is what Project 1 did:
build the thing, then reconstruct the design from the thing. That produces
documentation describing the implementation rather than the intent, and it
structurally cannot catch the case where the implementation drifted from
what was asked for. It also defers every incompatibility to the point where
a build is already running.

---

## 2. Four kernel symbols checked against the source, and one has a trap

**What happened.** The specification asks for three kernel symbols:

```
CONFIG_TINYDRM_ILI9486=m
CONFIG_TOUCHSCREEN_ADS7846=m
CONFIG_DRM_FBDEV_EMULATION=y
```

This repository has a rule about believing symbol names, written after three
invented netfilter symbols survived review, CI and a 178 minute build. So
all of them were read out of `v6.12` rather than recalled. All three exist,
and so does `DRM_MIPI_DBI`, which was the fourth candidate.

Two findings came out of reading the stanzas rather than only checking that
the names resolve.

**`TINYDRM_ILI9486` selects four symbols**, `DRM_KMS_HELPER`,
`DRM_GEM_DMA_HELPER`, `DRM_MIPI_DBI` and `BACKLIGHT_CLASS_DEVICE`. Naming
any of them in the fragment would be noise that somebody later has to keep
true.

**`TOUCHSCREEN_ADS7846` depends on `HWMON = n || HWMON`.** That is a
tristate dependency, and it means the driver can be built in only when
`HWMON` is itself built in or absent entirely. If the Raspberry Pi defconfig
carries `CONFIG_HWMON=m`, then `CONFIG_TOUCHSCREEN_ADS7846=y` is not a valid
configuration and Kconfig drops it without a word. The build succeeds, the
option is absent, and the board has no touch input with nothing anywhere
saying why. That is the exact failure shape this bench keeps meeting.

**What was done.** Recorded in the design's kernel section with the file and
line each symbol was found at, and marked as the first thing to check on the
build host, with the two commands that check it:

```
./go ksym -f lcd35a        every line names a symbol that exists
./go kconfig -f lcd35a     every line reached the .config
```

**Why that and not the alternative.** The alternative is to write the
fragment and let the build find out. The build cannot find out: a fragment
line that Kconfig drops produces no error, which is the whole reason those
two checks exist. Checking the stanza costs one command and answers the
question before a card is written.

**What this entry does not claim.** The `HWMON` interaction is reasoning
from the Kconfig stanza. Nobody has read the Raspberry Pi 3 defconfig to see
what `HWMON` is set to there, because that needs a kernel tree and the
laptop this was written on has none. It predicts a failure; it has not seen
one.

---

## 3. The specification hard-codes the device its own pitfall list warns about

**What happened.** The specification's `drmfill.c` opens `/dev/dri/card1`,
and the same specification's pitfall list says this:

> If `vc4-kms-v3d` is disabled the panel becomes `card0` and `fb0`;
> hard-coded device paths in scripts then point at the wrong device. Match
> on the driver name or the sysfs modalias instead.

Both are correct advice and they contradict each other in the same
document. Worse, one of the acceptance criteria is that running against
the wrong card "fails with a clear error rather than painting the HDMI
output by accident", which the hard-coded version cannot satisfy: opening
`card1` when `card1` is HDMI succeeds and paints HDMI.

**What was done.** `drmfill` walks `/dev/dri/card*`, reads each one's
driver name with `drmGetVersion`, and uses the first that reports
`ili9486`. It prints every card it looked at and what it rejected. An
explicit `-d` is checked against the same name and refused unless `-f` is
given.

That turns criterion 4 from a thing you hope about into a property of the
program. It also follows the rule this bench arrived at the hard way: a
tool that chooses its own input has to say what it chose, and a refusal
without evidence cannot be argued with, so the refusal names the driver it
found and the one it wanted.

**Why that and not the alternative.** The alternative is to keep the path
and document the risk, which is what the specification does. Documentation
does not survive a board configured differently; forty lines of C does.

---

## 4. Two tests, and then the tests were broken on purpose

**What happened.** The suite came out green on the first run: 48
assertions, 0 failures. That is the least informative possible result. A
check that has never failed is indistinguishable from a check that does
nothing, and this repository has already shipped three of those: one
defined and never added to the linter's list, one whose regex matched its
own file's comments and silenced itself, and one whose failure branch
reported a new refusal as a pass.

**What was done.** Four defects were introduced deliberately, the suite
was run, and each was watched to fail with a message naming the actual
fault rather than the symptom:

| Defect introduced | What fired |
|---|---|
| `/bits/ 16` removed from `ti,x-max` | `ti,x-max has no /bits/ 16` / `the driver will read the wrong half of the cell` |
| `CONFIG_TOUCHSCREEN_ADS7846` set to `=m` | two failures, the blanket no-modules rule and the specific one |
| `IMAGE_INSTALL:remove = "bench-status"` deleted | `the image removes bench-status` |

Then the files were restored from a backup and the suite went green again.
Both directions, which is the part that is usually skipped.

**Why that and not the alternative.** The alternative is to trust a green
run. The three shipped non-checks above are what that is worth here.

**What this did not cover.** The `dtc` section is skipped on this laptop,
which has no `dtc`, so the compile assertion has never run in either
direction. `device-tree-compiler` was added to `scripts/host-setup.sh` so
that CI runs it, and until a CI run happens that assertion is written and
unproven. It is skipped loudly rather than quietly, which is the least that
can be done about it from here.

---

## 5. Three shared files, one of them hot

**What happened.** Project 7 needs three files that belong to no project:
`linux-raspberrypi_%.bbappend` for its kernel switch, `go` for its target,
and `scripts/host-setup.sh` for `libdrm-dev` and `device-tree-compiler`.
The bbappend had been written by another session within the previous eight
minutes, adding Project 5's `BENCH_ADXL345_KERNEL`.

That file is the one where a lost write is expensive rather than annoying.
It already carries eleven switches, and adding a twelfth moves the kernel
recipe's basehash whether the switch is on or off, because a basehash
covers the expression and not what it evaluated to.

**What was done.** The three shared files were left until last, so the
window between writing and checking was as short as possible. The bbappend
edit was anchored on the exact two lines of Project 5's switch rather than
appended blind, and immediately afterwards every switch in the file was
counted:

```
BENCH_ROUTER_KERNEL BENCH_RT_KERNEL BENCH_RT_LAB BENCH_BLE_KERNEL
BENCH_NETBOOT_KERNEL BENCH_TEE_KERNEL BENCH_IIO_KERNEL
BENCH_EXPLORER_KERNEL BENCH_DEBUG_KERNEL BENCH_KASAN_KERNEL
BENCH_ADXL345_KERNEL BENCH_LCD35A_KERNEL
```

Twelve, with nothing lost.

**Why that and not the alternative.** The alternative is to write the
shared file first and trust it. A concurrent write to the same file does
not announce itself, and the way this repository has met that class of
failure before is a `str.replace` that matched nothing, returned the string
unchanged, and wrote it back unchanged with no error. Counting afterwards
costs one command.

**What follows from this for whoever builds it.** Adding a switch to that
bbappend stops any build already running on the other laptop, with an error
that blames the metadata. Check that nothing is building before pulling
this.

---

## 6. The README claimed a check that did not exist

**What happened.** Asked whether the project was ready to commit, the
honest way to answer was to re-read the claims rather than repeat them. The
README's table of what is tested without hardware said:

| Check | Command | Covers |
|---|---|---|
| Compile | `./go check` | `drmfill` with `-Werror` against the host libdrm |

`./go check` runs `scripts/host-check.sh`, and `grep drmfill` on that file
returned nothing. The claim had never been true. `libdrm-dev` had been
added to `scripts/host-setup.sh` in the same sitting, which is the half of
the job that makes the other half look done: the dependency was installed
for a step that was never written.

So `drmfill` had not been compiled by anything, anywhere. This laptop has
no C compiler, so nothing local had caught it, and nothing remote would
have either, for the reason in the next paragraph.

**What was done.** Three fixes, because pulling the thread found two more.

1. A `compile drmfill against host libdrm` step in `host-check.sh`. It is
   its own step rather than another block inside the libgpiod branch,
   because a host with libgpiod and no libdrm should still check what it
   can and say what it could not. It runs the binary afterwards and expects
   it to find no panel, which exercises the card-walking path from entry 3.
2. `libdrm-dev` added to the CI workflow. **CI has its own package list,
   separate from `host-setup.sh`**, and nothing had noticed that the two
   had drifted. Without this the new step would have failed every run.

   **This item was wrong when it was written. See entry 7.** CI does not
   run `host-check.sh` at all, so there was no "new step" in CI to fail:
   the package was installed for a step that did not exist there.
3. `device-tree-compiler` added to the same CI list. The overlay suite's
   `dtc` section skips where `dtc` is absent, and its skip message says
   "CI installs device-tree-compiler and does compile it". That sentence
   was also false. An assertion that is written and never runs is the third
   non-check this repository has shipped, and this one was caught before it
   shipped rather than after.

**Why that and not the alternative.** The alternative is to correct the
README to say that `drmfill` is not compiled by anything. That is honest
and it is the wrong repair: the program is forty lines of ioctl calls
against an API this bench cannot otherwise exercise, and compiling it with
`-Werror` is the only check available for it short of a panel.

**What this entry does not claim.** None of the three fixes has run.
`drmfill` still has not been compiled, and the overlay still has not been
through `dtc`, because the machine this was written on has neither tool.
The difference from an hour ago is that the checks now exist and will run
on the next CI, rather than being described in a README as though they
already had.

**The shape worth remembering.** Installing a dependency feels like doing
the work. `host-setup.sh` gained `libdrm-dev`, and that made the compile
step look present in every subsequent reading of the diff, including mine.
The thing that caught it was grepping for the claim instead of trusting it.

---

## 7. The first CI run was red, and five of the eight findings were mine

**What happened.** The commit went to `origin/main` and CI failed at the
`Shell scripts` step, which is `shellcheck`. Eight findings, across four
files. Five of them were in code written for this project:

| File | Finding |
|---|---|
| `lcd35a-verify` line 63 | SC2010, `ls` piped into `grep` |
| `lcd35a-verify` line 100 | SC2012, `ls` where a glob does the job |
| `lcd35a-verify` line 133 | SC2043, a `for` loop over a single literal path |
| `lcd35a-verify` line 136 | SC2086, unquoted expansion |
| `lcd35a-overlay-test.sh` line 236 | SC1087, an **error**: `"$ov["` reads as an array expansion |

The last one matters more than its one line. An error makes `shellcheck`
give up on the rest of the file, so every assertion after it went
unchecked. That is the same shape as the SC1073 another project hit the
same day, and the reason the linter here was tightened an hour earlier.

This is what having no `shellcheck` on the authoring laptop costs, stated
plainly: `lint.py` checks three of its findings and the real tool found
five more in one file.

**What was done.** All five fixed at the cause rather than silenced. The
`ls | grep` became a glob over the driver directory, which is what that
directory actually is; the single-item loop became an `if`; the one
genuine word split kept a `disable=SC2086` with a comment saying why it is
deliberate.

Three further findings were not from this project and were blocking the
same run, so they were fixed too: two in Project 2's `flash-emmc.sh`
(SC2154 on a variable assigned inside the trap body that reads it, and
SC1010 on an unquoted `STATE=done`) and one in Project 9's
`agent-proxy.sh`, an `A && B || C` that this repository has already lost
thirteen CI runs to.

**The finding that outlives the fixes.** Entry 6 said the CI workflow now
compiles `drmfill`. It did not. **CI does not run `scripts/host-check.sh`
at all**; it keeps its own step list, by hand, and the two drift. So the
step added to `host-check.sh` runs for anyone typing `./go check` and has
never run in CI, while `libdrm-dev` sat in the CI package list looking like
the work was done.

That is the identical mistake entry 6 was written about, one level up. In
entry 6 the dependency was installed and the step was missing from
`host-check.sh`. Here the dependency was installed and the step was missing
from the workflow. Both times the installed dependency is what made the
diff read as complete.

So the workflow now has two steps of its own, `Compile drmfill` and
`drmfill finds no panel on a runner`, the second exercising the
card-walking path from entry 3. The comment on the first says why it exists
twice, because the duplication is the thing a later reader will want to
delete.

**Why that and not the alternative.** The alternative is to make CI call
`./go check` and delete its hand-kept list. That is the right shape and it
is a change to every project's CI at once, made while `main` is red, which
is the wrong moment. Worth doing deliberately later; noted here so it is
not lost.

**What is still unproven.** The `dtc` assertion and the `drmfill` compile
have now run nowhere. The previous entry claimed one of them would; this
one claims neither. The next CI run is the first evidence for either.

---

## 8. Five red runs, and the fix was a linter rule rather than a fix

**What happened.** Five consecutive CI runs failed, and reading all five
together rather than one at a time changed what the problem was.

| Finding | In how many of the five runs |
|---|---|
| `flash-emmc.sh:66` SC2154 and `:247` SC1010 | **all five** |
| `boot-energy-analyze-test.sh` SC2154 x3 | three |
| `adxl345-driver-test.sh` SC1073 | two |
| `lcd35a-verify` x4, `lcd35a-overlay-test.sh` SC1087, `agent-proxy.sh` SC2015 | one |

The two in `flash-emmc.sh` arrived with the first red run and were never
fixed, so every run after it was going to fail whatever anyone else pushed.
Four sessions then pushed on top, each adding findings and each reading
only its own run. Project 7 contributed five of the eight in the last one.

**What was done.** All eight fixed, and then the actual problem addressed,
which is not any of them. The authoring laptop has no `shellcheck`, so
every one of these was invisible until a runner said so, which costs a
push, a run, an email and a round trip each time.

`scripts/lint.py` already carried three narrow rules for exactly this
reason, for SC2086, SC2120 and SC1072/SC1073. Five more were added for the
patterns that escaped this evening: SC2010, SC2012, SC2015, SC1087 and
SC1010. Every one of them is a pattern a regex can see, which is why they
are worth carrying and why the several hundred that are not remain CI's job.

**The rules were proved in both directions before being trusted.** A
fixture with all five defects produced five findings with the right codes;
a fixture with the five legitimate forms that resemble them produced none.
That second half mattered: the first version of the rules fired on three
innocent lines in `scripts/build.sh`, `scripts/common.sh` and
`tests/iio-probe-test.sh`, because `|| true` is not a pipe and
`VAR=$(cd x && pwd) || exit 1` is not the `A && B || C` mistake. A linter
that cries wolf on correct code is worse than no linter, because people
learn to skip it.

**Why that and not the alternative.** The alternative was to install
`shellcheck` on the Windows laptop, which I proposed and which was wrong:
`./go` and its checks run on the WSL laptop, and this one is for editing
and committing. Growing the linter is the bench's own documented answer to
a blind spot that has shipped twice, and it helps every future session on
this machine rather than only this one.

**What is still not covered.** SC2154, the finding that started all five
runs, needs dataflow rather than a regex and is not among the five. The
authoring laptop still cannot see the other several hundred, and the
linter now says which eight it does check instead of implying it checks
shell code generally.

**Owed.** A `walkthrough/DECISIONS.md` entry for the principle, not written
here because that file is shared and two sessions are active in the
checkout; entries written in parallel have collided twice.

---

## 9. The sixth run went further, and found a bug this laptop cannot see

**What happened.** With the eight shellcheck findings fixed, CI got past
`Shell scripts` for the first time in six runs and failed at `Tests`
instead. The failing assertion was Project 3's:

```
FAILED   the header is the one analyze.py checks by name:
         wanted 't_s,i_ua,d0,d1,d2', got 't_s,i_ua,d0,d1,d2
```

Two strings that print identically. The closing quote is missing from the
second because the value ends in a carriage return, which the terminal
swallowed.

**The cause, read rather than guessed.** `ppk2_boot.py` wrote its CSV with
`csv.writer(handle)`. Python's csv module defaults to `lineterminator =
"\r\n"`, confirmed by running it rather than recalling it, so the
measurement file a Linux board produces comes out CRLF. Everything
downstream reads it with `head`, `sed` and `cut`.

**Why it had never been caught.** The first attempt to reproduce it here
passed. So did a run with the defect deliberately put back, which is what
said the reproduction was wrong rather than the fix. The reason is that
**this laptop's shell strips a trailing carriage return in command
substitution**:

```
printf 'a\r\n' > f; x=$(head -n 1 f); [ "$x" = "a" ]   # true here
```

So `"$(head -n 1 out.csv)"` compares equal on Windows and unequal on
Linux, and the local suite cannot see this class of bug at all. Verified
by testing the shell directly, not inferred.

**What was done.** `lineterminator="\n"` on the writer, proved in both
directions at the byte level, which is the only level where this machine
can tell the difference:

```
with the defect:   header ends with CR: True
with the fix:      header ends with CR: False
```

And a `scripts/lint.py` rule for `csv.writer` without an explicit
lineterminator, proved to fire and then go quiet. Same argument as the
shellcheck rules in entry 8: a blind spot that has shipped once gets a
narrow rule rather than a resolution to be careful.

**The other thing this run showed.** CI's test loop is `sh "$t" || exit 1`,
so everything alphabetically after the first failure never runs. Six runs
had therefore said nothing about two thirds of the suite. A `python3` shim
on PATH turns 16 locally unrunnable suites into runnable ones, and with it
42 of 46 pass here. The four that do not are this machine: two need stubs
that native Windows Python cannot exec, one needs a C compiler, and
`rt-plot` fails because native Windows Python cannot resolve the MSYS
`/tmp/...` path the shell just wrote to, which is an artefact of the shim
rather than a fault in the test.

**Why that and not the alternative.** The alternative was to strip the
carriage return in the test. That makes the suite green and leaves every
consumer of the CSV reading a CRLF file, which is the wrong half of the
problem to fix: the test was right and the producer was wrong.
