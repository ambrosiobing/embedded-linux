# Bring-up

First boot in order, with the check that catches each silent failure.

**Every command block says which machine it is for.** Two laptops, two
clones, no shared filesystem, and a board with two ways in. In this
project that last point is sharper than usual: **the serial console is
the only way in that does not depend on the thing being built.**

## Before power

Read this section before plugging anything in. It is the one project on
this bench where the wiring can damage the host.

- **The host's USB port is the only supply.** 500 mA on USB 2.0, 900 mA
  on USB 3, against a Pi 4 that idles near 550 mA. No display, no HAT, no
  second board.
- **Do not feed 5 V into header pin 2 or 4** while the host provides
  VBUS. The USB-C VBUS and the 5 V rail are joined through a fuse, and a
  second supply back-feeds the host's port.
- **Use a plain USB-C cable.** One with an e-marker chip does not power a
  revision 1.1 Pi 4 at all, because of the shared CC pull-down on that
  revision. Later revisions are fine.
- **The Pi reboots when the cable moves** from its own supply to the
  host, because the supply is what moved. Shut down first.
- The USB/TTL cable's **red lead stays open**.

## 1. Check the disk, then build

On the **build laptop (WSL)**. The Windows figure is the one that counts;
`df` inside the guest reports the virtual disk maximum.

```bash
powershell.exe -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1GB,2)"
```

This image changes the kernel configuration, so the first build rebuilds
the kernel: budget **about 25 GB**, which is what `scripts/build.sh`
guards on.

```bash
./go gadget
```

## 2. Flash, then read the card back

On the **build laptop (WSL)**:

```bash
./go flash /dev/sdX
```

Read the boot partition before the card leaves the reader. These two
lines are the difference between a USB device and a power inlet:

```bash
grep -E 'dwc2|arm_freq' /mnt/boot/config.txt
```

Expect `dtoverlay=dwc2,dr_mode=peripheral` and `arm_freq=1000`.

## 3. First boot on the board's OWN supply

**Not on the host yet.** Boot on the normal 3 A supply with the USB/TTL
console attached, so that the gadget can be inspected before anything
depends on it.

**On the board over the picocom console:**

```sh
ls /sys/class/udc
```

Expect `fe980000.usb`. **An empty directory here means the port is still
a host port**, and there are exactly two causes:

| Cause | Check |
|---|---|
| the overlay did not load | `grep dwc2 /boot/config.txt`, then `dmesg \| grep -i dwc2` |
| the driver was built without peripheral support | `zcat /proc/config.gz \| grep -E 'DWC2\|CONFIGFS'` |

Both produce the same empty directory, which is why `bench-gadget`'s
refusal names both rather than guessing.

```sh
dmesg | grep -i dwc2
```

The controller should report device mode and its endpoint count. **`EPs:
8`** is EP0 plus the seven the budget spends.

## 4. Build the gadget by hand, once

Before trusting the unit, run it the way the unit will:

```sh
bench-gadget status
```

```sh
bench-gadget up && bench-gadget status
```

Expect `bound: fe980000.usb`, and then the three device nodes:

```sh
ls -l /dev/hidg0 /dev/ttyGS0; ip link show usb0
```

**If `up` fails, read the message rather than retrying.** It names which
of the four preconditions was missing, and a second `up` on a
half-built tree refuses by design.

Then tear it down and check it comes apart cleanly:

```sh
bench-gadget down && bench-gadget status
```

A `PARTIAL teardown` message here is a real finding: the next `up` will
refuse until the tree is gone, and the message names what could not be
removed.

## 5. Move to the host

**Shut down first.** The board reboots the moment the cable moves,
because the supply moves with it.

```sh
poweroff
```

Then move the USB-C cable to the host PC and power the board from it.
Keep the USB/TTL console attached.

**On the host (Linux):**

```bash
lsusb -d 1d6b:0104 -v | grep -E 'bNumInterfaces|bInterfaceClass|bEndpointAddress|MaxPower'
```

