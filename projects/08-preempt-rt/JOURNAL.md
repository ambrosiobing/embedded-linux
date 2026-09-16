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

---

## 28. The image builds, and the fourth vendor assumption was in the debug info

**What happened.** With the unversioned library name in place, `./go rt`
completed: 6258 tasks, 334 of them run, all succeeded, 11 min 44 s, and

```
bench-rt-image-raspberrypi4-64.rootfs-20260916061119.wic.bz2   78M
```

Four things that had never executed all worked first time: `do_install`
for the vendor library, the `${PN}-tools` package split, `python3-daqhats`
through `setuptools3`, and the image assembly, which is where a missing
`RDEPENDS` would have shown up. `python3-ctypes` was reasoned about rather
than tested and turned out right.

One QA warning, and it was the staging directory from entry 26:

```
QA Issue: File /usr/bin/.debug/daqhats_list_boards in package
          libdaqhats-dbg contains reference to TMPDIR [buildpaths]
```

**What was done.** Moved the staged headers from `${WORKDIR}/staged-include`
to `${S}/staged-include`, one path.

OE rewrites build paths out of debug information with prefix maps, and it
has exactly three: `${S}`, `recipe-sysroot` and `recipe-sysroot-native`. A
directory under `WORKDIR` but outside all three is covered by none of them,
so the compiler command line that GCC records in the debug info kept an
absolute path from this machine. Staging inside `${S}` puts it under a map
that already exists.

**Why that and not the alternative.** The alternative is a fourth
prefix-map argument of my own, which works and adds a thing to keep in step
with OE's. Using the map that is already there is one path change.

**Why fix a warning at all.** Because of what it means rather than what it
says. A shipped package carrying the builder's absolute paths is not
byte-for-byte reproducible, and Project 1 has an acceptance criterion about
reproducibility that this would quietly have broken for anyone who ran
`./go reproduce` on this image.

**The count, for the record.** Entry 5 said reading the vendor makefile
found three assumptions about a native build. Entry 26 found a fourth, in
the C rather than the makefile. This is a fifth, and it is in neither: it
is in what the compiler writes into the binary. Three build cycles, each
one step further, is what cross-compiling somebody else's build system
actually costs, and it is the honest answer to how much a carefully written
recipe proves before it has run. It proves nothing. It only fails faster.

---

## 29. The control and the variable differ in two things, not one

**What happened.** With the image built and the kernel configuration
proven, the next step was the matrix. Reading the two kas files together
before flashing anything:

```
kas/bench-rpi4.yml   no PREFERRED_VERSION      ->  6.6.63, PREEMPT
kas/bench-rt.yml     6.12.%  + BENCH_RT_KERNEL ->  6.12.93, PREEMPT_RT
```

So the "generic" row and the "rt" row would differ in the preemption model
**and** in six minor kernel versions of scheduler, timer and driver work.
Any difference between their histograms is attributable to either, and
nothing in the data separates them.

This project's own README says the two images "differ in the preemption
model and in nothing else that anyone had to think about". That sentence
was written on the first day, before the version pin existed, and the pin
made it false without anyone editing it.

`docs/BRINGUP.md` carried the same fault more plainly: step 1 said to flash
`bench-rt-image` and boot it "before installing the RT kernel. It carries
the generic BSP kernel." It does not and never did. `BENCH_RT_KERNEL = "1"`
is in the kas file, so that image always carries the real-time kernel.

**What was done.** Recorded, and the matrix stopped until it is fixed. The
fix is a third configuration that pins 6.12 and leaves `BENCH_RT_KERNEL` at
0, so the control and the variable differ in exactly one symbol. That is
also what makes `scripts/rt-kernel-install.sh` honest: two kernels of the
same version on one card, chosen by one line of `config.txt`.

**Why that and not the alternative.** The alternative is to measure what
exists and describe the row as "6.6 generic against 6.12 RT". It would
produce sixteen rows of real numbers, and the headline comparison would be
uninterpretable: PREEMPT_RT is the loudest change between those kernels but
it is not the only one, and a reader entitled to ask "how much of this is
the preemption model" would have no answer.

The other alternative, dropping the version pin and applying the
out-of-tree patch series to 6.6, gets one kernel version and costs a
rebase treadmill, for a comparison this way round already gives.

**The pattern worth naming.** Both faults are the same shape as the ones in
entries 21 and 25: a claim written when it was true, left standing after
the thing it described changed. The algebra claim survived four documents.
The "differ in nothing else" claim survived a kernel version pin added
three entries later, in the same file, by the same hand. Neither was caught
by a test, because neither is the sort of thing a test can hold.

What did catch this one was reading the two kas files side by side while
deciding what to flash, which is the same move that found the promptless
symbol and the wrong `.config`: comparing the thing against the claim
rather than against its own output.

---

## 30. What the image actually contains, and one thing nobody asked for

**What happened.** `./go packages` against the built image, 185 packages.
Every package reasoned about in the recipes is present:

```
kernel-6.12.93-v8            the pinned kernel, not the BSP default
kernel-module-spidev         the module core-image-minimal would omit
libdaqhats1, libdaqhats-tools, python3-daqhats
python3-numpy, python3-ctypes
rt-tests, stress-ng, util-linux-taskset
bench-rt, libgpiod3, libgpiod-tools
userland                     so vcgencmd exists for the throttle gate
```

`python3-ctypes` is worth singling out. The recipe names it because
`hats.py` calls `cdll.LoadLibrary` and the OE python split puts ctypes in
its own package; that was reasoned from reading the source rather than
tested, and the manifest confirms it. Leaving it implicit would have given
an image that boots and a capture script that dies on its first import.

**The thing nobody asked for.** Also in the list:

```
mesa-megadriver  libgallium  libegl-mesa  libgbm1  libdrm2  wayland
libx11-xcb1  libxau6  libxdmcp6  libxshmfence1  and five more libxcb*
```

Sixteen packages of graphics stack in an image whose entire purpose is to
toggle a pin on an isolated core and read a voltage. Nothing in
`bench-rt-image` asks for them.

**What was done.** Recorded as an open question rather than guessed at. The
likely source is `userland`, which this recipe added as an `RRECOMMENDS`
for one binary, `vcgencmd`, and which carries the Raspberry Pi GL
libraries. If that is where it comes from, the honest options are to drop
`vcgencmd` and record the throttle columns as unknown, to find a lighter
provider, or to keep it and justify the size in writing.

Answering it needs the build's own evidence rather than an opinion:

```
buildhistory/images/raspberrypi4-64/glibc/bench-rt-image/
    installed-package-sizes.txt
    depends.dot
```

and the one query that settles it:

```
grep -E '\-> "(mesa-megadriver|libgallium|wayland)"' depends.dot | sort -u
```

