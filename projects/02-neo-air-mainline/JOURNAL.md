# Journal: Project 2

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

All entries are Friday 18 September 2026 unless noted.

## 1. The specification first, and the ownership table earned its place

The method this repository settled on after Project 1 got it backwards:
read the specification, write the design document with every specified
figure redrawn as text, and only then write code.

Four figures were asked for and all four are in
[docs/DESIGN.md](docs/DESIGN.md). Redrawing the boot chain as addresses
rather than arrows is what made the two numbers visible: the bootloader at
byte 8192, the first partition at sector 2048. Everything dangerous in this
project is about the gap between them.

The ownership table found three places where two things write one resource,
which is exactly what it exists for:

- the micro USB port is the 5 V supply during normal work and the FEL
  recovery port when the PC is host, and the two are mutually exclusive
- `extlinux.conf` is written by the rootfs build and rewritten by the
  provisioning script
- `/etc/fstab` likewise

The last two are deliberate: the overlay cannot know the `PARTUUID` of a
partition that does not exist when the overlay is written. So the decision
recorded is what the overlay ships instead.

**A placeholder that cannot boot, rather than a value that might.**
`root=PARTUUID=FILLED-BY-FLASH-EMMC` fails at the first attempt with the
reason on the console. A stale `PARTUUID` copied from a previous card boots
the wrong filesystem, or drops to a prompt naming a device that really does
exist somewhere else, and both of those are hours.

## 2. A refusal the specification does not have

`flash-emmc.sh` in the specification checks two things before it writes:
that a device reporting type MMC exists, and that it is not mounted.

Both of those pass on a board that is already booted from the eMMC. The
script then writes a bootloader over the one it is running from, partitions
the disk under itself, and the board is gone. The window is small and the
situation is not exotic: it is what happens the second time somebody runs
the provisioner, having forgotten to put the SD card back.

So there is a third refusal, comparing the target against the device
carrying `/`. And while testing it, a fourth: `dd` with a missing input
file writes nothing and reports success, so a missing bootloader image is
refused by name rather than discovered at the next power-on.

## 3. The guard that no laptop could reach

Both build scripts refuse to build inside the checkout. `.gitignore`
records why at length: a build tree in the repository once made every
archived image claim a dirty tree, so the provenance was wrong about the
one thing it exists to get right.

The guard was written after the toolchain check. `gcc-arm-linux-gnueabihf`
is not installed on the authoring laptop, so every attempt to reach the
guard stopped one line earlier, and it could not be tested on the machine
it was written on.

Configuration errors are now refused before the environment is probed. A
misconfigured `NEO_SRC` is wrong on every machine; a missing cross compiler
is wrong only on this one. Proved in both directions afterwards: it fires
when `NEO_SRC` is inside the checkout, and stays quiet when it is not.

## 4. Two tests the specification does not ask for, and what they caught

`flash-emmc.sh` runs on the board twice in this project's entire life. Both
times it is being trusted rather than tested, and it is the one program
here that can destroy the system it is running on.

So both destructive scripts are tested with fixtures and recording stubs:
a fake `/sys/block` so the target is discovered the way the real one is, a
fake `/proc/mounts`, overridable mount points, and stubs for `dd`,
`sfdisk`, `mkfs.ext4` and the rest that record their arguments and succeed.
No root, no loop devices, no board.

Writing them required one change to the code: the mount points were
hardcoded as `/mnt/e1` and `/mnt/e2`, which made the copy, bootconfig and
verify states untestable without writing to the real `/mnt`. They are now
`NEO_MNT1` and `NEO_MNT2`, which is the difference between a state machine
that is tested and one that is read.

**The tests caught two things, and both were in the tests.**

The assertion for sector 2048 failed against a script doing exactly the
right thing. The partition table is piped to `sfdisk` on **stdin**, not
passed as an argument, so a stub that records only `argv` cannot see the
single most important number in the project. `sfdisk` now has its own stub
that records both.

That is worth stating as a rule rather than a fix: a stub that captures
less than the program consumes will report a correct program as broken, and
the tempting response on the next reading is to weaken the assertion rather
than the stub.

The second was the same shape. The write-order assertion in the card test
matched `sfdisk /dev/sdz` while the stub records `sfdisk -q /dev/sdz`, so
the pattern found nothing, the comparison ran against one line number, and
a correct script failed. Anchored on the command name now.

## 5. Proving the order assertion, and three path failures on the way

The write order in `sdcard.sh` is a real decision. `sfdisk` writes sector
0, so a bootloader written first loses its first 512 bytes to it. The
`eGON.BT0` header at byte 8192 survives either order and the SPL that
follows does not, which means the wrong order produces a board that reads
its header, starts, and dies with nothing on the console.

An assertion that cannot fail is not an assertion, so it was proved by
swapping the two writes in a copy and watching exactly that one fail. It
took four attempts, all of them environment rather than logic:

- `/tmp` in Git Bash is a Windows path that native Python cannot open
- a Windows-style `TMPDIR` makes `mktemp -d` return `C:/Users/...`, and a
  Windows path in `PATH` is never searched, so the stubs were ignored and
  the **real** `dd` ran against `/dev/mmcblk1`
- exact-block text matching across a heredoc was fragile; line numbers were
  not
- `sdcard.sh` finds the overlay relative to its own directory, so copying
  the script alone into a scratch folder broke it. The whole project tree
  has to be mirrored

The second of those is the one that matters. A test harness whose stubs are
silently not on `PATH` does not fail: it runs the real tools. The only
reason it was noticed is that the real `dd` said `Permission denied` on a
device that does not exist on this laptop.

## 6. What is deliberately not done yet

No cross toolchain is installed here, so the build scripts have been
exercised only as far as their refusals. Nothing has compiled. The board is
in its box and the console cable is not attached.

The order that follows is deliberate and is in
[docs/BRINGUP.md](docs/BRINGUP.md): the console cable is attached and
`picocom` is already running before the board is first powered, so the SPL
banner is captured rather than missed. It is the first line of evidence in
the project and it appears about a second after power, once.

## 7. The first build, and two guards that were wrong before the compiler was

The cross toolchain went onto JPTOUPM678 and `./go neo-air uboot` ran for
the first time. Three things went wrong before a single object compiled,
and two of them were mine.

**`qemu-user-static` does not exist on Ubuntu 26.04.** It is a virtual
package now, provided by `qemu-user-binfmt`, and `apt` refuses to pick a
provider for you. The whole install failed on that one name, so nothing was
installed at all.

The consequence in `mkrootfs.sh` was worse than the apt message, because it
was silent. The script copied `$(command -v qemu-arm-static)` into the
chroot with a `|| true` after it, and on this release there is no such
binary: only a dynamically linked `/usr/bin/qemu-arm`. So it would have
copied nothing and said nothing, and whether the second stage worked would
have come down to a binfmt flag the script never looked at.

It now reads the flag. A registration carrying `F` keeps the interpreter
open across a chroot and nothing needs copying; without it, a binary is
copied, preferring the static one and falling back to the dynamic. The
board's registration exists and the flag is the next thing to check when
the rootfs step runs.

**My own U-Boot guard refused a build that had just done the right thing.**
`merge_config.sh` printed

    Value of CONFIG_MMC_SUNXI_SLOT_EXTRA is redefined by fragment ...
    Previous value: CONFIG_MMC_SUNXI_SLOT_EXTRA=-1
    New value: CONFIG_MMC_SUNXI_SLOT_EXTRA=2

and the script treated the word "redefined" as failure. That line is the
fragment overriding the defconfig, which is the entire purpose of the
fragment, and that particular symbol is the one that makes U-Boot see the
eMMC at all. So the guard fired on success, on the single most important
line in the file.

It was also redundant. The check immediately after it compares every
fragment line against the produced `.config`, which is the question that
matters: not what the merge said about its work, but whether the option is
there. That check passed on the next run and printed `every fragment option
is present in .config`.

This repository has now documented four guards that refuse on evidence they
should not, three of them in other people's scripts and this one in mine,
written the day after writing the decision that names the pattern.

**Then the compiler, and this one is not a bug anywhere.** The build
stopped in `scripts/dtc/pylibfdt`:

    libfdt_wrap.c: error: too few arguments to function
    'SWIG_Python_AppendOutput'; expected 3, have 2

SWIG 4.3 added a third argument to that function. U-Boot `v2024.10` carries
a copy of dtc whose typemaps still call the two-argument form, and Ubuntu
26.04 ships SWIG 4.4. `pylibfdt` is not skippable here, because
`u-boot-sunxi-with-spl.bin` is a binman image and binman needs it.

Three options, and only one of them leaves the project honest:

- patch the vendored dtc inside a pinned tree, which makes the pin a lie
- hold the host's SWIG back, which makes the build depend on an apt pin
  that nothing in this repository can state
- move the tag, and record why

`UBOOT_TAG` is now `v2025.10`, which is also the vintage of the host's own
`u-boot-tools`. The reason is written where the pin is, not only here,
because the next person to read `toolchain.env` will be looking at the
number rather than at this file.

The expected SPL banner in `docs/BRINGUP.md` moved with it. A milestone
that names a version is a claim, and it was one line away from being a
stale one.

## 8. The session itself: forks, dead ends, and what transfers

Entry 7 records what was wrong with the code. This one records how the day
went, because the reusable part of a bring-up is rarely the bring-up.

Project 2 went from nothing to a pushed, tested, half-built project in one
sitting. The order below is the order it happened in.

### Timeline

| Step | What |
|---|---|
| 1 | specification read in full, 351 lines of it, before a file existed |
| 2 | two scoping questions asked: is the hardware here, and where does a project with no Yocto live |
| 3 | DESIGN.md, four figures redrawn as text, ownership table |
| 4 | toolchain.env, both build scripts, both fragments |
| 5 | guard ordering fixed after it proved unreachable on this laptop |
| 6 | flash-emmc.sh, then its test, then two changes to the code the test forced |
| 7 | sdcard.sh, its test, and four failed attempts at one negative test |
| 8 | mkrootfs.sh, fel-boot.sh, overlay, README, JOURNAL, BRINGUP |
| 9 | committed and pushed, 18 files, CI green after one SC2154 fix |
| 10 | ./go neo-air added, because the repository claims one entry point |
| 11 | disk and archive inventory, on request rather than on habit |
| 12 | toolchain installed, three failures before one object compiled |
| 13 | UBOOT_TAG moved, reason recorded beside the number |

### The forks, and what was not chosen

**Where does a project with no Yocto live?** Options were a separate
neo-air-mainline repository, which is what the specification literally
names, or `projects/02-neo-air-mainline/` inside the bench. Chose inside,
because Project 4 already keeps scripts under `projects/` so there was
precedent, and because a second repository means a second CI, a second
journal and a second place to forget. The cost showed up hours later:
`./go` had nothing to dispatch to, which is what produced the
`./go neo-air` target.

**Where do sources and artefacts go?** The specification puts an `out/`
directory in the project. Chose `$NEO_WORK` outside the checkout instead,
which is a direct departure from the text. The reason is in `.gitignore` at
length: a build tree inside the checkout once made every archived image in
this repository claim a dirty tree, so the provenance was wrong about the
one thing it exists to get right. A specification is a starting point, and
this repository has already paid for the other answer.

**How is the PARTUUID placeholder written?** Three candidates. Leave the
field absent. Ship a plausible value copied from a previous card. Ship
something that cannot possibly work. Chose the third,
`root=PARTUUID=FILLED-BY-FLASH-EMMC`. Absent and plausible both fail late
and quietly; a value that cannot parse fails at the first boot with the
reason on the console, and the console is the only way into this board.

**Should `./go neo-air` be a case block in `go` or its own dispatcher?**
`go` is deliberately thin, one line per target, and a six-way case block
would have been its first exception. Chose a dispatcher in the project
directory plus one line in `go`. That also gave somewhere to put the disk
guard and the `toolchain.env` sourcing, which removed the two things a
caller previously had to remember and get right.

**Patch, pin the host, or move the tag?** When SWIG 4.4 refused to build
v2024.10's vendored dtc, all three were available. Patching a vendored tree
inside a pinned tag makes the pin a lie. Holding the host's SWIG back makes
the build depend on an apt pin nothing in this repository can state. Moving
the tag leaves one honest number in one file, so that is what happened, and
the reason lives next to the number rather than only in this journal.

### Dead ends, all of them environmental

Four attempts went into proving one assertion in `neo-air-sdcard-test.sh`,
and not one of them failed for a reason about the code:

1. `/tmp` in Git Bash is a Windows path that native Python cannot open.
2. A Windows-style `TMPDIR` makes `mktemp -d` return `C:/Users/...`, and a
   Windows path in `PATH` is never searched. The stubs were therefore
   ignored and the real `dd` ran against `/dev/mmcblk1`. It was noticed
   only because that device does not exist on aquamarine and the kernel
   answered `Permission denied`.
3. Matching exact blocks of text across a heredoc was fragile. Line numbers
   were not.
4. `sdcard.sh` locates the overlay relative to its own directory, so
   copying the script alone into a scratch folder broke it. The whole
   project tree has to be mirrored.

The second is the one to keep. **A test harness whose stubs are silently
absent from PATH does not fail. It runs the real tools.** That is worse
than a broken test, because a broken test is loud.

A fifth dead end happened while writing this very entry: a shell heredoc
carrying the text failed to parse and wrote nothing. The skill already says
to use a file rather than a heredoc for anything long, and the second
attempt did that.

### The tally nobody wants

Four guards have now refused on evidence they should not have, and the
fourth was written the day after the decision naming the pattern:

| Guard | Refused because | Should have |
|---|---|---|
| require_no_running_build | a pgrep matched an idle BitBake server | matched the client invocation, and printed the pid |
| newest_path | it ranked a symlink against its own target | resolved with readlink -f first |
| kas.sh | a configuration name lacked a bench- prefix | accepted both spellings, as its own helper promises |
| uboot/build.sh | merge_config.sh said "redefined" | not parsed that output at all |

The fourth is the instructive one. The word "redefined" appeared on the
single most important line in the fragment, the one that makes U-Boot see
the eMMC, and the guard treated the fragment doing its job as failure.
Writing a decision about a pattern is not the same as not repeating it.

### Two habits that had to be asked for

**Check the disk before proposing a build.** Not after it fails. The number
that matters under WSL is the Windows one, and today it read 24.75 GB free
while the guest claimed 917. Project 2 costs about 10 GB, so the right
answer was to build and delete nothing, which is only knowable by asking
first. Project 2's build entry point had no disk guard at all while the
Yocto side has had one since a build filled a 254 GB drive and took the
filesystem read-only.

**Check what is archived before proposing a deletion.** Three read-only
commands found that the pair of images the entire Project 8 matrix was
measured on existed only inside the VHDX. Safe from `./go clean`, not safe
from the virtual disk this bench has already compacted, filled to
read-only and rebuilt. The distinction had never been written down: an
image in `~/bench/images` reads as archived and is one tier short of it.
976 MB of rsync closed the gap.

**And name the machine in every command.** Two laptops, one repository
name, one directory name, similar prompts. Saying "that laptop" makes the
reader decode before they can act. Both identifiers are now a table in the
skill: aquamarine authors, JPTOUPM678 builds.

### What transfers, and where it went

The bring-up specifics stay with the NEO Air. These do not:

| Learning | Recorded as |
|---|---|
| A test stub captures everything the program consumes, not only argv. sfdisk is configured on stdin, and the most important number in this project was invisible to a stub that recorded arguments | decision 98 |
| A placeholder that cannot work beats a value that might. Impossible fails once and loudly; plausible-but-stale fails later, quietly, somewhere else | decision 99 |
| A pinned input against a moving host: move the number and record why, beside the number. Never patch inside the pin, never depend on a host pin the repository cannot state | decision 100 |
| Configuration errors are refused before the environment is probed, so guards stay reachable on machines that cannot run the build | both build scripts, and entry 3 |
| Check the disk, and the archive, before proposing a build or a deletion | the skill, with the cost table and the two tiers of safe |
| Name the machine in every command, by identifier | the skill, as a table |

The first is the one worth the most. Every test in this repository that
uses recording stubs has the same exposure, and the failure mode is not a
false pass. It is a **false accusation**: a correct program reported as
broken, whose natural fix on the next reading is to weaken the assertion
rather than to widen the stub.

## 9. The dependency check could only see executables, and the first artefact

The bootloader builds. `u-boot-sunxi-with-spl.bin`, 513912 bytes, is the
first artefact this project has produced, and the last three failures
before it were all the same failure wearing different clothes.

### What happened, in order

With `UBOOT_TAG` moved to `v2025.10`, SWIG was satisfied and `pylibfdt`
disappeared from the output entirely. The build got as far as the host
tools and stopped:

    tools/mkeficapsule.c:20:10: fatal error: gnutls/gnutls.h:
    No such file or directory
    make[1]: *** [scripts/Makefile.host:114: tools/mkeficapsule.o] Error 1

Forty seconds in. `sudo apt install -y libgnutls28-dev` pulled twelve
packages, 13.4 MB, and the next run went all the way through.

### The finding, which is not the package

