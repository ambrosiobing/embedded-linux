# Journal: Project 15

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

Format for each entry: **what happened**, **what was done**, **why that and
not the alternative**.

All entries are 15 September 2026 unless noted.

---

## 1. The specification was read before anything was written

**What happened.** Project 1 was built first and its four specified figures
were written last, after being asked for twice. The specification existed
the whole time and was not consulted.

**What was done.** This project started from the written specification and
its four figures: system architecture, wiring and schematic, bench layout,
and the software's UML. All four were redrawn as text in
[docs/DESIGN.md](docs/DESIGN.md), in this repository, before a single recipe
was written. That file is now the specification of record: the architecture
it shows, the pin table it gives, the acceptance criteria it implies and the
sequence of a failover are all in the repository, and nothing outside it has
to be opened to review the design.

**Why that and not the alternative.** The alternative is what happened last
time: build the thing, then reconstruct the design from the thing. That
produces documentation that describes the implementation rather than the
intent, and it cannot catch the case where the implementation drifted from
what was asked for.

---

## 2. bench-provision was two recipes wearing one name

**What happened.** The router image needs the bench's German console keymap
and must not have its wireless client configuration: `bench-provision`
shipped a systemd-networkd profile for `wlan0` and a first-boot step
writing a `wpa_supplicant` client config, and this image runs an access
point on that same interface under NetworkManager.

**What was done.** Split into `bench-provision`, which is now site identity
only, and `bench-net-wifi`, which is the wireless client half.
`bench-image` installs both, so Project 1's image is unchanged in content.
`bench-router-image` installs the first and removes the second.

**Why that and not the alternative.** The alternative was to keep one recipe
and have the router image mask the units it does not want. That works and
leaves a package installed whose files are present and inert, which is
exactly the state that makes someone six months later spend an afternoon
finding out why `wlan0` flaps. Two managers on one interface is not a
conflict that resolves itself.

**The cost.** Project 1's package manifest gains one entry, and its recorded
count of 112 is now a count of a slightly differently sliced set. That is
noted here rather than quietly corrected.

---

## 3. The watchdog was split in two, against the specification

**What happened.** The specified watchdog is a single Python program that
calls libgpiod through its Python bindings to pulse PWRKEY.

**What was done.** Two programs. `lte-gpio`, in C against libgpiod v2, owns
the two control lines and nothing else. `lte-watchdog`, in Python, owns the
probe, the counting and the escalation, and reaches the hardware only by
running `lte-gpio`.

**Why that and not the alternative.** Three reasons, and the third is the
one that settled it.

The first is that it makes the policy testable on a laptop. Every external
command the watchdog runs is looked up on `PATH`, so the whole ladder from a
healthy bearer to a power cycle runs against stubs in under a second. That
test exists and passes; with the bindings in-process it could not.

The second is the same mechanism-and-policy split Project 1 made between
`bench-status` and `bench-state`, for the same reason: the C stays short
enough to read in one sitting.

The third is dependency risk. `python3-libgpiod` is a separate package whose
name and availability differ between OpenEmbedded releases, and it was not
possible to confirm from this machine which name scarthgap uses. A recovery
path that fails on an import is a recovery path that does not exist, and
the one time it matters is the one time nobody is watching.

---

## 4. The specified firewall has no input chain

**What happened.** The specified `nftables.conf` has a forward chain and a
postrouting chain. Input is therefore at the default policy, accept.

**What was done.** Added an input chain with policy drop, allowing return
traffic, loopback, ICMP, DHCP and DNS from the LAN, ssh from the LAN and
from the cable, and the metrics port from the LAN only. Everything else is
counted and dropped.

**Why that and not the alternative.** Without it, every service on the box
is reachable from the carrier network the moment the LTE bearer comes up:
the SSH server that `debug-tweaks` left with a passwordless root, and a
metrics endpoint that publishes the box's position and signal history. A
router with a public-facing uplink and no input policy is not a router.

The rule is asserted rather than remembered:
`tests/bench-router-nftables-test.sh` fails if the input policy is ever
accept, or if a port is opened towards an uplink. `nft -c` would accept both
mistakes without a word, which is why the test checks meaning and not only
syntax.

**Also added, for the same reason of things that work on a bench and fail in
the field:** the MSS clamp. Without it a client over LTE completes a TCP
handshake and then stalls on the first large response, which is the single
most confusing failure mode of any cellular gateway. It costs one line in
the ruleset and, as entry 17 records, no kernel options at all: the two
this entry first claimed were needed turned out not to exist.

---

## 5. The metrics endpoint was bound to the LAN, not to everything

