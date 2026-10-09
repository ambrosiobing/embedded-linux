# Hardware sources for project 14

[docs/DESIGN.md](DESIGN.md) carries the architecture, the endpoint budget,
the ownership table and the three consequences of the host port being the
supply. **This page does not repeat any of that.** It records what the Pi
4's own datasheet says about those claims, and the answer is more
interesting than usual: **the datasheet does not describe this project's
central capability at all.**

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| Raspberry Pi 4 Model B datasheet, release 1.1, 12 March 2024 | `datasheet` | **read Wednesday 7 October 2026** |
| BCM2711 ARM Peripherals, release 4, 18 January 2022 | `datasheet` | **read Friday 9 October 2026**, and it has no USB chapter |
| the USB Type-C specification's CC pull-down requirements | | **`NOT READ`** |

## The datasheet does not know this project is possible

**Section 5.3, page 11**, is the whole of what the datasheet says about
USB: two USB 2 and two USB 3 type-A sockets, with downstream current
limited to roughly 1.1 A in aggregate across the four. **Section 4.1,
page 8**, describes the USB-C connector in one role only: the power input,
wanting a good quality supply of 5 V at 3 A.

**Nowhere does it say the USB-C port is a dual-role port, or that the SoC
has a device-capable controller on it.**

That is the same shape as three other findings on this bench: the ILI9486
in project 7 and the FT5406 in project 13 are both named by Linux drivers
and by neither manufacturer, and here the entire premise of the project,
that `dwc2` can run in peripheral mode on that connector, comes from the
kernel's device tree and from the BCM2711, not from the product document.

**Which is fine, and it needs saying out loud.** `DESIGN.md` is right that
the USB-C port is wired to the SoC's own dual-role `dwc2` while the type-A
sockets sit behind a separate controller. The evidence for it is the
kernel source, the device tree and the project's own working gadget, which
is `measured`. It is **not** `datasheet`, and anyone auditing this project
against Raspberry Pi's document will find the capability absent rather
than contradicted.

## The current budget, now with the manufacturer's own number against it

`DESIGN.md`'s ownership table says the current budget is 500 mA on USB 2.0
or 900 mA on USB 3, that nothing may assume 3 A, and that a Pi 4 idles
near 550 mA.

**Section 4.1, page 8:** the Pi 4 requires a supply capable of 5 V at
**3 A**; a 5 V 2.5 A supply may be used if attached downstream USB devices
draw less than 500 mA.

Put those side by side and the shape of this project becomes stark:

```
   what the manufacturer asks for      what the host port provides

      5 V at 3.0 A                        0.5 A   USB 2.0
                                          0.9 A   USB 3.0
      5 V at 2.5 A, if downstream         up to 3 A only with USB-C
      USB draws under 500 mA              current negotiation

   |---------------------------------------------|
   0 A                                          3 A
      ^ USB 2.0        ^ USB 3.0                 ^ the requirement
```

**So this project runs the board at between one sixth and one third of its
specified supply, deliberately, and that is the project.** `DESIGN.md`
already draws the right conclusions from it: no display, no HAT, cap the
clock if the journal warns. What the datasheet adds is that this is not a
margin being shaved, it is a documented requirement being knowingly
unmet, and the line in the design that says "nothing that assumes 3 A"
should be read as the load-bearing sentence it is.

**The 550 mA idle figure is unsourced.** The datasheet gives no idle or
typical current anywhere. It is presumably a measurement or a well known
community figure; either way it should carry its origin, because the whole
budget argument turns on it. **This bench could measure it**, and
instructively cannot with the instrument it has: the PPK2's source meter
tops out at 600 mA, below the figure itself.

## The thermal row, which is the other half of the same budget

**Section 5.6, page 11:** recommended ambient 0 to 50 C, and the governor
reduces clock speed and voltage when idle, raises both under load, and
throttles to keep the CPU under 85 C.

`DESIGN.md` says to cap the clock if the journal warns. The datasheet says
the governor **raises** the clock under load by default, which is the
behaviour that turns a marginal supply into an undervoltage event at
exactly the moment the gadget is busy. So capping the clock is not a
tidying step, it is the countermeasure to a documented default.

## The back-feed warning, and what the datasheet says about it

`DESIGN.md`: feeding 5 V into header pin 2 or 4 while the host provides
VBUS back-feeds the host's port through the board's fuse.

The Pi 4 datasheet does not draw that path. **Table 2, page 7** gives the
absolute maximum for `VIN`, the 5 V input, as -0.5 V to 6.0 V, and notes
that `VDD_IO`, the GPIO bank voltage, is tied to the on-board 3.3 V rail.
Neither statement describes the connection between the USB-C VBUS and the
header's 5 V pins.

**The Pi 3B+ reduced schematic does show that topology** for its own
board: the micro USB input passes through a fuse and a transient clamp,
and the header's 5 V pins sit on the same net downstream of it. The Pi 4
is a different board and no schematic for it has been read, so **carrying
that across is `inferred`**, and it is worth marking because the
conclusion drawn from it, that a second supply is dangerous rather than
redundant, is a safety claim.

It is almost certainly right. It is not currently cited, and the honest
form is to say which.

## The board revision question, which is free to answer and has not been

`DESIGN.md`: a cable with an e-marker chip does not power a revision 1.1
Pi 4 at all, because of the shared CC pull-down on that revision.

**The datasheet says nothing about board revisions and nothing about the
CC pull-down.** Release 1.1 of March 2024 describes the product as one
thing. So that claim is sourced from neither of the documents this project
has, and it is the claim most likely to waste an afternoon, because its
symptom is a board that simply does not turn on.

