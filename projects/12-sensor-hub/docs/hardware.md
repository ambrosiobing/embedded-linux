# Hardware sources for project 12

[docs/DESIGN.md](DESIGN.md) carries the architecture, the CBOR frame
format, the D-Bus interface and the ownership table. **This page does not
repeat any of that.** It records what can and cannot be sourced for the
three pieces of hardware in the chain, and makes one point this project
needs more than any other on the bench: **almost none of it is the
Raspberry Pi's problem.**

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## The architecture decides who needs which document

```
   Raspberry Pi 4            NUCLEO-H7A3ZI-Q            X-NUCLEO-IKS5A1
  +---------------+        +-----------------+        +-----------------+
  | sensorhubd    |        | firmware        |        | LSM6DSV32X      |
  | CBOR over     | <====> | lsm6dsv32x_reg  | <====> | LSM6DSO16IS     |
  | a serial link |  UART  | proto.c         |  I2C   |                 |
  +---------------+        +-----------------+        +-----------------+

   needs: a tty              needs: the register        needs: the shield
   and a frame format        map and the pin map        documentation
```

**This is the project's whole architectural claim**, and it has a sourcing
consequence that is worth stating plainly: the sensors' registers are a
problem for the **firmware**, not for Linux. Projects 5 and 10 put sensors
under the kernel's IIO subsystem and therefore need every electrical and
register detail on the Linux side. This one deliberately does not.

**So the Raspberry Pi's hardware documentation requirement for this
project is almost nothing**: a USB serial device and a `udev` rule. The
hard sourcing sits one board along, and it belongs to the firmware volume
rather than to this repository.

## What has been read

| Document | Evidence | Status |
|---|---|---|
| ST register headers, `lsm6dsv32x_reg.h` and `lsm6dso16is_reg.h` | `datasheet`, as ST's own source | **read Wednesday 7 October 2026** |
| Raspberry Pi 4 Model B datasheet, release 1.1 | `datasheet` | read, in [docs/HARDWARE.md](../../../docs/HARDWARE.md) |
| **UM2408**, the Nucleo-144 MB1363 user manual | `datasheet` | **`NOT READ`**, `st.com` refuses |
| the X-NUCLEO-IKS5A1 product page and its user manual | `vendor page` | **`NOT READ`**, the same |
| the two sensors' datasheets | `datasheet` | **`NOT READ`**, the same |

## The two IMUs collide, exactly as they do on the IKS4A1

From ST's own headers, read Wednesday 7 October 2026:

| Sensor | header `#define` | **7-bit** address | `WHO_AM_I` | Expected value |
|---|---|---|---|---|
| LSM6DSV32X | `0xD5` / `0xD7` | **0x6A** or **0x6B** | `0x0F` | `0x70` |
| LSM6DSO16IS | `0xD5` / `0xD7` | **0x6A** or **0x6B** | `0x0F` | `0x22` |

**The same two observations as in
[project 10's page](../../10-iio-iks4a1/docs/hardware.md), and they apply
unchanged here.**

1. **ST's headers give 8-bit addresses.** Shift right by one for anything
   that speaks to Linux or to a 7-bit I2C API. On this project that trap
   is in the **firmware** rather than in a device tree, which makes it no
   less expensive.
2. **Both IMUs want the same address pair**, so one is strapped to the
   other, and a scan on the shield's bus must show both.
3. **`WHO_AM_I` separates them**, `0x70` against `0x22`, because they are
   different families. It would not separate an LSM6DSV32X from an
   LSM6DSV16X, which both answer `0x70`. That limit is worth knowing
   before a probe is trusted, especially here, where the IKS4A1 and the
   IKS5A1 are both on this bench and differ in exactly that way.

**And that is a real risk for this bench specifically.** Two shields, two
projects, two IMU pairs, and the part that distinguishes IKS4A1 from
IKS5A1 is the one thing `WHO_AM_I` cannot tell you. **The identification
read confirms you are talking to an LSM6DSV; the silkscreen tells you
which shield you picked up.** Look at the board.

## What this project needs that no sensor datasheet contains

The chain's weakest sourcing is not the sensors at all.

| Question | Where it lives | Status |
|---|---|---|
| which Nucleo pins carry the UART to the Pi | UM2408 | **`NOT READ`** |
| whether that UART is the ST-LINK virtual COM port or a separate one | UM2408 | **`NOT READ`** |
| which Arduino header pins the IKS5A1 uses for I2C and interrupts | the IKS5A1 user manual | **`NOT READ`** |
| the voltage of the Nucleo's UART pins | UM2408 | **`NOT READ`**, and this is the one with a hazard attached |

**The fourth row matters most**, because it is the only place in this
project where two boards' electrical worlds meet. `DESIGN.md` says the
same COM port carries both SWD and the serial link, which strongly
suggests the ST-LINK virtual COM port over USB rather than raw UART pins,
and if so **there is no voltage question at all**: the link is USB and the
translation happens inside ST-LINK.

That reading is `inferred` from one sentence in `DESIGN.md`. It is
probably right. **If it is wrong, and the link is raw UART pins between a
3.3 V Nucleo and a 3.3 V Raspberry Pi, it is still fine**, which is the
comfortable case. The reason to resolve it anyway is that the two
arrangements have completely different failure modes, and a bring-up note
that does not know which one it is describing cannot be followed.

## What the Pi contributes, which is one `udev` rule and one caution

**Raspberry Pi 4 Model B datasheet, section 5.3, page 11:** two USB 2 and
two USB 3 type-A sockets, downstream current limited to roughly 1.1 A in
aggregate.

A Nucleo drawing its own power from that port is well inside it. The
caution is not current, it is naming: `DESIGN.md` binds the service to
`dev-sensorhub.device` and a `udev` rule, which is the right shape
precisely because **a USB serial device's `/dev/ttyACM*` number is not
stable** and this bench has already been bitten by renumbering, on the
console adapter in project 9.

## Reflections on the wiring, and why there is so little of it

**This project's wiring is one USB cable**, and that is an architectural
result rather than a convenience.

Projects 5 and 10 wire sensors to a Raspberry Pi's own I2C bus, and they
have accumulated between them: a supply that must not go through a
breadboard rail, a friction-contact header that can open at any moment,
protection diodes that take a whole bus down when one module's supply
wanders, an interrupt line with an unsourced absolute maximum, and an
internal pull-up weak enough to predict its own failure.

**This one has a USB cable.** Everything that could go wrong electrically
has been moved onto a board designed to carry it, and the Linux side sees
a character device. **That is the argument for the architecture, stated in
hardware terms rather than in software ones**, and it is worth having
beside the CBOR and D-Bus reasoning in `DESIGN.md`, which is all about the
other benefits.

**The cost is equally real and should be said.** The sensors are now
behind firmware this repository does not build, so a sensor question
becomes a firmware question, and the one thing Linux can no longer do is
look at a register.

## What is needed from Joseph

The same list as project 10, with one addition. `st.com` refuses every
fetch from this bench; these can be downloaded in a browser.

| Document | What it closes |
|---|---|
| **UM2408**, the Nucleo-144 MB1363 user manual | every row of the table above, including the UART question |
| the X-NUCLEO-IKS5A1 user manual | the shield's pin map and its address straps |
| LSM6DSV32X and LSM6DSO16IS datasheets | supply ranges, absolute maxima, FIFO depths |

**UM2408 first**, for the same reason UM3239 comes first in project 10:
the board-level document is the one that says how the parts are connected,
and that is where every open question here actually lives.
