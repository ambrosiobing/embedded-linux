# Journal: Project 17

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 15 September 2026 unless noted.

---

## 1. Four packages decided whether this project was possible at all

**What happened.** The gateway is a Python program that needs a BLE client,
an MQTT client and GPIO bindings. On a distribution those are three `pip
install` lines. On a Yocto image there is no pip, so the first question was
not how to write it but whether it can exist.

**What was done.** `meta-openembedded/meta-python` on scarthgap was read
rather than hoped at, and it has all four:

```
python3-bleak_0.21.1.bb
python3-dbus-fast_2.21.1.bb        (what bleak uses underneath)
python3-paho-mqtt_2.0.0.bb
python3-gpiod_2.1.3.bb
```

The last one is a pleasant coincidence worth recording: 2.1.3 is exactly
the libgpiod version the C daemons in this layer are compiled against, so
the Python LEDs and the C LEDs speak to the same library.

**Why that and not the alternative.** The alternative was to design around
what might not exist: a C gateway on `sd-bus`, or a Python one shipped with
a vendored copy of its dependencies. Both are more work than reading a
directory listing, and one of them would have been wasted work. Checking
first also turned up the paho version, which decided a line of code, and
the bleak version, which decided a callback signature.

---

## 2. paho-mqtt 2.0 broke the spelling every example uses

**What happened.** `mqtt.Client(client_id)` is what every MQTT example
written before 2024 shows. meta-python ships paho-mqtt 2.0.0.

**What was done.** Read `client.py` at the v2.0.0 tag rather than trusting
memory:

```
731     callback_api_version: CallbackAPIVersion,     <- first positional
767     raise ValueError("Unsupported callback API version: version 2.0
        added a callback_api_version, see migrations.md for details")
```

So the sink constructs `mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
client_id=...)`, with the reason in a comment next to it.

**Why that and not the alternative.** `VERSION1` also exists and would let
the old callback shapes work. It is the compatibility shim, which means it
is the thing that will be removed, and this code has no callbacks to keep
compatible: it publishes and never subscribes. The failure without either
is a `ValueError` at construction time, which is at least loud, but it
happens on the board rather than here.

---

## 3. The radio firmware is a different package from the WiFi firmware

**What happened.** `bench-image` already installs
`linux-firmware-rpidistro-bcm43455`, which is the WiFi firmware for the
same chip. It seemed plausible that Bluetooth came with it.

**What was done.** poky's `linux-firmware_20240909.bb` was searched for the
Pi's Bluetooth patch RAM and does not have it: the only `.hcd` in the
recipe is `BCM-0bb4-0306.hcd`. The file the Pi 3B+ needs,
`BCM4345C0.hcd`, is in meta-raspberrypi's own
`bluez-firmware-rpidistro_git.bb`, which packages the Cypress blobs
RPi-Distro ships and upstream does not:

```
FILES:${PN}-bcm4345c0-hcd = "${nonarch_base_libdir}/firmware/brcm/BCM4345C0.hcd"
```

So `bluez-firmware-rpidistro-bcm4345c0-hcd` is in the image with a
paragraph next to it.

**Why that and not the alternative.** The alternative is to find out on the
board, where the symptom is an adapter that exists and an `hciattach` that
times out, and where the obvious suspects are the kernel fragment and the
UART overlay rather than a missing file. The CYW43455 has no flash: the
patch RAM is uploaded from the root filesystem on every single boot, so a
missing firmware file is not a degraded radio, it is no radio at all.

---

## 4. The bluetooth group does not exist, and adding it would break the unit

**What happened.** Every instruction for running a BLE program as a
non-root user says to add the user to the `bluetooth` group, and the
original scope for this project says the same.

**What was done.** Two things were read. First, upstream BlueZ's own D-Bus
policy, `src/bluetooth.conf` at 5.72, which ends:

```xml
<policy context="default">
  <allow send_destination="org.bluez"/>
</policy>
```

Any user may talk to `bluetoothd`. Second, poky's `bluez5.inc`, which
contains no `useradd` and no `GROUPADD_PARAM`, so no such group is created
on this image.

The group every tutorial names is Debian's patch to that policy file, where
the default context is restricted and a `bluetooth` group is punched
through instead. The unit therefore has no `SupplementaryGroups=bluetooth`,
and it has a comment saying why at more length than the line it replaces.

**Why that and not the alternative.** Copying the line would not have
tightened anything: the permission is already there. It would have stopped
the service from starting, because systemd cannot resolve a group that does
not exist, and the error would have pointed at Bluetooth rather than at a
missing entry in `/etc/group`.

---

## 5. The gpio group had to be created, or the hardening was decorative

