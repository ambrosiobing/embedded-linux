# Journal: Project 8

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 15 September 2026 unless noted.

---

## 1. The design was drawn before the code, again

**What happened.** Project 1 was built first and its four specified figures
were written last, after being asked for twice. Project 15 corrected that
by starting from the specification. This project did the same.

**What was done.** The four figures in the specification, architecture,
schematic, bench layout and the activity diagram of one run, were redrawn
as text in [docs/DESIGN.md](docs/DESIGN.md) before a recipe existed, and
two more were added that the original scope does not have: a component
diagram saying why each program is separate, and a sequence diagram
showing exactly where the internal and external measurements diverge.

**Why that and not the alternative.** Drawing the sequence first is what
produced the sentence this whole project turns on: the external instrument
sees the wake-up latency *plus* the system call, the internal one sees only
the wake-up latency, and the difference between them is the measurement.
That was in the original prose and not in any of its figures, and drawing
it is what made it a testable claim rather than a remark.

**Correction, added later.** That sentence is wrong. The external
instrument measures an interval between two edges, and a constant system
call cost appears in both ends of it and cancels; what survives is the
*variation* in the output path. See entry 21, which has the algebra and the
simulation that settled it. The point of this entry stands, and is if
anything sharpened: drawing the sequence turned a remark into a claim
specific enough to be checked, and checking it is what showed it to be
wrong. A vaguer statement would still be in the repository.

---

## 2. PREEMPT_RT is not selectable on the kernel this repository uses

**What happened.** The scope says `CONFIG_PREEMPT_RT` is selectable on
arm64 since 6.12 once `CONFIG_EXPERT` is set. `bench.cfg` has carried a comment
since Project 1 saying that `PREEMPT_RT` was being deferred to this
project. Neither said anything about the kernel version the BSP defaults
to.

**What was done.** Three files were read rather than assumed, all at
`rpi-6.12.y` and `scarthgap`:

```
kernel/Kconfig.preempt      config PREEMPT_RT
                              depends on EXPERT && ARCH_SUPPORTS_RT
arch/arm64/Kconfig:107      select ARCH_SUPPORTS_RT
meta-raspberrypi
  conf/machine/include/rpi-default-versions.inc
                            PREFERRED_VERSION_linux-raspberrypi ??= "6.6.%"
```

meta-raspberrypi's scarthgap branch ships `linux-raspberrypi_6.12.bb`
alongside 6.6 and 6.1, and defaults to 6.6. So `kas/bench-rt.yml` sets
`PREFERRED_VERSION_linux-raspberrypi = "6.12.%"` as well as the fragment
switch, and the reason is written in both files.

**Why that and not the alternative.** The alternative is the failure this
finds: a fragment containing `CONFIG_PREEMPT_RT=y` on 6.6 names a symbol
with no prompt, kconfig drops it silently, the build succeeds, and the
board boots a kernel that is not preemptible while the results table says
it is. Nothing in the build output would mention it. The other alternative,
applying the `patch-*-rt*` series to 6.6, is real work with no benefit here
when the same layer already offers a kernel with the feature in mainline.

---

## 3. The fragment names three options it does not want

**What happened.** `CONFIG_PREEMPT_RT` lives inside a kconfig `choice`, and
so does `CONFIG_NO_HZ_FULL`. Selecting one member implies the others are
off, so a minimal fragment would only need the positive lines.

**What was done.** The negative lines are there anyway:

```
# CONFIG_PREEMPT_NONE is not set
# CONFIG_PREEMPT_VOLUNTARY is not set
# CONFIG_PREEMPT is not set
CONFIG_PREEMPT_RT=y
# CONFIG_NO_HZ_IDLE is not set
CONFIG_NO_HZ_FULL=y
```

**Why that and not the alternative.** `scripts/check-kernel-config.sh`
treats `# CONFIG_X is not set` as a request and verifies it. Without those
lines a kernel that quietly fell back to `CONFIG_PREEMPT` would still pass
the check on every other line of the fragment. The negative lines cost
nothing at build time and turn the checker into something that can detect
the exact failure from entry 2.

The lockup detectors are the same argument one level deeper.
`lib/Kconfig.debug` declares `LOCKUP_DETECTOR` as a plain `bool` with no
prompt, selected by `SOFTLOCKUP_DETECTOR` and `HARDLOCKUP_DETECTOR`. The
fragment names all three: the two prompted ones are the request, and the
derived one is the consequence, which is what a future defconfig turning
one of them back on through another path would trip over.

`CONFIG_DEBUG_PREEMPT` earns its line for a different reason: it defaults
to `y` on a preemptible kernel, so leaving it alone means shipping it.

---

## 4. The image needs the spidev module named, and this repository knew that

**What happened.** `bench.cfg` builds `CONFIG_SPI_SPIDEV=m`, deliberately,
because spidev is a bring-up tool rather than part of a running system.
`core-image-minimal` installs no kernel modules at all.

**What was done.** `kernel-module-spidev` is in `bench-rt-image`'s install
list, with a comment pointing at the precedent.

**Why that and not the alternative.** The precedent is Project 1's
`brcmfmac`, which cost two rounds of debugging: the firmware was present,
the hardware was present, and `dmesg` had no line for the driver anywhere
because nobody had asked for the module package. The same failure here
would look like a HAT that enumerates in `/proc/device-tree/hat`, a
`daqhats_list_boards` that finds the board, and a scan that fails. The
alternative, making spidev built-in for this image, would change `bench.cfg`
for every project to fix one, and the whole point of an opt-in fragment is
that it does not do that.

