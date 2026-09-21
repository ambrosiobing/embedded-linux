# Project 16: design

The drawings before the code. This project's subject is not getting a
modem onto a network, which Project 15 already did. It is how little
current a device can use while still reporting where it is, which makes
the instrument and its limits part of the design rather than an appendix.

| View | Question |
|---|---|
| [Which board](#which-board-and-why-the-repository-disagrees-with-itself) | The repository says two different things, and the hardware settles it |
| [The instrument](#the-instrument-decides-what-may-be-claimed) | What the PPK2 can measure here, and what it cannot |
| [Architecture](#architecture) | What runs where, and what is deliberately absent |
| [Schematic](#schematic) | Which pin goes where. **Partly blocked, and why** |
| [The state machine](#the-modem-as-a-state-machine) | Why AT commands rather than ModemManager |
| [PSM and eDRX](#psm-and-edrx-are-a-negotiation-not-a-setting) | The mechanism the whole project exists to measure |
| [Ownership](#who-owns-what) | Which component owns which device, interface and file |
| [What gets built](#what-gets-built) | The files this project adds |

## Which board, and why the repository disagrees with itself

Two statements, both in the tree, never reconciled:

| Source | Says |
|---|---|
| `README.md:183` | Raspberry Pi 3 |
| `projects/02-neo-air-mainline/docs/DESIGN.md:28` | "Project 16 reuses the same small system for the cellular tracker", meaning the NanoPi NEO Air |

**Decision: Raspberry Pi 3, and Project 2's sentence is wrong rather than
merely different.** Three reasons, the first of which is physical.

The SIM7070G HAT is a Raspberry Pi HAT. Waveshare's own description is a
"Standard Raspberry Pi 40PIN GPIO extension header". The NanoPi NEO Air has
no 40-pin header; Project 2's own design document describes a 24-pin header
and a separate 4-pin debug UART. **The HAT does not stack on that board.**
It could be reached over its onboard USB or wired to UART pins by jumper,
but the part on this bench is a stacking HAT and the boards it stacks on
are the three Raspberry Pis.

Second, Project 2's system is Debian built by hand with no Yocto, so
"reuses the same small system" would put Project 16 outside the layer that
every other project shares. That is a large architectural claim to make in
a subordinate clause of another project's design document.

Third, the sentence was written as a forward-looking aside before either
project existed, which is the same class of claim Project 5 found four of.
It is recorded here as a finding rather than silently contradicted, and
Project 2's document should be corrected to match.

**What is genuinely right about that sentence, and is kept:** a tracker
wants the smallest system that will do the job, because every milliamp the
processor draws is a milliamp the modem's sleep mode cannot save. That
argument is answered below by measuring the modem rather than the system,
which makes the processor's own draw a separate question instead of a
confounding one.

## The instrument decides what may be claimed

This is first because it constrains everything after it. The bench has a
Nordic PPK2 and an MCC 118, and the repository has already recorded, twice,
where the PPK2 stops.

```
projects/15-lte-router/docs/DESIGN.md:132
  "The PPK2 cannot measure this, at 1 A maximum; the instrument for the
   current profile is Project 8's MCC 118 with a low-value shunt."

projects/03-boot-energy/JOURNAL.md, entry 26
  measured peak 1233 mA, "above the PPK2's 1 A rating", so the peak
  "cannot be quoted as a property of the board at all"
```

And a third constraint found the hard way, in Project 3's evidence:

```
projects/03-boot-energy/docs/evidence/logic-selftest.txt:87
  "USB POWER ONLY supplies the DUT and is required in source-meter mode
   above 400 mA. Only DATA/POWER was ever connected, in this session and
   every earlier one."
```

Three consequences, and they shape the whole measurement.

**The PPK2 measures the modem, not the system.** A Raspberry Pi 3 draws
several hundred milliamps doing nothing, and Project 3 measured a NanoPi
NEO Air at 187 mA mean during boot. A modem in PSM draws microamps. Putting
the instrument across the whole system would bury the entire subject of
this project inside the processor's idle current, and the resulting graph
would be a flat line with the answer somewhere in its thickness. So the
PPK2 sits on the modem's supply rail alone. The processor's own draw is a
separate measurement, taken separately, and named as such.

**2G has to be locked out, or the instrument clips.** The SIM7070G
supports GPRS as well as Cat-M and NB-IoT, and a 2G transmit burst is
conventionally around 2 A, well past the PPK2's ceiling. Cat-M and NB-IoT
transmit at far less. `AT+CNMP=38` selects LTE only and is in Waveshare's
own attach sequence, so the lockout costs one command. Without it a
fallback to GPRS during a bad-coverage moment produces a clipped trace that
looks like data.

This is stated as reasoning rather than measurement: the 2 A figure is the
conventional GPRS burst, not something taken on this bench. The first run
checks it, the same way `analyze.py` already reports peak current against
the 1 A limit for Project 3.

**Both micro-USB connectors, every time.** Source-meter mode above 400 mA
needs the USB POWER ONLY connector as well as DATA/POWER, and a modem
attaching to a network will exceed 400 mA. Project 3 ran an entire session
and several earlier ones with only one connected, and the current figures
from those sessions were withdrawn. The bring-up notes for this project put
that first, not in a troubleshooting section.

## Architecture

```
   WINDOWS AUTHORING LAPTOP            RASPBERRY PI 3
  +---------------------------+      +---------------------------+
  | Power Profiler, or        |      | tracker (AT state machine)|
  | ppk2_boot.py's successor  |      |   opens /dev/tracker-at   |
  |   100 kS/s, source meter  |      |   one command at a time   |
  |   5000 mV                 |      |   never two in flight     |
  +------------+--------------+      +-------------+-------------+
               | USB                               | write/read
               |                                   v
  +------------+--------------+      +---------------------------+
  |         PPK2              |      | /dev/ttyS0 or ttyUSB*     |
  |  VOUT ---------------------------+---> modem supply rail     |
  |  GND  ---------------------------+                           |
  |  D0   <--------------------------+--- a GPIO the tracker     |
  |         marks each report        |    toggles per report     |
  +---------------------------+      +-------------+-------------+
                                                   |
                                     +-------------v-------------+
                                     | SIM7070G HAT              |
                                     |  Cat-M1 / NB-IoT / GPRS   |
                                     |  GNSS, PSM, eDRX          |
                                     |  idle about 41 mA         |
                                     +-------------+-------------+
                                                   | antenna
                                                   v
                                          carrier, then a CoAP
                                          server somewhere
```

**What is deliberately absent is the point of the picture.** No
ModemManager, no NetworkManager, no QMI, no `wwan0`. Project 15 installs
all four and is right to. This project installs none of them, and the
reason is in the next section.

The `D0` line is the same trick Project 3 uses: the PPK2 samples eight
logic channels on the same clock as the current, so a GPIO toggled by the
tracker at the start and end of each report puts a marker in the current
trace. Without it, finding the report inside an hour of sleep means
guessing where it was.

## Schematic

**Partly blocked, and the blocked part is the dangerous one.**

Known from Waveshare's HAT wiki:

| Item | Value |
|---|---|
| Interface | Standard 40-pin header, UART; an onboard USB interface also works |
| PWRKEY | "connected to P7 (wiringPi number) of Raspberry Pi by jumper" |
| Idle current | "about 41mA" |
| Antennas | LTE and GNSS, the GNSS one active |

**Not known, and not to be guessed:**

1. **The logic voltage.** The wiki says "5V/3.3V (switch via 0ohm
   resistor)". A Pi GPIO is 3.3 V and is not 5 V tolerant. Which way this
   board is set has to be read off the board before anything is connected.
   This is the same hazard Project 5 stopped at on its accelerometer and
   the same one Project 15 documents for `PWRKEY`.
2. **Which header pins the jumpers actually occupy.** "P7 in wiringPi
   numbering" is BCM GPIO4 if the numbering is what it says, but a pin
   number is a property of a board revision rather than of a part, and this
   bench has already paid for that inference once.
3. **Where the PPK2 breaks into the modem's supply.** The HAT takes 5 V
   from the header. Measuring the modem alone means supplying it from the
   PPK2 instead, which means finding the point where that rail can be
   separated. If it cannot be separated without modification, the fallback
   is the MCC 118 with a shunt, which Project 15 already names.

Until those three are read off the hardware, this section stays a table of
what is known and a list of what is not.

## The modem as a state machine

Project 15 already judged this project, in one line:

```
projects/15-lte-router/README.md:192
  "A shell script driving AT commands. That is Project 16's subject and it
   gives up every one of those properties"
```

The properties are registration, bearer, signal and location as D-Bus
properties. The judgement is correct and the trade is still worth making,
for one reason: **ModemManager keeps the modem awake.** It polls, it
maintains a bearer, it queries signal quality on a timer. Every one of
those is a wake-up, and PSM is the modem being left alone for hours. A
daemon whose job is to always know the modem's state is the opposite of a
device that sleeps.

So this project drives the modem directly, and accepts what that costs:

| Lost | Gained |
|---|---|
| Registration and bearer as properties | The modem is not woken to answer questions |
| `mmcli` as a debugging tool | Every byte on the wire is in one log, in order |
| Automatic re-attach | An explicit state machine whose transitions can be tested |
| Project 15's `lte-watchdog` and `lte-exporter` | A program small enough to reason about at 3 in the morning |

The state machine is the deliverable, not the AT commands. Its shape:

```
  OFF ---PWRKEY---> BOOTING ---AT ok---> CONFIGURED
                                              |
                                        attach|
                                              v
                    +------------------ REGISTERED <--------+
                    |                         |             |
             report |                         | PSM granted |
                    v                         v             |
                 SENDING ---ack--->        ASLEEP ----------+
                    |                     (TAU timer)
                    | no ack, n times
                    v
                 BACKOFF ---> REGISTERED
```

Every transition is driven by an AT response or a timer, and both are
things a test can supply. That is the seam: the program reaches the modem
only by writing a line and reading lines back, so a fake modem is a port
with a table of canned responses. Project 15's watchdog is testable for the
same reason and it is the pattern worth copying.

A pseudo-terminal, in the end, rather than the pipe this section first
said. A FIFO is one-directional, so one process cannot open it both ways
without reading back its own traffic; and a pty slave is a character
device, so the port setup the program does on a real modem actually runs
during the test instead of being stepped around. The part most likely to be
wrong is then the part under test.

The `n times` on the arrow to `BACKOFF` is CoAP's own retransmission of a
confirmable message and not a counter of its own. There is no second retry
mechanism: see the send path below for why the cheap moment to try again is
while the radio is still up.

## PSM and eDRX are a negotiation, not a setting

The part most likely to be got wrong, so it is drawn before it is coded.

**PSM is requested, and the network decides.** `AT+CPSMS=` carries a
requested TAU period and a requested Active-Time. The network answers with
what it will actually give, which may be shorter, longer, or nothing at
all. A device that sets a value and assumes it holds is a device whose
battery life is a guess.

```
  device                              network
    |  AT+CPSMS=1,,,"TAU","Active"        |
    |------------------------------------>|
    |                                     |
    |  granted values in the ATTACH or    |
    |  TAU ACCEPT, read back with         |
    |  AT+CPSMS? and the +CEREG URC       |
    |<------------------------------------|
    |                                     |
    |  [Active-Time: modem still          |
    |   reachable, drawing idle current]  |
    |                                     |
    |  [then PSM: modem asleep until the  |
    |   TAU timer expires or the host     |
    |   wakes it. Not reachable.]         |
```

**So the acceptance criterion cannot be "PSM is enabled".** It has to be
the granted values read back from the modem, and the current trace showing
the transition actually happened. A setting that the network refused looks
identical in the configuration and completely different in the trace, which
is exactly why the instrument is in this design rather than beside it.

eDRX is the same shape and a different trade: the modem stays reachable but
listens rarely, so downlink latency rises to seconds or minutes and current
falls a long way short of PSM's. A tracker that only ever reports upward
wants PSM; one that must accept a command wants eDRX. The project measures
both rather than choosing in advance.

## Who owns what

The table that prevents the commonest bug, which is two managers on one
resource.

| Resource | Owner | Nothing else may |
|---|---|---|
| The AT serial port | `tracker` | open it; no ModemManager, no `getty`, and the port is named by udev rather than by `ttyUSB` index |
| `PWRKEY` GPIO | `tracker-gpio` | drive it; the modem's power state is one program's business |
| The modem's power rail | the PPK2, during a measurement | be connected at the same time as the HAT's own supply, which would be two supplies on one rail |
| The report marker GPIO | `tracker-gpio marker-hold`, one process per report | be requested by anything else while it is held; the PPK2 reads it as a logic channel |
| `/etc/bench/tracker.conf` | the card, written after flashing | be in the repository; it carries the APN and the CoAP server |
| The GNSS antenna port | the HAT | receive DC bias from anywhere else |

The third row is Project 3's hardest-won lesson, stated there as "the PPK2
is the only supply during every measurement" because leaving the other
cable in "joins two supplies and the PPK2 then measures" something that is
not the device.

**The fourth row says "while it is held" rather than "while it is high",
and the difference is the whole mechanism.** A process that requests a GPIO
line, drives it and exits hands the line back to the kernel, which returns
it to an input. A marker set by one short-lived call and cleared by another
would be two spikes a few milliseconds apart with nothing between them, and
the charge integrated between those edges would be the charge of nothing.
So the line is held for the lifetime of a process and the interval ends
when that process does. Project 15 met the same fact from the other
direction, where releasing its `FLIGHT` line let a pull-up put the radio
into flight mode.

The cost lands inside a published number and is recorded here rather than
discovered later: the integration interval is bounded by that process
starting and stopping, so process startup is inside the interval. The
charge per report will read slightly high. That is the safe direction for a
budget, and it is worth measuring once rather than assuming it is small.

## The send path, and why there is no socket

Settled while writing the program rather than while drawing the design,
which is the honest order to record it in.

With no ModemManager, no NetworkManager, no QMI and no PPP, **nothing gives
the kernel a network device for the modem.** There is no `wwan0`, so there
is nothing to bind a UDP socket to. The CoAP datagram is therefore built in
the tracker and handed to the modem's own IP stack over the same AT port:
`AT+CNACT` activates the context, the `AT+CAOPEN` family carries the
datagram, and the socket and the context are both closed in a `finally`,
because a socket left open is a modem kept awake and that is the failure
this project exists to avoid.

```
  tracker                      modem                     network
     |  build CoAP datagram      |                          |
     |  AT+CNACT=0,1             |                          |
     |-------------------------->|  activate PDP context    |
     |  AT+CAOPEN=0,0,"UDP",...  |------------------------->|
     |-------------------------->|                          |
     |  AT+CASEND=0,<len>        |                          |
     |<----------- ">" prompt ---|                          |
     |  <the datagram itself>    |                          |
     |-------------------------->|-------- UDP ------------>|
     |                           |<------- ACK -------------|
     |  +CADATAIND: 0            |                          |
     |<--------------------------|                          |
     |  AT+CARECV=0,128          |                          |
     |-------------------------->|                          |
```

**This makes the open kernel question smaller than it looked.** The image
needs a USB serial driver and nothing else: no PPP, no CDC Ethernet, no
`qmi_wwan`. It is also a second reason Project 15's fragment cannot be
borrowed, beyond the one already given below.

**The retry is CoAP's own, and there is no other.** A confirmable message
is retransmitted on RFC 7252's doubling schedule with the same message id
and token, so a server can recognise the duplicate and answer it once
rather than recording the same position four times. Retrying on a later
wake instead would mean attaching again, and the attach is the expensive
part of a report; the cheap moment to try again is while the radio is
already up. A report that is never acknowledged reaches `BACKOFF` rather
than being reported as sent.

## What gets built

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/tracker.cfg` | The serial driver this modem needs, behind an opt-in switch. **Not written**, and not until `lsusb` has been read |
| `meta-bench/recipes-bench/bench-tracker/` | The state machine, the GPIO tool, the udev rule, the unit and its timer |
| `meta-bench/recipes-core/images/bench-tracker-image.bb` | The image, deliberately without ModemManager |
| `kas/bench-tracker.yml` | `./go tracker`, including `bench-rpi3.yml` |
| `tests/tracker-at-test.py` with a `.sh` wrapper | Parsers, both 3GPP timer tables, CoAP construction, the configuration reader, and every transition in process. Runs on any host |
| `tests/fake-modem.py` and `tests/tracker-state-test.sh` | The same scenario tables through a real serial port, which needs a pty and so skips on the Windows laptop |
| `projects/16-nbiot-tracker/measure/budget.py` | The charge arithmetic, reading the capture schema Project 3's `ppk2_boot.py` already writes. **Written and passing**, standard library only, so its suite runs on the authoring laptop rather than only where numpy is installed |
| the PPK2 capture program | Records one report cycle. **Not written**, and blocked on the marker GPIO offset, which is one of the three facts still to be read off the board. The arithmetic has no such dependency, so it was written first |

**Two suites rather than one, and they share their scenario tables.** The
transport needs a pseudo-terminal, which the Windows authoring laptop does
not have, so a single suite would skip on the machine the work is done on
and its failures would be found by somebody else. The split runs every
transition everywhere and leaves only the real `open`, `termios` and timed
reads waiting for a machine with a pty. Sharing the tables is what stops
the two fakes becoming two opinions about what the modem says.

**Every AT string in the program is provisional.** The command table and
every canned response were read out of the SIM7070G AT command manual, not
captured from the part on the bench. That is a claim about the modem rather
than an observation of it, and Project 8 shipped a `cyclictest` parser
written from a remembered format whose every row came out blank. The tables
are marked as provisional where they are written, and the first transcript
in `docs/evidence/` replaces them. Acceptance criterion 11 stays open until
it does.

**The udev rule is deliberately partial for the same reason.** The vendor
id it matches, 1e0e, is taken from this repository's own SIM7600 rule and
is therefore a fact. The product id and the AT interface number are not
known, so rather than guessing them the rule names every SIMCom tty by its
interface number as `/dev/tracker-tty-NN`, and the precise rule sits
commented out beside it with the two values to fill in. The first boot then
answers the question instead of raising it.

**The kernel fragment is the one open technical question.** Project 15's
`router.cfg` enables `option` and `qmi_wwan`, and carries no `USB_ACM`, no
`PPP`, and no `CDC_NCM`. The repository records nothing about how a
SIM7070G or a SIM7020E enumerates. Whether this project needs `cdc_acm`,
`option`, or PPP is a question for `lsusb` on the board, and the fragment
is not written until that has been read. Guessing it is how Project 1 lost
two rounds on `wlan0` and Project 8 lost a flash to `spidev`.

**Project 15's fragment cannot simply be reused** even if the drivers
matched: it is gated as one unit and carries the whole netfilter, NAT and
conntrack stack, which a tracker has no use for. A tracker that drags in a
router's packet filter is a larger kernel measured in a project about
power.