`uboot/build.sh` says in its own header that it names whichever dependency
is missing rather than failing partway through a make. Then it failed
partway through a make.

The check was this:

    for tool in bison flex swig dtc make; do
        command -v "$tool" >/dev/null 2>&1 || die ...
    done

`command -v` answers a question about **executables**. U-Boot's host tools
also need development headers, and a header is not an executable, so the
entire class was outside what the check could see. It was true about the
thing it looked at and silent about the rest.

That is this repository's oldest recurring shape, and it now has four
instances. The kernel-config check that passed vacuously on Project 8's
control arm. `newest_path` ranking a symlink against its own target. The
merge guard reading `merge_config.sh`'s prose instead of the produced
`.config`, yesterday. And this. Every one of them reported honestly on a
narrower question than the one being asked.

### The fix, and the option that was rejected

Two ways to test for a header from a shell script.

**A path test**, `[ -r /usr/include/gnutls/gnutls.h ]`. Rejected. The
include directory is multiarch, differs between distributions, and a
hardcoded path is a second wrong answer that happens to be right on one
machine. The failure mode is worse than the one being fixed: a guard that
refuses on a host where the header is present and simply lives elsewhere.

**`pkg-config --exists`**, which asks the system where its headers are
rather than assuming. Chosen. `gnutls` and `openssl` are both checked,
because `libssl-dev` is the same exposure and was in the package list only
by luck.

`pkg-config` can itself be absent, and there the script says so out loud:

    --- pkg-config is absent, so the header check is skipped
    ---            a missing development header will surface as a
    ---            compile error partway through the build

A skipped check that announces the skip is a different object from a check
that quietly passes. The second is what produced the Project 8 control
problem in the first place.

### Exercised before it was believed

The new check was run in all three states with a standalone harness rather
than by reading it:

| State | Result |
|---|---|
| library absent | dies, names the library, prints the apt line |
| both present | passes, build continues |
| `pkg-config` itself absent | notes the skip, continues |

The middle row is the one that is easy to skip and the one that would have
turned a fix into a new blocker.

### What the successful build says, for the next reader

Worth reading in that output rather than scrolling:

- `Value of CONFIG_MMC_SUNXI_SLOT_EXTRA is redefined by fragment`, then
  `Previous value: -1`, `New value: 2`. That is the fragment overriding the
  defconfig on the one option that makes U-Boot see the eMMC. Yesterday
  this line was treated as an error and refused a correct build. Today it
  is printed and ignored, and the check that follows it,
  `every fragment option is present in .config`, is the one that carries
  the claim.
- `DTC arch/arm/dts/sun8i-h3-nanopi-neo-air.dtb`, in a list of twenty-six
  sunxi boards. U-Boot builds every board in the family and picks one.
- `MKIMAGE spl/sunxi-spl.bin`, then `MKIMAGE u-boot.img`, then `BINMAN`.
  Binman is what concatenates SPL and U-Boot proper into the single file
  written to byte 8192, and binman is why `pylibfdt` was not skippable and
  why the tag had to move.
- `HOSTLD tools/mkeficapsule` now appears in the first twenty lines, near
  the top of the host-tool phase. That is how early the failure was, and
  how cheap a start-of-run check would have been.

### 513912 bytes, and what is in them

Not a round number and not meant to be. SPL is the first 32 KiB of it, the
part the boot ROM copies into SRAM before there is any DRAM; U-Boot proper
is the rest, running from DRAM the SPL has just initialised. One file,
written to one address, because the boot ROM only knows one address.

Nothing has touched hardware yet. The next artefact is the kernel, then the
root filesystem, and the root filesystem cannot be built before the kernel
because `brcmfmac` is a module and a filesystem built first is a board with
no Wi-Fi and nothing in `dmesg` to say why.

## 10. The fragment check earned its keep, and one of the two defects had no symptom

The kernel builds: `6.12.0`, `zImage`, the device tree from
`arch/arm/boot/dts/allwinner/`, and `brcmfmac.ko` where `mkrootfs.sh` will
look for it. Getting there took one refusal and two unrelated defects in a
file that had been read several times and looked right.

### What the guard said

    kernel/build.sh: these fragment options are not in the built .config:
    CONFIG_MMC_PWRSEQ_SIMPLE CONFIG_CFG80211 CONFIG_MAC80211
    CONFIG_BRCMFMAC CONFIG_BRCMFMAC_SDIO
           Requested and absent. Do not build on top of this.

Five of the fragment's sixteen options. This is the failure the check was
written for, and it is the first time in this repository that the check
fired on its first real run rather than after a board had already been
flashed.

### The wrong hypothesis, and why it was wrong

Three of the four wireless options share `=m`, so the reading that arrived
first was that `sunxi_defconfig` has no `CONFIG_MODULES`, which would make
every module request unsatisfiable and take `BRCMFMAC_SDIO` down with
`BRCMFMAC`. One cause, four symptoms, and it fit.

It was wrong. The `.config` has `CONFIG_MODULES=y` at line 654. The `=m`
pattern was a coincidence, and the shared cause was one line further down:

    895: # CONFIG_WIRELESS is not set

`sunxi_defconfig` closes the entire wireless menu, and cfg80211, mac80211
and everything under `drivers/net/wireless` lives inside it. Still one
cause and four symptoms, but not the one the pattern suggested.

Worth recording because the reasoning was sound and the conclusion was
false. Two commands settled it and neither cost anything. The habit that
matters is not guessing better, it is reaching for the cheap read before
committing to the shape that fits.

### The defect that would never have shown a symptom

`CONFIG_MMC_PWRSEQ_SIMPLE` is not a Kconfig symbol. The symbol is
`PWRSEQ_SIMPLE`, in `drivers/mmc/core/Kconfig:26`. The name that looks
right is `mmc-pwrseq-simple`, which is the **device-tree compatible
string** in `sun8i-h3-nanopi-neo-air.dts`, and the fragment's own comment
names it two lines above the wrong request. Two namespaces that read alike,
one of them borrowed for the other.

kconfig does not object to a symbol it has never heard of. There is no
warning and no line in `.config`. The request simply evaporates.

And here is the part worth keeping. `PWRSEQ_SIMPLE` is `default y`, so
`.config` already had `CONFIG_PWRSEQ_SIMPLE=y` at line 3586. The driver was
present. The board would have worked. The fragment would have carried a
line that did nothing, for the entire life of the project, and no test, no
boot and no measurement would ever have disagreed with it.

That is a defect with no symptom, found by a check that compares requests
against results rather than watching for failures. Nothing else in this
repository would have caught it, because there was nothing to catch.

### One cosmetic oddity, noted so the next reader does not chase it

`merge_config.sh` printed this:

    Value of CONFIG_WIRELESS is redefined by fragment ...
    Previous value: # CONFIG_WIRELESS is not set
    New value: # # CONFIG_WIRELESS is not set CONFIG_WIRELESS=y

The "New value" line is mangled. It is a display artefact of how that
script builds the message when the previous value is a `# ... is not set`
comment rather than an assignment. The merge itself is correct:
`CONFIG_WIRELESS=y` is in `.config` as an exact line, which is what the
check asserts and what it confirmed.

Two days ago this repository refused a correct build because a guard read
`merge_config.sh`'s prose. The prose is now printed and not parsed, which
is the only reason this line was an oddity to note rather than a second
false refusal.

### What the build produced

| Artefact | Where |
|---|---|
| `zImage` | `$NEO_OUT` |
| `sun8i-h3-nanopi-neo-air.dtb` | `arch/arm/boot/dts/allwinner/`, the post-6.5 path |
| `modules/lib/modules/6.12.0` | with `brcmfmac.ko`, `cfg80211.ko`, `mac80211.ko` |
| `kernel-version` | `6.12.0`, which is what unlocks `mkrootfs.sh` |

The dtb fallback in `build.sh` chose the `allwinner/` path, so the case it
was written for is the case that occurred. Three
`-Wunterminated-string-initialization` warnings appeared from
`drm_dp_dual_mode_helper.c`, `stmmac_ethtool.c` and
`power_supply_sysfs.c`. They are upstream, they are a warning class newer
than the tag, and they are not this project's to fix.

### The exposure this leaves open

Every kernel fragment in this repository asks for leaves and trusts the
defconfig for the branches. This one asked for four options inside a menu
its defconfig had closed. The Yocto projects' fragments have the same
shape and have never been checked for it, and their symptom would be the
same: a feature absent from a board that boots perfectly.

Recorded as decision 102.

## 11. The host moved again, and this time it moved under an instruction

