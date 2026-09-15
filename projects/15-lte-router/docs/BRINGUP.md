# Bring-up, Project 15

From a flashed card to a gateway with two uplinks. Read
[DESIGN.md](DESIGN.md) first: this file assumes you know which component
owns what.

Steps 0 to 6 have been run on hardware, on 15 September 2026, across two
builds. Section 1a records what those runs contradicted, and the journal
has the whole path. Step 4a and the failover measurements need a third
build, because the second uplink they depend on is new: see section 10.
Where a step says "record this", it means write the answer into this file
or into the two measurement documents, because the second person to do it
will be you in a year.

## 0. Before power

| Check | Why |
|---|---|
| SIM inserted with the HAT unpowered | Hot-inserting a SIM is how a SIM slot dies |
| Both antennas on the right sockets | The GNSS one is the active patch with the magnet base. Swapping them costs an hour of "no fix" |
| Official 3 A supply, nothing else on USB | The module pulls close to 2 A during registration |
| The HAT is powered from the header only | Never the header and the micro-USB together |
| The jumper block matches the HAT schematic | Especially PWRKEY and FLIGHT. See below |

## 1. Write the card's identity

The image carries the capability to be a router. The card carries the
identity. After flashing, mount the FAT boot partition on any machine and
create `router.conf` next to `config.txt`:

```
AP_SSID=bench-lte
AP_PSK=at-least-eight-characters
APN=internet
PIN=1234                  optional, only if the SIM keeps its PIN
WAN_SSID=HomeNetwork      optional, the wireless uplink
WAN_PSK=...               optional, its passphrase
```

`PIN`, `WAN_SSID` and `WAN_PSK` are all optional. The last two are how this
bench gets a second uplink without an Ethernet cable: a USB wireless
adapter joins the network the cable would have reached, at metric 100, and
the LTE profile's 700 still loses to it. Both of that pair or neither.

The APN comes from the carrier and nowhere else. A wrong APN produces a
modem that registers and never connects, which reads exactly like an
antenna fault.

The file is read once at boot by `bench-router-setup`, which fills in the
two NetworkManager profiles that carry secrets and writes them mode 600.
Nothing in this repository ever holds a passphrase or an APN. The same
mechanism, and the same three Windows text traps, as Project 1's
`wifi.conf`: CRLF endings, a byte order mark and a missing final newline
are all handled, and all three are tested in
[`tests/bench-router-setup-test.sh`](../../../tests/bench-router-setup-test.sh).

To change the access point name later, edit the file and run
`bench-router-setup` again, then `nmcli con reload`.

## 1a. What the first bring-up got wrong, so you do not

Recorded from 15 September 2026. None of it is in the wiring table because
none of it is about wiring.

| Trap | What happens |
|---|---|
| Wiring 5 V, GND, TX and RX with jumpers instead of stacking | No USB, so no modem at all. The UART carries AT commands and nothing else. A single Dupont lead also drops too much voltage at the 2 A registration peak |
| Connecting the HAT's **USB UART** socket rather than its **USB** socket | You get a serial bridge chip, `10c4:ea60` or `1a86:7523`, instead of `1e0e:9001` |
| Connecting no USB cable at all | The module powers up, its PWR LED lights, and nothing appears on the bus. Power is not the data path |
| Expecting `wifi.conf` to work | It does nothing here. This image has no wireless client; `wlan0` is an access point and the file it reads is `router.conf` |
| Reading the USB device number as a fault | It counts every device on the bus and never reuses a number. Count enumerations over thirty seconds instead |
| Forgetting the display board's power | The DSI ribbon carries video and touch, not power, and the HAT has taken the header pins. Use the adapter board's micro-USB, ideally from its own charger |

## 2. Enumerate

```sh
lsusb | grep 1e0e                  # 1e0e:9001 SimTech, the default QMI mode
dmesg | grep -E 'option|qmi_wwan'  # ttyUSB0..4, cdc-wdm0, wwan0
ls -l /dev/ttyUSB* /dev/cdc-wdm0 /dev/lte-at /dev/lte-nmea
```

If the NET LED stays dark, press the PWRKEY button on the HAT once. Most
revisions start the module on their own.

`lte-at` and `lte-nmea` are the udev symlinks from
`77-sim7600.rules`. The numbers behind them are allocation order, which is
not a promise, and they move if the USB composition changes.

If there is no `wwan0` at all, the question is the same one Project 1
answered for `wlan0`: is the driver in the image. Here it is built into the
kernel rather than packaged as a module, so the answer should be yes, and
`zcat /proc/config.gz | grep QMI_WWAN` says so in one line.

