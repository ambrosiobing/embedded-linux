# Bring-up

First boot in order, with the check that catches each silent failure.
Every step here can fail in a way that looks like the next step failing,
so each is confirmed before the next is tried.

**Every command block says which machine it is for.** Two laptops, two
clones, no shared filesystem, and a board with two ways in.

## Before power

- The panel takes **5 V from header pins 2 and 6**, not from a USB port.
  The panel works either way; the touch controller's power sequencing
  does not on some revisions, and the symptom is a picture with no touch,
  which sends you to the wrong layer.
- **The DSI ribbon carries the touch I2C on a Pi 4.** The SDA and SCL
  jumpers in older wiring guides are for earlier boards. Adding them puts
  a second driver on the same bus.
- Use the **3 A USB-C supply**. Panel and backlight are about 450 mA, the
  keyboard hub up to 200 mA more, and the Pi 4 peaks above 1 A.
- The USB/TTL cable's **red lead stays open**.

## 1. Check the disk before building

On the **build laptop (WSL)**. The number that matters is the Windows
one; `df` inside the guest reports the virtual disk maximum and has read
925 GB free while `C:` had 28.

```bash
powershell.exe -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1GB,2)"
```

This image needs a kernel rebuild on the first run (the command line
changes), so budget **about 25 GB**. `scripts/build.sh` guards on it.

## 2. Build

On the **build laptop (WSL)**:

```bash
./go kiosk
```

**Expect the first build to be long.** `DISTRO_FEATURES:append = " pam"`
is a distro-wide change, so it invalidates far more than this project's
own recipes. That cost is the price of weston refusing to build without
it, and it is paid once.

## 3. Flash, then read the card back

On the **build laptop (WSL)**:

```bash
./go flash /dev/sdX
```

Read the boot partition before it leaves the reader, because these three
lines are where this project succeeds or fails and they are far easier to
check now than from a board that will not talk:

```bash
grep -E 'dtoverlay|gpu_mem|disable_splash|boot_delay' /mnt/boot/config.txt
```

Expect `dtoverlay=vc4-kms-dsi-7inch` (from `bench-rpi4.yml`),
`disable_splash=1` and `boot_delay=0`.

```bash
cat /mnt/boot/cmdline.txt
```

It must contain `video=DSI-1:800x480@60,panel_orientation=upside_down`
and `console=tty1`.

## 4. First boot, and the two checks that catch the classic failure

Power the board with the serial cable attached and a terminal logging.

**On the board over the picocom console** (or ssh once it is up):

First, that the drivers are even present. **Every graphics driver on
this platform is a module**, and an image that did not install them
produces a black screen indistinguishable from a hardware fault:

```sh
lsmod | grep -E 'vc4|v3d|drm|ft5x06|panel'
```

Expect `vc4`, `v3d`, `drm`, `drm_kms_helper` and the panel and touch
drivers. If this is empty, nothing below this point can work and the
cause is the image, not the board. Keep the output:

```sh
lsmod > /tmp/lsmod.txt
```

It belongs in `docs/evidence/`, and it is also the measurement that
would let `kernel-modules` be narrowed to a named list later.

```sh
bench-gfx drm
```

This is the whole KMS layer in one command. What it should say:

- `DSI-1 is connected (on cardN)` and the first mode `800x480`
- how many DRM cards there are, and the warning that one of them has no
  connectors

**If `DSI-1` is missing or disconnected, stop here.** Nothing above this
layer can work, and the cause is the overlay or the ribbon, not the
compositor.

```sh
bench-gfx input
```

Expect a touch device and the **name it presents**. Write that name down:
it is what a udev calibration rule would have to match, and it differs
between kernel versions. `FT5406` and `raspberrypi-ts` are both seen in
the wild.

## 5. Check which seat backend was actually used

**On the board over the picocom console:**

```sh
systemctl is-active weston.service; bench-gfx compositor
```

The journal line naming the backend is the one to read.

**This check exists because of a specific doubt, recorded rather than
hidden.** oe-core's `seatd` recipe ships no systemd unit, so on this
image the seat should come from **logind**, through the PAM session that
`weston.service` opens. That is inferred from reading the recipe and the
unit, **not yet seen on this board**.

If the journal says `could not connect to seat`, the fallback is the
specification's Debian path:

```sh
systemctl enable --now seatd
systemctl set-environment LIBSEAT_BACKEND=seatd
systemctl restart weston
```

**It is not a permission problem on `/dev/dri`**, which is where the
error sends most people.

## 6. The dashboard

```sh
bench-gfx client
```

Expect `bench-hmi is running` and a Wayland socket. If weston is up and
`bench-hmi` is not, the `[autolaunch]` section of
`/etc/xdg/weston/weston.ini` is the place to look.

Then confirm the compositor offers what the client needs:

```sh
wayland-info | grep -E 'xdg_wm_base|wl_seat'
```

`wl_seat` must advertise **touch** capability. A seat with only pointer
and keyboard produces a dashboard that ignores fingers and looks like a
toolkit problem.

## 7. Touch, measured before it is corrected

**On the board over the picocom console:**

```sh
libinput debug-events --verbose
```

Touch the **top left of the picture**. The coordinates should be near
zero.

**If they are, do nothing.** The rotation set on the kernel command line
has been inherited correctly by both the output and the touch mapping,
and that is the whole design. `99-bench-touch.rules` ships disabled for
exactly this case: arming it here rotates the touch surface a second time
and produces touch that works correctly upside down, which is the hardest
version of this bug to read.

If they are wrong, the rule is in
`/usr/share/doc/bench-kiosk/99-bench-touch.rules` with the procedure in
its header.

## 8. Keyboard, with touch out of the way

Acceptance asks that Tab and Enter work **with the touch driver
unloaded**, which is what proves the two input paths are independent
rather than one path with two names.

```sh
modprobe -r edt_ft5x06; systemctl restart weston
```

Then Tab and Enter on the Pi keyboard. Afterwards:

```sh
modprobe edt_ft5x06; systemctl restart weston
```

## 9. The boot budget

Measure before trimming. **Both halves**, because one instrument is blind
to the first two thirds.

**On the board over ssh:**

```sh
systemd-analyze; systemd-analyze critical-chain weston.service
```

```sh
systemd-analyze blame | head -n 20
```

The firmware and kernel part comes only from the **serial console with
terminal timestamps**, which is why the USB/TTL cable is in the parts
list for a project with a screen.

A Yocto image starts from a very different place than the Raspberry Pi OS
Lite the specification measures: no NetworkManager, no ModemManager, no
apt timers. **The budget should be easier to meet and most of the
specification's trim list inapplicable.** That is a finding to record,
not a reason to skip the measurement.

## If something is wrong

```
  run bench-gfx first, all four layers, and read from the top
  |
  +-- drm says no connected connector
  |     --> the overlay or the ribbon. Nothing above can work.
  |
  +-- drm is fine, compositor says "no outputs"
  |     --> weston opened the card without connectors (v3d).
  |
  +-- compositor says "could not connect to seat"
  |     --> logind or seatd, NOT /dev/dri permissions. Step 5.
  |
  +-- compositor is up, client is not
  |     --> [autolaunch] in weston.ini, or bench-hmi is missing.
  |
  +-- everything up, touch does nothing
        --> wayland-info: does wl_seat advertise touch?
            then WAYLAND_DEBUG=1 on the CLIENT, never the compositor.
```

---

Back to [DESIGN.md](DESIGN.md), on to
[DEBUGGING.md](DEBUGGING.md), or the [project README](../README.md).
