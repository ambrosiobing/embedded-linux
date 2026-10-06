# Journal: Project 9

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled
list of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that
and not the alternative**.

All entries are 18 September 2026 unless noted.

---

## 1. The design document found the two-managers bug before a line was built

**What happened.** The method says to write `docs/DESIGN.md` before any
recipe, with an ownership table naming which component owns which device,
interface or file. This project looked like it had one contested
resource, the UART shared between console and debugger, which is the
whole reason agent-proxy exists and is not a discovery.

Filling the table out properly turned up a second one that nothing in the
specification mentions: **`/sys/fs/pstore` has two managers.**

**What was done.** `systemd` mounts pstore itself, which is in
`src/shared/mount-setup.c`. Then `systemd-pstore.service` copies every
record to `/var/lib/systemd/pstore/` and deletes it: `Storage=external`
and `Unlink=yes` are the compile-time defaults, and the unit is ordered
`Before=sysinit.target`, so it finishes long before a login prompt.

Acceptance criterion 2 says `/sys/fs/pstore/dmesg-ramoops-0` contains the
oops after the reboot. On a stock systemd image **that criterion would
have failed**, and not because ramoops was broken.

`bench-debug-image` masks the unit, and says why in the recipe.

**Why that and not the alternative.** Reading
`/var/lib/systemd/pstore/` instead would also work and would need no
mask. It was rejected because a debugging lab wants one owner of that
directory and wants records to persist until the person reading them says
otherwise. Clearing pstore after each capture is a step in the notebook,
done deliberately, so that an old record cannot be mistaken for a new
one. An archiver that empties the directory on every boot makes that step
impossible to perform.

The corroboration arrived from an unexpected direction afterwards: the
Raspberry Pi overlay README for `ramoops` carries the same warning in one
line. Two independent sources for a trap that costs an evening is worth
more than either.

---

## 2. Four symbols in the specification's fragment do nothing

**What happened.** Before writing `debug.cfg`, every symbol in the
specification's fragment was read out of the Kconfig at `rpi-6.6.y`
rather than assumed. Four of them are **promptless**: their value comes
from whatever selects them, and writing them in a fragment produces no
error, no warning and no effect.

| Written as a request | What it is | Ask for instead |
|---|---|---|
| `CONFIG_DEBUG_INFO` | bare `bool` | `CONFIG_DEBUG_INFO_DWARF5` |
| `CONFIG_HW_PERF_EVENTS` | `def_bool y depends on ARM_PMU` | `CONFIG_ARM_PMU` |
| `CONFIG_UPROBES` | `def_bool n` | `CONFIG_UPROBE_EVENTS` |
| `CONFIG_LOCKUP_DETECTOR` | bare `bool` | `CONFIG_SOFTLOCKUP_DETECTOR` |

The fourth was not in the original list and came out of checking the
others. `CONFIG_CONSOLE_POLL` is a fifth of the same kind and the
specification names it correctly, as a consequence rather than a request.

**What was done.** The fragment asks for the settable symbol in each case
and keeps the promptless one in a block labelled as assertions, so that
`./go kconfig` notices if a future defconfig stops selecting it.

**Why that and not the alternative.** Deleting the promptless lines would
be tidier and would lose the check. The value of `CONFIG_LOCKDEP=y` in
the file is not that it sets anything; it is that a kernel where lockdep
stopped being selected would be caught by a tool rather than by a
debugging session that found no lock reports and concluded the code was
correct.

**The general form, which belongs to the whole repository:** a fragment
is a list of requests, and a request the kernel silently ignores looks
exactly like one it granted.

---

## 3. A grep for `^config KFENCE` found nothing, and KFENCE exists

**What happened.** Verifying the memory-debugging symbols, `grep -A10
'^config KFENCE$'` against `lib/Kconfig.kfence` returned nothing. The
obvious reading is that the symbol does not exist on this tree.

**What was done.** Looked at the file instead of trusting the grep. It is
`menuconfig KFENCE`, not `config KFENCE`, and it has a prompt and is
perfectly settable.

**Why this is in the journal.** Because the wrong conclusion was one step
away and would have been written confidently into a fragment comment as
"KFENCE is not available on this tree". The pattern is the one this
repository keeps meeting: **a tool chose its own input, reported on what
it chose, and did not say what it had excluded.** A `^config` anchor
excluded every `menuconfig` in the kernel, silently.

The same check caught nothing wrong about `ARM_PMU` and something
important about `LOCKUP_DETECTOR`, so the pass paid for itself twice.

---

## 4. The leak was one block, and the acceptance criterion counts objects

**What happened.** `fault_leak` was written first as a single
`kmalloc(16 * 1024)` with the pointer dropped, and the documentation said
"16 kB per trigger". Then the specification's acceptance criteria were
read properly: **"kmemleak lists 64 unreferenced 256-byte objects"**.

**What was done.** Changed it to 64 allocations of 256 bytes, which is
the same 16 kB in a different shape, and propagated that through the
module docstring, `DESIGN.md` and the fault-matrix figure.

**Why that and not the alternative.** kmemleak reports objects, not
bytes. It never prints "16 kB leaked", so a criterion written in bytes is
not checkable against its output; a criterion written in objects is. The
shape of the allocation had to follow the thing that could be verified,
rather than the other way round.

---

## 5. The Bash heredoc ate a backslash level, three times, and the asserts caught it

**What happened.** Three separate attempts to edit a file through a
`python - <<'PY'` heredoc failed because the shell consumed one level of
backslashes:

- a `sed` on `\^{}` in a TikZ file matched nothing and reported success;
- `'{\texttt{leak}\\\scriptsize ...'` as a Python string literal arrived
  with one backslash fewer than written;
- `'\node[umlnote...'` had its `\n` turned into a newline.

**What was done.** Every one of them was caught by an `assert old in
text` before the replace, which is the rule this repository already has
for exactly this. The edits were redone with the Edit tool.

**Why this is worth an entry.** The rule was written because this failure
destroyed all seven Project 20 figures once. It has now paid for itself
three times in one session, and the important part is not that the
heredoc is dangerous: it is that **`str.replace` returns the string
unchanged when the anchor is missing, and writes it back with no error.**
The assert is the only thing standing between that and a silent no-op.
The `sed` case is worse, because `sed` has no assert to add.

---

## 6. Two checks were written, then broken on purpose to see them fail