**Why not just remove it.** Because "probably userland" is a guess, and
this repository has a costed lesson about exactly that: one word of
`DISTRO_FEATURES` added on a guess about NetworkManager cost 50 MB of a
237 MB rootfs, and the chain was only visible in `depends.dot`. A package
list is not a dependency graph, and the difference is what makes the answer
checkable.

---

## 31. vcgencmd costs sixteen packages, and the answer was one line

**What happened.** Entry 30 recorded a graphics stack in a headless latency
lab as an open question with the query that would settle it. It settled it:

```
buildhistory/packages/cortexa72-poky-linux/userland/userland/latest
RDEPENDS = bash glibc (>= 2.39+git0+be1e627cd7) libegl-mesa
PKGSIZE  = 942691
```

`userland` hard-depends on `libegl-mesa`, and that pulls
`mesa-megadriver`, `libgallium`, `libgbm`, `libdrm2`, `wayland` and nine
X libraries behind it. This recipe asked for `userland` as an
`RRECOMMENDS` to get one binary, `vcgencmd`, for the throttle gate.

The path in entry 30 was also wrong, `raspberrypi4-64` where buildhistory
writes `raspberrypi4_64`. Written from the skill notes rather than from the
tree, which is the same class of mistake as reading a makefile instead of
building it.

Then the size, from the same buildhistory:

```
484 KiB wayland      387 libegl-mesa   195 mesa-megadriver
194 libxcb1          132 libgbm1       130 libxcb-randr0
130 libdrm2          and nine more at 66 KiB each
```

2.2 MiB of graphics, plus `userland` itself at 920 KiB. **3.1 MiB in
total.**

**What was done.** Recorded, and deliberately not fixed yet. Nothing in
that stack runs, nothing links against it at runtime, and it cannot affect
a latency measurement. It is image size and tidiness, and changing it now
means rebuilding an image that is about to be flashed for bring-up, where
the question is whether the HAT enumerates rather than how large the rootfs
is.

**The number is the point of this entry.** "Sixteen packages of graphics
stack in a headless latency lab" is how it was written in entry 30, and it
reads like a problem. Measured, it is 3.1 MiB of a rootfs that carries a
Python interpreter and numpy. The comparison worth making is with the
`polkit` finding from Project 15, which sounded identical and was 50 MB of
a 237 MB rootfs. Same shape of discovery, two orders of magnitude apart in
consequence, and the only way to tell them apart was to look at
`installed-package-sizes.txt` rather than at a package count.

A package list tells you what is there. It does not tell you what it
costs, and reasoning about cost from a count is how a 3 MiB tidiness item
gets treated like a 50 MB defect.

**What the fix will be.** `/sys/class/thermal/thermal_zone0/temp` and
`/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` need nothing
installed and are arguably the better instrument: a clock that drops
mid-run is the thing that corrupts a measurement, and `get_throttled`
reports a latched bitmask rather than the current frequency.

What would be lost is the latched under-voltage bit, which catches a
marginal supply that never shows up as heat. That is worth keeping in some
form, and `dmesg` carries it, so the replacement should read both rather
than quietly measuring less.

**Why not now.** Because the ordering is: prove the hardware, then tidy the
image. A 16-package graphics stack in a build nobody has booted is a worse
thing to spend a build cycle on than finding out whether the MCC 118
answers at all.

---

## 32. The board is the one the HAT fits

**What happened.** With the image built for `raspberrypi4-64` and about to
be flashed, the HAT was stacked on a Pi 3 and fitted.

**Correction, written the same day.** The sentence that stood here said the
HAT "did not seat on a Pi 4", with an explanation about the Pi 4 having
moved its Ethernet and USB stacks. Nobody observed that. What was observed
was that the HAT fits a Pi 3; the rest was inferred, written as though it
had been seen, and committed. Told afterwards that the HAT seats on a 4B
and a 3B+ and not on a plain 3, which contradicts it.

What is actually known: the HAT is on a Pi 3 class board, and
`raspberrypi3-64` covers both the 3B and the 3B+, so the machine line is
correct either way. Why the Pi 4 was not used is **not** settled and no
longer claimed here. See entry 33.

**What was done.** `kas/bench-rt.yml` sets `machine: raspberrypi3-64`, and
the board changed in the project README, the three figures in DESIGN.md,
the bring-up notes and the repository's front-page table.

The change is smaller than it sounds, and that is worth recording rather
than assuming:

| Concern | Why it does not move |
|---|---|
| `ARCH_SUPPORTS_RT` | a property of arm64, and both boards are arm64 |
| `isolcpus=3` | both are quad-core |
| the wiring table | header positions, not board properties |
| `rt-toggle` | opens `/dev/gpiochip0` by path and never matches an SoC label |

The `pinctrl-bcm2711` string that would have needed changing belongs to
Projects 1 and 15, whose GPIO code looks the chip up by label. Project 8's
does not, and that was a deliberate choice made for a different reason,
which happened to make this a one-line change.

**What does move is the numbers.** A Cortex-A53 at 1.4 GHz with Ethernet
and USB on one shared controller is a harder real-time target than a
Cortex-A72, and its thermal limit is lower, so the throttle gate will fire
sooner under `stress-ng`.

**Why the thresholds were not relaxed.** The acceptance table says a 99.9th
percentile below 50 us and a maximum below 150 us. Those were written for a
Pi 4. The temptation on changing board is to adjust them to what the new
board is likely to manage, which converts a criterion into a prediction and
guarantees it passes.

They stay as written, marked as Pi 4 targets. If the Pi 3 misses them that
is a measurement and the row says which board it was taken on.

The criterion that carries the argument is relative anyway: the generic
kernel several times worse than the real-time one, under the same load, on
the same hardware, with the same userspace. That is a property of the
preemption model and it holds on either board. It is also the reason the
control kernel from entry 29 matters more than the absolute numbers do.

**Consequence for the plan.** Two kernel builds, not one, because both the
real-time and the control configurations now target a different machine
than the one already built. The image on disk is for a board the HAT does
not fit.

---

## 33. An inference written down as an observation

**What happened.** Told "I can't stack the MCC 118 on the Pi 4, it fits
almost exactly on the Pi 3", I changed the machine, rewrote three figures,
the README, the bring-up notes and the front-page table, and wrote entry 32
saying the HAT "did not seat on a Pi 4" because the Pi 4 moved its Ethernet
and USB stacks.

The observation was that it fits a Pi 3. The mechanism was invented to
explain it. Both went into a journal entry and a commit message in the same
voice, and nothing in either distinguished the part that was seen from the
part that was reasoned.

The correction came one message later: it seats on a 4B and a 3B+, not on a
plain 3. So the invented mechanism was not just unverified, it was wrong,
and it is now in the pushed history of a portfolio repository.

**What was done.** Entry 32 corrected in place rather than edited quietly,
which is the house rule, and the mechanism removed rather than replaced
with a better guess. The open question is left open.

**Why that and not the alternative.** The alternative is to find a
plausible reason the 4B might not fit and write that instead. It would read
better and be worth nothing.

