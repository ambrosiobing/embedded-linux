# Journal: Project 13

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled
list of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that
and not the alternative**.

All entries are 21 September 2026 unless noted.

---

## 1. The primary compositor is in none of the layers this bench uses

**What happened.** The specification's teaching vehicle is `cage`, chosen
because it is small: one application, one output, and the whole
configuration in a systemd unit. Before writing anything, the recipe was
looked for.

It is not in any of the three. Nor is `wlroots`, which it is built on.
Directory listings rather than guesses, because a wrong path had already
produced two false negatives in this session:

| | oe-core scarthgap | meta-oe scarthgap | meta-raspberrypi |
|---|---|---|---|
| `cage` | no | no | no |
| `wlroots` | no | no | no |
| `weston` | **13.0.1** | | |
| `seatd` | **`meta/recipes-core/seatd`** | | |
| `libinput` | **1.25.0** | | |

**That table is correct and its scope is the whole point.** It says
nothing about layers this bench does not use, and entry 11 is what
happened when that distinction was not kept.

**What was done.** Asked, rather than decided alone, because the two
options looked like materially different amounts of work. The answer was
weston, which is also what the specification names as the sanctioned
alternative.

**Why that and not the alternative.** The reason given at the time was
that packaging wlroots would be roughly a week before any dashboard
appeared. **That reason was wrong, and entry 11 is the correction.** The
decision survived it; the argument did not.

---

## 2. Three wrong paths in one session, and what they cost

**What happened.** Three times, a `curl` against a guessed path returned
404 and the conclusion "it is not packaged" was one step away:

| Guessed | Actually at |
|---|---|
| `meta/recipes-graphics/weston` | `meta/recipes-graphics/wayland/weston_13.0.1.bb` |
| `meta/recipes-graphics/libinput` | `meta/recipes-graphics/wayland/libinput_1.25.0.bb` |
| `meta/recipes-graphics/seatd` | `meta/recipes-core/seatd` |

The third was caught only because weston's own `PACKAGECONFIG[kms]`
lists `seatd` as a dependency, which it could not do if seatd were
absent. The recipe contradicted the conclusion.

**What was done.** Stopped probing paths and listed the directories.
Every later claim about what exists came from a listing.

**Why this is an entry.** It is the same failure Project 9 hit with
`grep '^config KFENCE'`, which found nothing because the symbol is a
`menuconfig`. **A tool chose its own input, reported on what it chose,
and did not say what it had excluded.** Three times in one session, on a
question ("is this packaged") where a false negative causes a week of
unnecessary work.

---

## 3. LVGL 9.1.0 has no Wayland driver, and meta-oe pins it

**What happened.** meta-oe carries `lvgl_9.1.0.bb`, which looked like a
gift: the toolkit already packaged. It is not usable here.

`src/drivers/` at that revision holds display, evdev, libinput, nuttx,
sdl, windows and x11. **There is no wayland directory**, and
`lv_conf_template.h` at that revision has no `LV_USE_WAYLAND` line at
all. The driver appears in 9.2.0.

**What was done.** `bench-hmi` vendors its own LVGL at v9.3.0, the way
oe-core's own `lvgl-demo-fb` fetches two repositories. meta-oe's recipe
is left untouched.

**Why that and not a bbappend bumping it.** meta-oe's recipe is pinned at
9.1.0 and carries three patches written against that revision. Bumping it
from a bbappend would apply them to a tree they do not fit, for every
consumer in the layer index, to solve a problem local to this project.

**The part that matters beyond this project.** meta-oe sets LVGL's
options by running `sed` over `lv_conf.h`. **A sed whose pattern matches
nothing changes nothing and reports success.** Adding `LV_USE_WAYLAND`
there would produce no error, no warning and no effect: a build that
succeeds and a binary with no Wayland support. That is precisely the
shape of Project 9's promptless Kconfig symbols, in a different tool, and
it is why `bench-hmi` reads its generated `lv_conf.h` back and fails the
build with the symbol name and the line actually present.

---

## 4. The license checksum changed between the two versions