**What happened.** `tests/debug-proxy-test.sh` and
`tests/debug-decode-test.sh` both passed on the first run, 37 assertions
between them. A check that has never failed is indistinguishable from a
check that passes.

**What was done.** Both guards were removed from a copy of the script
under test and the suites rerun:

| Guard removed | Assertions that failed |
|---|---|
| The "device already held" refusal in `agent-proxy.sh` | 6 |
| The "no cross toolchain" refusal in `decode.sh` | 2 |

Then restored, and both went quiet again.

**What that turned up.** For `decode.sh`, only 2 of the 4 relevant
assertions failed, because a later check (`command -v
"${CROSS_COMPILE}addr2line"`) catches the same case by a different route
and still exits 1. The two guards overlap. That is fine and now known;
without the mutation it would have read as full coverage of a guard that
is partly redundant.

For `agent-proxy.sh` the mutation also confirmed an assertion that had
been nagging: "a held device never reaches agent-proxy" passes trivially
when the record file is simply absent, so it could have been green for
the wrong reason. Under the mutant it failed, which is the proof it was
actually measuring something.

---

## 7. The debugger's argument order is printed before it runs

**What happened.** `agent-proxy` takes its arguments in an unusual order:
the port pair, then a target host of `0` meaning a serial device follows,
then the device and baud. The upstream README could not be fetched to
confirm it (the kernel.org cgit path 404s and the GitHub mirror does not
exist), so the invocation rests on the widely documented form rather than
on a source that was read.

**What was done.** The script echoes the exact command line before
executing it, and the test asserts on the recorded argument vector rather
than only on the exit status.

**Why that and not the alternative.** Guessing silently would mean a
version of `agent-proxy` with different expectations fails with a usage
message that never names this script, on a bench where the same symptom
is also produced by a dead cable, a held device and a wrong overlay. An
echoed command turns that into a one-line diagnosis. **Where something
could not be verified, the code says what it assumed, out loud, at the
moment it matters.**

---

## 8. kexec was left out on purpose, and said so

**What happened.** The component drawing listed `kexec-tools` alongside
`trace-cmd` and `perf`, carried over from the specification's component
list. Then the specification was read more carefully: kexec appears under
**stretch goals**, as "capture a full crash dump with kexec and `crash`
instead of ramoops, **and document why that is rarely done on small
boards**".

**What was done.** Removed it from the image and from the drawing, and
put the reason in the README's "going further" section instead.

**Why that and not the alternative.** Shipping `kexec-tools` with no
working kdump path would be a capability in the package list that nobody
can use, and the interaction between a kexec crash kernel and the
reserved ramoops region on this firmware boot flow is exactly the kind of
thing that is half-working in a way nobody notices. The specification
asks for the explanation rather than the feature, and the explanation is
cheaper and more honest than a half-built version of it.

---

## 9. The module is the layer's first, and its package is not named after it

**What happened.** Fifteen recipes in `recipes-bench/` and every one of
them builds userspace. `bench-buggy` is the first that inherits `module`,
and it behaves differently in a way that fails quietly.

**What was done.** Read `module.bbclass` and oe-core's own `hello-mod`
rather than writing the recipe from memory, which settled two things:

- `MAKE_TARGETS` is **not** set by `module.bbclass`, so `oe_runmake` runs
  with no target and gets the Makefile's first rule. The Makefile's `all`
  target is load-bearing and renaming it breaks the build with a make
  error that reads like a broken recipe.
- The package is `kernel-module-buggy`, from the kernel module split
  class, **not** `bench-buggy`. An image installing `bench-buggy` gets
  nothing, and BitBake does not consider that an error: the recipe built,
  and nothing asked for its output.

Both are written in the recipe and in the image, next to the lines they
explain.

**Why that and not the alternative.** The second one is the dangerous
one, because the failure is an image that builds, boots and has no
`/sys/kernel/debug/buggy`, on a board where a missing debugfs directory
has four other plausible causes.

---

## 10. `KERNEL_MODULE_AUTOLOAD` was deliberately not set

**What happened.** The natural thing for a module recipe is to add it to
`KERNEL_MODULE_AUTOLOAD` so it is there after boot.

**What was done.** Left out, and a comment in the recipe says why.

**Why that and not the alternative.** This module exists to break the
kernel. A fault injector that loads itself on every boot is one typo away
from a board that panics before the console is up, on an image whose
whole purpose is to be running when something goes wrong. It is loaded by
hand from a notebook entry that says what is about to happen.

The same reasoning shapes the module itself: nothing fires at load time,
every fault is behind an explicit keyword on a write-only file, and an
unknown keyword is an error that lists what it would have accepted rather
than a silent no-op. A typo that silently did nothing would let an
evening end with "the tool found nothing", which is the same shape as a
working tool reporting a clean run.

---

## 11. `strim` does not return what it was given

**What happened.** `trigger_write` called `strim(command)` and then
compared `command` against the keyword table, discarding the return
value.

**What was done.** Kept the returned pointer and compared that.

**Why it matters.** `strim` skips leading whitespace by returning a
pointer further into the buffer; it only trims the trailing end in place.
So `echo ' null'` would have failed to match, and the error message would
have printed the untrimmed string, for a reason nothing on the console
would explain. Found by reading the code back rather than by any tool.

---

## 12. The BSP's kgdb shortcut was not used, and the doubt is recorded

**What happened.** `meta-raspberrypi` offers `ENABLE_KGDB = "1"`, which
`rpi-cmdline.bb` turns into `kgdboc=serial0,115200`.

**What was done.** Set `CMDLINE_KGDB` to the explicit
`kgdboc=ttyAMA0,115200` instead, and wrote the reason in the kas file and
a check in `docs/BRINGUP.md`.

**Why that and not the alternative.** `serial0` is a device-tree alias.
`console=serial0` works because the console code resolves aliases through
the stdout-path mechanism. `kgdboc` resolves its argument through
`tty_find_polling_driver`, which matches a registered tty driver name and
index, and an alias is not one.

**This is inferred from reading, not seen on a board**, and it is
labelled that way in both places rather than stated as a finding. Being
explicit costs nothing if the alias does work; if it does not, the
failure it avoids is a debugger silently attached to no port at all, on a
board where everything else looks correct.

---

## 13. What is not done