**The pattern, fourth instance.** This repository has now recorded four
versions of the same fault, and they are worth listing together because
the shape is clearer than any one of them:

| Entry | The claim | What it actually was |
|---|---|---|
| 21 | the instruments differ by the GPIO write cost | algebra nobody had done |
| 25 | the fragment did not reach the kernel | the wrong `.config`, said so in a line nobody read |
| 29 | the two images differ in the preemption model alone | true when written, false after a version pin |
| 33 | the HAT does not fit a Pi 4 | an inference from "it fits a Pi 3" |

Entries 21 and 29 were claims that decayed. Entry 25 was a tool reporting
faithfully about the wrong input. This one is different and worse: there
was no decay and no wrong input, only a gap of one question, and the answer
would have cost a sentence.

**What changes as a result.** A journal entry records what happened.
Where something was inferred rather than seen, it says so, in the same
sentence rather than in a later correction. "The HAT fits a Pi 3" and "the
HAT does not fit a Pi 4" are different statements and only one of them was
ever true here.

The cheapest guard is the one that was skipped: when a fact would change a
build, a document or a claim, ask. One question against a machine change,
three figures, four documents and a commit.

## 34. The board named, and three numbers that were wrong with it

**What happened.** The question left open at the end of entry 33 was
answered in five words: a Raspberry Pi 3 Model B v1.2, 2015.

That is not the 3B+. It is the original BCM2837 board, and it settles
three things at once.

**The machine setting was already right, for a reason that had not been
checked.** `machine: raspberrypi3-64` had been set on the strength of "it
fits a Pi 3". It survives, because meta-raspberrypi uses `raspberrypi3-64`
for the whole BCM2837 family and a 3B and a 3B+ take the same image. Being
right by accident is not the same as being right, and the only reason it
did not cost a rebuild is that the two boards happen to share a machine
name.

**Three numbers written for the wrong board.** The comparison table in the
project README described the board as built as a Cortex-A53 at 1.4 GHz.
That is the 3B+. The 3B v1.2 is the same core at 1.2 GHz, with 1 GB of
memory rather than up to 8, and 100 Mbit Ethernet behind the same USB hub
as everything else rather than the 3B+'s gigabit. Corrected, along with
"a bare Pi 4 throttles" in two documents, which was written when the board
was still going to be a Pi 4.

**Where the numbers were not touched.** The absolute acceptance
thresholds, 99.9th percentile below 50 us and maximum below 150 us, stay
exactly as written. They were written for a Pi 4 and they are labelled as
such. A slower core with a busier interrupt controller is more likely to
miss them, and if it does, that is the measurement. Moving a threshold
after seeing the hardware is how a results table stops meaning anything.

The relative criterion is unaffected and always was: generic several times
worse than real-time, same load, same board, same userspace. That is a
property of the preemption model.

**The evidence file, and why it was annotated rather than edited.**
`docs/evidence/kconfig-check.txt` is verbatim `./go kconfig -f rt` output
and it says `MACHINE raspberrypi4-64`, because that is what the machine was
when the check ran. It is left exactly as captured, with a dated note
appended saying what changed and what the rerun is expected to show: the
same 31 lines from a different directory, because the kernel version comes
from `PREFERRED_VERSION_linux-raspberrypi` and `ARCH_SUPPORTS_RT` is
selected by the architecture, neither of which is a machine property.

Editing a captured output to match a later belief would have been quick,
undetectable, and the end of the file's usefulness. Criterion 7 is now
provisional again until that rerun.

**The aha, and it is a small one.** The thing that resolved two days of
wrong assumptions was the board's own silkscreen. Everything upstream of
that, the mechanism about the Pi 4, the 1.4 GHz, the choice of machine,
was reasoning about hardware that was sitting on the desk the whole time.
Read the label.

**What changes as a result.** `./go rt` and `./go rt-generic` have to be
built again for `raspberrypi3-64`, and every copy-and-paste path in
BRINGUP.md that carried the machine name has been corrected, because those
are the commands that go stale silently: a `cp` from a directory that does
not exist fails loudly, but a `cp` from the old one that still exists is
worse.

## 35. The same sort bug, in the sibling script, nine entries later

**What happened.** The first command of the rebuild ran, and its two halves
disagreed about which kernel they were reading:

```
--- kernel   .../work-shared/raspberrypi4-64/kernel-source     (./go ksym)
--- config   .../work/raspberrypi3_64-poky-linux/...           (./go kconfig)
```

The machine is `raspberrypi3-64`. `kconfig` read the tree the build had
just produced. `ksym` read the tree left over from the Pi 4, because
`tmp/work-shared` now holds one per machine and its autodetect ended in
`sort | tail -1`, a lexical sort in which `raspberrypi4-64` comes after
`raspberrypi3-64`.

**This is entry 25, again, in the script next to the one that was fixed.**
Entry 25 found `sort | tail -1` picking 6.6.63 over 6.12.93, because "6" is
greater than "1". It was fixed by ranking on modification time, a test was
written that names two trees so a lexical sort picks the wrong one, and the
whole thing was written up. What was not done was to grep for the same four
characters anywhere else, and the same four characters were sitting in
`check-kernel-symbols.sh` the entire time.

A fix that is not propagated to its siblings is half a fix. The cost of
looking was one `grep -rn "sort | tail -1" scripts/`.

**The part that is worse than being wrong.** It printed the right answer.
Both trees were 6.12.93 for arm64, so all 31 symbols resolved identically
and the check said `31 symbols, all real`. Had the leftover been a 6.6
tree, `CONFIG_PREEMPT_RT` would still have come back `ok`, because as this
script's own header says, it checks that a symbol is declared and not that
its dependencies are met. So the failure mode was: read the wrong kernel,
report the right answer, and teach the reader that the check is
trustworthy.

**What was done.** Three things, and the third is the one that generalises.

1. Ranked by modification time, like its sibling. There is always a newest,
   so unlike a filter this cannot exclude everything.
2. The trees it did **not** read are now named on stderr. A tool that
   silently chooses between its inputs can be quietly wrong about which
   question it just answered, and this one was, for a whole command.
3. Four assertions in `tests/kernel-symbols-test.sh`: two machine trees
   named so a lexical sort picks the wrong one, then the timestamps
   reversed so the assertion is about the clock rather than about the digit,
   and a single-tree case asserting that nothing is printed when there is
   no choice to make. A warning that fires when there is no ambiguity
   trains you to ignore warnings.

The suite was then run against the pre-fix picker to check the test was
worth having: 36 passed, 1 failed, and the failure was the assertion about
the newest tree. A test that does not fail on the bug it was written for is
decoration.

**Where criterion 7 stands.** The `kconfig` half is good: it read
`.../raspberrypi3_64-poky-linux/linux-raspberrypi/6.12.93+git/...`, which
is the right machine, and reported `CONFIG_PREEMPT_RT=y` along with all 31
lines of both fragments. The `ksym` half has to be run again, now that it
will read the right tree and say what it ignored.

