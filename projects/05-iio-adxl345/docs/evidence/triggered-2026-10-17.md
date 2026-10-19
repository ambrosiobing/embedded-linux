# The triggered path, Saturday 17 October 2026

The middle of the three paths `docs/DESIGN.md` has described since
before the driver was written, running on hardware for the first time.
The card carries the image built at `8d17d9b`, flashed the same
morning, which is also the first card to carry the probe that writes
whole registers.

## What was done

A sysfs trigger rather than an hrtimer one, and the reason is this
image rather than a preference. `kas/bench-adxl345.yml` sets
`BENCH_ADXL345_KERNEL` and not `BENCH_IIO_KERNEL`, so `iio.cfg` is not
in this build and `CONFIG_IIO_HRTIMER_TRIGGER` is absent; `iio-trigger
list` said so plainly, reporting that
`/sys/kernel/config/iio/triggers/hrtimer` does not exist.
`CONFIG_IIO_SYSFS_TRIGGER` is `=y` in `bench.cfg` for every image here
and was confirmed in the built `.config` by `./go kconfig -f adxl345`
earlier the same day.

    iio-trigger add sysfs 0
    echo sysfstrig0 > /sys/bus/iio/devices/iio:device0/trigger/current_trigger
    for f in in_accel_x_en in_accel_y_en in_accel_z_en in_timestamp_en; do
        echo 1 > /sys/bus/iio/devices/iio:device0/scan_elements/$f
    done
    echo 16 > /sys/bus/iio/devices/iio:device0/buffer/length
    echo 1  > /sys/bus/iio/devices/iio:device0/buffer/enable
    for i in 1 2 3 4 5; do iio-trigger fire sysfstrig0; sleep 1; done
    dd if=/dev/iio:device0 bs=16 count=5 2>/dev/null | od -x

**The buffer enabling at all is half the result.** The IIO core refuses
to enable a buffer in triggered mode with no trigger attached, so a
silent `echo 1 > buffer/enable` is the core agreeing that this device
declares `INDIO_BUFFER_TRIGGERED` and has a trigger.

## What came back

    0000000     fff6    0036    00f1    0000    9383    20f3    8b9c    184c
    0000020     fff6    0037    00f1    0000    551d    5d75    8b9c    184c
    0000040     fff6    0037    00f1    0000    dccf    99ff    8b9c    184c
    0000060     fff7    0037    00ef    0000    7783    d68c    8b9c    184c
    0000100     fff6    0036    00f2    0000    034d    131a    8b9d    184c

Sixteen bytes a scan: three signed 16-bit axes, two bytes of padding,
and a 64-bit timestamp aligned to 8, which is the layout the driver's
scan structure declares and `iio-decode`'s own test asserts.

| Scan | x | y | z | timestamp ns | delta |
|---|---|---|---|---|---|
| 1 | -10 | 54 | 241 | 1750927857824273283 | |
| 2 | -10 | 55 | 241 | 1750927858839409949 | 1.015137 s |
| 3 | -10 | 55 | 241 | 1750927859855121615 | 1.015712 s |
| 4 | -9 | 55 | 239 | 1750927860870969219 | 1.015848 s |
| 5 | -10 | 54 | 242 | 1750927861886878541 | 1.015909 s |

## The timestamps are the result, not the axes

Each scan carries the moment its trigger fired, and the five sit
1.015137, 1.015712, 1.015848 and 1.015909 seconds apart. The loop slept
one second between fires, so the excess of about 15 milliseconds is the
cost of `iio-trigger fire` itself, and it grows by a few hundred
microseconds a time rather than staying flat.

That is what distinguishes this path from the other two in a way no
amount of reading the code could. The FIFO path assigns timestamps by
arithmetic, counting back from one interrupt at the configured rate, so
a batch of its samples is evenly spaced by construction. These are not
spaced by construction. They carry what the core measured when
`iio_pollfunc_store_time` ran in the hard interrupt half, which is why
the driver passes that function rather than NULL, and the spacing is
the shell loop's.

## The axes, against the other path

Flat on the bench: x about -10, y about 54, z about 241 counts, varying
by a count or two between scans, which is the part converting afresh
rather than the same registers being read five times.

Magnitude is 247.1 counts on average. At the nominal 3.9 mg per LSB
that is 0.964 g, or 9.45 m/s^2 at the scale the driver reported on the
day. Corrected Monday 19 October 2026: the scale constant was derived
from the datasheet table's rounded 3.9 mg/LSB and is now derived from
256 LSB/g, so both of those read 0.16 per cent higher on the corrected
driver, 0.965 g and 9.46 m/s^2. The 247.1 counts are untouched, being
what the part converted, and 247.1 over 256 is the 0.965 directly. See
drivers-ab-2026-10-17.md.

**The same board read 246.5 counts through sysfs on Friday 9 October
2026**, from x -8, y 46, z 242. So the triggered path and the polled
path agree to within a count on the same bench, through different code,
three weeks apart. The 3.6 per cent shortfall against 256 counts is
therefore a property of this part and this orientation rather than of
either path; whether it is inside the sensitivity tolerance of the
datasheet is a separate question and is not answered here.

## What this does not show

That a trigger faster than the part can convert is handled sensibly.
The sysfs trigger fires when something writes to it, so every scan here
had a fresh conversion waiting. Trigger faster than `BW_RATE` and the
same conversion is read twice, which the driver neither prevents nor
reports and which `docs/DESIGN.md` names as a thing to measure. That
measurement wants an hrtimer trigger at a known rate, so it waits for
an image whose kernel carries one.