Two days, two pinned-input-meets-moving-host failures. The first was SWIG
against U-Boot's vendored dtc and cost a tag. This one cost twenty-one
lines of documentation, because what moved was not an input. It was an
instruction this repository gives in nine files.

    $ sudo -E ./go neo-air rootfs
    sudo: preserving the entire environment is not supported,
    '-E' is ignored
    [sudo: authenticate] Password:
    mkrootfs: no /root/bench/neo-air/out/kernel-version.
           Build the kernel first: kernel/build.sh writes it.

Read the path. `/root/bench`, not `/home/bing/bench`. The kernel had been
built forty minutes earlier and the script could not see it.

### What actually happened

`toolchain.env` derived the work tree from `$HOME`:

    export NEO_WORK=${NEO_WORK:-${BENCH_WORK:-$HOME/bench}/neo-air}

Under `sudo`, `$HOME` is root's. `sudo -E` was the answer to that and had
been since the file was written. The build host's sudo does not implement
`-E`. It says so, on stderr, and then **runs the command anyway**.

So the warning scrolled past above a password prompt, every pin from
`toolchain.env` was gone, `$HOME` became `/root`, and the script went
looking for a kernel in a directory that has never existed.

### The refusal was the good part

`mkrootfs.sh` refuses without `$NEO_OUT/kernel-version`, and the comment
beside that refusal explains why: a root filesystem assembled before the
modules exist has an empty `/lib/modules/<version>/`, and the board then
boots perfectly with no wireless interface and nothing in `dmesg` naming a
cause.

That guard was written to catch a wrong **order**. It caught a wrong
**environment** instead, and named the state precisely enough that the
absolute path in the message was the whole diagnosis. A guard that prints
what it looked for, rather than only that it failed, costs one line and
answered a question nobody had thought to ask.

Worth setting against the tally in entry 8. Four guards in this repository
have refused on evidence they should not have. This is the first one to
refuse on evidence it was not written for and still be right.

### The fix, and the one that was rejected

**Rejected: tell the operator to use a different incantation.**
`sudo env NEO_WORK="$HOME/bench/neo-air" ./go neo-air rootfs` works
everywhere, because `env` is a program rather than a sudo feature. It is
also a thing to remember and get right at the exact moment somebody is
typing a password, which is the category of problem `./go` exists to
remove. A workaround that lives in a human's memory is not a fix.

**Chosen: stop reading `$HOME` and recover the invoking user instead.**

    _neo_home=$HOME
    if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ]; then
            _neo_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            [ -n "$_neo_home" ] || _neo_home=$HOME
    fi

`SUDO_USER` is set by sudo itself and survives an environment reset,
because the reset is what sets it. Asking `getent` rather than assuming
`/home/<user>` matters on a host where a home directory is somewhere else,
which is most build machines eventually.

Exercised in four states before it was believed, rather than read:

| State | NEO_WORK |
|---|---|
| root, `SUDO_USER=bing` | `/home/bing/bench/neo-air` |
| ordinary user | `/home/bing/bench/neo-air` |
| explicit `NEO_WORK` under sudo | honoured, unchanged |
| `BENCH_WORK=/srv/bench` | `/srv/bench/neo-air` |

### And the documentation, which was the larger half

`sudo -E` appeared twenty-one times: usage headers, refusal messages, both
READMEs, `BRINGUP.md`, and one test asserting that a refusal mentions it.
Every one of them told the operator to do something that does not work on
the machine this project is being built on.

They now say the same thing in one form: **sudo goes on the entry point,
never on the script.**

    sudo ./go neo-air rootfs
    sudo ./go neo-air card /dev/sdX
    sudo ./go neo-air fel

`./go neo-air` sources `toolchain.env` itself, so with sudo in front of it
the pins are established **inside** the sudo, where nothing can reset them.
That property was already in `build.sh`, written for a different reason,
and the comment above it said the environment was "exported so that a
sudo -E further down keeps it". The mechanism was right and the explanation
was wrong, and the explanation was what everything else was written from.

The test that asserted the refusal mentions `sudo -E` now asserts it names
`./go neo-air card`. That assertion existed to check the message is
actionable, and an actionable message that names a broken form is worse
than none.

### The shape worth keeping

A tool that warns and continues is more dangerous than one that fails.
`-E` refused to do its job, said so in one line, and then handed control to
a script that had every reason to believe its environment. Had sudo exited
non-zero, the failure would have been at the door with the reason attached.
Instead it arrived forty seconds later as a missing file in a directory
nobody recognised.

Recorded as decision 103.

The implementation is **sudo-rs 0.2.13-0ubuntu1.2**, the Rust rewrite that
Ubuntu now ships in place of the C sudo. It is not a broken sudo; it is a
different sudo that has not implemented an option, and it is honest about
that in the only way available to it. The lesson is not about sudo-rs. It
is that an instruction written against one implementation of a tool is a
claim about that implementation, and package managers replace
implementations without asking.

## 12. A missing component reads like a wrong package name

The sudo fix worked. `--- modules /home/bing/bench/neo-air/out/...`, the
right home directory, on the first attempt and with no `-E`. binfmt took
the branch it was supposed to:

    --- binfmt qemu-arm is registered with the F flag, so the
    ---            interpreter is already open and nothing is copied in

`debootstrap` ran both stages and installed the base system. Then:

    E: Unable to locate package firmware-brcm80211

### The sentence apt does not say

Read literally, that is "no such package". It is true and it is the wrong
thing to conclude. The package exists; it is in **non-free-firmware**, and
`debootstrap` writes a `sources.list` carrying `main` and nothing else.

Bookworm split `non-free-firmware` out of `non-free` precisely so that a
machine needing a Wi-Fi blob would not have to enable the whole of
non-free. The split is a good decision that creates this trap: the
component is newer than most people's habits, and apt's phrasing points at
the package name rather than at the index it searched.

The cost of believing apt here is an evening spent checking spellings,
searching for a renamed package, and eventually concluding that Debian
dropped the firmware. All while one line was missing from one file.

The fix is that line:

    printf 'deb %s %s main non-free-firmware\n' \
            "$DEBIAN_MIRROR" "$DEBIAN_SUITE" >"$ROOT/etc/apt/sources.list"

Tied to `DEBIAN_SUITE` rather than hardcoded, because on a suite older than
bookworm the component is plain `non-free`, and `DEBIAN_SUITE` is pinned.

### The same shape as everything else this week

| Tool | Said | Meant |
|---|---|---|
| kconfig | nothing | this symbol does not exist |
| kconfig | nothing | this menu is closed |
| sudo-rs | `-E` is ignored, on stderr, then continued | your environment is gone |
| apt | unable to locate package | your sources list has one component |

Four tools, four true statements, four wrong conclusions available to a
reader in a hurry. None of them lied. Each answered a narrower question
than the one being asked, which is decision 101 arriving from four
directions in three days.

### What was added while the file was open

The firmware install now prints what the radio will actually find:

    --- brcm firmware for this chip:
    ---            brcmfmac43430-sdio.bin
    ---            no NVRAM .txt here. It is the one vendor artefact in
    ---            this project: see docs/BRINGUP.md section 5.

`brcmfmac` wants two files and Debian packages one. The `.bin` is in
`firmware-brcm80211`. The NVRAM `.txt` beside it is board specific, Debian
does not carry the AP6212 one, and without it the driver loads the firmware
and then times out bringing the SDIO clock up. That failure reads exactly
like broken hardware, and it is the single most predictable evening in this
whole project.

**It prints rather than refuses,** deliberately. The `.txt` is the one
input this project cannot pin, and a refusal would block a build over
something that is fetched by hand afterwards. A refusal is for a state the
build can fix. This is a state the operator has to fix, later, and the
right thing to do about it is to say so early and loudly.

Exercised in three states before being believed: both files present, `.bin`
only, and no `brcm` directory at all. The first state also confirmed it
ignores `brcmfmac43455-sdio.bin`, which is a different chip and would be a
misleading thing to list.

### A slip worth recording, because the skill already warned about it

The first attempt at both of these edits was written through a Bash
heredoc, and the Bash tool consumes backslashes in heredocs. Every `\n`
became a real newline and every line continuation became a tab.

The result was still valid shell. `sh -n` passed, `lint.py` passed, and the
`printf` would have worked, because a literal newline inside single quotes
is a newline either way. It was only wrong to read:

    printf 'deb %s %s main non-free-firmware
    ' 	"$DEBIAN_MIRROR" "$DEBIAN_SUITE" >...

The bench skill has carried a warning about exactly this for weeks, with a
tally: four silent drops in one session, three caught by a linter, the
fourth caught by hardware at forty-five minutes and a reflash. The
instruction there is to use an editing tool rather than a heredoc for
anything containing a backslash.

