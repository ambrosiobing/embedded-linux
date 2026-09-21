# Project 19: design

Read before anything is built. The specification is four evenings of work,
one of them a Yocto rebuild, and the expensive mistakes here are all in the
layout rather than in the code.

The four figures the specification asks for are redrawn below as text, with
the addresses and partition numbers written out, because the numbers are
what transfer and a picture of an arrow is not.

## What makes this project different from the rest

Every other project on this bench builds something that runs. This one
builds something that **fails safely**, and the deliverable is a recording
of it failing.

That inverts the usual order of work. The success path here is short: an
update installs, the board reboots into the other slot, a light changes
colour. The project is the failure paths, and they cannot be asserted into
existence. Three of them have to be provoked on the bench and recorded:

| Failure | How it is provoked | What must happen |
|---|---|---|
| a bad application | a bundle whose `bench-app.service` runs `/bin/false` | three attempts, then automatic return to the other slot |
| a hung kernel | `echo c > /proc/sysrq-trigger` | hardware watchdog reboots within 15 s, one attempt consumed |
| a forged bundle | sign with a different key | refused before anything is written |

A second difference: **the Raspberry Pi has no bootloader.** Its firmware
loads the kernel directly, which is why A/B on a Pi is unusual. The whole
project rests on one trick, letting the firmware load U-Boot *as if it were
the kernel*, and the consequences of that trick are what the ownership
table below is mostly about.

## Figure 1: the boot chain, and what each stage can and cannot replace

```
  power on
     |
     v
  [ VideoCore GPU ]  bootcode.bin, then start.elf        SHARED, not updatable
     |               reads config.txt
     |               loads the device tree + overlays
     |               loads whatever kernel= names
     |
     |  kernel=u-boot.bin          <-- the trick the project rests on
     v
  [ U-Boot ]  on FAT p1                                  SHARED, not updatable
     |        runs boot.scr
     |        reads BOOT_ORDER, BOOT_A_LEFT, BOOT_B_LEFT from uboot.env
     |        decrements the chosen slot's counter
     |        saveenv                                    <-- writes FAT p1
     |        ext4load mmc 0:<2 or 3> ${kernel_addr_r} /boot/Image
     |        booti ${kernel_addr_r} - ${fdt_addr}
     |                                   ^
     |                                   '-- the firmware's DT, from p1, SHARED
     v
  [ Linux ]  root=/dev/mmcblk0p2 (A) or p3 (B), ro        PER SLOT, updatable
     |       rauc.slot=A or B
     |
     +-- /etc      overlay, upper on p4                   SHARED state
     +-- /var      tmpfs, EXCEPT the journal              volatile
     +-- /var/log/journal -> /data/journal                SHARED state
     +-- /data     p4, rauc.status, bundles               SHARED state
     |
     v
  [ systemd ]  RuntimeWatchdogSec=14 -> /dev/watchdog0 (bcm2835_wdt)
     |
     +-- bench-app.service
     |        |
     |        v
     +-- bench-health.service     RequiredBy boot-complete.target
     |        |                   exits 0 or 1, and calls nothing
     |        v
     +-- boot-complete.target     reached only if the check passed
     |        |
     |        v
     +-- rauc-mark-good.service   meta-rauc's own, Requires the target above
     |                            resets BOOT_x_LEFT to 3     <-- writes FAT p1
     |
     '-- failsafe.timer  OnBootSec=120, reboots if /run/slot-good is absent
```

**The line that matters most is the one marked SHARED, not updatable.** The
firmware, `u-boot.bin`, `boot.scr` and the device tree are on the FAT
partition and are **not** part of any bundle. A/B protects the root
filesystem and nothing else. A broken `boot.scr` takes out both slots at
once, and no amount of rollback logic helps, because the rollback logic is
the thing that broke.

That is why the specification insists on a second microSD card, and why it
is the first entry in the bench layout below.

## Figure 2: the card, by partition and by owner

```
  microSD, msdos partition table
  +--------------+----------------+----------------+----------------+
  | p1  FAT      | p2  ext4       | p3  ext4       | p4  ext4       |
  | label boot   | label rootA    | label rootB    | label data     |
  | 64 MiB       | 1024 MiB fixed | 1024 MiB fixed | 512 MiB        |
  +--------------+----------------+----------------+----------------+
  | bootcode.bin | rootfs (ro)    | rootfs (ro)    | /etc upper     |
  | start.elf    | /boot/Image    | /boot/Image    | journal        |
  | config.txt   |                |                | rauc.status    |
  | *.dtb, *.dtbo|                |                | bundles        |
  | u-boot.bin   |                |                |                |
  | boot.scr     |                |                |                |
  | uboot.env    |                |                |                |
  +--------------+----------------+----------------+----------------+
     ^      ^                ^                ^            ^
     |      |                |                |            |
     |      |                '-- rauc install writes the INACTIVE one
     |      |
     |      '-- written by U-Boot saveenv AND by Linux fw_setenv
     |
     '-- read by the GPU firmware before any ARM core is running
```

