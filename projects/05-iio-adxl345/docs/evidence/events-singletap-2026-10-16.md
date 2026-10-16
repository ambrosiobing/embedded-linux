# Single tap alone, Friday 16 October 2026, after the part was put right

The second event run of the evening, and the one to read. The first is
in `events-2026-10-16.md` and was taken while `DATA_FORMAT` held
`0xaf`, so its interrupt polarity was inverted relative to the device
tree and both taps were armed at once; it proved the path and little
else.

This run was taken after the registers had been written by hand to what
the fixed probe writes, with only single tap enabled:

    echo 0 > events/in_accel_x\|y\|z_gesture_doubletap_en
    echo 0 > events/in_accel_x\|y\|z_thresh_falling_en
    echo 1 > events/in_accel_x\|y\|z_gesture_singletap_en
    iio-events bench-adxl345 -t 20

33 events in 20 seconds, in
`events-singletap-2026-10-16.csv`, from of the order of a dozen knocks
on the bench surface beside the board.

## One knock is not one event, and the timestamps say so

Sorting the 33 by the gaps between them gives about fourteen clusters.
Inside a cluster the events are one to seven milliseconds apart; the
clusters themselves are a second or more apart, which is the hand.

| Cluster | Events | Span |
|---|---|---|
| 1792186892441 to 892448 | 4 | 6.8 ms |
| 1792186891232 to 891240 | 3 | 8.0 ms |
| 1792186889920 to 889926 | 2 | 6.4 ms |
| several | 1 | none |

**That is mechanical, not a driver fault.** A knock on a bench rings:
the breakout sits in a breadboard on jumper wire, the acceleration
crosses the 3 g threshold several times as it decays, and each crossing
that satisfies `DUR` is a tap by the part's definition. The ADXL345 has
no inter-tap suppression for single taps; the suppress bit in
`TAP_AXES` only governs what counts as a double tap.

So a consumer of these events either wants every crossing, or has to
impose its own refractory period. Writing that down matters more than
the count: an application that treats one event as one tap will see
three.

## What this run also established

**The interrupt storm was real and is gone.** Before `INT_ENABLE` was
cleared, the line at `/proc/interrupts` gained about 1,100 counts a
second with nothing happening, because data ready, activity and
inactivity were enabled by a session nobody remembers and the handler
does not clear data ready. After clearing it, five seconds passed with
the count unchanged. Both numbers are in journal section 19.

**And the event path is confirmed with the polarity the overlay
declares**, which the first run could not claim.