Two notes for the tally. It happened again, which is what a warning that
has to be remembered is worth. And this time it produced **working code
that read wrongly**, which is a quieter failure than the documented one:
nothing downstream would ever have complained, and the next person to edit
that line would have had to work out why it was written that way.

Fixed by running the edit from a file instead, with the backslashes built
from `chr(92)` and an `assert` on every anchor, which is what the skill says
to do when a script must do it at all.

## 13. The vendor artefact was in the archive all along, and my own check missed it

*Saturday 19 September 2026. The session ran past midnight; everything
before this entry is Friday 18 September 2026.*

`rootfs.tar`, 393 MB. All three artefacts now exist. And the listing I
added one commit earlier, specifically so that the firmware situation would
be visible at build time rather than on the board, printed this:

    ---            brcmfmac43430-sdio.AP6212.txt
    ---            brcmfmac43430-sdio.Hampoo-D2D3_Vi8A1.txt
    ---            brcmfmac43430-sdio.MUR1DX.txt
    ---            brcmfmac43430-sdio.bin
    ---            brcmfmac43430-sdio.clm_blob
    ---            brcmfmac43430-sdio.raspberrypi,3-model-b.txt
    ---            brcmfmac43430-sdio.raspberrypi,model-zero-w.txt
    ---            brcmfmac43430-sdio.sinovoip,bpi-m2-plus.txt
    ---            ... and six more

Two things are true about that list and they point in opposite directions.

### The good one: there is no vendor artefact

`docs/BRINGUP.md` has said since the first day that the NVRAM is the only
input this project cannot pin, to be fetched by hand from a FriendlyElec
vendor image or from `armbian/firmware`, with its origin and `sha256sum`
recorded because nothing else could vouch for it.

`brcmfmac43430-sdio.AP6212.txt` is in `firmware-brcm80211`. The **AP6212 is
the module on this board**: a BCM43430 with Bluetooth on one SDIO bus.
NVRAM describes the module, its crystal and its antenna path, not the
carrier it happens to be soldered to, which is exactly why the vendor's
name for it is the useful one and why Debian ships it that way.

So the file was in the archive the whole time, packaged and versioned,
under a name the driver will never ask for. Copy it to the name the driver
does ask for and Project 2 has **no unpinned input at all**. That is a
better state than the one the design document assumed was unavoidable, and
it came from printing a directory listing.

### The bad one: my check said everything was fine

The check I wrote ended like this:

    case $fw in
    *.txt*) ;;
    *)  note "           no NVRAM .txt here." ;;
    esac

Fourteen `.txt` files are in that directory. Not one of them is the file
this board needs. The check asked **is there any .txt** and the sentence
above it claimed to answer **will the radio work**, and it printed nothing
because a Raspberry Pi Zero W's NVRAM is a `.txt`.

That is decision 101, committed by the person who wrote decision 101, in
the commit immediately after it. The tally of guards answering a narrower
question than their own claim is now five, and this one is mine from
today rather than inherited from a previous week.

The honest reading is that writing the decision down does not install the
habit. What would have caught it is the thing the decision actually says:
take the sentence above the check, ask what a failure would look like, and
check whether this code would see it. "No NVRAM" and "no `.txt` at all" are
different failures and only one of them was being looked for.

### What the driver actually asks for

    brcmfmac43430-sdio.friendlyarm,nanopi-neo-air.txt   first
    brcmfmac43430-sdio.txt                              then this

The first name is built from the device tree's root compatible string. It
is now `BOARD_COMPATIBLE` in `toolchain.env`, beside `BOARD_DTB`, because
it is the same fact written for a different consumer, and a string like
that duplicated in two files drifts.

The check now looks for those two names and nothing else, copies the
AP6212 file to the first one when neither exists, and prints the
`sha256sum` of what it installed. Exercised in five states, including the
one that caught this: `.txt` files present, none of them usable. That state
is in the harness precisely because it is the bug.

If the board still shows the SDIO timeout, `BRINGUP.md` now says to read
the name the driver asked for rather than assume the file is wrong. A
different name means `BOARD_COMPATIBLE` disagrees with the device tree,
which is a one-line fix in the right place instead of an evening with a
vendor image.

### A second thing the build output confessed

    Creating SSH2 ED25519 key; this may take some time ...
    256 SHA256:wj+DEdTiHXZ1kObreZV/+t6LSSimHTo+bl9DiZBmTxE root@JPTOUPM678

`openssh-server`'s postinst generates host keys when it is installed, and
it was installed inside a chroot on the build machine. Those keys went into
the tar. Every board ever written from that image would present the same
host key, with the private half travelling inside a 393 MB file that gets
copied to desktops and archives, and the comment field naming the build
host.

A private key that everything shares is not a key.

The keys are now deleted before packing and regenerated on the board at
first boot by a unit in the overlay. `ssh-keygen -A` writes only what is
missing and the unit has a `ConditionPathExists` on the ed25519 key, so a
board that already has them does nothing.

Nobody asked for this and it was not in the specification. It was in the
build output, in plain text, and it had been there on the previous run too.
The difference today is that the output was read rather than scrolled.

### Noise that is not a problem

`E: Can not write log (Is /dev/pts mounted?) - posix_openpt` and
`invoke-rc.d: could not determine current runlevel` are both chroot
artefacts. There is no pty and no running init inside a `debootstrap`
target, `dpkg` says so and carries on, and every package configured
correctly. Recorded here so the next reader does not spend time on them.

### Where Project 2 stands

| Artefact | State |
|---|---|
| `u-boot-sunxi-with-spl.bin` | built, 513912 bytes |
| `zImage` and the board dtb | built, 6.12.0 |
| `modules/lib/modules/6.12.0` | built, `brcmfmac` in `modules.dep` |
| `rootfs.tar` | built, 393 MB, rebuilding for the two fixes above |

Nothing has touched hardware. The next command writes a card, and the one
after that is the first time this project meets the board.

## 14. The first night with the board: no console, and an LED that answered everything

*Saturday 19 September 2026, from about 00:10 to 01:00.*

The card was written and the board was wired and powered, and the console
said nothing for an hour. This entry is mostly about how the question was
narrowed without ever getting a single character out of the UART, because
that turned out to be the transferable part.

### What was tried, in order

| Step | Result |
|---|---|
| card written, `picocom -g` running, board powered | `Terminal ready`, two stray bytes, then nothing |
| checked for an Allwinner FEL device on the host | nothing |
| `eGON.BT0` read back from byte 8196 of the card | present |
| boot partition listed | zImage, dtb, u-boot-sunxi-with-spl.bin, extlinux.conf, all correct sizes |
| loopback: cable TX joined to cable RX, typed `hello` | `hello` echoed |
| data wires swapped, both arrangements | nothing either way |
| card removed, board powered | green LED settled into a rhythmic blink |

### The two tests that did the work

**The loopback.** Joining the cable's own transmit and receive leads and
typing into `picocom` proves the adapter, the `pl2303` kernel module, the
usbipd bridge into WSL and `picocom` itself, all in one gesture and with
the board out of the circuit entirely. `hello` came back. That removed
four candidates at once and cost thirty seconds.

It matters because the adapter was a PL2303HXA, the chip Prolific
discontinued and whose counterfeits are everywhere, and "the cable is
probably fake" is a comfortable theory that would have absorbed the rest
of the night. The loopback made the theory unnecessary rather than
arguing with it.

**The LED, with the card out.** The board was supposed to be proven by a
FEL check: with no card and a blank eMMC the boot ROM has nowhere to go
and must appear on USB in FEL mode. Nothing appeared, which seemed to say
the board was not running.

It said no such thing. **The eMMC was never blank.** The board shipped with
a FriendlyElec vendor image on mmc2, so with the card out the boot ROM
found nothing at byte 8192 of mmc0, moved to mmc2 exactly as designed, and
booted the vendor system. No FEL, because FEL is the fallback for having
nothing to boot, and it had something.

The green LED settling into a rhythmic blink is what gave it away. **A
rhythmic blink is the kernel's heartbeat trigger.** The boot ROM does not
blink. U-Boot does not blink. Only a running kernel with a heartbeat
trigger produces that pattern, so an LED nobody had thought of as an
instrument reported that a full operating system was up.

### What that proved, which is a great deal

A vendor FriendlyElec image prints to UART0 at 115200. It was running, it
was talking, and `picocom` saw nothing.

So the console fault is independent of everything this project built. Not
our U-Boot, not our kernel, not the card, not the adapter. Four pins, or
the contact being made to them. The evening's remaining uncertainty went
from "any of eight things" to one.

### The assumption that was wrong, and where it was written down

