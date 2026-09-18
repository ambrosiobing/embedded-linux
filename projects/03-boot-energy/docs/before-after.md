# Before and after

One row per variant, assembled from each `results/<variant>/summary.md`.

**Every cell is empty, and that is the honest state of this project.** No
NanoPi has been powered with this instrumentation, Project 2 has not
produced a system to boot, and the specification's own example table says
its figures are illustrative placeholders to be replaced by the mean of
five boots.

A number here that was not measured would be worse than a blank, because
the blank is honest and the number is a claim the first careful reader will
check.

| Variant | Power-on to D1 | D1 to first console byte | Console to D0 | Total to D0 | Mean current | Energy per boot |
|---|---|---|---|---|---|---|
| `00-baseline` | | | | | | |
| `10-uboot` | | | | | | |
| `20-kernel-trim` | | | | | | |
| `21-kernel-lz4` | | | | | | |
| `30-systemd` | | | | | | |
| `40-final` | | | | | | |
| `40-final`, no `wpa_supplicant` | | | | | | |

Each cell is a mean over five kept boots, and every one is to be quoted
with the standard deviation beside it. The discard rules that decide which
boots are kept are in [DESIGN.md](DESIGN.md) and in `measure/analyze.py`,
and they were written before any data existed.

## What the table cannot show

The energy column assumes 5.0 V at the header. The PPK2 measures current
and not voltage, and long thin jumper wires drop tens of millivolts at
400 mA. The assumption belongs beside the number every time it is quoted.

The last row is the one the specification asks for separately: the same
final variant with `wpa_supplicant@wlan0` disabled. The difference is the
price of associating at boot, and for a device that transmits once and
shuts down it decides whether the association belongs in the boot at all.
