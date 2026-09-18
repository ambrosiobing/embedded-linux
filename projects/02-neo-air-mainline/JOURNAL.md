# Journal: Project 2

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

All entries are 18 September 2026 unless noted.

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
