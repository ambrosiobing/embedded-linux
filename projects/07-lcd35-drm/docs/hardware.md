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
3. **The ILI9486 datasheet**, which is in the source index and `NOT READ`.
   It gives the ID register and its expected value, which turns step 2
   from an impression into a measurement.

This matters more than it looks. `DESIGN.md`'s own analysis says the board
does **not** wire the controller's serial interface to SPI: it carries
shift registers that turn the SPI stream into the controller's 16-bit
parallel bus. If the controller identification is wrong, that analysis is
about the wrong part.

## What is still `NOT READ`

| Document | Why it matters here |
|---|---|
| ILI9486 datasheet | the ID register, the command set, and the timing the overlay's SPI clock has to respect |
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