---

## 5. Two recipes for the vendor library, not one, and not a board install

**What happened.** The usual route installs `daqhats` on the board with
`git clone && sudo ./install.sh`. A Yocto image has no compiler, no git and
no pip, so that route does not exist here.

**What was done.** Two recipes, `libdaqhats_1.5.0.1.bb` and
`python3-daqhats_1.5.0.1.bb`, both pinned to
`dc66583068372d95c87261eec8c6f9c2fd3c78bd`, the commit behind tag v1.5.0.1,
with `LIC_FILES_CHKSUM` computed from the LICENSE blob at that tag.

Reading the vendor makefile first turned out to matter. It assumes a build
on the Pi itself in three ways, and all three are wrong in a cross build:

| In `lib/makefile` | Why it breaks |
|---|---|
| `CC = gcc` | the host compiler, not the cross one |
| `-I/usr/include` | host headers ahead of the sysroot, which is the classic route to a wrong struct layout that fails at run time rather than at compile time |
| `-I/opt/vc/include -L/opt/vc/lib` | the 32-bit Broadcom userland, absent from a 64-bit image |

All three are replaced by overriding on the make command line, which beats
an assignment inside a makefile.

**Why that and not the alternative.** A patch against the vendor tree would
do the same thing and would have to be rebased at every version bump. The
command-line override is three lines that survive it. Splitting the Python
half into its own recipe avoids the other trap: `inherit setuptools3`
provides `do_compile`, and a single recipe that also has to run a makefile
ends up fighting the class that is trying to help it.

---

## 6. Two vendor tools are deliberately not installed

**What happened.** `tools/makefile` installs seven programs. Packaging all
of them looked like the polite thing to do.

**What was done.** Two are packaged, `daqhats_list_boards` and
`mcc118_firmware_update`. Two are not, and the recipe says why at length.

`daqhats_version` reads `/usr/local/lib/libdaqhats.so`, a path that exists
on Raspberry Pi OS after `install.sh` and on no Yocto image. It would print
"daqhats is not installed" next to a working library.

`daqhats_read_eeproms` caches the ID EEPROM of boards 1 to 7 into
`/etc/mcc/hats`, and needs the `dtoverlay` tool and the `at24` driver from
Raspberry Pi OS. Reading `lib/util.c` settled whether it is needed at all:

```
line 124   static const char* const SYS_HAT_DIR = "/proc/device-tree/hat";
line 766   // Boards 1-7 will be supported with the read_eeproms utility
           // that copies the EEPROM contents to /etc/mcc/hats
```

Board 0, which is the only board in this project, is read from the device
tree entry the firmware fills in at boot. The cache has nothing to add.

**Why that and not the alternative.** Shipping a tool that reports the
wrong answer is worse than shipping nothing, because somebody eventually
believes it. The alternative for `read_eeproms`, patching its paths and
pulling in `dtoverlay`, is real work to support a second HAT that this
bench does not have; if one appears, the recipe comment says what to do
instead of leaving a mystery.

---

## 7. numpy is not a dependency of the Python bindings

**What happened.** The capture script uses `a_in_scan_read_numpy`, so
`python3-daqhats` looked like it should depend on numpy.

**What was done.** It does not. `mcc118.py` imports numpy inside that one
method and nowhere else, so the ordinary read path works without it. The
image installs numpy because the capture script chooses the numpy path, and
that decision is recorded in `bench-rt-image.bb` where it belongs.

Reading that method also produced a number worth knowing: it allocates
`float64`, so a 60 s scan is 48 MB in flight. `rt-capture` casts to
`float32` on the way to disk, which is where the 24 MB figure in the
design notes comes from. The 12-bit converter over a 20 V span is 5 mV per code, so `float32`
has about five significant digits in hand.

**Why that and not the alternative.** Forcing 30 MB of numpy on every user
of a ctypes wrapper would be wrong, and it would hide the decision in a
place nobody reads. The alternative in the other direction, leaving numpy
out of the image and analysing on a laptop, means a feedback loop that runs
through an SD card reader; a bad row then costs half an hour instead of two
minutes.

---

## 8. The toggler goes real-time last

**What happened.** The reference implementation of the toggler raises
priority and locks memory first, then opens the GPIO chip.

**What was done.** Reversed. Everything that can fail, the chip, the line
request, the output file, fails first, as an ordinary process. Only then
does `set_realtime` pin the CPU, take SCHED_FIFO 80, `mlockall` and
pre-fault the stack.

**Why that and not the alternative.** A SCHED_FIFO 80 process that fails
and retries, or simply prints an error, is a process running at real-time
priority on a core it has just been pinned to. On a board where something
has already gone wrong that is how a shell stops responding. Failing before
the priority change costs nothing and removes the whole class.

Two more differences from that version, both small and both deliberate. The stack is pre-faulted with 512 kB of `memset` plus a
compiler barrier, because `mlockall(MCL_FUTURE)` keeps pages resident once
they exist and does not create the ones the stack has not grown into; the
first call deep enough to need them takes the fault inside the measured
loop. And the percentiles are read off the histogram rather than from a
sorted array, because sorting sixty thousand samples means allocating in a
program whose whole claim is that it does not allocate.

---

## 9. `_GNU_SOURCE`, found by reasoning rather than by a compiler

**What happened.** `bench-status.c` uses `#define _POSIX_C_SOURCE 200809L`
and the new program was written the same way.