`docs/BRINGUP.md` described removing the card and the boot ROM moving to
mmc2 **as the proof that our eMMC provisioning worked**. That step cannot
prove it on this board, because mmc2 already boots something. A board that
comes up is not evidence that our image came up.

The document now says so, and gives the three commands that ask the
running system who it is rather than inferring it from the fact that
something started:

    uname -r
    cat /etc/os-release
    findmnt /

This is the same shape as decisions 101 and 102 arriving from the hardware
side. "The board booted" answers a narrower question than "our image
booted", and the difference is invisible while everything is working.

### A gap found while planning the way around the console

With the board running Linux and the console unavailable, the obvious
route in is ssh over wireless. Reading the image to check that route
found a defect: `mkrootfs.sh` prompts for a root password at build time,
and Debian ships `PermitRootLogin prohibit-password`, so that password
works on the console and is refused over the network.

The build asks for a credential and then quietly arranges for it not to
work. The symptom is `Permission denied, please try again`, which reads as
a wrong password rather than as a policy, on a board whose only other way
in is the cable that is not working.

Fixed with a drop-in under `/etc/ssh/sshd_config.d/` rather than an edit
to `sshd_config`, so a package upgrade rewriting the main file does not
silently undo it, and with a check in `mkrootfs.sh` that Debian's
`Include` line is actually present. The tradeoff is written in the drop-in
itself: a bench board on a private network, a password set by hand and
absent from the repository, no host keys and no `authorized_keys` in the
image, and a note that anything leaving this bench should have a normal
user with sudo instead.

### What to keep

**An LED is an instrument.** Constant means powered. Rhythmic means
software is running a timer, which on Linux means the kernel got far
enough to schedule. Nothing else on the board can produce that pattern,
and it is readable from across a desk with no cable attached.

**A loopback takes the whole host path out of the question in one
gesture**, and is worth reaching for before any theory about a suspect
cable.

**When a test fails to produce the expected evidence, check the
assumption behind the test before believing its result.** "No FEL device
means the board is not running" rested on "the eMMC is blank", which
nobody had ever verified and which was false.

### Where this stops tonight

The board works. The card is correct at the byte level. Every artefact is
built and pushed. What remains is four pins and a silkscreen, which needs
daylight and possibly a second adapter, since the loopback clears the
electronics but says nothing about whether all four wires in that
particular connector are continuous.

## 15. The board boots, and the console was a bent pin all along

*Saturday 19 September 2026, daylight.* Entry 14 ended with the console
silent and the board proven alive by an LED. This is where it talked.

### The console

The debug pins on this board are bare plated holes, no header soldered in,
and there is no soldering iron on the bench. The connection was loose male
pins pushed into the holes with female jumpers on the other end. A pin
resting in a hole touches metal only by luck, and a UART with no contact is
not garbled, it is silent, which is exactly what entry 14 spent an hour on.

The fix needed no iron: bend each pin a few degrees so it springs against
the wall of the hole, seat all four, tape the bundle so nothing moves. The
banner appeared on the next power-up.

That is the whole of what the previous night was missing. Everything built
was correct; the instrument to see it was not connected.

### What the boot proved

`docs/bootlog-sd.txt` is the capture, SPL banner to login prompt, trimmed
of the interactive session that followed. Against the project's criteria:

| Criterion | Evidence |
|---|---|
| 1, U-Boot sees both media | `MMC: mmc@1c0f000: 0, mmc@1c10000: 2, mmc@1c11000: 1` |
| 2, login prompt | `Debian GNU/Linux 12 neo-air ttyS0`, kernel 6.12.0 |
| 3, Wi-Fi | `brcmfmac ... Firmware: BCM43430/1 ... 7.45.98.118`, then a lease |

The AP6212 nvram installed under the driver's name worked: no SDIO clock
timeout, firmware and nvram both loaded, `wlan0` came up and DHCP gave
`192.168.92.92`. The eMMC provisioning fix from `CONFIG_MMC_SUNXI_SLOT_EXTRA`
shows in that three-controller line, which is criterion 1.

### Three defects the boot output confessed, all now fixed

**`systemd-remount-fs.service` failed.** `/etc/fstab` still carried
`PARTUUID=FILLED-BY-FLASH-EMMC`. `sdcard.sh` patched the placeholder in
`extlinux.conf` and forgot the identical one in fstab. The kernel had
mounted root rw from the command line, so nothing broke visibly, which is
how a unit that fails on every boot goes unwatched. `flash-emmc.sh` already
patched both; `sdcard.sh` now does too, and the test grows an fstab fixture
so the fix is checked against a file that is present rather than absent.
Decision 99 said both files get the real value; this is the second file
finally getting it.

**`wpa_supplicant.service` failed while `wpa_supplicant@wlan0` succeeded.**
Two units ship. The templated one reads our per-interface config and is the
one we enable; the generic one wants D-Bus, which `--no-install-recommends`
left out. It is now masked, which states "not used here" rather than
leaving a red line that invites someone to install D-Bus chasing it.

**`cfg80211: failed to load regulatory.db`.** `wireless-regdb` was not
installed, so the radio ran on the world-restrictive default. Added, along
with `iw`, whose absence was noticed the moment a diagnosis needed it:
`iw dev wlan0 link` returned `command not found` on the board.

### The network, and a wall that is not ours

`ssh root@192.168.92.92` timed out. The board and the laptop are on the
same `/24`, so it was not routing. Pings from the board to its own gateway
returned `Destination Host Unreachable`: the association to the phone
hotspot had gone stale by then, and even before that, device-to-device
traffic was blocked. A phone hotspot with client isolation is not a network
a headless board can be reached on, and diagnosing an intermittent hotspot
link is not the project's problem. sshd listens on `0.0.0.0:22`; the image
is reachable, from a network that permits it. Criterion 3 is the DHCP
lease, and that was met and captured.

### What to keep

**A loose pin in a plated hole is silence, not noise.** Garbage points at
baud or ground; nothing at all points at contact or at swapped data lines.
The loopback separates the two, and once it clears the cable, bending the
pins is the no-solder fix.

**Read the boot log for its failures even when it reaches a prompt.** Three
red lines scrolled past on a board that booted fine, and each was a real
defect that would ship on every card until someone read the part between
the banner and the login.

## 16. The eMMC step could never have run, and nothing said so

*Saturday 19 September 2026.* With the board booting from the card, the
next criteria are the eMMC ones: provision it, boot from it, recover it.
Reading `flash-emmc.sh` against the card that `sdcard.sh` actually writes,
before running it, found two reasons it would fail on the first line of
real work. Neither had ever surfaced, because the eMMC step had never run.

### What was wrong

**The script was not on the card.** `BRINGUP.md` section 6 says
`sh /boot/flash-emmc.sh`. `sdcard.sh` copied the kernel, the dtb,
`extlinux.conf` and the bootloader image to the boot partition, and not the
one script the section is about. The card had every piece the eMMC step
needs except the step itself.

**`/boot` was not mounted, so even a delivered script would refuse.**
`flash-emmc.sh` reads the bootloader from `/boot/u-boot-sunxi-with-spl.bin`
and does `rsync /boot/ -> new boot partition`. Both assume `/boot` is the
card's first partition, mounted. But the fstab `mkrootfs.sh` wrote had a
root line and nothing else, so on the running board `/boot` is an empty
directory on the root filesystem. The kernel, dtb and bootloader live on
p1, which nothing mounts. `flash-emmc.sh` would die at its first state:
"no bootloader image at /boot/...".

The boot log from entry 15 hides this in plain sight. `findmnt /` showed
root on `mmcblk0p2`; nobody ran `findmnt /boot`, and it would have shown
nothing. The board booted perfectly because U-Boot reads p1 directly,
before Linux, and Linux never needs p1 for an ordinary boot. It needs it
only to replicate itself, which is the one thing the eMMC step does.

### Why the tests did not catch it

`flash-emmc.sh` is tested with fixtures: a fake `/sys/block`, a fake
`/proc/mounts`, and a pre-built `mnt1`/`mnt2` with an `extlinux.conf` and an
fstab already in place. The fixtures supply a populated `/boot`
equivalent, so the tests proved the state machine correct on the
assumption that `/boot` has the boot files. Nothing tested that the running
system actually mounts them there. It is decision 97 once more: the tests
check the program against a world the deployment does not match, and the
gap is exactly the assumption the fixtures encode.

### The fix