## 3. Confirm PWRKEY and FLIGHT before trusting the watchdog

This is the step to do slowly, because getting it wrong drives an unknown
line on the header.

```sh
lte-gpio info                  # which chip, which offsets it resolved
gpioinfo | grep -E 'lte-gpio|GPIO[46]'
```

Check the two offsets against the HAT schematic, not against this
repository. If they differ, edit `/etc/bench/lte.conf`; nothing has to be
rebuilt. Then, with the module running:

```sh
systemctl stop lte-watchdog
lte-gpio pwrkey 3000           # a long press: the module should power off
lsusb | grep 1e0e              # gone
lte-gpio pwrkey 1200           # a short press: it should come back
```

Only after both directions work should level 3 be armed. Its recovery is
exactly the pair of presses above, and until you arm it the watchdog
refuses that rung, says so in the journal and counts it in
`lte_pwrkey_refused_total`:

```sh
sed -i 's/^pwrkey_verified = 0/pwrkey_verified = 1/' /etc/bench/lte.conf
systemctl restart lte-watchdog
```

Levels 1 and 2 work from first boot regardless, and between them they
handle almost everything. Only the rung that drives a header pin waits for
a human who has seen the schematic.

`lte-flight.service` holds FLIGHT inactive for as long as it runs. That is
the feature, not a leak: releasing the line returns it to an input, and the
HAT's pull-up then asserts flight mode. `systemctl status lte-flight` should
show it active, and `gpioinfo` should show the line consumed by
`lte-gpio-flight`.

## 4. Walk the modem up by hand, once

Do this once before trusting any service, so that the failure modes are
familiar.

```sh
mmcli -L                                  # the modem object path
mmcli -m any                              # state, operator, signal quality
mmcli -m any --signal-setup=10
sleep 12 && mmcli -m any --signal-get     # rsrp, rsrq, snr
mmcli -m any --3gpp-scan --timeout=120    # operators seen, for antenna placement
```

A SIM with a PIN needs it sent once through `mmcli`. On a headless router,
disable the PIN on the SIM instead: a box that needs a human after every
power cut is not a router.

Confirm the filter is doing its job:

```sh
mmcli -L                       # must list the USB modem and nothing else
ls -l /dev/serial0             # the header UART, which must not appear above
```

## 4a. The second uplink

Only if you are using the USB wireless adapter. The onboard radio is the
access point; this is a separate radio doing the opposite job.

```sh
ip -br link                    # wan0 should exist, renamed by udev
dmesg | grep -i rtl8xxxu       # driver bound, firmware loaded
nmcli -t -f DEVICE,TYPE,STATE,CONNECTION d
```

`wan0` rather than `wlan1` is deliberate: the two radios race for `wlan0`
and the access point profile names it. See
[`76-bench-uplink.rules`](../../../meta-bench/recipes-bench/bench-router/files/76-bench-uplink.rules)
and Decision 48.

If `wan0` is absent but `lsusb` shows the adapter, the two candidates are
the driver and the firmware, and `dmesg` distinguishes them: no `rtl8xxxu`
line at all means the module is missing, and a line asking for
`rtlwifi/rtl8192eu_nic.bin` means the firmware package is. Both are named
in the image recipe, for exactly the reason Project 1 learned on `wlan0`.

If it exists and does not associate, check the band. RTL8192EU is 2.4 GHz
only and cannot join a 5 GHz network.

## 5. The profiles and the routes

```sh
nmcli con show                 # eth0-uplink, wan-wifi, lte, bench-ap
nmcli general                  # connectivity: full
ip route                       # two defaults, metric 100 and metric 700
```

Two defaults with different metrics is the whole failover. Two defaults
with the same metric is a coin toss, and it is the mistake this project
exists to avoid making silently.

## 6. The LAN

```sh
systemctl status bench-router-nft bench-router-dhcp
nft list ruleset               # one table, three chains
sysctl net.ipv4.ip_forward     # 1
```

Join the access point with a phone, get an address from 10.20.0.50 upwards,
and ping through. `conntrack -L` while pinging shows the NAT entries.

The input chain has policy drop. If SSH over the cable stops working after
the ruleset loads, that is this file and not the network: the rule allowing
port 22 on `eth0` is one line in
[`nftables.conf`](../../../meta-bench/recipes-bench/bench-router/files/nftables.conf).

## 7. GNSS

Off by default, because the engine costs power and modem time.

