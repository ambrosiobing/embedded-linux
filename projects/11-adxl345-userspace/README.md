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

**State: built, packaged and tested on a host, never run on a board.**
The library builds with `-Werror`, its fake-bus suite passes, it exports
exactly the six symbols its packaging pins, it passes `ctest` under ASan
and UBSan, and the three Debian packages build and come out of `lintian`
without an error. Three of the six acceptance criteria are met that way.
No sensor has been read, and the other three criteria are the ones that
need one.

Every one of those happens in CI on every push, and it took eleven days
to notice. The sentence here until Friday 2 October 2026 read "Nothing
here has been compiled, on any machine", and it went into the repository
in commit `5167220` on Monday 21 September 2026, **the same commit that
added `cmake` to the CI package list and the compile section to
`tests/adxl345-build-test.sh`**. It was false the moment it was written,
and 103 commits went past it. What the authoring laptop can do is not
what the project has had done to it; the first is a fact about this
machine and the second is a fact about the project, and writing the
first in the second's place is how the whole hardware-free half of this
work stayed invisible.

The evidence is CI run 36934729926, on `488438d`:

```
--- compile and run
ok       cmake configures
ok       everything builds with -Werror
ok       the fake-bus suite passes (48 checked)
ok       the built library exports exactly six symbols
```