**And it is checkable in one command**, on the board, with no instrument:
the `Revision` field in `/proc/cpuinfo` identifies the board revision.
Knowing whether this bench's Pi 4 is a 1.1 or a 1.2 turns "use a plain
cable" from a precaution into either a requirement or a non-issue. That
belongs in the bring-up notes ahead of everything else, because it decides
whether the project can start.

## The keyboard, and the other current limit

`DESIGN.md` grabs a physical keyboard on a USB-A port with `EVIOCGRAB`.
**Section 5.3, page 11** limits downstream current to roughly 1.1 A in
aggregate across the four type-A sockets.

That is not a constraint here, since a keyboard draws tens of milliamps.
It is worth recording for the opposite reason: **this is the one place in
the project where a number is comfortable**, and knowing which limits are
tight and which are not is most of what a hardware page is for. The tight
one is the input supply. The downstream one has three orders of magnitude
of room.

## The BCM2711 peripherals document is read, and it has no USB chapter

**Source: Raspberry Pi Ltd, "BCM2711 ARM Peripherals", release 4,
18 January 2022, build-date 2022-01-18, githash `cfcff44-clean`.** Read
Friday 9 October 2026, from the URL Joseph supplied that day, which
redirects twice through `pip.raspberrypi.com` to `pip-assets`.

This was the document expected to settle whether the USB-C port's
controller is `dwc2` and dual-role capable. **It cannot, because it does
not mention USB.**

### What the table of contents contains

Thirteen chapters, pages 2 and 3: Introduction, Auxiliaries (UART1, SPI1
and SPI2), BSC, DMA Controller, General Purpose I/O, Interrupts, PCM/I2S
Audio, Pulse Width Modulator, SPI, System Timer, UART, Timer (ARM side),
and ARM Mailboxes. The table ends at section 13.2 on page 163.

**No USB chapter. No `dwc2`. No DWC_OTG. No XHCI.** The same absence as
in the Pi 4 datasheet, which describes the USB-C connector only as a
power input.

### So the dual-role claim is now sourced from neither Raspberry Pi document

| Document | What it says about the USB-C port's controller |
|---|---|
| Raspberry Pi 4 Model B datasheet, release 1.1 | nothing; the connector is "power" in section 4.1 |
| **BCM2711 ARM Peripherals, release 4** | **nothing; there is no USB chapter** |
| the kernel's device tree for the Pi 4 | `dwc2` at `fe980000`, which is where this project's `DESIGN.md` got it |

**That is the fifth instance of the pattern this bench has been
cataloguing**, after the ILI9486, the FT5406, the BCM43455 and this same
port's earlier entry: **the Linux driver names the hardware and the
manufacturer's documents do not.** It is reliable, it has worked for every
gadget this project has built, and it is not a citation, and it now cannot
become one from any Raspberry Pi document that exists.

**The honest evidence level for "the USB-C port is `dwc2` in peripheral
mode" is `measured`.** The gadget enumerates on a host. That is stronger
than a datasheet sentence would have been and it is a different kind of
thing, and the page should say which.

### Two things the colophon says that matter elsewhere

**The document is derived.** Its own first sentence: "BCM2711 ARM
Peripherals, based in large part on the earlier BCM2835 ARM Peripherals
documentation." That is Raspberry Pi stating in writing the thing
[project 9's hardware page](../../09-kernel-debug/docs/hardware.md) had
to argue for: that the BCM2835 document is the right one to read for the
peripheral block across the whole family, with only the base address
moving.

**And two of its four releases are corrections of exactly the kind this
bench watches for.** Release 2 of 24 September 2020 "Corrected GPIO base
address". Release 4 of 18 January 2022 "Updated GPIO_PUP_PDN_CNTRL register
reset values" and "Updated UART GPIO mapping table". So a reader of
release 1 or 3 would have the wrong GPIO base address, or the wrong
default pull values, or the wrong UART pin table, and would not know it.
**Cite the release.** The same rule the Pi 4 datasheet taught on Wednesday
7 October 2026, from the same vendor, a second time.

### What this page's open table now says

| Document | Status |
|---|---|
| ~~BCM2711 peripherals~~ | **read, and silent on the question.** The USB-C controller's identity stays `measured`, from the gadget enumerating, and there is no Raspberry Pi document left that could change that |
| a Raspberry Pi 4 schematic | still the only thing that would settle the VBUS to header 5 V topology behind the back-feed warning |
| the USB Type-C specification | still the only thing that would turn the revision 1.1 cable warning into an explanation |

**None of those blocks the project**, which was true before and is true
now. What changed is that one of the three has gone from "unread" to
"read and empty", which is a better state to be in: a reader no longer
has to wonder whether the answer is in there.

## Still `NOT READ`

| Document | What it would settle |
|---|---|
| ~~BCM2711 peripherals~~ | **read.** It contains no USB chapter, so it cannot settle this and nothing from Raspberry Pi can; see the section above |
| a Raspberry Pi 4 schematic | the VBUS to header 5 V topology, which the back-feed warning depends on and which is currently carried across from the Pi 3B+ |
| the USB Type-C specification | why a shared CC pull-down breaks e-marked cables, which would turn the revision 1.1 warning into an explanation rather than a rule |

**None of those blocks the project.** The one thing that could block it is
a revision 1.1 board and an e-marked cable, and that is answered by
`/proc/cpuinfo` and a look at the cable rather than by any of these.