Stated plainly, because an acceptance table with blanks invites the
assumption that the blanks are oversights.

**Nothing has been built and no board has been booted.** Every measured
row in the README is empty and every notebook output block says `NOT YET
RUN`. What exists is the configuration, the module, the host tools, 37
assertions that run on a laptop, and the documents.

Two things are known to need a board before they can be trusted:

1. The `kgdboc=serial0` inference in entry 12.
2. Whether `total-size=0x20000` with a 32 kB console region actually
   leaves six usable dmesg slots, which is arithmetic until a seventh
   crash overwrites the first.

And one thing cannot be checked on the authoring laptop at all: this
machine has no cross compiler, so `buggy.c` **has never been compiled**.
It is C written against kernel headers and read back carefully, which is
not the same as building. That is the first thing the build laptop
should say something about.

---

## 14. The heartbeat LED was drawn as a part this bench does not have

**What happened.** The schematic, the wiring table, the bench layout,
`docs/BRINGUP.md` and both TikZ figure sources all drew a bare green LED
through a 330 ohm resistor on a breadboard. That is what the
specification assumes, and **none of those three parts is on this bench**:
no bare LEDs, no loose resistors. The bench's LEDs are Joy-IT LinkerKit
LK-LED10 modules, which carry their own resistor, `R1`, and a 2.54 mm
header printed `S1 S2 U G` beside a 2.0 mm LinkerKit socket.

This project did not make the error, it inherited it. Project 1 had
recorded for two weeks that the modules could not be connected at all,
read off the manufacturer's page rather than off the board, and that
belief is why three projects deferred their LED output. Commit `04caf17`
corrected it after three modules were lit on a Raspberry Pi 3 Model B on
Friday 2 October 2026, and corrected projects 1, 4 and 20. **Its sweep did
not reach this project or project 3.**

**What was done.** Six places rewritten. The wiring is now `S1` to pin 11,
GPIO17, and `G` to pin 9, GND, with `U` and `S2` left unconnected; one
module was lit with `U` wired and lit identically with that jumper pulled
out. Both TikZ sources were compiled with pdflatex and the schematic was
read as a rendered page before committing, rather than trusted from the
source.

**Why that and not the alternative.** The alternative was to leave the
documents alone, since the LED appears in **none of this project's twelve
acceptance criteria** and nothing measured depends on it. That was
rejected because the drawings are what a reader follows with the parts in
front of them, and a document that asks for a resistor that is not in the
drawer sends them looking for a shop rather than for a jumper. What the
correction also settles is that the `gpio-led` overlay needs no
`active_low`: driving the line high lights the module, low puts it out,
and releasing it to an input also puts it out and reads low, on each of
three pins.

**The part worth carrying elsewhere is how it was found.** Not by
re-reading around the earlier correction, which is what one would do and
which would have found nothing here, but by grepping the tree for the
number `330`. Correcting the prose of a document does not correct the
drawing sitting beside it, and `04caf17` had done exactly that in its own
files. The same grep found two more in project 3 and two more in project
1's own figures, in the very file whose prose that commit had already
fixed.

**Still unmeasured, and this changes none of it.** The LED is an
instrument that reports after the kernel has stopped, and whether it does
so on this image is a board question like every other row in the
acceptance table.


## 15. Sunday 4 October 2026 from 21:14, into Monday 5 October 2026, minute by minute

**What happened.** The debug image reached a board for the first time.
Seven things were found, four of them defects in this repository rather
than in the kernel, and one of them a real memory safety fault that only
this image could have seen. The order matters, because three of the
seven were visible only because of the fix for the one before.

Times carrying seconds are read from log timestamps. Times given to the
minute come from file modification times, or bracket a command between
two timestamped events either side of it. The board has no RTC, so its
own clock reads 26 June 2025 throughout and none of its wall times are
used here. After 23:09 nothing on either host wrote a wall clock, so
the rows below that point are ordered from the console transcript and
carry no time of their own. The last of them ran past midnight into
Monday 5 October 2026. Four capture files exist from that
evening rather than two, found by listing the directory on Monday 5
October 2026 after this entry had been written from their modification
times alone. Two are false starts at 265 and 0 bytes; an empty picocom
log is an abandoned session and not a corrupt one.

