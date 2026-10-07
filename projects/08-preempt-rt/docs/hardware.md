# Hardware sources for project 8

[docs/DESIGN.md](DESIGN.md) carries the architecture, the schematic, the
pin reasoning and the cancellation argument, and
[docs/METHOD.md](METHOD.md) carries the arithmetic. **This page does not
repeat any of that.** It records what the instrument's datasheet says,
which rows of the design it confirms, and **the one quantity a timing lab
needs most that the datasheet does not specify at all.**

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| MCC 118 datasheet, Measurement Computing, `DS-MCC-118` | `datasheet` | **read Wednesday 7 October 2026**, pages 1 to 4 |
| Raspberry Pi 4 Model B datasheet, release 1.1 | `datasheet` | read; in [docs/HARDWARE.md](../../../docs/HARDWARE.md) |
| MCC DAQ HAT library documentation, C API reference | `vendor page` | **read Wednesday 7 October 2026** |

**Provenance, stated because it is not ideal.** `files.digilent.com`
returned 403 to two attempts on Wednesday 7 October 2026, so the datasheet
was read from a copy served by a distributor. The document identifies
itself as the MCC 118 datasheet from Measurement Computing and carries no
revision number or date on the pages read, which is itself worth knowing:
there is no way to tell from it whether a newer version says something
different. Its own first line is "All specifications are subject to change
without notice."

## Every "do not touch" row in the design is now sourced

`DESIGN.md`'s schematic marks four groups of header pins as belonging to
the HAT, derived at the time from the library's behaviour and from
elimination. The datasheet's **Interface** section, page 4, states them
outright.

| What the HAT uses | Datasheet | Header pins | `DESIGN.md` | Agreement |
|---|---|---|---|---|
| SPI | GPIO 8, 9, 10, 11 | 24, 21, 19, 23 | CE0, MISO, MOSI, SCLK | yes |
| HAT ID EEPROM | `ID_SD`, `ID_SC` | 27, 28 | the same | yes |
| board address | GPIO 12, 13, 26 | 32, 33, 37 | A0, A1, A2 | yes |
| power | 3.3 V supply | | taken from the header | yes |

**And GPIO20 is confirmed free by the vendor rather than by elimination.**
`DESIGN.md` has a whole table explaining why the square wave goes on
GPIO20 and not on any other pin. That reasoning was sound and it was
reasoning. The datasheet's list of pins used does not contain GPIO20, so
the conclusion now has a source as well as an argument.

The datasheet adds three details the design did not have: the HAT is an
SPI **slave** on chip select **CE0**, it runs **SPI mode 1**, and the SPI
clock is **10 MHz maximum**.

## The number this project needs most, and the datasheet does not state it

This is the finding, and it is an absence.

**The MCC 118 is this project's independent time reference.** The whole
architecture exists because `cyclictest` measures the kernel on the
kernel's own clock, and an external instrument sampling on its own clock
is the only way to get a second opinion. `DESIGN.md` says so in its first
paragraphs.

The datasheet specifies the amplitude side to four significant figures:
gain error 0.098 per cent of reading maximum, offset error 11 mV maximum,
absolute accuracy at full scale 20.8 mV, gain temperature coefficient
0.016 per cent per degree, offset temperature coefficient 0.87 mV per
degree, noise 5 counts and 0.76 LSB rms.

For the **time base** it gives a range and a shape and no accuracy:

| Quantity | Datasheet |
|---|---|
| internal scan clock, rate range | 0.004 S/s to 100 kS/s, software selectable |
| external scan clock, maximum | 100 kS/s |
| conversion time per channel | 8 microseconds |
| clock pulse width, external input | 400 ns minimum |
| **frequency accuracy of the internal scan clock** | **not stated** |
| **stability or drift of the internal scan clock** | **not stated** |

**What follows, precisely.** An interval measured by this instrument is
exact in **samples** and uncertain in **seconds** by an unspecified
factor. So:

- **the comparison survives.** Two kernels measured on the same instrument
  within the same session are scaled by the same unknown factor, and the
  ratio between them, which is what this project reports, is unaffected.
  That is the same cancellation argument `DESIGN.md` already makes for the
  GPIO write cost, applied to the time base instead of to the offset
- **an absolute latency in microseconds does not survive**, strictly. Any
  number this project prints in seconds inherits an uncertainty the vendor
  declines to bound
- **the remedy exists and is not on this bench.** The `CLK` terminal is
  bidirectional and accepts an external scan clock up to 100 kS/s. Drive
  it from a source whose accuracy is known and the time base becomes
  specified. That needs a signal generator, which this bench does not have