**Aha, and it is the same one as entry 33 wearing different clothes.** In
entry 33 an inference was written as an observation. Here a tool reported a
fact about a file it had not read. Both are the same failure to ask which
input a statement came from, once by a person and once by a script, and
both were invisible because the answer happened to be right.

**What changes as a result.** `grep -rn "sort | tail -1" scripts/` is now a
thing to run after fixing any picker, and both pickers name their losers.
The build host still has the `raspberrypi4-64` tree on it, deliberately: the
rerun is better evidence with the ambiguity present than without it.

### Then the grep was actually run, and it was not two scripts

Written above as a resolution, run a minute later as a command. It found
three more, in scripts nobody had been thinking about:

| Script | What it chooses | What the wrong choice does |
|---|---|---|
| `flash.sh` | which `.wic.bz2` goes on the card | writes a Pi 4 image to a Pi 3 card. No warning, no boot, and the symptom is a dark board that reads as dead hardware |
| `packages.sh` | which `.manifest` to list | the package table in a README describes the other image |
| `sdk.sh` | the SDK installer, and the environment script under `/opt/poky` | builds against the wrong sysroot |

`flash.sh` is the one that matters. `deploy/images` holds one directory per
`MACHINE`, this host now has two, and `raspberrypi4-64` sorts last. The
walkthrough has said for weeks that `./go flash` does not check the image
against the card. It turned out not to check the image against the *build*
either, and it was one `./go flash` away from being discovered on hardware,
where it would have looked like a bad card, a bad HAT or a bad kernel.

**So the fix stopped being a fix and became a function.** `newest_path` in
`scripts/common.sh` reads `find -printf '%T@ %p\n'` lines, prints the
newest, and names the rest on stderr. Five call sites now use it:
`check-kernel-symbols.sh`, `check-kernel-config.sh`, `flash.sh`,
`packages.sh` and `sdk.sh` twice. `grep -rn "sort | tail -1" scripts/`
returns nothing but the comment explaining why.

Its own suite is `tests/common-test.sh`, eleven assertions, and three of
them are about things the inline versions had never been asked:

- that **stdout carries exactly one line**. Every caller writes
  `x=$(... | newest_path ...)`, so one stray line of commentary becomes
  part of a path, and the script goes looking for a file whose name ends
  in a sentence about warnings.
- that an **empty input says nothing**. The sentence to print belongs to
  the caller: `flash.sh` says run `build.sh`, the kernel check says run
  `kernel_configme`, and a helper that guesses between them is wrong twice.
- that a **path containing a space survives** `cut -d' ' -f2-`. Build
  directories should not have spaces in them, and one day one will.

CI globs `tests/*.sh`, so it runs from the next push without a change to
the workflow.

**The real lesson, and it is not about sorting.** Entry 25 fixed this bug
where it was found. That felt like finishing. Four more copies were sitting
in the same directory, and the one with teeth was in the script that
erases a card. The question that was never asked in entry 25 was the cheap
one: *where else did I write this?* Nine entries and one nearly dark board
later, it is a step rather than an afterthought.

## 36. Criterion 7, on the right machine, and a red CI in between

**What happened.** Both checks reran against `raspberrypi3-64` and both
opened by naming the tree they did not read:

```
--- also     1 older kernel tree(s) ignored, newest wins:
---          .../work-shared/raspberrypi4-64/kernel-source
--- kernel   .../work-shared/raspberrypi3-64/kernel-source
```

and the same for the `.config`. The fix from entry 35 is doing exactly what
it was written for, in both the script where the bug was found and the one
it was propagated to. 31 symbols real, 31 options present,
`CONFIG_PREEMPT_RT=y`.

**Criterion 7 is met on the build host for the machine the board actually
is.** The new capture is `docs/evidence/kconfig-check.txt`. The Pi 4 one
was renamed to `kconfig-check-raspberrypi4-64.txt`, unedited, with a note
recording that its prediction held: same 31 lines, same kernel version,
different directory.

That prediction was worth writing down. It is the difference between a
rerun that confirms something and a rerun that merely happens.

**Then CI went red on the commit before this one.**

```
tests/common-test.sh: has a shebang but is committed as 100644, not 100755
```

`scripts/lint.py` has checked exactly this for months. It reads
`git ls-files --stage`, because Git on Windows defaults to
`core.filemode=false` and a `chmod` on that side never reaches the commit.
I ran `chmod +x`, ran the linter, saw `lint: clean`, staged, committed.

**The linter was clean because the file was untracked.** An untracked file
has no index entry, so it does not appear in `git ls-files --stage` at all.
The one case the mode check cannot see is a brand new script, which is the
only case where the mode is ever wrong. Every existing test file in the
repository is already 755; the check had been passing for months by having
nothing to do.

**This is the third time this session that a check was clean about a file
it had not looked at.** `ksym` read the wrong kernel tree and reported the
right answer. `kconfig` read the wrong `.config` back in entry 25. Now the
linter passed a file it had never been given. The shape is identical: the
output says "clean" and the honest statement is "clean, of what I looked
at".

**What was done.**

1. `git update-index --chmod=+x tests/common-test.sh`, which is the only
   way to set the bit from this side.
2. `check_untracked_scripts()` in `lint.py`: untracked files with a
   shebang are now listed, with the command, as a **note** rather than a
   failure. An untracked file is not yet a claim about anything, and a
   working tree may hold scratch scripts on purpose. Verified by dropping
   a probe script in `tests/` and watching it appear, then removing it.

**What changes as a result.** Lint runs **after** `git add`, not before.
Every index-based check has the same blind spot and the ordering is the
whole fix. It also means the pre-commit sequence is now: `git add -A`, then
`python scripts/lint.py`, then commit, rather than the other way round.

**The aha.** A green check answers a narrower question than it appears to.
`lint: clean` means "the files I was given are clean", and what it was
given is a decision made somewhere else, by `git ls-files`, by a `find`, by
a glob. Three times in one session that decision was the actual bug, and in
none of them did the tool say what it had looked at. So both pickers now
name their inputs, and the linter names what it could not see.

## 37. An adapter, and the board moves for the third and last time

**What happened.** An adapter arrived that lets the MCC 118 stack on a 4B
and a 3B+ as well as the 3B. The Pi 4 was free, Project 15 finished with it,
and the constraint that had forced the previous two moves was gone.

So the machine went back to `raspberrypi4-64`, four hours after it had been
changed away from it.

**Why, and not "leave it, the 3B works".** The acceptance thresholds are a
99.9th percentile below 50 us and a maximum below 150 us, and they were
written for a Pi 4. Measured on a Pi 4 they are a criterion. Measured on a
3B they are a criterion with an asterisk in every row of the results table,
and the asterisk has to be explained every time the table is read.