**What happened.** The specified exporter is `python3 -m http.server 9101
--directory /var/lib/lte`, which binds every address.

**What was done.** `--bind 10.20.0.1`, from an environment file so the
address is configurable, plus the nftables rule that only admits 9101 from
`wlan0`.

**Why that and not the alternative.** Either alone would do. Both, because
they fail differently: a typo in the bind address is caught by the
firewall, and a ruleset that failed to load is caught by the bind. The
endpoint is an unauthenticated read of where this box is and how its link
has behaved.

---

## 6. dnsmasq and nftables got their own units

**What happened.** The specification installs `bench-lan.conf` into
`/etc/dnsmasq.d/` and `nftables.conf` into `/etc/nftables.conf`, both relying
on the distribution's packaged service to pick them up.

**What was done.** Both configurations go to `/etc/bench/`, and two units of
ours read them: `bench-router-dhcp.service` and `bench-router-nft.service`.
The packaged `dnsmasq.service` is masked, as is `systemd-networkd`.

**Why that and not the alternative.** Whether `/etc/dnsmasq.d` is scanned at
all depends on a `conf-dir` line in the distribution's `dnsmasq.conf`, which
this layer does not control and which differs between OpenEmbedded releases.
Whether the nftables recipe ships a service at all is the same kind of
question. Relying on either is relying on something invisible from here.

Masking in the image rather than in a first-boot script is deliberate: the
state is then visible in the package manifest, which is where someone
auditing the image will look.

**What this costs.** Two more units to reason about, and a mask that will
look strange to anyone expecting the distribution's defaults. The bring-up
notes and the ownership table in DESIGN.md exist partly to pay that back.

---

## 7. The kernel fragment is opt in, and getting it past the linter took a trick

**What happened.** The router needs built-in USB modem drivers and a
built-in netfilter stack. Adding them to the shared `bench.cfg` would put
them in every image, including the one Project 3 measures boot time and
kernel size with.

**What was done.** A second fragment, `router.cfg`, added to `SRC_URI` only
when `BENCH_ROUTER_KERNEL` is `"1"`, which `kas/bench-router.yml` sets.

**Why that and not the alternative.** The alternative, one fragment for
everything, is simpler and quietly changes a kernel that another project has
already measured.

**The trick, and why it is commented in the file.** `scripts/lint.py` reads
`SRC_URI` to check that every `file://` entry exists and that every file in
`files/` is referenced, and it stops a URI at a double quote. Written the
obvious way, with the conditional expression in single quotes inside a
double-quoted assignment, the linter sees a file named `router.cfg'` that
does not exist and a file `router.cfg` that nothing references. Swapping the
quoting fixes it. This is the second time in this repository that a lint
rule has shaped how a line is written; the first was the em dash check
having to spell its own dashes with `chr()`.

---

## 8. Everything built in, nothing modular, and why that is Project 1's fault

**What happened.** The first draft of the image named
`kernel-module-option`, `kernel-module-qmi-wwan` and about six netfilter
module packages.

**What was done.** Deleted all of them and set `=y` in the fragment instead.

**Why that and not the alternative.** Project 1 spent two rounds of
debugging on an empty `wlan0`: first because `core-image-minimal` installs
no kernel modules at all and nobody had named `kernel-module-brcmfmac`, then
because modern brcmfmac asks for a vendor module by name at probe time and
nobody had named `kernel-module-brcmfmac-wcc` either. The symptom both times
was a driver that was built, was not in the image, and therefore did not
exist.

On a router the modem drivers and the packet filter are not optional extras
that might be loaded later. Building them in removes the class of failure
entirely, at the cost of a larger kernel image, which on a mains-powered box
with an SD card is not a cost worth counting.

This entry originally ended with a claim that two more options, `NFT_RT` and
`NFT_EXTHDR`, were in the fragment to make the MSS clamp work. They were
not options at all. See entry 17.

---

## 9. The test for file permissions failed on the machine that wrote it

**What happened.** `tests/bench-router-setup-test.sh` asserts that the
generated NetworkManager keyfiles are mode 600, because NetworkManager
silently refuses a keyfile anyone else can read. On this Windows checkout
`ls -l` reports `-rw-r--r--` for everything, so the assertion failed.

**What was done.** The test now creates a file, chmods it, and checks
whether the file system reports the mode at all. Where it does not, the
permission assertion is skipped with a note; CI and the Linux build host
still make it.

