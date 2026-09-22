# Project 20: OP-TEE on the Raspberry Pi 3, a trusted application for key storage

**Board:** Raspberry Pi 3. **Theme:** TrustZone, OP-TEE OS, the TEE Client
API, secure storage.

**Read this paragraph first.** The Raspberry Pi 3 has no secure boot, no
hardware unique key and no controller that keeps the normal world out of
secure memory. The firmware loads the secure world from an unsigned FAT
partition, OP-TEE's secure storage is encrypted with a key derived from a
constant that is public in the source, and root can read the secure
world's memory. **This project protects nothing against an attacker who
can run code on the board.** It is a working demonstration of the
GlobalPlatform APIs, the boot flow and the debugging tools, on the board
OP-TEE lists as a reference platform, and the same trusted application
moves unchanged to an i.MX8 or an STM32MP1 where the silicon does enforce
the boundary. [docs/THREAT-MODEL.md](docs/THREAT-MODEL.md) is the long
form and is the part worth quoting.

With that said, what is real here is worth learning. The world switch is a
concrete mechanism rather than a marketing term: a message in shared
memory, an `SMC` instruction, a monitor at EL3, a dispatch by UUID. The
key is generated inside the secure world and never crosses that boundary.
And the failure modes, a missing supplicant, an unsigned TA, a parameter
type mismatch, a deleted storage directory, behave identically on hardware
that does enforce the boundary.

## State

**Both halves are built, the board has booted them, and the first call
into the secure world never returns.** The image was built at `4f84a65`
and the secure world on Tuesday 22 September 2026; the board reaches a
login with TF-A and OP-TEE resident and Linux running under PSCI on all
four CPUs. What it has not done is complete a single call into OP-TEE.
There are still no measurements in this README, and the rows that will
hold them say so.

What is proven on the board, each with the journal entry that holds the
console:

| Proven | Where |
|---|---|
| TF-A, OP-TEE and U-Boot boot in order from `armstub8.bin`, and Linux mounts Yocto's root with the kernel command line intact | entry 20 |
| The firmware's device tree has no `/psci` and no `/firmware/optee`; patched in RAM at the U-Boot prompt, Linux brings up four CPUs under PSCI v1.1 and the driver probes | entries 20 and 25, the fifteen commands in [BRINGUP.md](docs/BRINGUP.md) |
| `optee: revision 4.1 (18b424c2)` printed once, on the first boot, with the driver built in | entry 20 |
| The driver's first call into the secure world never returns, on every one of the four CPUs, at uptimes from twenty seconds to 551 | entries 20, 23, 25 to 29 |
| Within one second of that call the VideoCore firmware mailbox stops answering unrelated, healthy CPUs, seen six times from two independent consumers | entries 26 to 29, `docs/evidence/boot-console-2026-09-22.txt` |
| The card and the SD controller were never at fault: a 207 second control boot without the secure world ran clean | entry 21 |
| A read-only root with `systemd.mask=systemd-remount-fs.service` survives the hang intact, where three read-write runs each cost a filesystem | entries 27 and 28 |
| No normal-world observer that forks can survive the event, and SysRq does not answer on this kernel | entry 29 |

What is proven on a laptop:

| Proven | How |
|---|---|
| The signer and the verifier produce identical bytes for a record | `tests/keystore-canonical-test.sh`, 25 assertions |
| A tampered record, a forged MAC and another device's key all read as BAD | the same suite |
| The four commands, their errors, and what survives a reboot | `tests/keystore-policy-test.sh`, 29 assertions |
| The UUID, the command ids and the lengths agree across five files | `tests/keystore-header-test.sh`, 28 assertions |
| `CONFIG_TEE` and `CONFIG_OPTEE` exist and are settable | read out of `drivers/tee/Kconfig` at `rpi-6.6.y` |
| OP-TEE and TF-A both support this board | `core/arch/arm/plat-rpi3` at 4.1.0, `plat/rpi/rpi3` at 2.10 in the tree the kas file pins; the `armstub8.bin` actually built carries TF-A v2.6, see journal entry 18 |
| meta-arm can build them for it | `optee.inc` names `.bbappend or .conf` as the place to say so |

