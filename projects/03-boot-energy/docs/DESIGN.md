# Project 3: design

Boot time is the property an embedded product is judged on first and the
one most often guessed at. This project measures it, and measures a second
number that is guessed at even more badly: the energy one boot costs.

The design decision that makes both numbers trustworthy is that **the
instrument is not the thing being measured.** Console timestamps start only
once the kernel has a console, which is already several seconds into the
boot and after the part most worth optimising. Instead the board raises two
electrical markers, U-Boot sets one as its first action and a systemd unit
sets the other when the startup job queue empties, and a Nordic PPK2
records those markers on the same clock as the current samples. Nothing in
the timing comes from the board.

## What this project has not done yet

**There is now a system to boot.** Project 2 reached Complete on hardware
on Saturday 19 September 2026, and the NanoPi NEO Air boots its own eMMC to
a login prompt on `ttyS0`. An earlier version of this section said that
project was in flight and had produced no image, which was true on
Friday 18 September 2026 and is not true now.

What has not happened is the measurement. No board has been powered through
the PPK2, so every number in this project is still blank, and a blank is
honest where a placeholder is a claim. The specification's own before/after
table says the same thing in its caption: the example figures there are
illustrative and every cell is to be replaced by the mean of five boots.

The order of the first session with the instrument is in
[BRINGUP.md](BRINGUP.md). It does not follow the specification's step
order, and the reason is in that file: one test can end the method and
belongs first.

## Architecture

Three columns, and the middle one is the only clock.

```
  Windows host                 nRF-PPK2                  NanoPi NEO Air
  +--------------------+       +------------------+      +---------------------------+
  | Power Profiler app |       | source meter     |      | U-Boot                    |
  |  live view,        |       |   5.0 V, max 1 A |=====>|   preboot: gpio set PG11  |
  |  logic self-test   |       +------------------+ VOUT |            |              |
  +--------------------+       | current sampling |      |            v              |
  | ppk2_boot.py       |<--USB>|   100 kS/s       |      | kernel                    |
  |  one boot, CSV out |       +------------------+      |   initcalls, ttyS0 output |
  +--------------------+       | logic port D0..D7|      |            |              |
  | analyze.py         |       |   same time base |      |            v              |
  |  edges, energy,    |       +------------------+      | systemd                   |
  |  plots             |            ^  ^  ^              |   units, targets          |
  +--------------------+            |  |  |              |            |              |
  | results/           |         D1 |  |  | D0           |            v              |
  |  CSV per boot,     |            |  |  |              | boot-marker.service       |
  |  summary.md        |            |  D2 (console TX)   |   is-system-running --wait|
  +--------------------+            |  |  |              |   -> LED brightness, PA6  |
                                    +--+--+--------------+---------------------------+
```

The host owns the experiment and owns nothing else. It commands the supply,
streams samples, and afterwards derives four numbers per boot from the
recording:

| Number | From | What it covers |
|---|---|---|
| `t_uboot` | first **rising** edge of D1 | BROM plus SPL, before any storage is scanned |
| `t_console` | first **falling** edge of D2 | U-Boot, the kernel load and the decompression, up to the first console byte |
| `t_done` | first **rising** edge of D0 | everything, to the end of the systemd startup job queue |
| `E` | `5.0 V * sum(I) * dt` over `[0, t_done]` | energy for one whole boot, in joules |

D2 is the console TX line, which idles high and falls on the start bit of
the first character. That is why the console edge is a falling one and the
two marker edges are rising: they are different kinds of signal and reading
them the same way would put the first console byte at an arbitrary point
inside the first printed line.

### Ownership

The table that prevents the commonest class of bug here, which is two
managers on one resource. On this project one row of it is also a way to
damage hardware.

