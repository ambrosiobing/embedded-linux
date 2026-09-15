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

**The software is complete and the board work has not started.** Every
static check passes and every piece of logic that can be exercised without a
modem is tested. Nothing here has been near a SIM card. The acceptance
table below says which is which, and the [journal](JOURNAL.md) records the
decisions taken so far and the ones deliberately left until hardware
contradicts them.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-core/images/bench-router-image.bb` | The gateway image, from `bench-image` |
| `meta-bench/recipes-bench/bench-router/` | The profiles, the ruleset, DHCP, the ModemManager filter, udev names, first-boot provisioning |
| `meta-bench/recipes-bench/bench-lte/` | `lte-gpio`, `lte-watchdog`, `lte-exporter` and their units |
| `meta-bench/recipes-bench/bench-net-wifi/` | The wireless client half of the old `bench-provision`, split out so this image can leave it behind |
| `meta-bench/recipes-kernel/linux/files/router.cfg` | The opt-in kernel fragment: modem drivers and netfilter, built in |
| `kas/bench-router.yml` | `meta-networking`, the fragment switch, `bench-router-image` |
| `tests/lte-watchdog-test.sh` and three more | What can be proven without a modem |

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

| Measurement | Value |
|---|---|
| Packages in `bench-router-image` | not yet built |
| Rootfs size against `bench-image` | not yet built |
| Build time, cold and warm | not yet built |
| Boot time to a connected bearer | not yet measured |

## Acceptance criteria

The book's criteria, with what has been shown so far. The distinction
between a proof and a plan is the whole point of keeping this table.

| # | Criterion | State |
|---|---|---|
| 1 | `ip route` shows two defaults, eth0 at metric 100 and wwan0 at 700 | Configured, not observed |
| 2 | Pulling the cable loses at most 5 replies; the route returns within 90 s | Not measured. [failover-tests.md](docs/failover-tests.md) |
| 3 | A dead upstream behind a live cable is detected within two connectivity intervals | Not measured |
| 4 | `mmcli --location-get` reports a fix within 3 minutes, within 50 m | Not measured |
| 5 | After `AT+CFUN=0` the watchdog restores a bearer within 4 minutes, and the counters show the levels | Escalation logic tested against stubs; not run against a modem |
| 6 | `curl http://10.20.0.1:9101/lte.prom` returns valid Prometheus text | Format asserted in `tests/lte-exporter-test.sh`; endpoint not served yet |
| 7 | No undervoltage during a 10 minute `iperf3` over LTE | Not measured |

Beyond the book, three things this repository asserts and the book's
version does not:

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
| gpsd on the NMEA port | ModemManager's location API covers this project's need and the two cannot share the port | A stretch goal, and the natural pairing with `chrony` |
| The ModemManager D-Bus API in place of `mmcli` | `--output-keyvalue` is stable and needs nothing extra in the image. The D-Bus version also replaces polling with state-change signals, which is the real prize | After the first board run, and it is Project 12's technique |
| WireGuard following the default route | The one thing that makes a flow survive a failover, and independent of everything here | Stretch goal |
| The serial console on the header UART | Still unproven since Project 1, for want of a working USB/TTL cable | Blocks nothing here; step 9 of the bring-up notes needs it |
