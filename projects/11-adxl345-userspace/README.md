# Project 11: a userspace driver, packaged as a library

**Board:** Raspberry Pi 4. **Part:** DFRobot SEN0032, an ADXL345.
**Theme:** userspace drivers over i2c-dev, shared library hygiene, two
packaging systems from one build.

Not every sensor needs a kernel driver, and deciding which do is the
question this project exists to answer. Project 5 writes an in-kernel IIO
driver for this exact chip. This one drives it entirely from user space,
and the two together say more about the choice than either says alone.

[docs/kernel-or-userspace.md](docs/kernel-or-userspace.md) is the answer,
on four criteria, and it does not flatter this project: for the ADXL345
the kernel driver is the right one. That is why the accelerometer is the
excuse and packaging is the subject.

The subject is not the accelerometer. It is what has to be true before a
library is fit to hand to somebody else: an opaque API that survives its
own internals changing, a soname, hidden visibility, `pkg-config`,
bindings that need no structure definitions, tests that run with no
hardware, permissions without root, and packaging that installs and
purges cleanly.

**State: written, not yet built.** Nothing here has been compiled, on any
machine. The authoring laptop has neither `gcc` nor `cmake`, so every
claim below that says "asserted" is a statement about agreement between
files, and everything that would need a toolchain says so.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-bench/libadxl345/files/adxl345-linux/` | The whole CMake project: library, application, bindings, tests and `debian/` |
| `meta-bench/recipes-bench/libadxl345/libadxl345_1.0.0.bb` | The Yocto recipe over the same CMake project |
| `meta-bench/recipes-core/images/bench-userdrv-image.bb` | The image, from `bench-image` |
| `kas/bench-userdrv.yml` | Pi 4, I2C1 at 400 kHz, no kernel fragment at all |
| `tests/adxl345-build-test.sh` | 56 assertions on the build, the packaging and the recipe, plus compile and run where a toolchain exists |
| `tests/adxl345-motion-test.sh` | 22 assertions on the detector's decision logic |
| `tests/adxl345_datasheet.py` and `tests/adxl345-registers-test.sh` | 35 assertions comparing the register map against a transcription of the datasheet |
| `projects/11-adxl345-userspace/docs/` | DESIGN, BRINGUP, the kernel-or-userspace comparison, and an evidence directory that says what is missing |

## The API, and why it is this shape

```c
int  adxl_version(int *major, int *minor, int *patch);
int  adxl_open(adxl_dev **out, const char *i2c_path, int addr, int int_gpio);
int  adxl_start(adxl_dev *d, int range_g, int rate_hz);
int  adxl_read(adxl_dev *d, int16_t samples[][ADXL_AXES], int max, int timeout_ms);
int  adxl_stop(adxl_dev *d);
void adxl_close(adxl_dev *d);
```

Six functions, an opaque handle, integers in and plain arrays out. The
consequence is that the ctypes bindings are twenty lines with no structure
to redeclare, so a change to the library's internals cannot break them
silently. Everything is built with `-fvisibility=hidden`, so a symbol is
exported only where `adxl.h` says `ADXL_API`, and `debian/` pins that set
in a `.symbols` file: an accidental export fails the package build rather
than quietly widening the ABI.

`adxl_read` returns a **count**, not a fixed size. The FIFO delivers a
burst of up to 32, and a caller that assumed it always got `max` would
read stale values off the end of its own array.

`addr` is an argument rather than a constant because the part has two
strap addresses, `0x53` and `0x1d`, and which one this board is has not
been read yet. `int_gpio` may be negative, meaning no interrupt is wired;
the library then polls, which works and is worse.

## Running it

```sh
./go check           # everything provable without a board
./go userdrv         # build bench-userdrv-image for the Raspberry Pi 4
./go flash           # write the card
```

On the board:

```sh
i2cdetect -y 1       # is anything at 0x53 or 0x1d
adxl-map             # live acceleration, one line per burst
adxl-map -a 0x1d     # if the strap is the other way
```

And as a Debian package, which is the form the project is specified to
produce:

```sh
dpkg-buildpackage -us -uc -b
lintian ../*.deb
```

## Acceptance criteria

Written out in full so nothing outside this repository has to be
consulted. "Asserted" means a file says so and a test checks the file;
"measured" means a board did so. Nothing has been measured.

| # | Criterion | State |
|---|---|---|
| 1 | `adxl_open` succeeds in under 100 ms at 400 kHz | Not started |
| 2 | The board flat reads about 1 g on Z and near 0 on X and Y, and tilting to each edge moves the expected axis | Not started. The fake-bus suite asserts the library decodes a synthetic 1 g on Z correctly, which is the arithmetic and not the sensor |
| 3 | `ctest` passes in the sanitizer build with no sensor, and a sanitizer run against the real part survives 10000 samples | **Half written.** The suite and the `ADXL_SANITIZE` option exist. Neither has been compiled |
| 4 | `nm -D` lists exactly six defined text symbols, and the soname is `libadxl345.so.1` | **Asserted three ways**, measured none: the header declares six, the symbols file pins six, and the test compares the soname major in CMake against the one in `debian/`. The `nm` count runs only where the library can be built |
| 5 | The packages install cleanly, the udev rule lands, and purge leaves nothing behind | Not started |
| 6 | A member of `i2c` runs `adxl-map` without `sudo`; a user outside the group gets a clear permission error rather than a crash | Not started. The error path is written: the tool names the group and the other strap address rather than printing a number |

## What is tested without hardware

113 assertions across three suites, none of which needs a sensor.

| Check | Covers |
|---|---|
| `sh tests/adxl345-build-test.sh` | The API surface, hidden visibility, the soname agreeing between CMake and `debian/`, both platform implementations offering the same functions, the packaging file list, the Yocto recipe shipping what CMake installs, the design and the code agreeing, and that Project 5's kernel driver is not in this image. Where a toolchain exists it also configures, builds with `-Werror`, runs the fake-bus suite and counts the exported symbols |
| `sh tests/adxl345-registers-test.sh` | Every register address, fixed value, rate code and range code against `tests/adxl345_datasheet.py`, transcribed from the datasheet rather than from the code |
| `sh tests/adxl345-motion-test.sh` | The detector: the running baseline, the consecutive-burst requirement, and that sustained movement is absorbed |
| The fake-bus suite itself | Every register the library writes, including two ordering claims: measurement is enabled after the configuration, and the interrupt is disabled before measurement stops |

**The register suite exists because the other two cannot see a wrong
constant.** `fake_platform.c` uses the same register numbers as the
library, so corrupting `POWER_CTL` from `0x2d` to `0x2c` leaves 56
assertions green while the part never leaves standby. Internal
consistency is not correctness.

The second is the one worth reading. A suite that checks return codes
proves the error paths and nothing about the configuration, because a
wrong `DATA_FORMAT` byte returns success every time. So the fake records
every transfer and the assertions read like the datasheet.

Every assertion added to these suites was proved by breaking what it
checks and watching it fail, then restoring. Three had to be rewritten
because the first version passed for the wrong reason: a `grep` that
matched a `DESCRIPTION` line, another that matched a comment, and a
soname check that only confirmed `CMakeLists.txt` mentions `SOVERSION`
and would have passed whatever the two numbers were.

## The sharp edge: two drivers, one chip

Project 5 binds an in-kernel IIO driver to this part at this address.
This project drives the same part through `i2c-dev`. It is the only
conflict on this bench that produces readings that are **wrong rather
than absent**: the kernel claims the address, `i2c-dev` may still be
opened, and what comes back depends on which one last moved the register
pointer.

So the two never share an image, `bench-userdrv-image` says so in a
comment, and the test suite asserts that no `kernel-module-*adxl*` line
appears in it. If one is ever wanted, the answer is a second image.

The prediction that a bound kernel driver makes `i2c-dev` return `EBUSY`
is reasoning about how the I2C core claims addresses. Nobody has tried
it.

## Where this differs from the original plan

The project was scoped around a VL53L8CX time-of-flight sensor on an
X-NUCLEO-53L8A1. That shield is not on this bench, and the part that
is, an ADXL345, is better suited to the project for two reasons that came
out of reading rather than preference.

Its register map is public in its datasheet, so there is no vendor blob
and no licence-gated download. The original could not have reached even
its software state: the specified `ctest` links the vendor library into
the test binary, so the hardware-free half would have needed the download
too.

And the pairing with Project 5 only exists because both use one part.
That comparison is the project's own opening question, answered on
hardware rather than by analogy.

What is lost is named rather than glossed: the 90 kB firmware upload, and
with it the chunked large writes and the 8192-byte `i2c-dev` message
limit, which were the most interesting part of the original platform
layer.

## Sources

- ADXL345 datasheet, Analog Devices, for the register map and the FIFO
- Kernel I2C device interface, https://docs.kernel.org/i2c/dev-interface.html
- libgpiod v2 API, https://libgpiod.readthedocs.io/
- Debian policy manual, https://www.debian.org/doc/debian-policy/
- CMake documentation, https://cmake.org/cmake/help/latest/