| Resource | Owner | Everyone else |
|---|---|---|
| The board's 5 V rail | **the PPK2 alone**, in source-meter mode | the micro USB port is **empty** during every measurement. Two supplies on one net means the PPK2 measures part of the current, or none |
| The COM port | **one process at a time** | the Power Profiler desktop app holds it open. It is used for the logic self-test and then closed, before `ppk2_boot.py` runs |
| PG11 (line 203) | **U-Boot**, via `CONFIG_PREBOOT` | nothing in the Linux device tree claims it, so it holds the level U-Boot left it at for the rest of the boot |
| PA6 (gpiochip0 line 6) | **the kernel**, as the `gpio-leds` child named `boot-marker` | no `libgpiod` or raw sysfs writer. The marker unit writes `brightness`, which is the LED class interface, not the GPIO |
| UART0 TXD | U-Boot, then the kernel console | D2 and the cable's white lead **listen**. Neither drives it |
| The time base | **the PPK2's sample clock** | no timestamp from the board is used for any reported number. `systemd-analyze` is a cross-check, not a source |
| `results/<variant>/` | `analyze.py` | nothing in there is edited by hand, so the table can be regenerated |

## Schematic

Everything shares the PPK2's ground, and that is the only thing every
signal has in common.

```
   nRF-PPK2                                        NanoPi NEO Air
   source meter 5.0 V
  +------------------+                            +--------------------------+
  |            VOUT  o----- 5 V, max 1 A ---------o pin 2   VDD_5V           |
  |            GND   o----- common ground --------o pin 6   GND              |
  |                  |                            |                          |
  | logic VCC (REF)  o===== 3.3 V reference =======o pin 1   SYS_3.3V         |
  | logic GND        o----- common ground --------o pin 6   GND              |
  |            D1    o----- U-Boot started -------o pin 7   PG11   (3.3 V)   |
  |            D2    o----- console TX ~~~~~~~~~~~o debug 3 TXD0   (idle hi) |
  |            D3    o- - - level self-test - - - o pin 17  SYS_3.3V         |
  |            D0    o----- boot complete --------o pin 12  PA6    (3.3 V)   |
  +------------------+           |                +--------------------------+
        | USB                    |
        v                        +--[330R]--|>|--- GND (pin 9)
   Windows host                              green LED, visible marker

   micro USB supply: DISCONNECTED during every measurement
   USB/TTL cable:  white -> debug 3 (TX, in parallel with D2)
                   green -> debug 4 (RX)
                   black -> debug 1 (GND)
                   red   -> left open
```

| Signal | NEO Air pin | PPK2 or cable | Note |
|---|---|---|---|
| 5 V supply | 24-pin header pin 2 (`VDD_5V`) | PPK2 `VOUT` | source-meter mode, 5.0 V |
| Ground | 24-pin header pin 6 (`GND`) | PPK2 `GND` | common reference |
| **Logic level reference** | 24-pin header pin 1 (`SYS_3.3V`) | PPK2 logic port `VCC` | **required**, 1.65 to 5.5 V. Without it the level shifter has no reference and D0, D1 and D2 all read nothing |
| Logic ground | 24-pin header pin 6 (`GND`) | PPK2 logic port `GND` | the same ground as the supply |
| Boot-complete marker | pin 12 (PA6, `gpiochip0` line 6) | PPK2 `D0` | 3.3 V logic, also drives the LED |
| U-Boot marker | pin 7 (PG11, line 203) | PPK2 `D1` | set by U-Boot preboot |
| Console activity | debug header pin 3 (UART0 TXD) | PPK2 `D2`, cable white | idle high, falls on the first start bit |
| Console RX | debug header pin 4 | cable green | |
| Console GND | debug header pin 1 | cable black | |
| LED | pin 12 via 330 ohm to pin 9 (GND) | | optional, visible marker |

The specification's wiring table carries a caution worth repeating rather
than paraphrasing: the `VDD_5V` header pins are on the same net as the
micro USB 5 V, and that is to be confirmed against the schematic of this
board revision before the supply is switched on.

### The logic port has its own reference, and the specification does not mention it

**This section previously said the PPK2's logic inputs are referenced to
the voltage domain of the device it powers, and that 3.3 V markers under a
5.0 V supply might therefore not be readable at all. That was wrong, and
the correction matters more than the error did.**

The logic port carries **VCC and GND pins of its own**, alongside D0 to
D7. VCC is the level shifter's reference and Nordic's documentation
requires it in the range 1.65 to 5.5 V. Tie it to the board's 3.3 V rail
and 3.3 V markers are read correctly no matter what `VOUT` is set to. The
supply voltage and the logic domain are simply separate, which is what the
port is built for.

