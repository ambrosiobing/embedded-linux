# Project 16: a low-power Cat-M and NB-IoT tracker

**Board:** Raspberry Pi 3. **Theme:** AT state machines, CoAP over UDP,
PSM and eDRX, current budget.

Project 15 put a cellular modem on a network and left it there. This one
does the opposite: attach, send one position, and sleep for hours at
microamps. The subject is not connectivity, which is solved, but the ratio
between a device's waking and sleeping current, and whether the sleep the
network actually granted is the sleep that was requested.

That makes the instrument part of the design rather than an appendix, and
[docs/DESIGN.md](docs/DESIGN.md) puts it second, before the architecture.

## State

**Written and tested on a laptop, not yet built, not yet powered, as of
Monday 21 September 2026.**

The state machine, the GPIO tool, the recipe, the image, the kas
configuration, the charge arithmetic and three test suites exist.
`python scripts/lint.py` passes. `sh tests/tracker-at-test.sh` passes with
75 assertions and `sh tests/tracker-budget-test.sh` with 24, both on this
laptop.
`sh tests/tracker-state-test.sh` has **never run anywhere**: it needs a
pseudo-terminal, the Windows authoring laptop has none, and it skips there
rather than failing. It runs on the WSL laptop and in CI, and until one of
those has run it, it is a suite that has been written rather than a suite
that passes.

No BitBake build has been attempted and no board has been powered, so every
acceptance criterion below is still open.

Two parts of the design are deliberately unwritten rather than merely
unfinished, and both wait on the board rather than on effort:

- **the kernel fragment**, because nothing in this repository records how a
  SIM7070G enumerates on USB, and a fragment written from a guess is how
  Project 1 lost two rounds on `wlan0`
- **the schematic's pin table**, because the HAT's logic voltage is
  selectable between 5 V and 3.3 V by a 0-ohm resistor, and 5 V into a Pi
  GPIO destroys the pin

## What this project has that most do not

Its hardware. The bench carries both a **SIM7070G Cat-M/NB-IoT/GPRS HAT**
and a **SIM7020E NB-IoT HAT**, a **Nordic PPK2**, and an **MCC 118**.
Projects 10 and 17 were specified around parts that are not here; this one
was checked against the inventory before its design was written, which is
recorded as journal entry 1.

Two modems rather than one is the useful part. The SIM7070G does Cat-M,
NB-IoT and GPRS; the SIM7020E does NB-IoT only. Running the same tracker
against both makes the second modem a control, in the way Project 8 uses a
generic kernel against a real-time one.

## What this project adds to the repository

| Path | What | State |
|---|---|---|
| `meta-bench/recipes-bench/bench-tracker/files/tracker` | The AT state machine, in Python, standard library only | written |
| `meta-bench/recipes-bench/bench-tracker/files/tracker-gpio.c` | The power key and the instrument marker, on libgpiod v2 | written, never compiled |
| `meta-bench/recipes-bench/bench-tracker/files/78-sim7070.rules` | udev. **Incomplete on purpose**: it names every SIMCom tty by interface number so the AT port can be found, and the precise rule is commented out until the board has been read | written |
| `meta-bench/recipes-bench/bench-tracker/bench-tracker_0.1.bb` | The recipe | written, never built |
| `meta-bench/recipes-core/images/bench-tracker-image.bb` | The image, deliberately without ModemManager | written, never built |
| `kas/bench-tracker.yml` | `./go tracker` | written |
| `tests/tracker-at-test.py` and `.sh` | Parsers, timer octets, CoAP, and the state machine in process | **passing**, 75 assertions |
| `tests/fake-modem.py` | A pty that answers AT from a table of scenarios | written |
| `tests/tracker-state-test.sh` | The same scenarios through a real serial port | written, **never run** |
| `meta-bench/recipes-kernel/linux/files/tracker.cfg` | The USB serial drivers this modem needs | **not written**, and not until `lsusb` has been read on the board |
| `projects/16-nbiot-tracker/measure/budget.py` | Charge per report from a capture, with the refusals that stop a dishonest number being printed | **passing**, 24 assertions |
| `tests/tracker-budget-test.py` and `.sh` | Synthesised traces whose answers were worked out before the program ran | **passing** |
| the PPK2 capture program | Records one report cycle | **not written**, blocked on the marker GPIO offset |

## Running it

What runs today, with no board:

```sh
sh tests/tracker-at-test.sh
```

```sh
sh tests/tracker-state-test.sh
```

The second needs a pseudo-terminal and skips where there is none, which
includes the Windows authoring laptop. Both are picked up by `./go check`,
which runs everything in `tests/`.

What the board will need, in order:

```sh
./go tracker
```

```sh
./go flash /dev/sdX
```

`./go ksym -f tracker` and `./go kconfig -f tracker` belong between those
two and cannot run yet, because the fragment they would check does not
exist. The first build is a reconnaissance build: it is expected to boot
with the modem attached and no tty for it, and `lsusb` is installed so that
boot answers the question the fragment is waiting on.

## What is deliberately absent, and what it costs

No ModemManager, no NetworkManager, no QMI, no `wwan0`. Project 15
installs all four and is right to; this project installs none.

The reason is not taste. ModemManager's job is to always know the modem's
state, which it does by polling it, and PSM is the modem being left alone
for hours. Every query is a wake-up.

Project 15's README already wrote the case against this choice, before this
project existed:

> A shell script driving AT commands. That is Project 16's subject and it
> gives up every one of those properties

It is right, and the table is the honest accounting:

| Lost | Gained |
|---|---|
| Registration, bearer, signal and location as D-Bus properties | The modem is not woken to answer questions about itself |
| `mmcli` as a debugging tool | Every byte on the wire in one log, in order |
| Automatic re-attach | An explicit state machine whose transitions are testable |
| `lte-watchdog` and `lte-exporter` | A program small enough to reason about at 3 in the morning |

