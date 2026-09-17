# Journal: Project 01

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

It is kept because a polished repository hides the part that is worth
reading. Anyone can follow a working recipe. The useful question is what you
do when the output disagrees with you, and that is only visible if the
disagreements are written down.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 14 September 2026 unless noted.

---

## 1. Written before it could be built

**What happened.** The layer, recipes, application, scripts and CI were
written on a Windows laptop with no C compiler and no WSL distribution
installed. Nothing that needed BitBake or gcc could run.

**What was done.** Everything verifiable without a compiler was verified:
static layer checks, YAML parsing, shell syntax, the state machine tests
against a fake `systemctl`. The status tables said plainly that the image
had never been built and the daemon had never been compiled.

**Why that and not the alternative.** The alternative was to write the code
and describe it as done. A portfolio repository whose claims have not been
checked is worse than one that is visibly incomplete, because the first
failure a reader finds discredits everything else. The empty build-times
table came from the same rule.

---

## 2. The LEDs were not bare LEDs

**What happened.** The specification described three LEDs with series
resistors. The actual parts are four-pin modules: `S1` signal, `S2` unused,
`U` supply, `G` ground, with the resistor on the board.

**What was done.** The wiring table was corrected, the loose resistors
dropped, and two code changes followed. The GPIO chip is now found by label
rather than by index, and polarity became configuration through
`gpiod_line_settings_set_active_low()` and `/etc/bench/leds.conf`.

**Why that and not the alternative.** The alternative was to assume active
high, which is right half the time. A module with a supply pin may have the
LED between `U` and `S1`, in which case it lights on a low signal, and
nothing on the silkscreen says which. Guessing wrong produces a board that
works but shows the wrong colour, which is harder to notice than an outright
failure.

A second consequence was a safety note: `U` must go to 3V3 rather than 5 V,
because if the LED sits between supply and signal then `S1` floats at the
supply voltage whenever the GPIO is not driving.

---

## 3. Twenty repositories became one

**What happened.** The layer was first built as a standalone `meta-bench`
repository. That is wrong for twenty interdependent projects.

**What was done.** The repository root stopped being a Yocto layer. The
layer moved to `meta-bench/`, project material moved to
`projects/NN-slug/`, and the kas repository entry gained an explicit
`layers:` key so kas knows where the layer is inside the repository.

**Why that and not the alternative.** A layer directory cannot also be a
monorepo holding twenty projects' notes and evidence. The alternative,
twenty repositories, would mean twenty copies of the same layer pins and a
reader reconstructing the order from scratch. The projects genuinely depend
on each other, so the repository should say so.

Done before the first push, deliberately. Restructuring after publication
costs far more.

---

## 4. A lint rule that defeated itself

**What happened.** A rule was added to `scripts/lint.py` to keep tooling
attribution out of the published repository. Its word list meant the
repository now contained exactly the words it forbade. A scan of the built
archive found six matches, all inside the checker.

**What was done.** The rule was removed from the layer and the scanner moved
outside the repository entirely, where it is run by hand before a push and
also reads the git history, since commit trailers are where attribution
usually survives a clean working tree.

**Why that and not the alternative.** The alternative was to obfuscate the
word list so the literal strings never appear. That works and looks
peculiar, and a reader would reasonably wonder why. A check about publishing
belongs outside the thing being published.

**What it cost.** One wasted iteration, and a useful reminder: a checker is
part of the artefact it checks.

---

## 5. Permission denied on a fresh clone

**What happened.** After the first push and clone onto Linux,
`./go setup` failed with `Permission denied`. Every script had arrived
non-executable.

**What was done.** `git update-index --chmod=+x` on the twelve files with a
shebang, and a new lint rule that reads the git index and asserts that any
file with a shebang is recorded `100755` and any file without one is not.

**Why that and not the alternative.** The cause is that git on Windows
defaults to `core.filemode=false`, so `chmod` never reaches the commit. The
obvious alternative, setting `core.filemode=true`, does not work well on
NTFS: there is no executable bit to read, so git reports spurious mode
changes forever. Fixing the index directly works on any platform, and the
lint rule catches the next occurrence.

**The correction within the correction.** The first advice given was to
`chmod +x` on the Linux side. That was withdrawn: it modifies the working
tree, which then blocks the `git pull` carrying the real fix, and it swept
in `scripts/common.sh`, which is sourced rather than run and should stay
`644`. The better answer while waiting for the fix is `sh ./go`, which needs
no executable bit and leaves the tree clean.

---

## 6. A package that no longer exists

**What happened.** `./go setup` failed on Ubuntu 26.04:
`Package 'liblz4-tool' has no installation candidate`. It was a transitional
package, dropped after 24.04, and is now `lz4`.

**What was done.** Rather than renaming it, the package list is filtered
against `apt-cache policy` at install time. Anything without an installation
candidate is skipped with a note. Names that are two spellings of the same
tool, `lz4` and `liblz4-tool`, are declared as a pair so the dropped one goes
quietly, and afterwards the script checks that each pair left a working
binary behind.

**Why that and not the alternative.** Swapping one name fixes today and
fails again on the next release, and this list has to survive twenty
projects across several years of distributions. The filter was tested
against a stubbed apt that reports packages missing, including the case
where both names of a pair are gone, which is the one that must warn rather
than fail silently.

---

## 7. A check that passed by not checking