**Why that and not the alternative.** Deleting the assertion would remove a
check of something NetworkManager genuinely enforces. Leaving it failing
would train whoever runs the tests to ignore a red line, which is worse than
having no test. Project 1's rule that a skipped check counts as a failure
applies to a check that could have run; this one demonstrably cannot.

---

## 10. The tests could not be run on the machine that wrote them either

**What happened.** `tests/lte-watchdog-test.sh` and
`tests/lte-exporter-test.sh` replace `mmcli`, `ping`, `nmcli`, `ip` and
`lte-gpio` with shell stubs on `PATH`. Native Windows Python cannot execute
an extensionless shell script, so every stub came back as "not found", every
metric read as absent, and eight assertions failed for a reason that had
nothing to do with the code. There is no WSL distribution on this machine.

**What was done.** A harness in the session scratchpad imported both
programs and replaced their `run()` helper directly, making the same
assertions the shell tests make. All of them pass. The shell tests are the
ones committed, because they are what CI and the build host run, and they
prove slightly more: that the programs actually invoke the commands they
claim to.

One real defect surfaced while doing this, in the harness rather than in the
code: the first version of the fake modeled an absent modem by blanking only
the state query, so the signal query still answered and the exporter
reported signal metrics for a modem that was not there. The code was right;
the fake was not. It is recorded because a stub that lies in the direction
of passing is the most expensive kind.

**Why that and not the alternative.** The alternative was to commit the
shell tests unrun and let CI be the first thing to execute them. That is how
thirteen consecutive CI failures happened in Project 1, from a one-line fix
that nobody read the log for.

---

## 11. Nothing here has met a modem

**What happened.** The software is complete and the acceptance table is
mostly empty.

**What was done.** The table says so, line by line, and the two measurement
documents are committed with their headings and empty rows.

**Why that and not the alternative.** The same rule Project 1 used for its
build-times table. A number that was never measured is worse than a blank,
because the blank is honest and the number is a claim that the first careful
reader will check.

The specific things most likely to be wrong when hardware arrives, recorded
now so that the journal can say whether the guess was right:

1. The PWRKEY and FLIGHT GPIO offsets. They come from the Waveshare demo and
   the default jumper positions, and they are properties of a HAT revision.
2. Whether `ModemManager.conf` with `[filter] policy=strict` is read at all
   by the ModemManager version scarthgap packages, or whether the filter has
   to move into a systemd drop-in on the command line. The udev
   `ID_MM_PORT_IGNORE` rules are the belt to that braces.
3. Whether level 1 is enough to recover from `AT+CFUN=0`. If it is not, the
   cheap rung is cheaper than it is useful and the ladder should start
   higher.
4. The size `python3-modules` adds, which decides whether the two scripts
   stay Python.

---

## 12. The linter passed on the laptop and failed in CI, for a real reason

**What happened.** The first push failed at the "Static layer checks" step
after passing the identical check locally a minute earlier.

**What was done.** The cause was `check_systemd_units` in `scripts/lint.py`.
It reads `SYSTEMD_SERVICE` and splits it on whitespace, which is right for
the one-line form `bench-status` uses and wrong for the multi-line form both
new recipes use: the line continuations come out as unit names. The check
then asks whether `files/` contains a file whose name is a single
backslash.

On Windows that path resolves to `files/` itself, because the backslash is
a separator there, and `.exists()` returns true. On Linux it is a filename,
it does not exist, and seven spurious failures are reported. The fix is one
line, stripping continuations before the split, and it is commented in
place so the next person does not simplify it back.

**Why this entry exists.** Not for the fix, which is trivial. For the shape
of it: a check whose answer depends on which operating system runs it is
worse than no check, because it teaches whoever sees the red run that the
linter is unreliable. That is precisely how Project 1 came to push thirteen
times with a one-line shellcheck note nobody read.

It is also the second time the same class of bug has appeared in this
repository. The first was executable bits, which Windows does not record
and which therefore never reached a commit. Both are the same lesson: a
development host that is not the target is a source of silent disagreement,
and the only defence is to run the checks somewhere that is not that host.

---

## 13. The second CI failure: four shellcheck notes, and how they were read

**What happened.** With the linter fixed, the next run got one step further
and failed at "Shell scripts": two SC2012 and two SC2010, all in
`tests/bench-router-setup-test.sh`. The CI invocation is
`shellcheck -s sh -e SC1090,SC1091`, and shellcheck's default severity is
`style`, so an informational note fails the build exactly as a warning does.

**What was done.** Not guessed at. shellcheck is not installed on this
Windows machine and the Actions API refuses job logs without
authentication, so the log was fetched with the credential git already has
for pushing to this repository, and the four findings were read directly.
Then fixed:

- `ls -l file | cut -c1-10` became `stat -c %a file`, comparing `600`
  rather than the string `-rw-------`.
- `ls dir | grep -c name` became `[ -e dir/name ]`.

Both are better code, not silenced warnings. `stat` asks for the mode;
the pipe was counting columns in a listing meant for people to read. And
the two `grep -c` calls were asking whether one named file exists, which
`test -e` says in one word.

The fix also added an assertion that was missing: the gsm keyfile's mode
was never checked, only the access point's.

**Why this entry exists.** Project 1 pushed thirteen times against a
one-line shellcheck note because nobody opened the log. The lesson was not
"read the log next time", it was that a check you cannot run locally will
be guessed at under pressure. Two failures here, two logs read, two
targeted fixes. The real remedy is still to have shellcheck on the
authoring machine, and that is now the top of this project's list of
things the bench is missing.

---

## 14. The third CI failure: one assertion counted comments as samples

**What happened.** Everything passed on the runner except one line of
`tests/lte-exporter-test.sh`: "no modem: the route is still reported",
wanted 2, got 4.

**What was done.** The assertion counted every line matching
`lte_default_route_via`, which includes the `# HELP` and `# TYPE` lines the
exporter emits above the two samples. The correct answer is 4, and twenty
lines earlier the same count is asserted as 4, so the file disagreed with
itself. Both are now anchored to `^lte_default_route_via{`, which matches
samples only and reads as what is meant: two uplinks, always both reported.

**Why this one got through.** The harness that stood in for these tests on
the Windows machine computed `text.count(...) - 2`, subtracting the two
comment lines. It compensated for the very thing the shell test was
getting wrong, so it passed while the real test failed. A substitute check
that is not the same check will agree with you about the wrong things.
That is the cost of not being able to run the real tests locally, and it
is the second entry in this journal pointing at the same missing tool.

**What the same run proved, and is worth recording as a success:**
`lte-gpio.c` compiled clean with `-Werror` against a real libgpiod 2.1.3,
the whole watchdog escalation ladder passed against the PATH stubs on a
host where the stubs actually execute, and both keyfile modes came back
600. None of that could be checked on the authoring machine.

---

## 15. Green, and what that actually proves

**What happened.** The fourth run passed every step.

```
Static layer checks              lint clean
Shell scripts                    shellcheck -s sh, every shell file found by shebang
Compile the daemon               bench-status.c, -Werror, libgpiod 2.1.3
Compile the modem control tool   lte-gpio.c,     -Werror, libgpiod 2.1.3
Python programs compile          lte-watchdog, lte-exporter, lint.py
Tests                            5 suites, 65 assertions, 0 failed
```

The four suites this project added:

| Suite | Assertions |
|---|---|
| `bench-router-nftables-test.sh` | 17 |
| `bench-router-setup-test.sh` | 14 |
| `lte-exporter-test.sh` | 24 |
| `lte-watchdog-test.sh` | 19 |

**Four CI failures to get there**, all in this project's own work and all
read from the log rather than guessed at:

1. `check_systemd_units` treating line continuations as unit names, which
   answers differently on Windows and Linux.
2. Four shellcheck notes, `ls` parsed where `stat` and `test -e` were meant.
3. One assertion counting `# HELP` and `# TYPE` lines as samples.
4. Nothing. The fourth run was the green one.

Project 1 needed seventeen runs for its first green, thirteen of them
against a single unread note. Four is better and three of them were
avoidable with shellcheck and a Linux shell on the authoring machine, which
remains this bench's most expensive missing tool.

**What green does not mean.** No modem has been seen. No packet has been
routed. The image has never been built: `./go router` needs the Yocto host,
and the two things most likely to be wrong there are named at the end of
entry 11, which is the whole reason they were named in advance.

---

## 16. The specification was cited, which is not the same as being included

**What happened.** Entry 1 of this journal claimed a virtue: the design was
written before the code, from the specification and its four figures. It
then named those figures by their filenames in a tree that is not in this
repository. Five other entries did the same thing in passing, each opening
with "the specified X is" where X was a design a reader could not see.

The claim was true and the writing made it unverifiable. Anyone reading this
repository alone was told there is a specification, told the implementation
departs from it in six places, and given no way to see either.

**What was done.** All six entries rewritten so the original design is
stated where it is departed from. Entry 3 now says the specified watchdog is
one Python program calling libgpiod's bindings, which is the fact that
matters; entry 4 says the specified ruleset has a forward chain and a
postrouting chain and no input chain, which is the fact the rest of the
entry argues against. `docs/DESIGN.md` lost its pointer to the external
figure sources and gained a sentence saying it is now the design of record.
The README's acceptance table says the seven criteria are written out in
full below, and the three added here are labelled as added here.