| Time | What happened |
| --- | --- |
| 21:14 | `/dev/ttyUSB0` present on JPTOUPM678, picocom installed |
| 21:18 | picocom started, `proj09-firstboot-2026-10-04-2118.log` |
| 21:18 to 21:23 | 303 `BUG: sleeping function` traces, one per second, 713,037 bytes. The log opens at board time 32.4 s, so the first 32 seconds were never recorded |
| about 21:27 | board powered down. The LED on pin 11 was lit and steady, not beating. A second capture had run from 21:25, `proj09-firstboot-2026-10-04-2125.log`, 256,566 bytes and about 109 more traces, which was not known about when this entry was first written |
| 21:27 | card in the reader, `/dev/sde`, `sde1` vfat `boot`, `sde2` ext4 `root` |
| about 21:30 | `config.txt` carries all three `dtoverlay` lines, exactly as written |
| about 21:32 | `cmdline.txt` carries `kgdboc=ttyAMA0,115200` and `nokaslr` |
| about 21:33 | `ls /mnt/boot/overlays/` returns 68 files and only `disable-bt.dtbo` of the three |
| about 21:35 | `/etc/fstab` on `sde2` does mount `/boot`, so the WiFi unit's condition was never the obstacle |
| 21:51:43 | kas run without `KAS_WORK_DIR` begins cloning poky, meta-openembedded and meta-raspberrypi into the checkout |
| 21:52:24 | cancelled. 7.9 MB of `meta-raspberrypi` and a 4 kB `build` left behind |
| 21:53:17 | the same gate with `KAS_WORK_DIR` and `KAS_BUILD_DIR` set resolves `KERNEL_DEVICETREE` with both overlays appended |
| 21:55:25 | full `bitbake -e` to a file. The operation history shows the append attaching at `rpi-base.inc:110` |
| 21:59:07 | build starts. Sstate: Wanted 478, Local 443, Missed 35, Current 1983 |
| 22:00:15 | `linux-raspberrypi:do_compile` starts |
| 22:15:00 | `do_compile` succeeds, 14 min 45 s |
| 22:16:52 | `perf:do_compile` succeeds |
| 22:38:24 | `do_compile_kernelmodules` succeeds, 23 min 23 s |
| 22:46:11 | `do_rootfs` starts |
| 22:47:43 | 5,382 tasks attempted, 5,313 cached, all succeeded |
| 22:47:49 | build done, 48 min 42 s, 72 MB image |
| about 22:52 | the overlays are flat in the deploy directory, not under `overlays/`, so the pre-flash check could not be written against it |
| about 22:55 | flashed to `/dev/sde`, 200.6 MiB of 728.8 MiB mapped, 17.1 s at 11.7 MiB/sec |
| about 22:57 | card now carries 70 overlays, `gpio-led.dtbo` and `ramoops.dtbo` among them |
| about 22:58 | `cmdline.txt` gets `dwc_otg.fiq_enable=0 dwc_otg.fiq_fsm_enable=0`, original kept as `cmdline.txt.orig` |
| 23:00 | picocom started, logfile stayed empty |
| 23:01 | picocom restarted, 24,517 bytes captured |
| 23:05:02 | the LED filmed, 11.17 s at 30.001 fps, 1920x1080 |
| then | measured: two flashes of about 100 ms, 0.30 s apart, repeating every 1.22 s |
| after 23:09 | root prompt. The flood is gone, replaced by one `audit` pair every 2.5 s |
| then | `[heartbeat]` is the active trigger. `bench-status` is failing, restart counter 301 |
| then | `bench-status: requesting lines 17/27/22: Device or resource busy`, verbatim as predicted |
| then | ramoops registered at boot, but `/sys/fs/pstore` is not mounted |
| then | `fiq_enable` and `fiq_fsm_enable` both read `N` against a default of `Y` |
| then | `brcmfmac` has BCM4345/6 and firmware 7.45.265. `cfg80211: failed to load regulatory.db` |
| then | reboot, and this time a full log from `[0.000000]` |
| board 3.075 s and 4.62 s | two KFENCE reports in `hub_port_init` |
| then | pstore mounted by hand: `console-ramoops-0`, 32,756 bytes, carrying the previous boot |
| then | a 300 character paste overruns the UART input buffer and writes an empty key |
| then | the generated supplicant config still holds a placeholder, because `start` on a `RemainAfterExit` oneshot does nothing |
| past midnight | associated, `192.168.92.154/24`, ssh from aquamarine |

**What was done.** One line of configuration changed, in
`kas/bench-debug.yml`. Everything else in this list is a finding, a
measurement, or a mistake. The image was rebuilt once, flashed once, and
booted twice.

**Why that and not the alternative.** The alternative, at 21:33 with the
overlay list in hand, was to add the two overlays and get on with the
acceptance criteria. That would have skipped the question of why a card
had been built repeatedly without anyone reading its `overlays/`
directory, which is the finding with the longest reach, because it is
not specific to this project.


## 16. Three overlays were named in config.txt and one was on the card

**What happened.** The first boot put the LK-LED10 on pin 11 solidly lit
rather than beating. A steady LED is not a slow heartbeat: the kernel
trigger is mostly off, two short flashes and a pause, so a steady lamp
means nothing is modulating it.

`docs/BRINGUP.md` step 2 says to read the boot partition back after
flashing, and that step had been skipped in favour of writing
`wifi.conf`. Run late, it gave the answer in one line. Of the three
overlays `config.txt` asks for, the card held one:

    ls /mnt/boot/overlays/ | grep -E 'gpio-led|ramoops|disable-bt'
    disable-bt.dtbo

Sixty eight overlays were present. `gpio-led.dtbo` and `ramoops.dtbo`
were not among them. The firmware skips a `dtoverlay=` line whose `.dtbo`
is absent, and nothing in the kernel log mentions it, which is structural
rather than unlucky: overlay handling finishes before the kernel starts.

So the heartbeat LED was never created and ramoops reserved nothing. Two
of this project's acceptance criteria were unreachable, from a
`config.txt` that was exactly right.

**Where it came from.** meta-raspberrypi builds `KERNEL_DEVICETREE` in
`conf/machine/include/rpi-base.inc` out of `RPI_KERNEL_DEVICETREE` and a
hand curated `RPI_KERNEL_DEVICETREE_OVERLAYS`. That list carries
`gpio-ir`, `gpio-ir-tx`, `gpio-key`, `gpio-poweroff`, `gpio-shutdown`,
`i2c-gpio`, `pps-gpio` and `w1-gpio`, and neither of the two this project
needs. `KERNEL_DEVICETREE` appears nowhere in this repository, so the
list was never extended.

**What was done.** One line in `kas/bench-debug.yml`:

    KERNEL_DEVICETREE:append = " overlays/gpio-led.dtbo overlays/ramoops.dtbo"

Both overlay sources exist in the kernel tree at `rpi-6.6.y`, read out of
the downloads mirror before the build rather than discovered by a failing
`do_compile`:

    arch/arm/boot/dts/overlays/gpio-led-overlay.dts
    arch/arm/boot/dts/overlays/ramoops-overlay.dts
    arch/arm/boot/dts/overlays/ramoops-pi4-overlay.dts

There being two ramoops variants is worth the second look it got. This
board is a Raspberry Pi 3 Model B Plus, so `ramoops` is correct, and
`ramoops-pi4` would have built cleanly and reserved memory at an address
this board does not have.

The change was verified at four points before it was believed: the
resolved variable from `bitbake -e`, the compiled `.dtbo` in the deploy
directory, the boot partition after flashing with 70 overlays against the
previous 68, and the running board.

**Why the append goes on `KERNEL_DEVICETREE`.** Appending to the layer's
own `RPI_KERNEL_DEVICETREE_OVERLAYS` would read better and is what the
layer invites. It was rejected because an append to an internal variable
that a later layer version renames does nothing and says nothing, which
is the exact failure this line exists to repair.

**The part that reaches past this project.** `kas/bench-rpi3-ab.yml` asks
for `gpio-led` three times, on 17, 27 and 22. Project 10's slot LEDs have
never had an overlay on any card either. That is not fixed here.

And `meta-bench/recipes-core/images/bench-ab-image.bb` carries this,
under a heading in capitals:

    The gpio-led overlays in kas/bench-rpi3-ab.yml claim those lines in
    the device tree, so libgpiod cannot open them at all