**What happened.** `./go check` reported the compile step as
`libgpiod-dev absent, skipped`, and the message was wrong: `libgpiod-dev`
was present and `pkg-config` was missing. `pkg-config` had never been in the
host package list, and nothing else pulls it in.

**What was done.** `pkg-config` was added, with `pkgconf` as its alternative
name under the same pairing rule. The message now names the actual missing
tool. More importantly, a skipped compile now fails the run.

**Why that and not the alternative.** The alternative, printing a note and
passing, is the common pattern and is the worst possible behaviour for a
gate in front of a three hour build. In that run the script only reported
failure because shellcheck happened to be complaining about something else.
Without that coincidence it would have reported success, and the build would
have started with the daemon never once compiled.

A gate that can pass without checking is not a gate.

---

## 8. Four shellcheck warnings, two of them real

**What happened.** shellcheck reported `SC2034`, `SC2164` and two `SC2046`.

**What was done.**

| Warning | Verdict | Action |
|---|---|---|
| `SC2164` `cd` without a guard | Real | `cd "$REPO_DIR" \|\| die` |
| `SC2034` `REPO_DIR` unused | False positive: used by the scripts that source the file | Directive plus a comment saying why, and a guard added while there |
| `SC2046` twice, on `pkg-config` output | Intentional word splitting | Directive explaining that the output is a list of flags |

**Why that and not the alternative.** The alternative was to lower
shellcheck to advisory. Two of four were genuine faults, so advisory
warnings would mean re-reading and re-dismissing the same list forever. A
suppression with a written reason is a decision recorded once; an ignored
warning is a decision made again every time.

---

## 9. Reading a stale pull

**What happened.** Twice, output on the build machine contradicted fixes
that had already been made. Once because a commit had not been pushed, once
because it had not been pulled.

**What was done.** Both were diagnosed from line numbers rather than
guesswork: shellcheck flagged `common.sh` line 6 as the `REPO_DIR`
assignment, but in the fixed version line 6 is a comment and the assignment
is line 8. `git log --oneline -1` on both machines settles it in seconds.

**Why this is in the journal at all.** With two machines and a git remote
between them, "the code is wrong" and "this copy is old" produce identical
symptoms. Checking which one it is costs two seconds and is worth making a
reflex.

---

## 10. First build: 194 minutes, 5095 tasks, no failures

**What happened.** The first full build succeeded. 49 MB image, kernel
6.6.63, 36 warnings.

**What was done.** The warnings were checked rather than assumed benign. All
36 were one class: `do_fetch: Failed to fetch URL ... attempting MIRRORS`,
mostly `ftpmirror.gnu.org`. The primary was unreachable, the Yocto mirror
served it, and the completed build proves every one succeeded.

**Why that matters.** "There were 36 warnings" is not a result. Grouping
them takes one command and turns an unknown into a known, and the answer
here is that nothing in the layer is at fault.

The remaining single warning on later builds, that Ubuntu 26.04 is not in
`SANITY_TESTED_DISTROS`, is expected on a release this new.

---

## 11. The kernel fragment landed

**What happened.** `./go kconfig` reported all thirteen options present in
the built `.config`, including `CONFIG_GPIO_CDEV_V1` confirmed absent rather
than merely unrequested.

**Why the check exists.** A fragment that is silently ignored is the classic
Yocto trap: the build succeeds, the option is missing, a driver fails on the
board a week later with nothing to connect it to. Asking the build what it
actually produced costs one script and removes an entire class of late
failure.

It works only because `RM_WORK_EXCLUDE` keeps the kernel work directory,
which is a decision made much earlier for exactly this reason.

---

## 12. The warm rebuild: 21 seconds

**What happened.** A second build with no changes took 21 seconds.
`Sstate summary: 100% match, 100% complete`, 5091 of 5095 tasks reused.

**Why it is recorded.** 194 minutes to 21 seconds is the single most
convincing number about how Yocto behaves in daily use, and it is the
practical justification for keeping `DL_DIR` and `SSTATE_DIR` outside the
build tree. It also exposed a cosmetic bug: `build.sh` reported
`build took 0 min`, so it now reports seconds under a minute.

---

## 13. Four packages that could not be justified

**What happened.** The manifest listed 99 packages, four of them X11 client
libraries, in an image with no display: `libx11-6`, `libxau6`, `libxcb1`,
`libxdmcp6`.

**What was done.** The first guess was openssh with X11 forwarding. Rather
than acting on the guess, the build's own metadata was asked:

```sh
grep -H '^RDEPENDS' ~/bench/build/tmp/pkgdata/raspberrypi4-64/runtime/* | grep libx11
```

The answer was **dbus**, not openssh. The poky distro carries `x11` in
`DISTRO_FEATURES`, so dbus is built with X11 autolaunch: the feature that
starts a session bus by talking to an X display, which a headless board can
never use.

The fix is a bbappend with `PACKAGECONFIG:remove = "x11"`.

**Why that and not the alternative.** Removing `x11` from `DISTRO_FEATURES`
would also work and is arguably more correct for a headless image. It was
rejected because it invalidates shared-state signatures across the whole
build for a four-package saving, where the bbappend rebuilds one recipe.
Project 13 will want graphics, and it wants Wayland rather than X11, so the
distro feature is not being kept for its benefit either.