The boot partition is mounted at `/boot`, which is the standard sunxi
layout and makes the existing `flash-emmc.sh` correct rather than rewriting
it. `mkrootfs.sh` writes a two-line fstab now, root and `/boot`, each with
its own impossible placeholder. `sdcard.sh` patches both lines, with p2's
PARTUUID for root and p1's for `/boot`, and refuses to finish a card whose
patch did not take. It also copies `flash-emmc.sh` to the boot partition.
`flash-emmc.sh`, provisioning the eMMC, rewrites both fstab lines to the
eMMC's own partitions, so the eMMC mounts its own root and boot rather than
the card's.

`--one-file-system` in the root copy now does real work: with `/boot` a
separate mount it is excluded from the root rsync and copied once, by the
explicit `/boot` rsync, rather than doubled or empty.

### What the tests learned

Both recording `blkid` stubs answered one value for every partition, which
would let a swap of the root and boot PARTUUIDs pass unseen. They now
answer per partition, p1 and p2 distinct, and the fixtures carry a `/boot`
fstab line so the new patching is checked against a line that is present.
`sdcard.sh` grew an assertion that `flash-emmc.sh` reaches the card.
Sdcard 35 assertions, flash 33.

### What is still only proven in the harness

This is logic-correct and test-green, and it has not run on hardware. It
changes the rootfs, so it needs a rebuild, a reflash, and a boot before the
eMMC step is attempted, and `findmnt /boot` on the running board is the
first thing to check. `BRINGUP.md` section 6 now opens with that check for
that reason.

### What to keep

**Read the program against the deployment, not against its fixtures.**
Both defects were invisible to a passing test suite because the fixtures
encoded the very assumption that was false. A fixture is a claim about the
world, and a claim worth testing is worth checking against the world once.

## 17. Criterion 4, and the refusal that could never fire

*Saturday 19 September 2026.* The eMMC step ran, the board booted from its
own internal storage, and then the safety refusal we were most proud of
turned out to be unreachable.

### Criterion 4

`flash-emmc.sh` completed all seven states from the card. Power off, card
out, power on, and:

    Trying to boot from MMC2
    append: console=ttyS0,115200 root=PARTUUID=77847699-02 rootwait rw
    EXT4-fs (mmcblk2p2): mounted filesystem 33470494-...
    Mounted boot.mount - /boot.

The boot ROM found nothing at byte 8192 of mmc0, moved to mmc2, and mmc2
carried our bootloader rather than FriendlyElec's. `77847699` is the eMMC's
own PARTUUID; the card's was `0ea5d3ef`. Root and `/boot` both mounted from
the filesystems the `format` state had made minutes earlier, by UUID.

That is the `/boot` work from entry 16 proving itself end to end. Had
`bootconfig` not rewritten the fstab boot line, `/boot` would have hunted
for the card's `0ea5d3ef-01` on a board with no card in it.

Worth noting what the two boots did to device names. On the card boot the
SD was `mmcblk1` and the eMMC `mmcblk0`; on the eMMC boot the eMMC was
`mmcblk2`. Same board, same kernel, three different names across three
boots, purely from probe order. Every "never by name" decision in this
project was exercised by the hardware without being asked.

### Then the refusal that could not fire

Still booted from the eMMC, a dry run should have hit the third guard, the
one entry 2 calls "the refusal the specification does not have". Instead:

    flash-emmc: /dev/mmcblk2 is mounted:
           /dev/mmcblk2p1 /boot ext4 rw,noatime 0 0
           Unmount it first.
    flash-emmc: failed in state identify

The board was safe. The guard that saved it was the wrong one, and the
advice was wrong too.

**A board booted from the eMMC necessarily has the eMMC in `/proc/mounts`.**
Root is there by definition, and now `/boot` is as well. The mounted check
ran first, matched `^/dev/mmcblk2`, and died. The root-carries-target check
sat below it and could never be reached on real hardware.

And "Unmount it first" is advice that cannot be followed and should not be:
you cannot unmount `/`, and the correct action is not to unmount anything
but to boot from the card. An operator who trusted that message would
unmount `/boot`, retry, be refused again for a reason the message does not
explain, and learn nothing.

### Why the test said otherwise

The fixture put `NEO_ROOTDEV=/dev/mmcblk1p2`, the eMMC, while leaving
`/proc/mounts` saying `/dev/mmcblk0p2 /`, the card. **Those two cannot both
be true.** If root is on the eMMC, `/proc/mounts` says so. The fixture
described an impossible world, and that impossible world was the only place
the guard had ever fired. The comment above it stated, as fact, that "both
checks above pass on a board already booted from eMMC". The board disproved
that sentence within a minute of being asked.

This is decision 105 arriving again, hours after it was written, and from
the same file. The fixture encoded an assumption about the deployment; the
assumption was not merely wrong but impossible; and a green suite reported
a guard working that reality shadowed.

### The fix

The root-carries-target check now runs **before** the mounted check. Both
still fire on such a board, and the one with the correct remedy wins.

The fixture now describes a state that can exist: root on the eMMC, and
`/proc/mounts` carrying both the eMMC root and the eMMC `/boot`. A second
assertion checks that the output does **not** contain "Unmount it first",
because the defect was never a missing refusal, it was the wrong one
speaking.

Proved rather than assumed: with the old ordering restored, both new
assertions fail. With the fix, 34 pass.

### What to keep

**When two guards can both fire, order them so the one with the correct
remedy speaks.** Being refused is not enough. A refusal is an instruction,
and a safe refusal carrying wrong instructions sends a careful operator
somewhere useless while telling them they were careful.

And the older lesson underneath it: a fixture that has to describe an
impossible state in order to reach a branch is telling you the branch is
unreachable. That is a signal, not an inconvenience to be worked around.

## 18. Criteria 5 and 6, and the boundary this project is named after

*Saturday 19 September 2026.* Idempotence, then the recovery. The recovery
worked. Getting there cost two arithmetic errors at the one boundary every
document in this project warns about.

### Criterion 5

`flash-emmc.sh` run a second time from the card reprovisioned the eMMC
completely: new partitions, new filesystems, `bootconfig PARTUUID=e48fa0a9-02`
and `bootconfig boot PARTUUID=e48fa0a9-01`, `fsck reports clean`. New
PARTUUIDs because it repartitions, which is the point. A failed run is
recovered by rebooting from the card and running it again, and now that is
a thing that has been done rather than a thing that is claimed.

### Criterion 6, and what it proved

Erase the eMMC bootloader, remove the card, connect the micro USB to the
host. `usbipd list` showed `1f3a:efe8`, the board answering over USB with
nothing bootable on either medium. `sunxi-fel version` returned
`AWUSBFEX soc=00001680(H3)`. `./go neo-air fel` pushed U-Boot into SRAM and
the console printed:

    U-Boot SPL 2025.10
    Trying to boot from FEL

A full U-Boot, running from SRAM and DRAM, on a board that by every normal
measure was dead. It even tried PXE and gave up politely. `mmc write` put
the bootloader back and `reset` brought the board up again.

That is the story worth telling: bricked deliberately, recovered over a
USB cable, nothing opened, no JTAG, no programmer.

### The boundary, twice

The project's first design decision was to write down two numbers: the
bootloader at byte 8192, the first partition at sector 2048. Every figure
in `DESIGN.md` exists to make the gap between them visible. Both errors
today were in that gap.

**The erase.** `bs=1024 seek=8 count=1024` writes 1 MiB from byte 8192 and
ends at byte 1056768. Sector 2048 is byte 1048576. It overran by 8 KiB and
zeroed the ext4 superblock 1 KiB into partition 1. The correct count is
1016, the actual size of the gap.

The consequence arrived exactly where it hurt: `ext4load mmc 1:1` answered
`Can't set block device` at the moment the recovery needed the image, so
the image had to come off the SD card instead. The recovery still worked,
but the cardless path the document promises was not available, because the
document's own erase had destroyed it.

**The write-back.** `mmc write 0x42000000 0x10 0x800` is sector 16 plus
2048 sectors, ending at sector 2064. Same boundary, same 8 KiB, same
partition. Caught by reading it before typing it, only because the first
error had just been found. The correct count is `0x3EC`, 1004 sectors,
which is the image rounded up to a whole sector.

Two mistakes, one cause: a round number that looks like a megabyte, used
where the actual size of the thing was what mattered.

The repair run afterwards confirmed the damage without being asked. Every
previous `flash-emmc.sh` printed two lines from `sfdisk`:

    Partition #1 contains a ext4 signature.
    Partition #2 contains a ext4 signature.

This one printed only the second, and `mkfs` likewise reported an existing
filesystem on p2 alone. The tools could not see a filesystem on p1 because
its superblock was the 8 KiB that had been overwritten. A destructive
mistake left a signature in the output of the next ordinary run, which is
worth knowing: the evidence is often already in a log nobody is reading for
that purpose.

### A third one that cost twenty minutes