The alternative was to relax the thresholds to suit the 3B. That is worse
than it sounds: a threshold chosen after seeing the hardware is not a
threshold, it is a description, and the whole value of writing one down in
advance is that the hardware can miss it.

**Why the 3B build is not wasted, and is not the fallback.** Its image is
built, verified against its own `.config`, and archived. It is the second
board: same kernel, same userspace, a 1.2 GHz Cortex-A53 with 1 GB and its
Ethernet behind the USB hub. That is the harder real-time target, so the
pair says more than either alone, and `METHOD.md`'s stretch-goal row now
reads as a second set of runs rather than a second build.

**What it cost, honestly.** Two kernel builds for a board that is now the
second one, about four hours of machine time, 28 GB of disk at peak, and
three rounds of documentation churn. None of that would have happened if
the question in entry 33 had been asked before the machine was changed:
*is the other board free, and does the HAT fit it with anything you have?*

**The trade-off that was actually made.** Doing it a third time cost a day
of churn. Not doing it would have cost every future reader of the results
table a footnote. The churn is paid once; the footnote is paid forever. The
same reasoning is why the thresholds did not move.

**What changes as a result.** `kas/bench-rt.yml` carries the reasoning at
the `machine:` line rather than in a commit message, including how to build
for the 3B instead, which is one line. And `./go archive` refuses to file an
image under a configuration whose machine does not match, so the two boards
cannot be confused in the store.

## 38. A pull three hours into a build, and what a basehash covers

**What happened.** I told the operator to run `git pull && ./go archive
available` while a `bench-rt-image` build had been running for three hours.
I knew it was running. I had been watching its disk usage.

kas does not copy the checkout into the build directory. It registers it as
a layer, in place, and BitBake reads recipes from there for the whole of a
build. The pull brought in Project 4 and added two lines to
`linux-raspberrypi_%.bbappend`:

```
BENCH_NETBOOT_KERNEL ?= "0"
SRC_URI += '${@"file://netboot.cfg" if d.getVar("BENCH_NETBOOT_KERNEL") == "1" else ""}'
```

Both inert for that build: the switch was off and the expression expanded
to the empty string. The build stopped with 327 errors anyway:

```
ERROR: When reparsing .../linux-raspberrypi_6.12.bb:do_fetch, the basehash
value changed from 657647e2... to 1b9f07b4... The metadata is not
deterministic and this needs to be fixed.
```

**The aha, and it is about hashing rather than about git.** A basehash
covers the expression and what it depends on, not what the expression
evaluated to. Adding a conditional that contributes nothing still changes
the recipe's signature, because the signature is computed from the metadata
and not from the result. Five kernel tasks moved: `do_fetch`, `do_unpack`,
`do_populate_lic`, `do_create_spdx`, `do_recipe_qa`.

That is also why the message blames "the metadata", which is the one thing
that was not at fault. The metadata was deterministic. It was replaced
mid-flight.

**Why the obvious recovery was not the right one.** The obvious move is to
accept the new metadata and let the kernel rebuild, which is correct and
costs about two hours. The cheaper one is to restore only the changed
recipe file to the commit the build started from: the basehashes return,
the existing stamps match, and BitBake resumes. That needs the starting
commit, which is in the build's own opening lines and nowhere else once the
scrollback is gone.

In the end neither was needed, for the reason in the next entry.

**What was done.** `scripts/pull.sh` and `./go pull`, which refuse while
`pgrep` finds a `bitbake`, explain it in terms of the layer rather than the
build directory, print the commit they started from before pulling, and
list which incoming files were under `meta-bench` or `kas`, since only
those can move a basehash and prose cannot.

**Why a guard and not a note in the documentation.** Because the
documentation would have been written by the person who already knew, and
read by the person who already knew. The failure was not ignorance of the
rule; it was applying attention elsewhere while a three-hour process ran
unattended. That is what a guard is for.

**Why it also says when it cannot check.** `pgrep` does not exist on Git
Bash, where `pgrep ... >/dev/null 2>&1` is simply false and the guard waves
everything through. No build runs on that host, so nothing is at risk, but
a check that reports success without having looked is the exact failure
this repository had already found twice that day. It now says which of the
two it did.

## 39. 327 errors, 6258 successes, and one correct image

**What happened.** The build from entry 38 kept going. It printed its
errors, carried on scheduling tasks, and ended:

```
NOTE: Tasks Summary: Attempted 6258 tasks of which 2805 didn't need to be
rerun and all succeeded.
Summary: There were 327 ERROR messages, returning a non-zero exit code.
```

**All succeeded.** The 327 errors were the same five reparse complaints
repeated as BitBake reparsed. No task failed. The image was written at
13:13 and is 78 MB.

**Where I was wrong twice in an hour, and it is worth recording both.**

First I said BitBake had stopped scheduling new work and would exit
shortly. It had not: the count went 6201, then 6232, and `gcc` moved from
`do_compile` to `do_package`. I had read "327 errors" as "stopped" because
that is what errors usually mean.

Then the operator ran `ls .../raspberrypi3-64/*.wic.bz2`, got nothing, and
I concluded the image had not been produced and prepared the whole restore
path. The image appeared two minutes later, at 13:13. The check was right;
my reading of a single negative result as a settled fact was not.

**The trade-off in how the failure was handled.** Letting it run to its
own end preserved every completed task's sstate, at the cost of waiting.
Killing it would have been faster and would have thrown away a 28 minute
`gcc do_compile` that was in flight. Waiting was right, and it turned out
to be much more than right, because what it produced was the artefact.

**Why the image was not simply trusted.** The reasoning for trusting it is
sound: the netboot expression expands to nothing when the switch is off, so
the effective `SRC_URI` and kernel configuration were identical on both
sides of the change, and only the hash moved. That is a reason to believe.
It is not evidence.

So `./go kconfig -f rt` was run against the `.config` that build produced
at 10:06. All 31 options, `CONFIG_PREEMPT_RT=y`, the other three members of
its choice block excluded. Criterion 7, on the machine that was actually
built. The result is appended to the evidence file with the reason it was
worth repeating.

**What changes as a result.** A non-zero exit is a reason to look, not a
conclusion. The three questions, in order, are: did any task fail, does the
artefact exist, and does it check out. Here the answers were no, yes and
yes, and two of the three had already been answered by output that was on
the screen.

## 40. Twenty-eight gigabytes for one word, and a disk that does not come back

**What happened.** Changing `machine:` from `raspberrypi4-64` to
`raspberrypi3-64` cost 28 GB of host disk and about four hours. The build
said why in one line, in a place nobody reads:

```
Sstate summary: Wanted 1921 Local 200 Mirrors 0 Missed 1721 Current 942
(10% match, 39% complete)
```

**The aha.** sstate is keyed on the tune, not on the machine name. The Pi 4
is `cortexa72`, the Pi 3 is `cortexa53`, so changing the board changed the
compiler flags for every package, and 1721 of 1921 wanted objects missed.
It was not "a rebuild of the kernel for another board". It was a rebuild of
the distribution.

