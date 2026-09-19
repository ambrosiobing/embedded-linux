# Project 03: boot time and energy per boot, measured

Boot time is the property an embedded product is judged on first and the
one most often guessed at. This project measures it, and measures a number
that is guessed at worse: the energy one boot costs. For a device that
wakes, does its work and shuts down again, that figure decides the battery
life more than the sleep current does.

**The instrument is not the thing being measured.** Console timestamps
begin only once the kernel has a console, which is already past the part
most worth optimising. Instead the board raises two electrical markers,
U-Boot sets PG11 as its first action and a systemd unit sets PA6 when the
startup job queue empties, and a Nordic PPK2 records both on the same clock
as the current samples at 100 kS/s. The console TX line is a third logic
channel, which ties every burst in the current trace to a line of output.

The design is in [docs/DESIGN.md](docs/DESIGN.md).

## The system to boot now exists

The specification's key facts line reads "NanoPi NEO Air with the mainline
system from Project 2", and until Saturday 19 September 2026 there was no
such system, so every measured cell in this project was blank for want of
anything to measure.

**That blocker is gone.** Project 2 reached Complete on hardware on
Saturday 19 September 2026: U-Boot 2025.10 and a 6.12 kernel on a Debian
bookworm armhf root filesystem, booting the board's own eMMC with no card
in the slot, with `docs/bootlog-emmc.txt` in that project a 522 line
capture from power-on to a login prompt on `ttyS0`.

**This section previously said Project 2 was in flight and had produced no
image.** That was true when it was written on Friday 18 September 2026 and
is false now. It is corrected here rather than quietly replaced, because
the sentence was load-bearing: it was the justification a reader was given
for a table with an empty column.

The measured column is still empty, and now for a different and smaller
reason: **no board has been powered through the PPK2 yet.** The first
session with the instrument is written out step by step in
[docs/BRINGUP.md](docs/BRINGUP.md), and it starts with the one test that
could still end the method, the logic-level self-test.

**This is Software complete on the repository's ladder**, and the
distinction from Project 6 is worth stating because the two look alike from
outside. Project 6 sits a rung lower because BitBake has never parsed its
recipes and `dtc` has never compiled its overlay: there is a build step
there and it has never run. This project has no build step. Its programs
have been executed, by 49 assertions, on a machine with no board attached,
which is exactly what that rung means.

What is missing is not software. `trim.cfg`, the device-tree patch and
`units-disabled.txt` are data that can only come from a board, and the next
rung up, Built and running on the board, is not met until the bench session
happens.

## What this project adds to the repository

| Path | What |
|---|---|
| `docs/DESIGN.md` | the four specified figures as text, the ownership table, and the two questions that cannot be answered without the hardware |
| `docs/BRINGUP.md` | the order of the first session with the hardware, starting with the test that could end the project |
| `docs/evidence/README.md` | what each artefact is and how it is produced, empty until a board has run |
| `measure/analyze.py` | CSV to phase times, energy, summary and plot, with the discard rules built in |
| `measure/ppk2_boot.py` | one boot: power off, settle, record, power on, detect the marker, power off |
| `board/boot-marker.service` | raises the marker when the startup job queue empties, without forming an ordering cycle |
| `board/boot-marker-led.dtsi` | the `gpio-leds` child on PA6, and why it is not yet a patch |
| `board/units-disabled.txt` | every unit masked or disabled, with its reason and what brings it back |
| `uboot/fragments/fast.config` | the preboot marker, then the U-Boot trimming, in two stages |
| `kernel/fragments/` | trimming and the three compression variants |
| `measure/Makefile` | six boots of a variant with the supply down between them, then the analysis |
| `docs/before-after.md` | one row per variant, every cell empty |
| `tests/boot-energy-analyze-test.sh` | 37 assertions against synthetic traces with arithmetic answers |
| `tests/boot-energy-capture-test.sh` | 12 assertions, including the call order that makes t=0 mean something |

## Running it

Neither test needs a board, a PPK2, or Project 2. Both need `numpy`, which
CI has.

```bash
sh tests/boot-energy-analyze-test.sh
```

```bash
sh tests/boot-energy-capture-test.sh
```

The measurement itself runs on the **Windows host**, because that is where
the PPK2 is attached, and the Power Profiler desktop app has to be closed
first because it holds the serial port open.

```bash
python measure/ppk2_boot.py COM5 results/00-baseline/boot-01.csv
```

```bash
python measure/analyze.py results/00-baseline --plot results/00-baseline/current.png
```

## Acceptance

