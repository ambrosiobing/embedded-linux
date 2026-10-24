# Evidence, Project 5

This file said "Empty on purpose" until Saturday 17 October 2026, and
by then the directory held nine files. It was true when it was written
on Saturday 3 October 2026, when this project had neither a kernel tree
nor a board. Nothing in this repository reads a sentence, which is the
third document in this project to have needed the same correction in
one day.

## What is here

| File | Criterion | Taken |
|---|---|---|
| `fifo-rates-2026-10-09.csv` and `.md` | 5, the hardware FIFO drained on a watermark interrupt | Friday 9 October 2026 |
| `events-2026-10-16.csv` and `.md` | 6, the three event types through the character device | Friday 16 October 2026, while `DATA_FORMAT` still held `0xaf`, so its interrupt polarity was inverted; it proved the path and little else |
| `events-singletap-2026-10-16.csv` and `.md` | 6, single tap alone, after the registers were put right by hand | Friday 16 October 2026 |
| `events-doubletap-2026-10-16.csv` and `.md` | 6, double tap, the quiet one | Friday 16 October 2026 |
| `fifo-watermark-2026-10-17.csv` and `.md` | 5, and a defect behind it: the part interrupts once per sample unless userspace writes `buffer/watermark` | Saturday 17 October 2026 |
| `paths-2026-10-17.csv` and `.md` | the design's three-path comparison, all three arms on one card, the duplicate experiment at 53.2 per cent against a 5.5 floor, and the run that measured the triggered path while reporting the FIFO | Saturday 17 October 2026 |
| `drivers-ab-2026-10-17.csv` and `.md` | 7, the same part under both drivers, eleven minutes apart, and the 0.141 per cent their scales disagree by | Saturday 17 October 2026 |
| `triggered-2026-10-17.csv` and `.md` | 11, the triggered buffer, one scan per fire, timestamped by the core | Saturday 17 October 2026, on the first card to carry the corrected probe |
| `supply-ruled-out-2026-10-24.txt` | no criterion, and it closes the entry below. The harness measured good BEFORE the scan this time, supply and return present at the module's own rows and not the same net, and the part still answered nothing. A seven-sensor shield had answered on the same four header pins twenty minutes earlier, which is the first positive control this bench has had. Sixth `-121`. What remains is the six friction contacts and nothing else | Saturday 24 October 2026 |
| `card-overlay-states-2026-10-21.txt` | no criterion, and it is a rescue rather than a measurement. Three states of the card's `config.txt`, read off the boot partition on Saturday 24 October 2026 before the card was overwritten with project 10's image. They differ on one line: the I2C overlay at 10:47, the SPI overlay at 11:23, the I2C overlay again at 11:46 on Tuesday 21 October 2026. The image was archived; these hand edits were in no archive. The value was in the modification times, which a `cp` does not carry, so the file records them as text | read Saturday 24 October 2026, describing Tuesday 21 October 2026 |
| `supply-fault-2026-10-21.csv` and `.md` | no criterion. Why the part answered nothing on either bus: its `VCC` and `GND` were the same net, at ground. Seventeen GPIO readings taken with no instrument but the Pi's own lines, four of which are marked in the page as having been over-read | Tuesday 21 October 2026 |

## What is still missing, in criterion order

- the build log showing three `.ko` produced, for criterion 1. The
  modules have been built four times since; what is not here is the log
- `dmesg` from a probe that found `DEVID` `0xe5` and from one that did
  not, for criterion 2. Both have been read on the bench and quoted in
  the README; neither is in a file here
- the four sysfs reads with the board flat, for criterion 3, for the
  same reason
- `./go ksym -f adxl345` and `./go kconfig -f adxl345`, for criterion 8.
  Both ran on Saturday 17 October 2026 and both are quoted in
  `JOURNAL.md` sections 24 and 25; their output is not in a file here

The pattern in that list is worth naming rather than leaving to be
noticed: this project has measured far more than it has filed. A figure
quoted in a journal entry is a record; a figure in a file beside its
own arithmetic is evidence somebody else can check.