The conflict it resolves is real and the resolution is right. The
sentence justifying it has never been true on any card this bench has
built. It was written as a statement about the device tree and never
checked against a boot partition, which is the same failure as the one it
was explaining.


## 17. Two claimants for GPIO17, written down before the boot and read off it after

**What happened.** With the overlay question answered, the lit LED was
still unexplained. Entry 14 had recorded, from three modules on three
pins on Friday 2 October 2026, that releasing a line to an input puts the
module out and reads low. With nothing claiming GPIO17 it should have
been dark.

`bench-status.c` has the answer at lines 100 to 102:

    cfg->offset[GREEN]  = 17;
    cfg->offset[YELLOW] = 27;
    cfg->offset[RED]    = 22;

`bench-image.bb` installs `bench-status` at line 28, so Project 9
inherits it. `leds.conf` ships `green=17` and `active_low=0`, and the
daemon sets GREEN active whenever `/run/bench/state` reads `ok`,
refreshing every 1000 ms. The steady lamp was the bench status daemon
saying the system was healthy, on the pin this project's ownership table
assigns to `ledtrig-heartbeat`.

**The prediction, written before the board was powered.** With
`gpio-led.dtbo` present, `leds-gpio` claims GPIO17 from the device tree
during probe. `bench-status` asks for 17, 27 and 22 in a single
`gpiod_chip_request_lines`, which is all or nothing, so it gets EBUSY and
exits 1. The console should carry
`bench-status: requesting lines 17/27/22: Device or resource busy`, and
the LED should beat. Falsifiable in the direction that matters: if the
LED beat and the daemon still ran, the reading of that single request was
wrong.

**What the board said.**

    bench-status: lines 17/27/22, active high
    bench-status: no chip labelled pinctrl-bcm2711, using the first wide enough chip
    bench-status: requesting lines 17/27/22: Device or resource busy
    bench-status.service: Main process exited, code=exited, status=1/FAILURE
    bench-status.service: Scheduled restart job, restart counter is at 301

Verbatim. And it closed a loose end that had been read as unrelated noise
for an hour: the `audit: prog-id=N op=LOAD` and `op=UNLOAD` pair arriving
every 2.5 seconds was this restart loop, each start loading a cgroup BPF
program and unloading it when the process died 230 ms later. The symptom
and the defect were the same event.

**A second finding in the same three lines.** `leds.conf` ships
`chip_label=pinctrl-bcm2711`, which is the Raspberry Pi 4 SoC. On a
Raspberry Pi 3 Model B Plus the label is `pinctrl-bcm2835`, so that match
never succeeds and the width fallback carries every Pi 3 image this bench
builds. The source comment describes that fallback as being so that the
daemon still starts on a board nobody has taught it about yet, which is
not what is happening: it is the normal path here, not the exception.
That belongs to Project 12.

**What was done, and what was not.** The daemon was stopped by hand,
which does not survive a reboot. The fix is
`IMAGE_INSTALL:remove = "bench-status"` in `bench-debug-image.bb`, which
is what `bench-ab-image.bb` and `bench-lcd35a-image.bb` already carry for
the same reason. It is not applied yet.

**Why that and not teaching the daemon another pin.** The same argument
`bench-ab-image.bb` makes. The heartbeat and a health indicator are two
meanings for one lamp, and an indicator that needs the image name to
interpret is not an indicator. The heartbeat wins here because it is the
instrument that keeps reporting after the kernel has stopped, which a
userspace daemon cannot do: it would freeze lit, and a frozen lit lamp is
indistinguishable from a healthy one.


## 18. KFENCE found a write two bytes past a USB device descriptor

**What happened.** The second boot, captured from `[0.000000]` because
picocom was attached before power this time, carried two KFENCE reports.

    BUG: KFENCE: memory corruption in hub_port_init+0x6bc/0xcc8
    Corrupted memory at 0x000000003f22a999 [ ! ! . . . . . . . . . . . . . . ]
    kfence-#18: size=18, cache=kmalloc-64
      allocated by task 9 ... usb_get_device_descriptor+0x30/0x98
                             hub_port_init+0x69c/0xcc8
      freed     by task 9 ... hub_port_init+0x6bc/0xcc8

Eighteen bytes is `sizeof(struct usb_device_descriptor)`. The two `!`
marks are the first two bytes of the trailing redzone, so two bytes past
the end of the object were written, and the canary check at free time
caught it. It happened twice in the one boot, at 3.075 s as `kfence-#18`
and at 4.62 s as `kfence-#23`, both during enumeration of the onboard
hub, `idVendor=0424 idProduct=2514`.

**What is established and what is not.** Established: the size, the
allocation site, the free site, that the overwrite is two bytes past an
eighteen byte object, and that it reproduces within a single boot. Not
established: the mechanism. Nothing here says which code wrote those
bytes, and no claim is made about it.

Two other things sit in the same window, relationship unknown: a
`WARNING` at `drivers/firmware/raspberrypi.c:69`, "Firmware transaction
timeout", reached through `rpi_firmware_property_list` from
`bcm2835_sdhost_set_clock` under `mmc_sd_init_card`, and
`mmc0: Problem switching card into high-speed mode!`. They are recorded
next to each other because they share a boot, not because they share a
cause.

**Why this entry exists at all.** This is the first thing Project 9 has
found that could not have been found without the image it builds. KFENCE
is one of the twelve acceptance criteria, and it has now produced a real
report on real hardware rather than a configured symbol. The report is a
notebook entry waiting to be written, not a closed question.

**A reading note for whoever opens that log.** The two KFENCE reports and
the firmware WARNING interleave line by line, because two CPUs were
printing at once. Neither report is corrupt; they are braided.


## 19. The vendor USB driver sleeps inside its own interrupt handler

**What happened.** The first boot produced this 303 times in five
minutes, one per second, 713,037 bytes of log:

    BUG: sleeping function called from invalid context at /kernel/irq/manage.c:737
    in_atomic(): 1, irqs_disabled(): 1, preempt_count: 10002
      dwc_otg_handle_common_intr+0x484/0xda8
      local_fiq_disable+0x28/0x40
      disable_irq+0x2c/0x70

with `hcd->lock` held through `DWC_SPINLOCK`. `disable_irq` waits for an
in flight handler to finish, so it may sleep, and it is being called from
hardirq context with interrupts off and a spinlock held. It is
`CONFIG_DEBUG_ATOMIC_SLEEP` that makes this visible, which is why a stock
image never shows it.