**What happened.** Having established that no group is needed for
Bluetooth, the LEDs turned out to need one. `/dev/gpiochip0` on a Yocto
image is root-owned and mode 0600.

**What was done.** The recipe creates a `gpio` group, adds the service
user to it, and ships a udev rule:

```
SUBSYSTEM=="gpio", KERNEL=="gpiochip[0-9]*", GROUP="gpio", MODE="0660"
```

The unit then has `SupplementaryGroups=gpio`, `DevicePolicy=closed` and a
single `DeviceAllow=/dev/gpiochip0 rw`.

**Why that and not the alternative.** The alternative is `User=root`, which
is one line shorter and makes every other line in the unit pointless:
`NoNewPrivileges`, `ProtectSystem=strict` and a capability bounding set
that is already empty are all statements about what a non-root process may
not do. The acceptance criterion asks for a `systemd-analyze security`
score below 5, and a root service cannot reach it.

`PrivateDevices=yes` would have been the obvious hardening line and is
absent for a related reason: it gives the service an empty `/dev`, and the
LEDs live there.

---

## 6. The decoder stops at an unknown bit, and that is the whole design

**What happened.** The obvious decoder walks the fields it knows, skips the
mask bits it does not, and returns what it found. Writing the field table
made it clear why that cannot work.

**What was done.** BlueST frames have no length fields, no type tags and no
padding: the mask is the entire description of the payload, and fields sit
back to back from the highest bit to the lowest. So **the width of every
field is needed to locate the ones below it**. A bit the table does not
know makes every field after it unlocatable.

The decoder therefore walks all 32 bits rather than only the known ones,
and when it meets an unknown set bit it stops, keeps everything above it,
and marks the record:

```python
{'dev_ts': 0, 'acc': [1.0, 2.0, 3.0],
 'undecoded_mask': '00000100', 'undecoded': 'deadbeef'}
```

Those two keys are columns in the CSV and keys in the MQTT payload, so an
incomplete record is visibly incomplete wherever it lands.

**Why that and not the alternative.** Two alternatives were considered and
both are worse. Skipping unknown bits produces a full record of plausible
numbers read from the wrong offsets, and nothing downstream can tell it
from a good one. Raising on any unknown bit is safe but throws away
measurements that were located correctly, which matters because the most
likely unknown bit is a new low-order feature in a firmware update.

A short frame does still raise, and the distinction is deliberate: there
the peripheral and the table disagree about a field that is supposedly
known, which is a fault rather than a gap.

---

## 7. The LEDs went dark in a state nobody had listed

**What happened.** `tests/stwin-sinks-test.sh` asserts that every state the
supervisor can emit has a colour. It failed on the first run:

```
FAILED   state resolving lights the right line:
         wanted {5: False, 6: True, 13: False},
         got    {5: False, 6: False, 13: False}
```

**What was done.** `LED_FOR_STATE` was written from the four states in the
original state diagram, and the supervisor emits five: `resolving` sits
between Connecting and Streaming, because subscribing is what proves the
services resolved. The table gained the entry, and `STATES` in the same
module became the authoritative list that the test compares against, rather
than the handful of states the test happens to exercise.

**Why that and not the alternative.** The bug is small and the failure mode
is not: three dark LEDs mean "the service is not running", and this would
have shown exactly that for the seconds between Connected and the first
notification. On a bench that is a shrug; in the battery-removal test,
which is timed by watching the LEDs, it is a wrong measurement.

The alternative fix was to assert only the states the test uses, which
would have passed and would have left the next added state to fail the same
way silently.

---

## 8. The test hung, because a frozen clock cannot measure a timeout

**What happened.** `tests/stwin-supervisor-test.sh` ran for two minutes and
printed nothing.

**What was done.** The supervisor takes an injectable clock so that
timestamps are assertable, and the test supplies one that always returns
1000.0. The stall check asks "has it been quiet for longer than the
timeout", which against a clock that does not move is never true, so the
supervisor waited in 30-second steps forever. That one case now gets the
real `time.time`, with a short stall timeout, and the fake clock's
docstring says why it is the wrong clock for exactly one test.

**Why that and not the alternative.** Making the fake clock advance
automatically on every call would have fixed the hang and broken the
timestamp assertions, which are the reason it exists. Injecting time is
worth doing; injecting it into a test *about* time passing is not.

The second finding from the same run was cosmetic and worth fixing anyway:
the stall message used `%.0f`, so with a 0.05 s timeout it read "no frame
for 0 s, treating the link as dead", which looks like a bug in the check
rather than a quiet link.

---

## 9. One assertion was wrong about the code rather than the other way round

**What happened.** `check("streaming reset the back-off", sup.backoff,
1.0)` failed with 2.0.

