# embedded-linux-bench

Twenty embedded Linux projects on one bench, in one repository. They share a
Yocto layer, a cross SDK, a set of boards and a single entry point, because
they are one body of work rather than twenty unrelated demos.

Project 1 builds the foundation the rest stand on: an image built entirely
from source, a layer that later projects extend, and an SDK that
cross-compiles their code against the exact sysroot on the target.

```sh
./go                 # the task list
./go setup           # prepare a Linux or WSL2 build host
./go check           # everything provable without a board, about 2 minutes
./go build           # bench-image for the Raspberry Pi 4
```

## Why it is built this way

[walkthrough/](walkthrough) explains the reasoning end to end: what
embedded Linux is and what these projects are for, why Yocto rather than
Buildroot, what BitBake does during those three hours, how a layer is put
together, why the status daemon is two programs, what each check proves and
what it cannot, and where every piece belongs across a product lifecycle
from first bring-up to a version still being patched years later. It ends
with a decision log, each entry naming the alternative that was rejected.

It is written so that it applies to the other nineteen projects, not only
to this one.

## Why one repository

The twenty projects are not independent. Project 5 writes a kernel driver
that Project 10 then exercises; Projects 11 and 12 cross-compile with the
SDK that Project 1 produces; Projects 5, 6 and 19 want the identical rootfs
on a different board. Twenty repositories would mean twenty copies of the
same layer pins, and a reader would have to reconstruct the order.

So the layer is shared and the projects are directories inside it:

```
embedded-linux-bench/
  meta-bench/          the Yocto layer every project extends
    conf/layer.conf
    recipes-core/images/       bench-image and its variants
    recipes-bench/             applications, one directory per program
    recipes-kernel/linux/      kernel configuration fragments
  kas/                 build configurations: machine, distro, layer pins
  projects/
    01-yocto-image/    what each project adds, how to run it, its evidence
  sdk/                 programs that prove the cross SDK works
  scripts/             build, flash, SDK, reproducibility, checks
  tests/               what can be tested without hardware
  docs/                bench-wide notes
  go                   one entry point
```

Recipes live in the layer because Yocto requires it. Everything that is not
a recipe, the narrative, the wiring, the measurements and the evidence,
lives under `projects/NN-slug/`, so each project reads as a unit while the
build stays a single coherent tree.

## The twenty projects

| # | Project | Board | Theme | State |
|---|---|---|---|---|
| 01 | [A Yocto image that owns the whole stack](projects/01-yocto-image) | Raspberry Pi 4 | Build systems, layers, recipes, SDK | **Complete**: built, booted, reproducible, SDK verified on the board |
| 02 | NanoPi NEO Air on mainline: U-Boot, kernel, device tree, eMMC | NanoPi NEO Air | Board bring-up, bootloader, sunxi mainline | Planned |
| 03 | Boot time and energy per boot, measured | NanoPi NEO Air + PPK2 | Boot-time optimisation, systemd-analyze, power | Planned |
| 04 | A network-boot hardware-in-the-loop lab | Pi 4 server + Pi 3B+ DUT | TFTP/NFS root, udev, serial consoles, automated tests | Planned |
| 05 | An IIO driver for the ADXL345 written from scratch | Raspberry Pi 3 | Kernel driver model, regmap, threaded IRQ, IIO events | Planned |
| 06 | Explorer 700: every peripheral in one device-tree overlay | Raspberry Pi 3 | Device tree composition, sysfs, hwmon, rtc, w1, input | Planned |
| 07 | A 3.5 inch SPI display as a DRM panel with touch | Raspberry Pi 3B+ | DRM/KMS tiny drivers, input subsystem, fbcon | Planned |
| 08 | PREEMPT_RT latency lab with the MCC 118 as instrument | Raspberry Pi 4 | Real-time kernel, cyclictest, IRQ affinity, jitter | Planned |
| 09 | Kernel debugging lab: kgdb, ftrace, perf, pstore | Raspberry Pi 3B+ | Debugging and tracing over the serial console | Planned |
| 10 | IIO in depth with the X-NUCLEO-IKS4A1 | Raspberry Pi 3B+ | IIO buffers and triggers, libiio, iiod, AHRS | Planned |
| 11 | VL53L8CX: porting and packaging a vendor userspace driver | Raspberry Pi 4 | i2c-dev and spidev, shared libraries, packaging | Planned |
| 12 | A sensor-hub D-Bus service over UART | Raspberry Pi 4 | CBOR wire protocols, sd-bus, polkit, socket activation | Planned |
| 13 | A Wayland kiosk HMI on the 7 inch touchscreen | Raspberry Pi 4 | DRM/KMS, Wayland, libinput, LVGL or Qt | Planned |
| 14 | The Pi as a USB gadget: Ethernet, serial and HID | Raspberry Pi 4 | USB gadget configfs, libcomposite, evdev to HID | Planned |
| 15 | An LTE router with failover and GNSS | Raspberry Pi 4 | ModemManager, NetworkManager, QMI, nftables, gpsd | Planned |
| 16 | A low-power Cat-M and NB-IoT tracker | Raspberry Pi 3 | AT state machines, CoAP/LwM2M, PSM/eDRX, current budget | Planned |
| 17 | A BLE gateway for the STWIN.box with BlueZ | Raspberry Pi 3B+ | BLE central on Linux, BlueZ D-Bus GATT, pipelines | Planned |
| 18 | Edge Wi-Fi access point with MQTT over TLS and a private PKI | Raspberry Pi 3 | hostapd, dnsmasq, Mosquitto, X.509 | Planned |
| 19 | A/B updates with RAUC, a watchdog and a read-only rootfs | Raspberry Pi 3 | OTA, U-Boot bootcount, overlayfs, dm-verity | Planned |
| 20 | OP-TEE on the Pi 3: a trusted application for key storage | Raspberry Pi 3 | TrustZone, OP-TEE OS, TEE Client API, secure storage | Planned |