At one per second with forty five lines each it makes the console useless
and `kgdboc` unusable, since both share `ttyAMA0`.

**What was done.** Two parameters added to `cmdline.txt` by hand, with
the original kept beside it as `cmdline.txt.orig`:

    dwc_otg.fiq_enable=0 dwc_otg.fiq_fsm_enable=0

The names were inferred from `local_fiq_disable` appearing in the trace,
so the test was built to fail informatively: a kernel parameter for a
module that does not declare it is accepted and ignored, which looks
exactly like a fix that did not work. After the boot:

    cat /sys/module/dwc_otg/parameters/fiq_enable
    cat /sys/module/dwc_otg/parameters/fiq_fsm_enable
    N
    N

Both files exist, so the names are real, and both read `N` against a
default of `Y`, so the command line did it. A full boot afterwards
carries not one occurrence.

**What this does not establish.** Two parameters were changed at once, so
which of them is responsible is unknown. The cost is USB throughput, and
on a Raspberry Pi 3 Model B Plus the Ethernet port is behind that
controller.

**Why it is on the card and not in the kas file.** Because of the
paragraph above. A workaround whose mechanism has not been separated does
not belong in a committed configuration where it will be inherited by
images that never saw the symptom.


## 20. ramoops carried a console across a reboot, and systemd did not mount it

**What happened.** With `ramoops.dtbo` finally on the card, the kernel
said all of it:

    OF: reserved mem: 0x000000000b000000..0x000000000b01ffff (128 KiB)
        map non-reusable ramoops@b000000
    pstore: Using crash dump compression: deflate
    printk: console [ramoops-1] enabled
    pstore: Registered ramoops as persistent store backend
    ramoops: using 0x20000@0xb000000, ecc: 0

The reservation is exactly the `base-addr` and `total-size` written into
`config.txt`.

But `mount | grep pstore` returned nothing and `/sys/fs/pstore` was an
empty directory. The image masks `systemd-pstore.service`, which is the
archiver and not the mount, so that is not the cause. Mounted by hand
after a reboot:

    mount -t pstore pstore /sys/fs/pstore
    -r--r--r-- 1 root root 32756 console-ramoops-0

32,756 bytes is `console-size=0x8000` less its header, and the contents
carry the previous boot: its audit records are stamped `1750927741`
against the current boot's `1750928498`. pstore is proven end to end on
hardware, from `config.txt` through the overlay and the kernel to a real
console surviving a reboot in DRAM.

**One loose end closed as a side effect.** The commit earlier the same
day that removed `CONFIG_PSTORE_DEFLATE_COMPRESS` argued that
`CONFIG_PSTORE_COMPRESS` being `default y` meant the image already had
the compression the dead symbol was reaching for, and that the image did
not need rebuilding. `pstore: Using crash dump compression: deflate` is
that argument shown rather than reasoned.

**What is wrong and not yet fixed.** `docs/BRINGUP.md` step 6 reads
`mount | grep pstore; ls /sys/fs/pstore/` and expects the mount to be
there. On this image it is not, and a reader following that step sees an
empty result and concludes ramoops is broken, which is precisely the
confusion `bench-debug-image.bb` spends thirty lines of comment trying to
prevent for a different reason.


## 21. The radio was never the problem, and three checks that could not fail

**What happened.** WiFi was reported not working. It took four rounds to
establish that nothing was wrong with it, and every round was a different
fault.

`brcmfmac` bound BCM4345/6 over SDIO with firmware 7.45.265 on every
boot. The radio was never in question. What happened instead:

1. On the first boot `/boot/wifi.conf` had never been written, so
   `bench-wifi-setup` was skipped by its `ConditionPathExists` without an
   error, which is correct behaviour and invisible.
2. The first picocom log opened at board time 32.4 s, so the window where
   any of this would have been visible was never recorded. The conclusion
   drawn at the time was that there was no evidence of WiFi failing,
   which was true and useless.
3. A template line was then pasted literally, putting
   `PSK=PASTE_THE_64_HEX_HERE` into `/boot/wifi.conf`. `wpa_supplicant`
   exited 255 on a config it could not parse.
4. With `/boot/wifi.conf` corrected, `systemctl start bench-wifi-setup`
   did nothing whatever, because the unit is `Type=oneshot` with
   `RemainAfterExit=yes` and was already active. Only `restart` re-reads
   the file. Nothing in this project says so, and the failure is silent:
   `start` returns success.

`systemctl restart bench-wifi-setup`, then the supplicant, and the
generated config went from a 21 character key line to a 72 character one
and the board took a lease on `192.168.92.154/24`. There is no avahi in
this image, so `.local` will never resolve for it and the address is the
only way in.

**Still open.** `cfg80211: failed to load regulatory.db` with error -2 on
every boot. The regulatory database is not in the image, so the kernel
falls back to the restrictive built in world domain. It did not prevent
association here, and it is a missing package rather than a configuration
mistake.

**The three checks that could not fail.** This is the part worth keeping.

The first was a verification command:

    sed 's/=.*/=<set>/' /boot/wifi.conf
    SSID=<set>
    PSK=<set>

which prints `<set>` whether the value is sixty four characters or zero.
It reported success on exactly the failure it existed to catch, and the
file at that moment had an empty key. Replaced by
`awk -F= '{print $1" len="length($2)}'`, which prints `SSID len=14` and
`PSK len=64` and cannot be right by accident.

The second was a recursive `grep` with several patterns piped through a
filter, which returned nothing and was read as the repository not
containing the thing. It did contain it, in the very file under
discussion. A search that returns nothing is not evidence until the
search itself has been shown to work on something it should find.

The third is the one this repository already had a guard for. Running kas
without `KAS_WORK_DIR` and `KAS_BUILD_DIR` started cloning poky,
meta-openembedded and meta-raspberrypi into the checkout. `common.sh`
carries `warn_stray_build_tree`, which exists because 469 MB of exactly
that sat in this checkout for weeks, and which prints a full account of
it. The guard fired. The "Falling back to file-relative addressing"
warnings printed. Both were read past, and the clone was noticed only
because it was slow.

A guard that fires correctly and is ignored is a different failure from a
guard that does not fire, and this evening produced one of each.