**What was done.** Changed to `_GNU_SOURCE`, with the reason in a comment.
`cpu_set_t`, `CPU_SET` and `sched_setaffinity` are glibc extensions guarded
by `__USE_GNU`, so under a strict POSIX feature test they are simply not
declared.

**Why that and not the alternative.** The error that would have produced is
`unknown type name 'cpu_set_t'`, which reads like a missing header and is
not one. Ten minutes of the next person's time, written down once.

---

## 10. The affinity checker was wrong, and its own test found it

**What happened.** `rt-irq-affinity set` skipped any
`smp_affinity_list` that failed `[ -w ]`, on the theory that an unwritable
file is an interrupt that cannot be moved. The test that stands a
read-only file in for a per-CPU interrupt then failed: the script reported
three moved and named none as immovable, because it had never tried.

**What was done.** The guard became `[ -f ]`, and the write itself is the
test. On a real board every one of those files is mode 644 and the kernel
rejects the write afterwards with EIO, so `-w` would have reported success
for interrupts that never moved. That is worse than the test failure.

**Why that and not the alternative.** The same reasoning produced the
`check` subcommand's discriminator, which is the part worth keeping. Asking
"does this interrupt's affinity include the isolated core" flags every
per-CPU timer on every board, everybody learns to ignore the output, and
the day a real device interrupt lands there nobody notices. So `check`
writes an interrupt's current affinity back to itself: it changes nothing,
it goes through the same permission check, and it succeeds exactly for the
movable ones. An entry that lists the isolated core and accepts a write is
a finding; one that refuses is a per-CPU timer, counted and reported as
expected.

---

## 11. The interpolation does not do what it is usually said to do

**What happened.** The plan was to write a test for `rt-analyze` that
synthesises a square wave with known edge times and checks that the
analysis recovers them. Writing the generator forced the question of what
the samples around an edge actually look like.

**What was done.** The arithmetic, before any code:

```
frac = (thr - v[i]) / (v[i+1] - v[i])
```

A 3.3 V CMOS edge into a 10 cm jumper settles in tens of nanoseconds. The
chance that a sample lands during the transition is about 10 ns in 10 us,
one in a thousand. So for essentially every crossing `v[i]` is 0 and
`v[i+1]` is 3.3, `frac` is `(1.65 - 0) / 3.3 = 0.5` exactly, every time,
and the recovered edge time is `(i + 0.5) / fs`. The interpolation returns
a constant. The resolution is one sample period, 10 us, presented with
three decimal places.

The usual justification for the method is that the 3.3 V edge is fast
compared to the sample period. That is precisely the condition under which
it does not work.

Three things followed:

1. `rt-analyze` measures which regime it is in rather than assuming.
   `subsample_fraction` is the share of crossings whose two straddling
   samples differ by less than 80 percent of the full logic swing, meaning
   at least one was taken on the ramp. Below 0.2 the program warns on
   stderr, and the value goes into the results row as a column.
2. `docs/METHOD.md` states what survives quantisation, the mean and the
   clock offset, and what does not, the spread and the tail.
3. The fix is in the schematic as an option: 1 kohm in series and 10 nF to
   ground, about 10 us of rise time, so the edge spans two or three
   samples.

The test then asserts the difference in microseconds. The same 2.0 us of
injected jitter reads as 4.2 us through an ideal edge and 2.0 us through a
slowed one, with the generator writing out the truth for comparison.

**Why that and not the alternative.** The alternative was to implement the
usual method, get plausible-looking histograms, and publish a 99.9th
percentile that is mostly a property of the sample clock. It would have
looked fine. The acceptance criterion about the GPIO system-call cost, a
few microseconds, is not reachable at all through an unresolved edge, so
the flaw would have surfaced eventually as an unexplained disagreement
between the two instruments, which is exactly the thing this project claims
to be able to interpret.

Worth noting what made this visible: writing the test first. A test that
generates its input has to model the physics, and modelling the physics is
what showed that one term in the model was constant.

---

## 12. The generator needed two clocks before it was realistic

**What happened.** The first version of the synthetic wave used a 1000 us
toggle period and a 100 kS/s sample rate, which are exactly commensurate:
100 samples per toggle. Every edge then fell in the same place inside a
sample interval, the quantisation residual was identical for all of them,
and the ideal-edge case came out with a standard deviation of exactly zero.
The test passed for the wrong reason.

**What was done.** The generator samples on a clock 50 ppm fast, which is
an ordinary difference between two crystals. The sample grid then drifts
through the toggle grid over the run, the residual sweeps the whole
interval, and the quantisation shows up as it does on real hardware. The
same change makes the `clock_offset_ppm` column testable: it reads 50.

**Why that and not the alternative.** A generator that hides the effect the
test exists to measure is worse than no generator. The alternative,
injecting more jitter until the quantisation was visible anyway, would have
worked and would have modelled a system nobody has.

---

## 13. `rt-run` refuses rather than records

**What happened.** The orchestration as originally scoped takes the
configuration as arguments and records it in the result file name.

**What was done.** `rt-run` takes the configuration as flags and then
checks it against the kernel, in both directions:

- `-i` with an empty `/sys/devices/system/cpu/isolated` is refused, and the
  message names `isolcpus=3 nohz_full=3 rcu_nocbs=3`
- no `-i` on a kernel that *did* isolate the core is refused too
- a board already reporting `throttled` other than `0x0` is refused
- an overrun from `rt-capture` voids the run and writes no row

