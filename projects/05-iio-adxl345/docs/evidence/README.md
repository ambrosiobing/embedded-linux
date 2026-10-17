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
| `paths-2026-10-17.csv` and `.md` | the design's three-path comparison, two arms of it: 94.00 per cent reader CPU polled against 0.10 batched | Saturday 17 October 2026 |
| `drivers-ab-2026-10-17.csv` and `.md` | 7, the same part under both drivers, eleven minutes apart, and the 0.141 per cent their scales disagree by | Saturday 17 October 2026 |
| `triggered-2026-10-17.csv` and `.md` | 11, the triggered buffer, one scan per fire, timestamped by the core | Saturday 17 October 2026, on the first card to carry the corrected probe |

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