**The specification's wiring table does not list that pin.** Following it
exactly leaves the level shifter with no reference, and then D0, D1 and D2
read nothing, all three at once. That is precisely the symptom its own
self-test was written to detect, so the self-test would have reported the
method broken and been believed. A false negative here would have ended
the project on a missing jumper.

So the self-test stays, and it is now a wiring check rather than a
question about the instrument:

| PPK2 | NEO Air |
|---|---|
| logic `VCC` | pin 1, `SYS_3.3V` |
| logic `GND` | pin 6, `GND` |
| `D3` | pin 17, `SYS_3.3V` |

Pin 1 and pin 17 are the same net, so D3 sits at its own reference and must
read high. Two pins rather than one wire doubled back, because a single
point of contact that has come loose looks identical to a level that
cannot be read.

What remains genuinely unknown is smaller and is stated in the acceptance
table: whether **this** board's rails, wires and connector do what the
documentation says. That is what the first session answers.

**Source meter, or ampere meter in series?** The appendix says of the PPK2
that it cannot power a Pi with peripherals and directs it to "ampere-meter
mode in series with the supply of the NanoPi NEO Air". The section
specifies source-meter mode at 5.0 V, and so does its measurement script.

**This design follows the section, and the reason is the experiment rather
than the instrument.** A boot measurement has to begin from a board that is
genuinely off, and only source-meter mode can switch the DUT rail: the
script powers off, waits for the rails to discharge, starts recording, and
only then powers on, so sample zero is before the BROM runs. In
ampere-meter mode the PPK2 cannot cut power, an external switch would sit
in the path, and the interval `[0, t_done]` that the energy figure is
defined over would have no defined start.

The appendix's caution still applies as a limit rather than as a mode: the
PPK2 sources at most 1 A, and the NEO Air stays well under that during boot
as long as nothing is plugged into its USB. The measured peak current is
reported in every run's summary precisely so that the assumption is checked
by the data rather than asserted once here.

### The assumption in the energy figure

The PPK2 measures current. It does not measure the voltage at the board.
`E = 5.0 V * sum(I) * dt` therefore assumes 5.0 V **at the header**, and
long thin jumper wires drop tens of millivolts at 400 mA. The wires are
kept short, and the assumption is stated in the report next to the number
rather than left implicit. This is the same class of statement as the
external instrument's clock offset in Project 8: a systematic effect that
is small, known, and named.

## Bench layout

```
   +------------------+
   |  Windows host    |
   |  ppk2_boot.py    |
   +--------+---------+
            | USB
            v
   +------------------+        VOUT, GND, D0, D1 to the 24-pin header
   |   nRF-PPK2       |------\  D2 to the debug header TX
   | source meter 5 V |       \
   |  logic port      |        \      +-------------------+
   +------------------+         >---->| NanoPi NEO Air    |      breadboard
                                      |  header:          |     +-----------+
                                      |   2 5V   6 GND    |     |  o  o  o  |
                                      |   7 PG11 12 PA6   |---->|   green   |
                                      |                   |     |  LED+330R |
                                      | micro USB: EMPTY  |     +-----------+
                                      +---------+---------+
                                                | USB/TTL
                                                v
                                        +----------------+
                                        |  host PC       |
                                        | picocom 115200 |
                                        +----------------+
```

The console cable's red lead is left open. It carries 5 V from the host and
would be a second supply on a board whose whole measurement depends on
having exactly one.

## One measured boot, as a sequence

```
 host script      PPK2          BROM+SPL      U-Boot       kernel+systemd   marker unit
     |             |               |             |               |               |
     |--source meter, 5000 mV----->|             |               |               |
     |--start_measuring, power ON->|             |               |               |
     |             |==VOUT 5 V====>|             |               |               |
     |             |               |--loads SPL, then U-Boot---->|               |
     |             |<----------- preboot: gpio set PG11 (D1 high)|               |
     |             |               |             |--bootz zImage + dtb---------->|
     |             |<--------- console output on TXD0 (D2 falls) |               |
     |             |               |             |               |--start unit-->|
     |             |               |             |               |               |
     |             |               |       is-system-running --wait returns when |
     |             |               |       the startup job queue is empty        |
     |             |<--------- echo 1 to boot-marker brightness (D0 high)--------|
     |<-samples + D0 D1 D2---------|             |               |               |
     |--power OFF, stop----------->|             |               |               |
     |                                                                           |
     E = 5.0 V * sum(I) * 10 us          phases from the D1, D2 and D0 edges
```