**Why that and not the alternative.** `isolcpus=3` in a text file is not
isolation; the kernel having accepted it is. One row labelled isolated that
was not makes the entire table unusable, and nothing in the output would
admit it. The second direction matters just as much and is easier to
forget: a run started after a reboot that still had the isolation
parameters, but without `-i`, would be recorded as the unisolated control.

The CPU list parsing is part of this. The kernel writes ranges, so a plain
comma match reads `2-3` as not containing 3 and refuses a correctly
isolated board. There is a test for exactly that.

---

## 14. Three shell traps, all of them already paid for once

**What happened.** Writing four shell programs reintroduced patterns this
repository has already been burned by.

**What was done.**

`[ -r "$CONF" ] && . "$CONF"` became an explicit `if`. Under `set -e` an
and-list whose test fails returns non-zero as a whole and ends the script,
silently, at the top, before anything has printed.

`[ "$x" = yes ] && label="${label}-iso"` became an `if` for the same reason,
and because shellcheck rejects `A && B || C` as SC2015. Thirteen CI
failures in Project 1 were that one warning.

`ls "$deploy"/modules-*.tgz | tail -1` became a glob loop. Parsing `ls` is
SC2012 and breaks on a space in a path; this repository replaced the same
pattern with `stat` and `test -e` once already.

**Why that and not the alternative.** None of these is a matter of taste.
Each has a failure mode that is silent, and each was found by remembering
rather than by a tool, because the tool that would have found them,
shellcheck, is not installed on the machine this was written on.

---

## 15. The linter rejected a correct recipe

**What happened.** `python3 scripts/lint.py` failed on both new daqhats
recipes:

```
SRC_URI names LICENSE;md5=14d452bb31a1ae3c2fb70163065ffbc8,
which is not in files/
```

**What was done.** The check scans for `file://` and had never met a recipe
that fetches its own source, where `LIC_FILES_CHKSUM` is
`file://LICENSE;md5=...`, a path inside the fetched tree rather than a file
this layer ships. Every earlier recipe uses
`file://${COMMON_LICENSE_DIR}/MIT;...`, which starts with a variable and is
skipped. The fix removes the `LIC_FILES_CHKSUM` assignment before scanning,
matched on the variable name so it stays exact.

**Why that and not the alternative.** The alternative is an exception list
of filenames, which grows, or writing the recipes to suit the linter, which
is backwards. The check is still worth having: it is the thing that catches
a file added to `files/` and forgotten in `SRC_URI`, which is a real
mistake and a confusing one.

---

## 16. What was run, and what it proves

**What happened.** None of this can be built here: no Yocto host, no board,
no HAT. The question was what can honestly be checked anyway.

**What was done.** Three test suites, run locally:

| Suite | Assertions | What it covers |
|---|---|---|
| `tests/rt-irq-affinity-test.sh` | 14 | A fake `/proc/irq` tree; movable against kernel-owned, ranges, the failure case |
| `tests/rt-run-test.sh` | 51 | Nine stub commands and a fake `/sys`; ordering, confinement, both isolation refusals, the throttle gate, an overrun, and every column of the row |
| `tests/rt-analyze-test.sh` | 21 | A synthesised waveform with known edges, both edge regimes, the clock offset, a late edge, the empty capture |

Plus `python scripts/lint.py` clean, `sh -n` on every new shell file, and
`scripts/check-kernel-config.sh -f rt` exercised against a synthetic
`.config` in both directions: one satisfying both fragments, and one with
`CONFIG_PREEMPT_RT` replaced by `CONFIG_PREEMPT`, which it correctly
rejects with two mismatches.

**Why that and not the alternative.** The alternative is to write the code,
say it is finished, and find out on the board. Project 1 established what
that costs: seventeen CI failures, three sequential causes for one missing
network interface, and two days of not reading CI results. The suites above
took an hour and they run in under three seconds.

What none of it proves is any latency number. The project README says so in
its first section rather than at the bottom.

---

## 17. What is deliberately not done

- **No systemd unit anywhere in `bench-rt`.** Every other bench recipe has
  one. These are laboratory instruments, started by hand, one configuration
  at a time, with a person watching. A timer running the matrix unattended
  would produce rows nobody could attach a thermal state or a jumper
  position to.
- **No plotting.** The histograms are text files with two columns. Whatever
  plots them belongs on the host, and what is asked for is a
  logarithmic count axis, which is one gnuplot line.
- **No second GPIO for the threaded-IRQ experiment.** It is a stretch goal
  for later and it needs an input line, a source of edges and `gpiomon`.
  Project 9 is the tracing project and is the right home for the follow-up
  question, which is not "how late was it" but "what made it late".
- **No `force_turbo=1` anywhere in the repository.** It is in the bring-up
  notes as a manual step for two rows, with what it costs stated: the ARM
  clock pinned at turbo, a hotter board, and the warranty bit set
  permanently. Putting it in a kas file would make it the default for
  anybody who built this image.

---

## 18. Project 15 met hardware, and its first defect was ours too

**What happened.** Project 15 reached a board on 15 September and found
three defects that no amount of testing without hardware had produced. The
first one was not about modems at all: `router.cfg` asked for
`CONFIG_NFT_CHAIN_NAT`, `CONFIG_NFT_RT` and `CONFIG_NFT_EXTHDR`, and none
of the three is a Kconfig symbol. `nft_rt.o` and `nft_exthdr.o` are objects
inside `nf_tables-objs`, and `nft_chain_nat.o` arrives with `NFT_NAT`.
`./go kconfig` caught them, on the first build in fourteen projects that
compiled a kernel rather than taking one from shared state.

