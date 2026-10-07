# Hardware sources for project 10

[docs/DESIGN.md](DESIGN.md) carries the architecture, the IIO ownership
table, the wiring and the expected bus addresses. **This page does not
repeat any of that.** It records where those addresses now come from, and
it adds the two things the design was missing: a **7-bit versus 8-bit
warning** that would make every scan look wrong, and a **second IMU that
must be answering and is not in the list.**

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## The datasheets are unreachable, and ST publishes the same facts as code

**Every attempt to fetch a PDF from `st.com` has failed on this bench**,
across several sessions and several documents: UM3239 for the IKS4A1, the
seven sensor datasheets, the product pages. That is recorded in
[docs/DATASHEETS.md](../../../docs/DATASHEETS.md) and it is not a dead
link, it is the host refusing.

**ST publishes the register maps anyway, as C headers, in its own GitHub
repositories.** Each sensor has a `<part>-pid` repository containing
`<part>_reg.h`, written and maintained by STMicroelectronics, and it
carries the I2C addresses, the `WHO_AM_I` register and the expected device
identification value as `#define` lines.

**That is a primary source**, with one important limit stated up front: it
gives **addresses and register layout**, not **electrical characteristics**.
Supply ranges, absolute maxima, timing and noise are still `NOT READ` and
only the datasheets have them.

| What ST's headers give | What only the datasheet gives |
|---|---|
| I2C addresses, both strap options | supply voltage range |
| `WHO_AM_I` register address | absolute maximum ratings |
| the expected identification value | output data rates with their noise figures |
| every register address and bitfield | timing, start-up, and the FIFO's real depth in bytes |

## The trap, before the table: these are 8-bit addresses

**ST's headers give the addresses in 8-bit form, shifted left by one, with
the read/write bit included.** Linux, `i2cdetect`, device tree and every
`i2c-tools` command use **7-bit** addresses.

```
   ST header        >> 1      what i2cdetect shows
   -----------               --------------------
   0xD5             -->      0x6A
   0xD7             -->      0x6B
   0x3D             -->      0x1E
   0xB9 / 0xBB      -->      0x5C / 0x5D
```

**Read a `#define` straight into a device tree node and the device will
not answer**, and the symptom is a clean bus scan with the sensor visible
at an address nothing is bound to. That is the ordinary way to lose an
evening on an I2C bus, and it is entirely avoidable by writing the
conversion down once, which is what this section is for.

## The predicted scan, which is now a test that can fail

`DESIGN.md` says the expected addresses are to be confirmed with
`i2cdetect -y 1` rather than assumed, and lists four. **Here is the full
set, derived from ST's own headers**, so that a scan becomes a comparison
rather than a reading.

| Sensor | ST header `#define` | 7-bit address | `WHO_AM_I` register | Expected value |
|---|---|---|---|---|
| LSM6DSV16X | `0xD5` / `0xD7` | **0x6A** or **0x6B** | `0x0F` | `0x70` |
| LSM6DSO16IS | `0xD5` / `0xD7` | **0x6A** or **0x6B** | `0x0F` | `0x22` |
| LIS2MDL | `0x3D`, fixed | **0x1E** | `0x4F` | `0x40` |
| LIS2DUXS12 | `0x31` / `0x33` | **0x18** or **0x19** | `0x0F` | `0x47` |
| LPS22DF | `0xB9` / `0xBB` | **0x5C** or **0x5D** | `0x0F` | `0xB4` |
| STTS22H | `0x71`, `0x79`, `0x7D`, `0x7F` | **0x38**, **0x3C**, **0x3E** or **0x3F** | | `0xA0` |
| SHT40 | Sensirion, not an ST part | **0x44** | | |

Source for every ST row: the `<part>_reg.h` header in the corresponding
`STMicroelectronics/<part>-pid` repository, read Wednesday 7 October 2026.

**`DESIGN.md`'s four addresses are all confirmed by this.** `0x6a` is the
LSM6DSV16X with its strap low, `0x1e` is the LIS2MDL's only address,
`0x5d` is the LPS22DF with its strap high, and `0x44` is the standard
Sensirion SHT4x address.

## The second IMU, which must be answering and is not in the list

**The IKS4A1 carries two inertial measurement units**, the LSM6DSV16X and
the LSM6DSO16IS. ST's headers give both the same address pair, `0x6A` and
`0x6B`.