Check it against the prediction in
[DESCRIPTORS.md](DESCRIPTORS.md#the-budget-written-first): one
configuration, **five** interfaces, **seven** endpoints. Paste the full
output into that document.

```bash
ip link; ls -l /dev/serial/by-id/
```

```bash
picocom -b 115200 /dev/ttyACM0
```

A login prompt, with nothing configured on the host.

**On a Windows host**, the network function needs `NET=ncm`; ECM has no
in-box driver. See
[DESCRIPTORS.md](DESCRIPTORS.md#on-a-windows-host).

## 6. The keyboard, and the point of no return

**Read this before plugging the keyboard in.**

`kbd-bridge` **grabs** the keyboard. From the moment it starts, that
keyboard types on the **host**, not on the Pi, and the Pi has no local
input at all. The USB/TTL console is the only way to type on the board.

First confirm the udev rule matches the keyboard you actually have. The
rule ships with `04d9`, which is Holtek, which is what the official
Raspberry Pi keyboard reports. **A different keyboard has a different id,
and a rule that matches nothing fails silently**: no symlink, no device
unit, no service, and nothing anywhere saying why.

**On the board over the picocom console:**

```sh
lsusb
```

```sh
ls -l /dev/input/bench-kbd
```

If the symlink is absent, find the real id and fix the rule:

```sh
udevadm info -a -n /dev/input/event0 | grep -m1 idVendor
```

Once the symlink exists the bridge should already be running, pulled in
by the rule:

```sh
systemctl status kbd-bridge.service
```

Then type on the Pi keyboard and watch the text appear **on the host**.

## 7. Macros

```sh
echo 'ssh root@10.42.0.1' > /run/kbd-bridge/macro
```

The string is typed into whatever has focus on the host. Try it against
a text editor before trying it against a shell.

**Right Ctrl plus M replays the last macro**, from the physical keyboard,
with no shell needed. The M is consumed rather than forwarded, so the
host gets the macro and not a stray letter in front of it. Before any
macro has been sent, the hotkey says so on the journal rather than
typing nothing.

## 7a. The host side

Three files under [`../host/`](../host) belong on the **host**, not on
the board, and no recipe installs them.

On a **Linux host**:

```bash
sudo install -m0644 projects/14-usb-gadget/host/linux/70-pi-gadget.rules /etc/udev/rules.d/
```

```bash
sudo udevadm control --reload
```

That gives the gadget's serial port a fixed `/dev/pi-console`, so nothing
has to guess whether it is `ttyACM0` or `ttyACM1` today.

```bash
sudo install -m0600 -o root -g root projects/14-usb-gadget/host/linux/nm-pi-gadget.nmconnection /etc/NetworkManager/system-connections/
```

**The 0600 matters and NetworkManager enforces it.** A connection file
that is group readable is ignored silently, and the symptom is a profile
that never appears in `nmcli`.

That profile carries `never-default=true`, so the host does not route
through the Pi. The board declines to offer a route as well; both ends
refuse independently, because either alone would do and neither can be
relied on when the other end is somebody else's machine.

On a **Windows host** there is nothing to install, and one function does
not work: see [`../host/windows/README.md`](../host/windows/README.md).

**The layout caveat is real and is not a bug.** The gadget sends usages,
not characters: a macro containing `z` types `y` on a host set to a Swiss
or German layout, because usage 0x1d is "the key where z is on a US
keyboard". The table in `kbd_bridge.c` is US and says so.

## 8. The undervoltage check

Acceptance criterion 7, and it is the one that fails quietly.

**On the board over ssh** (through the gadget network, which is the point):

```sh
journalctl -k | grep -i -E 'undervoltage|under-voltage'
```

Run it after ten minutes with the keyboard attached and some load. A
brown-out during enumeration presents as a gadget that does not work,
and the journal entry explaining it is on a board that just reset.

If it warns, `arm_freq=1000` is already set; the next steps are a USB 3
port rather than USB 2, and removing anything else drawing current.

## If something is wrong

```
  the host sees nothing at all
  |
  +-- ls /sys/class/udc on the Pi: empty?
  |     yes --> the port is a host port. Overlay or kernel. Step 3.
  |     no  --> bench-gadget status: is it bound?
  |               no  --> run bench-gadget up and read the refusal
  |               yes --> the cable. A charge-only cable has no D+/D-
  |                       and looks exactly like this.
  |
  the host sees a device but one function is missing
  |
  +-- count bEndpointAddress in lsusb -v
        6 not 7 --> one function did not bind. dmesg on the Pi names it.
        7        --> the function is there and the host has no driver.
                     On Windows that is ECM: rebuild with NET=ncm.
  |
  the keyboard types on the Pi instead of the host
  |
  +-- systemctl status kbd-bridge: is it running?
        no  --> the udev rule did not match. Step 6.
        yes --> it grabbed a DIFFERENT keyboard than the one you are
                typing on. Check which: ls -l /dev/input/bench-kbd
```

---

Back to [DESIGN.md](DESIGN.md),
[DESCRIPTORS.md](DESCRIPTORS.md), or the
[project README](../README.md).
