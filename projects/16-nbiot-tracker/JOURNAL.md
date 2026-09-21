# Journal: Project 16

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are Monday 21 September 2026 unless noted.

---

## 1. The parts were checked before the design, for once

**What happened.** Three projects in this repository were specified around
hardware that is not on the bench: Project 10 wants an X-NUCLEO-IKS4A1,
Project 17 a STWIN.box, and Project 11 wanted a VL53L8CX until it was
re-targeted to the ADXL345 on Monday 21 September 2026. Each was found out
after its design was written.

**What was done.** The inventory was read first this time. Project 16 needs
a Cat-M or NB-IoT modem and the bench has two: a SIM7070G Cat-M/NB-IoT/GPRS
HAT and a SIM7020E NB-IoT HAT. It also needs a current meter, and the bench
has a Nordic PPK2 with a recorded serial number, E617EB4AAAC1, and an MCC
118.

So this project starts from the unusual position of having all of its
hardware, and the design can make claims about measurements rather than
deferring them to a purchase.

**Why that and not the alternative.** The alternative is the order the
other three used, which produces a design document that is correct about
software and fictional about hardware, and a project that cannot reach its
own acceptance criteria. Checking first costs five minutes.

---

## 2. The repository says this project is on two different boards

**What happened.** The root README row says Raspberry Pi 3. Project 2's
design document says, in an aside, "Project 16 reuses the same small system
for the cellular tracker", meaning the NanoPi NEO Air. Both are in the
tree. Neither mentions the other.

**What was done.** The Raspberry Pi 3, and Project 2's sentence recorded as
wrong rather than as an alternative.

The deciding fact is physical rather than editorial. The SIM7070G part on
this bench is a Raspberry Pi HAT with a "Standard Raspberry Pi 40PIN GPIO
extension header". The NEO Air has a 24-pin header and a separate 4-pin
debug UART, described in Project 2's own design document. **The HAT does
not stack on that board.**

**Why that and not the alternative.** Two further reasons beyond the
header. Project 2's system is Debian assembled by hand with no Yocto, so
following that sentence would put this project outside the layer every
other project shares, which is a large decision to inherit from a
subordinate clause. And the sentence was written before either project
existed, which is the same class of forward-looking claim that Project 5
found four of and had to treat as constraints.

**What was right about it, and is kept.** A tracker wants the smallest
system that will do the job, because the processor's idle current sets the
floor under everything the modem's sleep mode can save. That concern is
answered in the design by measuring the modem's rail rather than the
system, which turns the board's own draw from a confound into a separate
question.

---

## 3. The instrument was designed in, not appended

**What happened.** The theme ends with "current budget", which is a
measurement, and this repository has already recorded three ways the PPK2
disappoints somebody who assumed it would just work.

Project 15, on measuring a cellular modem: "The PPK2 cannot measure this,
at 1 A maximum; the instrument for the current profile is Project 8's MCC
118 with a low-value shunt." Project 3, after measuring: a peak of 1233 mA,
above the rating, so "the peak cannot be quoted as a property of the board
at all". And in Project 3's evidence, found on Sunday 20 September 2026:
source-meter mode above 400 mA needs the second micro-USB connector, and
an entire session's current figures were withdrawn because only one was
ever plugged in.

**What was done.** Three decisions, written into the design before any
code.

The PPK2 goes on the modem's supply rail rather than the system's. A Pi 3
idles at several hundred milliamps and Project 3 measured a NEO Air at 187
mA mean; a modem in PSM draws microamps. Measured across the whole system,
the entire subject of this project disappears into the processor's idle
current.

2G is locked out with `AT+CNMP=38`, which is in the HAT vendor's own attach
sequence. A GPRS transmit burst is conventionally near 2 A, past the
instrument's ceiling, and a clipped trace looks like data rather than like
an error. **This is reasoning rather than measurement:** the 2 A figure is
the conventional GPRS burst and not something taken on this bench, and the
first run checks it.

Both micro-USB connectors, stated first in the bring-up notes rather than
in a troubleshooting section, because that is where Project 3 needed it.

**Why that and not the alternative.** The alternative is to measure the
system, which is easier to wire and produces a number nobody can use: a
tracker's whole argument is the ratio between its sleeping and waking
current, and a processor two orders of magnitude above the modem's sleep
floor hides exactly that ratio.

---

## 4. ModemManager is left out on purpose, and Project 15 already said why it hurts

**What happened.** Project 15 pre-judged this project in one line of its
README: an AT-driving script "gives up every one of those properties",
meaning registration, bearer, signal and location as D-Bus properties. That
judgement is correct.