**This belongs in the acceptance table as a named limit rather than as
silence**, in the same way that the missing voltmeter is named in project
3. A timing lab whose time base has no stated accuracy is still a good
timing lab; it is a comparative one.

## What the datasheet does say about the edge, and it is good news for the RC

`DESIGN.md` adds an optional `R = 1 kohm` and `C = 10 nF` so that the edge
spans two or three samples and interpolation can recover sub-sample
timing. Those values were chosen before the datasheet was read. Three rows
of it say the choice was right.

| Datasheet | Value | What it means for the RC |
|---|---|---|
| input bandwidth, small signal, -3 dB | 150 kHz | the RC's corner is about 16 kHz, roughly ten times lower, so **the RC dominates and the instrument's own front end is not a confound** |
| input impedance | 1 Mohm | the 1 kohm series resistor loses about 0.1 per cent of amplitude into it, which is nothing, and the design's divider is harmless |
| crosstalk, adjacent channels, DC to 10 kHz | -75 dB | irrelevant here, because only one channel is used, which is the next section |

**And without the RC the design's own claim holds too.** 150 kHz of
bandwidth spreads a step over roughly 2 microseconds, which is still well
inside one 10 microsecond sample, so "without them the edge is faster than
one sample" remains true as written.

## One channel, and the datasheet explains why that must stay true

Two lines from page 4, which belong together:

- **"Sampling mode: 1 A/D conversion for each configured channel per
  clock"**
- **"Conversion time, per channel: 8 microseconds"**

and from the same page, throughput on a Raspberry Pi 2, 3 or 4 is up to
100 kS/s for a single board.

**That 100 kS/s is the aggregate, across however many channels are
configured.** This project configures CH0 alone and therefore gets the
full 100 kS/s on it, 10 microseconds between samples, which is the number
every piece of arithmetic in `METHOD.md` rests on.

**Configure a second channel and that number halves**, silently, to 20
microseconds per sample on CH0. Nothing fails. The capture succeeds, the
edges are found, the interpolation runs, and every interval comes out with
twice the quantisation it had before. **This is exactly the failure shape
this repository keeps cataloguing**: a change that produces plausible
numbers instead of an error.

So: **CH0 only, and a run that configures more than one channel should be
voided the way an overrun is.** `rt-capture` already checks both overrun
flags per chunk and exits non-zero; this is a check of the same family and
it is cheaper, because the channel count is known before the scan starts.

## The amplitude accuracy turns into a timing offset, and then cancels

Worth doing the arithmetic rather than waving at it.

The datasheet's absolute accuracy at full scale is 20.8 mV. The threshold
crossing of the filtered edge is found by interpolation, so a 20.8 mV
error in the voltage shifts the apparent crossing time by that error
divided by the slope. With a 3.3 V edge and about 10 microseconds of rise,
the slope near the middle is of the order of 0.2 V per microsecond, so
20.8 mV is **of the order of a hundred nanoseconds**.

Against a 10 microsecond sample period that is one per cent of one sample.
**And it is the same offset on both edges of an interval**, because it is a
property of the instrument rather than of the edge, so it subtracts out in
exactly the way `DESIGN.md` already argues for the GPIO write cost. What
survives is its variation, and the datasheet bounds that too: offset
temperature coefficient 0.87 mV per degree, which over the temperature
swing of a desk is a fraction of the 20.8 mV.

The datasheet also asks for a **one minute minimum warm-up**. Nothing in
the run protocol mentions it. For a comparative measurement it hardly
matters, for the reason just given; it costs nothing to add to the
protocol and it removes a question.

## The hazard check, which comes out clean

The bench's "before power" rule asks every time what is about to be driven
into what. For this pairing the answer is comfortable, and it is worth
writing down once so nobody has to re-derive it.

| Direction | Limit | Actual | Margin |
|---|---|---|---|
| Pi GPIO20 into CH0 | input range +/-10 V, absolute maximum +/-25 V power on or off | 3.3 V | large |
| Pi GPIO into `TRIG`, if ever used | input high threshold 2.64 V minimum, absolute maximum 5.5 V | Pi `V_OH` is at least `VDD_IO - 0.4` = 2.9 V at 2 mA | **0.26 V**, adequate and thin |
| `CLK` output into a Pi input, if ever used | output high 2.65 V minimum at 3 mA | Pi `V_IH` minimum is 2.0 V | 0.65 V |
| 3.3 V rail | 35 mA typical, 55 mA maximum | | |

