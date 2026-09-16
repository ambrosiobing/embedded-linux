# Project 15: an LTE router with failover and GNSS

**Board:** Raspberry Pi 4. **Theme:** ModemManager, NetworkManager, QMI,
nftables, gpsd.

Cellular connectivity is where embedded Linux meets telecom, and it is the
part of the stack most engineers have only ever used through a vendor's
black-box script. This project replaces the script with the standard
components: the kernel's USB serial and QMI drivers, ModemManager as the
modem abstraction, NetworkManager as the policy engine that decides which
uplink carries the default route, and nftables for the packet path. Each is
an ordinary Linux service with a D-Bus interface and a command-line tool
that shows its state, so the debugging story is complete.

The failover is the point. A gateway with two uplinks is only useful if the
switch-over needs no human: the cable comes out, the bench keeps working
over LTE within seconds, and when the cable comes back the traffic moves
back without a reboot. Route metrics and NetworkManager's connectivity
check give you that with configuration alone. The watchdog is the last
resort, for the states a modem gets into on its own where only a power
cycle through the PWRKEY line helps.

Project 1 built the layer, the image and the SDK. This is the first project
to extend all three rather than only use them.

## State

**The router works.** On 15 September 2026, on a Raspberry Pi 4 with a
SIM7600E-H stacked on the header:

```
cdc-wdm0:gsm:connected:lte
wwan0        10.166.165.254/30
default via 10.166.165.253 dev wwan0 proto static metric 700
```

A live LTE bearer at the configured metric, packets flowing through it at
103 ms, the access point serving the bench LAN, the firewall loaded with
drop policies on input and forward, and the exporter publishing real signal
data. Full output in
[docs/evidence/first-bearer.txt](docs/evidence/first-bearer.txt).

It took two builds. The first one booted and had no bearer, and the reason
was not visible from any amount of testing without hardware:

1. Three kernel options in `router.cfg` that are not Kconfig symbols, caught
   by `./go kconfig` on the first build that compiled a kernel rather than
   taking one from sstate.
2. NetworkManager built without its `wwan` plugin, so `wwan0` was
   `unmanaged` and the `lte` profile bound to nothing.
3. NetworkManager built without `concheck`, so the connectivity check this
   project's failover depends on was not in the binary. That one fails
   silently and is why acceptance criterion 3 could never have passed.

