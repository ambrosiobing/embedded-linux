# FIFO path, Friday 9 October 2026, 21:45 local

Two runs of Project 10's `iio-rate fifo` against Project 5's driver on
the Raspberry Pi 3B+, image `6d41adc`, bus at 100 kHz, `INT1` on GPIO23
level high. The rows in `fifo-rates-2026-10-09.csv` are
`/var/lib/bench/iio/rates.csv` as the board wrote them; the timestamps
are UTC from the board's clock, 19:45 UTC being 21:45 in the bench's
time zone.

| asked | watermark | samples in 10 s | interrupts | per second | expected | ratio | timestamp spread |
|---|---|---|---|---|---|---|---|
| 100 Hz | 24 | 960 | 40 | 4.00 | 4.17 | 1.0 | 1.7 ms |
| 100 Hz | 8 | 960 | 120 | 12.00 | 12.50 | 1.0 | 0.96 ms |

Both runs were asked for five seconds with `-d 5` and ran ten, because
the tool's usage line promised the option and nothing read it; fixed
the same night, after these rows. The ten seconds are real and the
rows say so.

**What the two rows prove.** Samples arrive at the configured rate
through the part's own FIFO. The interrupt count follows the watermark
written through `buffer/watermark`, three times as many at 8 as at 24,
which is the driver's `set_watermark` hook reaching the part. The
timestamp spread is under two milliseconds, which is each batch spread
back from the interrupt at the period; on the image before this one it
was 49 and 27 milliseconds, every sample in a batch carrying the
interrupt time. Those earlier two rows were on the card that was
reflashed and are recorded only in journal section 13.

**What they do not prove.** Nothing here is a latency measurement: the
timestamps are assigned by the driver from the interrupt time and the
configured rate, and the tool labels the column so. The 96 against 100
samples per second is the part's own oscillator against the board's
clock, and the datasheet's tolerance on the output data rate is the
place to read that number against.
