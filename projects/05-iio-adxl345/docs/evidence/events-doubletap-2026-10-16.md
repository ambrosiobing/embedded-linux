# Double tap alone, and what it says about the single tap run

Friday 16 October 2026, the third event run, taken with only double
tap enabled on the same wiring and the same 3 g threshold as the single
tap run in `events-singletap-2026-10-16.md`.

17 events in 20 seconds, in `events-doubletap-2026-10-16.csv`.

## One pair, one event

The gaps between consecutive events are 1.14, 1.05, 1.01, 0.93, 1.01,
0.99, 1.01, 1.17, 1.08, 1.20, 1.06, 1.09, 1.17, 1.13, 1.09 and 2.35
seconds. That is the hand: a pair of knocks about once a second, and
one event for each pair.

**Nothing clusters.** The single tap run on the same mount produced two
to four events per knock, milliseconds apart, because the breadboard
rings and every crossing of the threshold that satisfies `DUR` is a tap
by the part's definition. Double tap does not do that, and the reason
is in what it asks for: a tap, then `Latent` of quiet, then a second
tap inside `Window`. Ringing inside the latency window is not a second
tap, and a third knock arriving inside the same window cannot make a
second event because the sequence has already completed.

So on a mechanically noisy mount **the double tap path is the better
behaved of the two**, which is the opposite of what one would guess
from it being the more complicated gesture. It is worth saying plainly
because an application choosing between them on this bench should
choose from the measurement rather than from the name.

## The parameters behind both numbers

From the probe defaults, which `bench-adxl345.h` carries with the
datasheet page for each:

| Register | Value | Meaning |
|---|---|---|
| `THRESH_TAP` | 0x30 | 3 g, at 62.5 mg a count |
| `DUR` | 0x10 | 10 ms, the longest a tap may stay above the threshold |
| `Latent` | 0x50 | 100 ms of quiet after the first tap |
| `Window` | 0xf0 | 300 ms in which the second tap is accepted |

Three of those four are this bench's choice rather than the
datasheet's, and the clustering above is the first measurement that
says anything about whether they are good ones.