Both root slots are `--fixed-size 1024M`, not `--size`. A slot that can
grow is a slot that can stop matching the other one, and RAUC writes a
whole filesystem image into a partition: if the target is smaller than the
source the install fails, and if it is larger the difference is wasted on
every update forever. Fixed and equal is the only sane choice.

## Figure 3: the LEDs and the console

Three LEDs, each through a 330 ohm series resistor to the ground rail.

| Signal | Header pin | BCM | Meaning |
|---|---|---|---|
| green anode | 11 | GPIO17 | booted from slot A |
| yellow anode | 13 | GPIO27 | booted from slot B |
| red anode | 15 | GPIO22 | steady: installing. blinking: slot not yet good |
| cathodes | 9 | GND | ground rail |
| console TXD | 8 | GPIO14 | cable RX, white |
| console RXD | 10 | GPIO15 | cable TX, green |
| console GND | 6 | GND | cable black |

**The cable's red 5 V lead stays disconnected**, taped back, exactly as in
Project 2. The Pi is powered from its own USB supply and never from the
header.

The red LED carries two different meanings and that is deliberate. Steady
means a write is in progress and the card must not lose power; blinking
means the slot is running but unconfirmed, so a reboot now costs an
attempt. Those are the two states during which the board is fragile, and
one indicator for both is easier to read across a desk than two.

## Figure 4: bench layout

```
     [ second microSD ]   known good, never written during development
            :
            : swap in when a boot-script change leaves the Pi at the
            : U-Boot prompt, which it will
            :
   +--------------------+        USB/TTL           +------------------+
   |   Raspberry Pi 3   |======= 3 wires =========>|  JPTOUPM678      |
   |   raspberrypi3-64  |   GPIO14/15/GND          |  picocom 115200  |
   |                    |                          |  kas build       |
   |  [G][Y][R] LEDs    |                          |  rauc info       |
   +--------------------+                          +------------------+
            |                                              |
            | own 5 V USB supply                           | builds bundles,
            | (never the header)                           | holds the private
            |                                              | signing key
```

The private signing key stays on the build laptop. The target carries only
`ca.cert.pem`, the public half. That is the whole of the bench PKI and it
is the part that makes the "bundle signed with a different key is refused"
criterion meaningful rather than decorative.

## Figure 5: the slot state machine, and where each transition is written

RAUC's model per slot, and the actor that performs each transition:

```
        inactive
           |
           |  rauc install          (Linux, rauc)
           |    writes the slot, sets BOOT_x_LEFT=3,
           |    puts x first in BOOT_ORDER
           v
        pending  ------------------------------------+
           |                                         |
           |  boot attempt          (U-Boot, boot.scr)|
           |    BOOT_x_LEFT-- ; saveenv               |  BOOT_x_LEFT reaches 0
           v                                          |  U-Boot skips the slot
        booted                                        |
           |                                          v
           |  health-check.sh passes (Linux)        bad
           |  rauc status mark-good
           |    BOOT_x_LEFT=3
           v
         good
```

And the update sequence, including the path that matters:

```
  host                    target                         U-Boot
  ----                    ------                         ------
  bitbake bench-bundle
  rauc info --keyring     (verifies signature)
       |
       '--- copy .raucb to /data
                             |
                             rauc install
                             |  verify signature against ca.cert.pem
                             |  verify compatible == bench-rpi3
                             |  write inactive slot
                             |  BOOT_ORDER="B A", BOOT_B_LEFT=3
                             reboot
                                                          |
                                                          Slot B, 2 attempts left
                                                          saveenv
                                                          boot
                             |
                             bench-app fails
                             health-check never passes
                             red LED keeps blinking
                             failsafe.timer at 120 s -> reboot
                                                          |
                                                          Slot B, 1 attempt left
                             ... and again ...
                                                          Slot B, 0 attempts left
                                                          |
                                                          Slot A, 2 attempts left
                             |
                             slot A boots, green LED
                             rauc status: B is bad
```

**Three reboots, each 120 s apart, is roughly six minutes of rollback.**
That is worth knowing before watching it happen and assuming it has hung.

## Ownership: which component owns which resource

The table that earns its place. Every row with two owners is a hazard until
the arbitration is written down.