**And one that is not a check at all.** A single pasted command of about
300 characters overran the board's UART input buffer:

    ttyAMA ttyAMA0: 1 input overrun(s)
    -sh: echowpa_passphrase: command not found

Two words spliced together out of the middle of the line. The board's
shell is BusyBox ash and its console has no flow control. Commands typed
at that console are kept short from here, and anything long is written to
the card from the reader instead.


## 22. Monday 5 October 2026: the three fixes, and thirty lines about a service that is not in the image

**What happened.** The three things Sunday left open were applied and taken
to a board. All four predictions written down beforehand held.

| Predicted | Observed |
| --- | --- |
| `bench-status` gone, no EBUSY, no restart loop | `Unit bench-status.service could not be found.` |
| the `audit` pair every 2.5 s gone, since it was that loop | gone. What remains is ordinary startup BPF loading, prog-id 6 to 19, which stops |
| `cfg80211: failed to load regulatory.db` gone | gone. Instead the four regulatory certificates load |
| the heartbeat still beating, nothing now competing | `[heartbeat]` in brackets |

And one that was not predicted and is better: `wlan0` took
`192.168.92.154/24` on the first boot with no intervention at all. Sunday's
WiFi trouble was entirely the placeholder key and the `RemainAfterExit`
no-op, and nothing about the credentials file or the radio.

The rebuild was 1 min 45 s, 5,383 tasks of which 5,350 cached, against 48
minutes on Sunday. It is archived as `2026-10-05_c246665`, the first
archive of this project whose provenance record is exactly true, because
the tree was clean when it was taken.

**The overlay check ran against a card for the first time.** Until this
point it had only ever seen fixtures in /tmp:

    --- requested    5: disable-bt gpio-led ramoops vc4-fkms-v3d vc4-kms-dsi-7inch
    --- commented out, not checked: act-led
    --- on the card  69 .dtbo files
    --- every requested overlay is present

It found the commented `#dtoverlay=act-led` in the stock config.txt and
named it. That branch had never run against real input before.

**A reading note about KFENCE.** This boot produced no KFENCE report, and
Sunday's produced two. That is not a fix. KFENCE guards a small random
sample of allocations, 255 objects at a time, so a defect caught twice in
one boot can go unsampled in the next. The write past the end of that
eighteen byte `usb_device_descriptor` is still there. Absence of a report
is absence of a sample.

**And the thirty lines that describe something which cannot happen here.**
`/sys/fs/pstore` was still not mounted, so the question was finally put to
the board rather than reasoned about:

    journalctl -b | grep -i pstore
      only the kernel's own two lines

    ls -l /usr/lib/systemd/system/systemd-pstore.service
      No such file or directory

systemd never attempted the mount, never logged a failure, and does not
contain the service at all. This systemd was built without its pstore
component.

`bench-debug-image.bb` spends thirty lines explaining why
`systemd-pstore.service` must be masked, and masks it, against a unit this
image does not have. The mask is a symlink to /dev/null for a file that is
not there: harmless, and not the guard the comment says it is.

The consequence is the opposite of the one it worries about. That comment
fears an archiver moving records out from under the reader. What actually
happens is that nothing mounts the filesystem at all, so a crash record
sits in the backend while `/sys/fs/pstore` is an empty directory, which
reads exactly like the failure being guarded against. `docs/BRINGUP.md`
step 6 runs `mount | grep pstore` and expects a mount, and on Sunday that
step was a false negative.

**What was done.** A `sys-fs-pstore.mount` unit, installed by the image
and wanted by `sysinit.target`. The mask stays, relabelled as insurance
against a later layer bringing the service in rather than described as
preventing something current.

**Why not simply correct BRINGUP instead.** Because the document was
right. A debugging lab should have its crash records visible at a path
every instruction ever written about pstore names. Teaching the reader to
mount it by hand each boot moves the cost onto the person who is already
dealing with a crash.

**Seen on hardware the same evening.** The image rebuilt in 1 min 45 s,
archived as `2026-10-05_a743c9c`, and the boot log carries systemd doing
it rather than anyone typing:

    systemd[1]: Mounting Persistent Store File System...
    systemd[1]: Mounted Persistent Store File System.

and after login, with nothing typed first:

    pstore on /sys/fs/pstore type pstore (rw,nosuid,nodev,noexec,relatime)

`docs/BRINGUP.md` step 6 is true as written for the first time since the
project was created.

The unit text was proven before the rebuild rather than by it. It was
written into `/run/systemd/system` on the running board over ssh and
started by hand, which tested the syntax, `Type=pstore` and the options
without costing a card. `/run` is a tmpfs, so it left nothing behind.
What the rebuild added was the half that could not be tested that way:
that the image installs the file and that the `sysinit.target.wants`
symlink makes systemd pull it in at the right point in the boot.

**And that boot found a second KFENCE defect.** A two byte `kmalloc`
buffer in `usb_get_status`, allocated and freed 300 microseconds apart
inside one call, with two canary bytes changed at free time. A different
site from the eighteen byte `usb_device_descriptor` in `hub_port_init`,
and it had never appeared before. Both reports are now in
`notebook/06-lockdep-kasan.md` as part four, raw, with a table of what
three boots sampled. The third boot caught neither, which is what KFENCE
sampling looks like rather than evidence that anything was fixed.

**The third of its kind this week.** Project 10's image recipe asserts
that the gpio-led overlays claim those lines so libgpiod cannot open them,
which was never true on any card. `leds.conf` ships a Pi 4 chip label that
never matches on a Pi 3, so the width fallback is the normal path rather
than the exception its own comment calls it. And now thirty lines about a
service that is not installed. All three are correct reasoning about a
premise nobody put to a board.

## 23. Tuesday 6 October 2026: the oops decoded, and an hour lost to a carriage return

Acceptance criterion 1 is met. The console carried the NULL dereference,
`decode.sh` resolved it to `buggy.c:109`, and the line it names is
`victim->magic = 0x1234;`. Entry 01 of the notebook now holds the raw
oops, the decoded trace, the tool versions and the conclusion, which makes
it the first of the six to carry real output end to end.

**The thing that makes the decode trustworthy was not planned.** This
entry has always warned that decoding against the wrong `vmlinux` does not
fail: it produces plausible function names from the other build and says
nothing about it. The register dump settled that by accident. `x2` holds
`0000000000001234`, and `0x1234` is the constant on line 109. A different
build would not have put it there, so the symbols and the running kernel
are the same build on evidence rather than on assumption. Worth copying:
when a tool cannot verify its own inputs, look for a value in the raw
output that only the right input could have produced.

