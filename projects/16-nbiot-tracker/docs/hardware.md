# Hardware sources for project 16

[docs/DESIGN.md](DESIGN.md) carries the architecture, the instrument
section, the schematic and the modem state machine, and it is unusually
careful about what the instrument may be asked to claim. **This page does
not repeat that.** It records what the vendor's page actually says, and it
is a short page, because the vendor's page says very little.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| Waveshare wiki, SIM7070G Cat-M/NB-IoT/GPRS HAT | `vendor page` | **read Wednesday 7 October 2026** |
| PPK2 user guide v1.0.1, document 4461_012 | `datasheet` | read; worked through in [project 3's page](../../03-boot-energy/docs/hardware.md) |
| SIM7070G HAT user manual or schematic | | **`NOT READ`**, and see below: it is not obvious that one exists |
| SIMCom SIM7070G hardware design and AT command manual | `datasheet` | **`NOT READ`** |

## What the wiki states

**Source: Waveshare wiki, SIM7070G Cat-M/NB-IoT/GPRS HAT.** Read
Wednesday 7 October 2026.

| Item | Value |
|---|---|
| NB-IoT bands | B1, B2, B3, B4, B5, B8, B12, B13, B18, B19, B20, B25, B26, B28, B66, B71, B85 |
| Cat-M bands | B1, B2, B3, B4, B5, B8, B12, B13, B14, B18, B19, B20, B25, B26, B27, B28, B66, B85 |
| also supported | GPRS and EDGE |
| GNSS | GPS, BeiDou, GLONASS, Galileo; 16 channels; 1 Hz update |
| power supply | 5 V |
| logic voltage | 5 V or 3.3 V, **switched by a 0 ohm resistor** |
| idle current | about 41 mA overall |
| UART | breakout control pins, "to connect with host boards like Arduino/STM32" |
| power on | hold the PWRKEY button for about 1 s |

## What the wiki does not state, which is most of what this project needs

**This is the finding, and it is worth being blunt about.**

| Question | On the wiki |
|---|---|
| which Raspberry Pi header pins the HAT uses | **absent**; there is no pin table at all |
| UART selection jumper positions | **absent** |
| whether PWRKEY is active high or active low | **absent** |
| whether PWRKEY can be driven from a host GPIO, and any default strap | **absent** |
| a flight mode pin | **absent**; not mentioned anywhere |
| peak or transmit current | **absent**; only the 41 mA idle figure |
| antenna connector types | **absent**; the page says antennas are needed |
| the USB to UART converter part | **absent** |

**Compare that with its sibling.** The SIM7600E-H 4G HAT has both a PDF
manual and a wiki page, and between them they give a pin table, the
jumper block, the board inventory and two contradictory PWRKEY straps. See
[project 15's hardware page](../../15-lte-router/docs/hardware.md). For
the SIM7070G only the wiki was found, and it answers almost none of the
same questions.

**So the two HATs are not equally documented**, which is not something you
would guess from the product pages, and this project should not assume
that what was learned about the 7600 transfers. It is a different board by
the same vendor, and the only evidence that the jumper arrangement is
similar would be a photograph of the board or its schematic.

## The one specification that is a live hazard

**"Logic voltage: 5 V / 3.3 V (switch via 0 ohm resistor)."**

That is not a jumper. It is a resistor that has to be unsoldered and moved
to change the host side between 5 V and 3.3 V. Three consequences:

1. **The setting is whatever the factory fitted**, and the wiki does not
   say which that is
2. **It cannot be changed on this bench**, because there is no soldering
   iron here, as [docs/HARDWARE.md](../../../docs/HARDWARE.md) records
3. If the fitted setting is 5 V, a Raspberry Pi GPIO on the other side of
   it is outside its absolute maximum, which the Pi 4 datasheet puts at
   the 3.3 V rail plus a margin

**So the first action with this board is to look at it**, find the 0 ohm
resistor and its two pads, and record which pad it sits on. That is a
photograph, not a document, and it comes before the HAT and a Raspberry Pi
are connected. This is the same shape as project 15's PWRKEY strap: a
question no document here answers and the board answers in seconds.

## What this project already got right without a datasheet

`DESIGN.md` is, unusually, ahead of its sources. Three of its decisions
were made from reasoning and from this repository's own evidence rather
than from a vendor document, and reading the vendor document has not
changed any of them.

**The instrument is put on the modem's rail alone.** Because a Raspberry
Pi drawing hundreds of milliamps would bury a modem in power saving mode,
whose current is measured in microamps. The PPK2's resolution table,
read in [project 3's page](../../03-boot-energy/docs/hardware.md), now
puts a number on why that matters: in the 50 mA to 1 A range the
resolution step is a whole milliamp, so a microamp-scale subject measured
alongside a Pi would not merely be buried, it would be below the
quantisation.

**2G is locked out with `AT+CNMP=38`.** Because a GPRS burst is
conventionally about 2 A and the PPK2 cannot take it. The wiki confirms
the HAT supports GPRS and EDGE, so the fallback path this guards against
is real rather than theoretical. The 2 A figure is still **`inferred`**,
as `DESIGN.md` says: it is the conventional GSM burst, not a measurement
and not a quoted specification. The SIMCom hardware design document would
settle it.

**Both of the PPK2's micro USB sockets are connected, every time.** This
project put the rule first because project 3 lost a session to it. The
instrument's own guide, page 9, now supports it exactly: the
`USB POWER ONLY` socket is "only needed in Source Meter mode (> 400 mA)",
with a supply of 1 A or more recommended. A modem attaching to a network
crosses 400 mA.

**And one number in that section needs amending.** `DESIGN.md` quotes
project 15 saying the PPK2 maxes at 1 A. In source meter mode the limit is
**600 mA**, Table 7 page 16. Since this project measures a modem that will
exceed both, the conclusion stands and the margin for error is smaller
than written.

## Still `NOT READ`, in the order worth closing

| Document | What it would settle |
|---|---|
| a photograph of the board | the 0 ohm logic voltage resistor, and whether a UART jumper block exists at all |
| the SIM7070G HAT schematic, if Waveshare publishes one | the header pins, PWRKEY and the logic voltage strap, all at once |
| SIMCom SIM7070G hardware design | the transmit current, which is the number that decides whether the PPK2 can be used at all |
| SIMCom SIM7070 series AT command manual | the exact command set behind the tracker's state machine |

**The first row is free and is blocking the second half of everything
else.** Until somebody looks at the board, this project does not know what
voltage its host interface runs at, and that is a question to answer
before a Raspberry Pi is attached rather than after.