**A wrong guess, recorded on purpose.** The first attempt to read the
dependency graph also used the wrong path: `buildhistory` sanitises the
machine name to `raspberrypi4_64` with an underscore. The habit worth taking
from this is to locate the file rather than predict it, and to ask the build
rather than reason about it from memory.

---

## 14. A rebuild that rebuilt nothing

**What happened.** After the dbus fix, a pull and rebuild still reported 99
packages.

**What was done.** The output was read rather than rerun. Four independent
signals said nothing had changed:

| Signal | Meaning |
|---|---|
| `Sstate summary: Wanted 136 Local 136 ... 100% match` | Every signature already had a cached artefact |
| `5091 of 5095 didn't need to be rerun` | dbus was not among the four |
| Image timestamp unchanged | The same artefact as the previous build |
| The pull's file list | No `meta-bench/recipes-core/dbus/` in it |

The fix was staged but never committed, so it had not been pushed and could
not have been pulled.

**Why this is worth writing down.** The instinct after an unexpected result
is to run it again. Reading the output first cost thirty seconds and gave a
definite answer, where a rerun would have produced the same 99 packages and
no information. A Yocto build tells you what it did if you let it.

---

## 15. The same command, after the push: 95 packages

**What happened.** With the commit actually pushed and pulled, the identical
command produced a different build, and the output says why:

| Signal | Before | After |
|---|---|---|
| Sstate summary | `100% match, 100% complete` | `84% match, 98% complete`, 25 missed |
| Stale objects removed | none | 19 for cortexa72, 4 for raspberrypi4_64 |
| Tasks attempted | 5095 | 5057, so 38 fewer exist at all |
| Recipes parsed | all cached | `1920 cached, 1 parsed`, the new bbappend |
| Image | 49 MB | 48 MB |
| Packages | 99 | **95** |
| Wall clock | 21 s | 2 min 31 s |

**What this confirms.** Removing one `PACKAGECONFIG` from dbus dropped
`libx11-6`, `libxau6`, `libxcb1` and `libxdmcp6`, and with them 38 build
tasks that no longer needed to exist. The four X11 packages in a headless
image are gone, and the acceptance criterion that every package can be
justified is now met for all 95.

**A detail worth noticing.** `Removing 19 stale sstate objects` is BitBake
garbage-collecting cache entries whose signatures can never be needed again,
because the recipe that would ask for them has changed. It is the same
signature mechanism from the other direction.

**And the cosmetic fix landed too:** `build took 2 min 31 s` rather than the
previous `0 min`.

---

## 16. Four hours on a board that was working

**What happened.** The first flashed card appeared not to boot. The serial
console showed nothing, the touchscreen showed a grey backlight, and the
green activity LED flickered briefly and stopped. Every symptom pointed at a
board that read the card and then failed.

**What was done.** Four edits were made directly to the card, since
`config.txt` and `cmdline.txt` are on a FAT partition and need no rebuild:
`uart_2ndstage=1` to make the firmware narrate, `arm_64bit=1` on the theory
that the firmware was looking for the wrong kernel filename,
`dtoverlay=vc4-kms-dsi-7inch` for the panel, and `console=tty1` so the kernel
would print somewhere other than the serial port. The next boot reached a
login prompt on the touchscreen.

**What it actually was.** The board had been booting correctly since the
first flash. Two independent faults hid it:

1. The serial wiring never worked. A loopback test, done far too late,
   proved the cable good up to its own connector, so the break was between
   the connector and the header.
2. `grep -rn arm_64bit ~/bench/meta-raspberrypi/` returns nothing. The BSP
   never sets it, because the firmware defaults to 64-bit on a BCM2711. That
   edit changed nothing at all.

So of the four edits, only the console pair mattered, and they did not fix
the boot. They fixed the ability to watch it.

**The tell that was missed.** `uart_2ndstage=1` makes the *firmware* log over
the UART, before any kernel exists. It produced nothing. Firmware logging is
independent of the kernel, the device tree and the rootfs, so silence there
could only mean the wire. That was known roughly three hours before it was
acted on.

**Why the LEDs never lit either.** They are Joy-IT LinkerKit LK-LED10
modules, which have a 2.0 mm socket and require a LinkerKit baseboard and
cable. The jumper wires in use are 2.54 mm Dupont. They cannot mate. Every
polarity test was driving pins into open air. The datasheet says a baseboard
and cable are required, in one line, and nobody read it until the end.

**What changed in the layer.** An image whose only console is a serial port
is undebuggable the day that serial port fails, which is what happened. The
kas file now sets both consoles and names the panel overlay, so a freshly
flashed card reaches a visible login prompt with no hand edits:

```
CMDLINE_CONSOLE = "console=serial0,115200 console=tty1"
RPI_EXTRA_CONFIG = "dtoverlay=vc4-kms-dsi-7inch"
```

**Why that and not the alternative.** The alternative was to keep the
single serial console and treat this as a wiring accident. It is not an
accident: a bench board is going to lose its console cable again, and the
cost of a second console is one line of configuration against hours of
indistinguishable symptoms.

**The lesson, which is the reason this entry exists.** When the instrument
and the subject are both silent, suspect the instrument. Validate the
instrument before trusting its readings. The loopback test takes ten seconds
and belongs *before* the first power-on, not after four hours of debugging a
board that was already printing a login prompt into a disconnected wire.

---

## 17. Reproducible, and a full disk

