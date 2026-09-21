# Project 19: bring-up

The order matters here more than in most projects, because the step that
can leave the board unbootable comes early and the recovery for it is
physical.

**Read this first.** The boot script, `u-boot.bin` and the device tree are
on the shared FAT partition and are in no bundle. A mistake in any of them
takes out both slots at once. The second microSD card is the recovery path
and it is not optional.

## 1. The signing material, on the build laptop only

RAUC signs bundles and the board verifies them. Three paths are needed and
**none of them is in this repository**. They are left empty in
`kas/bench-rpi3-ab.yml`, and every recipe that needs one refuses to build
and names the variable rather than falling back to meta-rauc's example
certificate, whose private half is published on the internet.

A self-signed development pair is enough for a bench. On the wsl build
laptop JPTOUPM678:

```bash
mkdir -p ~/bench/keys && chmod 700 ~/bench/keys
```

```bash
cd ~/bench/keys && openssl req -x509 -newkey rsa:4096 -nodes -keyout dev.key.pem -out dev.cert.pem -days 3650 -subj "/O=embedded-linux-bench/CN=bench-rpi3 development"
```

```bash
chmod 600 ~/bench/keys/dev.key.pem && ls -l ~/bench/keys
```

Then fill the three paths in `kas/bench-rpi3-ab.yml`. With a self-signed
pair the certificate is also its own CA, which is why two of the three
point at one file:

```
BENCH_RAUC_CA   = "/home/<user>/bench/keys/dev.cert.pem"
BENCH_RAUC_CERT = "/home/<user>/bench/keys/dev.cert.pem"
BENCH_RAUC_KEY  = "/home/<user>/bench/keys/dev.key.pem"
```

**The private key never leaves that machine and is never committed.** The
repository's own check refuses any `.pem` under `meta-bench`, and
`tests/ab-config-test.sh` asserts it on every run.

A second pair under a different name is what criterion 7 needs: a bundle
signed with a key the board does not trust must be refused. Make it the
same way, with a different `CN`, and keep it for that test.

## 2. Build

```bash
cd ~/bench && ./go ab
```

This is a kernel fragment change, so it is a kernel rebuild rather than an
incremental build. Check the free space on the Windows drive before
starting, not after it fails, and read `Sstate summary` on the first screen
of output: it is the number that says whether this is a warm build or a
cold one.

`raspberrypi3-64` is `cortexa53` and this bench has built that tune before,
on Wednesday 16 September 2026 for Project 8, and kept `sstate-cache`. That
is a reason to expect a warm build, not a promise of one.

## 3. Write the card

**Name the image rather than letting it be chosen.** `flash.sh` picks the
newest `.wic.bz2` by modification time, which is the right rule when the
choice is between machines: it is what stops a Pi 4 image reaching a Pi 3.
It does not separate two images built for the *same* machine, and this
project produces exactly that situation. `bench-image` and `bench-ab-image`
are both `raspberrypi3-64` and land in one directory, so whichever was
built last wins.

Getting that wrong is quiet. A `bench-image` card boots, reaches a login
and looks entirely correct; it simply has one root partition, no slots and
no update mechanism, and nothing says so until an install fails much later.
The script does print the images it ignored above the confirmation prompt,
so read that line rather than pressing through it.

```bash
cd ~/bench && ls -lt build/tmp/deploy/images/raspberrypi3-64/*.wic.bz2
```

```bash
cd ~/bench && ./go flash /dev/sdX build/tmp/deploy/images/raspberrypi3-64/bench-ab-image-raspberrypi3-64.rootfs.wic.bz2
```

Check the device with `lsblk` first. The card that comes out of this has
slot A populated, **slot B empty**, and an empty data partition. That is
correct: the first update is what fills slot B, and until then a boot of
slot B fails, spends an attempt and returns to A, which is the mechanism
working rather than a fault.

Before the card leaves the reader, decide whether it needs credentials on
the FAT partition. This project does not require a network.

## 4. First boot

Console is 115200 on GPIO14/15, ground on pin 6, and the cable's red 5 V
lead stays taped back and disconnected. The board is powered from its own
USB supply.

What the console should show, in order:

1. the GPU firmware
2. `U-Boot 20xx.xx`
3. `Slot A chosen, 2 attempts left after this one`
4. `Booting slot A from /dev/mmcblk0p2`
5. the kernel, then a login prompt

Then, on the board:

```bash
rauc status
```

`boot-status: good` means the health check passed and meta-rauc's
mark-good service has reset the counter. To see that it really was reset:

```bash
fw_printenv BOOT_A_LEFT BOOT_B_LEFT BOOT_ORDER
```