**What was done.** No ModemManager, no NetworkManager, no QMI, no `wwan0`.
The design carries a table of exactly what is lost.

**Why that and not the alternative.** ModemManager's job is to always know
the modem's state, which it does by polling it. PSM is the modem being left
alone for hours at a time. The two are not in tension over configuration,
they are in tension over purpose: every query is a wake-up, and a daemon
that keeps the modem reachable is a daemon that prevents the thing this
project measures.

What is taken from Project 15 instead is its shape rather than its code.
`lte-watchdog` reaches hardware only by running commands found on `PATH`,
which is what makes its escalation ladder testable against stubs with no
modem present. The tracker's state machine reaches the modem only by
writing a line and reading lines back, so its fake is a pipe and a table of
canned responses.

---

## 5. Python, not the shell script Project 15 predicted

**What happened.** Project 15's README characterised this project before it
existed, as "a shell script driving AT commands". Entry 4 used that
characterisation to explain what the trade costs, which made it worth
checking rather than inheriting.

**What was done.** The state machine is Python, standard library only, and
the recipe depends on `python3-core` rather than `python3-modules`.

**Why that and not the alternative.** Two things the shell cannot do
without putting another binary in the image. CoAP is a binary protocol over
UDP, and building its header is sixteen lines of struct packing in Python
against a helper program in shell. And reading an AT response needs a read
that times out, which POSIX shell has no portable way to express.

The dependency is smaller than Project 15's, not larger, and this time it
is measured rather than guessed. That recipe installs `python3-modules`
whole and says plainly in a comment that this is the honest version of a
dependency nobody had measured. This program imports ten modules: argparse,
errno, os, random, re, select, struct, subprocess, sys and time. All ten
are in `python3-core`. Nothing here imports json, urllib, ssl or logging,
which is most of what the larger package carries. If that is wrong the
symptom is immediate and precise, an ImportError naming the module on the
unit's first run, which is the kind of wrong that does not survive a boot.

---

## 6. The fake modem is a pseudo-terminal, not the pipe entry 4 predicted

**What happened.** Entry 4 said the fake would be a pipe with a table of
canned responses. Building it showed the pipe does not work. A FIFO is
one-directional, and a single process cannot open one read and write
without reading back its own traffic, so a two-way dialogue needs two FIFOs
and a convention about which is which.

**What was done.** `tests/fake-modem.py` creates a pty, prints the slave
path, and serves the master side. The tracker is pointed at the slave with
`--port` and does not know it is under test.

**Why that and not the alternative.** The pty is better than the two FIFOs
it replaces rather than merely equivalent. A pty slave is a character
device, so the termios setup in the tracker actually runs during the test.
With a FIFO it would be skipped, because the tracker guards that setup on
the file being a character device, and the part most likely to be wrong
would be the part the test stepped around.

Two consequences were paid for on the spot. The first draft of the server
loop treated EIO on the master as the end of the session; EIO also means
that nobody holds the slave yet, so every scenario would have reported a
modem that answered nothing. It now tells the two apart by whether the
tracker has spoken. And a pty does not exist on the Windows authoring
laptop, so `tests/tracker-state-test.sh` skips there, which is why the
second suite in entry 7 exists.

---

## 7. Two suites, because a suite that always skips proves nothing

**What happened.** Once the transport test needed a pty, it could not run
on the laptop the work was being done on. A test that is only ever run by
someone else is a test whose failures are found by someone else.

**What was done.** The work was split along the line where the host stops
mattering. `tests/tracker-at-test.py` substitutes the port in process and
runs anywhere: parsers, both timer tables, CoAP construction, the
configuration reader, and every state transition, against the same scenario
tables the pty test serves. It is 75 assertions and it passes here.
`tests/tracker-state-test.sh` keeps the transport and skips where there is
no pty.

**Why that and not the alternative.** Sharing the scenario tables between
the two is the part that matters. Two fakes would be two opinions about
what the modem says, and they would drift apart.

**What it found, in its first hour.** Four things, and three were in the
program rather than in the test.

The configuration default `psm_tau` was `00111000`, with a comment beside
it saying eight hours. It is twenty-four: the count is the low five bits
and `11000` is twenty-four, not eight. `decode_tau` printed 86400 the first
time it ran. That is the argument for decoding these octets in the program
instead of trusting the value where it is written.

`await_ack` handed the whole `+CARECV:` line to the CoAP parser, prefix
included, so it read the letters of the prefix as a version, a type and a
code. It would have returned a confident answer about a header that was
never in the packet. Designing the fake is what surfaced it; no test
existed yet that could have.

