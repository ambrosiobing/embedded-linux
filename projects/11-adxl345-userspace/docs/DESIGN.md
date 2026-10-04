# Design: Project 11, a userspace driver packaged as a library

Written before any recipe, which is the order Projects 15, 04, 06 and 07
established. The value is not the document. It is that the specification
and the hardware get read against each other while both are still cheap to
change.

Related: [../JOURNAL.md](../JOURNAL.md),
[DECISIONS.md](../../../walkthrough/DECISIONS.md), and
[Project 5](../../05-iio-adxl345/docs/DESIGN.md), which drives the same
sensor from inside the kernel.

## The sensor

A DFRobot SEN0032, an ADXL345 accelerometer on the bench, reached over
I2C1 from a Raspberry Pi 4. Four jumpers and a breadboard; no shield, no
adapter, nothing to order.

Two properties of this part decide the project. Its register map is public
in the datasheet, so there is no vendor blob and no licence gate: every
line here is buildable from the first commit, including the tests, which is
what lets CI exercise it with nothing plugged in. And Project 5 drives the
same chip from inside the kernel, so the pair answers the question this
project opens with, which is why a sensor needs a kernel driver at all.
The answer, written from what the two projects contain, is in
[kernel-or-userspace.md](kernel-or-userspace.md); for this part it is the
kernel, which is what makes Project 11 an exercise in shipping rather
than a recommendation.

## What the product is

A versioned shared library with a stable C API, its bindings, two small
applications, tests that need no sensor, and the packaging that installs
them.

| User space sees | Because of |
|---|---|
| `libadxl345.so.1` with six exported symbols | `-fvisibility=hidden` plus an export macro, and a soname |
| `pkg-config --cflags --libs adxl345` | A generated `.pc` file, so a third party links the way anyone would |
| `import adxl345` in Python | ctypes over the same six functions, no structure definitions |
| `adxl-map` and `adxl-motion` | Two applications that link the library as an outsider would |
| A service running as an unprivileged user | udev group, system user, and a hardened unit |

There is no kernel module here and that is deliberate. This is the half of
embedded Linux that has nothing to do with the kernel and everything to do
with shipping.

## Acceptance criteria

The six criteria this project is specified against, written out in full so
nothing outside this repository has to be consulted. "Configured" means a file says so;
"measured" means a board did so. Nothing below has been measured: no image
has been built and no sensor has been wired.

| # | Criterion | State |
|---|---|---|
| 1 | `adxl_open` succeeds in under 100 ms at 400 kHz, measured with `time` around a single-sample run | Not started |
| 2 | `adxl-map` shows a coherent live reading: the board flat reads about 1 g on Z and near 0 on X and Y, and tilting to each edge moves the expected axis | Not started |
| 3 | `ctest` passes in the sanitizer build with no sensor present, and a sanitizer build against the real sensor runs 10000 samples with no report | Not started |
| 4 | `nm -D` lists exactly six defined text symbols, and `objdump -p` shows the soname `libadxl345.so.1` | Not started |
| 5 | The packages install cleanly on a fresh image, the service starts as user `adxl345`, and purge leaves no files behind, compared with `dpkg -L` before and after | Not started |
| 6 | A member of the `i2c` group runs `adxl-map` without `sudo`; a user outside the group gets a clear permission error rather than a crash | Not started |

Criterion 2 is a physical fact anyone can check by picking the board up.
Gravity is the convenient reference because it is always there and always
1 g, so the test needs no instrument and no second opinion.

## Figure 1: System architecture

The subject of this figure is the layering. Everything above `adxl.h` is
written here, everything below it is the kernel, and the seam in the middle
is the one the tests exploit.

```
  USER SPACE                     libadxl345.so.1 and its users
  +--------------------+  +--------------------+  +--------------------+
  | adxl-motion.service|  | adxl-map           |  | adxl345 (package)  |
  | systemd, user      |  | adxl_motion.py     |  | ctypes bindings    |
  | adxl345            |  | applications       |  | six functions only |
  +---------+----------+  +---------+----------+  +---------+----------+
            | starts               | links, via            | dlopen
            v                      v pkg-config            v
  +---------------------------------------------------------------+
  | adxl.h: the public C API                                       |
  | opaque adxl_dev, six symbols, arrays out, no register types    |
  +----------------------------+----------------------------------+
                               |
            +------------------+------------------+
            v                                     v
  +---------------------------+        +---------------------------+
  | platform.c                |        | fake_platform.c           |
  | i2c-dev, I2C_RDWR         |        | in-memory register map    |
  | libgpiod v2 for INT1      |        | synthetic samples         |
  | one buffer per handle     |        | ctest only, no hardware    |
  +-------------+-------------+        +---------------------------+
                |                       replaces the left box in tests
  ==============|==================================================
  KERNEL        |
  +-------------v-------------+  +----------------+  +--------------+
  | i2c-dev                   |  | GPIO chardev   |  | udev rule    |
  | /dev/i2c-1, I2C_RDWR      |  | INT1, if wired |  | group i2c    |
  +-------------+-------------+  +--------+-------+  | mode 0660    |
                |                         |          +--------------+
  ==============|=========================|========================
  HARDWARE      v                         v
  +---------------------------------------------------+
  | DFRobot SEN0032, an ADXL345                       |
  | 0x53 or 0x1D depending on the SDO pin             |
  | 3 axes, 13-bit, FIFO of 32 samples                |
  +---------------------------------------------------+
```