**If `fw_printenv` reports a bad CRC**, the environment size in
`/etc/fw_env.config` does not match U-Boot's `CONFIG_ENV_SIZE`. Check that
before anything else: RAUC cannot mark a slot either way, and every
symptom downstream of it is misleading.

## 5. The LEDs, and the one thing the overlay cannot know

Green means slot A, yellow means slot B, and red blinking means the slot is
running but not yet confirmed. After a clean boot the red LED should go out
within a few seconds of the login prompt, because the health check passed.

```bash
ls /sys/class/leds/ ; cat /sys/class/leds/ab-busy/trigger
```

If those directories do not exist, the `dtoverlay=gpio-led` lines did not
reach `config.txt`. Check the card's FAT partition rather than the board.
The board runs perfectly well without them and reports its slot on the
console, so nothing else will complain.

**If an LED is on when it should be off, and off when it should be on**, the
modules are wired the other way round from what the overlay assumes. The
LED class device has no way to detect this. `leds.conf` records that this
bench is active high, and the overlay takes `active_low` as a parameter:

```bash
gpioset -c gpiochip0 17=1
```

Green lights: active high, leave the overlays alone. Green stays dark and
lights on `17=0` instead: add `,active_low=1` to each overlay line in
`kas/bench-rpi3-ab.yml`. `gpioset` in libgpiod v2 holds the line until
interrupted, so press Ctrl-C between the two commands.

Force each state by hand rather than waiting for one to happen:

```bash
bench-slot-leds busy ; sleep 2 ; bench-slot-leds unconfirmed ; sleep 2 ; bench-slot-leds good
```

## 6. Criterion 3, the read-only root and its overlay

```bash
mount | grep " / " ; touch /usr/x ; touch /etc/x ; findmnt /data
```

`/usr/x` must fail and `/etc/x` must succeed. Reboot, and `/etc/x` must
still be there, because it is in the overlay's upper layer on p4.

```bash
findmnt /var/log/journal ; journalctl --disk-usage
```

The journal must be on the data partition. This is not tidiness: every
interesting event in this project is followed by a reboot, and a volatile
journal would delete the record of why each one happened.

## 7. Install a good bundle

On the build laptop:

```bash
cd ~/bench && ./go ab-bundle
```

Copy it to the board, then:

```bash
rauc install /data/bench-ab-raspberrypi3-64.raucb && reboot
```

The board comes back on slot B, the yellow LED replaces the green one, and
`rauc status` reports the new version.

## 8. The three failures, which are the actual deliverable

**A bad application.** On the build laptop:

```bash
cd ~/bench && ./go ab-broken
```

That builds a bundle identical to the good one except that its
`bench-app.service` runs `/bin/false`. It is correctly signed and carries
the right compatible string, so it installs without complaint; the failure
is meant to happen afterwards, on the next boot, from inside the new slot.
The file names itself `bench-ab-broken`, because three bundles end up in
one directory and two of them are supposed to fail.

Install it and reboot. Expect exactly three attempts of slot B in the
console log, then an automatic return to slot A with no manual action, and
slot B marked bad. Keep the whole log: it is the deliverable, and the
journal on the data partition survives every one of those reboots, so
`journalctl --boot=-1` can be read afterwards from slot A.

**A hung kernel**, from the console of the slot under test:

```bash
echo c > /proc/sysrq-trigger
```

The board must reset within 15 s and the running slot's counter must drop
by one. This is the failure the boot counter alone cannot catch, and the
reason the watchdog is in the kernel fragment.

**A forged bundle**, and then a mismatched one. These are two different
mechanisms failing at two different moments, which is why the criterion
asks for both.

Point `BENCH_RAUC_KEY` and `BENCH_RAUC_CERT` at the second key pair from
step 1, rebuild with `./go ab-bundle`, and install. It must be refused with
a signature error, when the bundle is opened.

Then put the paths back and build the mismatched one:

```bash
cd ~/bench && ./go ab-wrong
```

That one is correctly signed and claims to be for `bench-rpi4`, which is
what a bundle for the Pi 4 on this same bench would carry. It is the
mistake somebody would actually make, rather than a nonsense string that
would only demonstrate that RAUC compares strings. It must be refused when
the system is examined, before anything is written to the inactive slot.
Quote both refusals; they should not read alike.

## Recovery

If the board stops at a U-Boot prompt or shows nothing at all, the fault is
in something shared rather than in a slot, and no amount of rebooting
helps. Power off, swap in the second card, and compare its FAT partition
against the one that failed.

If both slots run out of attempts, the boot script resets both counters to
3 and reboots, and says so on the console. If that repeats, the fault is
again shared: `boot.scr`, the device tree, or the firmware on p1.