**What was done.** Nothing to the code. Reaching Streaming resets the delay
to 1 s; the round then ends, and ending a round sleeps for the current
delay and doubles it. So after one complete round the *next* delay is
already 2, which is correct. The assertion was rewritten to check the delay
that was actually slept, which is the observable thing, and a comment says
why the other reading looks like a bug.

**Why that and not the alternative.** The alternative was to "fix" the
supervisor so that the attribute read 1.0 after a round, which would have
meant not doubling after a streaming round, which is the opposite of what
the ladder is for.

---

## 10. Every kernel symbol was read out of the tree first

**What happened.** Another project in this repository had three invented
`CONFIG_` symbols in its fragment, discovered only when a build finally
compiled a kernel and `./go kconfig` reported them. That was fresh in mind
while writing `ble.cfg`.

**What was done.** Every symbol was located in the kernel source at
`rpi-6.6.y` before it was written, and two of them turned out to need
saying differently:

| Symbol | What reading it changed |
|---|---|
| `BT` | Declared with `menuconfig`, not `config`. Settable, but worth knowing that grepping for `^config BT$` finds nothing |
| `SERIAL_DEV_BUS` | The same |
| `BT_HCIUART_BCM` | `depends on BT_HCIUART_SERDEV` and `select BT_HCIUART_H4`, `select BT_BCM` |
| `BT_HCIUART_SERDEV` | A promptless bool, `default y` when `SERIAL_DEV_BUS && BT_HCIUART` |
| `BT_BCM` | A promptless tristate, selected only |

The last two cannot be asked for from a fragment at all. They are in the
file anyway, as assertions about the consequence of the three lines above
them, in the same way `rt.cfg` names `LOCKUP_DETECTOR`. A future defconfig
that drops `SERIAL_DEV_BUS` is then caught by `./go kconfig` rather than by
an `hci0` that never appears.

**Why that and not the alternative.** Ten minutes of reading against an
evening of debugging a radio that is not the problem.

---

## 11. What was run, and what it proves

**What happened.** None of this can be built here: no Yocto host, no board,
no peripheral. The question was what can honestly be checked anyway.

**What was done.** Three suites, run locally:

| Suite | Assertions | What it covers |
|---|---|---|
| `tests/stwin-bluest-test.sh` | 29 | Masks from UUIDs, both frame shapes, an unknown bit above and below the known ones, short and long frames |
| `tests/stwin-supervisor-test.sh` | 28 | The ladder, a failure at each of four steps, the doubling and the cap, reset on data, a stalled link, that a session is always closed |
| `tests/stwin-sinks-test.sh` | 30 | CSV columns per mask, daily rollover, append without a second header, an incomplete record, MQTT topic and payload, one LED per state |

Plus `python scripts/lint.py` clean and `sh -n` on every new shell file.
Two of the three suites found a real defect on their first run, which is
entries 7 and 8 above.

**Why that and not the alternative.** The alternative is the version of
this project that exists in a hundred repositories: a script that works on
the author's bench, with no way to tell whether a change broke the
reconnect logic short of pulling a battery. The indirection that makes
these suites possible, one module that imports bleak and a supervisor that
takes a link object, cost about thirty lines.

What none of it proves is that `bleak` and `bluetoothd` behave like the
fake link, or that the field table matches the firmware. The README says
both in its first section rather than at the bottom.

---

## 12. What is deliberately not done

- **No `AdvertisementMonitor1`.** BlueZ has an API for RSSI-filtered
  advertisement monitoring that would wake this process less often than a
  continuous scan. It is a stretch goal, and measuring the CPU difference
  is the interesting part of it rather than the code.
- **No BlueST v2, and so no FP-SNS-DATALOG2.** Different advertising
  layout, and streaming starts only after a PnP-L command is written to a
  command characteristic. That is a second decoder and a command step, not
  a variant, and starting with the firmware that streams unprompted means
  debugging wrong numbers rather than debugging silence.
- **No pairing.** The sensor demo firmware does not request encryption, so
  `Connect` succeeds unpaired and no keys are stored. What to do if a
  firmware build does ask is in the bring-up notes, because the symptom,
  an ATT `Insufficient Authentication`, is not obvious from the Python
  side.
- **No live RSSI.** `org.bluez.Device1`'s `RSSI` property is fed by
  advertising reports and is not refreshed during a connection; reading a
  live link's RSSI needs an HCI command BlueZ does not expose on D-Bus.
  The gateway logs the advertisement RSSI from just before each connection
  and says so, rather than presenting a stale number as a live one.
- **No plot.** The CSV has a real header with units in the column names,
  which is what makes it plottable by anything. What plots it belongs on
  the host.
