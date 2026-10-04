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

**What this bench's part carries, read off the board on Saturday 3 October
2026.** Eight pads in one row:

    GND  VCC  CS  INT1  INT2  SDO  SDA  SCL

with an axis marker showing X and Y in the plane of the board and Z out of
its face, which is the orientation criterion 2's "flat reads about 1 g on
Z" refers to. Three things follow that the paragraph above could not say:
the supply pad is labelled **`VCC`** rather than `3V3`, consistent with the
`3.3~6V` rating and an on-board regulator; there is an **`INT2`** this
project does not use; and **`CS` is exposed**, which matters more than
either and has its own entry below.

Confirm it against the part in hand anyway. That is one board photographed
once, and breakouts sold under a single part number are not always one
layout.

**Where each one goes on the Raspberry Pi 4's 40-pin header**, written as
physical pin numbers because that is what a person counting along a
header can check, with the GPIO number beside it because that is what
the software asks for. Physical pin 1 is the corner nearest the microSD
slot, and the odd numbers are the row nearest the board edge.

| Breakout pad | Raspberry Pi 4 header | GPIO | Signal | Direction |
|---|---|---|---|---|
| `3V3` | physical pin 1 | 3V3 rail | supply, 3.3 V | Pi to breakout |
| `GND` | physical pin 9 | ground | ground | common |
| `SDA` | physical pin 3 | GPIO2, `SDA1` | I2C data | both ways |
| `SCL` | physical pin 5 | GPIO3, `SCL1` | I2C clock | Pi to breakout |
| `CS` | physical pin 17 | 3V3 rail | selects I2C, see 3 below | strap, must be high |
| `SDO` | physical pin 14 | ground | address strap, low gives `0x53` | strap |
| `INT1` | physical pin 16 | GPIO23 | watermark interrupt | breakout to Pi |

Physical pin 1 for the supply and not physical pin 2, which is 5 V and
sits directly beside it on the other row. That adjacency is the whole
reason section 1 above exists, and a 5 V pin is one row away from the
3V3 pin at both pin 1 and pin 17.

`adxl-map -i 23` is **GPIO23, which is physical pin 16**. The two
numbers are not the same number and neither is 23. Project 10 lost an
evening on Thursday 1 October 2026 to its interrupt wire landing on
physical pin 16 when its overlay asked for GPIO24, which is physical pin
18: the two sit next to each other, the board came up, the sensor read,
and only the interrupt count said anything was wrong. Here the same
mistake is quieter still, because the library falls back to polling when
it cannot claim the line, so a wrong pin produces working output and an
interrupt path that was never exercised. That is what the `gpioinfo`
check at the end of this document is for.

### 3. The two straps: which bus, and which address

**`CS` decides whether the part is on I2C at all, and it is the strap this
document did not name.** The ADXL345 uses `CS` as an active-low SPI chip
select, and for I2C it must be tied **high**. Left low or floating, the
part is in SPI mode and answers nothing on the bus however correct the rest
of the wiring is. That presents as an empty `i2cdetect` grid, which sends a
reader to `SDA` and `SCL` and to the bus, none of which is the fault.

On Saturday 3 October 2026 this bench got exactly that empty grid, with
`/dev/i2c-1` present and the controller working and the shield off the bus.
That attempt is not resolved, so this records the strap rather than a fix:
`CS` is the first thing to check, not the last.

**`SDO` decides the address.** Tied low gives `0x53`; tied high gives
`0x1d`. A floating `SDO` gives neither reliably. Some breakouts fix
it, some expose it; this one exposes it. This is why `adxl_open` takes the address as an
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

## Read the configuration before believing a reading

**This bench's SEN0032 does not come up at the documented reset values**,
and taking them on trust made a correct part look broken three times in a
row on Saturday 3 October 2026. What it actually held:

| register | read | documented reset | what it changed |
|---|---|---|---|
| `DATA_FORMAT` `0x31` | `0x42` | `0x00` | plus or minus 8 g, so one count is 15.6 mg and 1 g is **64** counts, not the 256 the default gives |
| `FIFO_CTL` `0x38` | `0x6b` | `0x00` | FIFO mode with all 32 entries used, so the data registers served queued samples from an earlier orientation and looked frozen |
| `OFSX` `OFSY` `OFSZ` `0x1e` to `0x20` | `0xa4 0x29 0x2a` | `0x00` | adds -1.44 g, +0.64 g and +0.66 g to every sample |
| `INT_ENABLE` `0x2e`, `INT_MAP` `0x2f` | `0xe0`, `0x60` | `0x00` | interrupts enabled and mapped, which this project does not want yet |

