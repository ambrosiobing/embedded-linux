# Evidence

Empty, and the emptiness is the point: nothing in this project has been
compiled or run on any machine, so there is nothing here that a reader
could check. A directory of plausible-looking output would be worse than
a blank one.

What lands here, and what each file would settle:

| File | Command | What it would prove |
|---|---|---|
| `build.txt` | `cmake -B build && cmake --build build` on the build laptop | The library compiles with `-Werror` against a real libgpiod v2, which has never happened |
| `ctest.txt` | `ctest --test-dir build --output-on-failure` | The fake-bus suite runs rather than merely existing. It is written and has executed nowhere |
| `symbols.txt` | `nm -D --defined-only libadxl345.so.1` and `objdump -p` | Acceptance criterion 4, measured. Today three separate files agree that there should be six symbols and no compiler has counted them |
| `sanitizer.txt` | `cmake -DADXL_SANITIZE=ON` then the suite | Criterion 3's first half |
| `open-time.txt` | `time adxl-map -n 1` on the board | Criterion 1, the 100 ms budget |
| `flat-and-tilted.txt` | `adxl-map -n 20` lying flat, then on each edge | Criterion 2. Gravity is the reference, so this needs no instrument |
| `lintian.txt` | `dpkg-buildpackage -us -uc -b` then `lintian ../*.deb` | Criterion 5 |
| `unprivileged.txt` | `adxl-map` as a member of `i2c`, then as a user outside it | Criterion 6, both halves: the success and the clear refusal |

The first three need only a Linux machine with a toolchain and are the
cheapest to obtain. The last five need the sensor wired, which needs
[Figure 2 of the design](../DESIGN.md) answered first: the strap address,
the interrupt pin and the supply are all unread.