`report` counted send attempts and returned to `REGISTERED` to try again
later. This program sends one report and exits, so later was a counter that
reset every run and a retry that never happened. Worse, the retry belongs
inside the wake: the expensive part of a report is the attach, and the
cheap moment to try again is while the radio is still up. CoAP's
confirmable retransmission is now the retry, and a report that is never
acknowledged reaches `BACKOFF`.

Beside that, `main` called `sleep_until_next` unconditionally, so a report
that had just reached `BACKOFF` was immediately moved to `ASLEEP` and the
program exited reporting the one state that means everything went well. A
failure that overwrites itself with a success is worse than a crash.

The fourth was in the test: two expected values had been worked out by hand
and worked out wrongly. `01100001` was read as 320 hours when it is two
seconds, and an option header was sliced at three bytes when it is two.
Both are kept in the file with the mistake named, because an octet that
differs by one bit and a factor of 576,000 is worth showing twice.

The two load-bearing assertions were then proven by breaking what they
check. Making `note_granted` echo the requested values instead of the
granted ones fails four assertions; making an unacknowledged report return
to `REGISTERED` fails one. The file was restored from a checksummed copy
afterwards and the checksum verified, because a break-and-restore on a
shared checkout is how Project 5 nearly committed a driver that referred to
an undefined register.

---

## 8. The instrument marker has to be held, not set

**What happened.** The marker GPIO was first designed as two calls,
`tracker-gpio marker 1` before a report and `marker 0` after it.

**What was done.** It is one call that blocks. `tracker-gpio marker-hold`
drives the line and waits for a signal, and the tracker ends the interval
by ending the process.

**Why that and not the alternative.** A process that requests a line,
drives it and exits gives the line back to the kernel, which makes it an
input again. The two-call version would have produced two spikes a few
milliseconds long and no interval between them, and the charge integrated
between those edges would have been the charge of nothing at all. The
figure would still have been a number, printed to three decimal places.

Project 15 met the same fact from the other side: releasing its FLIGHT line
let the HAT's pull-up put the radio into flight mode, so that line is held
too. The shape is general and worth stating once. A GPIO held by a
short-lived process is not held.

**What it costs, said here because it lands inside a published number.**
The interval the PPK2 integrates is bounded by this process starting and
stopping, so process startup is inside the interval rather than outside it.
The measured charge per report is therefore slightly high. That is the safe
direction for a budget, and the size of it should be measured once rather
than assumed negligible.

---

## 9. There is no network interface, and that shrinks the kernel question

**What happened.** Writing the send path made visible an assumption that
had not been stated. With no ModemManager, no NetworkManager, no QMI and no
PPP, nothing gives the kernel a network device for the modem. There is no
`wwan0` to bind a UDP socket to.

**What was done.** The CoAP datagram is built in the tracker and handed to
the modem's own IP stack over the same AT port, with `AT+CNACT` to activate
the context and the `AT+CAOPEN` family to carry the datagram.

**Why that and not the alternative.** It is the only option that does not
bring back the daemon this project exists without. It also makes the open
kernel question smaller than it looked: this image needs a USB serial
driver and nothing else. No PPP, no CDC Ethernet, no `qmi_wwan`. That is
worth knowing before writing a fragment, and it is a second reason Project
15's `router.cfg` cannot simply be borrowed, beyond the one already
recorded: that fragment is gated as a single unit which also builds in the
whole netfilter and conntrack stack.

**What is still not known, and is not being guessed.** The modem's USB
product id, and which of its tty interfaces carries AT. So
`78-sim7070.rules` is deliberately partial: it names every SIMCom tty by
interface number, as `/dev/tracker-tty-NN`, and leaves the precise rule
commented out with the two values to fill in. The vendor id it matches on,
1e0e, is not a guess either. It is taken from this repository's own SIM7600
rule, written against a part that has enumerated on a board.

That makes the first build a reconnaissance build. It is expected to boot
with the HAT attached and no AT port, and `lsusb` is in the image so that
boot answers the question rather than raising it. Project 1 lost two rounds
to a `wlan0` that was assumed and Project 8 lost a flash to a `spidev` that
was. One boot is cheaper than either.

---

## 10. The completeness check found a program nothing compiled

**What happened.** With everything written and three suites passing, the
question was whether the project was complete. Auditing it against the
repository's own checks rather than against the list of files produced
found that **`tracker-gpio.c` was compiled by nothing**: not by
`scripts/host-check.sh`, not by CI, not by anything. It had been written,
read, and never once put in front of a compiler.