Before either of those, an erase appeared to succeed and had not. The
command in the document says `of=/dev/mmcblkN`, and `mmcblkN` was typed
literally. `dd` created a regular file called `/dev/mmcblkN`, wrote 1 MiB
into it and reported success.

Two things hid it. `/dev` is devtmpfs, so the file vanished at the next
reboot and could not be found afterwards. And `1048576 bytes copied` looks
identical either way.

What gave it away was the transfer rate. **125 MB/s is RAM. The eMMC with
`conv=fsync` does 4.4 MB/s.** The number that looked like success was the
evidence it had not happened, and the verification that settled it was
reading byte 8196 back and finding `eGON.BT0` still there.

The placeholder is the defect. `mmcblkN` is honest about the danger and
useless at the moment of typing, and the device number moved three times in
one afternoon: the eMMC was `mmcblk0`, `mmcblk1` and `mmcblk2` across
consecutive boots of the same board. A document cannot hardcode it and a
human should not have to substitute it under pressure.

### What to keep

**Verify a destructive operation by reading the target back, never by
reading the tool's own report.** `dd` reported complete success three
times: once into a file, once into the eMMC, once into the eMMC again. Only
`od -c` on byte 8196 distinguished them.

**A throughput number is a fingerprint of where the write went.** RAM,
eMMC and SD each have a signature, and a write that lands somewhere
unexpected usually announces itself in the rate before it announces itself
anywhere else.

**When a project's design document names a boundary, check every arithmetic
operation against it, including the ones in the prose.** Both errors were
in the documentation rather than the code, and the code that surrounds them
has been checking sector 2048 correctly since the first week.

## 19. The one project with a working board had no archived image

*Saturday 19 September 2026.* Asked whether Project 2's artefacts were on
the Desktop with a project prefix. They were not. The Yocto store on
aquamarine holds `proj08-bench-rt` and `proj08-bench-rt-generic`, and
Project 2 had nothing: `./go neo-air` never had an archive target.

So the only project in this repository with a board that boots was the only
one whose artefacts existed in exactly one place, inside the WSL virtual
disk. That file has been compacted, filled to read-only and rebuilt on this
bench before. Losing it would have meant rebuilding U-Boot, a 6.12 kernel
and a 394 MB root filesystem, with the eMMC as the only surviving copy of
the thing that works.

`./go neo-air archive` now writes `proj02-neo-air/<date>_<commit>[-dirty]`
into the same store, with the same naming as the Yocto side, and a
`PROVENANCE.txt` carrying the pins, the sha256 of every artefact, the flash
line and the rebuild line. Exercised in three states: a normal run, a
second run onto the same stamp, which refuses rather than merging, and a
missing artefact, which refuses and creates nothing.

The `-dirty` detection caught the working tree during its own test, which
is the right kind of first result.

### The flash line was a claim the code did not support

The provenance file's whole point is that somebody can write a card from an
archived set years later. The line it generated was:

    NEO_OUT=<dest> sudo -E ./go neo-air card /dev/sdX

Wrong twice. `sudo -E` is ignored on this bench's sudo, which is entry 11's
whole subject. And `toolchain.env` set `NEO_OUT` unconditionally, so even a
variable that survived sudo would have been overwritten a line later.

`NEO_OUT` is now `${NEO_OUT:-$NEO_WORK/out}`, and the line reads
`sudo env NEO_OUT=<dest> ./go neo-air card /dev/sdX`. Verified in three
states rather than assumed: default, overridden, and overridden under a
sudo that resets the environment.

That is decision 97 again, a document describing a program, in a file whose
entire job is to be trustworthy long after everyone has forgotten the
details. A provenance file with a flash command that does not work is worse
than one with no flash command, because the reader will not find out until
they need it.

### What to keep

**An artefact that exists in one place is not archived, whatever the
directory is called.** The two tiers were named in entry 8 and the project
with the most to lose was still in the lower one, because the tooling to
move it up had never been written for the one project that had no Yocto to
inherit it from.

## 20. Two loose ends, and one of them was on every boot

*Saturday 19 September 2026.* Closing out.

### The regulatory database

Every boot since `wireless-regdb` was installed has printed:

    Loaded X.509 cert 'sforshee: 00b28ddf47aef9cea7'
    Loaded X.509 cert 'wens: 61c038651aabdcf94bd0ac7ff06c7248db18c600'
    cfg80211: loaded regulatory.db is malformed or signature is missing/invalid

Adding the package made this worse rather than better, in a way easy to
misread as the package being broken. It is not. `wireless-regdb` ships two
copies and `update-alternatives` picks `regulatory.db-debian`, signed with
Debian's key. A mainline kernel trusts only the certificates it was built
with, and the two it names on the line above are `sforshee` and `wens`.
`regulatory.db-upstream` is signed by sforshee, which is one of them.

So the kernel is correct, the package is correct, and the default
alternative is the wrong one for a kernel that is not Debian's. The cost is
the world-restrictive default domain, which loses channels rather than
function, and is why this sat unaddressed while the radio associated and
took a lease perfectly well.

`mkrootfs.sh` now selects `regulatory.db-upstream`, guarded: if the
alternative is not registered under that name the build says so and carries
on, because a channel list is not worth failing a root filesystem over.

**This is not verified on hardware.** It needs a rootfs rebuild and a
reflash, and Project 2's criteria were all met before it. The next card
written will show whether the line goes away.

### A line wrap in the provenance file

`PROVENANCE.txt` is the one artefact in this project designed to be read
years from now by someone with no context. An edit left a sentence broken
across an awkward line: "Check the device / with lsblk first". Fixed.

Small, and worth doing precisely because of what that file is for. A
document whose whole purpose is to be legible later is the wrong place to
leave a paragraph that reads as though it was assembled rather than
written.

### Where Project 2 ends

| | |
|---|---|
| Criteria | all six, on hardware |
| Evidence | boot logs for both media, committed |
| Artefacts | archived with provenance, outside the VHDX |
| Tests | 69 assertions across the two destructive tools |
| Record | 20 journal entries, decisions 98 to 107 |

Open, and neither blocking: the regulatory alternative above, unverified
until the next build; and the guard-ordering and package fixes from earlier
today, which are in the repository and will reach a board the next time a
card is written.

## 21. CI went red on a commit that was already fixed, and said something anyway

*Saturday 19 September 2026, late afternoon.* A failure notice arrived for
`ci - main (033b674)`, the archive commit.

### What it was

Read through the API with the stored git credential, since there is no `gh`
on this laptop:

    GET /repos/ambrosiobing/embedded-linux/actions/runs?per_page=5

    661fa04 completed success ci
    033b674 completed failure ci
    8c1f894 completed success ci

Already fixed by the next commit. The log named one thing and nothing else:

    projects/02-neo-air-mainline/tools/archive.sh: has a shebang but is
    committed as 100644, not 100755
    1 problem(s)

That mattered to confirm rather than assume. **aquamarine has no
shellcheck**, so `archive.sh`, a 165 line script written today, had never
been through the real linter. CI runs it. A green-after-fix result does not
prove shellcheck was happy, because the run that would have told us failed
before reaching it. Reading the log did prove it: the only finding was the
mode, and the shellcheck stage had no complaints about the new script.

### What it exposed, which is the part worth keeping

`scripts/lint.py` caught the exec bit **before** CI did. It is in the
repository, it works, and it found the problem the moment it was run. The
problem is when it was run: after the commit, because I happened to run it
as part of the next change.

So the check existed, the check was correct, and the check was not attached
to the event that needed it. The repository already has a
`.git/hooks/commit-msg` guard for attribution traces, which exists for
exactly this reason: prose telling a person to remember something does not
survive contact with a busy afternoon. There is no `pre-commit` hook
running `lint.py`, and had there been one, 033b674 would have been refused
locally and CI would never have gone red.

That is the same shape as the whole of Project 2, one layer up. A correct
check, in the wrong place, reporting truthfully about something nobody was
asking it at the moment it mattered.

### Not done, and why

The hook is not added here. It touches `.git/hooks` on two machines, which
is outside the repository and therefore outside what a commit can carry;
Project 2 is closed; and a CI failure already fixed by the following push
is not urgent. It belongs with the next piece of tooling work, alongside
installing the existing `commit-msg` guard on JPTOUPM678, which is still
outstanding from 17 September.

### Also checked

The five `walkthrough/` files that mention the NEO Air were read for stale
claims now that Project 2 is finished. All five mention it descriptively,
in a hardware table, a piece-by-piece comparison against the Pi, and a
lifecycle example. None asserts a status, so none went stale. The root
`README.md` row is the only place that tracked status and it was updated
with the criteria.