### Why the marker unit waits instead of being ordered

A unit that is `WantedBy=multi-user.target` and also `After=multi-user.target`
is an ordering cycle. systemd breaks a cycle by dropping a unit from the
transaction, and the unit it drops may be this one, in which case **the
marker never rises and the run looks like a board that failed to boot.**
That failure is indistinguishable from the real thing it is meant to detect.

So the unit is ordered only `After=basic.target`, and the waiting is done
at runtime by `systemctl is-system-running --wait`, which returns when the
startup job queue is empty. That is the same definition of "boot complete"
that `systemd-analyze time` reports, which is what lets the electrical
number and the console number be compared at all: the second acceptance
criterion requires them to agree within 0.2 s, and they can only be
compared if they mean the same thing.

`is-system-running` returns `running` or `degraded`. **The marker rises
either way**, deliberately: a degraded startup is still a finished startup,
its duration is a real measurement, and the degradation is visible in the
journal. Raising the marker only on `running` would silently discard the
runs most worth looking at.

## Data flow

```
  one boot
    ppk2_boot.py  ->  results/<variant>/boot-NN.csv     t_s, i_ua, d0, d1, d2
                       one row per sample at 100 kS/s

  five boots of one variant
    analyze.py    ->  results/<variant>/summary.md      mean and sd of
                                                        t_uboot, t_console,
                                                        t_done, energy_J
                  ->  results/<variant>/current.png     trace with marker lines

  all variants
    docs/before-after.md                                one row per variant
```

Variants, one directory each, one change each:

| Directory | Change |
|---|---|
| `00-baseline` | the unmodified Project 2 system |
| `10-uboot` | `BOOTDELAY=0`, no USB or PXE or DHCP probing, `boot_targets=mmc1` |
| `20-kernel-trim` | `localmodconfig` plus manual trimming, `quiet loglevel=3` |
| `21-kernel-lz4` | compression variants, gzip against LZ4 against XZ |
| `30-systemd` | masked and disabled units, volatile journal |
| `40-final` | everything, with and without `wpa_supplicant@wlan0` |

## Discard rules, decided before any data exists

These are written here rather than in the analysis script's comments
because a rule invented after seeing the numbers is not a rule.

- **A run where D1 does not rise within 0.5 s of the supply coming on is
  discarded, not averaged.** The bootloader did not start. Averaging it in
  would report a slow boot for a board that did not boot.
- **The first run of every variant is discarded.** A filesystem change can
  trigger a long `fsck` on the next mount, and that is a property of the
  previous run rather than of the variant being measured.
- Five runs per variant after those discards, with mean and standard
  deviation reported for every number.

## What gets built

| Path | What | Runs on |
|---|---|---|
| `measure/ppk2_boot.py` | one boot: power off, record, power on, detect D0, power off, write CSV | Windows host |
| `measure/analyze.py` | CSV to phase times, energy, summary and plot | Windows host |
| `measure/requirements.txt` | `ppk2-api`, `numpy`, `matplotlib` | |
| `measure/Makefile` | six boots of one variant with the supply down between them, then the analysis | Windows host |
| `board/boot-marker.service` | raises the marker when the job queue empties | NEO Air |
| `board/0001-dts-boot-marker-led.patch` | the `gpio-leds` child on PA6 | applied in the kernel tree |
| `board/units-disabled.txt` | every unit masked or disabled, with its reason and what brings it back | |
| `uboot/fragments/fast.config` | preboot marker, then the U-Boot trimming | |
| `kernel/fragments/*.cfg` | `trim`, and the three compression variants | |
| `tests/boot-energy-*-test.sh` | everything provable with no hardware | either laptop, and CI |
| `NEO_EXTRA_FRAGMENT` | Project 2's build scripts take one extra fragment, which is how every variant here reaches a build | wsl laptop |
| `docs/before-after.md` | one row per variant, assembled from the summaries | |

The measurement scripts are the part that can be tested without the board,
the PPK2, or Project 2, and they are where the analysis errors would
otherwise hide: an edge detector that finds the wrong edge, an energy
integral over the wrong interval, a summary that averages a discarded run.
Synthetic traces with known answers settle all three, and that is what the
test suite does.