Assuming the defaults made the part read 42 per cent low, then apparently
frozen, then 2.3 g. It was reading 1 g correctly the whole time.

So read these three before any number is believed, and write what you
need rather than inheriting it:

```sh
i2ctransfer -y 1 w1@0x53 0x2c r6     # BW_RATE .. DATA_FORMAT
i2ctransfer -y 1 w1@0x53 0x38 r2     # FIFO_CTL, FIFO_STATUS
i2ctransfer -y 1 w1@0x53 0x1e r3     # the three offset trims
```

Bypass and zeroed trims, which is what the raw-register checks below want:

```sh
i2cset -y 1 0x53 0x38 0x00
i2ctransfer -y 1 w4@0x53 0x1e 0x00 0x00 0x00
```

Why the part holds a configuration nobody in that session wrote is not
established. A clone with different reset values is one candidate and is
not asserted. The control that answers it costs one power cycle: drop the
3.3 V on physical pin 1, bring it back, and read those registers before
writing anything.

This is also the reason `adxl_open` takes the range and the rate as
arguments rather than compiling them in. A library that trusts what it
finds on this part is wrong by a factor of four before it starts.

## Getting this project's software onto the board

Everything above this point used `i2c-tools` and nothing from this project,
which is why criterion 2 could be measured on Saturday 3 October 2026 with
no library at all. Everything below it needs `libadxl345` and `adxl-map`
present, and until Sunday 4 October 2026 no document said how they get
there. There are two routes and they are not interchangeable.

**The Yocto route.** `./go userdrv` builds `bench-userdrv-image` for a
Raspberry Pi 4 and the recipe installs the library, the tool, the bindings
and the udev rule into the image. Nothing is built on the board. This is the
route the rest of this document was written for.

**The Debian route, which is the one eplepi is on.** The board holding the
sensor is a Raspberry Pi 3 Model B+ running Raspberry Pi OS on Debian
trixie, from a card no `kas` file ever touched. The software has to be built
there. Native rather than cross: this is a small CMake project, the board
can compile it, and a native build removes the question of whether the
binary that was tested is the binary that ran. It also happens to be the
same base as `debian:trixie-slim`, which is the container the packaging was
proved in, so `libgpiod-dev (>= 2.0)` and the non-essential `adduser` behave
as they did there rather than as a new unknown.

Note that this board is full Debian, so the repository's standing warning
about a BusyBox userland does not apply here. It applies to the Yocto cards.

### Getting the source there, which is 123 KiB of it

The whole CMake project is one directory, 123 KiB of it:

```
meta-bench/recipes-bench/libadxl345/files/adxl345-linux
```

The repository around it is about 27 MiB with its history. Both routes work
and they say different things:

```sh
git clone https://github.com/ambrosiobing/embedded-linux.git
cd embedded-linux/meta-bench/recipes-bench/libadxl345/files/adxl345-linux
```

A clone on the board means the commit that was built is recorded by `git
rev-parse` rather than remembered, which is what an evidence file needs. The
alternative is to copy the one directory from the authoring laptop, which
avoids 27 MiB on the card and loses that: a copied tree cannot say which
commit it came from unless the commit is written down by hand at the time.
Prefer the clone, and if the directory is copied instead, record the commit
in the same command that copies it.

Every command below runs in that `adxl345-linux` directory, not at the top
of the repository.

### Check the disk, and check the one dependency that can be absent

```sh
df -h /
apt-cache policy libgpiod-dev debhelper cmake pkg-config
```

The build needs a few hundred megabytes with the build dependencies
installed, and minutes rather than seconds on a Pi 3. The dependency to read
rather than assume is `libgpiod-dev`: this project requires **2.0 or later**
and the v1 API is not source compatible, so a candidate of 1.6 means the
build cannot proceed on this card. That is a finding to write down, not a
surprise to hit halfway through a build.