That is the same class of defect `rt.cfg` could carry, and this project has
never had a kernel compiled at all.

**What was done.** Every symbol in `rt.cfg` and `bench.cfg` was checked
against the actual `rpi-6.12.y` tree, before any build. Two things are
needed for a fragment line to do anything: the symbol has to exist, and it
has to have a prompt, because kconfig will not let a fragment set a symbol
that is chosen by whatever selects it.

`bench.cfg` came out clean, fifteen symbols. `rt.cfg` had one:

```
kernel/irq/Kconfig:116   config IRQ_FORCED_THREADING
                           bool                     <- no prompt
arch/arm64/Kconfig:251     select IRQ_FORCED_THREADING
```

So `CONFIG_IRQ_FORCED_THREADING=y` in the fragment does nothing, and arm64
selects the symbol unconditionally, so the built kernel has it anyway.

**Why that and not the alternative.** The obvious fix is to delete the
line. It stayed, marked as a consequence rather than a request, because the
check it enables is still worth making: an arm64 that stopped selecting it
would take the `threadirqs` comparison row away and nothing else in this
repository would notice.

The important part is what the outcome would have looked like without this.
The line is inert, the value is right anyway, and `./go kconfig` would have
printed `ok CONFIG_IRQ_FORCED_THREADING=y` after the build. A check passing
for the wrong reason is worse than one failing, because it is evidence that
is not evidence, and there is no later step that catches it.

---

## 19. A check that runs before the build, because the other one cannot

**What happened.** `./go kconfig` compares a fragment against a `.config`,
and a `.config` exists only after `do_compile`. So the earliest moment a
bad symbol can be found is at the end of a build, which is what Project 15
paid for. The kernel source, though, is on disk after `do_unpack`, minutes
in rather than hours.

**What was done.** `scripts/check-kernel-symbols.sh`, wired up as
`./go ksym`. It indexes every `config` and `menuconfig` declaration in the
tree in one pass, then for each fragment line asks two questions:

| Verdict | Meaning |
|---|---|
| `MISSING` | not declared anywhere, so the line can never do anything |
| `PROMPTLESS` | declared, but a fragment cannot set it |
| `consequence` | promptless and the fragment says so, with the selector printed |

A promptless symbol is allowed only with a marker directly above it:

```
# consequence: promptless, selected by arch/arm64/Kconfig
CONFIG_IRQ_FORCED_THREADING=y
```

and the script prints what actually selects the symbol, so the claim in the
comment can be checked rather than believed.

Run against `router.cfg` as it was before the board corrected it, all three
defects are reported. That is the check validated against a known answer
rather than against an opinion.

**Why that and not the alternative.** The alternative is to keep relying on
`./go kconfig`, which does work, at the price of a build cycle per defect.
Two checks in sequence answer two different questions, and both are worth
asking: `ksym` asks whether the line is a request the kernel can receive,
`kconfig` asks whether the answer came back. Neither substitutes for the
other, and the cheap one now runs first.

---

## 20. The checker was wrong twice, and its own test found both

**What happened.** Writing the test before trusting the script paid for
itself immediately.

**What was done.** The first run reported 22 of 25 assertions passing, and
the three failures all pointed at the same place: the branch that reports a
missing symbol printed nothing at all. Under `set -e`, a `grep` that
matches nothing returns 1 and takes the script with it, so the lookup that
established a symbol was missing killed the process that was about to say
so. A checker that exits silently is worse than no checker, because the
absence of output reads as success.

The second was found by pointing the script at real netfilter text rather
than at the synthetic tree. `CONFIG_NF_CONNTRACK_TIMESTAMP` came back
`PROMPTLESS`, which it is not:

```
net/netfilter/Kconfig:178       bool  'Connection tracking timestamping'
```

Kconfig accepts either quote character, and that one file uses single
quotes eighty-one times. A check that only knew double quotes would have
called eighty-one ordinary settable symbols promptless, in one file, and
the natural response to a wall of false failures is to stop running the
check.

Both shapes are now in the test tree, and a third case was added for the
other way this can mislead: a partial kernel tree makes real symbols look
missing, so when anything is reported missing and the tree declares fewer
than five thousand symbols, the script says the tree is the likely problem
rather than leaving a wall of MISSING lines to be read as a broken
fragment.

**Why that and not the alternative.** The alternative was to write the
script, run it once against `rt.cfg`, see a plausible answer, and ship it.
It would have given a plausible answer: `rt.cfg` has no netfilter symbols
and no missing ones, so neither bug would have shown. The defects were
found because the test generates inputs the fragment does not contain, and
because the second input was real kernel text rather than a synthetic
imitation of it.

---

## 21. The central claim of this project was wrong, and simulation showed it

**What happened.** Acceptance criteria 3 and 5 both compare the two
instruments, and nothing in the repository compared them: three histograms
are written per run and `rt-run` extracted a maximum from one of them.
Writing that tool meant deciding what the comparison should say, which
meant doing algebra that nobody had done.

Entry 1 of this journal, DESIGN.md, METHOD.md, the results notes and the
project README all said the same thing: the external instrument sees the
wake-up latency plus the cost of the GPIO write, so the difference between
the instruments is that cost. It is the intuitive reading and it is wrong.

The instrument does not measure when an edge happened. It measures the
interval between two of them:

```
  edge_i = i*T + L_i + S_i
  P_i    = T + (L_i+1 - L_i) + (S_i+1 - S_i)
```