**What happened.** `./go reproduce` built the tagged commit a second time in
its own tree with its own sstate cache. Both builds produced exactly 95
packages and `diff` reported nothing. The narrow claim holds, with evidence
in `docs/evidence/reproduce.txt`.

Then the SDK build died in a way that had nothing to do with Yocto:

```
OSError(30, 'Read-only file system')
[Errno 5] Input/output error
Bus error
```

**What it actually was.** The Windows drive behind WSL had reached **zero
bytes free**. The virtual disk grows on demand out of host space, so when
Windows ran out, the guest could not allocate blocks, and ext4 did what
`errors=remount-ro` says it should: it went read-only mid-build.

Three full builds had accumulated: the original, the reproduce run with its
own tree and cache, and the SDK. 63.6 GB of virtual disk against a system
drive that was already nearly full for unrelated reasons.

**What was done.** `powercfg /h off` freed the hibernation file and bought
enough headroom to restart WSL. The reproduce result was captured *before*
deleting anything, because the tree about to be reclaimed held the only copy
of the evidence. Then the second build tree and `build/tmp` went, and the
virtual disk was compacted so the space returned to Windows.

**Why the guard did not fire.** `require_disk_gb` checks the directory it is
given, which under WSL reports the virtual disk's maximum size. It said 919
GB free while Windows had none. The check was not wrong so much as looking
at the wrong number.

`require_host_disk_gb` now checks `/mnt/c` as well when it exists, because
that is where the space actually comes from. `./go build` and `./go sdk`
want 25 GB there, `./go reproduce` wants 60 GB, since it needs a second full
tree.

**Why that and not the alternative.** The alternative was to treat it as a
one-off and remember to watch the host drive. Nobody remembers. The guard is
four lines and turns an exhausted disk into a refusal at second one rather
than a corrupted build tree at hour two, which is the same reasoning as the
case-sensitivity probe and the missing-tool check.

**The lesson.** A measurement can be precise and still be of the wrong
thing. The guest filesystem answered the question it was asked, honestly,
and the answer was useless, because under WSL the number that matters lives
on the other side of a virtual disk.

---

## 18. Thirteen red runs nobody read

**What happened.** CI failed on every push from the very first one. Thirteen
consecutive red runs over two days, each sending an email, while the work
carried on and the workflow was repeatedly described as the thing that would
catch mistakes.

**Seventeen failures, in full.** Newest last. The step column is where the
job died; durations are from `gh run list`.

| # | Commit being tested | Sec | Died at | Cause |
|---|---|---|---|---|
| 1 | one repository for the twenty projects | 17 | shellcheck | A |
| 2 | host-setup: survive package renames | 21 | shellcheck | A |
| 3 | docs: why each host package is installed | 19 | shellcheck | A |
| 4 | host-check: pkg-config was missing | 23 | shellcheck | A |
| 5 | walkthrough: why the repository is built this way | 27 | shellcheck | A |
| 6 | project 01: first build measured | 25 | shellcheck | A |
| 7 | dbus: drop x11 autolaunch | 19 | shellcheck | A |
| 8 | project 01: journal of the build | 43 | shellcheck | A |
| 9 | bench-image: a console you can actually see | 20 | shellcheck | A |
| 10 | project 01: defer the LED indication | 20 | shellcheck | A |
| 11 | project 01: console is the panel and SSH | 25 | shellcheck | A |
| 12 | bench-provision: German keymap and WiFi | 19 | shellcheck | A |
| 13 | scripts: refuse a second BitBake run | 18 | shellcheck | A |
| 14 | shellcheck: an explicit if for SC2015 | 21 | compile | B |
| 15 | shellcheck: find shell files rather than listing them | 21 | compile | B |
| 16 | ci: pin the runner, ubuntu-latest carries libgpiod v1 | 22 | compile | B |
| 17 | ci: build libgpiod v2 from a pinned tag | 18 | clone | C |
| 18 | ci: pin libgpiod to v2.1.3 from kernel.org | 71 | passed | |

**The durations are the tell.** Everything under about 30 seconds died
before the runner had finished installing packages and compiling. The first
green run took 71 seconds precisely because it finally reached the work:
building a library, compiling twice and running thirteen tests. Run 8's 43
seconds is the one outlier and reflects a slower runner rather than a
different fault.

Cause **A** is one `info`-level shellcheck note, `SC2015`, in a line of
`scripts/reproduce.sh` written in the very first commit. The log was read
for run 13 and named it; it was present and unchanged in every run before
that. **Thirteen pushes went out while a one-line fix sat unread.**

Cause **B** is libgpiod. Runs 14 and 15 got past shellcheck and died in the
compile with forty lines of implicit-declaration errors, gcc helpfully
suggesting v1 symbol names. Run 16 added a version check and said it in one
sentence instead: `This runner has libgpiod v1.6.3; the daemon targets v2.`
Same cause, legible output, which is the difference the check was for.

Cause **C** is a tag I guessed. `v2.1` does not exist on the GitHub mirror,
which carries only recent tags. `git ls-remote --tags` would have said so
before the push rather than after.

**Three causes, found in sequence.**

1. `SC2015` in `scripts/reproduce.sh`, an *info*-level style note about
   `A && B || C`. shellcheck exits non-zero on any finding, so one note
   failed the job.
2. The shellcheck invocation named its files by hand, and
   `bench-wifi-setup` never joined the list. A script written that evening
   had never been checked by anything.
