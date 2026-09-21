# Project 19: A/B root filesystem updates with RAUC

A Raspberry Pi 3 that updates itself and, more importantly, **fails back**
when an update is bad. Two equal root partitions, a boot counter U-Boot
decrements before it risks anything, and a health check that confirms a
slot only when the application on it has actually answered.

The success path is three lines long. The project is the failure paths.

| Path | What |
|---|---|
| [docs/DESIGN.md](docs/DESIGN.md) | five figures, the ownership table, and the decisions taken before any code |
| [JOURNAL.md](JOURNAL.md) | what happened, in order, including what was wrong first |
| [kas/bench-rpi3-ab.yml](../../kas/bench-rpi3-ab.yml) | `./go ab`, the card image |
| [kas/bench-ab-bundle.yml](../../kas/bench-ab-bundle.yml) | `./go ab-bundle`, a signed update |
| [meta-bench/wic/bench-ab.wks](../../meta-bench/wic/bench-ab.wks) | the four partition card, and the first `.wks` in this repository |
| [boot.cmd.in](../../meta-bench/recipes-bsp/rpi-u-boot-scr/files/boot.cmd.in) | the boot script: the most dangerous file here |
| [system.conf](../../meta-bench/dynamic-layers/meta-rauc/recipes-core/rauc/files/system.conf) | what the board believes about its own slots |
| [bench-bundle.bb](../../meta-bench/dynamic-layers/meta-rauc/recipes-core/bundles/bench-bundle.bb) | one signed bundle, one root filesystem |
| [bench-ab](../../meta-bench/recipes-bench/bench-ab/) | the application, the health check, the failsafe, the watchdog, the LEDs |
| [tests/ab-config-test.sh](../../tests/ab-config-test.sh) | 101 assertions about agreements no build can check |
| [tests/ab-bootscript-test.sh](../../tests/ab-bootscript-test.sh) | runs the real boot script in a U-Boot sandbox |
| [kas/bench-ab-bundle-broken.yml](../../kas/bench-ab-bundle-broken.yml) | `./go ab-broken`, the bundle that must roll back |
| [kas/bench-ab-bundle-wrong.yml](../../kas/bench-ab-bundle-wrong.yml) | `./go ab-wrong`, the bundle that must be refused |

## The one limitation, stated plainly

**A/B protects the root filesystem and nothing else.** The GPU firmware,
`u-boot.bin`, `boot.scr`, the device tree and `uboot.env` all live on the
shared FAT partition and are in no bundle. A broken boot script takes out
both slots at once, and no rollback logic helps, because the rollback logic
is the thing that broke.

That is why a second microSD card is part of the bench rather than a
precaution, and why boot script changes are tested on it first.

## Acceptance

Seven criteria, from the specification. "Configured" means a file in this
repository says so and a test asserts it. "Measured" means a board did it
and there is a log. Nothing here is measured yet: **nothing has been
built.** The blank column is the honest state, and a number invented to
fill it would be worse than the blank.

| # | Criterion | Evidence it will take | State |
|---|---|---|---|
| 1 | Console shows firmware, `U-Boot 20xx.xx`, `Slot A, n attempts left`, then the kernel, and reaches a login in under 25 s | a console log, timed | **Not started.** Nothing built |
| 2 | `rauc status` reports the booted slot with `boot-status: good` after the health check, and `fw_printenv BOOT_A_LEFT` prints 3 again | console transcript after a clean boot | **Configured.** The gate is `boot-complete.target`; meta-rauc's own mark-good service resets the counter. Asserted by `ab-config-test.sh` |
| 3 | Root is `ro`; `touch /usr/x` fails; `touch /etc/x` succeeds and survives a reboot; `/var/log/journal` is on the data partition | four commands and a reboot | **Configured.** `read-only-rootfs`, `overlayfs-etc` on p4, and a journal symlink onto p4. Asserted |
| 4 | Installing a good bundle switches to the other slot, the LED colour changes, and `rauc status` reports the new version | console log and the LED video | **Configured.** Three `gpio-led` overlays, `bench-slot-leds` driving them from `rauc.slot`, and RAUC's own pre- and post-install handlers for the busy light. Asserted |
| 5 | A broken bundle gives exactly three boot attempts of slot B, then an automatic return to slot A, and slot B is marked bad | the full console log of the rollback | **Configured.** `./go ab-broken` builds it: one switch, which swaps in a `bench-app.service` running `/bin/false` and changes nothing else. Asserted |
| 6 | A sysrq crash causes a hardware reboot within 15 s and drops the running slot's counter by one | console log across the reboot | **Configured.** `RuntimeWatchdogSec=14` against a driver that clamps near 15. Asserted |
| 7 | A bundle signed with a different key is refused with a signature error, and one with another `compatible` string is refused before anything is written | two refusals, quoted | **Configured.** `./go ab-wrong` builds the second; the first is the ordinary bundle built against the second key pair. Asserted |

## Where this deviates from the specification, and why

Two places. Both are recorded here rather than left for a reader to find by
comparing documents.

**The FAT partition is mounted `rw,sync` rather than read-only with a
remount.** The specification says to mount `/boot` read-only and let
`fw_setenv` remount when needed. That cannot be implemented where it has to
be: RAUC invokes `fw_setenv` itself, from `PATH`, with no hook to wrap, so
the remount would need a shadow binary installed over the one in
`u-boot-fw-utils`. The hazard the specification names is pending writes at
reboot time, and `sync` removes those directly by making every write reach
the card before the call returns. The cost is slow writes to a partition
whose only runtime writer is a 16 KiB file, twice per update.

**`/var/log/journal` is a symlink rather than a bind mount.** The
specification's best-practice list says bind mount for `/var`. Acceptance
criterion 3 asks only that `/var/log/journal` be on the data partition,
which the symlink satisfies. A bind mount needs ordering against
`systemd-journald.service`, which starts very early; a symlink made at
image build time needs no ordering at all. The rest of `/var` is volatile,
which is what `read-only-rootfs` gives and what this project has no reason
to change.

## What is not built yet

The software is written and lints clean; no build has been run and no
board has seen any of it. Outstanding before that can change:

1. The three signing paths in `kas/bench-rpi3-ab.yml` are empty on purpose.
   Every recipe that needs one refuses and names the variable. The openssl
   commands are in [docs/BRINGUP.md](docs/BRINGUP.md).
2. The boot script has a test that runs it in a U-Boot sandbox, and that
   test has never actually executed it, because no sandbox binary has
   been built on this bench. It says so loudly and lists the questions it
   could not ask. Building one is a host-only step and needs no board.
3. Disk and build time on the build laptop have not been checked, and a
   kernel fragment means a kernel rebuild.
