# Journal: Project 14

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled
list of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that
and not the alternative**.

All entries are 22 September 2026 unless noted.

---

## 1. The same trap as Project 13, and the opposite answer

**What happened.** Project 13 had just been caught by drivers that are
modules in `bcm2711_defconfig` on an image that installs none, so the
first thing checked here was the same question rather than the
specification's next step.

```
  CONFIG_USB_GADGET=y      the framework is built in
  CONFIG_USB_DWC2=m        the controller driver is not
  CONFIG_USB_CONFIGFS=m    nor is the configfs interface
```

Same trap. The specification's answer, `/etc/modules-load.d/gadget.conf`
listing `dwc2` and `libcomposite`, is right on Raspberry Pi OS and would
produce a board with no gadget at all here.

**What was done.** Checked whether `=y` was reachable, which is the step
Project 13 could not take:

```
  config USB_DWC2      tristate   depends on USB || USB_GADGET
  config USB_CONFIGFS  tristate   select USB_LIBCOMPOSITE
```

`CONFIG_USB=y` and `CONFIG_USB_GADGET=y` already, so both are reachable.
The fragment sets them and this image installs no modules.

**Why that and not `kernel-modules`.** Because it is available. Project
13 had to install the module set because `DRM_VC4 depends on SND`, which
is itself `=m`, and a tristate depending on a module can be at most a
module. Here nothing blocks `=y`.

**The general form, and it is the useful part.** Two projects met the
same symptom a day apart and the correct fixes were different, and the
thing that decided it was neither judgement nor precedent: it was reading
the `depends on` line. **A trap that recurs does not imply a remedy that
recurs.**

---

## 2. Seven promptless symbols, up from Project 9's four

**What happened.** Writing the fragment, the function drivers looked like
ordinary options to request.

**What was done.** Read them first.
`USB_LIBCOMPOSITE`, `CONFIGFS_FS`, `USB_F_ECM`, `USB_F_NCM`,
`USB_F_ACM`, `USB_F_HID`, `USB_U_ETHER` and `USB_U_SERIAL` are all bare
`tristate` with no prompt string. The four that ARE settable are the
`USB_CONFIGFS_*` booleans, which select them.

**Why this keeps being an entry.** Because the failure is invisible:
writing a promptless symbol in a fragment produces no error, no warning
and no effect. Project 9 found four, this is eight, and the count going
up is not the point. The point is that the check costs one `grep` per
symbol and the alternative is a kernel that builds, boots, and does not
have the thing that was asked for.

---

## 3. The descriptor needed a tool the board may not have

**What happened.** The specification converts the annotated hex report
descriptor on the target:

```
  xxd -r -p /usr/local/share/bench-gadget/hid-keyboard.desc > .../report_desc
```

BusyBox may or may not carry `xxd`, depending on how it was configured.

**What was done.** Moved the conversion into the recipe, as a BitBake
python task, and installed bytes on the board. The annotated hex is still
what is checked in, which is the property the specification's "best
practices" section actually asks for.

The task **asserts the result is 63 bytes**, plus two structural checks
on the first and last octets.

**Why the assertion is worth more than the conversion.** A descriptor
short or long by one octet is not a syntax error. It is a valid tree that
the host parses differently, and the symptom is a keyboard that
enumerates cleanly and types nothing: no message on either side. Catching
it at build time, with the byte count in the error, turns a bring-up
mystery into a build failure.

The count was checked against the shipped file before the assertion was
written, so the assertion is a fact rather than a hope.

---

## 4. Inverting the kernel's usage table is ambiguous, and silently so

**What happened.** The bridge needs Linux keycode to HID usage. The
kernel has the inverse, `hid_keyboard[256]` in `drivers/hid/hid-input.c`,
indexed by usage. The specification says to generate the table rather
than type it, which is clearly right for 160 numbers.

What it does not say is that **the forward map is not injective**. Seven
keycodes have more than one usage in `rpi-6.6.y`:

```
  keycode 43  <- usages 0x31, 0x32
  keycode 111 <- usages 0x4c, 0x9c, 0xd8
  keycode 113 <- usages 0x7f, 0xef
  keycode 114 <- usages 0x81, 0xee
  keycode 115 <- usages 0x80, 0xed
  keycode 128 <- usages 0x78, 0xf3
  keycode 136 <- usages 0x7e, 0xf4
```

A generator that iterated in the other direction, or used a dict without
thinking, would pick the **last** one and produce a table that is wrong
for seven keys and looks completely normal.

**What was done.** The rule is written down and enforced: lowest usage
wins, because the duplicates are alternate national-layout positions and
keypad variants that a boot-protocol keyboard does not distinguish. All
seven collisions are **listed in the generated header**, so the choice is
visible to whoever reads it next.

The generator also spot-checks three keycodes against the HID usage
tables and refuses to write the header if they disagree, so a kernel that
reshapes the array cannot silently produce a plausible file.

---

## 5. A comment asserted a bug that does not exist

**What happened.** Rewriting the teardown to use `if` rather than
`[ -d X ] && rmdir X`, the justification written into the comment was
that under `set -e` the second form exits the script when the test fails,
halfway through the teardown.

**What was done.** Tested it, because it is three lines:

```sh
set -eu
echo reached-1
[ -d /definitely/not/here ] && rmdir /definitely/not/here
echo reached-2
```

`reached-2` printed and the exit status was 0. **The claim was wrong.**
`errexit` is suppressed for a command whose status is being tested, and
the left operand of `&&` is such a command.

