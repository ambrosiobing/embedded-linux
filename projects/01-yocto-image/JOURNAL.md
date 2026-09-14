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

## Still open

- `kbd`, `kbd-consolefonts`, `kbd-keymaps`, `kbd-keymaps-pine`, `keymaps`,
  `update-rc.d` and `update-alternatives-opkg` remain unjustified. All come
  from `packagegroup-core-boot`, so trimming them means overriding a
  packagegroup, which is a larger change than a `PACKAGECONFIG` and has not
  been attempted yet.
- No board has booted. The SDK has not been generated.
- `./go reproduce` has not been run.

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
