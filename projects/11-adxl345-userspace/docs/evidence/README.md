# Evidence

One capture, taken on Saturday 3 October 2026. The rest is still empty,
and that emptiness is still the point: a directory of plausible-looking
output would be worse than a blank one.

What lands here, and what each file would settle:

| File | Command | What it would prove |
|---|---|---|
| `build.txt` | `cmake -B build && cmake --build build` on the build laptop | The library compiles with `-Werror` against a real libgpiod v2, which has never happened |
| `ctest.txt` | `ctest --test-dir build --output-on-failure` | The fake-bus suite runs rather than merely existing. It is written and has executed nowhere |
| `symbols.txt` | `nm -D --defined-only libadxl345.so.1` and `objdump -p` | Acceptance criterion 4, measured. Today three separate files agree that there should be six symbols and no compiler has counted them |
| `sanitizer.txt` | `cmake -DADXL_SANITIZE=ON` then the suite | Criterion 3's first half |
| `open-time.txt` | `time adxl-map -n 1` on the board | Criterion 1, the 100 ms budget |
| `flat-and-tilted-2026-10-03.txt` | `i2ctransfer` against the raw registers, flat and then standing | **Criterion 2, taken.** 0.960 g with Z dominant lying flat, 1.031 g with Y dominant on edge, from a SEN0032 at `0x53` with no library, no driver and no soldering |
| `lintian.txt` | `dpkg-buildpackage -us -uc -b` then `lintian ../*.deb` | Criterion 5 |
| `unprivileged.txt` | `adxl-map` as a member of `i2c`, then as a user outside it | Criterion 6, both halves: the success and the clear refusal |

The first three need only a Linux machine with a toolchain and are the
cheapest to obtain. Of the questions [Figure 2 of the design](../DESIGN.md)
left open, the supply, the pad list and the strap address were all answered
on Saturday 3 October 2026 and are written down in the capture above and in
[the bring-up](../BRINGUP.md). The interrupt pin is still unread. The four
remaining captures need the library itself on this arm64 board, which is
now the only thing between them and the bench.