A 10% sstate match is the number to read when deciding whether a
configuration change is small. Nothing else on the screen says so.

**Then the disk would not come back.** Deleting 4.5 GB of stale work trees
inside WSL moved the host free space not at all, and neither did
`fstrim -av` reporting 21.6 GiB trimmed. The VHDX is a growing file: freeing
blocks inside it makes them reusable, and returns nothing to Windows.

Three options, and two are wrong:

| Option | Verdict |
|---|---|
| `wsl --manage Ubuntu --set-sparse true` | Refused by WSL itself: disabled due to data corruption. It offers `--allow-unsafe`. Declined: the VHDX holds the build tree, the archives and a git checkout |
| `Optimize-VHD` | Hyper-V only, and this is Windows Home |
| `diskpart` `compact vdisk` | Supported, non-destructive, works on Home |

`compact vdisk` on a stopped VHDX returned 9.3 GB the first time, 69.6 to
60.3, and C: went 11 to 19.4 GB. Less than the 21.6 GiB trimmed, because
compaction reclaims whole free extents and not interior slack.

**Why that was still not enough, and what actually fixed it.**
`require_host_disk_gb 25` blocks a build below 25 GB, so 19.4 was still a
refusal. The fix was `./go clean`, which deletes `~/bench/build` and keeps
the caches. The layout was checked before running it rather than trusted:

| Path | Size | Fate |
|---|---|---|
| `build` | 15 G | deleted |
| `downloads` | 16 G | kept |
| `sstate-cache` | 13 G | kept |
| `images` | 233 M | kept |
| `kernel-rt` | 70 M | kept |

Then `fstrim` reported 968 GiB and a second compaction took the VHDX from
60.3 to 44.8 GB, leaving 34.7 GB on C:. Keeping `sstate-cache` is what
makes the next build cheap; deleting it would have turned a one hour
control build back into a four hour one.

**The guard's real defect, which is not its threshold.** It checks once, at
the start, before it can know what the build will cost. 38 GB passed a 25 GB
test and the build peaked at 28 GB with a floor of 9.8 GB. It was right by
13 GB of luck. A machine change is not an ordinary build and nothing in the
guard can tell the difference.

**What changes as a result.** Before a build that changes `MACHINE`, expect
a near-total sstate miss and budget for a full build rather than an
incremental one. `Sstate summary` in the first screen of output is the
number that says which you are getting. And on WSL, freeing disk is three
steps rather than one: delete, `fstrim`, compact the VHDX with `diskpart`
while WSL is shut down. Never `--allow-unsafe`.

## 41. The right board is not the right system, and three more silent checks

**What happened.** Writing out the command to archive Project 15's image, I
read `scripts/archive.sh` and found that `save()` checked the image's
machine against the kas file and not its target.

`deploy/images` holds one directory per machine and every image ever built
for that machine inside it. So after building `bench-rt` and then archiving
under `bench-router`, newest-wins returns `bench-rt-image`, the machine
matches, the check passes, and a real-time image is filed as an LTE router.

**Why that is worse than the wrong-board case sitting directly above it.**
A wrong board does not boot. The symptom is immediate and the card is
obviously wrong. A wrong target flashes, boots, runs, and is only
discovered by whoever trusted the label. The check that existed guarded the
loud failure and not the quiet one.

**What was done, and the two things the fix got wrong first.**

`kas_target()`, following includes for the same reason `kas_machine()`
does. Matched against `<target>-<machine>` rather than the target alone,
because `bench-image` is a prefix of `bench-image-dev` and a prefix match
would file a dev image under the production configuration.

Then the first version keyed on `.rootfs` being in the filename and treated
everything else as "not a Yocto name, skip". The short name in
`deploy/images` is a symlink without `.rootfs` in it, written after the file
it points at and therefore usually the newest, so the check silently did
nothing in exactly the case it was written for. The test found it on the
first run after the assertions were strengthened.

And the suite itself had a test passing for the wrong reason: "an inherited
machine still matches" ran `bench-dev` against a `bench-image` fixture and
accepted anything that was not a machine complaint, so when the new target
check began refusing it, the catch-all branch reported the refusal as a
pass. A test whose failure branch is "some other error occurred" is not
testing what it names.

**Two more of the same shape, the same day.**

`.gitignore` covers `build/`, `tmp/`, `sstate-cache/` and `downloads/` under
the heading "these are the strays". It did not cover the layer clones kas
leaves in the checkout when `KAS_WORK_DIR` is unset, because they are named
after real things. 469 MB of them had sat there for weeks. Disk is not what
surfaced them: `archive.sh` appends `-dirty` when `git status` is not clean,
so every image archived on that host was recorded as `6126444-dirty`. The
tree was not modified. A provenance record that is wrong about the commit is
worse than none, because it is believed.

And `./go archive rt` failed with `no such configuration: kas/rt.yml`. True,
and it names a file nobody had in mind: every build verb is the short name,
so `rt` is what a hand types. `resolve_kas_config` now tries the name, then
the `bench-` prefix, and lists the ten configurations when neither fits.

**The pattern, and this is the fifth and sixth instance.** Entry 25:
`kconfig` read another kernel's `.config`. Entry 35: `ksym` read the
abandoned machine's tree. Entry 36: the linter passed a file it had never
been given. Here: an archive check that guards the loud failure, a `.gitignore`
that is right about everything it names, and a resolver that answers the
question it was asked rather than the one that was meant.

None of them reported an error. All of them reported success.

## 42. A lint rule that took three attempts, and both failures were the theme

**What happened.** CI went red on SC2120: a `run()` helper in
`tests/pull-test.sh` forwarding `"$@"` that every call site invokes bare.
Second shellcheck finding in a day that this host structurally cannot see,
since there is no shellcheck on it, so it earned a narrow rule in
`lint.py` beside the SC2086 one.

**Attempt one: written, and never called.** The function was defined and
not added to `main()`'s tuple of checks. It reported nothing. `lint: clean`.
A check that is not registered is indistinguishable from a check that
passes, which is the same sentence this journal has now written about a
`find`, a `git ls-files` and a `pgrep`.

**Attempt two: defeated by its own file's comments.** The call-site regex
matched the bare word `run` in the sentence `# and run from there, which is
also how they`, counted prose as a call with arguments, and therefore
concluded the helper was used both ways. It silenced itself on the one file
it had been written for.

**Attempt three: strip comments, then verify by breaking it on purpose.**
Reintroduce `"$@"`, run the linter, watch it fire, restore, watch it go
quiet. Both directions, because a rule that fires is only half of what was
wanted; the other half is that it does not fire otherwise.