## Building

Every build configuration is a kas file, and every external layer is pinned
there. Moving to the next Yocto LTS means editing three branch names in one
file.

| Command | Configuration | Result |
|---|---|---|
| `./go build` | `kas/bench-rpi4.yml` | `bench-image` for `raspberrypi4-64` |
| `./go rpi3` | `kas/bench-rpi3.yml` | The same image for `raspberrypi3-64` |
| `./go dev` | `kas/bench-dev.yml` | `bench-image-dev`, with gdbserver and perf |
| `./go release` | `kas/bench-release.yml` | The same image plus an SPDX bill of materials, a CVE report and the corresponding source archive |

Later projects that need a different kernel or a different image add their
own kas file next to these rather than changing the shared one. Project 8
will do exactly that for `PREEMPT_RT`.

The build host needs a case-sensitive file system and about 60 GB. The
scripts check both and refuse to start otherwise, because finding out three
hours into a build is expensive.

[docs/BUILD-HOST.md](docs/BUILD-HOST.md) covers the host in full, including a
table of every package `./go setup` installs and why each one is needed.

## What this image assumes about the bench

These are choices about one workshop, not defaults anyone should inherit
silently. Each is one line, and each says where to change it.

| Assumption | Why | Where it is set |
|---|---|---|
| The console is the official 7 inch DSI panel | This bench has no micro-HDMI adapter and its USB/TTL cable is obsolete | `RPI_EXTRA_CONFIG` and `CMDLINE_CONSOLE` in `kas/bench-rpi4.yml` |
| The console keymap is German | The boards are used with a German keyboard, and a US map makes a shell unusable | `vconsole.conf` in `meta-bench/recipes-bench/bench-provision/files/` |
| Networking is wireless | There is no wired network within reach of the bench | `bench-provision`, plus the firmware named in `bench-image.bb` |
| The Pi 4 radio firmware is proprietary | The radio does not initialise without it | `LICENSE_FLAGS_ACCEPTED` in `kas/bench-rpi4.yml` |
| Root has no password | `debug-tweaks`, right for an isolated bench and wrong for anything else | `IMAGE_FEATURES` in `bench-image.bb` |

**Wired networking needs no changes at all.** The image already runs DHCP on
`eth*` and an SSH server, so a board with a cable gets an address and accepts
`ssh root@...` out of the box. The wireless support exists because this
bench has no cable, not because it is better.

**WiFi credentials are never in this repository.** The image carries the
capability to join a network; the card carries the identity. A first-boot
service reads `SSID` and `PSK` from `wifi.conf` on the FAT boot partition,
which you write after flashing with any text editor. See
[the bring-up notes](projects/01-yocto-image/docs/BRINGUP.md).

## What is tested without hardware

Most of a Yocto project cannot be tested on a laptop, but the parts that
usually break can be:

| Check | Command | Covers |
|---|---|---|
| Static layer checks | `./go lint` | Files in `SRC_URI` that are missing, units in `SYSTEMD_SERVICE` that are never installed, layer.conf completeness, ASCII and line length |
| State machine | `sh tests/bench-state-test.sh` | The status logic, against a fake `systemctl` |
| WiFi provisioning | `sh tests/bench-wifi-setup-test.sh` | Credentials parsed from a file written on Windows, including CRLF endings, missing fields and file permissions |
| Host compile | `./go check` | The application built with `-Werror` against the host libgpiod v2, the same API the target uses |

CI runs all of these on every push, on a pinned `ubuntu-24.04` runner
with libgpiod v2 built from a named tag, because no Ubuntu LTS image
packages v2 and an unpinned runner is a moving dependency like any
other. It does not build the image: that needs a
self-hosted runner with a shared sstate mirror, which is an opt-in job.

## Licence

MIT. See [LICENSE](LICENSE).
