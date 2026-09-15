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
