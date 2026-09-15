# Bring-up: from a flashed card to a 24 hour run

In order, because every step depends on the one before it and because a
fault found at step 7 that was introduced at step 2 costs an evening.

Nothing below has been performed. It is the plan, written alongside the
code, and it will be corrected in the [journal](../JOURNAL.md) the first
time it meets hardware.

## 0. The peripheral first, on its own

Before the Pi is powered, prove that the STWIN.box advertises.

1. Flash the BLE sensor demonstration firmware with STM32CubeProgrammer
   through the STLINK-V3MINI from the kit.
2. Open ST's BLE Sensor app on a phone and confirm the board appears and
   streams.
3. Close the app.

Step 3 is not optional. **Two centrals cannot both be connected to the demo
firmware**, and a phone left connected in a pocket produces a Pi-side
connection that succeeds about every second attempt. That is a fault which
looks like a radio problem, a driver problem, or a bleak problem, and is
none of them.

Start with the plain sensor demo rather than FP-SNS-DATALOG2. DATALOG2
speaks BlueST v2, which needs a command written to a command
characteristic before anything streams, and debugging silence is harder
than debugging wrong numbers.

## 1. hci0 has to exist before anything else

Flash `bench-ble-image`, boot with the console attached, and stop at the
first thing that fails.

```sh
dmesg | grep -i -e bluetooth -e bcm
systemctl status bthelper@hci0 hciuart bluetooth
hciconfig -a                 # hci0: Type: Primary  Bus: UART, UP RUNNING
bluetoothctl show            # Powered: yes, and the LE UUIDs
```

The order those fail in tells you where to look:

| Symptom | Cause |
|---|---|
| No `hci0` at all, and `dmesg` has no `hci_uart` line | The kernel fragment did not arrive. Check with `./go kconfig -f ble` against `/proc/config.gz` |
| `hci_uart` registered, `hciattach` times out, no `UP RUNNING` | The firmware is missing. `ls /lib/firmware/brcm/BCM4345C0.hcd`; it comes from `bluez-firmware-rpidistro-bcm4345c0-hcd` and from no other package |
| `hciuart.service` fails calling `hciconfig` | `hciconfig` is a deprecated tool and is present only because poky's default `PACKAGECONFIG` for bluez5 includes `deprecated`. If a release drops it, this is where it shows |
| `hci0` exists but `Powered: no` | `AutoEnable = true` did not take. Check `/etc/bluetooth/main.conf` exists at all: poky's bluez5 does not ship one, and this image's copy comes from the layer's bbappend |