**An hour went on a carriage return.** The first decode resolved every
kernel frame perfectly and neither module frame, reporting that the
modules path was not set. It was set, `decode.sh` printed it, the
directory was right and the module in it was unstripped. Three hypotheses
were formed and all three were wrong, each from reading part of the
problem rather than running it. `bash -x` answered it in one line:

    module=$'[buggy]\r'
    module=$'buggy]\r'

A serial console emits CRLF and picocom records the stream verbatim.
`decode_stacktrace.sh` strips a leading `[` and a trailing `]` from the
last token, and a carriage return sitting after the `]` makes the second
strip match nothing. Kernel frames never enter that branch because their
last token has no brackets, so the output looks almost right and only the
frames the oops was captured for are missing. `decode.sh` now strips CRs
before the parser sees the log and reports how many it removed. On this
bench a log can only arrive as a serial capture, so CRLF is the normal
case and not an edge one.

**Four things entry 01 said that the run contradicted**, all four written
when nothing had been run and left standing afterwards. The decode was
said to run on the authoring laptop, which has no aarch64 binutils and no
kernel source; it runs on JPTOUPM678. Every command carried `sudo`, which
does not exist on this image. The check list asked whether the heartbeat
LED went dark at the panic, when it freezes, and `docs/DESIGN.md` already
had the right word in its sequence figure. And the board was said to
reboot after ten seconds, when it reads `panic_on_oops 1` and `panic 0`
and halts: `CONFIG_PANIC_TIMEOUT` is set nowhere in this layer, so
`sysctl -w kernel.panic=10` is a runtime step that has to be typed on
every boot. The run only worked because it was typed.

That last one is a configuration gap and not just a documentation one. A
halted Raspberry Pi 3B+ can only be restarted by pulling the power, which
is a cold cycle, and the ramoops region is ordinary DRAM. The image as
built guarantees that a panic it was configured to capture is lost.

**The README said nothing had been run.** It had said so since the project
was created and it stayed true for a while. Two boots, three findings and
a met criterion later it was simply false, and nothing in the repository
could notice, because no test holds a sentence. Corrected along with the
notebook README, which carried the same `sudo` and the same ten seconds.

Two frames below the faulting one resolve one line past their call, which
looks like an off-by-one and is not: a frame holds a return address. Noted
in entry 01 so the next reader does not spend ten minutes on it.

## 24. Tuesday 6 October 2026: the second capture destroyed the first, and that is the finding

Acceptance criterion 2 is met. The oops ramoops kept across the reboot
matches the block in notebook entry 01 on all 46 lines, and the SysRq
crash produced its own record with `Kernel panic - not syncing: sysrq
triggered crash` in it. Both are in `docs/evidence/` as files rather than
as quotations.

**The run contradicted a prediction, and the wrong prediction was worth
more than a right one.** Before the crash I wrote down three expectations
so they could fail. Two held: one new record rather than two, because
SysRq calls `panic()` with no oops ahead of it, and no `O` in the taint
field, because nothing auto-loads the module. The third was that the new
record would be `dmesg-ramoops-2`, taking a free zone.

It was not. The crash overwrote `dmesg-ramoops-0`, which held the oops.
`fs/pstore/ram.c` says why at lines 366 and 389: `dump_write_cnt` is a
field of the in-RAM context, nothing restores it from the persistent
region, so it starts at zero on every boot and the first dump after any
reboot lands in zone zero no matter how many zones exist. The header
numbering agrees from the other side, `Oops#1` then `Panic#2` on the
crash boot, `Panic#1` on the next.

So entry 05's sentence about there being room for six records and the
seventh overwriting the first was wrong twice. Not the seventh crash, the
next boot's first crash. And the six was arithmetic on the overlay README
rather than a measurement.

**It also means criterion 2 asks for a state the hardware cannot be left
in.** Both captures exist and the board cannot hold both at the end. The
acceptance row now says that instead of passing quietly, because a row
that reads "met" and hides an impossibility teaches the wrong thing about
the next criterion.

**The reason the oops record still exists is a question asked yesterday.**
"are we saving first before wiping out" became the order of operations
today: three files copied off the board, byte counts compared against
`ls -l`, and only then a deliberate crash. Had the entry's own
instructions been followed, they say `rm -f /sys/fs/pstore/*` before
triggering, and the oops record would have been deleted on purpose in the
name of not confusing old records with new ones. The record headers make
that confusion impossible anyway.

**A control did the work that reading could not.** `kernel.sysrq` reads
`16`, sync only, and `sysrq_crash_op` carries `.enable_mask =
SYSRQ_ENABLE_DUMP`, so by the mask the crash should have been refused.
Rather than reason about which dispatch path checks the mask, SysRq `m`
was used first: it prints memory statistics, it carries the identical
enable mask, and it crashes nothing. It ran. So the gate the crash had to
pass was already known to be open, and nothing on the board needed
changing. Raising `kernel.sysrq` as a precaution would have changed two
things at once immediately before a deliberate crash, which is how the
`dwc_otg` workaround became unattributable.

**Two sloppy things I did in the same hour, both of the same shape.** A
`find` for `sysrq.c` piped to `head -n 1` handed me the NanoPi NEO Air
tree, and I read it and reported on it without saying which tree it was.
The conclusion survived only because the control had run on the actual
board; the source reading was corroboration from the wrong kernel and
could have corroborated nothing. Listing every match afterwards showed
both trees agree, so it happened to be right, which is exactly the
failure mode the kernel config checks had: right for the wrong reason,
and that teaches you to trust it.

The other was handing over a command containing a made up IP address,
`192.168.1.50`, as a placeholder. It was run as written and timed out.
A placeholder that is syntactically runnable is not a placeholder.

**Three things are open and named in entry 05 rather than guessed.** The
zone count, which two records at once bounds from below and does not
determine, and which no experiment crossing a reboot can measure now that
the cursor behaviour is known. The console zone, unchanged in size and
mtime across a fresh panic and a reboot at 32,756 bytes of 32,768, so not
currently recording. And the `-28` from entry 01's oops, whose two
candidate causes the first two items distinguish.
