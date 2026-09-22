# Project 14: the Pi as a USB gadget, Ethernet, serial and HID keyboard

**Board:** Raspberry Pi 4. **Theme:** the USB device model from the other
side: descriptors, the endpoint budget, `dwc2` in peripheral mode, and
`libcomposite` driven entirely through configfs.

**Read this paragraph first.** Every other project on this bench uses the
Pi as a USB **host**. This one turns it around. The Pi enumerates on a PC
as one composite device with a network adapter, a serial console and a
keyboard, and a daemon bridges the Pi's own keyboard to the host so the
board sits between a keyboard and a PC. The whole gadget is a shell
script and a systemd unit: no kernel module is written, because
`libcomposite` turns a directory tree into USB descriptors.

The Pi 4 is the only board in the inventory that can do this on an
external connector. Its USB-C port is wired to the SoC's own dual-role
`dwc2`; the USB-A ports sit behind a separate host-only controller.

## State

**Everything is written and nothing has been run.** No image has been
built, no board has enumerated, no key has crossed the cable. There are
no measurements in this README and the rows that will hold them say so.

What is proven today, on a laptop:

| Proven | How |
|---|---|
| The configfs tree is built in the right order, and `UDC` is written last | `tests/gadget-configfs-test.sh`, 51 assertions |
| `up` refuses without a controller, without a descriptor, and on a bad `NET`, naming what was wrong each time | the same suite |
| Teardown continues through failures, names what it could not remove, and reports `PARTIAL` | the same suite |
| The gadget MACs are locally administered | the same suite |
| The HID descriptor is exactly 63 octets and begins and ends correctly | the same suite, and again in the recipe at build time |
| Two of those guards fire when broken and go quiet when restored | each defect reintroduced and the suite rerun |
| `USB_DWC2` and `USB_CONFIGFS` are `=m` in the Pi 4 defconfig, and `=y` **is** reachable for both | `bcm2711_defconfig` and the Kconfig at `rpi-6.6.y` |
| Seven gadget symbols are promptless and cannot be set by a fragment | `drivers/usb/gadget/Kconfig` at `rpi-6.6.y` |
| `dwc2.dtbo` is already deployed by meta-raspberrypi | `rpi-base.inc` at scarthgap |
| `libevdev` is in oe-core, so no new layer is needed | `meta/recipes-support/libevdev` |
| The keycode to usage table matches the HID tables for six known keys | generated from `hid-input.c`, checked against the specification |

## The four findings worth carrying elsewhere

### 1. The same trap as Project 13, with the opposite answer

`CONFIG_USB_DWC2=m` and `CONFIG_USB_CONFIGFS=m` in `bcm2711_defconfig`,
and `bench-image` is built on `core-image-minimal`, **which installs no
kernel modules**. Project 13 met this and had to answer it by installing
`kernel-modules`, because `DRM_VC4` depends on `SND`, which is itself a
module, so `=y` was unreachable.

Here it is reachable, and it was checked rather than assumed:

```
  config USB_DWC2      tristate   depends on USB || USB_GADGET   (USB=y)
  config USB_CONFIGFS  tristate   select USB_LIBCOMPOSITE        (USB_GADGET=y)
```

So this image builds them in and installs no modules at all. **Which way
a project solves it is decided by the Kconfig, not by preference**, and
these two came out differently for that reason.

### 2. Seven promptless symbols, up from Project 9's four

`USB_LIBCOMPOSITE`, `CONFIGFS_FS`, `USB_F_ECM`, `USB_F_NCM`,
`USB_F_ACM`, `USB_F_HID`, `USB_U_ETHER` and `USB_U_SERIAL` are all bare
`tristate` with no prompt string. A fragment asking for any of them is
legal, silent and useless. They are written in `gadget.cfg` as a
consequences block so `./go kconfig` checks them, never as requests.

### 3. The descriptor is assembled at build time, and its length asserted

The specification converts the annotated hex on the board with
`xxd -r -p`. BusyBox may not have `xxd`, and the failure would land at
the very last step of bringing the gadget up, after everything else
looked right.

So the recipe assembles it in a BitBake python task and **asserts 63
bytes**. A descriptor short or long by one octet is not a syntax error:
it is a tree the host parses differently, and the symptom is a keyboard
that enumerates cleanly and types nothing.

### 4. The usage table is generated, and the inversion is ambiguous