**The console is on the mini UART.** If it is garbled, that is `enable_uart`
rather than the cable: see the UART section of
[DESIGN.md](DESIGN.md#the-uart-that-is-not-free) before suspecting
hardware.

## 2. Everything by hand, before any automation

Every D-Bus call the gateway makes, made by a person first, with a trace
running. In one terminal:

```sh
btmon -w /var/lib/stwin-gw/first-connect.btsnoop
```

In another:

```sh
bluetoothctl
[bluetooth]# menu scan
[bluetooth]# transport le
[bluetooth]# back
[bluetooth]# scan on
# note the address advertising BlueST manufacturer data
[bluetooth]# scan off
[bluetooth]# connect C0:XX:XX:XX:XX:XX
[STWIN]# info                     # RSSI, UUIDs, ServicesResolved
[STWIN]# menu gatt
[STWIN]# list-attributes
[STWIN]# select-attribute 00e00000-0001-11e2-9e96-0002a5d5c51b
[STWIN]# notify on
# "Value: 0x..." lines appear
[STWIN]# notify off
[STWIN]# back
[STWIN]# disconnect
```

Copy the trace to the host and open it in Wireshark. Find three things,
because they are the three the sequence diagram claims:

1. `LE Create Connection`
2. `ATT Write Request` to the client characteristic configuration
   descriptor, value `0x0001`
3. the first `ATT Handle Value Notification`

That trace is the ground truth for everything else in this project, and it
is what [PROTOCOL.md](PROTOCOL.md#confirming-this-against-a-trace) asks for
to turn the field table from a claim into a measurement. Do that now, while
the trace is open: check one frame length and one physical value, and put
the real bytes into `tests/stwin-bluest-test.sh`.

### If `Connect` fails with `Insufficient Authentication`

The firmware wants encryption. Once, in `bluetoothctl`:

```sh
agent NoInputNoOutput
default-agent
pair C0:XX:XX:XX:XX:XX
trust C0:XX:XX:XX:XX:XX
```

The keys live in `/var/lib/bluetooth/<adapter>/<device>/info` and survive
reboots. Nothing in the gateway changes.

### If the attribute table looks wrong after a firmware change

`bluetoothd` caches GATT databases per device. After reflashing the
peripheral the cached table is stale, `ServicesResolved` becomes true
against attributes that no longer exist, and the symptom is a subscription
that succeeds and delivers nothing.

```sh
bluetoothctl remove C0:XX:XX:XX:XX:XX
```

## 3. The gateway, in the foreground, with nothing else on

```sh
systemctl stop stwin-gw
stwin-gw --scan-only --scan-timeout 15
```

That prints one line per device with its RSSI and exits. It is the fastest
way to confirm the radio works and to find the address without
`bluetoothctl`.

Then the real thing, still in the foreground, still without LEDs or a
broker:

```sh
stwin-gw --mac C0:XX:XX:XX:XX:XX --no-csv --log-level debug --rounds 1
```

`--rounds 1` runs one pass of the ladder and stops, so a mistake costs one
cycle rather than a reconnect loop that has to be interrupted.

Then add the sinks one at a time, in this order, because each can fail on
its own and a failure of any of them is survivable by design:

```sh
stwin-gw --mac C0:... --broker ""                       # CSV only
stwin-gw --mac C0:... --broker localhost                # CSV and MQTT
stwin-gw --mac C0:... --broker localhost --leds         # all three
```

In another terminal:

```sh
mosquitto_sub -h localhost -t 'bench/stwin/#' -v
tail -f /var/lib/stwin-gw/*.csv
```

## 4. The service

```sh
vi /etc/bench/stwin.conf          # STWIN_MAC, STWIN_LEDS=1
systemctl restart stwin-gw
journalctl -u stwin-gw -f
systemd-analyze security stwin-gw
```

The last one is an acceptance criterion and asks for a score below 5. If it
is higher, the output names the line that is missing; the unit has a
comment for every hardening directive in it, including the one that is
deliberately absent.

**The group that is not there.** If the unit fails to start with a message
about resolving a group, that is `SupplementaryGroups`. This image has a
`gpio` group, created by the recipe, and no `bluetooth` group, because
upstream BlueZ's D-Bus policy allows any user to talk to `org.bluez` and
the group every tutorial names comes from Debian's patched copy of that
policy file.

## 5. The measurements

Four numbers, and they belong in the README rather than in a terminal
scrollback.

**Notification rate.** Frames per second per characteristic, and the gap
statistics between consecutive `dev_ts` values. Compare with the connection
interval negotiated in the trace, which is in the L2CAP connection
parameter update, not in `main.conf`: what is in `main.conf` is what the
central proposed.

```sh
awk -F, 'NR>1 {n++} END {print n/60, "frames per second"}' \
    /var/lib/stwin-gw/$(date -u +%Y%m%d)-00e00000.csv
```

**RSSI against distance.** Walk the peripheral away with
`--scan-only` running, and note the RSSI at which the link stops coming
back. Remember that the number is from advertisements: BlueZ does not
refresh the `RSSI` property while a device is connected, and reading a
live connection's RSSI needs an HCI command that BlueZ does not expose on
D-Bus. The README says that rather than presenting a stale number as a
live one.

**The battery test.** This is the one worth timing with a stopwatch.

| Step | Expect |
|---|---|
| Remove the cell while streaming | green goes out, red within the supervision timeout plus about a second |
| Wait | red stays on, the delay in the journal doubles: 1, 2, 4, 8, 16, 30 |
| Replace the cell | yellow, then green, within 30 s |
| `journalctl -u stwin-gw` | no `Started` line: the service never restarted |

That last row is the point of the whole supervisor. A gateway that
recovers by having systemd restart it also loses its MQTT session, its open
files and its counters, and it hides the fault from anyone reading the
journal later.

**Twenty-four hours.** Leave it running.

```sh
systemctl show stwin-gw -p MemoryCurrent      # at the start
# ... a day later
systemctl show stwin-gw -p MemoryCurrent      # and at the end
systemctl show stwin-gw -p NRestarts          # 0
```

A resident set that grows over a day is the thing this test exists to find,
and the usual cause in a program like this is a list that is appended to
and never read.

---

Back to the [project README](../README.md), the [design](DESIGN.md) or the
[protocol](PROTOCOL.md).