**What happened.** Having decided to vendor LVGL, the obvious move was to
copy meta-oe's `LIC_FILES_CHKSUM` for `LICENCE.txt`.

**What was done.** Computed it instead:

```
  9.1.0  bf1198c89ae87f043108cea62460b03a
  9.3.0  4570b6241b4fced1d1d18eb691a0e083
```

**Why this is an entry.** It is a thirty second check that prevents a
build failure whose message is about a license file and whose cause is a
copied constant. The general form is the one this repository keeps
meeting: **a value that was correct for the thing it was written about,
carried to a different thing.**

---

## 5. Poky does not supply the distro feature weston requires

**What happened.** weston's `required-distro-features.inc`:

```
REQUIRED_DISTRO_FEATURES = "wayland opengl \
    ${@oe.utils.conditional('VIRTUAL-RUNTIME_init_manager',
                            'systemd', 'pam', '', d)}"
```

This bench sets `INIT_MANAGER = "systemd"`, so `pam` is required. Poky
supplies `wayland` and `opengl` and **not** `pam`.

**What was done.** `DISTRO_FEATURES:append = " pam"` in
`kas/bench-kiosk.yml`, and only there.

**Why not in the shared base.** It is a distro-wide change that rebuilds
a great deal and alters every other image in this repository. Project 3
measures boot time and kernel size, and a silently different distro
underneath those numbers is exactly the comparison failure Project 8 made
once with `BENCH_RT_LAB`. One project's requirement stays in one
project's configuration.

---

## 6. The screen already had an owner

**What happened.** Writing the ownership table, the DSI panel looked like
a fresh resource. It is not: `kas/bench-rpi4.yml` has set
`dtoverlay=vc4-kms-dsi-7inch` and appended `console=tty1` since Project 1,
with a comment calling the panel the bench console. **Every bench image
already drives this screen and runs a getty on it.**

**What was done.** Read oe-core's `weston-init` unit before writing one.
It uses **tty7**, not tty1, runs as a dedicated `weston` user in
video/input/render/wayland, and opens a login session with
`PAMName=weston-autologin`.

So the project ships no unit at all. It ships a `weston.ini` through a
bbappend, and that is the whole kiosk configuration.

**Why that and not the specification's unit.** The specification writes
`Conflicts=getty@tty1.service`, which takes the console away from the
operator on a board whose serial cable is the other way in. tty7
**removes the conflict rather than declaring it**: the dashboard and the
login prompt coexist and Ctrl-Alt-F1 still reaches a shell. A second unit
managing the same compositor would also be the two-managers bug the
ownership table exists to prevent, invisible until both tried to take DRM
master.

---

## 7. The seat comes from logind, not from a seatd daemon

**What happened.** The specification's Debian recipe is
`systemctl enable --now seatd` plus `LIBSEAT_BACKEND=seatd`. Checking
whether that applies here: oe-core's `seatd` recipe **ships no systemd
unit**. It inherits `update-rc.d` for sysvinit and sets no
`SYSTEMD_SERVICE`. What it provides on this image is `libseat`.

**What was done.** Wrote the design around logind, which has a seat to
hand out because `weston.service` opens a PAM session, and **labelled it
as inferred**. `bench-gfx compositor` reads the backend line out of the
journal and `docs/BRINGUP.md` carries the fallback.

**Why the label matters.** Whether libseat in this build has a logind
backend compiled in has not been seen on a board. Stating it as fact
would be the Project 8 mistake again: an observation and a mechanism
written in the same voice, where only the first was checked.

---

## 8. A test suite for a project with nothing testable

**What happened.** Project 13 has no code that runs on a laptop: the
dashboard needs a compositor and the compositor needs a GPU. The
temptation was to write no tests and say hardware was required.

**What was done.** Tested the thing that actually breaks, which is
**agreement between five files that nothing forces to agree**. The
rotation rule is the sharp one: set once on the kernel command line, and
the design depends on it not being set again in `weston.ini` or armed in
udev. Both are one uncommented line away, and the symptom of getting it
wrong is touch working correctly **upside down**, which is the hardest
version of this bug to read because every individual layer looks right.

