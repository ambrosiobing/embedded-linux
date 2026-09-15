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

**What was done.** This project started by reading `sections/p15.tex` and
the four `figures/p15_*.tex` sources, and
[docs/DESIGN.md](docs/DESIGN.md) was written from them before any recipe.

**Why that and not the alternative.** The alternative is what happened last
time: build the thing, then reconstruct the design from the thing. That
produces documentation that describes the implementation rather than the
intent, and it cannot catch the case where the implementation drifted from
what was asked for. It also wastes the figures somebody already drew.

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

## 3. The watchdog was split in two, against the book

**What happened.** The book's watchdog is a single Python program that calls
libgpiod through its Python bindings to pulse PWRKEY.

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

## 4. The book's firewall has no input chain

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
the ruleset and two kernel options behind it.

---

## 5. The metrics endpoint was bound to the LAN, not to everything

**What happened.** The book's exporter is `python3 -m http.server 9101
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

**What happened.** The book installs `bench-lan.conf` into `/etc/dnsmasq.d/`
and `nftables.conf` into `/etc/nftables.conf`, both relying on the
distribution's packaged service to pick them up.

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

Two netfilter options are in the fragment for one line of the ruleset:
`NFT_RT` and `NFT_EXTHDR`, which are what `tcp option maxseg size set rt mtu`
is made of. Without them that line fails to load and takes the whole ruleset
with it. A box whose input policy is drop, with no ruleset loaded, has no
ruleset at all.

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