**Why a narrow rule and not shellcheck locally.** Installing shellcheck on
the authoring machine would fix the class rather than the instance and is
the better answer. It is not available there, and the gap is structural
rather than a matter of discipline, so the choice is between one rule per
recurring mistake and shipping them to CI. Two rules for two mistakes is
not a reimplementation of shellcheck; it is a note that the compiler cannot
be run here.

**What changes as a result.** A new check is verified by breaking the thing
it checks, before it is trusted. The cost is two extra commands and it has
now caught three separate defects in one day, in a `find`, in a test and in
the rule itself.

## 43. The board booted, and two acceptance criteria were written against a file that does not exist

**What happened.** First boot of a real-time kernel on real hardware, and
line two of the console said it:

```
Linux version 6.12.93-v8 ... #1 SMP PREEMPT_RT
Machine model: Raspberry Pi 4 Model B Rev 1.4
```

Then:

```
# cat /sys/kernel/realtime
cat: can't open '/sys/kernel/realtime': No such file or directory
```

**The aha.** `/sys/kernel/realtime` came from the **out-of-tree RT patch
series**. `PREEMPT_RT` was merged into mainline for 6.12, and that sysfs
file did not come with it. On the kernel this project deliberately went to
6.12 to get, the file is absent on the real-time build exactly as it is on
the generic one.

So acceptance criterion 1 was written against an interface that the
project's own version pin removed. Every document in the project said to
read it. It had never been read, because no board had ever booted.

**What was used instead.** `uname -v` carries the preemption model and
always has, and `CONFIG_IKCONFIG_PROC=y` is in `bench.cfg`, so the running
kernel's own configuration is readable:

```
#1 SMP PREEMPT_RT
CONFIG_PREEMPT_RT=y
# CONFIG_PREEMPT_NONE is not set
# CONFIG_PREEMPT_VOLUNTARY is not set
# CONFIG_PREEMPT is not set
```

That is better evidence than the file would have been. All four members of
the choice block, read from the kernel that is running, matching what
`./go kconfig -f rt` verified against the build tree. Criterion 1 met, and
the on-board half of criterion 7 with it.

**Why the criterion was changed rather than marked unmet.** A criterion
that cannot be satisfied because its interface no longer exists is a defect
in the criterion. The question it was asking, "is this board running a
preemptible kernel", is still the right question and now has a better
answer. Lowering a bar would be different and is not what this is.

**What changes as a result.** Every reference to `/sys/kernel/realtime` in
BRINGUP, the project README, the results schema and
`rt-kernel-install.sh` now names `uname -v` and `/proc/config.gz`. And one
more thing, which is the next entry, because the file was not only in the
documentation.

## 44. Every real-time row would have been labelled generic

**What happened.** `rt-run` reads that same vanished file to decide what
every row of the results table means:

```sh
realtime=no
if [ -r "$SYS/kernel/realtime" ]; then
	if [ "$(cat "$SYS/kernel/realtime")" = "1" ]; then
		realtime=yes
	fi
fi
```

It does not refuse when the file is missing. It writes `realtime=no`.

**What that would have cost.** This project is one comparison between two
kernels that differ in one symbol. On the real-time board, every row would
have carried `realtime=no`; the auto-generated label would have been
`generic` rather than `rt`; the result files would have been named to
match; and the CSV would have contained two arms of an experiment labelled
identically.

Nothing in the output would have looked wrong. The numbers would have been
real measurements of a real kernel. Only the column that gives them their
meaning would have been false, and it would have been false in the
direction that makes the whole table say nothing.

**Why this is the worst one yet.** The earlier silent failures this session
were wrong about their inputs: a `find` that read the wrong kernel tree, a
linter handed no file, a `pgrep` that could not run. This one is not wrong
about its input. Its input is genuinely absent, and it treats absence as a
measurement. "The file is not there" and "the kernel is not real-time" are
different statements and it collapses them.

**What was done.** `uname -v` is the authority: the kernel puts its
preemption model in the version string, on every kernel, with no filesystem
involved and no way for it to be missing. Where the old interface does
exist it has to agree, and a disagreement is a refusal rather than a
choice:

```
the kernel disagrees with itself about its preemption model.
uname -v says realtime=yes ... /sys/kernel/realtime says realtime=no.
One of them is wrong and a row labelled from either would be a guess.
```

**And the test agreed with the bug.** `tests/rt-run-test.sh` created
`/sys/kernel/realtime` in every fixture, so the case the board actually
presents was never simulated. Worse, its generic-kernel fixture wrote 0 to
that file while leaving the `uname` stub saying `PREEMPT_RT`: a machine
whose version string and whose sysfs file contradict each other. No such
kernel exists. It passed only because the code read one source and ignored
the other, so an incoherent fixture could not be detected.

Adding the disagreement check broke that test immediately, which is the
test doing its job three months late.

Four assertions added, and the generic half of the experiment is now
simulated for the first time: absent file plus `PREEMPT_RT` in `uname`
reads as real-time; absent file plus `PREEMPT_DYNAMIC` reads as generic;
sources that disagree refuse; sources that agree still work. 59 passing.

**What changes as a result.** When a check reads a fact from a file, ask
what it does when the file is not there. "Absent" is not a value. If the
code has no way to distinguish "absent" from a real answer, it needs a
second source or it needs to refuse, and the second source should be one
that cannot be absent.

## 45. The instrument announced itself and could not be opened

**What happened.** With the HAT stacked on the Pi 4:

```
# cat /proc/device-tree/hat/product
MCC 118 Voltage Input HAT
# daqhats_list_boards
Found 1 board(s):
  Address: 0
  Type: MCC 118
  Name: MCC 118 Voltage Input HAT
Can't open device
# ls /dev/spidev0.0
ls: /dev/spidev0.0: No such file or directory
```

The firmware read the HAT's ID EEPROM at boot, so the board is seated and
identified by name and address. The library then could not talk to it.

That is the third row of this project's own failure table, written months
ago: *"the library found the board and could not talk to it. That is SPI,
not the EEPROM."* The table was right, and it sent the diagnosis straight
at SPI instead of at the HAT, the wiring or the address links.

**The diagnosis, in three questions.**

| Question | Answer |
|---|---|
| Is the bus enabled in config.txt | `dtparam=spi=on` present |
| Did the firmware apply it | `/proc/device-tree/soc/spi@7e204000/status` = **okay** |
| Is the driver there | `/sys/class/spi_master/` **empty**, `dmesg` silent, `modinfo spi-bcm2835` **not found** |

And then the one that settled it, from the running kernel's own config:

```
CONFIG_SPI=y
CONFIG_SPI_MASTER=y
CONFIG_SPI_BCM2835=m      <- built
CONFIG_SPI_SPIDEV=m       <- built
```

`/lib/modules/6.12.93-v8/kernel/drivers/spi/` contained **`spidev.ko.xz`
and nothing else.**

**The aha.** The controller driver was configured, compiled and deployed,
and is not in the image. Yocto packages one kernel module per `.ko` and
installs only what an image names. `bench-rt-image.bb` asks for
`kernel-module-spidev` and never asks for the controller that `spidev`
attaches to.