What remains is bounded and named in the table below. The
[journal](JOURNAL.md) has the whole path in order, including four CI
failures, the bring-up traps, and an alarm about a USB device number that
turned out to be nothing.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-core/images/bench-router-image.bb` | The gateway image, from `bench-image` |
| `meta-bench/recipes-bench/bench-router/` | The profiles, the ruleset, DHCP, the ModemManager filter, udev names, first-boot provisioning |
| `meta-bench/recipes-bench/bench-lte/` | `lte-gpio`, `lte-watchdog`, `lte-exporter` and their units |
| `meta-bench/recipes-bench/bench-net-wifi/` | The wireless client half of the old `bench-provision`, split out so this image can leave it behind |
| `meta-bench/recipes-kernel/linux/files/router.cfg` | The opt-in kernel fragment: modem drivers and netfilter, built in |
| `kas/bench-router.yml` | `meta-networking`, the fragment switch, `bench-router-image` |
| `meta-bench/recipes-kernel/linux-firmware/` | A firmware package poky does not provide, for the second uplink's radio |
| `tests/lte-watchdog-test.sh` and three more | What can be proven without a modem |

## What a clone gives you

**No image is published.** `bench-router-image` has been built twice and
booted, and neither build is downloadable from here: this directory carries
the recipes, the programs, the tests and the evidence, and `.gitignore`
excludes `*.wic*` on purpose.

**If the software is what interests you, no modem is required.** Four test
suites run on any machine in seconds and are listed under
[what is tested without hardware](#what-is-tested-without-hardware): the
escalation ladder against stubbed `mmcli`, `ping`, `nmcli` and `lte-gpio`;
the exporter's Prometheus output with no modem present; the firewall's
invariants, which assert meaning rather than syntax, because `nft -c`
accepts an input chain with policy accept; and the provisioning parser
against the three ways a Windows text editor breaks a config file.
`lte-watchdog`, `lte-exporter`, `lte-gpio` and the ruleset all read on
their own, and [docs/DESIGN.md](docs/DESIGN.md) is the architecture,
including the ownership table saying which component owns which interface.

**If you want to boot it, expect a long build.** This image is not a small
delta on Project 1: it pulls in ModemManager, NetworkManager, nftables and
dnsmasq, and it compiles its own kernel because `router.cfg` builds the
modem and netfilter drivers in rather than as modules. Measured here, with
warm shared state from earlier builds: **178 min 30 s** for the first and
**58 min 11 s** for the second, 5822 and 5686 tasks, all succeeded. A host
with no shared state at all starts from Project 1's three hours and adds
these on top.

**The same board and the same HAT are still not enough.** The SIM, the APN
and the access point's passphrase are yours and are never in this
repository: they go into `router.conf` on the FAT boot partition after
flashing, which is [the bring-up notes](docs/BRINGUP.md). Two things in
this project are properties of a HAT revision rather than of a part, the
PWRKEY and FLIGHT GPIO offsets, and the watchdog's power-cycle rung stays
disabled behind `pwrkey_verified` until you have checked them against the
schematic. A wrong offset does not fail safely.

## Running it

```sh
./go check                     # about 2 minutes, no board and no modem
./go router                    # bench-router-image for the Raspberry Pi 4
./go flash /dev/sdX
# then write router.conf on the boot partition, see docs/BRINGUP.md
```

[docs/DESIGN.md](docs/DESIGN.md) is the methodology: the architecture, the
schematic, the bench layout, the watchdog state machine, the failover
sequence, and the table of who owns which interface. Read it before the
bring-up notes.

[docs/BRINGUP.md](docs/BRINGUP.md) is the board work, in order, including
the step that has to come before the watchdog is ever enabled.

[docs/usb-modes.md](docs/usb-modes.md) records the USB composition decision
with its trade-offs. [docs/failover-tests.md](docs/failover-tests.md) is
where the measured switch-over times go.

## What is in the image beyond Project 1, and why

`bench-image` is 112 packages. This is a considerably larger box, and the
rule from Project 1 still applies: every addition is justified in writing.

| Package | Why it is there | Cheaper alternative, and why not |
|---|---|---|
| `modemmanager` | The modem abstraction: registration, bearer, signal, location, all as D-Bus properties | A shell script driving AT commands. That is Project 16's subject and it gives up every one of those properties |
| `networkmanager` | The routing policy: metrics, autoconnect, the connectivity check | systemd-networkd has metrics but no connectivity check and no `gsm` device type |
| `libqmi` | `qmicli`, to ask the modem directly when ModemManager and the modem disagree | Nothing. On a box whose failure mode is "no network", a tool you have to download is no tool |
| `dnsmasq` | DHCP and DNS for the bench LAN | NetworkManager's shared mode, which also brings its own NAT rules and hides the packet path |
| `nftables` | The packet path, in one readable file | iptables, which is the legacy interface to the same kernel code |
| `bench-router` | Our configuration | |
| `bench-lte` | `lte-gpio`, the watchdog, the exporter | |
| `python3-core`, `python3-modules` | The watchdog and the exporter | Rewriting both in shell. Worth reconsidering once the size is measured; see below |
| `iproute2` | `ip route`, which the exporter reads to find the live uplink | |
| `iputils-ping` | The second half of the probe | |

Two of those deserve more than a line.

**Python.** It is the largest single addition and it exists for roughly 400
lines of script. `python3-modules` is pulled whole rather than as a measured
list of the modules these two programs import, because guessing at the
OpenEmbedded Python split and getting it wrong produces an image that boots
and a watchdog that dies on its first import. That is the worst of both
outcomes. The list should be trimmed with `oe-pkgdata-util` once an image
has been built, and the measured size belongs in the table below.

**The kernel.** The modem drivers and the netfilter stack are built in
rather than modular. See [DESIGN.md](docs/DESIGN.md#what-the-kernel-has-to-provide)
for the reasoning, which comes directly from Project 1's two rounds of
debugging a missing `brcmfmac` module.

| | First build | Second build |
|---|---|---|
| Packages | 220 | 226 |
| Image, compressed | 97 MB | **79 MB** |
| Written to the card | 305.8 MiB | **255.0 MiB** |
| Installed size | 237 MiB | not re-measured |
| Of which Python | 39 MiB, 16 percent | unchanged |
| Of which ICU, SpiderMonkey and NSS | 64 MiB, 27 percent | removed |
| Build time, warm sstate | 178 min 30 s | 58 min 11 s |
| Tasks | 5822, all succeeded | 5686, all succeeded |
| Kernel fragment reached the `.config` | No, three lines | **Yes, all 37 options** |

Six more packages and 18 MB less. Package count is a poor proxy for size:
five large ones left (polkit, `libmozjs-115`, `nss`, `nspr`, three `libicu*`)
and several small ones arrived (`networkmanager-wwan`, `usbutils`, `curl`,
`mobile-broadband-provider-info`, GnuTLS and its dependencies).

**The 64 MiB was nobody's decision, and `depends.dot` says whose fault it
was.** The chain is `polkit -> libmozjs-115 -> libicuuc74`, plus
`networkmanager-daemon -> nss`. polkit reached the build because
`kas/bench-router.yml` put `polkit` into `DISTRO_FEATURES` on a guess that
NetworkManager needed it, behind a comment stating it as fact. It does not:
polkit governs non-root D-Bus callers and every caller here is root. NSS is
NetworkManager's default crypto backend, and `PACKAGECONFIG[gnutls]` is a
smaller one. Both are changed in the tree; the next build should lose most
of that 64 MiB.

Python is the next 39 MiB, and it is `python3-modules` pulled whole: 57
packages including `python3-tkinter`, `python3-idle` and `python3-venv` on
a headless gateway, for two scripts that import five modules between them.
Trimming it needs `oe-pkgdata-util` against a built image, which now
exists.

Two of those 5822 tasks are worth a line of their own. `libnftnl` and
`intltool-native` both failed to fetch from their upstream homes,
`git.netfilter.org` and `launchpad.net`, and completed from Yocto's
mirrors. The build was never at risk, and it is the argument in
[09. Lifecycle](../../walkthrough/09-lifecycle.md) for archiving `DL_DIR`
turning up on the first build that needed those sources: they still existed
because somebody else had kept a copy.

## Acceptance criteria

The seven criteria the project was specified against, written out in full
below so that nothing outside this repository has to be consulted to judge
whether it is finished, with what has been shown so far against each. The
distinction between a proof and a plan is the whole point of keeping this
table: "configured" means a file says so, "measured" means a board did so.

| # | Criterion | State |
|---|---|---|
| 1 | `ip route` shows two defaults, the primary at metric 100 and wwan0 at 700 | **Half met, unblocked.** `wwan0` at 700 is live with packets flowing. The primary is now a USB wireless adapter on `wan0` at metric 100, standing in for the cable. Needs the third build |
| 2 | Losing the primary uplink loses at most 5 replies; the route returns within 90 s | **Unblocked.** A wireless uplink makes the disconnect a software event unless the home access point is powered off; both methods and what each proves are in [failover-tests.md](docs/failover-tests.md) |
| 3 | A dead upstream behind a live carrier is detected within two connectivity intervals | **Was impossible and nobody knew.** NetworkManager was built with `-Dconcheck=false`, so the check was not in the binary. Fixed, and unaffected by the uplink being wireless |
| 4 | `mmcli --location-get` reports a fix within 3 minutes, within 50 m | **Deferred**, with the reason in the table below |
| 5 | After `AT+CFUN=0` the watchdog restores a bearer within 4 minutes, and the counters show the levels | Unblocked by the bearer. Escalation tested against stubs; level 3 needs `pwrkey_verified` first, journal 21 |
| 6 | `curl http://10.20.0.1:9101/lte.prom` returns valid Prometheus text | **Met.** Real signal, one-hot state, and the live uplink. [first-bearer.txt](docs/evidence/first-bearer.txt) |
| 7 | No undervoltage during a 10 minute `iperf3` over LTE | Not measured, but registration produced no undervoltage and throttle flags `0` |