The `if` form was kept, because it is clearer and because keeping one
shape means the genuinely dangerous three-part form `A && B || C` never
gets written by habit. The comment now says that is the reason, and says
which argument is the wrong one.

**Why this is an entry.** It is the Project 8 mistake in miniature: an
observation (this form is worth avoiding) and a mechanism (because set -e
exits) written in the same voice, where only the first was checked. The
correction cost one command.

---

## 6. Teardown aborted halfway, and the trigger was not the bug

**What happened.** Running the script against a fake configfs tree, `down`
printed three `rm` errors and then stopped. It never reached its final
line and left the whole tree in place.

The immediate cause was an artefact: Git Bash without privileges copies
directories for `ln -s`, so the function links were real directories and
`rm -f` refused. On a real configfs they are symlinks.

**What was done.** Not dismissed as a test artefact, because the
behaviour it exposed is real: **any** failure in `down` aborted the rest
of it under `set -e`, and the state left behind is the half-removed tree
that makes the next `up` refuse. The unit's `ExecStopPost` gets no third
chance.

`down` now runs every step regardless, names each thing it could not
remove, and ends with `PARTIAL teardown` and exit 1 when the tree is
still there. `up` stays fail-fast, which is the opposite policy and the
right one for it: continuing to build after a failure produces a tree
that cannot bind.

**Why this is an entry.** The trigger was environmental and the weakness
was not. A test on the wrong platform still told the truth about the
code, and the useful discipline was separating what caused the failure
from what the failure revealed.

---

## 7. The feature test macro, again

**What happened.** `kbd_bridge.c` uses `usleep` and `mkfifo`.

**What was done.** `#define _DEFAULT_SOURCE` before the includes.

**Why.** Both are POSIX rather than ISO C, so a strict `-std=c99` build
does not declare them, and the compiler treats them as implicitly
declared functions returning `int`. On a 64-bit target that is a real
bug, not a style warning. Project 8 lost time to the same shape with
`_POSIX_C_SOURCE` and `cpu_set_t`.

Put in the source rather than the build flags, so the file compiles the
same way wherever it is built.

---

## 8. The artefact audit passed, and three deliverables were still missing

**What happened.** With everything written, the project was audited the
way Project 13 was: every path and every command named in the documents,
checked against the tree. It came back clean, 17 artefacts across 7
documents, no problems.

Then the specification's own **repository layout** was read against the
tree rather than the documents, and three named artefacts did not exist:

```
  host/linux/70-pi-gadget.rules          MISSING
  host/linux/nm-pi-gadget.nmconnection   MISSING
  host/windows/README.md                 MISSING
```

plus one behaviour from step 9: **right Ctrl plus M replays the last
macro**, which was not implemented.

**What was done.** Wrote all four. The host files live under
`projects/14-usb-gadget/host/`, which is the convention Project 9
established for things that run on the developer's machine and belong in
no image.

**Why the audit could not have caught it.** The audit checks that every
artefact a document NAMES exists. These three were named by the
specification and by no document in the repository, so there was nothing
to follow. **An audit of internal consistency cannot find a missing
deliverable**, because a project that never mentions a thing is perfectly
consistent with not having it.

This is the same shape as Project 13's missing `kernel-modules`, found
the same way: by reading the specification's requirements against the
tree rather than the documentation against itself. Both times the tooling
was green and the project was incomplete.

The cheap habit that catches it: **the specification's file list is a
checklist, and it gets ticked off against `ls`, once, at the end.**

---

## 9. Two deviations recorded rather than left implicit

**`meson` was not used.** The specification's layout has
`bridge/meson.build`. The bridge is one C file with one dependency, and
every other C program in this layer is compiled by its recipe with
`${CC}` and `pkg-config` directly: `bench-status`, `lte-gpio`,
`rt-toggle`, `drmfill`. Adding a build system for one file would make it
the odd one out and would give CI a second thing to install.

**The macro hotkey consumes its key.** The specification says right Ctrl
plus M replays the last macro and does not say what happens to the M. It
is swallowed, press and release, because forwarding it as well would type
the letter in front of the macro. Written down because it is a choice the
specification left open rather than one it made.

---

## 10. What is not done

Stated plainly, because an acceptance table with blanks invites the
assumption that the blanks are oversights.

**Nothing has been built and no board has enumerated.** Every measured
row is empty and every output block in `docs/DESCRIPTORS.md` says `NOT
YET RUN`.

What the 37 assertions do and do not prove is written at the top of the
suite, and the honest half is this: **nothing in this repository speaks
USB.** The configfs tree is built and torn down against an ordinary
directory, which accepts values the kernel would refuse. The order is
proven; the content is only checked against what the specification says
it should be.

Known to need a board:

1. Whether `bNumInterfaces` really comes out as 5 and the ACM symlink
   really ends in `if02`. Both are predictions in `DESCRIPTORS.md` and
   both are written there as predictions rather than as facts.
2. The keyboard's vendor id. The udev rule ships with `04d9` because that
   is what the official Raspberry Pi keyboard reports, and a rule that
   matches nothing fails silently.
3. Whether a Pi 4 on a 500 mA port stays up with the keyboard attached.
   `arm_freq=1000` is applied in advance because the failure is a reset
   rather than a message.

**This laptop has no compiler**, so `kbd_bridge.c` has never been built.
Delimiters balance and every header it needs is included, which catches a
misremembered name and nothing else. CI compiles it; that is where the
first real check happens.