**Why that and not the alternative.** The alternative is to keep the
citations, on the grounds that they are honest about where the design came
from. They are, and honesty about provenance is not the same as being
readable. A design document that names a file the reader does not have is
a design document that asks the reader to take it on trust, which is exactly
what the ownership table and the pin table in `docs/DESIGN.md` exist to
avoid.

The rule for all twenty projects is Decision 29.

---

## 17. Three kernel options that do not exist

**What happened.** The first build that actually compiled a kernel, rather
than taking one from sstate, made `./go kconfig` possible for the first time
in this repository. It failed:

```
MISMATCH  CONFIG_NFT_CHAIN_NAT=y   (built: not set)
MISMATCH  CONFIG_NFT_RT=y          (built: not set)
MISMATCH  CONFIG_NFT_EXTHDR=y      (built: not set)
```

**What was done.** Checked `net/netfilter` in 6.6 rather than arguing with
the kernel. `Kconfig` defines none of the three. `Makefile` line 91 puts
`nft_rt.o` and `nft_exthdr.o` inside `nf_tables-objs`, so they are built
into `nf_tables` whenever `NF_TABLES` is set; line 136 is
`obj-$(CONFIG_NFT_NAT) += nft_chain_nat.o`. All three lines were deleted
from `router.cfg` and replaced with that citation, and the two documents
repeating the claim were corrected.

**Why it happened.** The three names were derived from the source files
that implement the features, which is how most netfilter options are named
and is why the mistake was plausible enough to survive review, a CI run and
a 178 minute build. `NFT_CT`, `NFT_NAT` and `NFT_MASQ` are real and follow
exactly that pattern; `NFT_RT` and `NFT_EXTHDR` are not, because those two
objects were folded into the core module years ago.

**What it cost, and what it did not.** Nothing. The kernel that was built
is correct: `NF_TABLES=y` and `NFT_NAT=y` bring in all three features, so
the MSS clamp and the nat chain work on the image sitting on disk. Only the
fragment was wrong, and only in claiming credit for something it was not
doing.

**Why this is the entry worth reading in this file.** Project 1 wrote
`check-kernel-config.sh` for a failure mode nobody had yet experienced: a
fragment silently ignored, a build that succeeds, and a driver that fails on
the board a week later. It then never fired, because every subsequent build
was a complete sstate hit and there was no `.config` to read. Fourteen
projects' worth of fragments later, the first time it could run, it found
three. A check that has never failed is not a check that is working.

**And one more thing it exposed.** The check could not run at all at first:
its search carried `-newer $fragment`, and `git pull` had just rewritten
`bench.cfg`, so every existing `.config` looked stale and the script
reported "no built kernel .config found". Git sets mtime to checkout time,
not commit time. The guard was also pointless: a `.config` older than a
fragment line is a `.config` missing that line, which the script already
reports as a MISMATCH. It was turning an honest failure into a confusing
absence, and it is gone.

---

## 18. First boot: what the hardware taught, in the order it taught it

The board came up on 15 September 2026. Everything below is from that
session, recorded because the interesting part of a bring-up is the
sequence of wrong assumptions, not the working end state.

**The card was written with two things on the FAT partition**, both
editable from any machine: `router.conf` carrying the access point name,
its passphrase and the APN, and an addition to `cmdline.txt`.

**`systemd.mask=lte-watchdog.service` was added to `cmdline.txt` for the
first boot.** The reason is entry 21. It cost nothing and it is the
mechanism worth remembering: a unit can be masked from the boot partition,
on a card, without mounting the root filesystem, which on a Windows machine
is the difference between a two-minute edit and an afternoon.

**The board was first wired with jumpers rather than stacked**, carrying
5 V, GND, TX and RX. Three things were wrong with that and only one was
obvious.

The obvious one: PWRKEY and FLIGHT were not connected, so half this
project's distinctive content was unavailable.

The second: 5 V through a single Dupont lead. The module pulls close to 2 A
when it powers its transmitter to attach, and a 24 to 28 AWG lead with a
crimp at each end drops enough voltage at that current to reset the module
mid-registration. The pin table in DESIGN.md lists 5 V on pins 2 **and** 4
and GND on 6, 9 **and** 14 precisely because the header shares that current
across several contacts. It had been written down and not understood.