3. The real one: GitHub's `ubuntu-latest` ships **libgpiod 1.6.3**. The
   daemon targets v2. Forty lines of implicit-declaration errors, with gcc
   helpfully suggesting v1 names like `gpiod_line_iter_new`. Ubuntu did not
   package v2 until 24.10, so no LTS runner image has it.

**What was done.** An explicit `if` for the style note. Both the CI step and
`./go check` now *find* shell files rather than listing them, by shebang and
by extension, so a new script cannot escape. And libgpiod is built in CI
from tag `v2.1.3` taken from kernel.org, which is the series the target
image carries.

**Why that and not the alternative.** Two easier options were rejected.
Lowering shellcheck's severity so `info` findings do not fail would mean
re-reading and re-dismissing the same list forever. Skipping the compile
when v2 is absent would be a gate that passes by not checking, which is the
same fault as the skipped `pkg-config` compile in entry 7.

**A guess that cost a round trip.** The first attempt pinned tag `v2.1` on
the GitHub mirror. It does not exist there: the mirror carries only recent
tags. One `git ls-remote --tags` would have said so, and that is the third
time in this project that guessing cost more than asking.

**The lesson.** A check nobody reads is not a check. CI was correct from run
one and said so thirteen times. And the CI environment is a dependency like
any other: `ubuntu-latest` is a moving target in exactly the way a git
branch is, and the fix was the same as everywhere else in this repository,
which is to name the version.

---

## 19. Firmware without a driver

**What happened.** The WiFi image booted, and `networkctl` listed no `wlan0`
at all. Not down, not unconfigured: absent.

**What was done.** Two commands, rather than a theory.

`ls /lib/firmware/brcm` was full of `brcmfmac43455-sdio.*` files, including
the `raspberrypi,4-model-b` variants. The firmware package had installed
exactly what it promised.

`dmesg | grep -i brcm` returned `brcm-pcie`, `brcmstb-i2c` and
`irq_brcmstb_l2`, and no `brcmfmac` line anywhere. The driver had never
probed.

`find /lib/modules -name "brcmfmac*"` returned nothing, which settled it.

**What it actually was.** `core-image-minimal` installs no kernel modules.
The manifest had been saying so the whole time: the only two present were
`kernel-module-ipv6` and `kernel-module-sch-fq-codel`, both dragged in by
something else. The Raspberry Pi kernel builds `brcmfmac` as a module, so
the image had the firmware, the supplicant, the netlink libraries and the
network configuration, and nothing at all to drive the radio.

**The fix** is one line, `kernel-module-brcmfmac` in `IMAGE_INSTALL`. Yocto
splits the kernel into per-module packages and resolves their dependencies
from the modules' own metadata, so that one pulls `brcmutil`, `cfg80211` and
`mac80211` behind it.

**Why that and not the alternative.** `kernel-modules` installs every module
the kernel built, which is tens of megabytes and would quietly end the
"every package can be justified" criterion. Naming the one driver keeps the
image explicable.

**The mistake was mine and it has a shape.** I added a firmware package and
a userspace daemon and never asked whether the kernel side existed, because
"the Pi has WiFi" and "the kernel supports WiFi" felt like they implied "the
image can use WiFi". They do not. An image contains exactly what was asked
for, which is the whole point of building one, and that cuts both ways.

The tell was in the manifest from the first build: 95 packages and only two
kernel modules. It was read several times, including while justifying every
package in it, and the absence was never noticed. Absences are harder to see
than mistakes.

---

## 20. The driver was not enough either

**What happened.** With `kernel-module-brcmfmac` in the image, rebuilt and
reflashed, `networkctl` still listed no `wlan0` at all. Identical symptom to
entry 19, different cause.

**What was done.** `lsmod` showed `brcmfmac` loaded with a usage count of
**0**: the driver was in memory and no device was bound to it.
`ls /sys/bus/sdio/devices` showed three function devices, so the radio had
enumerated. `dmesg | grep -i brcmf` gave the answer in one line:

```
brcmf_fwvid_request_module: mod=wcc: failed 256
brcmf_attach: brcmf_fwvid_attach failed
brcmf_sdio_firmware_callback: brcmf_attach failed
```

Modern `brcmfmac` splits its vendor-specific half into a separate module and
asks for it by name at probe time. `wcc` is the Cypress and Infineon
variant, which is what the Pi 4 carries. `bca` is the Broadcom one.

**The fix** is `kernel-module-brcmfmac-wcc` in the image.

## Why `wlan0` was empty, in full

Four distinct states, three of them looking the same from `networkctl`. The
command that distinguished each one is the useful column.

| State | What `networkctl` showed | Cause | The command that proved it |
|---|---|---|---|
| 1 | No `wlan0` | No driver in the image. `core-image-minimal` ships no kernel modules | `find /lib/modules -name "brcmfmac*"` returned nothing |
| 2 | No `wlan0` | Driver present but no vendor module. `brcmfmac` loaded, bound to nothing | `lsmod` showed `brcmfmac` with usage count **0**, and `dmesg` said `mod=wcc: failed 256` |
| 3 | `wlan0`, `no-carrier` | Driver attached, supplicant never configured | `journalctl -u bench-wifi-setup` said `/boot/wifi.conf has no PSK= line` |
| 4 | `wlan0`, `routable` | Working | |