| Resource | Owner 1 | Owner 2 | Arbitration |
|---|---|---|---|
| `uboot.env` on FAT p1 | U-Boot `saveenv`, every boot | Linux `fw_setenv`, on install and mark-good | **Hazard.** Never simultaneous by construction: U-Boot writes only before Linux exists, Linux writes only after U-Boot has finished. The danger is the FAT partition being mounted read-write by Linux with dirty pages when a reboot happens. **Policy changed during implementation.** The remedy written here, mount read-only and let `fw_setenv` remount, cannot be implemented where it has to be: RAUC calls `fw_setenv` itself from PATH, so the remount would need a shadow binary over the one in u-boot-fw-utils. `boot.mount` instead mounts rw with `sync`, which removes the dirty pages rather than the write window, needs no wrapper, and costs nothing because the only runtime writer is a 16 KiB file twice per update. |
| `BOOT_ORDER`, `BOOT_x_LEFT` | `boot.scr` decrements | `rauc` sets on install and mark-good | Same file, same rule as above. The semantics are disjoint: U-Boot only ever decrements, RAUC only ever sets to 3 or reorders. Neither reads a value the other is mid-way through writing. |
| the FAT boot partition as a whole | the Yocto image build, at flash time | nothing, at runtime | **Not updatable, and that is the design's main limitation.** No bundle touches it. README must say so plainly. |
| the device tree | firmware loads it from p1, shared | each slot's kernel expects it | **Hazard.** Kernel is per slot and updatable; DT is shared and is not. An update that needs a new DT cannot have one. Stretch goal moves the DT into the slots; until then this is a stated constraint, not an oversight. |
| `/etc` | the rootfs image, read-only lower | overlay upper on p4, persists across updates | **Hazard.** A file edited on slot A shadows the new default shipped in slot B forever, invisibly. Policy: the overlay is for operator configuration only; anything the image owns must not be edited in place. |
| `/data` | slot A | slot B | Shared by design, and not versioned. Two slots may expect different schemas. A post-install migration handler is the stretch goal; for now the constraint is that the data schema must not change between bundles. |
| `/var` | slot A | slot B | **Corrected after implementation.** A read-only root makes `/var` volatile, so there is no shared `/var` and no hazard. Only the journal is persistent, by an explicit symlink onto p4, and logs from both slots do interleave there, which is what makes a rollback readable afterwards. Journal entry 9 has the reason and the size cap. |
| the mount of p4 | the `overlayfs-etc` preinit, before `/sbin/init` | nothing else, and that is enforced by absence | **Found during implementation, after this table was written.** A `data.mount` unit had already been written and installed before the class was read. Deleted: the class mounts p4 itself, so the unit was a second owner. Mount options live in `OVERLAYFS_ETC_MOUNT_OPTIONS` and nowhere else. Journal entry 7. |
| `rauc status mark-good` | meta-rauc's own `rauc-mark-good.service`, installed by default | this project's health check, which does **not** call it | **Found before implementation, by reading the upstream unit.** It is `Requires=boot-complete.target`, so it is already health-gated. `bench-health.service` is `RequiredBy` that target and calls nothing. Writing a second mark-good would have been two owners of the one decision this project exists to make. Journal entry 6. |
| `/dev/watchdog0` | systemd PID 1, `RuntimeWatchdogSec=14` | the application, `WatchdogSec=30` | Not a conflict: two layers, different jobs. systemd feeds the hardware watchdog; the application's own watchdog is a systemd-level restart long before the hardware one fires. |
| GPIO 17, 27 and 22 | Project 12's `bench-status`, via libgpiod | this project's `gpio-led` overlays, via the device tree | **Found during implementation.** The same three lines, with unrelated meanings: health in one scheme, slot identity in the other. Not reconcilable by agreement, because the overlays claim the lines in the device tree and libgpiod then cannot open them at all. `bench-ab-image.bb` removes `bench-status` from this image. Journal entry 13. |
| the rollback decision | U-Boot, by counter | RAUC, by `mark-good` | Cooperating halves of one mechanism. U-Boot can only give up; RAUC can only confirm. Neither can do the other's job, which is what makes the mechanism safe. |

Five hazards were found before any code existed. Implementation added three more rows, and every one of the three was a resource whose real owner turned out to be a line in an upstream class, an upstream unit, or a device tree overlay, rather than any component named in this document. It also corrected two rows whose stated policy could not be implemented where it had to be. Each has an explicit policy rather than being
left to be discovered on the bench. That is the whole purpose of writing
this table before the code.

## What is decided here, and why

**The counter is decremented before the kernel is loaded, not after.** A
kernel that hangs must still consume an attempt, otherwise a hang is an
infinite loop rather than a rollback. This costs nothing and is the single
most important ordering decision in the boot script.

**Health is "the application answered", not "systemd reached
multi-user.target".** A rootfs that boots to a shell and runs nothing is a
failed update that the naive check would confirm as good. This is the same
shape as Project 2's lesson about a booting board not proving whose image
booted.