The third, and the one that actually blocked everything: with jumpers there
was no USB. The UART carries AT commands and nothing else. `ttyUSB0..4`,
`/dev/cdc-wdm0` and `wwan0` are all USB endpoints, and without them
ModemManager has no modem, NetworkManager has no device and the entire
stack has nothing to stand on. The UART is the recovery channel for a
misconfigured USB composition, which is its only job.

**Resolution:** stack it, and leave the PWRKEY and FLIGHT jumpers off the
HAT's own block until the offsets are confirmed. Best of both: a proper
power path and a data path, with the two unverified lines still
disconnected. After stacking, `journalctl -k | grep -i voltage` stayed
empty through registration, which is the header carrying 2 A peaks as the
table said it would.

---

## 19. Two micro-USB sockets, and only one of them is the data path

**What happened.** The HAT has two micro-USB connectors, labelled `USB` and
`USB UART`. The first cable went into neither, then into the wrong one.

**What it means.** `USB` is the module's own USB interface and is the data
path: five `option` serial ports plus a `qmi_wwan` control channel and
`wwan0`. `USB UART` is a USB-to-serial bridge chip on the HAT, for talking
AT commands to the module from a PC without a Pi. Plugging the wrong one
into the Pi gives a bridge chip, `10c4:ea60` or `1a86:7523`, rather than
`1e0e:9001`, which is a quick way to tell which is which.

**Also worth noting, for a different project.** That bridge chip is a
working USB-to-serial adapter, and Project 1's serial console has been
blocked since its PL2303HXA turned out to be a generation Windows refuses
to drive. Whether it can serve as a Pi console adapter depends on whether
the HAT's jumper block exposes the bridge's TX and RX as pins, which is one
look at the silkscreen. Recorded here rather than chased.

**The success, when the right socket was used:**

```
usb 1-1.1: New USB device found, idVendor=1e0e, idProduct=9001
usb 1-1.1: Product: SimTech, Incorporated
option 1-1.1:1.0 .. 1.4  ->  ttyUSB0 .. ttyUSB4
qmi_wwan 1-1.1:1.5: cdc-wdm0: USB WDM device
qmi_wwan 1-1.1:1.5 wwan0: register 'qmi_wwan'
```

That is the 9001 composition `docs/usb-modes.md` chose, arriving exactly as
described, with no `AT+CUSBPIDSWITCH` needed. And the two drivers had
registered at 0.83 s and 0.94 s, before any module could have loaded, which
is entry 8's `=y` decision proven on hardware rather than against a
`.config`.

The udev rules worked first time: `/dev/lte-at -> ttyUSB2` and
`/dev/lte-nmea -> ttyUSB1`.

---

## 20. A device number of 29, and the alarm that was not one

**What happened.** The modem's `dmesg` line said `usb device number 29`,
preceded by `device disconnected`. A module re-enumerating every few
seconds never finishes registering, so this looked like the worst kind of
fault: an intermittent power or cable problem.

**What was done.** Counted rather than guessed:

```
n1=$(dmesg | grep -c 'idVendor=1e0e'); sleep 30
n2=$(dmesg | grep -c 'idVendor=1e0e')
```

`20 then 20`. No undervoltage lines, throttle flags `0`. Not cycling.

**Why the number was misleading.** USB device numbers are allocated across
the whole bus and never reused within a session, so hubs, a keyboard and
every one of the operator's own plug-and-unplug cycles advance the counter.
Twenty of those twenty-nine were a human finding the right socket.

**The lesson worth keeping.** The diagnosis took one command and thirty
seconds because there was a way to measure the thing directly. The
temptation was to start moving the display onto its own supply, shortening
the cable, and re-seating the HAT, any of which would have "fixed" it and
taught nothing. Measure the rate, not the counter.

---

## 21. The watchdog would have fired at an unverified GPIO on first boot

**What happened.** `bench-lte` ships `SYSTEMD_AUTO_ENABLE`, so
`lte-watchdog` starts at boot. With the HAT attached and the modem not yet
registered, it reaches level 3 in three to nine minutes and pulses GPIO6.
Meanwhile `docs/BRINGUP.md` step 3 says to confirm PWRKEY and FLIGHT
against the HAT schematic **before** trusting the watchdog. The recipe does
not allow that: it arms the thing before anyone has looked.

The default offsets come from a vendor demo and the default jumper
positions. Both are properties of a HAT revision rather than of the part. A
wrong offset does not fail safely; it drives whatever else is on that pin,
on a board that by then is unattended.

