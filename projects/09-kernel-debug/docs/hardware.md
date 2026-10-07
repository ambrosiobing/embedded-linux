# Hardware for project 9, from the datasheet down to the wire

This project needs very little hardware and spent an afternoon on it
anyway. That makes it a good place to show the whole chain: what the
silicon can do, what the device tree asks for, what the kernel then does,
and what finally appears on a pin. Every claim below says where it came
from, using the evidence levels in [docs/HARDWARE.md](../../../docs/HARDWARE.md).

If you are new to this board, the short version is that **two pins on the
header can carry either of two completely different UARTs, and which one
they carry is a three bit field in a register.** Almost everything that
went wrong here follows from that.

## What this project needs on the bench

| Thing | Why | Evidence |
|---|---|---|
| Raspberry Pi 3 Model B Plus Rev 1.3 | the target | `measured`, the board reports it in its oops banner |
| microSD card | the image | |
| Joy-it LK-LED10 module | the heartbeat LED, which is how you see a kernel stop without a console | `measured`, see below |
| Renkforce PL2303HXA USB/TTL cable | the serial console, which kgdb needs | `measured` |
| `agent-proxy` on the host | splits that one cable into a console port and a gdb port | |

No HAT. Nothing stacked. The only thing driven from software is the LED,
and even that is driven by a kernel trigger declared in `config.txt`
rather than by any program.

## The heartbeat LED

A **Joy-it LinkerKit LK-LED10**, 10 mm, with its own fitted resistor `R1`.

| Connection | Pi header pin | BCM |
|---|---|---|
| module `S1` | pin 11 | GPIO17 |
| module `G` | pin 9 | GND |
| module `U`, `S2` | not connected | |

**The module needs signal and ground only.** `measured` Friday 2 October
2026: one module had `U` wired and lit identically with that jumper
pulled.

**The signal pin is the anode side, so the header pin sources current.**
A pin driven high is lit, low is dark, and a line released to an input is
dark and reads low. `measured` on a Raspberry Pi 3 Model B Rev 1.2,
gpiochip0, pinctrl-bcm2835, 54 lines, libgpiod v2.2.1. Which way round the
LED sits is not printed on the board, so test one before wiring three:
drive high, drive low, release.

Current, `measured` with the nRF PPK2 on Saturday 3 October 2026, each
module alone on the source meter:

| | blue | green | yellow | red |
|---|---|---|---|---|
| at 3.300 V | 2.94 mA | 7.39 mA | 6.20 mA | 6.34 mA |
| effective R | 247 ohm | 198 ohm | 246 ohm | 249 ohm |
| derived Vf | 2.57 V | 1.84 V | 1.77 V | 1.72 V |

**These are the instrument's readout, not four significant figures of
accuracy.** The PPK2 user guide states accuracy "better than plus or minus
20 per cent (average currents measurement)", so the milliamp values carry
that uncertainty and the derived resistance and forward voltage inherit
it. The comparison between the four modules is still sound, because they
were measured the same way on the same instrument within minutes; it is
the absolute values that should not be read as precise. Source: PPK2 user
guide, Nordic Semiconductor, read Wednesday 7 October 2026.

Any of the four is fine here. A few milliamps from one GPIO is nowhere
near the pin's limit, and the project only ever lights one.

**Why an LED at all, in a project about debuggers?** Because it is the one
diagnostic that does not depend on anything else working. When the kernel
stops, the trigger's timer stops with it, so the LED **freezes** at
whatever brightness it had. It usually looks dark, because heartbeat is
off most of the time, but frozen and dark are different states and the
difference tells you the kernel stopped rather than the board rebooted.
That signal survives a dead console, which this bench has, and it survives
a dead network.

## The serial console, from the register up

Here is the chain the whole afternoon of Tuesday 6 October 2026 turned on.
It is worth following once in full, because every link looks fine when the
one below it is broken.

### 1. The silicon: two UARTs, one pair of pins