## Acceptance criteria

"Configured" means a file says so; "measured" means a board did. Nothing in
this table is measured on Monday 21 September 2026.

| # | Criterion | Evidence | State |
|---|---|---|---|
| 1 | The modem powers on under software control and answers `AT` | the PWRKEY pulse in the log, then `OK` | **Not started.** Needs the PWRKEY pin confirmed against the board |
| 2 | It attaches to Cat-M or NB-IoT, and never to GPRS | `AT+CNMP=38`, then `+CEREG` showing registered, and no 2G in the whole transcript | **Not started.** The GPRS lockout is also an instrument requirement, criterion 7 |
| 3 | One position fix is obtained and sent as a CoAP POST, and the server acknowledges it | the AT transcript and the server's log, with matching timestamps | **Not started** |
| 4 | The PSM values the network granted are read back and recorded, and they are not assumed to be the values requested | `AT+CPSMS?` and the `+CEREG` URC after attach | **Not started.** This is the criterion most likely to surprise: a network may grant less than asked, or nothing |
| 5 | The current trace shows the modem entering PSM, with the sleeping current and the waking current both reported | a PPK2 capture with the report marker on a logic channel | **Not started** |
| 6 | A charge budget per position report, in millicoulombs, with the integration interval stated | the same capture, integrated between markers | **Not started.** This is the number the project exists to produce |
| 7 | No sample in any published trace is at the instrument's ceiling | peak current reported per run, against the PPK2's 1 A limit | **Not started.** Project 3 has already published a peak above that rating and had to withdraw it |
| 8 | eDRX is measured as well as PSM, so the trade between reachability and current is a number rather than an opinion | two captures, same tracker, same report interval | **Not started** |
| 9 | The same tracker runs against the SIM7020E and its budget is reported beside the SIM7070G's | two rows in the same table | **Not started.** The second modem is the control |

Two further criteria this repository asserts that the theme does not ask
for:

| # | Criterion | State |
|---|---|---|
| 10 | The state machine is testable with no modem present | **Met.** The program reaches the modem only by writing a line and reading lines back, and everything else outside the process by name through PATH. Both seams are exercised: 75 assertions run in process, and the same scenarios run again through a pseudo-terminal |
| 11 | Every AT response the parser accepts came from a real transcript rather than from memory | **Not met, and the whole modem command table is provisional.** Every string in `MODEMS` and every response in `tests/fake-modem.py` was read out of the SIM7070G AT command manual, which is a claim about the part rather than an observation of it. Project 8 shipped a cyclictest parser written against a remembered format and every row it produced was blank. The first transcript in `docs/evidence/` replaces the tables |

## What is tested without hardware

| Check | Command | Covers | State |
|---|---|---|---|
| Parsers, timer octets, CoAP, and the machine | `sh tests/tracker-at-test.sh` | The `+CEREG`, `+CSQ`, `+CPSMS` and `+CARECV` parsers including their refusal paths, both 3GPP timer tables, RFC 7252 message construction byte for byte, the configuration reader's three Windows traps, and every transition against the scenario tables in process | **75 passing** |
| The same scenarios through a serial port | `sh tests/tracker-state-test.sh` | All of the above plus the transport: a real `open`, `termios`, timed reads, the send prompt, and `tracker-gpio` reached through PATH | **never run**; needs a pty |
| The budget arithmetic | `sh tests/tracker-budget-test.sh` | Charge, duration, mean, peak and idle current from traces whose answers were worked out before the program ran, plus every refusal: a clipped sample, a dropped-sample gap, a missing marker, a channel that is not there, a wrong header, a one-sample file and a truncated one | **24 passing** |

Two of the assertions were proven by breaking what they check and watching
them fail: making `note_granted` echo the requested PSM values instead of
the granted ones fails four assertions, and making an unacknowledged report
return to `REGISTERED` instead of `BACKOFF` fails one. A check that has
never failed is not a check that is working.

**What none of it proves.** That the modem attaches, that it answers
anything like the tables say, that the network grants any PSM at all, or
that a single current figure is right. The suites drive a fake modem whose
answers were written from a manual. Whether the real part behaves like the
fake is exactly what criteria 1 to 9 are for, and they need the board.

## Deferred, with reasons

| What | Why | What would close it |
|---|---|---|
| The kernel fragment | Nothing here records how a SIM7070G enumerates. Project 15's `router.cfg` provides `option` and `qmi_wwan` and carries no `cdc_acm` and no PPP, and that fragment is gated as one unit that also drags in the whole netfilter stack a tracker has no use for | `lsusb` and `dmesg` from the first power-on |
| The schematic's pin table | The HAT's logic voltage is 5 V or 3.3 V by a 0-ohm resistor, and its PWRKEY jumper is described in wiringPi numbering. A pin number is a property of a board revision rather than of a part | Read the board. Three facts, listed in `docs/evidence/README.md` |
| LwM2M | CoAP is the transport and LwM2M is a device-management layer on top of it. The tracker needs the first to report at all; the second is worth adding once a report has ever been acknowledged | A working CoAP path, then a decision about which LwM2M implementation fits an image this size |
| Measuring the processor's own current | The PPK2 goes on the modem's rail, so the Pi's draw is a separate question and this project does not answer it | A second capture, which Project 3's tooling can already take |

**The supply is the hazard here, as it was on Project 5.** The HAT takes
5 V from the header and the PPK2 must be the only supply during a
measurement. Project 3 states it plainly: leaving the other cable connected
"joins two supplies and the PPK2 then measures" something that is not the
device.