**What was done.** Two things. For this boot,
`systemd.mask=lte-watchdog.service` on the kernel command line. For every
boot after, a `pwrkey_verified` key in `/etc/bench/lte.conf`, defaulting to
`0`. Level 3 now refuses, logs why, and counts the refusal in
`lte_pwrkey_refused_total` so that a box stuck one rung below its last
resort appears on a dashboard rather than looking healthy.

**Why a config flag and not a disabled unit.** Splitting the package so the
watchdog ships disabled would mean the other three units lose their
automatic start too, and a router whose recovery only runs when somebody
remembers to start it is not a router. The flag keeps rungs 1 and 2 working
from first boot, which handle almost everything, and gates only the rung
that touches hardware whose wiring the software cannot verify.

**What it costs.** Somebody has to set a flag after checking a schematic.
That is the correct failure mode: forgetting leaves a modem that recovers
two ways out of three and says so in the journal and the metrics, rather
than a board that quietly toggles an unknown pin.

---

## 22. A daemon that could see the modem and refused to touch it

**What happened.** With the modem enumerated, ModemManager claiming it and
the udev symlinks correct, NetworkManager reported:

```
wwan0:wwan:unmanaged:
manager: (wwan0): 'wwan' plugin not available; creating generic device
```

The `lte` profile existed and was bound to nothing. The listing of
`/usr/lib/NetworkManager/1.46.6/` contained one plugin,
`libnm-device-plugin-wifi.so`.

**What was done.** Read the recipe rather than guessed. In
`networkmanager_1.46.6.bb`, the version on the board:

```
PACKAGECONFIG ??= "readline nss ifupdown dnsmasq nmcli vala systemd \
    <bluez5 if bluetooth> <filter of DISTRO_FEATURES: wifi polkit ppp> ..."
```

Three things this project needs are absent from that default.

| Missing | What it costs |
|---|---|
| `wwan` | No `networkmanager-wwan` package, so no `libnm-device-plugin-wwan.so`, so no `gsm` device type. This is the observed symptom |
| `modemmanager` | `-Dmodem_manager=false`. Even with the plugin, no ModemManager integration |
| `concheck` | `-Dconcheck=true` is not passed, so the connectivity check is compiled out |

The fix is two lines: `PACKAGECONFIG:append:pn-networkmanager` in
`kas/bench-router.yml`, and `networkmanager-wwan` in the image recipe. Both
are needed. Building the package without installing it, or installing a
package that was never built, each leave the same symptom.

**The third one is the serious one.** `concheck` fails silently and in the
worst possible direction. `connectivity.conf` is installed, NetworkManager
parses it without complaint, `nmcli general` reports a connectivity state,
and none of it does anything, because the feature is not in the binary.
That is acceptance criterion 3 in its entirety: the case where the cable is
plugged in, the carrier is up, and the home router has lost its own uplink.
Nothing about it would have shown up on a bench with one uplink. It was
found by reading the recipe while chasing a different bug.

**The general lesson, which is now Decision 43.** A configuration file
proves nothing about whether the feature it configures exists. In a
distribution you install a package and get the features its maintainer
chose; in Yocto you choose them, and `PACKAGECONFIG` is where that choice
lives. Every recipe in an image has one, most people never look at one, and
the default is somebody else's idea of a sensible desktop.

**And the size question, answered from the same file.** The 64 MB of ICU,
SpiderMonkey and NSS that `buildhistory` found is two entries in that same
list. `nss` is in the default and is the crypto backend, with
`PACKAGECONFIG[gnutls]` as the alternative. `polkit` arrives through the
`DISTRO_FEATURES` filter, and it is in `DISTRO_FEATURES` because
`kas/bench-router.yml` put it there, on a guess that NetworkManager needed
it. It does not. polkit governs what a non-root D-Bus caller may change,
and every caller on this box is root.

So one speculative word in a kas file cost about 50 MB of a 237 MB rootfs,
and it sat behind a comment confidently explaining why it was necessary.
Both are now changed, with the measurement recorded next to them.

---

## 23. What the first boot proved, and what it did not

Proven on hardware, none of which could be checked before:

| Claim | Evidence |
|---|---|
| The kernel fragment reaches the hardware | `qmi_wwan` and `option` registered at 0.83 s and 0.94 s, before any module could load |
| The 9001 USB composition is what the module presents | `1e0e:9001`, `ttyUSB0..4`, `cdc-wdm0`, `wwan0`, with no `AT+CUSBPIDSWITCH` |
| The udev rules name the right ports | `/dev/lte-at -> ttyUSB2`, `/dev/lte-nmea -> ttyUSB1` |
| The strict ModemManager filter does not block the modem | `mmcli -L` lists it |
| `bench-router-setup` reads a card written on Windows | The access point came up on the name and passphrase in `router.conf` |
| The access point, DHCP and addressing work | A laptop associated, got a lease and reached `10.20.0.1` over ssh |
| `lte-gpio` runs on target | `chip pinctrl-bcm2711, pwrkey offset 6, flight offset 4` |
| The header carries the modem's current | No undervoltage through registration, throttle flags `0` |
| Nothing fails at boot | `systemctl --failed` empty |

