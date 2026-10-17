# The watermark nothing writes, Saturday 17 October 2026

A 32 sample FIFO exists to turn many samples into one interrupt. This
driver has had one since the first week, every capture of it has been
taken through Project 10's `iio-rate`, and `iio-rate` writes
`buffer/watermark` before it measures anything. So the path a program
takes when it does not write that attribute had never been measured.

It interrupts once per sample.

## How it was found

Not by reading the code. The register was read off the part while a
buffer was enabled, expecting `0x98`, which is stream mode with 24 in
the low five bits:

    i2cget -f -y 1 0x53 0x38   ->   0x81

`0x81` is stream mode with 1. The driver writes
`BENCH_ADXL345_WATERMARK_DEFAULT`, which is 24, into `st->watermark` at
probe. The IIO core calls the `hwfifo_set_watermark` hook when a buffer
is enabled and passes the buffer's own `watermark` attribute, which it
initialises to 1, and that call lands before `postenable` reads the
field. The probe's value is therefore overwritten every time.

## The three arms

Counted from `/proc/interrupts`, summing the four processor columns of
the `bench-adxl345` line, two reads ten seconds apart. The part was at
its reset rate of 100 Hz throughout, `BW_RATE` `0x0a`.

| Arm | watermark | `FIFO_CTL` | delta in 10 s | per second |
|---|---|---|---|---|
| default, nothing written | 1 | `0x81` | 967 | 96.7 |
| default, repeated | 1 | `0x81` | 967 | 96.7 |
| default, repeated again | 1 | `0x81` | 967 | 96.7 |
| control, buffer disabled | none | `0x00` | 0 | 0.0 |
| `echo 24 > buffer/watermark` | 24 | `0x98` | 40 | 4.0 |
| repeated | 24 | `0x98` | 40 | 4.0 |
| repeated again | 24 | `0x98` | 40 | 4.0 |

Three windows per arm, every one identical to the last, and a control
in the middle at exactly zero. That zero was an accident: a shell `&&`
chain stopped at a failed write and left the buffer disabled, which is
a cleaner control than one anybody would have thought to take.

**967 against 40 is a factor of 24.18, and the watermark is 24.** The
FIFO does precisely what it exists for. Nothing asks it to.

## The sample rate, which both arms agree on

96.7 interrupts a second at one sample each, and 4.0 a second at 24
samples each, which is 96.0 samples a second. Two numbers from very
different working points agreeing to within one per cent, both about
three per cent under the 100 Hz the rate register was set to.

That agreement is worth more than either number. If the handler were
running late and draining more than its watermark each time, the two
arms would not agree: at watermark 1 the thread has about 10
milliseconds per interrupt and at 24 it has 250, so lateness would
distort the fast arm and not the slow one. It does not. The part's
output rate really is a few per cent below nominal, which is one part
on one bench at one temperature and is not a defect.

## The write that failed, and the tool that knew

`echo 24 > buffer/watermark` returned `Invalid argument` on the first
attempt. The core refuses a watermark larger than `buffer/length`, and
the length had been left at 16 by the triggered capture earlier that
day. `iio-rate` writes the length before the watermark, and
`tests/iio-rate-test.sh` asserts that order. The sequence here was
hand-rolled and walked straight into what the tool was built to avoid.

## What changes and what does not

The driver is not wrong, its documentation was. `bench-adxl345.h`
called 24 a default, and the core overwrites it before it can mean
anything; the header now says what the constant is, which is the value
held if that hook is never called and the ceiling the clamp works
against.

What is not fixed, because there is no interface for it: a driver
cannot set the IIO buffer's initial watermark in this kernel, so the
only way to get batching is for userspace to ask. Every capture this
project has published did ask, through `iio-rate`. A program that
simply enables the buffer does not, and pays 24 times the interrupts
for it.
