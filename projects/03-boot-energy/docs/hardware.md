# Hardware sources for project 3

[docs/DESIGN.md](DESIGN.md) carries the architecture, the schematic, the
ownership table, the discard rules and the reasoning behind source meter
mode. **This page does not repeat any of that.** It records what the
instrument's own document says, which turned out to include one number
that `DESIGN.md` had wrong.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| PPK2 user guide, v1.0.1, document 4461_012 | `datasheet` | **read Wednesday 7 October 2026**, sections 6 and 8 |
| Nordic's online PPK2 user guide, HTML | `vendor page` | read the same day; see the warning below |
| FriendlyELEC wiki, NanoPi NEO Air | `vendor page` | read; worked through in [project 2's page](../../02-neo-air-mainline/docs/hardware.md) |
| PPK2 hardware files and schematic | `schematic` | **`NOT READ`** |

**A note on provenance, because it matters here.** The PDF was read from a
copy served by a distributor rather than from `nordicsemi.com` directly.
The document identifies itself as *Power Profiler Kit II v1.0.1 User
Guide, 4461_012*, and its page numbers are cited below so that any copy
can be checked against these claims. If a later revision changes a figure,
that is exactly what the citation is for.

## The warning about the online guide, first, because it nearly cost this

Nordic publishes the same guide as HTML pages and as a PDF. **They are not
the same document for the purposes of this project.**

The HTML overview page gives: two modes, 0.8 V to 5.0 V variable supply,
500 nA to 1 A, 100 kS/s, resolution to 0.2 microamp, accuracy "better than
plus or minus 20 per cent (average currents measurement)", an eight pin
digital port. The HTML logic port page gives three wiring instructions and
nothing else: no VCC range, no thresholds, no sampling rate.

**Every single figure that constrains this experiment is in the PDF and in
none of those pages.** The source meter current limit, the logic port
voltage range, the per range accuracy, the digital sampling rate, the host
USB requirement and the instrument's own temperature range are all in
section 8 of the PDF. A bench that reads the overview page and stops has
read the brochure.

That is the same shape as the Raspberry Pi 3B+ product brief, recorded in
[docs/HARDWARE.md](../../../docs/HARDWARE.md), and it is becoming the most
reliable pattern on this bench: **the document that is easiest to reach is
the one that says least, and it never says so.**

## The correction: 600 mA, not 1 A

`DESIGN.md` said, from the day it was written, that the PPK2 "sources at
most 1 A". **Table 7, page 16** gives the maximum admissible DUT current
as two different numbers for the two modes:

| Mode | Maximum DUT current | Page |
|---|---|---|
| ampere meter, continuous | 1 A | 16 |
| **source meter** | **600 mA** | 16 |

This project uses source meter mode, for the reason `DESIGN.md` gives and
which is still right: only source meter mode can switch the rail, and a
boot measurement that cannot define `t = 0` is not a boot measurement.
**So the mode was chosen correctly and then costed incorrectly.** The
headroom is forty per cent smaller than the design said.

**This is the second time on this bench that a number was true when it was
written and nobody re-read it against the thing it described.** The first
was project 8's claim about GPIO write cost. The shape is identical: a
figure stated once, carried into four documents, and never checked against
the document it came from.

## The whole supply chain, which is longer than the schematic shows

`DESIGN.md`'s schematic starts at the PPK2's `VOUT`. The user guide shows
there are two more links upstream of that, and they matter.

**Page 12, section 6.5:** in source meter mode the host's USB power source
has to support the DUT's maximum current **in addition to approximately
50 mA for the PPK2 circuitry**. **Page 9** adds the part that matters
most: the PPK2 has a **second** micro USB socket, and above 400 mA in
source meter mode it wants a supply of 1 A or more on it. That is the next
section.

```
   the laptop's USB port  --->  [ USB DATA/POWER ]   500 mA on USB 2.0
                                       |             900 mA on USB 3.0
                                       |             always connected  p.9
   a 1 A or more supply   --->  [ USB POWER ONLY ]
                                       |             needed in source
                                       |             meter mode over
                                       v             400 mA           p.9
                             +--------------------+
                             |       PPK2         |  about 50 mA of its
                             |                    |  own               p.12
                             |   source meter     |  VDD_DUT 0.8 to
                             |                    |  5.0 V    Table 6, p.16
                             |                    |  max DUT  600 mA
                             |             VOUT   o--+        Table 7, p.16
                             +--------------------+  |
                                                     | two jumper leads,
                                                     | tens of mV at a few
                                                     | hundred mA
                                                     v
                                          NanoPi NEO Air   4.7 to 5.6 V
                                                  vendor says 5 V / 2 A

   the narrowest point is whichever of these is reached first, and
   nothing in the rig reports which one it was
```

**Read that bottom line twice.** Four separate limits, at four different
places, and the instrument reports none of them. It reports current. A rig
that hits any one of them produces a plausible looking current trace.

**So the honest statement of what this project measures** is: the energy a
NEO Air draws while booting **from this particular supply**, whose
regulation under a step load is not characterised, at a voltage assumed
rather than measured, with the board's lower limit 300 mV away. That is
still a useful measurement, and it is a different claim from "the boot
energy of a NanoPi NEO Air".

## The second USB connector, which the bench found the hard way and the guide states plainly

**The PPK2 has two micro USB sockets, and they do different jobs.**
Table 1, page 9:

| Connector | What the guide says it is for |
|---|---|
| `USB DATA/POWER` | power and communication with the PPK2; **must always be connected** |
| `USB POWER ONLY` | extra power to the PPK2, "**Only needed in Source Meter mode (> 400 mA)**" |
| `VIN` | external power input, **only** used for ampere meter mode |
| `VOUT`, `GND` | the output to the DUT |
| `LOGIC PORT` | `VCC`, `GND` and `D0` to `D7` |

And in prose on the same page, section 5.1.2: if the PPK2 is in source
meter mode and the DUT can draw more than 400 mA, an extra external USB
supply that can deliver **1 A or more** is recommended.

**This bench already knew, and knew it the expensive way.** Project 3's
own evidence file
[`evidence/logic-selftest.txt`](evidence/logic-selftest.txt) records at
line 87 that `USB POWER ONLY` is required in source meter mode above
400 mA and that **only `DATA/POWER` was ever connected, in that session
and every earlier one.** The current figures from those sessions were
withdrawn.
[Project 16's design](../../16-nbiot-tracker/docs/DESIGN.md) puts the rule
first rather than in a troubleshooting section, for exactly that reason.

**What the guide adds to what the bench had worked out.** The bench's
version was an observation from a line of evidence output. The guide gives
the threshold, 400 mA, the reason, the PPK2's own circuitry needs headroom
the data port cannot spare, and the remedy, a supply rated 1 A or more on
the second socket. So the rule stops being a superstition about cables and
becomes a number you can check a measurement against.

## The 1233 mA that was already withdrawn, now with a sharper reason

Journal entry 26 of this project records a measured peak of 1233 mA,
described there as "above the PPK2's 1 A rating", and concludes that the
peak "cannot be quoted as a property of the board at all". That conclusion
was right.

**It is now right for a stronger reason.** In source meter mode the limit
is not 1 A, it is **600 mA**. The measured peak was not 23 per cent over
the admissible current; it was more than double it, and it was taken with
only one USB socket connected on a rig whose guide says to connect two
above 400 mA. Three separate reasons to discard one number, where the
journal had one.

**The useful general form**, because this will happen again: when a
measurement is withdrawn for one reason and the instrument's document is
read afterwards, **check whether the other reasons were there too.** A
number discarded for the wrong reason is still discarded, and the right
reason is what stops the next measurement repeating it.

## What the accuracy actually is, which is better than recorded

[docs/HARDWARE.md](../../../docs/HARDWARE.md) has carried "accuracy better
than plus or minus 20 per cent" since the LED currents were measured, from
Nordic's overview page. **Table 9, page 17** of the guide is more specific
and kinder.

| Current range | Accuracy | Offset | Resolution, Table 8 p.16 |
|---|---|---|---|
| 100 nA to 50 microamp | 10 per cent | 2 per cent | 0.2 microamp |
| 50 to 500 microamp | 10 per cent | 2 per cent | 0.5 microamp |
| 500 microamp to 5 mA | 10 per cent | 2 per cent | 5 microamp |
| 5 mA to 50 mA | 10 per cent | 2 per cent | 50 microamp |
| 50 mA to 1000 mA | 15 per cent | 5 per cent | 1000 microamp |

Every LED measurement on this bench, 2.94 mA to 15.98 mA, sits in the
500 microamp to 5 mA or the 5 mA to 50 mA range. **So those figures carry
10 per cent, not 20.** The shared reference has been corrected.

**And the row that matters to this project is the last one.** A boot
drawing a few hundred milliamps is measured in the 50 mA to 1000 mA range,
where accuracy is 15 per cent and the resolution step is a whole
milliamp. The energy figure inherits both. Writing a boot energy to four
significant figures would be the same error the LED table already made
once.

## The logic port, now properly cited

`DESIGN.md` says the logic port's `VCC` must be between 1.65 V and 5.5 V,
and it is right. Until now that was asserted without a page. **Table 6,
page 16** gives the logic port VCC as 1.65 V minimum, 5.5 V maximum. The
same table gives the external supply voltage as 0.8 V to 5.0 V, the micro
USB supply voltage as 4.5 V to 5.5 V, and the rated power as 5 W maximum.

So the self-test wiring in `DESIGN.md`, logic `VCC` to the NEO Air's
`SYS_3.3V`, is inside the specified range with room on both sides, which
is what you want from a reference.

## Digital inputs are slower than the console, and that changes what D2 means

**Section 8.3.4, page 17:** the digital input pins D0 to D7 are sampled at
100 kHz with a typical bandwidth of 50 kHz.

`DESIGN.md` uses `D2` to watch the console transmit line, described as
"idle high, falls on the first start bit". At 115200 baud one bit lasts
8.7 microseconds. One PPK2 sample lasts 10 microseconds. **A single
isolated start bit is shorter than the sampling interval**, so the
instrument cannot be relied on to catch it, and it certainly cannot
resolve individual bits.

What it can do, and what the project actually needs, is catch the
**burst**. A console banner is thousands of transitions over tens of
milliseconds, and the line's average level falls for the duration. So:

| Claim | Status |
|---|---|
| D2 marks that console output has begun | sound |
| the mark is good to roughly 10 microseconds | sound |
| D2 marks the first start bit specifically | **not supported** |
| D2 could decode the console | false, and nothing here asks it to |

On a boot timeline measured in seconds, a 10 microsecond quantisation is
irrelevant. **The point is not that the project is wrong. It is that the
sentence in `DESIGN.md` promised a resolution the instrument does not
have, and a reader checking it would have found the gap before the bench
did.**

## The instrument is the fussiest thing on the bench about its surroundings

**Tables 4 and 5, page 15.** Operating temperature 5 C to 40 C. Indoor use
only. Altitude up to 2000 m. Relative humidity up to 80 per cent at 31 C,
falling linearly to 50 per cent at 40 C. Pollution degree 2. Overvoltage
category 0 under EN 61010-1-2-030.

Worth putting beside the boards it measures:

| Thing | Operating temperature |
|---|---|
| nRF PPK2 | **5 to 40 C** |
| Raspberry Pi 3B+ and Pi 4 | 0 to 50 C |
| NanoPi NEO Air | -20 to 70 C |

**The instrument has the narrowest range of anything here.** Any
temperature related measurement on this bench is bounded by the thing
doing the measuring, not by the thing being measured.

And one instruction, quoted because it is an instruction: the guide says
not to use the PPK2 for measurements within measurement categories II, III
or IV, or on mains circuits or circuits derived from them. Nothing here
goes near mains. It is written down so that it stays that way when
somebody later wants to profile a mains powered adapter.

## Reflections, and the one change worth making

**The mode decision stands and the arithmetic around it did not.** Source
meter mode is still right: it is the only mode that can define the start
of a boot. What changed is that the price was never calculated. Choosing
the mode that can switch the rail also chose the mode with 600 mA instead
of 1 A, and put the host laptop's USB port into the supply path. Both of
those follow from the same sentence in the design and neither was written
next to it.

**The rewiring question, and the answer is no.** It would be possible to
move to ampere meter mode with an external 5 V supply, recovering the full
1 A and taking the laptop out of the path. **That should not be done**,
because it destroys the measurement: without the ability to switch the
rail there is no defined `t = 0`, and the quantity this project exists to
measure stops being defined. A limit you can state is better than a
limit you have removed by measuring something else.

**What to do instead, in order, cheapest first:**

1. report the peak current in every run summary, which the design already
   does, and **compare it to 600 mA explicitly** rather than to 1 A
2. use a USB 3.0 port on the host, so the upstream limit is 900 mA rather
   than 500 mA, and record which port was used
3. keep the supply leads short and say so in the report, since the drop is
   now a validity question and not only an accuracy one
4. buy a multimeter, which is the only thing that turns "the board was
   above 4.7 V" from an assumption into a measurement

## Still `NOT READ`

| Document | What it would settle |
|---|---|
| PPK2 hardware files and schematic | how well `VOUT` regulates under a sudden few hundred milliamp step, which is the one property this rig depends on and no table states |
| Allwinner H3 datasheet | the board's own inrush behaviour |

The first of those is the interesting one. Everything above is about
limits that are stated. The question nobody has a number for is what
happens to 5.0 V at the instant a quad core SoC starts.
