# Bring-up: from an empty card to a signed record

In order. Nothing below has been performed; it is the plan, written
alongside the code, and it will be corrected in the
[journal](../JOURNAL.md) the first time it meets hardware.

The console is not optional in this project. Three boot stages print
before Linux exists, and a failure in any of them produces a board with no
`dmesg`, no network and no LED, because none of those exists yet.

## 0. Before the power goes on

| Check | Why |
|---|---|
| The board is a Pi 3, and `machine:` in `kas/bench-rpi3.yml` is `raspberrypi3-64` | An image built for the Pi 4 does not boot here and does not say so; the symptom is a dark board that reads as dead hardware |
| The USB/TTL cable: **black** lead to pin **6** (GND), **white** lead to pin **8** (GPIO14, `TXD0`, the board transmits), **green** lead to pin **10** (GPIO15, `RXD0`, the board receives), **red** lead connected to nothing | It is the only instrument that sees the secure world. Pins 6, 8 and 10 are three consecutive pins in the outer row, second to fourth from the corner where pin 2 sits. The red lead is 5 V and the board has its own supply. Colours are this bench's PL2303 cable; another adapter's printed labels win over them |
| The three LEDs are on GPIO17, 27 and 22 with 330 ohm resistors, cathodes to pin 9 | Wrong pins drive whatever else is there |
| The card's previous contents are archived, and the restore command is known | This bench has **one card**. Every flashed instance is archived with `./go archive` and copied to the Desktop before the card is reused, so "the card this project owns" is not how it works here. Mount the FAT partition read-only and say whose image is on it first; on Tuesday 22 September 2026 it was the NEO Air's provisioning card, restored by `./go neo-air card`. Project 17 builds for the same `MACHINE`, so its image and this one still cannot share a card at the same time |
| The card is not the hot one | A microSD that is warm to the touch after a failed write is faulting, and through a reader it presents as USB resets and CRC errors that look exactly like a bad USB/IP link. One did on 22 September 2026 and was blamed on the link until a second card wrote clean. It is out of the pool |

## 1. Build both halves, and pin them to each other

Two builds, and the version they share is the thing to get right.

```sh
# the normal world, the TA and the rootfs
./go tee

# the secure world, in its own checkout, on the Linux filesystem.
# Two host packages first; neither is in the OP-TEE build's own docs
# for this platform and both stopped the first attempt:
sudo apt-get install -y repo python3-pyelftools
mkdir -p ~/optee-rpi3 && cd ~/optee-rpi3
repo init -u https://github.com/OP-TEE/manifest.git -m rpi3.xml -b 4.1.0
repo sync -j4                                  # 2.1 GB, about four minutes
cd build && make -j8 toolchains && make -j8 tf-a u-boot-env
mkdir -p ../out/boot
cp ../trusted-firmware-a/build/rpi3/debug/armstub8.bin ../out/uboot.env ../out/boot/
ls -la ../out/boot     # armstub8.bin 1261624 bytes, uboot.env 16384 bytes
```

**Not `make -j8`, and not `update_bootfs`, on purpose.** `all` also builds
Buildroot, a Linaro 5.17 kernel and a rootfs this project never uses; the
image is Yocto's. And `update_bootfs`, the target that fills `out/boot`,
depends on `linux` and installs that kernel as `kernel8.img` together with
`bootcode.bin` and friends from a **2019** firmware tag, over a Yocto boot
partition that carries a 2025 set. `tf-a` and `u-boot-env` produce the two
files `./go armstub install` actually reads. `armstub8.bin` embeds U-Boot
as BL33 inside the FIP, so no separate `u-boot.bin` is wanted, and the
installer writes its own three `config.txt` lines rather than copying the
reference file. Built this way on Tuesday 22 September 2026 in about forty
minutes including the toolchain download, at TF-A **v2.6**, which is what
the 4.1.0 manifest pins; the kas comment's "TF-A 2.10" is about where
`plat/rpi/rpi3` exists, not about the version built.

**Write down what you built.** `repo manifest -r` prints every commit id;
put its output in `docs/evidence/rpi3-manifest.txt`. OP-TEE moves fast and
"built from 4.x" is not reproducible.

**Check the two halves agree.** `kas/bench-tee.yml` pins
`PREFERRED_VERSION_optee-os = "4.1.0"`, and the reference build must be at
the same tag. If they differ, the TA is compiled against one dev kit and
dispatched by another OP-TEE, and nothing in either build will mention it.
The check that settles it is on the board, in step 4.

**The `-b 4.1.0` above is what makes that true, and it was missing.** This
page asked for the tag in the paragraph you are reading and then gave a
`repo init` without it, which takes the manifest's default branch: OP-TEE
tip on whatever day the command is run. The two halves would then differ
by however far tip has moved, and the failure mode is the one described
above, which no build reports. Corrected on Monday 21 September 2026,
before either half was built.

Before paying for the long build, check the fragment:

```sh
./go bitbake bench-tee -c kernel_configme virtual/kernel
./go ksym -f tee       # every line names a symbol that exists
./go kconfig -f tee    # every line reached the .config
```

## 2. Write the card, then add the secure world

```sh
./go flash /dev/sdX
# mount the FAT partition, then
./go armstub install /mnt/boot ~/optee-rpi3/out/boot
./go armstub status /mnt/boot
```

`status` should report `armstub8.bin present`, `uboot.env present`,
`config.txt boots the secure world` and `kernel8.img present`. That last
one matters: U-Boot loads `kernel8.img` from partition 1, so an image
whose kernel is named anything else stops at a U-Boot prompt that looks
like a hang to anyone not watching the console.