The right-hand box is the load-bearing one. A fake platform layer replaces
the real one under test, which is what lets criterion 3 run in CI on a
machine that has never seen the sensor.

## Figure 2: Wiring

**Answered, and still not drawn here.** The refusal in this section was
about guessing, not about drawing, so now that the board has been read the
answer goes in one place and this section says where. Repeating the pin
table would create a second place for it to be wrong, which was the original
reason and has not changed.

[Project 5's schematic section](../../05-iio-adxl345/docs/DESIGN.md#schematic)
carries the drawing, every lead with its colour, its pad, its header pin and
its direction. It was drawn on Sunday 4 October 2026 from the wiring built
on Saturday 3 October 2026, and the capture behind it is
[docs/evidence/flat-and-tilted-2026-10-03.txt](evidence/flat-and-tilted-2026-10-03.txt).

The three things this section said could not be drawn without reading the
board, and what reading it gave:

1. Whether `SDO` is tied low or high, which decides the address. **Low, so
   `0x53`.** The library still takes the address as an argument, because the
   strap is a property of the wiring rather than of the library.
2. Which pin carries `INT1`. **Header pin 16, BCM GPIO23**, proved by
   changing `INT_ENABLE` in the sensor and watching the pin follow high,
   low, high. So the FIFO watermark path is reachable and the library need
   not poll.
3. **The supply.** Removed rather than answered: the breakout is powered
   from header pin 1, 3V3, so `INT1` cannot be driven above 3V3 whatever the
   level shifting does. The level shifting itself is still unconfirmed and no
   longer needs to be.

**One thing this project cannot borrow from that drawing.** Project 5
specifies a Raspberry Pi 3 and the wiring was built and read on a Raspberry
Pi 3 Model B+, so for that project the drawing is an observation. This
project specifies a Raspberry Pi **4**. The pin numbers carry because the
40-pin header is the same across models, which is a fact about the header
rather than something anyone has seen on a Pi 4 with this part attached. If
this project is ever run on its own specified board, that is the line to
re-read.

What could be said without the board and still can: the bus is I2C1 on GPIO2
and GPIO3, which is fixed by the Pi rather than by the sensor, and 400 kHz is
enough for any rate the ADXL345 offers.

## Figure 3: Bench layout

```
   +----------------------------------+
   |  o o o o o o o o o o o o o o o   |  40-pin header
   |  o o o o o o o o o o o o o o o   |
   |                                  |        +------------------+
   |  Raspberry Pi 4          [ETH]---|--------| Host PC          |
   |                                  |Ethernet| scp, ssh, apt    |
   |  [microSD]               [USB]   |        +------------------+
   +--[USB-C 5V]----------------------+
          |  |  |  |
          |  |  |  |  four jumpers: 3V3, GND, SDA, SCL
          v  v  v  v  (a fifth for INT1, once the pin is known)
   +----------------------------+
   |  DFRobot SEN0032           |
   |  ADXL345, 3 axes           |
   |  lying flat: Z reads 1 g   |
   +----------------------------+
```

The sensor lies flat on the bench rather than facing the room, because
gravity is the reference for criterion 2. No enclosure and no aiming: the
useful test is picking the board up and tilting it.

## Figure 4: Components, and what depends on what

```
  +----------------------+        +----------------------+
  | platform.c           |<------ | fake_platform.c      |
  | fd: /dev/i2c-1       | replaces, in ctest            |
  | gpiod line for INT1  |        | register map replay  |
  | rd/wr, 8-bit index   |        | synthetic samples    |
  | one buffer per handle|        | same four functions  |
  +----------+-----------+        +----------------------+
             ^
             | calls
  +----------+-----------------------------------+
  | libadxl345.so.1 : adxl.h                     |
  | opaque adxl_dev, internals hidden            |
  | adxl_version, adxl_open, adxl_start,         |
  | adxl_read, adxl_stop, adxl_close             |
  +----------+------------------------+----------+
             ^                        ^
             | dlopen                 | pkg-config, links
  +----------+-----------+  +---------+------------+
  | adxl345 bindings     |  | adxl-map (C)         |
  | ctypes, no structs   |  | live three-axis read |
  +----------+-----------+  +---------+------------+
             ^                        ^
             | import                 |
  +----------+-----------+            |
  | adxl_motion.py       |            |
  | threshold, journal   |            |
  +----------+-----------+            |
             |                        |
  +----------v------------------------v----------+
  | packaging, two ways                          |
  |   Debian: libadxl345-1, -dev, adxl345-tools  |
  |   Yocto:  one recipe, into a bench image     |
  +----------------------------------------------+
```

## The C API

Six functions, chosen so that ctypes needs no structure definitions and a
change of register handling cannot change the ABI.

```c
#define ADXL_AXES 3

typedef struct adxl_dev adxl_dev;

int  adxl_version(int *major, int *minor, int *patch);
int  adxl_open(adxl_dev **out, const char *i2c_path, int addr, int int_gpio);
int  adxl_start(adxl_dev *d, int range_g, int rate_hz);
int  adxl_read(adxl_dev *d, int16_t samples[][ADXL_AXES], int max,
               int timeout_ms);
int  adxl_stop(adxl_dev *d);
void adxl_close(adxl_dev *d);
```

`adxl_read` returns a count rather than filling a fixed-size array, because
the ADXL345 delivers a FIFO burst of up to 32 samples and the caller should
learn how many arrived rather than assume.

**The scale is fixed, and that is a decision rather than a default.**
`adxl_start` always sets `FULL_RES` in `DATA_FORMAT`, so the sensor
reports 3.9 mg per count at every range and only the clipping point
moves with `range_g`.

Without it, the scale changes with the range: the same count means
something different at 2 g and at 16 g. Every stored sample would then
have to carry the range it was taken at to be interpretable later, and
any file, log line or D-Bus message that dropped that field would be
quietly unreadable. Fixing the scale costs one bit in one register and
removes the whole question.

It is also why the API returns raw counts rather than milli-g. The
conversion is one multiplication the caller can do, and an integer
crosses the ctypes boundary without a float conversion in the middle.

`int_gpio` may be negative, meaning no interrupt line is wired. The library
then polls at the configured rate. That is worse, and it was written as the
difference between a project that works today with four jumpers and one that
waits for Figure 2 to be answered. Figure 2 is answered: there are seven
leads rather than four, and `-i 23` is the one that makes the interrupt path
real. The negative case stays in the API, because a caller with three
jumpers and no spare GPIO is a caller this library should still serve.

## Ownership

The table that prevents two managers on one resource.

| Resource | Owner | Never touched by |
|---|---|---|
| `/dev/i2c-1` | `platform.c`, one file descriptor per handle | Any in-kernel ADXL345 driver. **Project 5's module must not be loaded**, or both will drive the same address |
| The ADXL345 at its address | One `adxl_dev` at a time | A second handle. Opening twice is a caller error the library reports rather than a race it loses |
| `INT1`, when wired | `platform.c` through libgpiod v2 | Project 5's driver, for the same reason as the bus |
| The transfer buffer | One per handle, allocated in `adxl_open` | A static buffer. It is the easy way to write a platform layer and it makes the library non-reentrant, so two handles on two threads corrupt each other's transfers |
| Group membership | A udev rule and a system user | `sudo`. Criterion 6 exists to prove root is never needed |

**The first row is the sharp one and it is new to this bench.** Project 5
and Project 11 drive the same chip by different routes, and nothing in
either prevents both being present at once. The in-kernel driver claims the
address through the I2C core; `i2c-dev` then refuses with `EBUSY`, which is
the good case. The bad case is a kernel driver bound to the device while
something pokes it through `i2c-dev` anyway, which the kernel permits and
which produces readings that are wrong rather than absent.

So the two projects never share an image, and each says so in its recipe.

## What this bench does differently

The specification targets Raspberry Pi OS and `dpkg`. This repository is
Yocto and has never carried either CMake or Debian packaging.

**Both are produced, and that is a decision rather than a compromise.**

| Concern | How |
|---|---|
| The specification's deliverable is three `.deb` packages | A `debian/` directory, built with `dpkg-buildpackage` on a Pi or under `sbuild` |
| The bench builds images with BitBake and `./go` | A Yocto recipe over the same CMake project, so the library reaches a bench image |
| Neither should duplicate the other | One `CMakeLists.txt` is the single build definition; both packagings call it |

The specification's own stretch goals ask for the Yocto recipe, so this is
completing it rather than departing from it. The cost is that this project
carries two packaging systems and has to keep their file lists in step,
which is a real maintenance burden and is why the tests assert that the
installed set matches in both.

## What this design does not claim

- **No sensor has been wired and no image built.** Every acceptance row
  says "not started" and will keep saying so until that changes.
- **Figure 2 is unanswered, not omitted.** The address, the interrupt pin
  and the supply are all properties of a board nobody has read yet.
- **The `EBUSY` behaviour in the ownership table is reasoning from how the
  I2C core claims addresses, not an observation.** It predicts that a bound
  kernel driver makes `i2c-dev` refuse; it has not been tried. Trying it is
  cheap once Project 5 has a module, and it belongs in whichever project
  gets there first.
- **The library is untested against real silicon**, so every statement
  about FIFO behaviour, timing and the 100 ms open budget in criterion 1 is
  taken from the datasheet rather than measured.