Proven on the board on 15 September 2026, in the first boot:

| Claim | Evidence |
|---|---|
| The kernel fragment reaches the hardware | `qmi_wwan` and `option` registered at 0.83 s and 0.94 s, before any module could load |
| The module presents the 9001 composition | `1e0e:9001`, `ttyUSB0..4`, `cdc-wdm0`, `wwan0`, with no `AT+CUSBPIDSWITCH` |
| The udev rules name the right ports | `/dev/lte-at -> ttyUSB2`, `/dev/lte-nmea -> ttyUSB1` |
| The strict ModemManager filter does not block the modem | `mmcli -L` lists it |
| The card carries the identity, the image the capability | The access point came up on the name and passphrase in `router.conf` |
| The LAN works | A laptop associated, took a DHCP lease and reached `10.20.0.1` over ssh |
| `lte-gpio` runs on target | `chip pinctrl-bcm2711, pwrkey offset 6, flight offset 4` |
| The header carries the modem's 2 A peaks | No undervoltage through registration, throttle flags `0` |
| Nothing fails at boot | `systemctl --failed` empty |

Three further criteria, added here and not part of the original seven,
because building the thing showed that a router without them is not a
router:

| # | Criterion | State |
|---|---|---|
| 8 | The input chain drops by default, so nothing on the box is exposed to the carrier | Asserted in `tests/bench-router-nftables-test.sh` |
| 9 | No credential is in the repository; the card carries SSID, passphrase and APN | Asserted in `tests/bench-router-setup-test.sh` |
| 10 | The GPIO offsets are configuration, not code, and are confirmed before the watchdog is enabled | Step 3 of [BRINGUP.md](docs/BRINGUP.md) |

