# Kernel driver or userspace library

Projects 5 and 11 drive the same chip, the ADXL345 on a DFRobot SEN0032,
by the two available routes. Project 5 writes an in-kernel IIO driver;
this project drives it from user space over `i2c-dev`. Doing both on one
part is the only way to answer the question either of them opens with,
which is when a sensor needs a kernel driver at all.

This document is the answer. It is written from what the two projects
actually contain, and **nothing in it has been measured**: no image has
been built and no board powered on for either. Every row below is a
property of the design rather than a number off a bench, and the ones
that will need measuring say so.

## What each one actually gives user space

| | Project 5, in-kernel | Project 11, userspace |
|---|---|---|
| Interface | `/sys/bus/iio/devices/iio:deviceN`, and `/dev/iio:deviceN` for buffered reads | `libadxl345.so.1`, six functions |
| Who can consume it | Anything. `cat` on a sysfs file, `iio_readdev`, libiio over the network, a Grafana bridge, another kernel driver | Anything that links this library, or calls it through the ctypes bindings |
| Timestamps | `iio_push_to_buffers_with_timestamp`, taken in the interrupt handler | None. The caller notes the time it got the burst |
| Sample streaming | A triggered buffer with a scan mask; the kernel packs samples and user space reads them in blocks | One call per burst, one bus transaction per FIFO entry |
| Hardware FIFO | Drained on a watermark interrupt by a threaded IRQ | Drained by the caller, on a watermark interrupt or by polling |
| Cost of a sample reaching an application | One copy out of a kernel buffer | One `ioctl` per entry, each a full round trip through the kernel |

## The four things that actually decide it

### 1. Does anything else need the data

This is the one that settles most cases and it is not about performance.

An IIO driver publishes to a **shared namespace**. Every tool that
already speaks IIO works with it on the day it probes: `libiio`, `iiod`
serving it over the network, any program somebody else wrote. A userspace
library publishes to whatever links it, and nothing else in the system
knows the sensor exists.

If one application owns the sensor, that is no loss. If the sensor is a
system resource, it is the whole argument.

### 2. Timestamps, and where they are taken

Project 5 timestamps in the interrupt handler. This project cannot: by
the time `adxl_read` returns, the samples have been through a scheduler,
an `ioctl` and a userspace process that may have been preempted between
any two of them.

For an accelerometer that matters more than it sounds. A burst of 16
samples at 100 Hz covers 160 ms of real time, and knowing which 160 ms is
the difference between data you can integrate and data you can only look
at.

**This is the sharpest technical reason to be in the kernel for this
class of part**, and it is unmeasured here: what the jitter actually is
on this bench is a number Project 8's instruments could take and nobody
has.

### 3. Who is allowed to touch it

The kernel driver arbitrates. Two processes reading a sysfs file both get
sensible answers, because the driver serialises them.

This library does not arbitrate and does not pretend to: one handle is
one thread, the transfer buffer is allocated per handle to make two
handles safe, and two processes opening the same chip through `i2c-dev`
will interleave transactions with nothing stopping them. That is a
documented limit rather than a bug, and it is fine for one application
and wrong for a system service.

### 4. What it costs to ship a change

Not a technical property of the part at all, and often the one that
decides in practice.

| | In-kernel | Userspace |
|---|---|---|
| A fix reaches a board by | Rebuilding the kernel, or building a module against the exact running kernel | Replacing a `.so` |
| Distributing it | The kernel's licence terms apply to the driver | Whatever licence you choose |
| Upstreaming | Possible, and then it maintains itself | Not applicable |
| A vendor blob | Cannot be in-tree | Is somebody else's userspace library, which is how they usually ship |
| Debugging | `printk`, `ftrace`, and a crash takes the machine with it | `gdb`, a sanitizer, and a crash takes one process |

The last two rows are why the original specification for this project
chose a time-of-flight sensor. A part whose register map is not public
and that needs a 90 kB firmware upload at every power-up **cannot** have
an in-tree driver, so the question does not arise: the vendor ships a
userspace library and the engineering job is to port and package it.

## Where the ADXL345 actually falls

**In-kernel, and Project 5 is the one to prefer.**

The part has a public register map, an in-tree driver already exists, it
produces a timestamped stream, and other tools would want it. Every one
of the four criteria points the same way.

That makes Project 11 the answer to a different question: not "how should
this sensor be driven" but "what does shipping a userspace driver
properly involve", which is a skill the twenty projects otherwise never
exercise. The ABI versioning, the soname, the symbols file, the bindings,
the packaging and the hardened unit are the subject; the accelerometer is
the excuse, exactly as the specification says.

## What would change this answer

A sensor with any of these belongs in user space, and the third is the
common one:

- No public register map, so no in-tree driver is possible
- A large firmware upload at every power-up, which the kernel would have
  to carry or request
- A vendor library that already exists and is supported, where
  re-implementing it in the kernel means owning it forever
- A part used by exactly one application, where the shared namespace buys
  nothing and the release cycle of a `.so` is worth more

## What is not settled here

- **No measurement, on either side.** The timestamp jitter, the cost per
  sample, and the CPU load of sixteen `ioctl` calls against one buffered
  read are all unmeasured, and all three are measurable once either
  project reaches hardware.
- **The two never run in one image**, so a direct back-to-back comparison
  on the same board needs two flashes rather than two processes. That is
  the ownership row in [DESIGN.md](DESIGN.md) and it is a consequence of
  the parts collapsing onto one chip.