**Source: BCM2835 ARM Peripherals, Broadcom, 6 February 2012.** The
BCM2837 in a Pi 3 keeps the same peripheral layout; what changes is where
it appears in physical memory, which is the next section.

From **Table 6-31, page 102**, the alternate function assignments:

| Pin | Default pull | ALT0 | ALT1 | ALT5 |
|---|---|---|---|---|
| GPIO14 | Low | `TXD0` | `SD6` | `TXD1` |
| GPIO15 | Low | `RXD0` | `SD7` | `RXD1` |

and from the legend on **page 103**: `TXD0` is "UART 0 Transmit Data" and
`RXD0` is "UART 0 Receive Data". UART0 is the PL011. The `TXD1` and `RXD1`
of ALT5 are the mini UART.

**So which UART those two header pins carry is nothing but the alternate
function number.** ALT0 gives you the PL011. ALT5 gives you the mini UART.
Same copper, same pins 8 and 10, different peripheral entirely. That is
the fact underneath `disable-bt`, and it is why "the UART" is an ambiguous
phrase on this board.

### 1a. The board maker's own confirmation, added later

Everything above comes from the chip vendor. On Wednesday 7 October 2026
the board vendor was read too, and it agrees.

**Source: Raspberry Pi 3 Model B+ reduced schematic, revision V1.0, sheet
1 of 1, drawn by Roger Thornton, dated Monday 19 March 2018, copyright
Raspberry Pi 2018.** In the GPIO EXPANSION block, the nets between the SoC
symbol `U1C` and `J8`, the 40 way header, carry alternate function names
in brackets. `GPIO14` is annotated `(TXD0)`. `GPIO15` is annotated
`(RXD0)`.

**Source: Raspberry Pi 4 Model B Datasheet, release 1.1, 12 March 2024,
Table 5, page 10.** `GPIO14` is `TXD0` on ALT0 and `TXD1` on ALT5;
`GPIO15` is `RXD0` on ALT0 and `RXD1` on ALT5. Identical to Broadcom's
Table 6-31 for the two rows that matter.

**Why bother, when the first source was already clear?** Because this
project spent an evening on a console that did not work and the wiring was
never the fault. When a chain of reasoning has cost that much, the cheapest
thing you can do afterwards is find a second, independent document that
says the same thing, and either sleep better or find out early. Here it is
the first.

**One warning that travels with the Pi 4 table.** Its ALT4 column lists
`TXD2` through `TXD5`, four UARTs that BCM2711 added and **that the Pi 3
does not have**. The table confirms ALT0 and ALT5 for this board and must
not be used for anything else on it. The wider version of that point is in
[docs/HARDWARE.md](../../../docs/HARDWARE.md).

### 2. The register that holds that choice

From **Table 6-1, page 90**, the GPIO registers begin at bus address
`0x7E20 0000`, and the function select registers are the first six:

| Bus address | Register |
|---|---|
| `0x7E20 0000` | GPFSEL0 |
| `0x7E20 0004` | GPFSEL1 |
| `0x7E20 0008` | GPFSEL2 |

Each GPIO gets **three bits**. From **Table 6-3, page 92**, GPFSEL1 covers
FSEL10 to FSEL19, with **FSEL14 at bits 14 to 12** and **FSEL15 at bits 17
to 15**.

The encoding, from **Table 6-2, page 92**, quoted because the ordering is
not what you would guess:

```
000 = input
001 = output
100 = alternate function 0
101 = alternate function 1
110 = alternate function 2
111 = alternate function 3
011 = alternate function 4
010 = alternate function 5
```

**ALT0 is binary 100, which is 4.** That is where the `pin_func=4` in this
project's `config.txt` line comes from, and the reset value for every pin
is `000`, plain input.

So a correctly muxed console contributes `4 << 12` from GPIO14 and
`4 << 15` from GPIO15, which is **`0x24000` set in GPFSEL1**.

### The same thing as one picture