To go back to a board with no secure world, `./go armstub remove
/mnt/boot` restores the `config.txt` that was there before.

## 3. The first boot, watched

Console attached, at 115200. Three banners, in this order:

```
NOTICE:  BL1: v2.10 ...
I/TC: OP-TEE version: 4.1.0 ...
U-Boot 20xx.xx ...
```

Then the kernel. If any of the three is missing, stop and use the
[decision tree](DESIGN.md#where-a-failure-lives): each missing banner puts
the fault in a different place, and the first two questions need nothing
but this console.

Once Linux is up:

```sh
dmesg | grep -i optee        # revision, and "dynamic shared memory"
ls -l /dev/tee0 /dev/teepriv0
systemctl status tee-supplicant@0
systemctl status optee-selftest
```

**`tee-supplicant@0`, with the instance number.** The packaged unit is a
template and the plain name is not a unit at all. `bench-keystore`
installs the symlink that starts instance 0; if `systemctl status
tee-supplicant@0` says it is not loaded, that symlink is the thing to look
for.

## 4. Conformance, before anything is believed

```sh
optee-selftest
xtest > /var/lib/bench/tee/xtest-report.txt 2>&1
tail -20 /var/lib/bench/tee/xtest-report.txt
```

Zero failures, and the report goes into `docs/evidence/`. Everything after
this step assumes it passed; a failure here is OP-TEE, not this project's
code, and diagnosing the TA against a broken TEE wastes an evening.

**The version check, one line:**

```sh
dmesg | grep -i "optee: revision"
```

Compare with the `PREFERRED_VERSION_optee-os` in `kas/bench-tee.yml`. The
running OP-TEE is the only authority on which OP-TEE is running.

## 5. Provisioning, which happens once

On the console, not over the network, because the key crosses the terminal
in step three.

```sh
benchkey status              # key: no   locked: no
benchkey generate            # key generated
benchkey status              # key: yes  locked: no
benchkey export-once > /tmp/device.key
benchkey status              # key: yes  locked: yes
```

Copy `/tmp/device.key` to the host, into the verifier's key file, and
delete it from the board. Then prove the lock:

```sh
benchkey export-once         # ACCESS_DENIED, and says why
benchkey generate            # ACCESS_CONFLICT, and says why
```

**A device with `key: yes, locked: no` is half provisioned.** `benchkey
status` prints a note when it sees that, because the state should not
survive the bench: it means the key exists and can still be read out.

Reboot, and prove the key survived:

```sh
echo -n hello | benchkey sign -     # same 32 bytes as before the reboot
benchkey status                     # key: yes  locked: yes
```

## 6. End to end, with a verifier

On the board:

```sh
echo '{"host_ts":1,"v":42}' > /tmp/rec.json
benchkey sign /tmp/rec.json
```

On the host, with the exported key:

```sh
printf '{"host_ts":1,"v":42,"mac":"<the hex above>"}\n' |
    benchkey-verify --key device.key
```

`OK` for that record; change one byte of the JSON and it prints `BAD`. Both
lines belong in the README as evidence, and the verifier exits non-zero
when anything failed, so a script can use it.

For the full pipeline, Project 17's gateway calls `BenchKey.sign_record()`
and publishes with a `mac` field; `benchkey-verify --mqtt` subscribes and
checks every record. That needs the two images in sequence on one card, so
it is the last step rather than the first.

## 7. The numbers

Three, and they belong in `docs/evidence/` rather than in scrollback.

**Signing rate.** Time 10000 signatures of a 200-byte message and divide.
The acceptance criterion is under 1 ms per call; expect the cost to be
dominated by the SMC round trip rather than by the HMAC, and say so with
the two numbers rather than asserting it.

**World-switch cost.** `xtest -t benchmark` has the round-trip figures.
Compare with a normal-world `sha256` of the same message to show what the
switch costs over the arithmetic.

**TA heap.** `TA_DATA_SIZE` in `user_ta_header_defines.h` is 32 kB, chosen
because that is what the examples use, and it is a guess until the board
reports otherwise. `plat-rpi3/conf.mk` already sets `CFG_WITH_STATS=y`, so
the figures are available; record the real number and the journal entry
that corrects the guess.

## What a recipe for the secure world would have to settle

`./go armstub` exists because the secure world is not built by bitbake
here. Anyone attempting that recipe starts with these, which are the
things that stopped it being attempted now:

1. **TF-A's output is not a kernel.** `PLAT=rpi3` with `SPD=opteed`
   produces `armstub8.bin`, a BL1 plus a FIP. meta-arm's
   `trusted-firmware-a` recipe has its own conventions for
   `TFA_PLATFORM`, `TFA_BUILD_TARGET` and `TFA_INSTALL_TARGET`, and none
   of them has been checked against this platform's `fip` step.
2. **BL33 is U-Boot**, so a U-Boot recipe has to produce a `u-boot.bin`
   that TF-A consumes, and the boot flow of every other image in this
   repository does not have a U-Boot in it.
3. **`uboot.env` is a build artefact**, generated from a text file by
   `mkenvimage`, and it carries the commands that load `kernel8.img`.
4. **`IMAGE_BOOT_FILES` cannot carry `armstub8.bin`** unless something in
   the build produces it, which is the circular part: the image cannot
   contain the secure world until the secure world is a recipe.
5. **meta-raspberrypi's `armstubs` recipe builds a different stub**, the
   plain one from `raspberrypi/tools`, and a second provider of the same
   file name needs a decision rather than a coincidence.

Points one to three are a few days of work by someone with a board to test
on. Point four is the reason it has to be all of them at once.

---

Back to the [project README](../README.md), the [design](DESIGN.md) or the
[threat model](THREAT-MODEL.md).