The kernel has the mapping in `hid-input.c` as `hid_keyboard[256]`,
indexed by HID usage. The bridge needs the inverse, and **the forward map
is not injective**: seven keycodes have more than one usage. The
generator resolves them by taking the lowest usage, which is what a real
keyboard sends, and **lists all seven collisions in the generated header**
so the choice is visible rather than silent.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/gadget.cfg` | `dwc2` and the configfs gadget interface built in, plus eight asserted consequences |
| `meta-bench/recipes-bench/bench-gadget/` | The configfs script, the unit, the annotated HID descriptor and the networkd file |
| `meta-bench/recipes-bench/bench-kbd-bridge/` | The bridge daemon, the generated usage table and its generator, the udev rule and the unit |
| `meta-bench/recipes-core/images/bench-gadget-image.bb` | The image, and the getty on the gadget's own serial port |
| `kas/bench-gadget.yml` | The overlay that makes the port a device port, and the clock cap |
| `projects/14-usb-gadget/host/` | The host side: a udev rule, a NetworkManager profile that refuses to become the default route, and what Windows does |
| `tests/gadget-configfs-test.sh` | 51 assertions, no board and no cable |

## Running it

On the **authoring laptop (Windows)**:

```bash
sh tests/gadget-configfs-test.sh
```

On the **build laptop (WSL)**, after checking the disk (about 25 GB; the
first build rebuilds the kernel):

```bash
./go gadget
```

```bash
./go flash /dev/sdX
```

On the **board over the picocom console**, on its own supply first:

```bash
bench-gadget status
```

The full sequence, including the order that matters when moving the cable
to the host, is in [docs/BRINGUP.md](docs/BRINGUP.md).

## Documents

| File | What |
|---|---|
| [docs/DESCRIPTORS.md](docs/DESCRIPTORS.md) | **The deliverable.** The endpoint budget written before the build, and what to check it against |
| [docs/DESIGN.md](docs/DESIGN.md) | The drawings, the ownership table, and the two deviations |
| [docs/BRINGUP.md](docs/BRINGUP.md) | First boot in order, including the point of no return for the keyboard |
| [host/windows/README.md](host/windows/README.md) | Which in-box drivers bind, and the one function Windows cannot use |
| [JOURNAL.md](JOURNAL.md) | What was decided and why |

## Acceptance criteria

Measured rows are blank until a board has produced them.

| # | Criterion | Kind | Status |
|---|---|---|---|
| 1 | `lsusb -v` shows `1d6b:0104`, one configuration, five interfaces, seven endpoints | measured | |
| 2 | The host gets a DHCP lease from 10.42.0.0/24 within 5 s, SSH works, `iperf3` exceeds 100 Mbit/s | measured | |
| 3 | A login prompt on the host's ACM port at 115200 with no host configuration | measured | |
| 4 | A key reaches the host within 20 ms, and no key is lost in a 1000-character test | measured | |
| 5 | A 200-character macro types correctly, capitals and symbols included | measured | see the layout note |
| 6 | Unplug and replug re-enumerates all three functions without a reboot | measured | |
| 7 | No undervoltage warnings in a 10 minute test with the keyboard attached | measured | |
| 8 | The endpoint budget is written before the build and checked after | configured | `docs/DESCRIPTORS.md`, written first |
| 9 | The gadget is torn down in the reverse order it was built | configured | verified by test, and proven by breaking it |
| 10 | The report descriptor is checked in as annotated hex, not a blob | configured | and its length asserted at build time |
| 11 | The usage table is generated from the kernel source, not typed | configured | generator shipped beside the header |
| 12 | Every other bench image is unaffected | configured | one `?= "0"` kernel switch, one kas file |

### Criterion 5 has a limit that is not a defect

The macro table is **US layout**. The gadget sends usages, not
characters, so a macro containing `z` types `y` on a host set to a Swiss
or German layout. That is how HID works and it cannot be fixed on the
device side without knowing the host's layout. The table says so where it
is defined, and the criterion is met for a host set to US.

## Going further

- **Add mass storage and watch the budget fail.** Two more endpoints
  against zero spare. Then drop ACM and make it work. The failure is the
  lesson and it is cheap to stage.
- **Read the LED report.** `read(2)` on `/dev/hidg0` returns the host's
  Caps Lock state; mirroring it to the physical keyboard's LED through
  `EV_LED` closes the loop.
- **Use the ACM port as Project 9's kgdb channel**, so one cable carries
  network, console and debugger.
- **A mouse function**, bridging a USB mouse through the keyboard's hub.