18 assertions. Then three of the guards were proven by reintroducing the
defect and rerunning:

| Defect reintroduced | Guard fired |
|---|---|
| an armed udev calibration matrix | yes |
| `transform=rotate-180` in weston.ini | yes |
| the LVGL 9.1.0 pin | yes |

Restored, and the suite went quiet again.

---

## 9. The test caught a real defect in advice, not in code

**What happened.** The suite asserts that `bench-gfx` uses
`head -n N` rather than the GNU `head -N`, because the board is BusyBox.
It failed on the first run.

**What was done.** The offending line was not a command the script runs.
It was a line the script **prints to the operator**:

```
  note "  WAYLAND_DEBUG=1 bench-hmi 2>&1 | head -50"
```

Advice that would fail on the board it is printed on. Fixed to
`head -n 50`.

**Why this is an entry.** The check was written for executable code and
caught a documentation defect, which is the more likely of the two to
survive review: nobody runs the comments. A diagnostic tool that hands
out a command the board cannot run is worse than one that says nothing,
because it spends the reader's trust.

---

## 10. A help entry for a target that did not exist

**What happened.** Adding `./go kiosk`, a second line was added for
`./go gfx` to run the diagnostic over ssh. The case statement got only
the first.

**What was done.** Removed the help line. `bench-gfx` runs **on the
board**, and a host-side wrapper would need an address this repository
does not hold.

**Why this is an entry.** `./go` prints its own header as its help, so a
documented target that does not exist is invisible until somebody types
it. It is the same class as a design document naming a file that was
never written, which this repository has done before: **when a document
names an artefact, go and look for it.** Here the document and the code
were written ninety seconds apart and still disagreed.

---

## 11. cage is packaged after all, and the reason for weston had to change

**What happened.** A background query launched early in the session and
forgotten finished at the end of it. It had asked the OpenEmbedded layer
index for cage, wlroots and seatd, and it reported `200` for every one of
them, including `libseat`.

That output was worthless, and worth knowing why: it was written as

```
curl -s -o /dev/null -w "%{http_code}" ".../api/recipes/?q=$r"
```

which checks only that the API answered. The index returns 200 for any
query, matched or not. **A check that cannot fail**, which this
repository has now shipped four of.