A constant `S` is in both edges and subtracts out. The wire cannot see the
cost of the GPIO write at all.

**What was done.** The algebra was checked against a simulation before a
line of it went into a document. 120000 periods, a one-sided latency
distribution, and a deliberately large constant write cost of 6 us:

```
constant S             int: sd 2.83 | ext: mean 2000.000 sd 4.00 max 87.21
S with 1.5 us jitter   int: sd 2.83 | ext: mean 2000.000 sd 4.53 max 87.59

prediction sd_ext = sqrt(2) * sd_int = 4.01
prediction mean_ext = T exactly      = 2000.0   (S does not appear)
```

The mean is 2000.000 in both rows. Six microseconds of constant write cost
produced no effect anywhere. Adding 1.5 us of jitter to it moved the spread
from 4.00 to 4.53, which is `sqrt(4.00^2 + 2*1.5^2)` to three digits.

So the relationships that hold are:

| Quantity | Value |
|---|---|
| mean period | exactly `T`, whatever the write costs |
| spread | `sqrt(2)` times the internal spread, for independent latencies |
| in general | `var(ext) = 2 var(int) + 2 var(write path)` |
| maximum | tracks the largest latency above its mean |

`rt-compare` implements that, `rt-run` calls it at the end of every run,
and the five documents that stated the old claim now state the new one and
say they were corrected. Entry 1 above carries a pointer here.

**Why that and not the alternative.** The alternative was to build the lab,
run sixteen configurations, and report a column called "system call cost"
computed as `ext_max - int_max`. It would have produced numbers. They would
have been differences between two maxima of two differently-shaped
distributions, varying run to run for reasons having nothing to do with
system calls, and the whole point of the second instrument would have been
a number nobody could defend.

The correction also makes the project's claim smaller and better. The wire
does not tell you what a GPIO write costs. It tells you whether that cost
is *steady*, which is the property a control loop actually depends on, and
which no instrument inside the kernel can report.

---

## 22. Two more things the comparison got wrong before its test passed

**What happened.** `tests/rt-compare-test.sh` builds a run from a known
latency series and checks that the tool recovers what went in. Two
assertions failed on the first run and both were the tool, not the test.

**What was done.**

*Binning inflates a variance.* The simulation put a perfectly constant
write cost in, so the reported write-path variation should have been zero.
It was 0.305 us. Binning spreads every value uniformly across its bin and
adds `width^2/12` to the variance whatever the distribution is, and the
external histogram has 2 us bins, so it carried 0.33 of variance that was
not in the signal. The excess-over-sqrt(2) calculation is a difference of
two variances, which turned that into a third of a microsecond of invented
finding. Sheppard's correction subtracts `width^2/12` from each variance
and the figure fell to 0.099 us, at which point the same test recovered an
injected 2.0 us of write jitter as 2.02 us.

*A low ratio is not a small write cost.* The test asserted that a run with
a constant write cost would print the "ratio below sqrt(2)" explanation,
and it printed the other branch, because the ratio came out at 1.422. The
test was wrong to expect it: with independent latencies the ratio sits at
sqrt(2) and lands either side of it by chance. The case that genuinely
produces a low ratio is correlated latencies, which is what load does, so
the generator grew an AR(1) mode. At `rho = 0.7` the ratio is
`sqrt(2(1 - rho)) = 0.775` exactly, and the tool reports 0.779 and refuses
to compute a write-path figure from it.

**Why that and not the alternative.** Both corrections point the same way.
A tool that reports a third of a microsecond of write-path variation for a
system that has none, or that interprets a burst of correlated wake-ups as
a cheap GPIO write, produces numbers that look like measurements. The
alternative to finding this in a test was finding it in a results table,
where a plausible number is indistinguishable from a real one.

---

## 23. The new check looked for the kernel where BitBake does not put it

**What happened.** `./go ksym` was about to be run on the build host for the
first time. Its autodetect searched `tmp/work` for a directory whose path
contained `linux-raspberrypi` and whose name began with `linux-`. That was
written from an idea of where a recipe's source lands, not from reading
anything.

**What was done.** Read it instead:

```
kernel.bbclass:26     S = "${STAGING_KERNEL_DIR}"
bitbake.conf:481      STAGING_KERNEL_DIR =
                        "${TMPDIR}/work-shared/${MACHINE}/kernel-source"
```

The kernel is unpacked once per machine into a shared tree, not once per
recipe, so that the kernel and its modules build against the same sources.
Only an alternate kernel recipe, one whose `KERNEL_PACKAGE_NAME` is not
`kernel`, gets a `kernel-source` under its own `WORKDIR`.

The search now looks for the directory name under both locations, and three
test cases cover it: the shared tree, the per-recipe one, and an unbuilt
tree, which has to be an error rather than an empty pass.

**Why that and not the alternative.** The failure would not have looked
like a bug in the checker. It would have printed "no unpacked kernel source
found" on a build host where the kernel had just been unpacked
successfully, and the obvious reading of that is that the unpack failed.
The next half hour goes into BitBake rather than into the sixteen-line
function that was wrong.

Worth noting what prompted it: a question about which build target to run
next, not a test failure. The check had passed its own suite thirty-three
times by then, because every one of those cases passed the tree in
explicitly and none exercised the branch that goes looking for it. A test
suite that only exercises the arguments you remember to pass is a suite
with a hole in exactly the shape of the thing you assumed.

---

## 24. The first build went to the wrong directory, and stopped one task short

**What happened.** The bring-up notes said to unpack the kernel with