State 3 had its own sub-cause, which is entry 21: the `PSK` line *was* in
the file, and the parser could not see it because the file had no trailing
newline.

Things that were present and correct the entire time, and therefore never
the problem: the firmware blobs in `/lib/firmware/brcm`, the SDIO card at
`mmc1`, the three SDIO function devices, the network file for `wlan0`, and
the credentials on the card.

**Each absence looked identical, and that is the lesson.** Firmware, driver,
vendor module: three layers, one symptom. I added them one at a time across
an evening because each time I fixed the layer I could see, I assumed it was
the last one. The faster route was available at every step: read `dmesg` for
what the kernel itself was complaining about, rather than reasoning about
what an image ought to contain. At state 2 the driver said `mod=wcc` by
name, which is more specific than anything inference would have produced.

**What would have been faster.** Reading `dmesg` for the driver's own
complaint, rather than reasoning about what the image ought to contain. The
driver said exactly what it wanted, by name, the first time it was asked.

---

## 21. Three ways Windows breaks a text file

**What happened.** The board had WiFi hardware working and would not
associate. `bench-wifi-setup` refused the credentials file with
`/boot/wifi.conf has no PSK= line`, while `cat` on the board appeared to
show only an `SSID=` line.

**What was done.** I concluded the `PSK` line was missing and said so. The
reply was "no it's there, see image". It was there.

`od -c` settled it: the file ended `"` with **no trailing newline**. The
parser is `while IFS='=' read -r key value; do`, and `read` returns false on
an unterminated final line, so the loop exits *before* the body runs. The
last key in the file is silently dropped. Notepad does not write a final
newline.

The fix is the standard idiom, `|| [ -n "$key" ]`, which runs the body once
more when `read` hits data with no newline after it.

**That was the third of three.** This one small script now handles:

| Trap | Symptom | Handling |
|---|---|---|
| CRLF line endings | `ssid` contains a stray carriage return | `tr -d` on both values |
| UTF-8 byte order mark | The first key is unrecognisable | `tr -cd` on the key, which drops any non-alphanumeric byte |
| No final newline | The last key is silently ignored | `|| [ -n "$key" ]` on the read loop |

All three have tests. The first two were written defensively before anyone
hit them. The third was found on hardware, at two in the morning, because
the user did not accept my reading of `cat`.

**Why that matters more than the bug.** I had evidence, `cat` showing one
line, and treated it as proof of the file's contents rather than as a
rendering of them. `od -c` was one command away the whole time and shows
bytes rather than an interpretation. The lesson from entry 13 was to ask the
build rather than reason from memory; this is the same lesson about a file.

---

## 22. Measuring what the build tree no longer has

**What happened.** `./go kconfig` failed with "no built kernel .config
found", despite `RM_WORK_EXCLUDE` naming `linux-raspberrypi` precisely to
prevent that.

**What it actually was.** `RM_WORK_EXCLUDE` preserves a work directory that
a build creates. After `build/tmp` was deleted during the disk recovery,
every subsequent build was a complete shared-state hit, so the kernel was
never compiled and no work directory ever existed to preserve. The setting
was working; there was simply nothing for it to protect.

**What was done.** Two changes rather than one.

`./go kconfig` now takes an optional path, so it can check any config rather
than only one it finds in the build tree.

And `CONFIG_IKCONFIG=y` with `CONFIG_IKCONFIG_PROC=y` went into the kernel
fragment, which gives `/proc/config.gz` on the board. That turns the
criterion from "the fragment reached a build directory" into "the fragment
reached the kernel that is currently executing", which is a stronger claim
and checkable at any time on any flashed card.

**Why that and not the alternative.** The alternative was
`bitbake -c compile -f virtual/kernel`, forcing a kernel rebuild to
recreate the work directory. It costs the same fifteen minutes as the
fragment change, produces evidence about a build tree rather than about
hardware, and has to be repeated every time the tree is cleaned.

**A smaller version of the same thing.** `systemd-analyze` is not in the
image, so the boot-time criterion looked unmeasurable. systemd logs the
figure to its own journal at the end of startup, so the number was already
there: 8.330 s, 3.183 kernel plus 5.146 userspace, against a 15 s
criterion. The tool was missing; the measurement was not.

---

## 23. The SDK, and a command that lied

**What happened.** `./go sdk` built the installer in a couple of minutes,
because the run that died on the full disk had already done the work: 6264
tasks, 6231 restored from shared state.

Then `./go sdk install` ran a **build** instead of an installer. The `go`
script had `sdk) exec sh ./scripts/sdk.sh build ;;`, which matches on the
first word and drops everything after it. The word `install` went nowhere.

**Why that is worse than an error.** It did not fail. It printed a plausible
build log and finished successfully, and only the absence of an installer
prompt gave it away. A command that quietly does the wrong thing is the same
fault as the skipped compile in entry 7: the failure was invisible. Fixed by
passing the subcommand through.

**Then it worked.** The environment script supplied everything:

```
aarch64-poky-linux-gcc -mcpu=cortex-a72+crc -mbranch-protection=standard
  -fstack-protector-strong --sysroot=/opt/poky/5.0.20/sysroots/cortexa72-poky-linux
  ... -lgpiod
aarch64 binary: SDK is cross
```

None of that is in the Makefile, which names no compiler and no sysroot.

On the board:

```
hello-gpiod, libgpiod 2.1.3
  /dev/gpiochip0     pinctrl-bcm2711      58 lines
  /dev/gpiochip1     raspberrypi-exp-gpio 8 lines
```