**What was done.** Asked the index properly, parsing the JSON, and then
resolved the layer ids. `cage` and `wlroots` are in
[meta-wayland](https://codeberg.org/flk/meta-wayland), which has a
**scarthgap** branch carrying `recipes-wlroots/cage/cage-0.1.5.bb` and
`recipes-wlroots/wlroots/wlroots-0.17.bb`.

**Why this matters more than a footnote.** The decision in entry 1 was
taken partly on the claim that cage meant "roughly a week of packaging".
It does not. It means one `repos:` entry in a kas file, exactly the way
`kas/bench-tee.yml` adds meta-arm, and `seatd` is already in oe-core.

The decision was re-examined rather than defended, and it survived on a
different argument: every other layer this repository depends on comes
from the Yocto Project or OpenEmbedded, and meta-wayland is a personal
layer. Adding one to a portfolio repository is a supply chain choice, and
making it to save a nine line configuration file is not a good trade.
That is a real reason; "it is not packaged" was not.

**The general form, and it is the one this repository keeps meeting.**
The observation was "cage is not in these three layers", which was true.
The conclusion was "therefore packaging it is a week", which was
reasoning, written in the same voice, and wrong. Project 8 made exactly
this mistake with a DAQ HAT and a Pi 4. **Separate what you saw from what
you worked out**, and when the worked-out part is load bearing for a
decision, go and check it.

The three documents that carried the wrong reason were corrected rather
than quietly edited: each now says what it used to say and why that
changed.

---

## 12. A header promised a test that did not exist

**What happened.** `metrics.h` was written with this in its opening
comment:

> the whole module can be tested on a laptop by pointing
> `BENCH_METRICS_ROOT` at a directory of fake files.
> `tests/hmi-metrics-test.sh` does exactly that

There was no such file. The `BENCH_METRICS_ROOT` indirection was built
for it, the comment described it in the present tense, and it did not
exist.

**What was done.** Wrote it, plus `tests/hmi-metrics-harness.c`. 21
assertions, the sharpest being that a `/proc/meminfo` with a tiny
`MemFree` and a large `MemAvailable` reads as 25 percent used and not 95:
an implementation reading the wrong field produces a bar that sits near
full on a completely idle board, which is the commonest way to ship a
memory widget that is always alarming and never informative.

**Why this is an entry.** This repository has done it before, in Project
3, where a design document described `analyze.py` writing a summary file
that the program never wrote. **A document that describes a program is a
claim about it, and nothing tests it.** Both times the prose and the code
were written in the same hour by the same hand and still disagreed. The
only defence is the one the method already names: when a document names
an artefact, go and look for it.

Fixed in the direction the document pointed, not the other way. Editing
the comment to remove the promise would have been faster and would have
silently dropped the testability the module was designed for.

---

## 13. The test cannot run here, and says so rather than passing

**What happened.** `tests/hmi-metrics-test.sh` compiles `metrics.c`. The
authoring laptop has no `cc`, `gcc`, `clang` or `tcc`.

**What was done.** The suite looks for a compiler and, finding none,
prints what it did **not** do and exits 0:

```
unasked  no C compiler on PATH (tried cc, gcc, clang).
         metrics.c was NOT compiled and NOT exercised here.
         ... treat this as 'not checked' rather than as a pass.
```

CI installs `build-essential` and runs every `tests/*.sh`, so it runs
there for real.

**Why exit 0 and not a failure.** A red suite on the authoring laptop
every single run is a suite people stop reading, and then the day it goes
red for a real reason nobody notices. The alternative danger is the one
this repository has shipped three times: a check that silently skips and
reports a clean run for a question it never asked. Printing the skip
loudly, in the `unasked` channel `bench-gfx` also uses, is the line
between those two.

**What this does mean.** Those 21 assertions have **never executed**.
They are written, not proven, and the README says so in the same cell as
the count. The first CI run is what turns them into evidence.

---

## 14. The GPU provider is a MACHINE_FEATURE nothing in this project sets

**What happened.** Checking what weston's `kms` and `egl` PACKAGECONFIG
entries actually resolve to on this board, rather than assuming Mesa.

`meta-raspberrypi/conf/machine/include/rpi-base.inc`:

```
MACHINE_FEATURES += "... ${@bb.utils.contains('DISABLE_VC4GRAPHICS',
                             '1', '', 'vc4graphics', d)}"
```

and `rpi-default-providers.inc` reads it:

```
PREFERRED_PROVIDER_virtual/egl      ?= vc4graphics ? mesa : userland
PREFERRED_PROVIDER_virtual/libgbm   ?= vc4graphics ? mesa : mesa-gl
```

**What was done.** Nothing, which is the correct action: `vc4graphics` is
on by default. The finding was written into `kas/bench-kiosk.yml` beside
the settings that ARE made, with the failure it predicts.

**Why it is worth a note about something that needed no change.** The
whole compositor rests on that feature being present, and on a board
where somebody set `DISABLE_VC4GRAPHICS = "1"` weston would be built
against the closed VideoCore userland stack. The symptom would be a KMS
backend that does not work, four files away from the cause, on a project
whose most common failure message is already "no outputs". A default that
load-bearing is worth naming even when it is correct.

---

## 15. The image had no graphics drivers in it, and nothing would have said so

**What happened.** Auditing the project for completeness rather than
re-reading the summary of it, the specification's step 1 was checked
against what had actually been built. It names seven kernel options and
says they "are all enabled in the Raspberry Pi kernel". They are. **As
modules.**

`arch/arm64/configs/bcm2711_defconfig` at rpi-6.6.y, which
meta-raspberrypi selects for raspberrypi4-64:

```
  CONFIG_DRM=m
  CONFIG_DRM_VC4=m
  CONFIG_DRM_V3D=m
  CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN=m
  CONFIG_TOUCHSCREEN_EDT_FT5X06=m
  CONFIG_INPUT_EVDEV=y
```

and `bench-image` requires `core-image-minimal`, which installs **no
kernel modules**; it names two `kernel-module-brcmfmac` packages
explicitly for the radio and nothing else.

So the image as written would have booted with no `/dev/dri`, no panel
driver and no touch device. weston would have reported no outputs, the
screen would have stayed black, and that is indistinguishable from a bad
ribbon, a missing overlay or a brown-out. **Every layer above it was
correct and the board would have shown nothing.**

**What was done.** `kernel-modules` in `bench-kiosk-image.bb`, with the
reasoning beside it, plus an assertion in the test suite that fires when
the line is removed.

**Why not Project 6's answer.** That project met the same trap, with the
same defconfig, and solved it with a fragment full of `=y` on the
argument that nothing on its image is optional. The same argument applies
here and **the same solution does not**:

```
  config DRM_VC4
      tristate "Broadcom VC4 Graphics"
      ...
      depends on SND && SND_SOC
```

with `CONFIG_SND=m` and `CONFIG_SND_SOC=m` in that defconfig. A tristate
that depends on a module can be at most a module, so `CONFIG_DRM_VC4=y`
is **unreachable**, not merely unset. A fragment asking for it would be
dropped in silence, the build would succeed, and the board would be
exactly as black as before. Reaching `=y` would mean pulling the whole
ALSA and ASoC stack in built-in to gain nothing the modules do not
already give.

**Why this entry matters more than the others.** It is the only defect
found in this project that a document could not have caught and a test
would not have caught either, because nothing was wrong with any file:
the recipes were right, the configuration was right, the code was right,
and the product did not work. It was found by asking "what does step 1 of
the specification actually require, and did I do it", against the thing
rather than against my own summary of the thing.

The general form is the one the method already names and this is the
sharpest instance of it yet: **a claim that explains an absence is the one
to re-read.** The specification's sentence "the kernel options behind
this are all enabled in the Raspberry Pi kernel" was true, and reading it
as "so there is nothing to do" was the error.

---

## 16. What is not done

Stated plainly, because an acceptance table with blanks invites the
assumption that the blanks are oversights.

**Nothing has been built and no board has been booted.** Every measured
row is empty and every output block in `docs/DEBUGGING.md` says `NOT YET
RUN`.

Known to need a board before they can be trusted:

1. The logind-versus-seatd inference in entry 7.
2. Whether LVGL's CMake needs more help than
   `meta-bench/recipes-bench/bench-hmi/files/CMakeLists.txt` gives it.
   `lv_wl_xdg_shell.c` includes `"wayland_xdg_shell.h"`, that header is
   not in the LVGL tree, and neither LVGL's CMake nor `lv_port_linux`'s
   generates it. The CMakeLists here generates it with `wayland-scanner`
   under exactly that name. **That is read off an include line and has
   never been compiled.**
3. Whether `[autolaunch]` in weston 13 behaves as the man page's section
   heading implies.

And two things are missing rather than unverified: there is no recipe for
`drm_info` or `evtest` in any layer here, so acceptance criterion 2 can
be only partly met and layer 4 is reachable only indirectly. Both are in
the README's acceptance table with their reason, because a stated
limitation is a finding and an empty row is an accusation.

**This laptop has no compiler at all**, so none of the C in this project
has been compiled. It is C written against headers that were read, which
is not the same as building. That is the build laptop's first job, and
`tests/hmi-metrics-test.sh` is the cheapest way to start: it needs no
Yocto, no board and no GPU, only `cc`.

What was done instead of compiling, and what it is worth: every LVGL
function the application calls, and every `lv_conf.h` option the recipe
sets, was checked against the 9.3.0 headers and template. Thirteen
functions, three signatures and eight options, all present and matching.
**That catches a misremembered name and catches nothing else.** It does
not catch a type error, an argument in the wrong order, or a missing
include.