So: the bus was on, the driver existed, and the rootfs did not have it. A
`spidev` with no master registers no device node, and the only symptom is a
file that never appears.

**Why nothing upstream caught it, and this is the part worth keeping.**
`./go ksym -f rt` passed on all 31 fragment options. `./go kconfig -f rt`
passed on all 31, twice, on two machines. Both were correct and both were
answering the same question: **did what I asked for arrive?** Neither can
answer **did I ask for what I needed?**

`bench.cfg` asks for `CONFIG_SPI_SPIDEV=m`, the userspace interface, and
never names a controller, because the BSP defconfig provides one. It did
provide one. Providing it as a module moved the problem from the kernel
configuration to the image package list, where no kernel check looks.

**Second time in this repository.** Project 1 lost a round to a wireless
driver without its module package, which is why `scripts/lint.py` has
`check_image_packages` at all. That rule scans recipe comments for
`kernel-module-*` names and requires them in `IMAGE_INSTALL`. It could not
see this one: nobody had ever written the name down anywhere to be scanned.
A rule that checks that what you mentioned is installed cannot catch what
you never mentioned.

**What was done.** `kernel-module-spi-bcm2835` added to
`bench-rt-image.bb`, with the whole chain written beside it so the next
reader does not have to rediscover which layer was at fault. The kernel is
unchanged, so this is a rootfs rebuild and not a kernel compile.

**What changes as a result.** When an image asks for a `spidev`, an
`i2c-dev` or any other userspace interface to a bus, it has to ask for the
controller too, and the two belong on adjacent lines. The general form: a
kernel option and an image package are different things, and `=m` is the
word that turns one into the other.

## 46. A console deferred since Project 1, and the hardware that comes off the bench

**The console.** Project 1's journal recorded a deferral: *"this bench's
USB/TTL cable is a PL2303HXA, a generation Windows refuses to drive, so
there was no serial console."* Project 2 then made a console mandatory, and
it stayed unavailable.

It worked today, and the fix had nothing to do with the cable. `usbipd list`
names the device as Windows sees it:

```
2-1  067b:2303  PL2303HXA PHASED OUT SINCE 2012. PLEASE CONTACT YOUR SUPP...
```

That string is Prolific's **Windows driver** refusing to bind to an old or
counterfeit chip. Linux has no such policy: the kernel's `pl2303` driver
attaches to it without comment.

```
usbipd attach --wsl --busid 2-1
pl2303 converter now attached to ttyUSB0
picocom -b 115200 /dev/ttyUSB0
```

**The aha, and it generalises past this cable.** The blocker was a vendor
policy in one operating system's driver, not a hardware fault, and the
machine already had a second operating system with a different policy
attached to the same USB port. Two projects' worth of "the console does not
work here" was one `usbipd attach` away from working.

Worth asking, when a device is declared unusable on this bench: unusable to
which side of the machine? WSL is not only where the builds run.

**And the hardware that came off.** Two things were removed before the
first measurement, both for the same reason and neither of them broken:

- the DSI touchscreen ribbon. A display pipeline means DMA moving
  framebuffers and a touch controller polling, all of it work the system
  under test performs while being timed. It leaves a mark in the boot log
  even unplugged: `deferred probe pending: wait for supplier reg_display@45`
- a TP-Link USB wireless dongle, which turned out to have bound to no
  driver at all. `/sys/class/net` held only `eth0` on `bcmgenet` and
  `wlan0` on `brcmfmac`, both onboard. The image ships no Realtek driver,
  so it had enumerated, raised its interrupts, and provided nothing

The dongle is the better illustration. It was contributing USB interrupt
traffic to a board whose entire purpose is measuring interrupt latency,
while delivering no interface. Unused hardware is not neutral on a bench
like this, and the cheapest isolation available is unplugging something.

**Why not simply add the Realtek driver so it works.** Because this image
wants the fewest interrupt sources, not the most. Project 15 names
`kernel-module-rtl8xxxu` and `linux-firmware-rtl8192eu` because a router
needs a second radio. Project 8 does not. The same missing driver is a
defect in one image and a correct decision in another, which is the
argument for per-image package lists rather than one shared one.

## 47. One line in an image recipe, and the instrument answered

**What happened.** `kernel-module-spi-bcm2835` added to
`bench-rt-image.bb`, rebuilt, reflashed, booted:

```
/dev/spidev0.0
spidev        24576  0
spi_bcm2835   20480  0
spi0
Found 1 board(s):
  Address: 0
  Type: MCC 118
  Hardware version: 1
  Name: MCC 118 Voltage Input HAT
  Firmware version:   1.03
  Bootloader version: 1.01
```

**The two lines that prove it rather than suggest it.** Firmware 1.03 and
bootloader 1.01 were not in this morning's output. They cannot be: the ID
EEPROM carries the vendor, product and UUID, and nothing else. Those two
numbers come off the board over SPI. So the library is no longer merely
finding the HAT, it is holding a conversation with it.

That distinction is worth keeping. This morning's failure printed the
board's name and address and looked most of the way to working. The
difference between "found" and "opened" was one module, and the only way to
see it in the output is to know which fields come from where.

**What it cost, and what it did not.** A one-line change to an image
recipe. The kernel was never wrong. `dtparam=spi=on` was never wrong. The
device tree node read `status = okay` from the first boot. `./go ksym` and
`./go kconfig` passed on all 31 options every time they were run, on two
machines, because they answer whether what was asked for arrived, and this
was never asked for.

The rebuild was 48 minutes, nearly all of it kernel, and none of that was
needed for this fix: the TEE bbappend from Project 20 had landed in the
same pull and moved the kernel's basehash. The fix itself was a rootfs
rebuild. Two unrelated things travelled together because they arrived in
one `git pull`, which is the ordinary cost of a shared repository and not a
fault.

**Where this leaves the project.**

| Criterion | State |
|---|---|
| 1, a real-time kernel on the board | **met**, `uname -v` and `/proc/config.gz` |
| 7, the fragment reached the kernel | **met on both machines**, now confirmed against the running kernel |
| the HAT is visible and open | **met**, firmware version read over SPI |
| the wire | blocked, two jumper wires not yet to hand |

Steps 1 and 2 of the bring-up notes are done. Step 3 proves that the pin
the software drives is the pin the instrument reads, and it needs a jumper
from header pin 38 to CH0 and one from pin 39 to AGND. Until then the
external instrument has nothing to measure and the internal one has nothing
to be compared against.

**What changes as a result.** The bring-up notes' failure table earns its
keep: *"the library found the board and could not talk to it. That is SPI,
not the EEPROM."* Written months ago, from reasoning rather than from
experience, and it sent the diagnosis straight at the bus instead of at the
HAT, the address links or the wiring. A failure table written before the
hardware arrives is worth the time it takes, and this is the evidence.
