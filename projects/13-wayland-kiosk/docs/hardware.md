# Hardware sources for project 13

[docs/DESIGN.md](DESIGN.md) carries the architecture, the ownership table
and the path from a finger to a widget callback. **This page does not
repeat that.** It records where the hardware claims come from, and which
two of them currently come from somewhere other than Raspberry Pi.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What the product brief says

**Source: Raspberry Pi Touch Display product brief, Raspberry Pi Ltd,
published April 2024**, pages 2 to 4. Read Wednesday 7 October 2026.

| Specification | Value | Page |
|---|---|---|
| display size, diagonal | 7 inches | 3 |
| display format | 800 (RGB) x 480 pixels | 3 |
| active area | 154.08 mm x 85.92 mm | 3 |
| assembly module size | 192.96 mm x 110.76 mm | 3 |
| LCD type | TFT, normally white, transmissive | 3 |
| touch panel | true multi-touch capacitive, up to 10 points | 3 |
| colour configuration | RGB stripe | 3 |
| backlight | LED | 3 |
| surface | anti-glare | 3 |
| production lifetime | in production until at least January 2030 | 3 |

**How it connects**, from page 2, and this is the part that matters for a
bench where everything competes for one header:

> The display connects through an adapter board that handles power and
> signal conversion. **Only two connections to the Raspberry Pi are
> required: power from the GPIO port, and a ribbon cable to the DSI
> port**, on every Raspberry Pi except the Zero line.

So it takes **some** GPIO pins for power plus the DSI connector. The brief
does not say which pins, which matters for the exclusivity question, so
that is `NOT READ` and should be read off the adapter board or measured
rather than assumed.

## Two identifications that the brief does not support

`DESIGN.md` names two parts that Raspberry Pi's own document never
mentions. Both are very likely right and neither is currently sourced.

| Claim in `DESIGN.md` | Evidence | Where it probably comes from |
|---|---|---|
| the touch controller is an **FT5406**, driven by `edt_ft5x06` | `inferred` | the kernel driver and community knowledge |
| the backlight is driven by an **on-board MCU over I2C** | `inferred` | the same; the brief says only "an adapter board that handles power and signal conversion" |

This is the same shape as project 7, where the panel controller is named
from a kernel driver rather than from the vendor. It is worth noticing
that **the pattern repeats**: for display hardware on this bench, the
Linux driver has consistently been a better source of part identity than
the manufacturer's own marketing document. That is a useful thing to know,
and it is still not a citation.

## The safety instruction that belongs in the bench rules

From page 4, and quoted because it is an instruction rather than a
specification:

> Before connecting the device, shut down your Raspberry Pi computer and
> disconnect it from external power.

That is stronger than the bench's general "ground first" rule and it is
the manufacturer's own words. Also from page 4: operate between 0 and
50 C in a dry environment; do not fold or strain the ribbon cable; and the
ribbon's locking mechanism is pulled forward, the cable inserted with the
metal contacts facing the circuit board, then the mechanism pushed back.

The brief also requires the product to be **mounted in a suitable
enclosure** with no part of the circuit board accessible during operation.
This bench does not do that, which is worth stating plainly rather than
leaving implied: the panel is used bare on a desk, which is outside the
manufacturer's stated condition of use.

## This panel is the bench console, and that has consequences elsewhere

`DESIGN.md` records that **every bench image drives this panel**, with
`CMDLINE` appending `console=tty1` so it shows kernel messages and a login
prompt. That is why `dtoverlay=vc4-kms-dsi-7inch` appears in images that
have nothing to do with this project.

**It was briefly mistaken for a stray.** On Tuesday 6 October 2026, while
chasing project 9's serial console, that overlay was found in the kernel
debugging image's `config.txt`, assumed to belong only here, and recorded
in that project's journal as a leak between kas files. It is not. The
correction is in journal entry 27, and the lesson is small and repeatable:
**a line in one project's configuration is explained by the project that
put it there**, and reading the sibling document answers it in one
sentence.

What does remain open is the pairing of `vc4-fkms-v3d` with a `vc4-kms-`
overlay in the same `config.txt`. Those are two different display stacks,
fkms and full KMS, and having both is at best redundant. That is a
question for this project rather than for project 9.

## Still `NOT READ`

| Document | Why it matters here |
|---|---|
| which GPIO pins the adapter board takes for power | decides what else can share the header |
| the number of DSI lanes | the brief does not state it |
| FT5406 datasheet | would turn the touch controller identification into a citation |

The first of those needs no document at all. It can be read off the
adapter board or confirmed on a running system, and it is the one most
worth closing.