**Two things that confirmed earlier guesses rather than leaving them
assumed.** The target carries libgpiod **2.1.3**, which is exactly the tag
CI was pinned to after `v2.1` turned out not to exist on the GitHub mirror.
That pin was chosen on the belief that scarthgap ships the 2.1 line, and
this is the first evidence for it. And the second chip, the
`raspberrypi-exp-gpio` expander, is the reason matching the GPIO chip by
label rather than by index was worth the forty lines it cost.

**That closes Project 01.** Every criterion met, two items deferred with
written reasons.

---

## 24. The documentation still pointed outside the repository

**What happened.** These twenty projects were scoped in a separate document
that is not in this tree, and the text written for Project 1 kept referring
to it. One README section was headed as a comparison against that outside
document; the design document said the same four figures were also rendered
as vector drawings in files it named by path; the kernel fragment justified
an option by saying no project in that outside document used it. None of
that is readable by someone who has only this repository, which is everyone
who will ever find it.

Worse, it made two claims uncheckable. Naming an outside document as the
specification tells a reader that a specification exists and that they do
not have it. "The acceptance criteria require a state file" asserts a
requirement whose text is then elsewhere.

**What was done.** Every reference removed, and in each place the content
replaced the citation rather than the sentence being deleted:

- The eleven acceptance criteria were already written out in the README's
  verification table, so that section needed nothing.
- The comparison section became "Where this differs from the original
  plan", and each of its items now says what the original asked for inside
  the item itself. While checking it, the introduction turned out to say
  "four things" above a list of six; corrected.
- `docs/DESIGN.md` lost its pointer to the external figure sources. The
  figures themselves were already here as ASCII and mermaid, which was the
  point of drawing them that way.
- `bench.cfg` now says "if no project in this repository uses it".
- The workflow diagram in the walkthrough showed the repository nested
  inside the outside document's tree. It now shows the repository alone, and
  says that the three-machine split is this bench rather than a
  recommendation.
- One Buildroot comparison in the README named another piece of work without
  explaining it. It now states the trade directly and points at
  `walkthrough/02-build-systems.md`, which is in this repository.

**Why that and not the alternative.** The cheap fix is to delete every
sentence that points outward. It takes ten minutes and it costs the
reasoning: "six things are done differently" is only worth reading if the
reader can see what they differ from. Writing the original requirement into
the sentence keeps the comparison and removes the dependency.

The rule is now recorded as Decision 29 and in the root README, because it
has to hold for the eighteen projects not yet written. A convention that
lives only in a diff is a convention that lasts one project.

---

## 25. The radio was in the image, in the manifest, and on a path the kernel never searches

Found on 17 September 2026 while trying to get the board back on the
network after Project 8's matrix. It took about an hour, it did not
converge, and most of what is worth keeping is about how it was chased
rather than about the defect.

**The symptom.** `ip addr show wlan0` answered `can't find device`. Not a
down interface: no interface at all.

**Four wrong hypotheses, in order, each one disproved by the next
command.** That the card had been flashed without a `/boot/wifi.conf`.
That `bench-wifi-setup` had failed. That the licence flag for the
proprietary firmware had not been accepted, so the package never built.
That the two kernels sharing `/lib/modules/6.12.93-v8` had overwritten
each other's modules. Every one of them was plausible, every one was
wrong, and the fourth was wrong even though the collision it describes is
real and still open.

**What it actually was.** `brcmfmac` loaded, found the chip, asked for
`brcm/brcmfmac43455-sdio.bin` and got ENOENT. The firmware is in
`/usr/lib/firmware/brcm/`. The kernel's firmware loader searches
`/lib/firmware`. On this image `/lib` is a **real directory**, not a
symlink to `/usr/lib`, so the two never meet.

Proved at runtime without a rebuild, which is the part worth keeping:

    echo -n /usr/lib/firmware > /sys/module/firmware_class/parameters/path
    modprobe -r brcmfmac; modprobe brcmfmac

and `wlan0` appeared, with the firmware announcing itself as
`BCM4345/6 wl0 version 7.45.265`.

**The recipe was right the whole time.** `bench-image.bb` names
`linux-firmware-rpidistro-bcm43455` and both driver modules.
`bench-rpi4.yml` accepts `synaptics-killswitch`. All three archived images
list the package in their manifests. Every artefact said the radio was
installed and the radio was installed. A manifest records what was put
into an image and says nothing about whether anything can find it.

**A second defect in the same output.** `regulatory.db` also fails with
ENOENT and does not come back when the path is changed, so it is not in
the image at all. `cfg80211` falls back to the built-in world domain,
which is why the `country=` string in the supplicant config is currently
moot. `wireless-regdb` is missing.

**A third, in `bench-wifi-setup`.** It writes `psk=%s` verbatim. An
unquoted value means a 64 character hex key to wpa_supplicant, so a bare
passphrase is rejected and the network block fails to parse. The script's
own header documents that a passphrase must be wrapped in double quotes
and the script does not check, then prints `configured wlan0 for ...` and
exits 0. The card on this bench had a bare 12 character passphrase, so
this image could not have associated even with the firmware present.