So "asserted" below still means a file agrees with another file, and it
is no longer the strongest thing on offer: where a row says compiled, a
compiler produced it. "Measured" still means a board did it, and no row
says that yet.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-bench/libadxl345/files/adxl345-linux/` | The whole CMake project: library, application, bindings, tests and `debian/` |
| `meta-bench/recipes-bench/libadxl345/libadxl345_1.0.0.bb` | The Yocto recipe over the same CMake project |
| `meta-bench/recipes-core/images/bench-userdrv-image.bb` | The image, from `bench-image` |
| `kas/bench-userdrv.yml` | Pi 4, I2C1 at 400 kHz, no kernel fragment at all |
| `tests/adxl345-build-test.sh` | 76 assertions on a host with the full toolchain: the build, the packaging, the recipe, the `-Werror` compile, the fake-bus run, the exported-symbol count, the sanitizer build with `ctest`, and the three Debian packages built and inspected. Fewer where a tool is absent, and it says which |
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
consulted. Three words, and keeping them apart is the point. "Asserted"
means a file says so and a test checks the file. "Compiled" means a
toolchain produced the thing and the claim is about what it produced.
"Measured" means a board did so, and nothing here is measured.

| # | Criterion | State |
|---|---|---|
| 1 | `adxl_open` succeeds in under 100 ms at 400 kHz | **Not measured, but the instrument now exists.** Until Sunday 4 October 2026 nothing in this tree could produce that number: the criterion had named a measurement for thirteen days and no code timed anything, so the only way it could ever have been closed was by somebody timing the whole process and calling it the open. `adxl-map` now brackets `adxl_open` with `CLOCK_MONOTONIC` and prints the figure to stderr on every run, passed or failed, and says whether the interrupt path was inside what it measured, because `-i` adds a gpiochip open and a line request and that is the slow half. The timing lives in the application and not the library on purpose: criterion 4 pins the library at exactly six exported symbols, so a seventh for timing would close one criterion by breaking another. Asserted with no sensor by `scripts/adxl345-install-purge.sh`, where a failed open in a container is still a timed open. **Two numbers are needed and neither is taken:** the open time on eplepi, and the bus frequency it was taken at. The frequency has to come off the running board and not from `kas/bench-userdrv.yml`, which sets 400 kHz for a Yocto image on a Pi 4 and says nothing about a Raspberry Pi OS card on a Pi 3 Model B+. Where the running board states it has not been checked yet; the two candidates are the adapter's `of_node/clock-frequency` under `/sys/class/i2c-adapter/` and the `dtparam` line in `/boot/firmware/config.txt`, and the bring-up step is to look rather than to pick one here |
| 2 | The board flat reads about 1 g on Z and near 0 on X and Y, and tilting to each edge moves the expected axis | **MET on Saturday 3 October 2026**, with `i2c-tools` and no library at all. Lying flat: Z +60 counts, 936 mg, with X at -47 mg and Y at +203 mg. Standing on one long edge: Y +64 counts, 998 mg, with X at -31 mg and Z at -250 mg. Magnitudes **0.960 g** and **1.031 g**, both inside four per cent of gravity, which is the half of the test that a convenient orientation cannot fake. The off-axis terms are the 12.5 and 14.1 degree tilt of a breadboard propped on a cushion and agree with the photographs. Capture in `docs/evidence/flat-and-tilted-2026-10-03.txt`. The library itself has still not run on this part; the fake-bus suite asserts it decodes a synthetic 1 g on Z, which is the arithmetic and not the sensor |
| 3 | `ctest` passes in the sanitizer build with no sensor, and a sanitizer run against the real part survives 10000 samples | **First half met on a host**, CI run 36976709299: the library and its test compile under ASan and UBSan, and `ctest` passes under them. `ADXL_SANITIZE` had existed as a CMake option nothing ever switched on, so eleven days of green `RelWithDebInfo` runs had said nothing about ASan. The sanitizer tree is configured separately from the ordinary one, because ASan changes the layout of what it touches and a mixed tree would prove nothing. The second half needs the part |
| 4 | `nm -D` lists exactly six defined text symbols, and the soname is `libadxl345.so.1` | **Met on a host.** `nm -D` counted six on the built `libadxl345.so.1` in CI run 36934729926, and the soname is the name of the file it counted. Three file-against-file assertions back it up: the header declares six, the symbols file pins six, and CMake's soname major agrees with `debian/`. The only thing left is that no Pi 4 has loaded it |
| 5 | The packages install cleanly, the udev rule lands, and purge leaves nothing behind | **MET, both halves.** The build half on the WSL build laptop JPTOUPM678 on Friday 2 October 2026: 76 passed, 0 failed, 0 skipped. `dpkg-buildpackage` drives debhelper and CMake to three binary packages, each carries what its `.install` file promises, and `lintian` reports no errors. That host packages `libgpiod-dev` 2.2.1, so it ran `dh_shlibdeps` **strict**: nothing about the shared-library dependencies was waived to get this result. Getting there cost five defects that no file-against-file assertion could see, because no file disagreed with any other file: `dh_shlibdeps` unable to resolve a `/usr/local` library, a tools package shipping a compiled ELF with no `${shlibs:Depends}`, the same package shipping two python3 programs and depending on no interpreter, an `adduser --no-create-home` with no `--home`, and the udev rule shipped to `lib/udev/rules.d` through the merged `/usr` symlink. Installing and purging closed on Saturday 3 October 2026 in two podman containers on that same laptop: 15 passed, 0 failed, 0 skipped in the test, and 30 passed, 0 failed in the prover it runs inside `debian:trixie-slim`, a base with no `adduser`, so the `Depends` on it was exercised rather than assumed. The udev rule landed at `/usr/lib/udev/rules.d/60-adxl345.rules`, purge left none of the 12 shipped files, the python module and its bytecode are gone, and `ldconfig` no longer lists the library. The `i2c` and `gpio` groups and the `adxl345` account survive the purge, which policy permits and no `postrm` undoes; the prover names them as residue rather than counting them clean |
| 6 | A member of `i2c` runs `adxl-map` without `sudo`; a user outside the group gets a clear permission error rather than a crash | Not started. The error path is written: the tool names the group and the other strap address rather than printing a number |

## What is tested without hardware

133 assertions across three suites, none of which needs a sensor: 76, 35
and 22, counted from runs rather than from this file. The 76 is the WSL
build laptop JPTOUPM678 on Friday 2 October 2026, which is the only host
so far where every branch of the build suite could execute; the other two
are CI run 36934729926.

A host missing a tool runs fewer and says which, so this number is a
ceiling rather than a promise. It has been wrong once already: it read
113 while crediting the build suite with 56, which was that suite's count
before four compile-and-run assertions were added to it in the very
commit that added them.

| Check | Covers |
|---|---|
| `sh tests/adxl345-build-test.sh` | The API surface, hidden visibility, the soname agreeing between CMake and `debian/`, both platform implementations offering the same functions, the packaging file list, the Yocto recipe shipping what CMake installs, the design and the code agreeing, and that Project 5's kernel driver is not in this image. Where a toolchain exists, which is CI on every push and the WSL build laptop, it also configures, builds with `-Werror`, runs the fake-bus suite, counts the exported symbols with `nm -D`, builds a second tree under ASan and UBSan and runs `ctest` in it, and builds the three Debian packages and checks their contents |
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
X-NUCLEO-53L8A1. It is built on an ADXL345 instead, for two reasons that
came out of reading rather than preference.

An earlier version of this section gave a third reason, that the shield
was not on the bench. That was wrong and was corrected on Wednesday 30
September 2026: the X-NUCLEO-53L8A1 is here. The choice never rested on
it. Both reasons below hold with the shield sitting on the desk, and the
first is the one that decides it.

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