```
kas shell kas/bench-rt.yml -c 'bitbake -c unpack virtual/kernel'
```

It ran, reported three tasks and all succeeded, and produced nothing this
project could use. Two independent mistakes in one line.

*Wrong directory.* Every build directory in this repository is decided by
`scripts/common.sh`, which exports `KAS_WORK_DIR` and `KAS_BUILD_DIR`
pointing at `$BENCH_WORK`. A bare `kas shell` inherits neither, and kas
falls back to paths relative to the current directory. So it built in the
checkout: `~/src/embedded-linux-bench/build`, with its own `downloads` and
`sstate-cache`, 7.7 GB of it, on a machine with 35 GB of headroom. It did
not fail. It produced a correct result in a place nothing else looks, and
the next command read the previous project's kernel from `~/bench` and
reported 6.6 where 6.12 was expected. Ten minutes went into suspecting the
version pin, which was correct all along.

The tell was in the log and was not read at the time: BitBake printed
`Loaded 4389 entries from dependency cache` and no `Parsing recipes` bar. A
changed `local.conf` forces a full reparse, so an unchanged one meant kas
had written its configuration somewhere else entirely.

*Wrong task.* `do_unpack` puts the git tree in `${WORKDIR}/git`, and its
`cleandirs` empties `STAGING_KERNEL_DIR` on the way past. What fills that
directory is `do_kernel_checkout`, a separate task from
`kernel-yocto.bbclass`. So `kernel-source` existed, empty, and `./go ksym`
would have had nothing to read.

**What was done.** `scripts/kas.sh`, with `./go shell [CONFIG]` and
`./go bitbake CONFIG ARGS`. Everything that invokes kas goes through one
place that sets the build directory, and `warn_stray_build_tree` in
`common.sh` reports a `build/` inside the checkout rather than letting a
correct build happen in the wrong place again. Sixteen assertions in
`tests/kas-run-test.sh`, including that the two variables reach kas.

The bring-up step became `kernel_configme` rather than `unpack`, which is
worth more than the correction: it runs fetch, checkout and patch, and then
merges the fragments into a real `.config`. So `./go kconfig -f rt`, which
the acceptance table had as needing a full build, now runs in minutes,
before the compile.

**Why that and not the alternative.** The alternative was to tell the
operator to export two variables by hand, which is what I had effectively
done by writing a raw `kas shell` into a document. A command that has to be
run correctly by memory is a command that will be run wrongly, and this one
fails by succeeding.

**A correction to what entry 19 claims.** It says `./go ksym` catches a
fragment line the kernel cannot honour. It catches a line that names no
symbol; it does not catch a symbol whose dependencies are unmet.
`CONFIG_PREEMPT_RT` is declared with a prompt in 6.6 and 6.12 alike, and
what 6.6 lacks on arm64 is `ARCH_SUPPORTS_RT`. On a 6.6 tree `ksym` prints
`ok CONFIG_PREEMPT_RT` and tells you nothing, so it could never have caught
the failure it was partly written for. That is why the bring-up notes now
read the kernel's own Makefile as a separate step and run `./go kconfig`
before the build rather than after it.

---

## 25. The kernel check read the wrong kernel, and said so in a line nobody reads

**What happened.** With 6.12.93 unpacked, the version pin confirmed by the
kernel's own Makefile, and `./go ksym -f rt` reporting all 31 symbols real,
`./go kconfig -f rt` returned six mismatches including the one that
matters:

```
MISMATCH  CONFIG_PREEMPT_RT=y   (built: not set)
MISMATCH  CONFIG_NO_HZ_FULL=y   (built: not set)
```

The obvious reading is that the fragment failed. It had not. Two lines
above the verdict:

```
--- config   .../linux-raspberrypi/6.6.63+git/...-build/.config
--- built    2026-09-15 17:56
```

It was checking yesterday's 6.6 kernel, from before this project existed.

**What was done.** The search ended in `sort | tail -1` over the paths.
That is a version sort done lexically, and kernel versions defeat it:

```
linux-raspberrypi/6.12.93+git/...   sorts first
linux-raspberrypi/6.6.63+git/...    sorts last, because "6" > "1"
```

So the newest kernel sorted first and the oldest won. Ranking by
modification time instead cannot get this wrong, and unlike the mtime
*filter* that was removed from this script earlier it never excludes
everything: there is always a newest.

`tests/kernel-config-test.sh`, thirteen assertions, builds two trees named
so that a lexical sort picks the wrong one and checks that the newer is
used. Then it reverses their timestamps and checks that the verdict
reverses too, because a check that cannot fail is not a check.

**Why that and not the alternative.** The alternative was to parse the
version out of the path and compare numerically, which is a version
comparator nobody needs: the question is never "which kernel is newest" but
"which build just ran".

The line that saved this was `--- built 2026-09-15 17:56`, added to the
script by someone in passing so a check passing against a week-old tree
would be visible rather than implied. It was the only thing in the output
that contradicted the verdict. Worth remembering when deciding whether a
diagnostic line earns its place: this one cost two minutes to write and
turned an hour of hunting a phantom kernel-configuration bug into reading
one line.

---

## 26. The vendor library built, its tools did not

**What happened.** The first `./go rt` failed in `libdaqhats do_compile`,
and it failed in the half I had said to watch:

```
daqhats_list_boards.c:3:10: fatal error: daqhats/daqhats.h:
                            No such file or directory
    3 | #include <daqhats/daqhats.h>
```