**They cannot both be at `0x6A`.** On a board that carries both, one of
them is strapped to `0x6B`, and a scan of that bus must therefore show
**both** addresses.

`DESIGN.md` names `0x6a` and says the STTS22H and LIS2DUXS12 "also answer",
without addresses. It does not mention `0x6b` at all, and the design's
driver table binds `st_lsm6dsx` to one IMU.

**So there is a sensor on that bus this project has not accounted for**,
and the first `i2cdetect` will show it. Three things follow:

1. **`0x6b` appearing is expected**, not an anomaly, and nobody should
   spend time on it
2. **Which of the two IMUs is at which address is not knowable from the
   headers**, because that is a board-level strap and it lives in UM3239
   or on the schematic. It **is** knowable in one command on the board:
   read register `0x0F` at each address and compare against `0x70` and
   `0x22`
3. **That read is a real test.** It can fail, it distinguishes the two
   parts, and it would catch a shield that is not the one anyone thought
   it was. `DESIGN.md` already insists that addresses be confirmed rather
   than assumed; this makes the confirmation diagnostic rather than merely
   present

## Why the identification read is worth more here than anywhere else

This bench has wanted a `WHO_AM_I` check before. Project 5's page lists
"the device identification register and its fixed value" among the things
the ADXL345 datasheet would settle and that are "not stated anywhere in
this project", and project 7 needs the same thing for its display
controller and cannot get it.

**Here it is available for six of the seven sensors, for free, from the
vendor's own code.** A probe that reads `0x0F` and compares against a
published constant turns "something answered at this address" into "this
exact part answered", which is the difference between a scan and a
measurement.

**And it closes a question an address cannot.** An address is ambiguous by
design: two parts on this very shield share `0x6A`. The two
identification values here, `0x70` for the LSM6DSV16X and `0x22` for the
LSM6DSO16IS, are different, so on **this** board the read separates them.

**It would be wrong to generalise that.** Reading more of ST's headers on
the same afternoon shows the value identifies a **family**, not a part:
the LSM6DSV32X on the IKS5A1 also answers `0x70`, and the ILPS22QS on the
STWIN.box answers `0xB4`, the same as the LPS22DF here. So the honest form
of the rule is:

> `WHO_AM_I` tells you which family answered. It separates the two IMUs on
> this shield because they are from different families. It would not
> separate an LSM6DSV16X from an LSM6DSV32X.

Which is still far better than an address, and it is the kind of limit
worth knowing before a probe is written and trusted.

## What the register headers do not settle, and it matters for wiring

The project's wiring puts `INT1` of the LSM6DSV16X on **GPIO24**, header
pin 18, with the shield's own 3.3 V arrangement behind it.

**Nothing in a register header says what voltage that pin presents.** The
headers are a software interface; they contain no electrical information
at all. So the following remain exactly as `NOT READ` as before:

| Question | Where it lives |
|---|---|
| the supply range of each sensor | its datasheet |
| the absolute maximum on an interrupt pin | its datasheet |
| what the IKS4A1 shield does between the Arduino header and the sensors | UM3239 |
| whether `INT1` is push-pull or open-drain by default, and its polarity | the datasheet, and also a register the header does define |

**The last row is half answerable from the header**, which is a good
illustration of the split: the header tells you which bit selects
open-drain and which selects active-low, and the datasheet tells you what
voltage results and what may be connected to it.

## What is needed from Joseph, and why

**The ST documents cannot be fetched from this bench.** They can be
downloaded in a browser. The ones that would close the remaining gaps, in
order of value:

| Document | What it closes |
|---|---|
| **UM3239**, getting started with the X-NUCLEO-IKS4A1 | which IMU is strapped to which address, what the shield does between the header and the sensors, and the jumper arrangement |
| LSM6DSV16X datasheet | the supply range, the absolute maxima, and the `INT1` pin's electrical behaviour |
| LPS22DF, LIS2MDL, STTS22H, LIS2DUXS12 datasheets | the same, per sensor |
| SHT40 datasheet, from Sensirion | the one non-ST part, and Sensirion does serve PDFs here, so this one is gettable without help |

**UM3239 is the one worth asking for first.** Everything else on the list
is a per-sensor detail; UM3239 is the only document that describes the
board, and the board is where every address strap and every level shift
actually happens.

## Still `NOT READ`

Everything above marked so, plus the IKS4A1's schematic if ST publishes
one separately from UM3239. **The register maps are no longer on this
list**, and that is the change this page records.