**And a fourth, which was mine.** `sed -i 's/^PSK=\(.*\)$/PSK="\1"/'`
on the FAT partition was supposed to add those quotes. Afterwards
wpa_supplicant reported `psk '""'`, an empty quoted string: the value was
gone. A repair turned into damage on a file holding a credential that is
not recoverable from anywhere in this repository, by design. The measured
length was 16 characters before and the quotes were empty after, and the
step in between is not explained.

### What this cost, and the rule that comes out of it

The honest move an hour earlier was to say **this needs a rebuild, so
stop**. The firmware path cannot be fixed from a console. Once that was
clear, every further command on the board was diagnosis for its own sake,
and it ran until Joseph said it was not converging, which it was not.

Two smaller things that cost real round trips:

- **The board is BusyBox.** `head -20` fails and needs `head -n 20`.
  `cat -A` does not exist. `sed -n l` prints nothing. Three exchanges went
  on GNU habits rather than on the board.
- **Log output in a fenced block gets pasted into the shell.** It happened
  three times, because a fence reads as "run this". Quote log lines
  inline, and reserve fences for commands.

### What has to change in the image

Both need a build and neither is done:

- A `/lib/firmware` symlink to `${libdir}/firmware` in `bench-image.bb`,
  next to the comment that already explains why the driver and the
  firmware are both named there. That comment records half of this
  lesson. This is the better half, because "firmware present, driver
  present, and still no radio" is the failure that looks like nothing is
  wrong.
- `wireless-regdb`, so `cfg80211` has a database to read.

And `bench-wifi-setup` should accept 64 hex characters bare, accept an
already quoted value, quote a bare passphrase of 8 to 63 characters
itself, and refuse anything else by name.

## Still open

**Project 01 is complete.** Eleven of eleven criteria met, four evidence
artefacts captured in `docs/evidence/`.

**Three image defects found on 17 September 2026 and not yet fixed**, all
of them needing a rebuild. Entry 25 has the detail. `/lib/firmware` is not
a symlink to `${libdir}/firmware`, so the radio firmware is installed and
unreachable. `wireless-regdb` is absent. And `bench-wifi-setup` writes a
passphrase through unvalidated, so an unquoted one is rejected by
wpa_supplicant while the setup script reports success.

Two optional transcripts remain, and neither changes a result:

- `state-transition.txt`. The transition was observed on the board, `ok`
  then `failed`, and is recorded in the verification table; only the
  transcript is missing.
- `kconfig-check.txt`, which needs the next flash, because the check now
  reads `/proc/config.gz` from the running board rather than a build tree.

Deferred with written reasons rather than open: the LED indication, because
the LinkerKit modules cannot be connected with the cables available, and the
serial console, which Project 2 makes mandatory.

**A possible way out of the serial console deferral, found in Project 15.**
The reason that console was never exercised is that this bench's USB/TTL
cable is a PL2303HXA, a generation Windows refuses to drive, so there was no
adapter rather than no interest.

The SIM7600E-H HAT has two micro-USB sockets. One is the module's own USB
interface, which is the data path; the other is a USB-to-serial bridge chip
on the HAT itself, put there so a PC can send AT commands without a Pi.
Those bridges are CP2102 or CH340 parts and Windows drives both without
argument, so the bench now owns a bridge chip that works.

Whether it can serve as a Pi console adapter is one look at the HAT's
silkscreen. Out of the box the bridge is wired to the **modem's** UART, not
to the header, so it is a PC-to-modem channel. It becomes a console adapter
only if that HAT revision exposes the bridge's TX and RX as pins on its
jumper block, which some Waveshare revisions do and others do not. If they
are there, jumper them to the Pi's GPIO15 and GPIO14.

Two things would still be needed after that: the Pi's console has to be
freed from `serial0`, since `CMDLINE:append` now puts `console=tty1` there
as well, and Project 15's `ModemManager.conf` strict filter plus the
`ID_MM_PORT_IGNORE` udev rules exist precisely to keep ModemManager off that
UART. Recorded rather than chased. Project 15's journal, entry 19.

One loose end outside the repository: the build laptop's `git push` is
refused by a token scope, so `packages.txt` was transcribed and committed
from the other machine instead. `gh auth refresh -s repo` there, and a
`git reset --hard origin/main` to drop the stranded duplicate commit.

**A correction that belongs here.** Earlier entries and the project README
listed the `kbd` and `keymaps` packages as unjustified, on the grounds that
a board reached over serial and SSH does not need console keymaps. That was
wrong for this bench: the console is a touchscreen with a German keyboard,
`bench-provision` depends on those packages to set `KEYMAP=de`, and acting
on the recommendation would have broken the console this project is used
through. The lesson is narrow and worth keeping: a package that looks
unnecessary in the abstract may be load-bearing for how the thing is
actually used.

---

## The practice, for the other nineteen projects

Keep one of these per project. Write the entry when the surprise happens,
not afterwards, because the reasoning is what fades and the outcome is what
survives.

Three habits earned their place here and are worth repeating:

1. **Ask the build, do not reason from memory.** `pkgdata`, `buildhistory`,
   `bitbake -e` and `bitbake -S printdiff` answer questions that guesswork
   gets wrong. The X11 trace is the example: the guess was confident and
   incorrect.
2. **Read the output before rerunning.** An unexpected result usually
   contains its own explanation.
3. **When something fails late and unrecognisably, add a check where the
   cause is.** The executable bit, the case-sensitive filesystem, the kernel
   fragment and the skipped compile are all the same pattern.
