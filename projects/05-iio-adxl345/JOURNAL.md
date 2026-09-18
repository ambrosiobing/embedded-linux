# Journal: Project 5

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 18 September 2026 unless noted.

---

## 1. What the repository had already promised, before any of it was written

**What happened.** Project 5 had been a single row in the root README since
the repository began, and nothing under `projects/` existed for it. The
first useful hour was spent finding out that the repository had already
committed to several things about it, in four other files, and that none of
them had been read recently.

- `walkthrough/06-mechanism-policy.md` states that "Project 5's driver has
  such a seam at the regmap layer", as an example in a general argument
  about testability. That is a design decision about a driver nobody had
  started.
- `walkthrough/10-generalising.md` says the driver is IIO rather than a
  character device "precisely so that Project 10 can use the whole IIO
  ecosystem against it without further work".
- `kas/bench-rpi3.yml` names Project 5 in its first line as one of the
  three projects that want the identical rootfs on a Pi 3.
- `projects/10-iio-iks4a1/README.md` and its design document both open by
  positioning themselves against this project: "Project 5 writes an IIO
  driver. This one does the opposite."

**What was done.** All four were treated as constraints rather than as
suggestions, and the design document was written to satisfy them
explicitly. The regmap seam is not a choice this project made; it is a
promise it inherited and has now paid.

**Why that and not the alternative.** The alternative is to design from
first principles and then discover the contradictions later, which is how a
repository acquires two documents that disagree. The lesson here is the
reverse of Project 15's entry 1: there the specification existed and was not
consulted, and this time the specification was partly the repository's own
prose about a project that did not exist yet.

**A gap worth naming.** The root README says Project 5's driver is what
Project 10 exercises, and Project 10 as built exercises ST's in-tree drivers
on a different part. Nothing in Project 10 consumes an ADXL345. The claim
survives only because Project 10's tools are part-agnostic by construction:
`iio-rate` takes a device name, `iio-decode` reads `scan_elements`. That is
a fact about how those tools were written rather than a plan anyone made,
and it is recorded here so the dependency is not read as stronger than it is.

---

## 2. The kernel already has this driver, and that is useful rather than awkward

**What happened.** Writing an ADXL345 IIO driver "from scratch" invites an
obvious objection, which is that Linux has had one for years. The design
cannot pretend otherwise, and the repository's Decision 83 forbids working
from memory about a driver: a binding is cited to a driver line.

So it was cited. Linux v6.12,
`drivers/iio/accel/adxl345_core.c`, about 260 lines, exports

```
EXPORT_SYMBOL_NS_GPL(adxl345_core_probe, IIO_ADXL345);

int adxl345_core_probe(struct device *dev, struct regmap *regmap,
                       int (*setup)(struct device*, struct regmap*))
```

with channels `ADXL345_CHANNEL(0, X)`, `(1, Y)`, `(2, Z)` and
`regmap_bulk_read`, `regmap_read`, `regmap_write` and `regmap_update_bits`
throughout. The binding
`Documentation/devicetree/bindings/iio/accel/adi,adxl345.yaml` claims
`adi,adxl345`, `adi,adxl375` and `adi,adxl346`, and requires `compatible`,
`reg` and `interrupts`.

Two things follow from having read it rather than remembered it.

The first is reassuring: mainline arrives at exactly the seam the
walkthrough promised, a core taking `struct regmap *` with thin bus files
either side. The shape is a property of the problem.

The second is a hazard. If this project's overlay declared `adi,adxl345`,
two drivers would match one node and which bound would depend on module
load order. Both would probe, both would register an IIO device, and the
numbers would look plausible either way, so the failure would not announce
itself.

**What was done.** The overlay declares `bench,adxl345` and the driver
matches only that. The in-tree driver cannot bind to it, so no race exists.

**Why that and not the alternative.** The obvious alternative is to leave
`CONFIG_ADXL345` unset and take the mainline name. That works until someone
builds an image that turns it on, and the defect it then produces is
invisible.

The reason to prefer a private string is better than defensive, though.
With both drivers installable and only one matching, **changing one word in
the overlay swaps which driver owns the hardware.** Every number this
project produces can then have a control taken on the same board, the same
bus and the same afternoon. Project 8 needed two kernel builds to get a
control that honest; here it costs a string.

---

## 3. The schematic is not drawn, because the board has not been read

**What happened.** The part on this bench is a DFRobot SEN0032. The design
needs three facts about the breakout rather than about the chip: whether
SPI is exposed at all, which pin carries `INT1`, and what the supply does
to the logic levels. DFRobot's wiki gives the chip's capability,
`I2C / SPI (3 or 4 lines)` at `3.3~6V`, and publishes no pin list.

**What was done.** Nothing was drawn. The schematic section of the design
document says why it is empty and names the three facts it is waiting for.

**Why that and not the alternative.** A pin table assembled from a product
page would look exactly like a pin table read off hardware, and the
repository has already paid for that class of mistake more than once. The
specific hazard here is not a wasted afternoon: a board rated to 6 V
regulates, and a 5 V `INT1` into a Pi GPIO destroys the pin. Project 15
carries the same shape of risk on `PWRKEY` and handles it by keeping the
dangerous path disabled behind a flag until the offsets are confirmed
against a schematic.

**What is not blocked by it.** The driver is written for both buses
regardless, because that is the subsystem's shape rather than this bench's
wiring. What the board exposes decides which half gets hardware evidence
and which stays a compile-time claim, and the acceptance table will say
which is which.