**Configured** is what a file says. **Measured** is what a board did.
Criterion 0 is measured; the rest are empty because no boot has been
recorded yet.

| # | Criterion | Configured | Measured |
|---|---|---|---|
| 0 | With the logic port's `VCC` on `SYS_3.3V`, D3 on pin 17 reads high while the supply is 5.0 V | the wiring table lists the `VCC` pin the specification omits; Nordic requires it between 1.65 and 5.5 V | **met**, Saturday 19 September 2026. D3 at 62 percent of its band against 38 percent for the other seven, including four with nothing attached. [logic-selftest.txt](docs/evidence/logic-selftest.txt) |
| 1 | D1 rises within 0.5 s of the supply coming on in every run; a later or missing marker discards the run rather than averaging it | `D1_DEADLINE_S = 0.5` in `analyze.py`, with the refusal naming the time it saw and the deadline it used | |
| 2 | `systemd-analyze time` agrees with the D0 time minus the kernel start within 0.2 s | both use the same definition of complete: the startup job queue emptying, via `is-system-running --wait` | |
| 3 | The final variant reaches D0 in at most a third of the baseline time, with a standard deviation under 5 percent of the mean over five boots | six variant directories defined, one change each | |
| 4 | Energy per boot is reported in joules with the integration interval stated | integrated over `[0, t_done]`, and the interval is printed in every summary | |
| 5 | Every optimisation variant is a committed fragment or patch with its own result directory of five CSV files | fragments written for U-Boot, kernel trimming and three compressions | |
| 6 | After optimisation the console login still works, `ssh` over Wi-Fi still works, and `systemctl --failed` is empty | `BOOTDELAY=0` without `AUTOBOOT_KEYED`, so the console stays interruptible | |

### One acceptance criterion cannot fail as written

Criterion 4 has a second clause in the specification: "the mean current
times the total time reproduces it within 2 percent."

**Over the integration interval that product is the energy, exactly, by
construction.** `E = V * sum(I) * dt` and `mean(I) * t_done = sum(I) * dt`
are the same arithmetic written twice, so a check of one against the other
can only ever pass. Implementing it would add a test that cannot fail,
which this repository has already shipped three of and which is worse than
no test because it is counted.

So it is not implemented as a check. What the clause is actually worth is
its first half, and that is done: the interval is named in every summary,
because an energy figure without its interval is not a measurement of
anything. The two numbers are both printed and a reader can multiply them.

### The one that could have ended the project on a missing jumper

Criterion 0 is not in the specification's list. It is promoted here
because it is a precondition rather than a result, and because the
specification's wiring table is missing a pin.

The PPK2's logic port carries **VCC and GND of its own** alongside D0 to
D7. VCC is the level shifter's reference and Nordic requires it between
1.65 and 5.5 V. Tie it to the board's 3.3 V rail and 3.3 V markers are
read correctly whatever `VOUT` is set to; leave it unconnected, as that
table would, and D0, D1 and D2 read nothing, all three at once.

**That is the same symptom the self-test was written to detect.** It would
have reported the method unworkable, for a missing jumper, and been
believed. An earlier version of this README said the risk was that the
logic inputs are referenced to the supply domain and 3.3 V might be below
threshold at 5.0 V. That was wrong; they are separate on purpose.

What is left to confirm is narrower: that this board's rails, wires and
connector behave as documented. Whatever is found is written down either
way, because a low reading is a finding about the bench rather than a
failure of the project.

## What has not been done

- **No boot has been recorded.** The board has been powered through the PPK2 and the logic port verified, but the markers are not installed and no CSV exists.
- **No board has been powered through the PPK2.** Project 2's system exists and boots; this project has not yet measured it.
- `board/0001-dts-boot-marker-led.patch` is a `.dtsi` instead. A patch is a
  diff against specific lines of a specific tree, and inventing hunk
  headers for a tree that has never been checked out would be a
  fabrication in the format of evidence. The file says how to generate the
  real patch once Project 2 has a kernel tree.
- `kernel/fragments/trim.cfg` holds no symbols. The list comes from
  `localmodconfig` against an `lsmod` captured from a real reference boot,
  and writing a plausible list in advance would be a guess in the same
  voice as a measurement.
- `board/units-disabled.txt` is a template. Which of those units exist on
  the rootfs is a fact about a system nobody has booted.
- The `ppk2-api` version is unpinned, because no version has been verified
  on this bench yet. Its digital-channel helpers have been renamed between
  releases and `ppk2_boot.py` calls two of them.

## Journal

[JOURNAL.md](JOURNAL.md).
