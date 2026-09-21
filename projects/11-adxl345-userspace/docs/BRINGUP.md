# Bring-up: Project 11

Written before the board has been touched, which is the only time this is
worth writing. The order below is a safety ordering, not a convenience
one: every step that can destroy something comes before every step that
merely produces a reading.

Nothing here has been done. When a step is carried out, its output goes
in [evidence/](evidence/) and the acceptance row in
[../README.md](../README.md) changes from "not started" to what the board
actually said.

## Before any power

The design's [Figure 2](DESIGN.md) is deliberately undrawn: the DFRobot
SEN0032 publishes no pin list, and three things cannot be known without
reading the board. Two of them are inconvenient. **One can destroy a
GPIO.**

### 1. The supply, first and alone

The breakout is rated `3.3~6V`, which means it regulates. What it does
with its logic levels at 5 V is the question, and it is not answered by
the fact that it powers up.

**Power it from the Pi's 3V3 rail, not 5 V.** That removes the question
entirely: a part running at 3V3 cannot drive an interrupt line above
3V3, whatever its level shifting does or does not do. The cost is
nothing, because the ADXL345 works at 3V3.

Only if 3V3 turns out to be insufficient is the 5 V question worth
asking, and then it is answered with a meter on the `INT1` pin before
that pin reaches the Pi, not after.

### 2. Which pins the breakout exposes

Read the silkscreen. Write down what is actually printed rather than what
a wiki says, because this bench has already put a wrong clock speed and a
wrong board revision into a comparison table by reasoning from a
catalogue page.

Four are needed for a first reading: `3V3`, `GND`, `SDA`, `SCL`. A fifth,
`INT1`, is optional and the library is written to work without it.

### 3. The strap address

`SDO` tied low gives `0x53`; tied high gives `0x1d`. Some breakouts fix
it, some expose it. This is why `adxl_open` takes the address as an
argument rather than compiling one in, and why `adxl-map` names the other
one in its error message.

## First contact, before any of this project's software

```sh
i2cdetect -y 1
```

One of `0x53` or `0x1d` must appear. If neither does, nothing further in
this document will work and the fault is wiring, the strap, or the bus
not being enabled. `ENABLE_I2C` in `kas/bench-userdrv.yml` is what turns
the bus on; without it there is no `/dev/i2c-1` at all, which presents as
a missing sensor rather than a missing bus.

If **both** appear, something else is on the bus at the other address and
the ownership question below matters immediately.

## The ownership check, which is specific to this project

Project 5 binds an in-kernel driver to this same chip. The two must never
be in one image, and this is how to tell which you have:

```sh
ls /sys/bus/i2c/devices/1-0053/driver 2>/dev/null
```

Nothing there means the address is free and `i2c-dev` owns it, which is
what this project wants. A driver name there means Project 5's module is
loaded, and then `adxl-map` is reading a device somebody else is also
driving. The readings will look plausible and be wrong.

`bench-userdrv-image` installs no such module, so on the right image this
check is a formality. It is here because the expensive version of this
mistake is running the wrong image and not noticing.

## First reading

```sh
adxl-map -n 5
```

Expected, with the board lying flat: `z_mg` near 1000, `x_mg` and `y_mg`
near 0. That is criterion 2 and it needs no instrument, because gravity
is always there and always 1 g.

Then pick the board up and turn it onto each edge in turn. The axis that
reads 1000 should change, and it should be the one pointing down. If the
numbers move but the wrong axis responds, the axes are simply labelled
differently on this breakout, which is a note for the README rather than
a fault.

If `adxl-map` refuses:

| Message | Cause |
|---|---|
| something answered and it is not an ADXL345 | The other strap address. The message names it |
| cannot use /dev/i2c-1 | Permission, or the bus is not enabled |
| range or rate is not one the part offers | A typo in the arguments; the message lists both ladders |

## The interrupt, last

`INT1` is the only step that puts a signal from the breakout into a Pi
GPIO, so it comes after everything above has worked at 3V3.

```sh
adxl-map -i 23 -n 5
```

Without `-i` the library polls and says so on stderr. With it, the
library requests the line and falls back to polling if the request fails,
which means **a wrong offset does not announce itself**: the tool keeps
working and the interrupt path is simply never exercised. Check the
consumer to be sure the line was claimed:

```sh
gpioinfo | grep adxl345
```

## The service

```sh
systemctl status adxl-motion
journalctl -u adxl-motion -f
```

Then move the sensor. One `start` line should appear, and then nothing
while it keeps moving: the detector uses a running baseline, so sustained
movement is absorbed. That is a property rather than a fault and it is
asserted in `tests/adxl345-motion-test.sh`.

The service runs as user `adxl345` in groups `i2c` and `gpio`, with
`ProtectSystem=strict`. If it fails to start, the journal will say which
of those it could not get, and the answer is the `postinst` not having
run rather than the unit being wrong.
