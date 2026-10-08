# Hardware sources for project 7

[docs/DESIGN.md](DESIGN.md) already carries the wiring figure, the
ownership table and the analysis of why this panel is not a plain SPI
device. **This page does not repeat any of that.** It answers a different
question: where does each hardware claim come from, and which ones are
currently resting on something other than a manufacturer's document.

Evidence levels are defined in
[docs/HARDWARE.md](../../../docs/HARDWARE.md); the index of primary
sources is [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## The parts

| Part | What it does | Evidence | Source |
|---|---|---|---|
| Waveshare 3.5 inch RPi LCD (A) | the board | `vendor page` | the Waveshare wiki, read Wednesday 7 October 2026 |
| ILI9486 | panel controller | **see below, this is the interesting one** | |
| ADS7846, or an XPT2046 compatible with it | touch controller | `vendor page` | the wiki names ADS7846 explicitly |

## What the vendor page actually says

Read Wednesday 7 October 2026 from
`https://www.waveshare.com/wiki/3.5inch_RPi_LCD_(A)`.

| Claim | Value |
|---|---|
| resolution | 480 x 320 hardware |
| interface | SPI, over the 40-pin GPIO header |
| pins occupied | **26 of the 40** |
| touch controller | ADS7846, resistive panel |
| supply | 3.3 V and 5 V inputs both used |
| operating current | about 150 mA |
| temperature | commercial grade, 0 to 70 C |
| compatibility | "compatible with any version of Raspberry Pi" |

Pins the wiki identifies, which is not a full table: 1, 2, 4 and 17 for
power; 6, 9, 14, 20 and 25 for ground; **11 for `TP_IRQ`**, the touch
interrupt; 18 to 24 for the panel's control signals and reset; and 19, 21,
23 and 26 for the touch SPI.

## The gap worth naming: nobody has sourced the controller

**The Waveshare wiki does not name the panel controller anywhere.** It
describes the board, the resolution and the touch part, and is silent on
what drives the glass.

`DESIGN.md` identifies it as an **ILI9486** and supports that by citing
`drivers/gpu/drm/tiny/ili9486.c` at v6.12. That is a kernel driver, not a
datasheet. It is good evidence that *somebody* concluded ILI9486, and it
is the right driver to try, but it is not the manufacturer saying so.

So the honest status of the central hardware claim in this project is:

| Claim | Evidence | Note |
|---|---|---|
| the controller is an ILI9486 | `inferred` | from the kernel driver that is believed to work, and from the separate ILI9486 datasheet being the one in the source list. The vendor does not state it |

**What would settle it**, in order of cost:

1. **The board itself.** The controller is usually marked. A reading of
   the silkscreen or the chip is primary evidence and costs nothing but a
   look.
2. **A probe.** Once the panel is driven, the ILI9486 answers a read of
   its ID register. A driver that binds and produces a picture is strong
   evidence; a driver that binds and produces nothing is not.
3. ~~**The ILI9486 datasheet**, which is in the source index and
   `NOT READ`. It gives the ID register and its expected value, which
   turns step 2 from an impression into a measurement.~~ **Read Thursday
   8 October 2026, and the second sentence was wrong.** It gives two
   identification commands and publishes an expected value for neither.
   The section after next explains why, and what to do instead.

This matters more than it looks. `DESIGN.md`'s own analysis says the board
does **not** wire the controller's serial interface to SPI: it carries
shift registers that turn the SPI stream into the controller's 16-bit
parallel bus. If the controller identification is wrong, that analysis is
about the wrong part.

## The controller datasheet is read, and it does not contain the answer

**Source: ILI Technology Corp., "a-Si TFT LCD Single Chip Driver,
320RGBx480 Resolution and 262K-color", version 0.06, 219 pages.** Read
Thursday 8 October 2026.

This section was written expecting to close the identification question.
It does the opposite, and the reason is worth more than the closure would
have been.

### Three names, and the first surprise is on the cover

| Where | What it says |
|---|---|
| `DESIGN.md` | the controller is an **ILI9486** |
| the kernel | `drivers/gpu/drm/tiny/**ili9486**.c` |
| the file Waveshare serves as `ILI9486_Datasheet.pdf` | **ILI9486L**, on every one of its 219 pages |

**The vendor's own link for "the ILI9486 datasheet" serves a datasheet for
the ILI9486L.** Those are different part numbers from the same
manufacturer. Whether the difference matters for this panel is not
something either document says.

**And the URL in the source index was dead.** It pointed at
`waveshare.com/w/upload/4/4e/ILI9486_Datasheet.pdf`, which returns 404.
The live file is at `/7/78/`. Both are corrected in
[docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

### The step that was planned, and why it cannot be taken

This page's plan said, as step 3:

> **The ILI9486 datasheet**, which is in the source index and `NOT READ`.
> It gives the ID register and its expected value, which turns step 2 from
> an impression into a measurement.

**The first half is true and the second half is not.** The document
defines two identification commands and publishes an expected value for
neither.

| Command | What it returns | What the datasheet gives as the value |
|---|---|---|
| `04h`, RDDIDIF, section 8.2.3 page 73 | a dummy byte, then `ID1`, `ID2`, `ID3` | **`XX` for all three**, and the Default table says "See description" |
| `D3h`, Read ID4, command list page 69 | a dummy byte, then `ID41`, `ID42`, `ID43` | **`XX` for all three** |

And the description of `04h` explains why. `ID1` is the **LCD module's
manufacturer ID**, `ID2` the **module and driver version ID**, `ID3` the
**module and driver ID**. They identify the module, which the module maker
programs, not the controller, which ILI makes.

**So there is no published constant to compare a read against.** This is
structurally different from every other identification on this bench. The
BMP280 answers `0x58` because Bosch says so; the LSM6DSV16X answers `0x70`
because ST says so. **This controller answers whatever Waveshare put
there, and Waveshare does not say what that is either.**

### What that changes about the plan

The three steps stand, with step 3 rewritten:

1. **The board itself.** Unchanged, and now the **only** route that can
   give a part number. Read the chip marking.
2. **A probe.** Unchanged in value and lower in ambition: reading `04h` or
   `D3h` tells you **something answered and what it calls itself**, which
   is useful, repeatable and not a part number. Record whatever it
   returns; a value nobody can interpret today is still a value the next
   person can compare against.
3. ~~The datasheet gives the expected value~~. **It does not.** What the
   datasheet gives instead is the command set, the interface selection and
   the timing, which is what the overlay's SPI clock has to respect, and
   that was the other half of why it was on the list.

**A fourth route exists and it is the one most likely to work.** The
kernel's `ili9486.c` was written by somebody who had this hardware. What
initialisation sequence it sends, and whether it reads any identification
at all, is in that file. It will not name the chip on this board, but it
will say what the driver assumes, which is the thing `DESIGN.md`'s
analysis actually depends on.

### One practical obstacle to the probe, from the same command list

The command list on page 70 includes **`FBh`, "SPI Read Command Setting"**,
with a `SPI_READ_EN` bit and an `SPI_CNT[3:0]` field.

**So reading anything back over the serial interface has to be enabled
first.** A probe that sends `04h` and expects three bytes without having
set that up may get nothing, and getting nothing would look exactly like a
part that is not an ILI9486.

That matters because it is a way for step 2 to produce a **false
negative**, which is the failure mode this repository keeps cataloguing in
its other form. The honest version of the probe is therefore: enable SPI
read, then read, and if nothing comes back, say that the probe did not run
rather than that the part is wrong.

**And `DESIGN.md`'s own analysis makes it harder still.** It concludes
that this board does not wire the controller's serial interface to SPI at
all: shift registers turn the SPI stream into the controller's 16-bit
parallel bus. **A one-way path cannot carry a reply.** If that analysis is
right, the probe is not merely awkward, it is impossible on this board,
and step 1 is the only route left.

### The copyright notice, quoted because it is the sharpest instance yet

Every page of this document carries, in italics at the foot:

> The information contained herein is the exclusive property of ILI
> Technology Corp. and shall not be distributed, reproduced, or disclosed
> in whole or in part without prior written permission of ILI Technology
> Corp.

[docs/DATASHEETS.md](../../../docs/DATASHEETS.md) already forbids copying
vendor figures, tables and extended text into this public repository, and
sets out the alternative: cite the value, the section and the page, and
redraw anything that needs a picture. **This is the clearest reason yet
for that rule**, and the sections above are written to it: command codes,
section numbers, page numbers and the one short sentence that explains why
`ID1` is not a part number. No table is reproduced.

## What is still `NOT READ`

| Document | Why it matters here |
|---|---|
| ~~ILI9486 datasheet~~ | **read Thursday 8 October 2026.** It gives the command set and the timing. It does **not** give an identification value, because there is none to give |
| `drivers/gpu/drm/tiny/ili9486.c` | what the driver assumes about the part, which is what `DESIGN.md`'s analysis actually rests on. Not a datasheet, and the best remaining source |
| ADS7846 datasheet | the conversion timing and the reference arrangement behind the touch driver's settings |

Both are listed in [docs/DATASHEETS.md](../../../docs/DATASHEETS.md) with
their URLs.

## Before wiring this board

The decisions that are already made, and why, so they are not rediscovered:

**It is a 26-pin socket that sits straight on header pins 1 to 26**, which
means the HAT exclusivity rule applies in full: nothing else can be on
that header at the same time. See
[docs/HARDWARE.md](../../../docs/HARDWARE.md).

**It takes both 3.3 V and 5 V from the header.** Unlike the sensor modules
on this bench, that is correct and intended here, and neither is to be
left open.

**Two SPI slaves, two subsystems that never meet.** CE0 is the panel, CE1
is the touch controller. They are different drivers in different kernel
subsystems, and a working panel with dead touch, or the reverse, is a
normal intermediate state rather than a sign that something is wired
wrongly.

**`TP_IRQ` is on header pin 11, which is GPIO17.** That is the same GPIO
the heartbeat LED uses in project 9. Both cannot be on one board at once,
which is the kind of collision the ownership table in `DESIGN.md` exists
to catch.

## Nothing has been wired yet

This project has not been built on the bench, so there are no rewiring
reflections to record. When it is, the thing worth writing down is
whichever of the three controller checks above settled the identification,
and what the panel did before it was settled.