What none of that proves is that a MAC ever came out of a secure world,
and nothing on the board has proven it either. The
[acceptance table](#acceptance-criteria) says which rows are evidence and
which are still plans.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/tee.cfg` | The opt-in kernel fragment: the TEE subsystem. The driver is chosen by the next line |
| `meta-bench/recipes-kernel/linux/files/tee-builtin.cfg` and `tee-modular.cfg` | `CONFIG_OPTEE=y`, the product answer, or `CONFIG_OPTEE=m`, the debugging answer, picked by `BENCH_TEE_MODULAR` |
| `kas/bench-tee.yml` | meta-arm, the machine declaration OP-TEE asks for, and the version pin that has to match |
| `meta-bench/recipes-core/images/bench-tee-image.bb` | `bench-image` plus the client, the conformance suite and the keystore |
| `meta-bench/recipes-core/images/bench-tee-modular-image.bb` and `kas/bench-tee-modular.yml` | The same image with the driver as a module and `kernel-module-optee` installed, for a hang at probe; to be deleted when the hang is understood |
| `meta-bench/recipes-bench/bench-keystore/` | The TA, the client library, the CLI, the Python binding, the verifier, the LED daemon and two units |
| `scripts/optee-armstub.sh` | Puts the secure world on a card the image is already on |
| `tests/keystore-canonical-test.sh` and two more | What can be proven without a TEE |
| `projects/20-optee-keystore/docs/figures/` | Seven TikZ drawings, each compiling on its own |

## Running it

```sh
./go check                   # about 2 minutes, no board and no TEE
./go tee                     # bench-tee-image for the Raspberry Pi 3
./go tee-mod                 # the same, driver as a module, for debugging the hang
./go flash /dev/sdX
sudo ./go armstub install /mnt/boot ~/optee-rpi3/out/boot
```

The fifth line is the one that is unlike the rest of this repository, and
[the next section](#two-builds-one-card) explains why it exists. Today the
board also needs fifteen `fdt` commands at the `U-Boot>` prompt before
`booti`, because the firmware's device tree has no `/psci` and no
`/firmware/optee`. [docs/BRINGUP.md](docs/BRINGUP.md) has them in order,
and a permanent home for them is deliberately not chosen until the hang
they expose is understood.

On the board:

```sh
optee-selftest               # /dev/tee0, a session, then xtest
benchkey generate            # once, during provisioning
benchkey export-once > device.key   # once, ever, on the console
benchkey status              # key: yes  locked: yes
echo -n hello | benchkey sign -
```

[docs/DESIGN.md](docs/DESIGN.md) is the methodology: the two worlds, the
ownership table, the schematic, the boot chain, one signing call as a
sequence, and a decision tree for where a failure lives. Read it first.

[docs/THREAT-MODEL.md](docs/THREAT-MODEL.md) is what the board cannot
enforce, and what would have to change.

[docs/BRINGUP.md](docs/BRINGUP.md) is the board work in order, from an
empty card to a signed record a verifier accepts.

## Two builds, one card

This is the only project here whose image is not the whole story, and the
reason is the boot chain.

```
  every other project           this one
  -------------------           --------
  GPU firmware                  GPU firmware
       |                             |
       v                             v
  kernel8.img                   armstub8.bin   <- TF-A, OP-TEE inside it
       |                             |
       v                             v
  Linux                         BL31 monitor, resident at EL3
                                     |
                                     +--> OP-TEE OS at S-EL1
                                     |
                                     v
                                U-Boot
                                     |
                                     v
                                Linux
```

`bitbake` builds the kernel, the device trees, the rootfs and the trusted
application. The OP-TEE build repository builds Trusted Firmware-A, OP-TEE
OS and U-Boot and packs them into `armstub8.bin`. The two meet on the boot
partition, and `./go armstub` is that meeting.

**Why the secure world is not a recipe yet.** Writing one is the spec's own
stretch goal and it is a project rather than an afternoon: TF-A for this
board needs U-Boot as BL33, produces a FIP rather than a kernel, and
changes what the GPU loads. A recipe written here could not be built or
booted, and a recipe that looks right and is wrong is worse than a
documented manual step. The exact unknowns are listed in
[docs/BRINGUP.md](docs/BRINGUP.md#what-a-recipe-for-the-secure-world-would-have-to-settle)
so that the next person starts from a list rather than from scratch.

**The version that has to match.** The TA is compiled against the
development kit that `optee-os-tadevkit` produces, and it runs on the
OP-TEE that `armstub8.bin` carries. If those are different versions, the
TA is built against one set of headers and dispatched by another, and
nothing in either build says so. `kas/bench-tee.yml` pins 4.1.0 and the
bring-up notes have the one-line check on the board.

## Four things that are true of this image and not of a tutorial

**Secure storage is at `/var/lib/tee`, not `/data/tee`.** meta-arm builds
optee-client with `-DCFG_TEE_FS_PARENT_PATH='${localstatedir}/lib/tee'`.
Every document that says `/data/tee` is describing the OP-TEE default,
which this package overrides. Deleting that directory destroys the key,
with no recovery, and the tmpfiles entry says so where somebody will read
it.

**The supplicant is a template unit that nothing instantiates.** meta-arm
ships `tee-supplicant@.service` and sets `SYSTEMD_SERVICE` to it. A
template with no instance and no `DefaultInstance` starts nothing at boot,
and the symptom is the classic one: `TEEC_OpenSession` fails with an error
naming neither the supplicant nor the file it could not read.
`bench-keystore` ships the wants symlink that starts `tee-supplicant@0`,
and `optee-selftest` waits for the effect rather than ordering against the
name.

**meta-arm refuses to build OP-TEE for a machine nobody vouched for.**
`optee.inc` opens with `COMPATIBLE_MACHINE ?= "invalid"` and a comment
inviting you to add yours. That is the layer being careful rather than the
platform being unsupported, and `kas/bench-tee.yml` vouches in four lines,
in the place the comment names.

**`OPTEEMACHINE` is not `MACHINE`.** It defaults to `${MACHINE}` and is
passed to OP-TEE as `PLATFORM=`, so without a line it would look for
`plat-raspberrypi3-64`. The directory is `plat-rpi3`.

## Acceptance criteria

| # | Criterion | Evidence | State |
|---|---|---|---|
| 1 | Three banners on the console in order, then `dmesg` reports the OP-TEE revision and `/dev/tee0` exists | a console capture in `docs/evidence/` | **reached once, not held**: on Tuesday 22 September 2026 the three banners printed in order and `dmesg` reported `optee: revision 4.1 (18b424c2)`, then the board wedged on the driver's first call before `/dev/tee0` was checked. That console is quoted in journal entry 20; the capture in `docs/evidence/` is of two later boots in which the revision line never appears |
| 2 | `xtest` completes with zero failures on this image | `docs/evidence/xtest-report.txt` | **blocked** on criterion 1 |
| 3 | `generate` succeeds once and returns `ACCESS_CONFLICT` on a second call; the key object is an encrypted file under `/var/lib/tee` and is not plaintext | the CLI output and a hexdump | **policy proven against a model**, unproven on a TEE |
| 4 | `sign` of the same input gives the same 32 bytes before and after a reboot; `export-once` works exactly once | the CLI output across a reboot | **policy proven against a model**, unproven on a TEE |
| 5 | The verifier prints OK for a device record and BAD for an altered one | `tests/keystore-canonical-test.sh` today, and the same command against real records later | **met in software**, unproven end to end |
| 6 | A single signing call completes in under 1 ms | a timing table in `docs/evidence/` | **blocked** on criterion 1 |
| 7 | Removing the TA makes `TEEC_OpenSession` fail with `ITEM_NOT_FOUND` and origin `TEE`, and the red LED comes on | the CLI output and a photograph | **blocked** on criterion 1 |

Criterion 5 is the one to read carefully. The suite proves that the signer
and the verifier agree about bytes, which is the part that was wrong
first and the part that no board would have diagnosed. It does not prove
that a MAC ever came out of a secure world.

## What is tested without hardware

| Check | Command | Covers |
|---|---|---|
| The canonical form | `sh tests/keystore-canonical-test.sh` | The five serialisation rules, a round trip, tampering, a forged MAC, a foreign key, a stream, and that re-signing is stable |
| The TA's policy | `sh tests/keystore-policy-test.sh` | The four commands against a model written from the documented rules: provisioning, a reboot, both ways to lose a key, parameter contracts |
| The five restatements | `sh tests/keystore-header-test.sh` | That the UUID, the command ids, the lengths, the object names and the LED bytes have not drifted between C, Python, a makefile and a recipe |
| The fragment | `./go ksym -f tee` then `./go kconfig -f tee` | That every symbol exists, and that it reached the built kernel |

Not covered, and only a board can cover it. The board has now covered the
first three: TF-A loads, OP-TEE initialises, and the driver probes. It has
not covered the rest, because the driver's first call into the secure
world never returns: that the TA is signed with a key this OP-TEE trusts,
that `xtest` passes, and every number in the acceptance table.

## Departures from the original scope

| # | As originally scoped | Here | Why |
|---|---|---|---|
| 1 | A standalone `optee-bench` repository | A recipe in the shared layer, plus one script | The repository rule: one tree, one layer, no twenty copies of the same pins |
| 2 | Secure storage under `/data/tee` | `/var/lib/tee`, stated in the tmpfiles entry | That is where meta-arm's optee-client actually puts it |
| 3 | `After=tee-supplicant.service` | `After=tee-supplicant@0.service`, plus a wait on the effect | The packaged unit is a template; the plain name orders against nothing |
| 4 | The TA built by hand against an exported dev kit | Built by bitbake against `optee-os-tadevkit` | The spec's own stretch goal, and it keeps one version pin instead of two |
| 5 | The signer uses `json.dumps(rec, sort_keys=True)` and the verifier adds `separators=(",", ":")` | One `canonical()` shared by both | Those two differ by two spaces per field, so every record would have verified as BAD. See journal entry 4 |
| 6 | The LED indicator driven from the signing path | A datagram to a socket, which cannot block or fail | A signature must not depend on an LED being wired |
| 7 | Secure world and normal world in one build | Two builds meeting on the boot partition | Stated above, with the list of what a recipe would have to settle |

## Pitfalls, and what guards each one

| Pitfall | Guard |
|---|---|
| `tee-supplicant` not running before the first session | The recipe instantiates it, and `optee-selftest` waits and then says which of three things is wrong |
| Deleting `/var/lib/tee` | The tmpfiles entry names the consequence; the policy test asserts what the device looks like afterwards, which is brand new |
| A TA signed with a key OP-TEE does not know | The decision tree puts it in the same branch as a missing file, because that is how it presents |
| Parameter type mismatches between client and TA | One shared header, and a test that parses it |
| The two builds drifting apart in version | The kas file pins, and the bring-up notes check on the board |
| A wrong `enable_uart` | The schematic says the secure world prints before the clock is pinned, so the garbage is from TF-A and OP-TEE only |
| A `config.txt` without `arm_64bit=1` | The firmware loads `armstub8.bin` only in 64-bit mode, and without the line the card is silent from power on. `./go armstub remove` appends it, and BRINGUP has the three-boot table that proved it |
| The firmware's device tree, which has no `/psci` and no `/firmware/optee` | Fifteen `fdt` commands at the `U-Boot>` prompt, `fdt addr 0x04000000` first, in BRINGUP. Without that first one the next command answers `No FDT memory address configured` and nothing else runs |
| A driver that hangs at probe, on a read-write root | Three runs each cost a filesystem. `./go tee-mod` makes the call from a login, `ro` plus `systemd.mask=systemd-remount-fs.service` keeps the root untouched, and since no observer that forks survives the event, the observer is started first |
| Calling this "secure key storage on the Pi" | The first paragraph, the threat model, and the sentence to use instead |

---

[Journal](JOURNAL.md) | [Design](docs/DESIGN.md) |
[Threat model](docs/THREAT-MODEL.md) | [Bring-up](docs/BRINGUP.md) |
[Figures](docs/figures)