```sh
mmcli -m any --location-enable-gps-nmea --location-enable-gps-raw
sleep 90 && mmcli -m any --location-get
```

Then set `export_location = 1` in `/etc/bench/lte.conf` so that the
exporter reports it.

A first fix with the antenna at a window takes one to three minutes. On a
desk, indoors, it may never come, and that is not a fault to debug.

The alternative is gpsd on `/dev/lte-nmea` with `AT+CGPS=1` on the AT port,
which is what mapping software and `chrony` expect. The two cannot share
the port. Pick ModemManager's API when the position goes into a service of
your own, which is a D-Bus property and Project 12's territory; pick gpsd
when other software consumes it.

## 8. The metrics

```sh
curl http://10.20.0.1:9101/lte.prom
curl http://10.20.0.1:9101/watchdog.prom
```

From a bench client, not from the Pi: the endpoint binds the access point
address on purpose, and the input chain drops 9101 from both uplinks.

`promtool check metrics < lte.prom` if you have it. The assertions that
matter are also in `tests/lte-exporter-test.sh`, which runs without a modem.

## 9. The UART, when USB has gone wrong

The fallback exists for one case: a wrong `AT+CUSBPIDSWITCH` that leaves the
module in a composition the host cannot use. Then the header UART still
answers.

Free the Pi UART from the console, set the HAT jumper to the Pi UART
position, and:

```sh
picocom -b 115200 /dev/serial0
AT
AT+CPIN?
AT+CUSBPIDSWITCH?
```

The bench image sets `CMDLINE_CONSOLE = "console=serial0,115200 console=tty1"`,
so the console is on that UART by default and has to be taken off it first.
Project 1 left the serial console unproven for want of a working USB/TTL
cable; that debt is still open and it is the reason this step is last.

## Pitfalls, in the order they usually happen

| Symptom | Cause |
|---|---|
| ModemManager sends AT into the console | The strict filter is missing. `ModemManager.conf` plus `ID_MM_PORT_IGNORE` |
| `dhclient wwan0` finds nothing | `qmi_wwan` is raw IP. ModemManager configures the address. Never add a DHCP profile there |
| `registered`, never `connected` | An APN typo. Check that before the antenna |
| Failover is random | Two default routes with the same metric |
| No GNSS fix anywhere | The antennas are swapped |
| A power cycle turns the modem on and off | PWRKEY toggles. The watchdog checks `mmcli -L` first for exactly this |
| The radio is in flight mode after boot | FLIGHT floating on a pull-up. `lte-flight.service` holds it |
| Clients connect, then large downloads stall | The MSS clamp. It is one line in the ruleset and one kernel option behind it |

## 10. The third build, for the second uplink

The first build had no bearer and the second one does. What the second one
does not have is a second uplink, which is what criteria 1, 2 and 3 need,
so there is one more rebuild:

```sh
./go router
./go ksym -f router
./go kconfig -f router "$(find ~/bench/build/tmp/work -path '*linux-raspberrypi*' -name .config | head -1)"
./go flash /dev/sdX
```

| Change | Where | Why a rebuild |
|---|---|---|
| `CONFIG_RTL8XXXU=m` | `router.cfg` | A kernel module is in the kernel or it is not |
| `linux-firmware-rtl8192eu`, a package this layer creates | new `linux-firmware_%.bbappend` | poky ships no package for `rtlwifi/rtl8192eu_nic.bin`. Decision 47 |
| `kernel-module-rtl8xxxu`, `linux-firmware-rtl8192eu` | `bench-router-image.bb` | Driver and firmware are separate packages and both have to be named |
| `76-bench-uplink.rules`, renaming the adapter to `wan0` | `bench-router` | Two radios race for `wlan0`. Decision 48 |
| `wan-wifi.nmconnection.in`, a client profile at metric 100 | `bench-router` | |
| `WAN_SSID` and `WAN_PSK` in `router.conf` | `bench-router-setup` | |
| Three uplinks in the forward and masquerade lists, ssh in on `wan0` | `nftables.conf` | Without `wan0` in the masquerade list, a failover moves the route and the packets are then dropped on the way out |
| `uplinks = eth0 wan0 wwan0` | `lte.conf` | So the exporter reports which of the three holds the route |

When you rewrite `router.conf` after flashing, add the two new keys:

```
WAN_SSID=YourHomeNetwork
WAN_PSK=its-passphrase
```

Then `ip route` should finally show what this project is about: two default
routes, the wireless uplink at metric 100 and the modem at 700, with the
kernel sending everything through the first while it works.
