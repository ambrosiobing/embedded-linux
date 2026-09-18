# Project 5: design

The drawings before the code. This is the first project in the repository
that compiles kernel code, so the views that matter most are the ones about
where the driver's boundaries are: what the subsystem gives you for free,
what the bus glue owns, and where the seam is that makes any of it testable.

| View | Question |
|---|---|
| [Architecture](#architecture) | What the three files are, and why there are three |
| [The seam](#the-seam-is-the-regmap) | Where the fake goes, and what that buys |
| [A compatible of our own](#a-compatible-string-of-our-own) | How this driver avoids fighting the one already in the tree |
| [The IIO surface](#the-iio-surface) | What userspace sees, and who else consumes it |
| [Schematic](#schematic) | Which pin goes where. **Not yet drawn, and why** |
| [Data flow](#data-flow) | What turns into what, from a sample to a CSV row |
| [What gets built](#what-gets-built) | The files this project adds |

## Architecture

The ADXL345 speaks both I2C and SPI. A driver written once per bus is the
same driver twice, so the shape is one core and two thin bus files, which
is the shape the subsystem is designed around and the shape the repository
already promised: `walkthrough/06-mechanism-policy.md` says "Project 5's
driver has such a seam at the regmap layer" before a line of it existed.

```
  DEVICE TREE
  +--------------------------------------------------------------+
  |  overlay declares one node:                                   |
  |    compatible, reg (address or chip select), interrupts       |
  +--------------------------------+-----------------------------+
                                   | the bus the node sits under
              +--------------------+--------------------+
              |                                         |
  +-----------v------------+              +-------------v----------+
  | bench-adxl345-i2c.c    |              | bench-adxl345-spi.c    |
  |  i2c_driver            |              |  spi_driver            |
  |  devm_regmap_init_i2c  |              |  devm_regmap_init_spi  |
  |  sets the read/write   |              |  sets the multi-byte   |
  |  bit conventions       |              |  and read bit          |
  +-----------+------------+              +-------------+----------+
              |                                         |
              |          struct regmap *                |
              +--------------------+--------------------+
                                   v
  +--------------------------------------------------------------+
  | bench-adxl345-core.c                                          |
  |   probe(struct device *, struct regmap *)                     |
  |   knows registers, scales, rates, FIFO, interrupts            |
  |   knows NOTHING about which wires carry them                  |
  +--------------------------------+-----------------------------+
                                   | iio_device_register
  +--------------------------------v-----------------------------+
  | IIO core                                                     |
  |   sysfs attributes     buffer + trigger     events           |
  +--------------------------------+-----------------------------+
                                   v
  +--------------------------------------------------------------+
  | user space: /sys/bus/iio/..., /dev/iio:deviceN, libiio        |
  |   and Project 10's tools, which are part agnostic already     |
  +--------------------------------------------------------------+
```

The core file never includes `i2c.h` or `spi.h`. If it ever needs to, the
split has failed and the bug is in this drawing rather than in the code.

**This is not a guess at the right structure.** Mainline solves the same
problem the same way, and the repository's rule is that a binding is cited
to a driver line rather than recalled, so: Linux v6.12
`drivers/iio/accel/adxl345_core.c` exports

```c
EXPORT_SYMBOL_NS_GPL(adxl345_core_probe, IIO_ADXL345);

int adxl345_core_probe(struct device *dev, struct regmap *regmap,
                       int (*setup)(struct device*, struct regmap*))
```

with the bus-specific halves in `adxl345_i2c.c` and `adxl345_spi.c`. Ours
is written independently and arrives at the same seam, which is the point:
the shape is a property of the problem, not of anyone's cleverness.

## The seam is the regmap

`struct regmap` is the only thing the core needs to reach the chip. That is
what makes it the seam, and a seam is only worth naming if something can be
put on the other side of it.

| Side | In production | Under test |
|---|---|---|
| Above | the core: channels, scales, FIFO logic, event thresholds | unchanged |
| The seam | `devm_regmap_init_i2c` or `_spi` over real wires | `regmap_init_ram` or a mock register file |
| Below | an ADXL345 on a bench | a table of register values |

This is the same move the repository makes everywhere and names in
`walkthrough/06-mechanism-policy.md`: find where the code talks to the
system, make the opening narrow, put a fake behind it. Project 10's shell
tools do it with `BENCH_IIO_ROOT` pointing `/sys` at a directory tree.
Project 15's watchdog does it by reaching hardware only through commands on
`PATH`.

What it buys here specifically: the register conventions of this part are
fiddly and wrong-by-one-bit is the commonest mistake. The measurement range
lives in `DATA_FORMAT`, the rate in `BW_RATE`, and the FIFO mode in
`FIFO_CTL`, each a couple of bits inside a byte that also carries something
else. A test that writes a range and reads back the byte catches a mask
error on a laptop, in milliseconds, without a board.

## A compatible string of our own

**The kernel already contains a working ADXL345 driver.** Writing one from
scratch is a legitimate exercise and pretending the other does not exist is
not, so the design has to say what happens when both are present.

The binding in v6.12,
`Documentation/devicetree/bindings/iio/accel/adi,adxl345.yaml`, claims
these compatible strings:

```
adi,adxl345
adi,adxl375
adi,adxl346   (with adi,adxl345 as fallback)
```

and requires `compatible`, `reg` and `interrupts`, the last with
`maxItems: 1`.

If this project's overlay declared `adi,adxl345`, two drivers would match
one node and which of them bound would depend on module load order. That is
not a conflict anyone would notice quickly: both would probe, both would
register an IIO device, and the numbers would look plausible either way.

**Decision: the overlay declares `bench,adxl345`, and the driver matches
only that.** Three consequences, and the third is the reason.

1. The in-tree driver cannot bind to our node, because it does not claim
   that string. No load-order race exists to lose.
2. Both drivers can be in the same image without interfering, so the
   failure mode of forgetting to disable one is nothing at all.
3. **The two become an A/B pair.** Change one word in the overlay,
   reboot, and the same hardware is driven by mainline's driver instead of
   ours. Every number this project produces then has a control taken on the
   same board, the same bus and the same afternoon. Project 8 had to
   rebuild two kernels to get that property; here it costs a string.

The cost is that the overlay is not portable to a machine running the
in-tree driver, which is correct: it describes this bench, and a node that
asked for a driver nobody has is a node that does not probe.

## The IIO surface

What userspace gets, and therefore what the acceptance criteria can be
written against. Three paths out of the part, which is the same trio
Project 10 measures and compares:

| Path | Mechanism | What it demonstrates |
|---|---|---|
| Polled | `in_accel_x_raw` and friends in sysfs | the channel spec, the scale, `read_raw` |
| Triggered buffer | a trigger plus `/dev/iio:deviceN` | the scan mask, `iio_push_to_buffers_with_timestamp` |
| Hardware FIFO | the part's own 32-sample FIFO, drained on a watermark interrupt | the threaded IRQ, and why it exists |

Channels are the three axes plus a timestamp. Mainline's core declares
exactly `ADXL345_CHANNEL(0, X)`, `(1, Y)`, `(2, Z)`; ours adds the
timestamp channel that a buffer needs.

Events are where an accelerometer earns the subsystem. The part detects
single tap, double tap, activity, inactivity and free fall in hardware and
can route each to `INT1` or `INT2`. IIO already has a vocabulary for these,
so they surface as `iio_event` on the character device rather than as an
invention of ours. That is the whole argument of
`walkthrough/10-generalising.md`: write an IIO driver rather than a
character device "precisely so that Project 10 can use the whole IIO
ecosystem against it without further work".

## Schematic

**Not drawn yet, and deliberately not guessed.**

This bench's ADXL345 is a DFRobot SEN0032. Its wiki states the part
communicates over `I2C / SPI (3 or 4 lines)` at `3.3~6V`, and publishes no
pin list. Which pins the *breakout* exposes decides three things the
drawing cannot be written without:

1. Whether SPI is reachable at all, or only I2C. The driver is written for
   both either way, because that is the subsystem's shape; what the board
   exposes decides which half gets hardware evidence and which stays a
   compile-time claim.
2. Which pin carries `INT1`, without which the FIFO watermark path and the
   event path are unreachable and two thirds of this project is a
   compile test.
3. **The supply, which is the one that can do damage.** A board rated to
   6 V regulates, and if it is powered from 5 V and drives `INT1` at 5 V
   into a Pi GPIO, the pin is destroyed. Powering it from the Pi's 3V3
   removes the question; confirming the level shifting answers it.

The repository's own rule applies, from `walkthrough` and from the bring-up
discipline every board project here follows: a pin number is a property of
a board revision rather than of a part, a wrong one does not fail safely,
and nothing is wired until it has been read off the hardware. Project 15
carries the same hazard for `PWRKEY` and handles it by keeping the
dangerous path disabled behind a flag until the offsets are confirmed.

This section is filled in when the board has been read, and not before.

## Data flow

```
  the part                     the kernel                     user space

  +-----------+
  | ADXL345   |
  | 3 axes    |
  | 32-sample |
  | FIFO      |
  +-----+-----+
        |  watermark reached
        |  INT1 asserted
        v
  +-----------+   hard IRQ: nothing but wake the thread
  | GPIO IRQ  |----------------------------+
  +-----------+                            |
        |                                  v
        |                     +------------------------+
        |                     | threaded handler       |
        |                     |  regmap_bulk_read the  |
        |                     |  FIFO, one sample at a |
        |                     |  time, 6 bytes each    |
        |                     +-----------+------------+
        |                                 |
        |                                 v
        |                     +------------------------+
        |                     | iio_push_to_buffers_   |
        |                     | with_timestamp         |
        |                     +-----------+------------+
        |                                 |
        v                                 v
  +-----------+                 +--------------------+
  | events:   |                 | /dev/iio:deviceN   |
  | tap, free |---------------->| kfifo of scans     |
  | fall      |  iio_push_event +---------+----------+
  +-----------+                           |
                                          v
                              +-------------------------+
                              | iio-decode reads        |
                              | scan_elements and turns |
                              | the buffer into CSV     |
                              +-------------------------+
```

The right-hand end of that picture is already written. `iio-decode` from
Project 10 parses `scan_elements/*_type` and computes offsets from the
sysfs description rather than hard-coding them, so it decodes this driver's
buffer with no change. That is the dependency the root README claims when
it says Project 5 writes a driver Project 10 exercises, and it is worth
being precise that the claim holds because those tools were written
part-agnostic, not because anyone planned this pairing.

## What gets built

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/adxl345.cfg` | The IIO symbols the driver needs, behind an opt-in switch |
| `meta-bench/recipes-bench/bench-adxl345/` | The three driver files, their Makefile, and the recipe that builds them as a module |
| `meta-bench/recipes-bench/bench-adxl345-dt/` | The overlay declaring `bench,adxl345` |
| `meta-bench/recipes-core/images/bench-adxl345-image.bb` | The image, with the module named in `IMAGE_INSTALL` |
| `kas/bench-adxl345.yml` | `./go adxl345`, including `bench-rpi3.yml` |
| `tests/adxl345-*-test.sh` | What can be proven with no board |

**This is the first recipe in the layer to compile kernel code.** Nothing
here inherits `module` today, there is no `KERNEL_MODULE_AUTOLOAD` anywhere
in the tree, and every `kernel-module-*` line in an existing image names
something Yocto built from the in-tree kernel. The nearest precedents are
partial: `libdaqhats` is an out-of-tree build but of userspace, and
`bench-iks4a1` compiles a device tree overlay with `dtc-native`.

The trap that follows is already documented in this repository at the cost
of a flash and a boot, in Decision 75: **a driver that is configured is not
a driver that is installed.** Yocto packages one module per `.ko` and
installs only what an image names. The module therefore has to appear in
`IMAGE_INSTALL` explicitly, and `scripts/lint.py` has a check that reads
image recipe comments for `kernel-module-*` names and asserts they are
installed.