### Two builds, and they must not be installed over each other

This is the part that is easy to get wrong, because both builds produce a
program called `adxl-map`.

**The packaged build gives criteria 1 and 6.**

```sh
sudo apt install debhelper dh-python cmake pkg-config libgpiod-dev
dpkg-buildpackage -us -uc -b
sudo apt install ../libadxl345-1_*.deb ../adxl345-tools_*.deb
```

`dpkg-buildpackage` writes its output into the **parent** directory, which is
why the install line reaches back with `../`. Installing both packages rather
than only the tools one is deliberate: `adxl345-tools` depends on
`libadxl345-1`, and letting apt resolve it from the local files is what
proves the dependency is declared correctly.

`dh-python` rather than `dh-sequence-python3`, which is what `debian/control`
asks for: the second is a virtual package and the first is what provides it.
Installing the provider by name is clearer than relying on apt to resolve a
virtual package with one provider, and it is the same package either way.

Criterion 6 is reachable no other way: it is about a member of `i2c` reading
the sensor without `sudo`, and the `i2c` group, the `adxl345` account and the
udev rule that puts `/dev/i2c-*` in that group are all created by the
package's `postinst`. A binary built in a work tree creates none of them.

**The sanitizer build gives criterion 3's second half, and is never
installed.**

```sh
cmake -S . -B build-asan -DADXL_SANITIZE=ON
cmake --build build-asan
./build-asan/adxl-map -n 320
```

Run it from its build directory. If it were installed it would replace the
packaged `adxl-map` with a sanitized one, and then criterion 1's open time
would be measured on a binary carrying ASan and UBSan, which on a Pi 3 is
slow by a large factor. That number would be wrong without looking wrong,
which is the expensive kind. Criterion 3 asks for 10000 samples; the FIFO
delivers up to 32 per burst, so 320 bursts is the floor and more is better.

So the order is: package, install, measure criterion 1 and criterion 6, and
only then build the sanitizer tree and run it from where it was built.

### Criterion 1 needs two numbers, not one

`adxl-map` prints the open time to stderr on every run, in milliseconds and
again in microseconds, and says whether the interrupt path was inside what it
measured, because `-i 23` adds a gpiochip open and a line request.

```sh
adxl-map -n 1
adxl-map -i 23 -n 1
```

Run each several times and record the spread rather than one figure. The
criterion is "under 100 ms", so a single sample that happens to land under it
is the weaker half of the evidence.

The second number is the bus frequency, because the criterion says "at
400 kHz" and that is a property of this card rather than of this project.
`kas/bench-userdrv.yml` sets 400 kHz for a Yocto image on a Pi 4 and says
nothing about this board, so quoting it would be a measurement borrowed from
a different machine. Where Raspberry Pi OS states the running bus clock has
not been checked on this board yet. The two candidates are the adapter's
device-tree node under `/sys/class/i2c-adapter/` and the `dtparam` line in
`/boot/firmware/config.txt`, and the step is to look at both and say which
one answered:

```sh
ls /sys/class/i2c-adapter/i2c-1/of_node/
grep -n i2c /boot/firmware/config.txt
```

If the bus is not at 400 kHz, the honest result is the open time with the
frequency it was actually taken at, and a separate note about whether
changing it is worth a reboot. A time measured at 100 kHz is not a failure of
criterion 1; it is criterion 1 not yet asked.

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

**Prove the line before any software touches it.** `INT_MAP` leaves
`DATA_READY` on `INT1`, and at 100 Hz that line is asserted essentially
all the time, so the Pi can watch it with no library at all. Change one
register inside the sensor and watch the pin follow:

```sh
pinctrl set 23 ip && pinctrl get 23           # expect hi
i2cset -y 1 0x53 0x2e 0x00 && pinctrl get 23  # expect lo
i2cset -y 1 0x53 0x2e 0x80 && pinctrl get 23  # expect hi
```

Done on Saturday 3 October 2026 and recorded in
`docs/evidence/flat-and-tilted-2026-10-03.txt`. The ADXL345 drives `INT1`
push-pull, so both states are driven and no pull resistor is needed to
read it. Restore `INT_ENABLE` with `i2cset -y 1 0x53 0x2e 0xe0` if you
want what the part was found holding.

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