Also drawn as [`figures/uart-mux.tex`](figures/uart-mux.tex), which
compiles with `make uart-mux.pdf`. Nothing in the build depends on TeX, so
here it is in text as well:

```
            GPFSEL1, bus 0x7E20 0004                 Table 6-1, page 90

  bit    17   16   15 | 14   13   12
       +----+----+----+----+----+----+
       |     FSEL15   |    FSEL14    |               Table 6-3, page 92
       +--------------+--------------+
              |               |
              |               +--  000   input, the reset value
              |               +--  100   ALT0, which is pin_func=4
              +------------------  010   ALT5
                                                     Table 6-2, page 92
  000  ->  nothing on the pin, a GPIO nobody drives
  100  ->  TXD0 and RXD0, the PL011,    3f201000.serial
  010  ->  TXD1 and RXD1, the mini UART, 3f215040    Table 6-31, page 102

  header pin 8 = GPIO14          header pin 10 = GPIO15
```

**The encoding is not sequential**, which is worth pausing on: ALT0 is
`100` and ALT5 is `010`, so a value that looks like "2" is not alternate
function 2. And a pin sitting at `000` is not broken; it is still an
input, which is exactly where this bench's pins were.

All four tables are in BCM2835 ARM Peripherals, Broadcom, 6 February 2012.
The figure redraws them rather than reproducing them, and names the source
on its face.

### 3. The address trap between a Pi 1 and a Pi 3

The datasheet gives **bus** addresses beginning `0x7E...`. The ARM sees
them at a different physical base depending on the SoC:

| SoC | Board | ARM physical peripheral base | GPFSEL1 at |
|---|---|---|---|
| BCM2835 | Pi 1, Zero | `0x2000 0000` | `0x2020 0004` |
| BCM2836, BCM2837, BCM2837B0 | Pi 2, Pi 3, Pi 3B+ | `0x3F00 0000` | `0x3F20 0004` |

`inferred` from the bus address plus the known peripheral base for this
family, not stated in this document, which predates the Pi 3. **Worth
stating explicitly because the datasheet you reach for is the BCM2835
one and the board on the bench is a BCM2837B0**, as the Raspberry Pi 3
Model B+ product brief of October 2025 states on page 3. An address copied
straight out of the PDF reads the wrong place on a Pi 3, and reads it
without complaining.

On this bench the question is academic anyway: `/dev/mem` refuses with
`Bad address`, so the register cannot be read directly and the kernel's own
view has to be used instead.

### 4. What the kernel exposes instead

Two files, both readable over ssh, and between them they answer the whole
question without `/dev/mem`:

```sh
grep -E 'pin 14|pin 15' /sys/kernel/debug/pinctrl/*/pinmux-pins
wc -c /proc/device-tree/soc/gpio@7e200000/uart0_pins/brcm,pins
```

A muxed pin reads `3f201000.serial (GPIO UNCLAIMED) function alt0 group
gpio14`. An unmuxed one reads `(MUX UNCLAIMED) (GPIO UNCLAIMED)`.

## The decisions, in the order they were made

### Why `disable-bt`

On a Pi 3B+ the PL011 is wired to the Bluetooth radio by default and the
mini UART is on the header. `kgdboc=ttyAMA0` on a board without
`disable-bt` therefore attaches the debugger to a UART that is not on the
header, and debugs nothing, silently. `disable-bt` swaps them, which the
device tree aliases confirm: `serial0` becomes `/soc/serial@7e201000`, the
PL011, and `serial1` becomes `/soc/serial@7e215040`, the mini UART.

That decision was right and is unchanged.

### Why `dtoverlay=uart0,...` had to be added as well

**This is the one that was missed, and it cost an afternoon.**

`disable-bt.dtbo` moves the UART and **does not mux the pins**. Decompiled
off the card with `dtc`:

```
fragment@3 {
        target = <0xffffffff>;
        __overlay__ {
                brcm,pins;
                brcm,function;
                brcm,pull;
        };
};
```