**How it hid.** `host-check.sh` discovers shell scripts by shebang and
Python programs by shebang or extension, so both of those are picked up
automatically and a new one needs no wiring. C programs are not: each has
its own hand-written `step` with its own `gcc` line, because each needs
different libraries. `tests/*.sh` is a glob too, which is why the three new
suites were running from the moment they existed. The automatic discovery
in four places out of five is exactly what made the fifth easy to miss.

**What was done.** A compile step in `scripts/host-check.sh` and two in
`.github/workflows/ci.yml`: one that compiles with `-Werror` against
libgpiod v2 like its four siblings, and one that runs the binary twice.
`info` must succeed, because it touches no line. `pwrkey` must fail with
exit 2, because a runner has no `/etc/bench/tracker.conf` and therefore no
offset, and there is no default offset on purpose.

**Why the second step and not just the compile.** A guard that has never
refused is indistinguishable from a guard that is not there, and this one
is the guard that stops a program driving whatever else is on a pin whose
number it does not know. Asserting the exit status rather than just the
failure matters too: any bug that made the program exit non-zero would
otherwise look like the refusal working.

**A trap found while writing it.** The first version tested the status in
an `if` and read `$?` in the `elif`. That works, and it is wrong here
twice: GitHub Actions runs `run:` under `bash -e`, where the expected
non-zero ends the step before anything can check it, and reading `$?` after
a failed condition is a trick nobody should have to verify while reading a
CI log. It captures the status explicitly now.

**Three stale claims fixed in the same pass.** The root README said
`./go check` compiles "both C programs" and byte-compiles "both Python
programs"; it now compiles six and every Python program in the tree. A
table lower down said four C programs, three against libgpiod, which had
already gone stale when `drmfill` was added and went staler here. These are
the shape of error this repository keeps meeting: a sentence that was true
when it was written and was left standing after the thing it described
changed. Nothing tests a sentence, so the only moment to catch it is when
changing the thing.

**What the audit confirmed rather than found.** `kas_project` and
`kas_machine` in `scripts/archive.sh` derive a project number and a machine
from the kas file itself instead of from a table, so `kas/bench-tracker.yml`
resolves to project 16 on `raspberrypi3-64` with nothing to register.
`resolve_kas_config` accepts both spellings. `./go projects` lists the new
project from its README's first line. Four things that could each have
needed a table entry, and none did.

---

## 11. A signal race that would have been silent, found by reading instead of compiling

**What happened.** Asked whether the project was ready to commit, the
honest answer depended on a program that no machine here can compile: this
laptop has no gcc, no cc, no clang and no libgpiod headers. Waiting for CI
to find out is a round trip, so `tracker-gpio.c` was reviewed by hand
against the one thing available as a control: `lte-gpio.c`, which CI
already compiles, so its API usage is known good.

**What that comparison proved.** Every libgpiod function this file calls is
one that file already calls, and every call shape matches, argument for
argument: the direction, the active-low flag, the output value, the four
argument `gpiod_line_config_add_line_settings`, the request and the value
set. The one symbol not in the control is `enum gpiod_line_value`, which is
the type of constants the control already passes. That is not a compile,
and it is the strongest evidence obtainable without one.

**What the reading found anyway.** The wait loop was

```
	while (!stop_requested)
		pause();
```

which has a race old enough to have a name. A signal delivered between the
test and the `pause` sets the flag, finds no `pause` to interrupt, and the
process then sleeps until a signal that never arrives.

**Why it matters here and not in the program it was copied from.** Project
15's `lte-gpio` holds its FLIGHT line with the identical loop, and gets
away with it: if it hangs, a systemd unit takes its stop timeout to die and
somebody sees a slow shutdown.

Here the same hang lands inside a published number. The tracker ends a
report by terminating this process and waits five seconds before resorting
to `SIGKILL`. If the signal falls in the window, the marker line stays high
for those five extra seconds, the PPK2 integrates five seconds of
post-report idle into the charge budget, and nothing anywhere reports a
problem. The run looks clean and the figure is wrong.

**What was done.** `SIGTERM` and `SIGINT` are blocked before the line is
driven, and the wait is `sigsuspend` with the original mask rather than
`pause`. Installing the mask, waiting and restoring are one uninterruptible
step, so a signal arriving before the wait is held pending and delivered
the moment the wait begins. The window closes.

**Not fixed in Project 15, deliberately.** That project is built and
running on a board. The same one-line change there is a change to a working
system that nobody asked for, and its consequence is a slow shutdown rather
than a corrupted measurement. It is recorded here so the next person to
open that file knows, rather than edited from this one.

**The general shape, and it is the third time this repository has met it.**
Copying a pattern carries its defects along with its correctness, and the
cost of a defect is a property of where it lands rather than of the code.
The same loop is a nuisance in a daemon and a falsified measurement in an
instrument.