**The health check does not test the network.** An offline device with an
unplugged cable would otherwise roll back for no reason. The check tests
the local application and the writability of `/data`, both of which are
true properties of a healthy device regardless of connectivity.

**A failsafe timer, not only a watchdog.** The hardware watchdog catches a
hung kernel. It does not catch a kernel that is perfectly healthy running
an application that will never start. The 120 s timer converts that second
case into a consumed attempt, which is what makes the bad-application
rollback terminate.

**Slots are fixed and equal size.** See figure 2.

## What can be built before the board is touched

Most of it, which is the point of doing the design first.

| Buildable now | Needs the board |
|---|---|
| the kas file, the WIC layout, the bbappends | the boot chain actually booting |
| `boot.cmd` and its logic | `saveenv` writing FAT successfully |
| `system.conf`, `fw_env.config` | `fw_printenv` agreeing with `CONFIG_ENV_SIZE` |
| the health check, the units, the LED service | the three recorded failure paths |
| the bundle recipe and the signing key | install timing on a class 10 card |

**One open question I am not going to pretend is settled.** The boot
script is the most dangerous artefact in the project, it cannot be tested
by running it, and a shell reimplementation of its logic would be testing
the reimplementation rather than the script, which is the trap decision 98
names. The honest options are:

1. Build U-Boot's `sandbox` target on the host and run the real script
   against real U-Boot semantics with a fake environment. Highest fidelity,
   and the only option that tests the artefact rather than a copy of it.
2. Test only the *derived* facts on the target after each change, from the
   console, against the second card as the recovery path.
3. Accept it as untested, and lean on the second microSD card.

**Resolved: option 1, with one substitution named out loud.**
[tests/ab-bootscript-test.sh](../../../tests/ab-bootscript-test.sh) runs
the real script text through the same token substitution the recipe makes,
then executes it in a U-Boot sandbox binary. The hush parser, the `setexpr`
arithmetic and the environment are U-Boot's own, so what is tested is the
artefact rather than a description of it.

Two commands are stubbed, because they need an arm64 target and a real
card: the `ext4load` and the boot command. Nothing that decides anything is
touched, and the test asserts the boundary of its own substitution, so a
later edit cannot widen it quietly.

The FAT `uboot.env` question that made this uncertain turned out not to
matter. The decision logic reads and writes ordinary environment variables,
and where they are persisted is a separate concern that the sandbox does
not need to reproduce. What the sandbox cannot answer is whether the script
boots a board, and that stays with the second microSD card.

Without a sandbox binary the test exits zero and prints the list of
questions it could not ask. That is deliberate rather than convenient: a
skip that reads as a pass is a failure this repository has shipped three
times.

## Before any of this is built

Two constraints that are not design questions but will decide the schedule.

**The disk cost is not what it looks like, in both directions.**
`raspberrypi3-64` is not a new machine for this bench. Project 8 built it
on Wednesday 16 September 2026, when the HAT turned out to be on a 3B+, and
paid the full price then:

    Sstate summary: Wanted 1921 Local 200 Mirrors 0 Missed 1721 Current 942
    (10% match, 39% complete)

sstate is keyed on the tune rather than on the machine name, and
`cortexa53` shares nothing with `cortexa72`. That build completed,
`sstate-cache` was kept through the cleanup that followed at 13 GB, and
Project 8 then moved back to the Pi 4 in `d7c6295`. So both tunes should be
in that cache, and this project should not have to buy the machine change a
second time.

What it does have to buy is `meta-rauc`, U-Boot under `RPI_USE_U_BOOT`, and
a kernel fragment. The last is the expensive one: a fragment change means a
kernel rebuild, which is exactly what `require_host_disk_gb 25` in
`scripts/build.sh` guards on. The last recorded free space on the build
laptop's Windows drive was 18 GB, which is below that guard, so the build
refuses at the start rather than filling the disk halfway through.

Two cheap figures settle the schedule: the exact free space, and whether
the `cortexa53` objects are still in `sstate-cache`. Neither needs a build
started. And `Sstate summary` on the first screen of output is what says
which build is actually being bought, so it gets read rather than assumed.
Note that the guard checks once, before it can know what the build will
cost; on Project 8 it passed 38 GB against a 25 GB test and the build
peaked at 28 GB, which was right by 13 GB of luck.

**The hardware has to be on the bench**: a Raspberry Pi 3, a second microSD
card kept as the known-good recovery image, three LEDs with 330 ohm
resistors, a breadboard and the USB/TTL cable. Project 6 and Project 8 have
both used a Pi 3, so the board exists; the second card and the LEDs are the
open items.