Those are **empty** properties. The overlay blanks the pin group and
leaves the real values to the VideoCore firmware, and on this image the
firmware does not supply them. The group then names no pins and no
function, pinctrl has nothing to map, and GPIO14 stays a plain input at
its reset value of `000`.

Every other indicator says the console is fine, which is what makes it
expensive: `enable_uart=1` is set with no conditional filter above it, the
Bluetooth child reads `disabled`, `console=ttyAMA0,115200` is in the
command line, `/proc/consoles` lists `ttyAMA0` as enabled, the driver
probes and prints `console [ttyAMA0] enabled`, and every write to
`/dev/ttyAMA0` returns success. One line, at about 4.6 seconds, says
otherwise:

    uart-pl011 3f201000.serial: there is not valid maps for state default

and it is printed on the console that does not work.

The fix, now in [`kas/bench-debug.yml`](../../../kas/bench-debug.yml):

    dtoverlay=uart0,txd0_pin=14,rxd0_pin=15,pin_func=4

`pin_func=4` is ALT0 by Table 6-2, which is `TXD0` and `RXD0` by Table
6-31. After it, `measured`:

    pin 14 (gpio14): 3f201000.serial (GPIO UNCLAIMED) function alt0 group gpio14
    uart0-gpio14/brcm,pins      00 00 00 0e 00 00 00 0f
    uart0-gpio14/brcm,function  00 00 00 04

`0e` and `0f` are 14 and 15, and the "not valid maps" line is gone.

**And the console still produced nothing on the host.** A second fault
remains between a correctly muxed GPIO14 and the laptop, unidentified as
of Tuesday 6 October 2026. The fix above is in because the unmuxed pins
were real and measured, not because the console works.

## Wiring, rewiring, and why most of it was beside the point

This section is the honest part, and it is here because the reasoning is
more useful than the outcome.

**What was wired**, following the bench's standard mapping: black to pin 6
GND, white to pin 8 GPIO14 `TXD0`, green to pin 10 GPIO15 `RXD0`, red left
open. Correct from the first attempt.

**What was rewired, and why.** White and green were swapped, on the
strength of a run of replacement characters appearing in the terminal when
the console port was first opened. The reasoning was that a floating input
picks up noise, which would fit a reversed pair, since the adapter's
receive lead would then sit on the board's receive pin and be driven by
nothing.

**Why that reasoning was wrong.** Those characters were `agent-proxy`'s own
**telnet negotiation**, arriving raw because the port was being read with
`nc` instead of `telnet`. They had nothing to do with the cable. So a
wiring change was made on evidence that was never about wiring, and the
leads were later put back exactly as they had started.

**The control that should have come first.** Take both signal leads off
the header entirely and bridge them to each other with a straightened
paperclip, then type into the console. Every character came back. That
proves the adapter, both leads along their whole length, `agent-proxy` and
`telnet` in one minute, and it needs no board at all. It was available
from the first silent console and was run last.

**What finally answered it** was not a wiring question:

```sh
ssh root@BOARD "dmesg | grep -i -e pl011 -e uart -e 'valid maps'"
```

one command, available in the first minute.

### The rule this project would like to leave behind

**When a signal path produces nothing, ask the source whether it is
driving before asking the wire whether it is carrying.**

The source answers in one command and in writing. The wire cannot answer
at all without an instrument this bench does not have, and the bench notes
already record a multimeter as the single purchase that unblocks the most
work. This is the second time that has been true on the same day.

## Further reading

- [docs/HARDWARE.md](../../../docs/HARDWARE.md), the shared bench reference
- [docs/DATASHEETS.md](../../../docs/DATASHEETS.md), every primary source with a read marker
- [JOURNAL.md](../JOURNAL.md) entries 26 and 27, the finding and the minute by minute log
- [docs/BRINGUP.md](BRINGUP.md), the ordered first boot
- [docs/DESIGN.md](DESIGN.md), the ownership table that catches two managers on one resource