The second row is the only one worth remembering. **A 3.3 V Raspberry Pi
output into this instrument's trigger input has about a quarter of a volt
of margin**, which works and is not generous, and would not survive a
series resistor or a long lead. The Pi figure comes from the Pi 4
datasheet Table 3, page 8, and the MCC figure from this datasheet page 4,
so this is a check across two documents rather than an assumption.

## Three instruments, three temperature ranges

| Thing | Operating temperature |
|---|---|
| nRF PPK2 | 5 to 40 C |
| **MCC 118** | **0 to 55 C** |
| Raspberry Pi 3B+ and Pi 4 | 0 to 50 C |
| NanoPi NEO Air | -20 to 70 C |

The MCC 118 is the widest of the three instruments and still narrower than
one of the boards. Storage is -40 to 85 C, humidity 0 to 90 per cent
non-condensing, and it is 65 by 56.5 by 12 mm, which is the HAT outline
plus the screw terminals.

## What the datasheet does not explain, said plainly

[The README](../README.md) records an open result: `ext_edges` never
reaches the expected 30000, with sixteen sound rows between 29984 and
29997, and no cause offered because none was investigated.

**The datasheet does not explain it, and it does rule things out.**

| Candidate | Status after reading the datasheet |
|---|---|
| a buffer overrun losing samples | **ruled out by the existing protocol**: `rt-capture` checks both overrun flags per chunk and voids the run, and no run was voided |
| the FIFO being too small for the read pattern | the data FIFO is 7168 samples, which is 71.7 ms at 100 kS/s, so a servicing gap longer than that loses samples. The overrun flags are what detect it, and they did not fire |
| an amplitude or range problem missing an edge | **ruled out**: a 3.3 V signal in a +/-10 V range with 20.8 mV of absolute accuracy and 5 counts of noise is nowhere near a threshold |
| a scan clock slightly off nominal | **cannot be ruled out, and cannot be checked**, because the datasheet states no accuracy for it. See above |

**No mechanism is offered here either**, and that is deliberate. This
repository has already paid once for a mechanism invented in the same
voice as an observation. What has changed is that three of the four
candidates are now closed with a citation, and the fourth is closed off
not because it is unlikely but because the vendor does not publish the
number that would settle it.

## Still `NOT READ`

| Document | What it would settle |
|---|---|
| a dated revision of this datasheet | whether anything above has changed; the copy read carries no revision |

## The library answers half the time base question, and names the two overruns

**Source: the MCC DAQ HAT library documentation, C API reference.** Read
Wednesday 7 October 2026.

**There is a function for the actual rate.** `mcc118_a_in_scan_actual_rate()`
calculates the achievable sampling rate and, in the documentation's own
words, "will return the actual rate for a requested channel count and
rate".

**Read what that is carefully, because it is half of what this project
wants.** It is a **calculation**, not a measurement: it tells you the
nominal rate the hardware will use when you ask for 100 kS/s with one
channel, which may not be exactly 100000. It does not say how accurate
that nominal rate is in seconds, and the datasheet still does not either.

| Question | Answered by |
|---|---|
| what nominal rate will the board actually use | `mcc118_a_in_scan_actual_rate()` |
| how close is that nominal rate to the truth | **nothing available here** |

**And it is free to use, which makes it worth doing now.** If `rt-capture`
requests 100 kS/s and converts sample indices to seconds by dividing by
100000, then any difference between the requested and the achievable rate
is a **systematic scale error on every interval this project reports**.
Calling the function and dividing by what it returns removes that error
entirely, costs one line, and is the kind of thing that is obvious once
somebody reads the API and invisible before.

**The two overrun flags now have names and a distinction.** `rt-capture`
checks both, as the README says. The library defines them as:

| Flag | What the documentation says it means | Which buffer |
|---|---|---|
| `STATUS_HW_OVERRUN`, `0x0001` | "The device scan buffer was not read fast enough and data was lost" | the board's own FIFO, 7168 samples, 71.7 ms at 100 kS/s |
| `STATUS_BUFFER_OVERRUN`, `0x0002` | "The thread scan buffer was not read by the user fast enough and data was lost" | the library's host-side buffer |

**Those are two different failures in two different places**, and the
distinction is useful: a hardware overrun points at SPI servicing and at
whatever is holding the CPU, while a buffer overrun points at the capture
program's own read loop. `mcc118_a_in_scan_read()` returns them ORed
together with `STATUS_TRIGGERED` and `STATUS_RUNNING`.

Nothing here changes the conclusion about the edge shortfall. It does
narrow it: if an overrun had happened, the flags would say which of the
two it was, and neither fired.