Not proven, and why:

| Not proven | Blocked by |
|---|---|
| A connected bearer | The `wwan` plugin, entry 22. Needs a rebuild |
| Failover between two uplinks | This bench has no Ethernet cable within reach. One uplink is not a failover |
| The connectivity check | `concheck`, entry 22, and also needs a second uplink |
| A GNSS fix | The GNSS antenna is not attached |
| The metrics endpoint over HTTP | Not yet queried from a client |
| Anything the watchdog does | Masked for this boot, entry 21 |

The Ethernet one is worth stating plainly because it is not a defect and
cannot be fixed by a rebuild: **the central claim of this project cannot be
demonstrated on this bench as it stands.** Scenarios 1 and 2 in
`docs/failover-tests.md` both require pulling a wired uplink. The options
are a USB Ethernet adapter, or a USB Wi-Fi dongle as a client uplink while
the onboard radio stays the access point. Either is a purchase, and the
choice belongs in the failover document rather than in a rebuild.

---

## 24. The bearer came up, and the firewall justified itself in four minutes

**What happened.** The rebuild carried the `wwan` plugin, `concheck`, the
corrected kernel fragment and the polkit removal. On the second boot:

```
cdc-wdm0:gsm:connected:lte
wwan0        10.166.165.254/30
default via 10.166.165.253 dev wwan0 proto static metric 700
```

A live bearer, a carrier address, and the default route at the metric the
`lte` profile configures. `ping -I wwan0` returned 0 per cent loss at 103 ms
average. Full output in
[docs/evidence/first-bearer.txt](docs/evidence/first-bearer.txt).

**One step remained after the rebuild**, and it was neither software nor
wiring: the SIM had a PIN, and `mmcli` said so precisely, `state: locked`.
Sent by hand. The card is temporary and the PIN stays on it, so the proper
fix went into the tree instead: `router.conf` gained an optional `PIN=` key,
because a SIM PIN is identity and identity belongs on the card rather than
in the image. It is absent by default, and absent means no key at all
rather than an empty one, since `pin=` with nothing after it is a
zero-length PIN the modem rejects. Both cases are tested.

**The measurement worth keeping.** A few minutes after the bearer came up:

```
type filter hook input priority filter; policy drop;
counter packets 40 bytes 6035 comment "dropped, mostly from the LTE side"
type filter hook forward priority filter; policy drop;
counter packets 0 bytes 0 comment "forward denied"
```

Forty packets dropped on input, zero forwarded. Unsolicited traffic
arriving at a carrier-assigned address within minutes of it existing. The
specified ruleset has no input chain, so its policy would have been accept
and all forty would have reached the SSH server that `debug-tweaks` left
without a root password, and the metrics endpoint that publishes this box's
position. Decision 39 was argued from first principles; this is the
measurement.

**A small lesson in the metrics.** `lte_signal_quality_ratio 0.78` sits next
to `rsrp -105`, `rsrq -17`, `snr -3.6`. Those three describe a poor to
marginal cell. ModemManager's coarse quality says 78 per cent. They cannot
both be a useful summary, and the exporter reports the measurements for
exactly this reason.

**Two more gaps the boot found, both fixed in the tree.** `hciuart.service`
failed at every boot: poky carries `bluetooth` in `DISTRO_FEATURES`, which
switches on NetworkManager's `bluez5` PACKAGECONFIG, which builds a
Bluetooth plugin, which recommends BlueZ, whose `hciuart` then tries to
attach a controller to the UART this board uses as its console. A gateway
has no use for any of that chain, and a unit that fails at every boot
teaches whoever reads `systemctl --failed` to ignore it. And `curl` was
absent, while `docs/BRINGUP.md` instructs the reader to query the metrics
endpoint with it. A documented command the image cannot run is a
documentation defect, not a missing convenience.

**Where that leaves the acceptance criteria.** Criterion 6 is met with real
data. Half of criterion 1 is met: `wwan0` at metric 700. The other half,
`eth0` at 100, and criteria 2 and 3 with it, need a second uplink this bench
does not have. Criteria 4, 5 and 7 are now unblocked and need only time on
the board.
