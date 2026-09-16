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

## What a clone gives you

**Source, not images.** Nothing flashable is published here. There are no
release assets, and `.gitignore` excludes `*.wic`, `*.wic.bz2` and
`*.wic.bmap` deliberately, so `./go flash` on a fresh clone looks into a
build tree that does not exist yet and refuses rather than writing
something wrong to a card.

**If you are interested in the software, you need no hardware and no
build.** `./go check` runs everything provable without a board in about two
minutes: both C programs compiled with `-Werror` against libgpiod v2, both
Python programs byte-compiled, the static layer checks and every suite in
`tests/`. CI runs the same set on every push. The applications, the
recipes, the kernel fragments, the systemd units, the test suites and the
whole `walkthrough/` read on any machine.

**If you want a card that boots, you build one.** That is the honest cost
and it is not a first-run penalty: Project 1's first build succeeded, 5095
tasks, no failures, in **194 minutes** on eight cores, plus about 10 GB of
downloads. A second build with nothing changed is **21 seconds** from
shared state, and a one-recipe change is under three minutes. The three
hours are a cross toolchain, glibc and a kernel compiled from source, and
no amount of fixing this repository makes them shorter.

**An identical board is not sufficient on its own.** These images are built
for one bench and the assumptions are listed under
[what this image assumes](#what-this-image-assumes-about-the-bench): the
console is a 7 inch DSI panel, the console keymap is German, networking is
wireless because no cable reaches the bench, and `debug-tweaks` leaves root
without a password. Each row says where to change it. No credential is ever
in this repository; SSIDs, passphrases and APNs are written to the FAT boot
partition after flashing.

**Why an image is not offered for download.** Two reasons, both
substantive. The image has passwordless root, which is correct for an
isolated bench and wrong on anyone else's network. And distributing a
binary attaches a corresponding-source obligation that building it yourself
does not; `./go release` exists to produce the licence manifest, the SPDX
SBOM and the source archive that a published image would have to carry. If
that changes, those four artefacts ship together or not at all.

What is offered instead is the reproducibility claim, stated narrowly and
backed by evidence: a clean build from the same commit produces the same
package list. `./go reproduce` checks it with its own separate sstate
cache, so it genuinely rebuilds and costs about as long as the first build
again. Project 1's result is 95 packages and 95 packages, identical.

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
    15-lte-router/
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

## How each project is written

**Every project is self-contained.** Nothing here cites a document that is
not in this repository. There is no companion text to fetch, no figure to
look up elsewhere and no acceptance criterion you have to take on trust:
what a project was asked to do is written out where the project is, in
words, and a reader who arrives at this URL with no other context can read
it end to end and judge it.

That rule shapes what each `projects/NN-slug/` directory contains, and the
same four files are expected of all twenty:

| File | What it holds |
|---|---|
| `README.md` | What the project is, what it adds to the layer, how to run it, its acceptance criteria written out in full, and what was measured against each |
| `docs/DESIGN.md` | The methodology before the results: system architecture, the wiring and its pin table, the bench layout, and the software's structure, all drawn as ASCII or mermaid so they diff and grep |
| `JOURNAL.md` | What actually happened in order, failures included. Each entry says what happened, what was done, and why that rather than the alternative |
| `docs/evidence/` | The raw output behind every number claimed: build logs, boot timings, package manifests, reproducibility diffs |

Choices that outlive one project go in
[walkthrough/DECISIONS.md](walkthrough/DECISIONS.md) instead, each entry
naming the alternative that was rejected. Where a project departs from what
it was originally scoped to do, it says what the difference is and why,
rather than pointing at where the original lives.

## The twenty projects

| # | Project | Board | Theme | State |
|---|---|---|---|---|
| 01 | [A Yocto image that owns the whole stack](projects/01-yocto-image) | Raspberry Pi 4 | Build systems, layers, recipes, SDK | **Complete**: built, booted, reproducible, SDK verified on the board |
| 02 | NanoPi NEO Air on mainline: U-Boot, kernel, device tree, eMMC | NanoPi NEO Air | Board bring-up, bootloader, sunxi mainline | Planned |
| 03 | Boot time and energy per boot, measured | NanoPi NEO Air + PPK2 | Boot-time optimisation, systemd-analyze, power | Planned |
| 04 | [A network-boot hardware-in-the-loop lab](projects/04-netboot-hil) | Pi 4 server + Pi 3B+ DUT | TFTP/NFS root, udev, serial consoles, automated tests | **Software complete**: server configuration, console framing, fixtures and the DUT image, with 47 assertions that need no boards. Nothing has netbooted yet |
| 05 | An IIO driver for the ADXL345 written from scratch | Raspberry Pi 3 | Kernel driver model, regmap, threaded IRQ, IIO events | Planned |
| 06 | Explorer 700: every peripheral in one device-tree overlay | Raspberry Pi 3 | Device tree composition, sysfs, hwmon, rtc, w1, input | Planned |
| 07 | A 3.5 inch SPI display as a DRM panel with touch | Raspberry Pi 3B+ | DRM/KMS tiny drivers, input subsystem, fbcon | Planned |
| 08 | [PREEMPT_RT latency lab with the MCC 118 as instrument](projects/08-preempt-rt) | Raspberry Pi 3B v1.2 | Real-time kernel, cyclictest, IRQ affinity, jitter | **Software complete**: RT kernel fragment, both instruments, the run protocol and three test suites; no board work yet |
| 09 | Kernel debugging lab: kgdb, ftrace, perf, pstore | Raspberry Pi 3B+ | Debugging and tracing over the serial console | Planned |
| 10 | IIO in depth with the X-NUCLEO-IKS4A1 | Raspberry Pi 3B+ | IIO buffers and triggers, libiio, iiod, AHRS | Planned |
| 11 | VL53L8CX: porting and packaging a vendor userspace driver | Raspberry Pi 4 | i2c-dev and spidev, shared libraries, packaging | Planned |
| 12 | [A sensor-hub D-Bus service over UART](projects/12-sensor-hub) | Raspberry Pi 4 | CBOR wire protocols, sd-bus, polkit, socket activation | **Linux side complete**: wire protocol, daemon, policy, activation, client and three test suites; firmware specified, no board work yet |
| 13 | A Wayland kiosk HMI on the 7 inch touchscreen | Raspberry Pi 4 | DRM/KMS, Wayland, libinput, LVGL or Qt | Planned |
| 14 | The Pi as a USB gadget: Ethernet, serial and HID | Raspberry Pi 4 | USB gadget configfs, libcomposite, evdev to HID | Planned |
| 15 | [An LTE router with failover and GNSS](projects/15-lte-router) | Raspberry Pi 4 | ModemManager, NetworkManager, QMI, nftables, gpsd | **Built and running on the board**: live LTE bearer at metric 700, NAT and DHCP for the bench LAN, a firewall that drops by default, metrics with real signal, and both uplink radios up. Failover timings are the measurement outstanding; GNSS is deferred, because the bench is an indoor desk and the antenna needs sky |
| 16 | A low-power Cat-M and NB-IoT tracker | Raspberry Pi 3 | AT state machines, CoAP/LwM2M, PSM/eDRX, current budget | Planned |
| 17 | [A BLE gateway for the STWIN.box with BlueZ](projects/17-ble-gateway) | Raspberry Pi 3B+ | BLE central on Linux, BlueZ D-Bus GATT, pipelines | **Software complete**: kernel fragment, BlueZ configuration, the gateway and three test suites; no board work yet |
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
| `./go router` | `kas/bench-router.yml` | `bench-router-image`, the gateway of Project 15: two uplinks, NAT, a cellular watchdog |
| `./go release` | `kas/bench-release.yml` | The same image plus an SPDX bill of materials, a CVE report and the corresponding source archive |
| `./go rt` | `kas/bench-rt.yml` | `bench-rt-image`, the latency lab of Project 8: a `PREEMPT_RT` kernel, cyclictest, stress-ng and an MCC 118 DAQ HAT |
| `./go ble` | `kas/bench-ble.yml` | `bench-ble-image`, the BLE gateway of Project 17: BlueZ, the radio firmware, a Python BLE client and a local broker |
| `./go hub` | `kas/bench-hub.yml` | `bench-hub-image`, the sensor hub of Project 12: the system bus, polkit, the D-Bus service and OpenOCD |

Later projects that need a different kernel or a different image add their
own kas file next to these rather than changing the shared one. Project 8
does exactly that for `PREEMPT_RT`, and it needs two lines rather than one:
the fragment switch, and a kernel new enough to have the symbol at all.
`arch/arm64` gained `ARCH_SUPPORTS_RT` in 6.12 and the BSP still defaults
to 6.6, so without the version pin the option is dropped without a word and
the image boots a kernel that is not preemptible.

The build host needs a case-sensitive file system and about 60 GB. The
scripts check both and refuse to start otherwise, because finding out three
hours into a build is expensive.

[docs/BUILD-HOST.md](docs/BUILD-HOST.md) covers the host in full, including a
table of every package `./go setup` installs and why each one is needed.

## Keeping a flashable copy

The build tree is disposable by design, which means the image in it is too:
`./go clean` deletes it, and so does anything else reclaiming disk. Losing
it costs nothing except the ability to put that exact state back on a card
without paying the hours again.

```sh
./go archive              # keep the image just built, with its provenance
./go archive router       # the same, for another configuration
./go archive list         # what has been kept, with board and commit
./go archive available    # what the build tree still holds, before it goes
./go flash /dev/sdX IMAGE.wic.bz2     # write a kept image back
```

The store is `~/bench/images` by default, outside the repository and beside
the caches, so it survives `./go clean`. Set `BENCH_IMAGE_DIR` to put it on
an external drive instead. Nothing in it is ever committed: these are build
outputs, and the compressed images are 48 to 79 MB each.

**Each saved image comes with a `PROVENANCE.txt`, and that is the point.**
An image on its own is a mystery card: it boots, and nothing about it says
which commit produced it, which layer revisions were pinned, or which board
it is for. The record carries the date, the kas configuration, the machine,
the commit, a `sha256` of each file, the command to flash it and the command
to rebuild it, and it says plainly when the working tree was dirty at build
time. `kas dump --lock` output is saved next to it, so the image can be
rebuilt rather than only re-flashed.

Archiving under a configuration you did not just build is refused rather
than filed, because the newest image in the tree may be for another board.
A Pi 4 image written to a card for a Pi 3 does not warn and does not boot:
the symptom is a dark board that reads as dead hardware.

## What this image assumes about the bench

These are choices about one workshop, not defaults anyone should inherit
silently. Each is one line, and each says where to change it.

| Assumption | Why | Where it is set |
|---|---|---|
| The console is the official 7 inch DSI panel | This bench has no micro-HDMI adapter and its USB/TTL cable is obsolete | `RPI_EXTRA_CONFIG` and `CMDLINE_CONSOLE` in `kas/bench-rpi4.yml` |
| The console keymap is German | The boards are used with a German keyboard, and a US map makes a shell unusable | `vconsole.conf` in `meta-bench/recipes-bench/bench-provision/files/` |
| Networking is wireless | There is no wired network within reach of the bench | `bench-net-wifi`, plus the firmware named in `bench-image.bb` |
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
| Router provisioning | `sh tests/bench-router-setup-test.sh` | The same three Windows text traps for the router's SSID, passphrase and APN, plus file modes and partial input |
| Cellular watchdog | `sh tests/lte-watchdog-test.sh` | The escalation ladder against stubbed `mmcli`, `ping`, `nmcli` and `lte-gpio` |
| Modem metrics | `sh tests/lte-exporter-test.sh` | Parsing and Prometheus text format, with no modem present |
| Firewall invariants | `sh tests/bench-router-nftables-test.sh` | Input policy drop, both uplinks masqueraded, the MSS clamp, no port opened towards an uplink |
| Edge timing arithmetic | `sh tests/rt-analyze-test.sh` | Project 8's period recovery, against a synthesised square wave with known edge times, in both edge regimes |
| Run protocol | `sh tests/rt-run-test.sh` | The measurement order, core confinement, the isolation claim in both directions, the throttle gate and every column of the results row |
| Interrupt affinity | `sh tests/rt-irq-affinity-test.sh` | Movable interrupts against kernel-owned ones, against a fake `/proc/irq` |
| Latency instrument comparison | `sh tests/rt-compare-test.sh` | Project 8's central claim, against a simulation: a constant GPIO write cost cancels in an interval measurement, and what survives is its variation |
| Kernel fragment symbols | `sh tests/kernel-symbols-test.sh` | That `./go ksym` tells a real Kconfig symbol from a line that names nothing, and a settable one from a symbol only the kernel can select |
| Wire protocol | `sh tests/sensorhub-proto-test.sh` | Project 12's frame format against frozen vectors, and a parser fed garbage, split frames, corrupted CRCs, absurd lengths and a lost byte |
| Protocol, two implementations | `sh tests/sensorhub-cabi-test.sh` | The C compiled and driven through ctypes, compared byte for byte against an independent Python implementation over 900 randomised cases |
| A D-Bus service's eight files | `sh tests/sensorhub-policy-test.sh` | Interface name, object path, polkit action, device path and unit name compared across the daemon, the bus policy, the activation file, the polkit action and rule, the udev rule, the unit and the recipe |
| BlueST protocol | `sh tests/stwin-bluest-test.sh` | Project 17's decoder: masks read from UUIDs, both frame shapes, and an unknown mask bit stopping the walk rather than shifting every field after it |
| BLE connection ladder | `sh tests/stwin-supervisor-test.sh` | Scan, connect, resolve, stream and back off, with a fake link that can fail at any step |
| Gateway sinks | `sh tests/stwin-sinks-test.sh` | CSV columns fixed by the feature mask, daily rollover, the MQTT topic and payload, one LED per state |
| Host compile | `./go check` | Four C programs built with `-Werror`: three against the host libgpiod v2, and the sensor hub daemon against libsystemd and libcbor, which is the only check anywhere that reads a D-Bus vtable. Every Python program byte-compiled |

CI runs all of these on every push, on a pinned `ubuntu-24.04` runner
with libgpiod v2 built from a named tag, because no Ubuntu LTS image
packages v2 and an unpinned runner is a moving dependency like any
other. It does not build the image: that needs a
self-hosted runner with a shared sstate mirror, which is an opt-in job.

## Licence

MIT. See [LICENSE](LICENSE).