The library itself was fine. It compiled twelve objects with the cross
compiler, selected `gpio_v2.c` from `pkg-config --modversion libgpiod`
reporting 2.1.3 in the target sysroot, and linked
`libdaqhats.so.1.5.0.1` with `-Wl,-z,defs` satisfied. The three overrides
of the vendor makefile all worked.

The tools are built from the same tree and include their headers with a
directory prefix that the tree does not have. The headers live flat in
`include/`; the tools ask for `<daqhats/daqhats.h>`. That prefix exists
only after the vendor's own `make install` has copied them into
`/usr/local/include/daqhats`, because natively you build the library,
install it, then build the tools against what was installed.
`-I${S}/include` cannot substitute: the compiler is looking for a
`daqhats/` directory, not for the files inside it.

**What was done.** Stage the same shape under `WORKDIR` before the tools
are built, two lines, and add it to their include path:

```
install -d ${WORKDIR}/staged-include/daqhats
install -m 0644 ${S}/include/*.h ${WORKDIR}/staged-include/daqhats/
```

**Why that and not the alternative.** A patch against the vendor tree
would rewrite eleven include lines to fix something that is not broken
upstream, and would need rebasing at every version bump. Installing the
headers into the recipe sysroot first and splitting the tools into a second
recipe would also work and is three times the machinery for two programs.

**What this says about the earlier claim.** Entry 5 recorded that reading
the vendor makefile had found three assumptions about a native build, and
that overriding them on the make command line handled it. Three were found;
there were four. The fourth is not in the makefile at all, it is in the
include lines of the C, and reading a makefile was never going to show it.
The honest version is that reading the build system finds what the build
system says, and only building finds the rest. That is why the build itself
was still listed as unproven in the README rather than implied by the care
taken over the recipe.

**On not interrupting.** BitBake had already stopped scheduling and was
draining four running tasks, one of them the 6.12 kernel `do_compile` eight
minutes in. Letting it finish writes that stamp; a Ctrl-C would have thrown
the kernel compile away and charged for it again on the next run.

**The same omission, one step further on.** With the headers staged, the
next run compiled both tools and failed at the link:

```
ld: cannot find -ldaqhats: No such file or directory
```

`-ldaqhats` makes the linker look for a file named exactly
`libdaqhats.so`. The build produces `libdaqhats.so.1.5.0.1`. The
unversioned name comes from the same vendor install step as the headers:

```
install:
        @cd ../include; make install; cd ../lib      <- the headers
        @install $(BUILD_DIR)/$(TARGET_LIB) $(INSTALL_DIR)
        @ldconfig
        @ln -frs .../$(TARGET_LIB) .../lib$(NAME).so <- the link name
```

That target does three things a cross build has to do for itself, and the
first fix replicated one of them. The second fix adds the symlink.

Reading the two tools settled that there is no third: `daqhats_list_boards.c`
includes `<daqhats/daqhats.h>`, which needs the staged prefix, while
`mcc118_firmware_update.c` includes `"daqhats.h"` and `"mcc118_update.h"`,
which need the flat `include/` and `lib/` directories that were already on
the command line. Both compiled; only the link was missing.

The lesson is not about this library. A vendor `install` target is a list
of the things a build leaves undone, and a cross build has to do all of
them or none. Reading it once and extracting one item is how this cost two
build cycles instead of none.

---

## 27. Two red CI runs, one finding, and a check that could not have caught it

**What happened.** Runs on `5265a88` and `e410bce` both failed. Not the
recipes, not the tests: shellcheck, four times, all the same shape.

```
In tests/kas-run-test.sh line 31:
export BENCH_TEST_DIR=$WORK
                      ^---^ SC2086 (info): Double quote to prevent
                            globbing and word splitting.
```

Two in `tests/kas-run-test.sh`, two in `tests/kernel-config-test.sh`. CI
runs `shellcheck -s sh -e SC1090,SC1091` at default severity, where an
`info` fails the build exactly as an error does.

**What was done.** Quoted all four. A repo-wide scan for the same pattern
found no others.

Then the part that matters more than the fix. This is the *second* time
this exact pattern has gone to CI: the `rt-*` tests had it, somebody else
corrected them, and I wrote it again in two new files a day later. The
reason is structural rather than careless. The authoring laptop has no
shellcheck, so nothing between writing the line and pushing it can see
SC2086, and both times I asked for shellcheck to be run and both times the
build was more interesting.

So `scripts/lint.py` gained one narrow rule: an `export` or `readonly`
whose value contains an unquoted expansion. An assignment on its own is not
subject to word splitting; an argument to a command is, which is the whole
of SC2086 and the only part of it this repository keeps getting wrong.

It was proven by reintroducing the defect in both file shapes, because the
discovery has to match CI's:

```
tests/kas-run-test.sh: line 31: export with an unquoted expansion
meta-bench/recipes-bench/bench-rt/files/rt-run: line 412: ...
```

The second is the important one. `rt-run` has a shebang and no extension,
so a `*.sh` glob misses it and CI's own discovery does not. The rule reads
37 files, the same set the runner does.

**Why that and not the alternative.** Reimplementing shellcheck in Python
would be foolish. One rule for the one finding that the authoring machine
structurally cannot see is not: the alternative is asking a person to
remember, twice already unsuccessfully, and discovering it in an email
after a push.

**What it does not fix.** Everything else shellcheck finds is still
invisible here until CI runs. The general answer is to install shellcheck
on the Windows machine or to stop pushing from it, and neither is a
decision for a lint rule to make.
