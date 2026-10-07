# Hardware sources for project 17

[docs/DESIGN.md](DESIGN.md) carries the architecture, the BlueZ D-Bus
model, the module split and the bench layout. **This page does not repeat
any of that.** It records a sourcing situation unlike every other project
here: **the link is a radio, so almost nothing a datasheet says is
reachable from the Linux side, and the document this project actually
needs is a protocol specification rather than a datasheet at all.**

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What the Raspberry Pi can and cannot see

```
   STWIN.box                                 Raspberry Pi 3B+
  +---------------------------+             +---------------------------+
  | IIS3DWB  ISM330DHCX       |             |                           |
  | ILPS22QS STTS22H          |             |  stwin-gw                 |
  |      |  I2C or SPI        |             |    decode(mask, bytes)    |
  |   STM32 firmware          |             |      ^                    |
  |      |                    |             |      | D-Bus              |
  |   BlueST GATT server      |  2.4 GHz    |   bluetoothd              |
  |      |                    | ~~~~~~~~~~> |      |                    |
  |   BlueNRG-M2              |             |   BCM43455, HCI           |
  +---------------------------+             +---------------------------+

   everything left of the radio is INVISIBLE to this project
```

**The four sensors' register maps, addresses and electrical
characteristics do not matter to this project at all.** No Linux driver
touches them; nothing on the Pi can read a register. What crosses the
radio is whatever the STWIN.box firmware chose to put in a GATT
characteristic.

That inverts the usual sourcing question. Everywhere else on this bench
the question is "what does this part do"; here it is **"what did somebody
else's firmware decide to send"**.

## The document this project needs is not a datasheet

| What the project needs | Where it lives | Status |
|---|---|---|
| the BlueST GATT service and characteristic UUIDs | ST's BlueST protocol documentation and SDK | **`NOT READ`** |
| the feature mask and how it maps onto bytes | the same | **`NOT READ`**, and `DESIGN.md`'s `decode(mask, bytes)` is the whole project |
| the timestamp format at the head of each notification | the same | **`NOT READ`** |
| which features this particular firmware build advertises | **the board**, by connecting and reading | a measurement, and the right instrument |

**The last row is the important one.** A GATT server is self-describing:
`bluetoothd` enumerates services and characteristics, and `bluetoothctl`
or a short `bleak` script lists them with their UUIDs. **So the primary
source for the protocol is the peripheral itself**, and it is available
without any document, without ST's website, and without the board being
opened.

That is a better position than projects 10 and 12 are in. They need
documents this bench cannot fetch. This one needs a connection.

## What is knowable about the sensors anyway, and why it is recorded

The four sensors are invisible across the link, but their identities are
worth having, because a decoded value with no part behind it is a number
without units or a range.

From ST's own register headers, read Wednesday 7 October 2026:

| Sensor | Role on the STWIN.box | `WHO_AM_I` value |
|---|---|---|
| IIS3DWB | wide-bandwidth vibration accelerometer | `0x7B` |
| ISM330DHCX | 6-axis IMU with machine learning core | `0x6B` |
| ILPS22QS | pressure | `0xB4` |
| STTS22H | temperature | `0xA0` |

**Two of those values are worth a warning.** The ISM330DHCX's
identification is `0x6B`, which is also an **I2C address** used elsewhere
on this bench; and the ILPS22QS's `0xB4` is the same identification as the
LPS22DF on the IKS4A1, because `WHO_AM_I` names a family rather than a
part. Neither matters inside this project and both would matter to anyone
carrying a value between projects, which is why they are written down
next to each other.

**What the identities buy here** is the ability to check a decoded value
against the part that produced it: a wide-bandwidth accelerometer and a
general purpose IMU have very different ranges and bandwidths, and a
`decode()` that treats them alike will produce plausible numbers from the
wrong one.

## The host's radio, named by Linux and not by Raspberry Pi

The Pi 3B+ is the central. Its radio is the **BCM43455**, and as
[project 18's page](../../18-edge-ap-mqtt/docs/hardware.md) records,
**that identification comes from the firmware filename
`brcmfmac43455-sdio.bin`, not from any Raspberry Pi document.** The Pi 3B+
product brief names the bands and Bluetooth 4.2 with BLE; it does not name
the chip.

**What the brief does say matters here.** Bluetooth 4.2 and BLE, from page
3. So this project's central is a 4.2 radio, and anything in the BlueST
protocol that assumes a 5.0 feature, such as 2M PHY or extended
advertising, is not available on this host. **That is a real constraint
and it is sourced**, which is unusual for a radio claim on this bench.

## The console, and the one thing project 9 contributes here

`DESIGN.md` notes that with `enable_uart=1` the console runs on the mini
UART as `ttyS0`.

**That is the same subject project 9 spent an evening on**, from the other
side. The short version, recorded in
[project 9's hardware page](../../09-kernel-debug/docs/hardware.md): on
these boards GPIO14 and GPIO15 carry either the PL011 or the mini UART
depending on a three-bit field, Bluetooth takes the PL011, and `disable-bt`
is what hands it back.

**And here is the conflict that is specific to this project.** This
project needs **Bluetooth**, so `disable-bt` must not be applied, so the
PL011 stays with the radio and the console gets the mini UART. That is
exactly what `DESIGN.md` describes and it is the correct choice.

**The cost, stated so that nobody is surprised by it:** the mini UART's
baud rate is tied to the VPU core clock, so it needs `core_freq` pinned or
`enable_uart=1`, which is why that line is there. A console on the mini
UART is a working console with a known caveat, not a compromise, and this
project is the one place on the bench where it is the right answer rather
than a symptom.

## Reflections on the wiring, which is a console and three LEDs

`DESIGN.md` says it outright: the sensor link is a radio and the only
wires are a console and three LEDs.

**So this project has the least hardware risk and the most protocol
risk on the bench**, and the two are not interchangeable. No lead can be
in the wrong hole. Nothing can be driven into anything. The failure modes
are all of the form "the bytes arrived and were interpreted wrongly",
which no instrument on this bench detects, because the bytes are correct
bytes.

**The guard against that is the one the design already has**: `decode()`
is pure and testable without hardware, `blelink.py` is the only module
that touches the radio and is kept as small as it can be. The hardware
page's contribution is to say **why** that split is the right one here: it
is the only split that lets the risky part be tested at all.

**And one concrete thing to add to it.** A decoder that is given a feature
mask it does not recognise should **refuse and name the mask**, not skip
the feature. On a self-describing protocol read from a firmware build
nobody has documented, an unknown feature is the expected case, and a
decoder that silently drops it produces a shorter record that looks
complete. That is the same failure shape this repository catalogues
everywhere else: plausible output instead of an error.

## Still `NOT READ`

| Document | Why, and whether it is gettable |
|---|---|
| the BlueST protocol specification | the UUIDs and the feature mask. ST hosts it, and `st.com` refuses every fetch from this bench. **The peripheral itself is the better source anyway** |
| the STEVAL-STWINBX1 product page and user manual | the sensor complement, confirmed above from the headers instead, and the board's own power and charging arrangement, which is not confirmed anywhere |
| the four sensors' datasheets | ranges and bandwidths, which turn a decoded number into a quantity with units |

**Nothing here blocks the project.** Of the three rows, the only one that
would change what gets written is the third, and the first is better
answered by connecting to the board than by downloading anything.