## What is tested without hardware

| Check | Command | Covers |
|---|---|---|
| Escalation ladder | `sh tests/lte-watchdog-test.sh` | Level ordering, no skipped rungs, a success resets to zero, one PWRKEY press when the modem is gone and two when it is not, the counters |
| Metrics format | `sh tests/lte-exporter-test.sh` | Parsing `mmcli` and `ip route`, one-hot state, both uplinks always reported, no stale coordinates after a lost fix, valid Prometheus text |
| Firewall invariants | `sh tests/bench-router-nftables-test.sh` | Input policy drop, masquerade naming both uplinks, the MSS clamp, no port opened towards an uplink. Plus `nft -c` syntax where nft exists |
| Provisioning | `sh tests/bench-router-setup-test.sh` | CRLF, byte order mark, missing final newline, an ampersand and a slash in the passphrase, file modes, partial input refused |
| Compile | `./go check` | `lte-gpio` against the host libgpiod v2 with `-Werror`; both Python programs byte-compile |

What none of it proves: that `mmcli`, `nmcli` and `nft` behave the way the
stubs pretend. Only a board shows that, which is what the bring-up notes and
the measurement documents are for.

## Deferred, with reasons

| Item | Why | Where it goes |
|---|---|---|
| A GNSS fix, acceptance criterion 4 | The engine works and the software is written: `export_location` in `/etc/bench/lte.conf`, the exporter's `lte_gnss_*` metrics, and step 7 of the bring-up notes. What is missing is sky. This bench is an indoor desk, the antenna is an active patch that needs a window, and a first fix there takes one to three minutes and on a desk may never come. Deferring it is honest about the room rather than about the code | Attach the puck at a window and run the two commands in [BRINGUP.md](docs/BRINGUP.md) step 7. Nothing needs rebuilding |
| gpsd on the NMEA port | ModemManager's location API covers this project's need and the two cannot share the port | A stretch goal, and the natural pairing with `chrony` |
| The ModemManager D-Bus API in place of `mmcli` | `--output-keyvalue` is stable and needs nothing extra in the image. The D-Bus version also replaces polling with state-change signals, which is the real prize | After the first board run, and it is Project 12's technique |
| WireGuard following the default route | The one thing that makes a flow survive a failover, and independent of everything here | Stretch goal |
| The serial console on the header UART | Still unproven since Project 1, for want of a working USB/TTL cable | Blocks nothing here; step 9 of the bring-up notes needs it |
