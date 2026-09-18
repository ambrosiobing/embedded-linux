# Decisions

Each entry records what was chosen, what was rejected, and why. The
rejected option is the useful half: a decision without an alternative is
just a description.

Format: **context**, **decision**, **rejected**, **consequence**.

---

## 1. Yocto for this project, although daqring uses Buildroot

**Context.** Both are credible build systems for a Raspberry Pi image.

**Decision.** Yocto, with `meta-bench` as the layer.

**Rejected.** Buildroot, which would have been faster to learn and about a
third of the build time.

**Why.** Two reasons. Project 1 must produce a cross SDK for nineteen later
projects, and SDK generation is a first-class Yocto feature that Buildroot
only approximates. And `daqring` already demonstrates Buildroot, so the pair
covers both major build systems, which is usually the first question asked
about this kind of work.

**Consequence, now measured rather than predicted.** 194 minutes for the
first build against Buildroot's roughly one hour, 60 GB of disk, and an
evening lost to three kernel modules that had to be named one at a time.
Buildroot installs every module the kernel builds; `core-image-minimal`
installs none, so the WiFi would probably have worked first time on the
other system.

Against that: 21-second incremental rebuilds from shared state, a
per-package manifest that makes "every package can be justified" a checkable
criterion, `buildhistory` answering two package mysteries as a `git diff`, a
licence mechanism that refused to ship proprietary firmware until it was
explicitly accepted, a cross SDK that matches the image exactly, and a
demonstrated reproducible build.

The trade in one line: Yocto makes you name everything, which is why the
image is explicable and why the radio took three attempts. That is worth
knowing from having paid it, and is written up with the numbers in
[02. Build systems](02-build-systems.md).

---

## 2. kas, rather than hand-managed bblayers.conf and local.conf

**Context.** A Yocto build needs several repositories at compatible
revisions plus two generated configuration files.

**Decision.** One tracked YAML file. `kas build kas/bench-rpi4.yml`.

**Rejected.** The documented manual path: clone, `source oe-init-build-env`,
edit the generated files. Also rejected: a shell script that does the same
clones, which is the usual homegrown alternative.

**Why.** The manual path leaves every decision in untracked files inside a
gitignored build directory. Six months later nobody can say which revisions
produced an image. That is a support problem, not a convenience one.

**Consequence.** One more tool to install, and the build directory becomes
disposable.

---

## 3. One repository for twenty projects, not twenty repositories

**Context.** Each project could be published on its own.

**Decision.** A monorepo with a shared layer and `projects/NN-slug/`
directories.

**Rejected.** Twenty repositories, which would each look self-contained.

**Why.** The projects genuinely depend on each other: Project 5 writes a
driver Project 10 exercises, Projects 11 and 12 compile against the SDK
Project 1 produces, Projects 5, 6 and 19 want the identical rootfs on
another board. Twenty repositories would mean twenty copies of the same
layer pins, and a reader would have to reconstruct the order.

**Consequence.** A larger repository, and a reader arriving at Project 14
needs the index to orient. The root README exists for that.

---

## 4. One shared layer, not one layer per project

**Context.** Yocto supports any number of layers, and per-project layers
would isolate each one.

**Decision.** A single `meta-bench`, with recipes grouped by directory.

**Rejected.** `meta-project-05`, `meta-project-06`, and so on.

**Why.** Twenty layers means twenty `layer.conf` files, twenty sets of
dependencies, and twenty entries in every kas file. The isolation buys
nothing, because the projects are meant to share an image.

**Consequence.** If one project ever needs genuinely conflicting
configuration, it gets its own layer then, added to the same kas `repos`
entry. The structure allows it without requiring it now.

---

## 5. The status daemon is two programs, not one

**Context.** Three LEDs showing system health.

**Decision.** `bench-status` in C drives the lines; `bench-state` in shell
decides what to show. One word in `/run/bench/state` between them.

**Rejected.** A single C daemon that queries systemd directly.

**Why.** Changing which services count as healthy would otherwise mean a
recompile and a reflash, testing would need a board, and much of the code
would be a worse reimplementation of systemd.

**Consequence.** Two programs and a file instead of one program. In return,
the decision logic is tested in under a second on any machine, and the
policy is a text file on the target.

---

## 6. libgpiod v2 and the character device, not sysfs

**Context.** Two GPIO interfaces have existed in Linux.

**Decision.** `/dev/gpiochipN` through libgpiod v2.

**Rejected.** `/sys/class/gpio`, which is simpler to demonstrate.

**Why.** It is deprecated and removed. It had no ownership model, so two
programs could fight over a pin, and nothing was released when a process
died. The kernel fragment also turns off `CONFIG_GPIO_CDEV_V1`, so nothing
in the image can quietly use the old path.

**Consequence.** A more verbose API, and a hard requirement on libgpiod 2.x
rather than the 1.x still common in older distributions.

---

## 7. The GPIO chip is found by label, not by index

**Context.** The daemon needs `/dev/gpiochip?` for the 40-pin header.

**Decision.** Walk the chips, match the label `pinctrl-bcm2711`, fall back
to the first chip wide enough.

**Rejected.** Hard coding `/dev/gpiochip0`, as most examples do.

**Why.** `gpiochip0` is the header on a Pi 4 but not on a Pi 5, and the
numbering moves when an expander probes first. It is exactly the kind of
assumption that works on one desk and fails on another.

**Consequence.** About forty more lines of C, and the label is configurable
for a board nobody has taught it about.

---

## 8. LED polarity is configuration, not a constant

**Context.** The bench LED modules have `S1`, `S2`, `U` and `G` pins. With a
supply pin, the LED may light on a low signal, and the silkscreen does not
say which.

**Decision.** `/etc/bench/leds.conf` carries `active_low`, and the code
calls `gpiod_line_settings_set_active_low()`.

**Rejected.** Assuming active high, which was the original design when the
LEDs were thought to be bare.

**Why.** Guessing wrong produces a board that works but shows the wrong
colour, which is worse than an obvious failure. libgpiod already has the
abstraction, so the kernel does the inversion and the program never reasons
about volts.

**Consequence.** One configuration file and one line of C. Rewiring the
breadboard no longer means rebuilding the image.

---

## 9. Kernel changes as a fragment, never a copied .config

**Context.** The bench needs a dozen kernel options the BSP default lacks.

**Decision.** `bench.cfg`, merged by the kernel recipe, with every line
naming the projects that need it.

**Rejected.** Copying the generated `.config` into the layer, which is what
the shortest path suggests.

**Why.** A copy is thousands of lines, pins the layer to one kernel version,
and hides which twelve options you actually care about. A fragment survives
the BSP rebasing and reads as a list of reasons.

**Consequence.** A fragment can be silently ignored, so `./go kconfig`
checks every line, including the ones asking for an option to stay off.

That check originally read the build tree, which turned out to be fragile:
`RM_WORK_EXCLUDE` preserves a work directory that a build creates, and a
build that is a complete shared-state hit never compiles the kernel at all.
Decision 19 moves the check onto the running kernel instead.

---

## 10. A skipped check counts as a failure

**Context.** `./go check` compiles the daemon before a three hour build. On
a host without `pkg-config`, the compile silently skipped and the script
still reported success.

**Decision.** A missing tool fails the run and names the tool and the
command to install it.

**Rejected.** Printing a note and passing, which is the common pattern.

**Why.** A gate that passes by not checking is worse than no gate: it
produces false confidence at exactly the moment someone commits three hours
to a build.

**Consequence.** A host without the development packages cannot get a green
check at all. That is intended, and the message says what to install.

---

## 11. The reproducibility claim is narrow and stated precisely

**Context.** Reproducible builds are a Yocto feature and a strong claim.

**Decision.** `./go reproduce` tests exactly one thing: a clean build from
the same commit produces the same package list. The README says it does not
claim bit-identical images.

**Rejected.** Claiming reproducible builds without qualification, or
attempting full binary reproducibility now.

**Why.** Timestamps, build paths and build IDs still differ. A narrow claim
that can be demonstrated on request is stronger than a broad one that
collapses under the first follow-up question.

**Consequence.** Full binary reproducibility remains available as a later
piece of work, with the groundwork already in place.

---

## 12. The build-times table is empty

**Context.** A README with an empty table looks unfinished.

**Decision.** Leave it empty until the build has run on this bench.

**Rejected.** Quoting typical figures from documentation or another machine.

**Why.** A number nobody measured cannot be defended, and the whole point of
the exercise is evidence. The same rule governs the evidence directory: it
stays empty until the board has actually run.

**Consequence.** Anyone reading the repository before the first build can
see precisely what has and has not been done, which is more useful than a
table of plausible numbers.

---

## 13. The LED indication is deferred, the code is not

**Context.** The bench LEDs are Joy-IT LinkerKit LK-LED10 modules with a
2.0 mm socket. The available jumper wires are 2.54 mm Dupont. They cannot
mate, so the modules were never electrically connected.

**Decision.** Defer the LED output, keep every line of the software, and
write down precisely what is and is not verified.

**Rejected.** Removing `bench-status` from the project, which would have
deleted the part that actually demonstrates something: a C program packaged
in a Yocto recipe with systemd units, a state machine, and tests.

**Why.** The daemon is verified on hardware. It runs, holds lines 17, 22 and
27, and reports state correctly. The single unverified link is that output
values reach the pins as voltages, which needs an LED or a meter. Saying
that plainly is worth more than a diode.

---

## 14. The serial console is deferred to Project 2

**Context.** The bench cable is a PL2303HXA. Prolific's current Windows
driver refuses it, it dropped its USB connection twice during bring-up, and
the 7 inch DSI panel works as a console instead.

**Decision.** Drop serial from Project 1's criteria. Keep `ENABLE_UART` and
the kernel's `serial0` console in the image.

**Rejected.** Removing the UART configuration entirely, and buying a cable
before continuing.

**Why.** Project 2 brings up a NanoPi NEO Air, which has no HDMI and no DSI.
Serial is its only console and interrupting U-Boot requires it. Removing the
capability now would mean rediscovering it in a month. A CP2102 or FTDI
adapter is the thing to own before then.

---

## 15. The image carries WiFi capability, the card carries the credentials

**Context.** The bench has no wired network in reach, and the repository is
public.

**Decision.** The image ships firmware, `wpa-supplicant` and a network file.
A first-boot service reads `SSID` and `PSK` from `wifi.conf` on the FAT boot
partition and writes the supplicant configuration from them.

**Rejected.** Putting the credentials in the layer or in the kas file. Both
are tracked, so the password would be in the history permanently, where
rotating it does not remove it.

**Why.** Images carry capability, devices carry identity. It is the same
split as per-device key provisioning at manufacturing, which is stage 5 in
[the lifecycle](09-lifecycle.md), and it means the card can be written from
any machine with a text editor.

---

## 16. CI pins its runner and builds libgpiod from a tag

**Context.** Thirteen consecutive CI failures. The last and real cause was
that GitHub's `ubuntu-latest` ships libgpiod **1.6.3**, and the daemon
targets v2. No Ubuntu LTS image packages v2.

**Decision.** Pin `runs-on: ubuntu-24.04`, do not install `libgpiod-dev`
from apt at all, and build libgpiod from tag `v2.1.3` taken from kernel.org.

**Rejected.** Skipping the compile when v2 is absent, which is a gate that
passes by not checking, exactly the fault in decision 10.

**Why.** `ubuntu-latest` is a moving target in the same way a git branch is,
and this repository's whole rule is to name the version. Building the
library also means the check no longer depends on what any distribution
happens to package.

---

## 17. Shell files and tests are discovered, not listed

**Context.** A new script, `bench-wifi-setup`, was written and shellchecked
by nothing, because the CI invocation named its files by hand. The same
shape had already bitten the test runner, where a new test file would not
have been run.

**Decision.** Both `./go check` and CI find their inputs: shell files by
shebang and by `.sh` extension, tests by globbing `tests/*.sh`.

**Rejected.** Adding the new files to the existing lists, which fixes today
and fails the next time somebody adds a file.

**Why.** A hand-maintained list of things to check is a list that new things
do not join, and the failure is silent: the check passes because it never
looked.

---

## 18. The disk guard checks the host, not only the guest

**Context.** A build filled a 254 GB Windows drive to zero bytes, the guest
filesystem remounted read-only mid-build, and BitBake died with I/O errors.
`require_disk_gb` had reported 919 GB free minutes earlier.

**Decision.** `require_host_disk_gb` also checks `/mnt/c` when it exists.
25 GB for a build or SDK, 60 GB for a reproduce run.

**Rejected.** Treating it as a one-off and remembering to watch the host
drive.

**Why.** Under WSL the guest reports the virtual disk's maximum size, not
what Windows can supply. The check was precise and about the wrong number.
Nobody remembers to watch a number manually.

---

## 19. The kernel reports its own configuration

**Context.** `./go kconfig` had nothing to read: a build that is a complete
shared-state hit never compiles the kernel, so `RM_WORK_EXCLUDE` has no work
directory to preserve.

**Decision.** `CONFIG_IKCONFIG_PROC` in the fragment, giving
`/proc/config.gz` on the board, and `./go kconfig` accepts a path.

**Rejected.** Forcing a kernel rebuild with `bitbake -c compile -f` whenever
the check is needed.

**Why.** Same cost in build time, and the evidence is better: it proves what
the hardware is executing rather than what a build directory once contained.
It also survives cleaning the build tree, which the alternative does not.

---

## 20. Bench policy is its own recipe

**Context.** The German console keymap, the wireless network file and the
credential provisioning all needed a home.

**Decision.** A separate `bench-provision` recipe, not additions to
`bench-status`.

**Rejected.** Folding them into the existing recipe, which already ships
configuration to `/etc/bench`.

**Why.** `bench-status` is about status. These are about this workshop: its
keyboard, its network, its lack of a cable. Two recipes with one subject
each stay explicable; one recipe with two subjects does not. The root README
lists every one of these assumptions with the file that sets it, because
they are choices about one bench rather than defaults anyone should
inherit.

---

## 21. Supply-chain artefacts are a separate build, not the default

**Context.** The EU Cyber Resilience Act obliges manufacturers of products
with digital elements to produce and maintain an SBOM and to handle reported
vulnerabilities. Reporting duties began in September 2026. Yocto can produce
all of it: `create-spdx` for the bill of materials, `cve-check` against the
NVD, `archiver` for corresponding source.

**Decision.** A separate configuration, `kas/bench-release.yml`, reached
through `./go release`. The everyday build does not carry them.

**Rejected.** Enabling them in `bench-rpi4.yml` so every build produces
them, which is the tidier-looking option.

**Why.** Each costs build time, `cve-check` needs network and a database,
and the everyday cycle is 90 seconds precisely because nothing unnecessary
runs. The lifecycle document puts these at stage 4, pre-production, not
stage 2. Making the configuration match that division means the document
describes something runnable rather than something aspirational.

**Consequence.** Somebody has to remember to run `./go release` before a
release. That is the correct failure mode: forgetting produces no SBOM,
which is visible, rather than a development build silently carrying release
machinery.

---

## 22. CI actions are pinned to commits, and the token is read-only

**Context.** The workflow used `actions/checkout@v4` and inherited whatever
token permissions the repository default gave it.

**Decision.** Pin to the commit behind the tag, with the version in a
comment, and declare `permissions: contents: read`. Add a `concurrency`
group so a newer push cancels an older run.

**Rejected.** Trusting the tag, which is what most workflows do.

**Why.** A git tag is mutable. Whoever controls an action can move `v4` to
different code, and a job holding a write token can then push. It is the
same rule this repository already applies to Yocto layers and to libgpiod in
CI: name the exact commit, not a label that can be repointed.

---

## 23. Bench configuration split again: identity and wireless client

**Context.** Project 15's router runs an access point on `wlan0` under
NetworkManager. `bench-provision` shipped the German keymap together with a
systemd-networkd profile and a `wpa_supplicant` client setup for that same
interface.

**Decision.** Split into `bench-provision`, site identity only, and
`bench-net-wifi`, the wireless client half. `bench-image` installs both;
`bench-router-image` removes the second.

**Rejected.** Keeping one recipe and masking the units the router does not
want.

**Why.** Masking leaves the files installed and inert, which is precisely
the state that costs someone an afternoon six months later. Two network
managers on one interface is not a conflict that resolves itself. Decision
20 split bench policy out of the status daemon for the same reason; this is
the same cut one level finer.

**Consequence.** Project 1's package manifest gains one entry, so its
recorded count of 112 now counts a differently sliced set.

---

## 24. The watchdog is two programs, and the GPIO half is not Python

**Context.** The watchdog as originally specified is one Python program that
drives PWRKEY through libgpiod's Python bindings.

**Decision.** `lte-gpio` in C owns the control lines; `lte-watchdog` in
Python owns the probe and the escalation and reaches hardware only by
running `lte-gpio`.

**Rejected.** One program, as specified.

**Why.** Three reasons. The escalation ladder becomes testable on a laptop
against stubs, which it cannot be with in-process bindings. The C stays
short enough to read in one sitting, which is Decision 6 applied again.
And `python3-libgpiod` is a separate package whose name differs between
OpenEmbedded releases: a recovery path that fails on an import is a
recovery path that does not exist, and the one time it matters is the one
time nobody is watching.

**Consequence.** A `fork` and `exec` per PWRKEY press, on a path that runs
at most once every few minutes.

---

## 25. The router firewall has an input chain

**Context.** The specified ruleset has forward and postrouting chains only,
leaving the input policy at accept.

**Decision.** An input chain with policy drop: return traffic, loopback,
ICMP, DHCP and DNS from the LAN, ssh from the LAN and the cable, and the
metrics port from the LAN only. Everything else counted and dropped.

**Rejected.** The ruleset as specified.

**Why.** With an accept policy, every service on the box is reachable from
the carrier network as soon as the bearer comes up, including an SSH server
that `debug-tweaks` left with a passwordless root and a metrics endpoint
that publishes the box's position. The bench assumptions that are harmless
behind a home router stop being harmless the moment the box has a public
address.

**Consequence.** Adding a service to this image now means adding a line to
the ruleset. That is the correct failure mode: forgetting produces a service
nobody can reach, which is visible, rather than one everybody can.

---

## 26. Firewall invariants are asserted, not reviewed

**Context.** `nft -c -f` checks syntax. It accepts an input policy of
accept, a masquerade rule naming one uplink, and a forward chain with no MSS
clamp, all of which work on a bench and fail in the field.

**Decision.** `tests/bench-router-nftables-test.sh` asserts the properties
themselves, and runs `nft -c` in addition where the tool exists.

**Rejected.** Relying on the syntax check plus review.

**Why.** The three mistakes above are invisible in a diff that is otherwise
correct, and two of them produce a box that passes every test on the bench.
This is Decision 17's principle, that checks find their own inputs, applied
to meaning rather than to file lists.

---

## 27. The router kernel fragment is opt in

**Context.** The router needs built-in USB modem drivers and a built-in
netfilter stack. `bench.cfg` is shared by every image, including the one
Project 3 measures boot time and kernel size with.

**Decision.** A second fragment, `router.cfg`, added to `SRC_URI` only when
`BENCH_ROUTER_KERNEL` is set, which `kas/bench-router.yml` does.

**Rejected.** One fragment for every image.

**Why.** Quietly changing a kernel another project has already measured
invalidates that measurement without anyone noticing. The kas file is
already where per-project build policy lives.

**Consequence.** One line of BitBake whose quoting is dictated by
`scripts/lint.py`, and is commented as such.

---

## 28. The modem drivers are built in, not modular

**Context.** The obvious packaging is `kernel-module-option`,
`kernel-module-qmi-wwan` and about six netfilter module packages in the
image recipe.

**Decision.** `=y` in the kernel fragment. No module packages named.

**Rejected.** Modules, which is what a general-purpose distribution does.

**Why.** `core-image-minimal` installs no kernel modules at all, so a driver
built as a module is a driver that exists in the build tree and not in the
image. That cost Project 1 two rounds of debugging on `wlan0`: once for the
core driver and once for the vendor module modern brcmfmac requests by name
at probe time. On a router the modem and the packet filter are not optional
extras, so the class of failure is removed rather than managed.

**Consequence.** A larger kernel image, on a mains-powered box with an SD
card.

---

## 29. Every project is self-contained, and cites nothing outside the repository

**Context.** These twenty projects were scoped in a separate document that
lives outside this tree. The early text referred to it, with sentences like
"the specification's Project 1 drives three LEDs" and pointers to figure
sources by filename. A reader who did not have that document could not
check the claim, could not see the figure, and in several places could not
tell what the project had actually been asked to do.

**Decision.** Nothing in this repository refers to a document that is not in
this repository. Where the outside text was the authority, its content is
written out here instead: the acceptance criteria are listed in full in each
project's README, the four figures are redrawn as ASCII and mermaid in each
project's `docs/DESIGN.md`, and a difference from the original scope is
described by what the difference is rather than by naming where the original
lives.

**Rejected.** Two alternatives. The first was to keep the references and add
a note explaining where to find the source, which solves nothing for a
reader who will never have it and quietly makes the repository a companion
volume rather than a work. The second was to delete the sentences that
referred outward, which is cheaper and loses the reasoning: "four things are
done differently" is only interesting if the reader can see what they are
different from.

**Why.** This repository is read by people who arrive at a URL with no
context: an engineer evaluating the work, a colleague looking for how a
thing was done, or the author in three years. Every one of them is served
by a tree that answers its own questions. It is also the same discipline the
rest of the repository already applies to builds, where a kas file that
depends on state outside itself is the defect that
[05. kas and layers](05-kas-and-layers.md) exists to prevent. A document
that depends on state outside itself is the same defect in prose.

**Consequence.** The project READMEs are longer, because a criterion written
out is longer than a citation. Narrative that summarised an outside source
now has to state it: where a sentence would have said "as specified", it
says what was specified. This applies to the eighteen projects not yet
built as much as to the two that are.

---

## 30. The real-time kernel is an opt-in fragment and a pinned version

**Context.** `PREEMPT_RT` replaces the locking primitives of the whole
kernel. Project 8 compares an RT kernel against a generic one, so exactly
one variable has to differ between the two rows.

**Decision.** `rt.cfg`, added to `SRC_URI` only when `BENCH_RT_KERNEL` is
set, which `kas/bench-rt.yml` does. The same kas file also sets
`PREFERRED_VERSION_linux-raspberrypi = "6.12.%"`.

**Rejected.** The switch alone. Also rejected: applying the out-of-tree
real-time patch series to the BSP default kernel.

**Why.** `kernel/Kconfig.preempt` makes `PREEMPT_RT` depend on
`EXPERT && ARCH_SUPPORTS_RT`, and `arch/arm64/Kconfig` gained that select
in 6.12. meta-raspberrypi on scarthgap still defaults to 6.6 and ships a
6.12 recipe beside it. Without the version pin the fragment names a symbol
with no prompt, kconfig drops it in silence, the build succeeds, and the
board boots a kernel that is not preemptible while the results table claims
otherwise. Patching 6.6 would reach the same place through a rebase
treadmill.

**Consequence.** Two lines instead of one, and two independent checks that
the intent arrived: `/sys/kernel/realtime` on the board, and
`./go kconfig -f rt` against `/proc/config.gz`. The fragment names the
other members of both kconfig choices as explicitly off, so that the
checker has something to compare against rather than passing on the lines
that were never in doubt.

---

## 31. A kernel is not allowed to be its own witness

**Context.** Real-time Linux is argued about with cyclictest numbers.
cyclictest measures the kernel from inside a task that kernel is
scheduling, using that kernel's clock.

**Decision.** A second instrument that shares nothing with the first except
a wire. The measured task toggles a GPIO line; an MCC 118 DAQ HAT samples
that line at 100 kS/s on its own crystal, from a process at normal priority
on another core.

**Rejected.** An in-kernel IIO driver for the HAT, which would be more
elegant, and cyclictest alone, which is what everybody quotes.

**Why.** An instrument inside the system under test is subject to the
delays it is measuring. The external path also sees something the internal
one structurally cannot: the cost of the system call that moved the pin.
That difference is the finding rather than an error term, and the whole
project exists to be able to interpret it.

**Consequence.** Two clocks, so the measurement carries a constant offset
of tens of parts per million. It is reported as its own column and
deviations are measured from the run's mean rather than from the nominal
period, so that a crystal difference is never counted as jitter.

---

## 32. A run refuses rather than records

**Context.** A measurement script normally takes the configuration as
arguments and writes it into the output, so that the row says what was set.

**Decision.** `rt-run` takes the configuration as flags and then checks it
against the kernel before measuring anything. `-i` on a kernel that
isolated nothing is refused; no `-i` on a kernel that did isolate the core
is refused too; a board already reporting a throttle state refuses to
start; a DAQ overrun voids the run and writes no row.

**Rejected.** Recording what was asked for, and trusting the operator.

**Why.** `isolcpus=3` in a text file is not isolation; the kernel having
accepted it is. One row labelled isolated that was not makes the whole
table unusable, and nothing in the output would admit it. The reverse
direction is easier to forget and just as damaging: a control row measured
after a reboot that still carried the isolation parameters.

**Consequence.** Runs fail more often, and they fail before spending sixty
seconds. The refusal messages name the exact kernel command line to add
rather than describing the problem.

---

## 33. Instrument resolution is measured, not assumed

**Context.** Recovering an edge time below the sample period by
interpolating the threshold crossing is standard practice, and the standard
justification is that the edge is fast compared to the sample period.

**Decision.** `rt-analyze` measures what fraction of crossings were
actually interpolated, reports it as a column in every results row, and
warns on stderr when that fraction says the interpolation did nothing.

**Rejected.** Applying the interpolation and reporting three decimal places.

**Why.** The justification is backwards. If the edge is much faster than a
sample, then the sample before every crossing sits at one rail and the
sample after it at the other, the interpolated fraction is exactly one half
every time, and the resolution is one sample period wearing a decimal
point. Interpolation needs an edge slow enough to be caught mid-transition,
which on this bench means a deliberate series resistor and capacitor.

**Consequence.** The schematic carries an optional RC that was not in the
original parts list, and `tests/rt-analyze-test.sh` asserts the difference
in microseconds: the same 2.0 us of injected jitter reads as 4.2 us through
an ideal edge and as 2.0 us through a slowed one. The mean and the clock
offset survive either way, which is stated rather than implied, because
those are the two numbers a reader is most likely to take on trust.

---

## 34. A protocol is a document first, and one implementation second

**Context.** Project 12 has a framed binary protocol between a
microcontroller and Linux. The obvious order is to write the encoder, get
frames flowing, and document it afterwards.

**Decision.** `docs/PROTOCOL.md` was written first and is the
specification of record. `proto.c` is compiled into both ends, so there is
one implementation rather than two. A second implementation exists in
Python, written from the document, purely so that the first can be
compared against something.

**Rejected.** Documenting after the fact, and implementing separately at
each end.

**Why.** A frame layout has a field order, an endianness, a CRC variant
and a resynchronisation rule, and every one of those becomes impossible to
change once two implementations exist. Writing them down forced the
resynchronisation rule to be decided rather than to emerge, and that rule
turned out to be the only substantive decision in the format.

Two implementations of one protocol drift, and they drift silently,
because each end is consistent with itself. One implementation compiled
twice cannot. The Python reference is not a third end: it is a test
instrument, and it is only useful because it was written from the document
rather than transcribed from the C.

**Consequence.** `tests/sensorhub-cabi-test.sh` can compare the C against
the specification byte for byte, including 900 randomised cases, on any
machine with a compiler. The firmware's protocol layer is therefore
covered before the firmware exists.

---

## 35. Encode by hand, decode with a library

**Context.** CBOR at both ends. The conventional answer is tinycbor on the
microcontroller and libcbor on Linux.

**Decision.** The five payloads are encoded by hand in `proto.c`, about
sixty lines with no dependency and no allocation. Incoming payloads are
decoded with libcbor.

**Rejected.** A library at both ends, and hand-written code at both ends.

**Why.** The two directions are not the same problem. Outgoing payloads
have a fixed shape that will never grow: a sample is always a four entry
map with integer keys, two three element arrays and two scalars. Incoming
bytes have unknown shape and arbitrary length, arrive from a device that
may be running half a firmware, and are parsed by a daemon on the system
bus. The first is bounded work; the second is a job for a parser somebody
else has already fuzzed.

The firmware then needs no CBOR library at all, which on a part where
tinycbor is a measurable fraction of the image is not a small saving.

**Consequence.** The hand encoder must obey RFC 8949's preferred
serialisation exactly, because otherwise two implementations produce
different bytes for the same value and the byte-for-byte comparison is
impossible. That rule is in the protocol document and asserted at four
integer widths.

---

## 36. A method handler may block only for as long as nobody would notice

**Context.** Two D-Bus methods have to wait for a microcontroller to
acknowledge. `SetRate` waits microseconds; `Calibrate` waits about two
seconds.

**Decision.** They are implemented differently. `SetRate` blocks the event
loop for at most 200 ms, measured against `CLOCK_MONOTONIC`. `Calibrate`
takes a reference to the message, returns without replying, and the reply
is sent from the frame parser or from a three second timer.

**Rejected.** One mechanism for both. Either would work for one of them
and be wrong for the other.

**Why.** The bus default timeout is 25 seconds, and a handler that
approaches it does not merely fail: it stalls every other client of the
daemon, so the failure looks like a hung service rather than a slow
device. Two seconds of that is already too much. Two hundred milliseconds
on something that answers in microseconds is a bound on a case that does
not happen.

**Consequence.** The deferred path needs a pending message, a timer and a
reply from a callback, which is more machinery than the blocking path and
is the reason the blocking path is kept where it is safe. It also produced
one bug worth recording: the first bounded wait counted loop iterations
rather than consulting the clock, which with samples arriving continuously
expires in microseconds.

---

## 37. Policy lives outside the daemon, in two different places

**Context.** A system service has to decide who may talk to it and who may
do the privileged thing. The short answer is an if statement on the
caller's uid.

**Decision.** Neither question is answered in C. The bus policy answers
"may this connection talk to this name", before a byte reaches the daemon.
polkit answers "may this user run this action", through a rule that grants
the `bench` group and a default that refuses everybody else.

**Rejected.** Checking the caller's uid in the daemon; expressing the
group rule in the bus policy.

**Why.** The two questions look alike and are not. The bus knows about
connections and names; polkit knows about users, sessions and actions.
"Only the bench group may calibrate" cannot be written in a bus policy,
because the bus has no notion of an action. "Nobody outside this image may
own this name" cannot be written in polkit. A uid check in C reimplements
the first badly, cannot express the second at all, and puts the security
decision in the file least likely to be reviewed.

polkit is asked without user interaction, which is its own small decision:
a system service must not block a bus call while polkit looks for an
authentication agent, because on a headless board that wait is unbounded
and usually pointless. The answer comes from the rules immediately, and
authorisation is therefore a property of the caller's group rather than of
somebody being at a keyboard.

**Consequence.** Two more files to keep in step with the daemon and with
each other, which is what `tests/sensorhub-policy-test.sh` exists for. And
one trap worth naming: without `SD_BUS_VTABLE_UNPRIVILEGED` on the method,
sd-bus demands `CAP_SYS_ADMIN` from the caller before the handler runs, so
polkit is never asked and no rule can fix it.

---

## 38. Nothing is enabled at boot, because there are two ways to start

**Context.** The daemon needs a device that may not be plugged in. The
default answer is to enable the unit and let it restart until the device
appears.

**Decision.** The unit is installed and not enabled. udev starts it when
the device appears, through `TAG+="systemd"` and `ENV{SYSTEMD_WANTS}`, and
the bus starts it when a client calls, through a D-Bus service file naming
`SystemdService=`. `BindsTo=dev-sensorhub.device` stops it when the device
leaves.

**Rejected.** `WantedBy=multi-user.target` and a restart loop; polling for
the device inside the daemon.

**Why.** A unit enabled at boot on a board with nothing attached starts,
fails to open the device, and spends its restart budget before anybody
plugs anything in. Both activation paths are free, they cover the two
situations that actually occur, and neither makes an assumption about boot
order.

The third mechanism is the one usually left out. A daemon that keeps its
bus name after its device has gone answers calls with stale data, and a
client has no way to tell. `BindsTo` makes the unit's life the device's
life.

**Consequence.** Four files have to agree about one device path and one
unit name, including a systemd device unit name derived from the path by
escaping it. A test derives it the same way rather than trusting that two
strings were typed consistently.

---

## 39. A decoder stops at the first thing it does not recognise

**Context.** BlueST frames carry a 16-bit timestamp and then the fields of
every feature named in a 32-bit mask, back to back, highest bit first.
There are no length fields, no type tags and no padding.

**Decision.** The decoder walks all 32 bits rather than only the ones it
knows. At an unrecognised set bit it stops, keeps every field above it, and
marks the record with `undecoded_mask` and the remaining bytes. Those two
fields are columns in the CSV and keys in the MQTT payload.

**Rejected.** Skipping unknown bits and carrying on, which is what a
decoder written from the happy path does. Also rejected: raising on any
unknown bit.

**Why.** Without lengths, the width of every field is needed to locate the
ones below it, so an unknown bit makes everything after it unlocatable.
Skipping produces a complete record of plausible numbers read from the
wrong offsets, and nothing downstream can distinguish it from a good one.
Raising is safe and throws away measurements that were located correctly,
which matters because the likeliest unknown bit is a new low-order feature
in a firmware update.

**Consequence.** A frame shorter than its mask promises still raises, and
the distinction is the point: there the peripheral and the table disagree
about a field that is supposedly known, which is a fault rather than a gap.
The same reasoning applies to any length-free wire format, which includes
most sensor protocols that were designed to fit in a 20-byte BLE
notification.

---

## 40. Back-off is reset by data, not by connection

**Context.** A gateway that reconnects on its own needs a delay that grows
while a fault lasts, and returns to its floor when the fault clears.

**Decision.** The ladder resets when the link reaches Streaming, meaning at
least one characteristic is notifying, rather than when the peripheral
accepts a connection. A separate stall timeout ends a link that is still up
and has stopped delivering.

**Rejected.** Resetting on `Connected`, which is the obvious place and is
what the original scope does.

**Why.** A peripheral that accepts a connection and drops it immediately is
a common failure and the worst case for the obvious version: every attempt
"succeeds", the delay returns to one second, and the gateway retries as
fast as the radio allows for as long as the fault lasts. Resetting on data
makes the delay mean "how long since this link last actually worked". The
stall timeout closes the other half of the same gap: a supervision timeout
detects a peripheral that has gone away and cannot detect one that is
present and silent, which is what a firmware with one crashed task looks
like from the other end of a radio.

**Consequence.** A gateway sitting in Streaming with a green LED and an
empty file is now impossible, which was the failure mode worth designing
against because it looks exactly like success.

---

## 41. A dependency of a program is not a permission of a service

**Context.** Running a BLE client as a non-root user is documented
everywhere as "add the user to the bluetooth group", and adding a user to a
group is the kind of instruction that gets copied without checking.

**Decision.** No `bluetooth` group is created or joined. A `gpio` group is
created by the recipe, and the service joins that one.

**Rejected.** The documented instruction, and its alternative of running
the gateway as root.

**Why.** Two files settle it. Upstream BlueZ's own policy,
`src/bluetooth.conf`, ends with a default-context rule allowing any user to
send to `org.bluez`; the restricted policy with a `bluetooth` group in it
is Debian's patch. And poky's `bluez5` recipe creates no user and no group,
so on this image the group does not exist at all: naming it in
`SupplementaryGroups=` would not tighten a permission that is already
granted, it would stop the unit from starting. The LEDs are the opposite
case: `/dev/gpiochip0` really is inaccessible to an ordinary user, so there
the group is load bearing and the recipe has to make it.

**Consequence.** Every permission line in that unit is now there because
something needs it, which is the only way a hardened unit stays honest as
it is edited. It also generalises: a distribution's group is a property of
that distribution's patches, and the question to ask about any such
instruction is which file grants the permission.

---

## 42. One module imports the library, so the other three can be tested

**Context.** A BLE gateway needs a controller, a daemon and a peripheral.
None of them exists on a laptop, and the parts most likely to be wrong are
the reconnect logic and the frame decoding, neither of which is about
radio.

**Decision.** `blelink.py` is the only module that imports bleak, and it is
deliberately the smallest. The supervisor takes a link object with two
methods, the sinks take their clients as arguments, and the LED sink drives
a wrapper with two boolean methods rather than libgpiod directly.

**Rejected.** One module that does all of it, which is shorter and is what
the original scope sketches.

**Why.** It cost about thirty lines and bought 87 assertions that run in
under two seconds, including cases that are genuinely hard to produce on a
bench: a peripheral that accepts a connection and drops it, one that
connects and never notifies, a frame that is two bytes short. Two of the
three suites found a real defect on their first run.

**Consequence.** The part that can only be proven on a board is now
identifiable and small, which is also what the bring-up notes are organised
around. The same split is worth applying to any program whose interesting
behaviour is failure handling around a device: the device goes behind an
interface, and the behaviour becomes testable.

---

## 43. PACKAGECONFIG is part of the image specification, not a detail

**Context.** Project 15's NetworkManager saw the modem's `wwan0` and
refused to manage it, logging `'wwan' plugin not available`. The cause was
in the recipe's `PACKAGECONFIG ??=` default, which omits `wwan`,
`modemmanager` and `concheck`.

**Decision.** Router-specific `PACKAGECONFIG` for `networkmanager` lives in
`kas/bench-router.yml` alongside the other build policy, with a comment
naming what each entry buys and what its absence costs.

**Rejected.** Installing more packages and hoping, which is the habit a
distribution teaches.

**Why.** On a distribution you install a package and receive the features
its maintainer chose. In Yocto you choose them. A configuration file proves
nothing about whether the feature it configures exists in the binary, and
the failure is silent in both directions: `connectivity.conf` is parsed
without complaint by a NetworkManager built with `-Dconcheck=false`, and a
`gsm` profile is valid without a device type to bind it to.

**Consequence.** Every future project has to read the `PACKAGECONFIG` of
anything it depends on for a specific feature, before believing that
feature is present. That is a real cost and it is smaller than the
alternative, which is finding out in the field.

---

## 44. A distro feature is added on evidence, not on a guess

**Context.** `kas/bench-router.yml` carried
`DISTRO_FEATURES:append = " polkit"` behind a comment stating that
NetworkManager needed it. buildhistory later measured polkit, SpiderMonkey
and ICU at roughly 50 MB of a 237 MB rootfs, and `depends.dot` traced every
byte of it back to that one word.

**Decision.** Removed, with the measurement and the condition for restoring
it recorded in its place.

**Rejected.** Leaving it, on the grounds that it might be needed one day.

**Why.** polkit governs what a non-root D-Bus caller may change, and every
caller on this box is root. The guess was never tested and was expressed as
a fact in a comment, which is worse than leaving it unexplained: the next
reader has no reason to question it.

**Consequence.** The first time a non-root user needs to change a
connection, one line comes back. The general rule is that a
`DISTRO_FEATURES` entry costs whatever every recipe in the image does with
it, which is unbounded until measured, so it needs a reason that has been
checked rather than assumed.

---

## 45. Hardware the software cannot verify is armed by hand

**Context.** `lte-watchdog`'s last-resort recovery pulses a GPIO whose
header pin is a property of the HAT revision and its jumper block. The
defaults come from a vendor demo. The recipe enabled the unit at boot,
while the bring-up notes said to confirm the offsets against the schematic
first. The recipe won.

**Decision.** `pwrkey_verified` in `/etc/bench/lte.conf`, defaulting to
`0`. The rung refuses, logs why, and counts the refusal in
`lte_pwrkey_refused_total`.

**Rejected.** Shipping the unit disabled, and trusting the notes.

**Why.** Disabling the unit would disarm the two rungs that handle almost
everything and need no hardware knowledge, and a router whose recovery runs
only when somebody remembers to start it is not a router. Trusting the
notes had already failed once, in this repository, in the same week.

**Consequence.** A step for the operator, and a counter that makes the
un-armed state visible instead of silent. A wrong GPIO offset does not fail
safely: it drives whatever else is on that pin, on a board that is by then
unattended. Software can verify almost everything about itself and nothing
at all about which wire is where.

---

## 46. A fragment line is checked before the build, not only after it

**Context.** `./go kconfig` compares a kernel fragment against the
`.config` that was built from it. That `.config` exists only after
`do_compile`, so the earliest a line naming a symbol the kernel does not
have can be reported is at the end of a build. Project 15 found three such
lines in `router.cfg` that way, on the first build in fourteen projects
that compiled a kernel rather than reusing shared state.

**Decision.** A second check, `./go ksym`, against the unpacked kernel
source, which is on disk minutes into a build. It answers two questions per
line: is the symbol declared anywhere, and does it carry a prompt. A
promptless symbol cannot be set by a fragment at all, and such a line is
allowed only when it is marked `# consequence:` and the check prints what
actually selects it.

**Rejected.** Relying on `./go kconfig` alone, which does work at the price
of a build cycle per defect. Also rejected: treating a promptless symbol as
an error to be deleted, which would have removed a line that is still worth
checking.

**Why.** The promptless case is the one that does not announce itself. The
line does nothing, the value is usually right anyway because something else
selects it, and `./go kconfig` then prints `ok` for a request that was
never made. A check passing for the wrong reason is worse than a check
failing, because there is no later step that catches it. `rt.cfg` had
exactly one, `CONFIG_IRQ_FORCED_THREADING`, which `arch/arm64/Kconfig`
selects unconditionally.

**Consequence.** Two checks in sequence rather than one, answering
different questions: whether the kernel could receive the request, and
whether the answer came back. The cheap one runs first. The marker
convention adds a line of prose to a fragment and makes the fragment say
which of its lines are requests and which are predictions.

The checker was wrong twice before it was right, and both bugs were found
by its own test rather than by reading it: a `grep` that matched nothing
killed the script under `set -e` exactly in the branch that reports a
missing symbol, and single-quoted Kconfig prompts were not recognised,
which would have called eighty-one ordinary netfilter symbols promptless.
A checker whose failures are silent or false is worse than none, so its
test generates inputs the real fragments do not contain, and one of them is
real kernel text rather than an imitation.

---

## 47. A firmware file with no package gets one

**Context.** The bench's second uplink is a TP-Link TL-WN823N v2/v3, a
Realtek RTL8192EU driven by the in-tree `rtl8xxxu`, which asks for
`rtlwifi/rtl8192eu_nic.bin`. poky's `linux-firmware` recipe splits out
`rtl8188`, `rtl8192cu`, `rtl8192ce`, `rtl8192su`, `rtl8723`, `rtl8821` and
`rtl8822`, and nothing claims that file.

**Decision.** A four-line bbappend in `meta-bench` creating
`linux-firmware-rtl8192eu`, with `PACKAGES =+` so it claims the file before
the catch-all package does.

**Rejected.** Installing `linux-firmware` whole, which is what the absence
of a package nudges you towards.

**Why.** The catch-all is every firmware blob for every device Linux
supports, on a board with two radios and a modem. And the rule this
repository already follows is that every package in the image is justified
in one line; "we needed one file out of it" does not justify the rest.

**Consequence.** One more thing to carry across a Yocto release, and it is
the kind of thing that breaks loudly rather than silently: if upstream ever
splits the file out itself, the build complains about an empty package
instead of quietly shipping the wrong thing. `PACKAGES =+` rather than `+=`
is the whole trick, and it is commented in place, because appending would
produce an empty package and a rootfs full of firmware for hardware nobody
owns.

---

## 48. Interface names are assigned, not hoped for

**Context.** Adding a USB wireless adapter gives the router two radios. The
onboard `brcmfmac` is built in but waits for firmware from the rootfs; the
adapter's `rtl8xxxu` loads as soon as USB enumerates. Which of them
registers its netdev first is genuinely undecided, and `wlan0` is named by
the access point profile, the DHCP configuration and three nftables rules.

**Decision.** A udev rule renames the adapter to `wan0`, matched on its USB
vendor and product ids.

**Rejected.** Letting the kernel number them and referring to `wlan1`.

**Why.** `wan0` is a name the kernel never assigns, so whichever order the
two appear in, the onboard radio ends up on `wlan0`: if the adapter
registers first it is renamed away before the other asks, and if it
registers second it was never going to take `wlan0` anyway. The failure
this avoids is not a crash. It is an access point that comes up on the
wrong radio, at the wrong power, on the wrong antenna, and works well
enough that nobody looks.

The ids rather than the driver name, because a driver name is a property of
the kernel version and the ids are a property of the part in the drawer.
This is the same reasoning as `77-sim7600.rules`, which gives the modem's
AT and NMEA ports stable names for the same reason: allocation order is not
a promise.

**Consequence.** A second adapter needs its own line. That is better than a
rule broad enough to catch something unintended.

---

## 49. A measurement relationship is derived and simulated before it is believed

**Context.** Project 8's whole justification is a second instrument that
watches the pin from outside. Five documents in this repository stated what
the comparison between the two instruments would show: that the external
number carries the wake-up latency plus the cost of the GPIO write, so the
difference between them is that cost.

**Decision.** Derive the relationship, check the derivation against a
simulation with a known answer, and only then write it down. The external
instrument measures an interval, `P_i = T + (L_i+1 - L_i) + (S_i+1 - S_i)`,
so a constant write cost cancels and what survives is
`var(P) = 2 var(L) + 2 var(S)`. The reportable quantity is the excess over
a factor of sqrt(2), which is the variation in the output path.

**Rejected.** Shipping the intuitive claim. It had survived a design
document, a method document, a results schema, a README and a journal entry
without anyone doing the algebra.

**Why.** The lab would have produced numbers either way. A column computed
as `ext_max - int_max` is a difference between the maxima of two
differently-shaped distributions; it varies run to run for reasons that
have nothing to do with system calls, and it would have been reported as a
system call cost. Wrong numbers that look like measurements are the failure
this whole repository is arranged against, and here the check cost an hour
and a hundred lines of simulation.

The corrected claim is smaller and more useful. The wire does not say what
a GPIO write costs. It says whether that cost is steady, which is the
property a control loop depends on and the one no instrument inside the
kernel can report.

**Consequence.** `rt-compare` exists, `rt-run` calls it at the end of every
run, and the five documents now state the derived relationship and say they
were corrected rather than being quietly edited. Two further defects came
out of writing its test: a binned variance needs Sheppard's correction, or
2 us bins invent a third of a microsecond of finding; and a ratio below
sqrt(2) means correlated wake-ups rather than a cheap write, so the tool
refuses that interpretation instead of computing a number from it.

---

## 50. One place decides where a build happens

**Context.** Every build directory in this repository is set by
`scripts/common.sh`, which exports `KAS_WORK_DIR` and `KAS_BUILD_DIR`. kas
reads both from the environment and, when they are absent, falls back to
paths relative to the current directory.

**Decision.** Everything that invokes kas goes through `scripts/kas.sh`,
exposed as `./go shell [CONFIG]` and `./go bitbake CONFIG ARGS`.
`warn_stray_build_tree` in `common.sh`, called from there and from
`build.sh`, reports a `build/` directory inside the checkout.

**Rejected.** Documenting the two variables and expecting them to be
exported by hand, which is what a raw `kas shell` line in a bring-up
document amounts to.

**Why.** This failure does not look like a failure. A bare
`kas shell kas/bench-rt.yml -c ...` from a checkout builds correctly, in
`<checkout>/build`, with its own `downloads` and `sstate-cache`, re-fetching
what the shared caches already hold. It cost 7.7 GB on a disk with 35 GB
free, and then cost an hour, because the next command looked in the right
place and read the previous project's kernel. Ten minutes of that went into
suspecting a version pin that was correct.

**Consequence.** One more script, and a warning that fires on a directory
that is harmless in itself. The tell that would have caught it sooner is
worth knowing: BitBake printed `Loaded 4389 entries from dependency cache`
with no `Parsing recipes` bar, and a changed `local.conf` always forces a
full reparse.

---

## 51. The kernel configuration is proven before the kernel is compiled

**Context.** `./go kconfig` compares a fragment against a `.config`, and a
`.config` exists only after `do_compile`. So the earliest a wrong fragment
could be reported was at the end of an hour.

**Decision.** `bitbake -c kernel_configme virtual/kernel` first. It runs
fetch, checkout and patch and then merges the fragments into a real
`.config`, in minutes. `./go ksym` and `./go kconfig` both run against
that, before the build.

**Rejected.** `-c unpack`, which sounds like the task that produces a
kernel tree and is not: `do_unpack` puts the tree in `${WORKDIR}/git` and
its `cleandirs` empties `STAGING_KERNEL_DIR` on the way past, leaving
`kernel-source` present and empty. `do_kernel_checkout` fills it.

**Why.** Project 8's whole kernel side rests on one symbol surviving into
the `.config`, and the failure mode is silence. Moving that check ahead of
the compile turned an acceptance criterion from something a board would
eventually reveal into something proven in the first ten minutes.

**Consequence.** Four checks before the compile rather than one after it,
each answering a different question: the kernel's own Makefile for the
version, `ksym` for whether a line names a real symbol, `kconfig` for
whether the value arrived, and the build for whether any of it compiles.

`ksym` cannot do `kconfig`'s job, which is worth stating because it looks
as though it could. `CONFIG_PREEMPT_RT` is declared with a prompt in 6.6
and 6.12 alike; what 6.6 lacks on arm64 is `ARCH_SUPPORTS_RT`, a
dependency rather than a declaration. On a 6.6 tree `ksym` prints `ok` and
tells you nothing.

---

## 52. A vendor install target is the list of what a cross build must do itself

**Context.** Vendor build systems are written for a native build on the
target, where you compile a library, `make install` it, then compile the
tools against what was installed. A recipe installs nothing on the build
host, so everything that install step did has to be done by hand.

**Decision.** Read the `install` target as a checklist and replicate all of
it, not the parts that look relevant.

**Rejected.** Reading the compile rules, overriding `CC`, `CFLAGS` and
`LDFLAGS`, and assuming that is the whole of it.

**Why.** For `libdaqhats` that assumption cost three build cycles, one
finding each, and none was visible in the file that had been read:

| Cycle | Failure | Where it lived |
|---|---|---|
| 1 | `fatal error: daqhats/daqhats.h` | the `#include` lines of the C |
| 2 | `ld: cannot find -ldaqhats` | the unversioned symlink `make install` creates |
| 3 | `buildpaths` QA warning | what the compiler writes into the debug info |

The makefile's own three assumptions, a hardcoded `gcc`, `-I/usr/include`
and a 32-bit Broadcom userland path, were all found by reading and all
fixed at once. Everything after that was somewhere else.

**Consequence.** An honest statement about what a carefully written recipe
proves before it has run: nothing. It only fails faster. That is why the
project README listed the build as unproven while the recipe was being
written, rather than treating care as evidence.

---

## 53. A comparison differs in one variable, or it is not a comparison

**Context.** Project 8 measures a real-time kernel against a generic one.
`kas/bench-rt.yml` pins `PREFERRED_VERSION_linux-raspberrypi = "6.12.%"`,
because `PREEMPT_RT` needs `ARCH_SUPPORTS_RT` which arm64 gained in 6.12.
`kas/bench-rpi4.yml` pins nothing and gets the BSP default, 6.6.

**Decision.** A third configuration that pins 6.12 and leaves
`BENCH_RT_KERNEL` at 0, so the two rows differ in one symbol.

**Rejected.** Measuring what already builds and describing the rows as
"6.6 generic" and "6.12 RT".

**Why.** Six minor versions of scheduler, timer and driver work sit between
those kernels. The numbers would be real and the headline claim would be
uninterpretable: `PREEMPT_RT` is the loudest difference between them but
not the only one, and a reader asking how much of the improvement is the
preemption model would have no answer in the data.

**Consequence.** One more kas file, one more kernel build, and a correction
to two documents that had quietly become false. The project README said the
two images "differ in the preemption model and in nothing else that anyone
had to think about", written before the version pin existed. The bring-up
notes said `bench-rt-image` "carries the generic BSP kernel", which it
never did.

Both are the shape this repository keeps producing: a claim written when it
was true, left standing after the thing it described changed. No test holds
a sentence like that. What caught it was reading the two kas files side by
side while deciding what to flash.

---

## 54. The linter covers the one thing the authoring machine cannot see

**Context.** The repository is edited and committed on a Windows laptop
with no shellcheck, and CI runs `shellcheck -s sh -e SC1090,SC1091` at
default severity, where an `info` fails the build exactly as an error does.

**Decision.** One narrow rule in `scripts/lint.py`: an `export` or
`readonly` whose value carries an unquoted expansion.

**Rejected.** Reimplementing shellcheck in Python. Also rejected: relying
on the operator to run shellcheck before pushing, which was asked for twice
and happened neither time, because a build is always more interesting.

**Why.** An assignment is not subject to word splitting; an argument to a
command is. That is the whole of SC2086 and the only part of it this
repository keeps getting wrong: once in the `rt-*` tests, fixed by somebody
else, and again a day later in two new files, four instances, turning CI
red twice.

**Consequence.** One rule, proven by reintroducing the defect in both file
shapes, `*.sh` and a shebang-only file, because the discovery has to match
CI's 37 files rather than a glob. Everything else shellcheck finds is still
invisible until CI runs; the real answer is shellcheck on that machine, and
that is not a decision a lint rule can make.

---

## 55. An observation and an inference are written differently

**Context.** Told that a DAQ HAT fits a Raspberry Pi 3, a journal entry was
written saying it "did not seat on a Pi 4", with a mechanism about the
Pi 4 having moved its Ethernet and USB stacks. Only the first half was
observed. The mechanism was invented to explain it, written in the same
voice, and committed. It was wrong, and it is in the pushed history.

**Decision.** Where something was inferred rather than seen, the sentence
says so, at the point of the claim rather than in a later correction. When
an unverified fact would change a build, a document or a claim, ask before
acting on it.

**Rejected.** Replacing a wrong mechanism with a more plausible one. It
reads better and is worth nothing.

**Why.** The repository has recorded four instances of one family now, and
the differences matter:

| Fault | Shape |
|---|---|
| The instruments differ by the system call cost | a claim nobody had done the algebra for |
| The fragment did not reach the kernel | a tool reporting faithfully about the wrong input |
| The two images differ only in the preemption model | true when written, false after a later change |
| The HAT does not fit a Pi 4 | an inference recorded as an observation |

The first three decayed or misfired. The fourth had no decay and no wrong
input, only a missing question, and the answer would have cost a sentence
against a machine change, three figures, four documents and a commit.

**Consequence.** Journal entries get longer in one specific way: "measured"
and "inferred" are separate words, and a correction says what was actually
seen rather than substituting a better guess. The acceptance tables already
made this distinction between what a file says and what a board did; this
extends it to the prose.

---

## 56. The board is what the hardware allows, and thresholds do not move with it

**Context.** Project 8 was scoped for a Raspberry Pi 4 and its acceptance
criteria name absolute figures: a 99.9th percentile below 50 us and a
maximum below 150 us under load. Which board the DAQ HAT physically seats
on decided where it would run.

**Decision.** The machine follows the hardware. The thresholds do not. They
stay as written and are marked as the board they were written for, and a
row records which board produced it.

**Rejected.** Adjusting the numbers to what the board in hand is likely to
manage.

**Why.** A threshold moved to fit the hardware is a prediction wearing a
criterion's clothes, and it will pass. A Cortex-A53 with Ethernet and USB
on one shared controller is a harder real-time target than a Cortex-A72; if
it misses a Pi 4 threshold that is a measurement worth reporting, not a
failure worth hiding by moving the line.

**Consequence.** The argument rests on the relative criterion instead, and
it is stronger for it: the generic kernel several times worse than the
real-time one, under the same load, on the same hardware, with the same
userspace. That is a property of the preemption model rather than of the
silicon, it holds on either board, and it is why the control kernel from
decision 53 matters more than any absolute number in the table.

---

## 57. Captured evidence is annotated, never edited

**Decision.** When a file in `docs/evidence/` is contradicted by something
learned later, the captured text stays byte for byte as captured and a
dated note is appended saying what changed and what a rerun is expected to
show. The acceptance criterion it supported goes back to provisional until
that rerun happens.

**Why.** `projects/08-preempt-rt/docs/evidence/kconfig-check.txt` is
verbatim `./go kconfig -f rt` output and its header says
`MACHINE raspberrypi4-64`, because that is what the machine was at 06:56 on
16 September 2026. The board was later confirmed to be a Pi 3B, the machine
changed, and that header became wrong.

Editing it would have taken one substitution and been undetectable. It
would also have converted the only file in the project whose value is that
nobody wrote it into a file somebody wrote. Evidence that gets tidied to
match the current belief is no longer capable of contradicting the current
belief, which is the entire job.

The note says what is expected to change on the rerun (the paths, which
carry the machine name) and what is not (the kernel version, pinned in the
kas file, and `ARCH_SUPPORTS_RT`, selected by the architecture). Writing
the prediction down before the rerun is what makes the rerun worth doing.

**Cost.** Criterion 7 is unproven again until the kernel is reconfigured
for `raspberrypi3-64`. That is the honest state and it is cheap to fix:
`kernel_configme` is minutes.

## 58. Absolute thresholds do not move to meet the hardware

**Decision.** The Project 8 acceptance thresholds, a 99.9th percentile
below 50 us and a maximum below 150 us, stay as written after the board
changed from a Pi 4 to a slower Pi 3B. They are labelled with the board
they were written for, and each results row records the board it was taken
on.

**Why.** A threshold chosen after seeing the hardware is not a threshold,
it is a description. The value of writing one down in advance is precisely
that the hardware can miss it, and a miss on a 1.2 GHz core with its
Ethernet behind a shared USB hub is a result worth reporting rather than an
embarrassment worth hiding.

**The general form.** Prefer a relative criterion where the project allows
one. "The generic kernel is several times worse than the real-time kernel,
under the same load, on the same board, with the same userspace" is a
property of the preemption model. It survives a change of board, a change
of governor and a change of silicon vendor, and it is usually the claim
that was actually wanted. The absolute number is the one that has to be
qualified; keep both, and be clear about which carries the argument.

## 59. A picker is a function, not a line each script writes again

**Decision.** Choosing the newest of several build outputs is
`newest_path` in `scripts/common.sh`, with its own test suite. Five call
sites use it and no script does the selection itself.

**Why.** Every script that had to choose between build outputs ended in
`sort | tail -1`, which orders paths as text. Text order is neither version
order nor time order:

```
6.12.93          sorts before 6.6.63            because "1" < "6"
raspberrypi3-64  sorts before raspberrypi4-64   because "3" < "4"
```

The first was found, fixed, tested and written up in
`check-kernel-config.sh`. The identical line was still in
`check-kernel-symbols.sh` nine journal entries later, where a machine
change gave the build host two kernel trees and it read the abandoned one.
Grepping for the shape then found three more, including `flash.sh`, which
chooses the image that gets written to a card. On a host that has built for
two machines, that one would have written a Pi 4 image to a Pi 3 card: no
warning, no boot, and a symptom that reads as dead hardware.

A fix applied where the bug was found is half a fix. Making it a function
is the half that does not depend on anybody remembering.

**The helper names what it did not choose.** Both kernel checks spent a
whole command reporting on a file they had not read, and printed correct
answers while doing it, because the two trees happened to be the same
kernel version. A check that is right for the wrong reason teaches you to
trust it. So the losers are printed, on stderr, above the confirmation
prompt in the case of `flash.sh`, which is the last gate before a card is
erased.

It stays quiet when there is one candidate. A warning that fires when there
is no ambiguity trains the reader to skip warnings, and then the one that
mattered is skipped too.

**What the helper deliberately does not do.** Report emptiness. The
sentence belongs to the caller: `flash.sh` says to run `build.sh`, the
kernel check says to run `kernel_configme`, and a helper that guesses
between them is wrong in both.

**Cost.** One shared function, eleven assertions, and five call sites that
now read as what they mean rather than as how they do it.

## 60. The instrument may be a distribution; the subject is ours

**Context.** Project 4's product is a lab rather than a device. Its server
needs dnsmasq, an NFS server, ser2net and pytest; its device under test
boots an image this repository builds.

**Decision.** The server runs Raspberry Pi OS Lite, configured by four files
that live here and an installer that copies them. Only the DUT image is
built by this repository.

**Rejected.** A `bench-lab-image` carrying the whole lab, which is more in
the spirit of every other project here.

**Why.** The server is the instrument, not the product. Four configuration
files and ten minutes of `apt` produce something that works; the same lab as
a Yocto image is a week of `PACKAGECONFIG` for a result nobody measures. The
thing worth being reproducible is the image under test, and that is exactly
the half this repository does build.

**Consequence.** A server rebuilt from a fresh card is `install.sh` plus two
manual steps the script names rather than guesses at. The lab itself is not
reproducible from source, which is recorded as a stretch goal and would
matter the day somebody else has to stand one up.

---

## 61. A console gets framing, because it has none

**Context.** A serial console is a byte stream. There is no end of message,
and a shell prompt is only some characters that usually turn up last.

**Decision.** Every command carries a unique end marker and returns its exit
status attached to it: `cmd; echo __END_<pid>_<n>__ $?`, and the reader
waits for that marker followed by digits.

**Rejected.** Matching on the prompt, which every expect script starts with.

**Why.** Prompt matching works until a command prints something that looks
like a prompt, and then it truncates output silently rather than failing.
The digits matter too: the console echoes the command before running it, so
the marker appears twice, and the echoed one is followed by a literal `$?`
rather than a number. Without that detail every command appears to finish
instantly with no output.

**Consequence.** Two things that look like details are load-bearing, and
both are commented where they are rather than explained once here. The
marker cannot be a timestamp: `time.monotonic_ns()` has about 15 ms of
resolution on some hosts, so two quick commands collide and the second
returns the first one's output. And the echo may only be stripped when it
is actually found, because a console can be configured not to echo and then
stripping unconditionally eats the first line of real output.

---

## 62. The kernel owns the interface the root filesystem is on

**Context.** A netbooted board has its network configured by the kernel,
before userspace, because the root filesystem is mounted over it. Then
systemd-networkd starts and, by default, manages every interface it
recognises.

**Decision.** `KeepConfiguration=yes` on that interface, shipped as part of
the DUT image rather than left to the operator.

**Rejected.** Leaving the default, which works often enough to look fine.

**Why.** Taking the interface over means dropping the address and acquiring
a new one, and for the few hundred milliseconds in between the NFS server is
unreachable. The process reading from the root filesystem at that moment is
systemd-networkd itself. The symptom is a board that reaches userspace,
prints a few lines and stops, with no shell to ask, and nothing about it
points at a network configuration.

**Consequence.** One more file in the image, and a class of intermittent
failure that would have been blamed on the cable. It is the same shape as
Decision 48 and as Project 15's ownership table: one resource, two managers,
and a failure that looks like something else.

---

Previous: [10. Generalising](10-generalising.md) | Index: [Walkthrough](README.md)

## 63. Lint runs after `git add`, and says what it could not see

**Decision.** The pre-commit sequence is `git add -A`, then
`python scripts/lint.py`, then commit. Not the other way round. And
`lint.py` now lists untracked files that carry a shebang, as a note.

**Why.** `check_exec_bits` reads `git ls-files --stage`, because Git on
Windows defaults to `core.filemode=false` and a `chmod` there never reaches
the commit. An untracked file has no entry in that listing, so the check
cannot see it. A brand new script is therefore the one case it misses, and
it is the only case where the mode is ever wrong: every file already in the
repository was fixed long ago.

`tests/common-test.sh` was written, `chmod +x`ed on Windows where that
records nothing, linted while untracked, reported clean, staged, committed,
and failed CI on the mode. Four steps, each reporting success, and the one
that should have caught it had been handed nothing to check.

**The general form, and it came up three times in one session.** A check
that selects its own inputs reports on what it selected, and says "clean"
either way:

| Check | Said | Had actually looked at |
|---|---|---|
| `./go kconfig` | fragment missing | a `.config` from another kernel version |
| `./go ksym` | 31 symbols, all real | the abandoned machine's tree |
| `lint.py` | clean | every file except the new one |

None of the three said what it had looked at. So both pickers now name the
inputs they rejected, and the linter names the files it could not check.
The rule is: **a tool that chooses its own inputs must report the choice**,
because the alternative is a green result that answers a narrower question
than the reader thinks it does.

**A note, not a failure.** An untracked file is not yet a claim about
anything, and a working tree legitimately holds scratch scripts. Making it
an error would turn ordinary work into a lint failure and teach people to
skip the linter, which costs more than the bug.

**Cost.** One function, and an ordering that has to be remembered once.

---

## 64. A built image is archived with its provenance, or not archived at all

**Context.** A build is one to three hours and the build tree is disposable
on purpose: `./go clean` deletes it, and so does any reclaim of disk. The
image in it is the only artefact that cannot be regenerated cheaply, and
keeping a copy is the difference between reflashing a board in a minute and
rebuilding for an afternoon.

**Decision.** `./go archive` copies the image, its `.bmap` and its
`.manifest` into a store outside the repository, together with a
`PROVENANCE.txt` and the output of `kas dump --lock`. The record carries the
date, the configuration, the machine, the commit, a `sha256` per file, the
command that flashes it and the command that rebuilds it, and it states
plainly when the working tree was dirty.

**Rejected.** Three alternatives. Copying the `.wic.bz2` somewhere by hand,
which is what everyone does and which produces a directory of files nobody
can later identify. Committing images to the repository, which git is the
wrong tool for and which `.gitignore` already forbids. And archiving the
image alone without the record, on the grounds that the filename says
enough.

**Why.** The filename says the image name and the machine. It does not say
the commit, the layer revisions, or whether the tree was clean, and those
are exactly the facts needed to decide whether a stored image is the one you
want on the card in front of you. This repository refuses to build without
pinned layers for the same reason; an archived artefact with no record of
its inputs is that same defect one stage later. Saving the lock file beside
it means the image can be rebuilt rather than only re-flashed, which is what
turns a stored card into a supportable version.

The machine check earns its place separately. "Newest wins" is correct
immediately after a build and wrong the moment you archive under a
configuration you did not just build, where it would file a Pi 4 image under
`bench-rpi3`. That card does not warn and does not boot, and the symptom is
a dark board that reads as dead hardware. So the machine in the kas file has
to agree with the machine in the deploy path, following `include:` because
`bench-dev.yml` sets only a target and inherits the rest.

**Consequence.** About 50 to 80 MB per kept image, and one command to
remember after a build that mattered. `./go flash` takes an optional image
path so a kept image can be written back, and prints that image's machine
and commit above the confirmation prompt, which is the last moment before
the card is erased and the only moment those two facts matter.

**What it found immediately.** `tests/archive-test.sh` failed on its first
run: the `.bmap` and `.manifest` were being derived from whichever of an
artefact's two names the search returned, and the short symlink's companions
are not guaranteed to exist. The fixture was shaped like a real deploy tree
rather than like the happy path, which is the only reason it was caught
before a real archive quietly lost its block map.

## 65. A pull is an input to the running build, so it is refused

**Decision.** `./go pull` refuses while a `bitbake` process exists. Plain
`git pull` during a build is treated as an error rather than a habit to
avoid.

**Why.** kas registers this checkout as a layer in place. BitBake reads
recipes from it for the whole of a build and reparses as it goes, comparing
each task's basehash against the one it started with. A pull is therefore
not an operation on a source tree beside a build; it is an edit to the
running build's inputs.

It cost a build here. Two inert lines added to
`linux-raspberrypi_%.bbappend` for an unrelated project moved five kernel
basehashes and produced 327 errors at 6201 of 6258 tasks. Inert, because
the switch guarding them was off and the expression expanded to nothing:
**a basehash covers the expression and its dependencies, not the value it
evaluated to.**

**Why a guard rather than a line in the documentation.** The documentation
would be written by somebody who already knew and read by somebody who
already knew. The failure was not ignorance of the rule. It was attention
elsewhere during a three hour unattended process. That is the situation a
guard exists for and a paragraph does not.

**Why it prints the commit before pulling.** Because the cheap recovery
needs it. Restoring only the changed recipe file to the pre-pull commit
restores the basehashes and BitBake resumes from its stamps instead of
recompiling a kernel, and that commit appears in the build's opening lines
and nowhere else once the scrollback is gone. The expensive recovery, which
is to accept the new metadata and rebuild, is always available and costs
about two hours.

**Why it says when it could not check.** `pgrep` is absent on Git Bash,
where the test is simply false and everything is waved through. No build
runs on that host, so nothing is at risk, but a check reporting success
without having looked is the failure this repository found three times in
one day. Two lines to say which.

**Cost.** One script, one verb, and a test suite. The alternative cost was
measured: about two hours, or a delicate restore that has to be explained
each time.

## 66. An archive is refused unless the board and the system both match

**Decision.** `scripts/archive.sh` checks the image's machine *and* its
target against the kas configuration, and refuses rather than filing
something that does not match.

**Why both.** `deploy/images` holds one directory per machine and every
image ever built for that machine inside it. The machine check alone
catches a Pi 4 image filed under a Pi 3 configuration, which is the loud
failure: the card does not boot and the symptom is immediate.

It does not catch a `bench-rt-image` filed under `bench-router`, which is
the quiet one. Same machine, so the check passes. That card flashes, boots,
runs, and is wrong only in its label, which means it is discovered by
whoever trusted the label rather than by the person who made the mistake.

**Why `<target>-<machine>` and not the target alone.** `bench-image` is a
prefix of `bench-image-dev`. A prefix match would file a debugging image
under the production configuration, which is the same class of error one
step smaller.

**What the check deliberately cannot do.** `bench-rt` and
`bench-rt-generic` resolve to the same target, because the control differs
from the variable in one kernel symbol rather than in the image. Their
output files are named identically and the second build overwrites the
first in `deploy/images`. No check can separate them; what separates them
is the store, one directory per configuration, and the operator naming the
file with `BENCH_IMAGE` when both exist. Saying so in the code is better
than a check that appears to handle it.

**Cost.** A refusal the operator answers with `BENCH_IMAGE=<path>`, which
is one line and lists its options.

## 67. A stray is gitignored and warned about, not one or the other

**Decision.** The layer clones kas leaves in the checkout are named in
`.gitignore`, and `warn_stray_build_tree` names them and prints the `rm`
for each.

**Why both halves.** Ignoring alone hides a real problem: 469 MB of unread
duplicates that every build silently steps around, announcing it each time
as "Falling back to file-relative addressing" in a warning nobody reads.

Warning alone leaves them making `git status` dirty, which is not cosmetic.
`archive.sh` stamps each stored image with the commit and appends `-dirty`
when the tree is not clean, so every image archived on that host claimed to
have come from a modified tree. It had not. **A provenance record that is
wrong about the commit is worse than none, because it is believed.**

**Why they were missed for weeks.** `.gitignore` already covered `build/`,
`tmp/`, `sstate-cache/` and `downloads/` under a comment reading "these are
the strays". The layers were not added because they are named after real
things: `poky` and `meta-raspberrypi` look like content rather than
accident.

**Why not just fix the kas invocation instead.** That was already done:
`scripts/kas.sh` exports `KAS_WORK_DIR` and `KAS_BUILD_DIR`. The clones
predate it. A fix applied forward does not clean up behind itself, which is
the same lesson as Decision 59 in a different costume.

**Cost.** Three lines of ignore, fifteen of warning.

## 68. A configuration answers to both of its names

**Decision.** `resolve_kas_config` accepts `rt` and `bench-rt` alike, and
lists the configurations when neither exists.

**Why.** Every build verb is the short name: `./go rt`, `./go ble`,
`./go router`. After months of that, `./go archive rt` is what a hand
types, and it answered `no such configuration: kas/rt.yml`, which is true and
naming a file nobody had in mind.

**Why not make the verbs long instead.** `./go bench-rt` reads worse and
would break every documented command in four project READMEs. The
inconsistency was in the scripts that take a configuration as data, not in
the verbs.

**Why an exact match wins.** A file that exists is never a guess. Only when
the name as given does not resolve is the prefix tried.

**Why it lists the options.** A configuration name is a closed set of files
in one directory. There is no reason to send somebody to go and look.

**Cost.** One function in `common.sh`, three call sites, seven assertions.

## 69. Build outputs leave the VHDX before the build tree is deleted

**Decision.** Everything worth keeping is archived with `./go archive`, and
then copied out of WSL onto the host filesystem, before `./go clean` runs.

**Why archive rather than copy the image alone.** An image on its own is a
mystery card. The store keeps the `.bmap`, without which a flash writes the
whole card instead of its used blocks; the `.manifest`; a `.lock.yml` with
the layer revisions that make it rebuildable rather than only reflashable;
and a `PROVENANCE.txt` naming the board and the commit. Those are the facts
that decide whether a stored image is the one you want on the card in front
of you.

**Why out of the VHDX as well.** The archive store survives `./go clean`,
because it lives beside the caches rather than inside the build tree. It
does not survive the VHDX, and the VHDX is a single file whose sparse
conversion WSL currently refuses on grounds of data corruption. One file,
three images, two projects.

**Why not a disk image of the card instead.** That was asked directly, and
the archive wins on every axis that matters: 78 MB against the size of the
card, a provenance record against a mystery blob, layer revisions against
none, and secrets held separately and rotatable rather than baked in.

The one thing a card image captures that an archive does not is hand edits
made on the running board, and this bench is built so that there are none.
The image carries the capability, the card carries the identity, in two
files on a FAT partition that any laptop can read. That design decision,
made for secrecy, turns out to be what makes a card disposable.

**Cost.** 233 MB on the host, and one command before any cleanup.

## 70. A new check is verified by breaking the thing it checks

**Decision.** A newly written check is proved by reintroducing the defect,
watching it fire, restoring, and watching it go quiet. Both directions,
before it is trusted.

**Why.** A check that does not fire on the bug it was written for is
decoration, and there is no way to tell decoration from vigilance by
reading it. The SC2120 rule took three attempts and the first two were
silent for different reasons: once because it was defined and never added
to `main()`, once because its own regex matched the word `run` inside a
comment and counted prose as a call site.

Both would have been committed as working. Both were caught in seconds by
breaking the file on purpose.

**Why both directions and not only the failing one.** A rule that fires is
half of what was wanted. A rule that fires on everything is worse than
none, because it gets silenced rather than fixed, and this repository has
already had to narrow one rule for exactly that reason.

**Why this is not paranoia.** It caught three defects in a single day: a
`find` that read the wrong kernel tree, a test asserting the absence of one
error message rather than the presence of a result, and the rule itself,
twice.

**Cost.** Two commands per check.

## 71. One function decides what gets signed, and both ends import it

**Decision.** The bytes a signature covers are produced by one function,
`canonical()`, which ships to the signer on the board and to the verifier
on the host. Neither end serialises a record any other way.

**Why not a documented format.** Because that is what was tried, and the
two ends were written from it four paragraphs apart:
`json.dumps(rec, sort_keys=True)` on one side and the same call with
`separators=(",", ":")` on the other. Those differ by two spaces per
field. Every record would have verified as BAD, with the data intact, the
key correct and the HMAC correct, and nothing in any output pointing at
the cause. The obvious reading of "every record is BAD" is tampering.

**Why the rules are written next to the code rather than in a spec.**
Five of them, each with the failure it prevents: drop the `mac` field, or
the two ends sign different objects; sort the keys, or insertion order
decides; no spaces, as above; escape non-ASCII, or an encoding choice is
made twice; refuse NaN, because Python writes tokens that are not JSON
and a non-Python verifier could never agree.

**Cost.** One import that crosses a machine boundary, and a rule that
floats are still a hazard for a verifier written in another language,
which the docstring says rather than leaving to be discovered.

## 72. A number restated in five files gets a test, not a comment

**Decision.** Where one value has to appear in several languages, a test
parses the authoritative file and compares. Project 20's TA UUID appears
as eleven hex integers in a C macro, as a string beside it, as a
makefile's `BINARY`, as a recipe variable and as a Python constant, and
`tests/keystore-header-test.sh` reassembles it from the macro and checks
all five.

**Why not a comment saying "keep these in step".** The failure is silent
and ambiguous. A TA built with one UUID and a client asking for another
gives `ITEM_NOT_FOUND`, which is also what a missing TA file gives, and
also what a TA whose signature is rejected gives. Three causes, one
number, and only one of them visible from a shell.

**Why the macro form specifically.** It is the one nobody proof-reads.
The string form is read at a glance; eleven separate integers are not.

**Cost.** A parser in a test, and the rule that the header is
authoritative, so a change starts there.

## 73. The secure world is installed, not built, and the reason is written down

**Decision.** `bitbake` builds the normal world, the kernel and the
trusted application. Trusted Firmware-A, OP-TEE OS and U-Boot come from
the OP-TEE build repository, and `./go armstub` puts the resulting
`armstub8.bin` onto a card the image is already on.

**Why not a recipe.** Five things would have to be settled first, and
they are listed in that project's bring-up notes rather than left as an
absence: TF-A for this board emits a FIP rather than a kernel, BL33 is
U-Boot so a second boot loader enters the picture, `uboot.env` is a
generated artefact, `IMAGE_BOOT_FILES` cannot carry a file the build does
not produce, and meta-raspberrypi already ships a different `armstub8.bin`.
None of that can be written blind: a recipe that looks right and has never
been booted is worse than a manual step that says it is one.

**Why the version pin matters more than the recipe.** The trusted
application is compiled against the dev kit one build produces and
dispatched by the OP-TEE the other build carries. Different versions mean
headers from one and a dispatcher from the other, and nothing in either
build says so. The kas file pins both, and the check that settles it runs
on the board, because the running OP-TEE is the only authority on which
OP-TEE is running.

**Cost.** One manual step in the bring-up, and a list of five unknowns
that the next person starts from rather than rediscovers.

## 74. The kernel's own version string is the authority on its preemption model

**Decision.** `rt-run` decides `realtime=yes` from `uname -v` containing
`PREEMPT_RT`. Where `/sys/kernel/realtime` also exists it must agree, and a
disagreement refuses the run rather than choosing a winner.

**Why the change.** `/sys/kernel/realtime` came from the out-of-tree RT
patch series. `PREEMPT_RT` was merged into mainline for 6.12 and the sysfs
file did not come with it, so on the kernel this project pinned itself to
in order to get `PREEMPT_RT`, the file is absent on both kernels.

The old code read absent as not-real-time. On the real-time board every row
would have been written `realtime=no`, the run would have been labelled
`generic`, and the table would have held two identically labelled arms of a
one-variable experiment. Nothing in it would have looked wrong.

**Why `uname -v` and not `/proc/config.gz`.** The config is the better
evidence and it is what the acceptance criterion now quotes. But it needs
`CONFIG_IKCONFIG_PROC`, which is a choice this project happens to have
made and another kernel need not. `uname -v` is on every kernel, needs no
filesystem, and cannot be missing. For a per-row label that must never be
silently wrong, unconditional availability beats depth.

**Why refuse on disagreement rather than prefer one.** Because there is no
correct answer to prefer. A machine whose version string and whose sysfs
file contradict each other is one where something is not what it claims,
and a row labelled from either source would be a guess wearing a fact's
clothes. Refusing costs one run. A mislabelled table costs every run in it,
and is not detectable afterwards.

**The general rule this is an instance of.** *Absent is not a value.* When
a check reads a fact from a file, ask what it does when the file is not
there. If it cannot distinguish "absent" from a real answer, it needs a
second source that cannot be absent, or it needs to refuse.

**Cost.** Four assertions, and one existing test which turned out to
describe a kernel that cannot exist.

## 75. A driver that is configured is not a driver that is installed

**Decision.** An image that names a userspace bus interface must name the
controller driver beside it, on the adjacent line.
`kernel-module-spidev` and `kernel-module-spi-bcm2835` travel together.

**Why.** The board found the HAT, read its name and address out of the ID
EEPROM, and then could not open it. `/dev/spidev0.0` did not exist and
`/sys/class/spi_master/` was empty, while `dtparam=spi=on` was in
config.txt, the device tree node read `status = okay`, and the running
kernel's own config had `CONFIG_SPI=y` and `CONFIG_SPI_BCM2835=m`.

The driver was configured, compiled and deployed. Yocto packages one module
per `.ko` and installs only what an image names, and the image named
`spidev` alone. A `spidev` with no master registers nothing.

**Why no check caught it, which is the part worth keeping.** `./go ksym`
and `./go kconfig` both passed on all 31 fragment options, twice, on two
machines. Both answer *did what I asked for arrive*. Neither can answer
*did I ask for what I needed*. The fragment names the interface and leaves
the controller to the BSP defconfig, which did supply it, as a module,
which moves the problem from the kernel configuration to the image package
list where no kernel check looks.

**Why `check_image_packages` did not catch it either.** That rule exists
because Project 1 lost a round to a wireless driver without its module
package. It scans recipe comments for `kernel-module-*` names and requires
them in `IMAGE_INSTALL`. It could not see this one because nobody had
written the name down anywhere to be scanned. **A rule that checks what you
mentioned is installed cannot catch what you never mentioned.**

**Cost.** One line, and a rootfs rebuild rather than a kernel compile,
because the module was already built.

## 76. Unused hardware comes off the bench before anything is measured

**Decision.** Anything attached to the board that the experiment does not
need is physically removed before the first run: the DSI display, the USB
wireless dongle, anything else that enumerates.

**Why.** This project measures how late a real-time task is. Every attached
device is a source of interrupts and DMA on the board being timed, and none
of it is in the experiment. It lands in the numbers with nothing in the
data to separate it from the preemption model, which is the one thing the
project exists to isolate.

The dongle made the case better than the screen did: it had bound to **no
driver at all**, because the image ships no Realtek module. It was raising
USB interrupts and providing not one interface. Unplugging it is the
cheapest isolation available, and it happens before `isolcpus` and IRQ
affinity rather than instead of them.

**Why not add the missing driver so it works instead.** Because this image
wants fewer interrupt sources, not more. Project 15 names
`kernel-module-rtl8xxxu` and `linux-firmware-rtl8192eu` because a router
needs a second radio. The same absent driver is a defect in one image and a
correct decision in another, which is the argument for per-image package
lists rather than one shared one.

**Cost.** Nothing, and it must be recorded: a results table has to say what
was attached, because "nothing else was running" is a claim about the
hardware as much as about the software.

## 77. A reconstructed number is labelled, or it is not published

**Decision.** `iio-rate` carries a `ts_source` column beside every
timestamp statistic, and prints a warning under the figure whenever the
source is `driver-interpolated`. The FIFO and hrtimer timestamp spreads are
never put in the same column of a results table.

**Why.** The three paths this project compares do not all produce the same
kind of timestamp. On the hrtimer path the IIO core stamps each scan as it
pushes it, so the jitter is real kernel latency. On the hardware FIFO path
the sensor stamps nothing: the driver takes one interrupt at the watermark,
drains N samples in a burst, and **assigns** timestamps by interpolating
backwards using the configured output data rate.

So FIFO timestamp intervals are close to exactly `1 / ODR` by construction,
and their standard deviation measures the driver's arithmetic and the
stability of the sensor's oscillator. Printed beside the hrtimer figure it
wins by a wide margin and means nothing, for the same reason a clock that
reports the time it was set to always agrees with itself.

**Rejected: print it and let the reader judge.** That is not neutrality. It
would be the most quotable number in the project and the least meaningful,
and an unlabelled figure in a portfolio is a claim whoever reads it will
repeat.

**Rejected: omit it.** The spread is worth knowing. A driver whose
reconstruction wanders says something about the sensor's clock. It is
evidence about a different question, and the column name is what keeps the
two questions apart.

**What is comparable**, and what the results table actually uses: interrupt
rate and reader CPU across all three paths, timestamp regularity *within*
the hrtimer path against the rate it was asked for, and samples delivered
against samples configured, which catches drops and is comparable
everywhere because a sample either arrived or did not.

**Consequence.** One more column, and a warning printed every time rather
than a note in a document that the person reading a CSV will not have open.
This is Project 8's error caught before the measurement rather than after:
that project asserted in five documents that the gap between its two
instruments was the cost of a GPIO write, until the algebra showed a
constant cost cancels.

## 78. An inventory says how something failed, not that it did

**Decision.** `iio-probe` reports five verdicts per sensor: `working`,
`not-bound`, `no-driver-in-image`, `bound-no-device` and `not-on-bus`. A
part with no mainline driver is `unsupported` and gets a row like any
other.

**Why.** From `ls /sys/bus/iio/devices` all five look identical, and they
have entirely different fixes:

| Verdict | Where the fix is |
|---|---|
| `not-bound` | the device tree overlay |
| `no-driver-in-image` | the image's `kernel-module-*` lines |
| `bound-no-device` | `dmesg`, a probe that failed |
| `not-on-bus` | the wiring or the bus speed |

A tool that answers "no sensor" sends the next hour to the wrong layer.
Project 8 spent a bring-up session on exactly that, from a HAT that
announced its own name out of its ID EEPROM and then could not be opened:
the failure table in its bring-up notes named SPI rather than the HAT, and
that one sentence was the difference between an hour and a morning.

**Rejected: report only what works.** The specification asks for an honest
inventory of which sensors work with which driver, and the interesting rows
are the failures. An inventory listing four working parts out of six, with
the other two absent, is not shorter: it is wrong by omission.

**Consequence.** The parts list is in the program rather than discovered,
because the useful output is the difference between what should be there
and what is. That list has to be maintained when the shield changes, which
is the cost, and it is what makes a missing part visible instead of simply
absent.

## 79. A scan layout is computed, never remembered

**Decision.** `iio-decode` reads `scan_elements/*_type` and `*_index` and
computes every offset. `iio-stream.c` uses `iio_buffer_first()` and
`iio_buffer_step()`. Neither contains a byte offset.

**Why.** The obvious IIO buffer loop indexes with literal offsets: 0, 2, 4
for three 16-bit channels and 8 for the timestamp. Those are correct for
exactly one configuration. Disable a channel and everything after it moves.
Read the magnetometer instead and the channel names change. Meet a driver
reporting 12 bits inside a 16-bit word and the values need a shift and sign
extension from bit 11 rather than 15.

None of that raises an error. The numbers stay plausible, which is the
failure mode this whole project is about.

**The rule the kernel uses**, and the reason it cannot be guessed: channels
appear in index order, each is aligned to its own storage size, and the
scan is padded to the largest alignment. A 64-bit timestamp after three
16-bit channels sits at offset 8 and not 6, and the scan is 16 bytes and
not 14. A reader that added sizes would be two bytes early on every
timestamp and would produce a number nobody would question.

**Rejected: hard-code and document.** The specification's own example does
this and says a robust program would not. A comment does not survive being
copied into the next program, and this layout is copied constantly.

**Consequence.** Thirty lines instead of three, and a test suite that pins
the alignment, the disabled-channel case, the shifted 12-bit case, big
endian, unsigned, and the rule that a timestamp is never scaled however
plausibly a `scale` attribute turns up beside it.

## 80. A filter is named after what it is, or renamed

**Decision.** `ahrs.py` implements Madgwick's gradient-descent update for
the accelerometer and gyroscope, and takes yaw from a tilt-compensated
magnetic heading rather than from his MARG variant. Its own header says so
in the first paragraph.

**Why not the filter the specification names.** The MARG variant folds the
magnetometer into the same gradient through a six-row Jacobian, and that
Jacobian is where published implementations disagree with one another: in
signs, and in the handedness of the reference frame.

A wrong sign there does not produce an obviously broken result. It produces
an orientation that tracks movement smoothly, responds correctly to being
turned, and is mirrored. Diffed against a recording from the same broken
filter it agrees forever.

The bench method already says not to copy a filter's helpers from a
repository without checking them against the paper. The honest consequence
of that rule, on a bench with no reference attitude source, is to implement
the part that can be derived and checked and to be explicit about the part
that was replaced.

**Rejected: implement MARG anyway and validate on hardware.** The
validation available here is "lay it flat and turn it ninety degrees",
which a mirrored filter passes on two of three axes. The bench cannot tell
the two apart, so building something the bench cannot check is building
something nobody will ever know is wrong.

**Rejected: call it Madgwick anyway.** Half of it is. A filter that
silently differs from the one it is named after is worse than one that says
so, because the name is what a reader uses to decide whether to trust it.

**How the remaining half is checked.** Against physics, never against
another program: gravity on an axis means ninety degrees about another, and
a gyroscope turning at a known rate for a known time has turned by their
product. Two independent paths to the same angle is what makes a sign
convention visible. That is not theoretical: the first version of those
checks had inverted expectations, and what exposed it was the gyroscope
check passing while the accelerometer checks failed.

**Consequence.** Yaw is noisier than a MARG filter would give, because it
is measured rather than smoothed by the gyroscope. The acceptance criterion
is pitch and roll within 2 degrees flat and 3 degrees after a 90 degree
rotation, which this answers directly, and the yaw drift demonstration the
specification asks for still works: turn the magnetometer off and yaw is
the integrated gyroscope, drifting.

## 81. Every attempt is recorded, and each row says which system produced it

**Decision.** A results table logs every run, planned or not, and no row is
removed for being unflattering. Each row carries the identity of the system
that produced it, so that superseded attempts can be read as superseded
rather than deleted. In Project 8 that is the `image_build` column, read
from `/etc/timestamp`.

**Why a column and not two columns in a markdown table.** The obvious
version of this is to add "first attempt" and "second attempt" columns to
the table by hand. That fails three ways: it has to be maintained by a
person on every reflash, it cannot be derived from the data, and the CSV
remains ambiguous when read on its own, which is how it will be read.

**Why the kernel columns do not already answer it.** `kernel` and
`kernel_version` describe the kernel. Two images can carry the same kernel
and differ in everything else, and on the first day of Project 8's bring-up
they did, twice: once to add the SPI controller module the image had never
named, once to fix a field extractor that was writing blank columns. Rows
from before and after would have been separable only by wall-clock time.

**Why `/etc/timestamp` rather than a git commit.** A commit is the better
identifier and nothing in the image carries one. Adding a recipe to stamp
it would mean this column could not be read on images already built, and
one of those was on the bench. poky writes `/etc/timestamp` during rootfs
assembly, it is unique per build, and `./go archive` records the commit
beside each stored image: stamp plus store gives the commit, and the row
alone gives the ability to group. That is enough, and it works today.

**Why empty rather than refusing when the file is absent.** A run that
produced good numbers should not be discarded over provenance. It should be
visibly missing it, which an empty column is and a missing row is not.

**The rule this exists to serve.** *Every attempt is a learning experience
and needs to be recorded, planned or unplanned, until the results become
acceptable.* A table containing only the acceptable attempts is a table
edited into agreement with its own conclusion. The unflattering rows are
how the quoted number was arrived at, and removing them removes the
evidence that it was arrived at rather than chosen.

**The one case where a row is deleted.** When it is not a measurement at
all. Project 8's first row was removed because a BusyBox incompatibility
left every external column empty: it recorded nothing. That is a different
act from removing an inconvenient number, and journal entry 50 says so at
length precisely because the two are easy to blur afterwards.

**Where this does and does not apply.** It applies to a results table whose
rows are experimental attempts, which today is Project 8 alone. It does not
apply to telemetry sinks: Project 17's `stwin-gw` CSV and Project 10's
`iio-rate` output are streams of sensor data, not logs of runs, and giving
them a build stamp per sample would be provenance theatre. The test is
whether a row is an attempt at something that could have gone differently.

## 82. A guard names the process or path it matched

A check that refuses has to say what it found. Two of this repository's
guards refused on evidence they did not print, and both were wrong.

require_no_running_build matches pgrep -f 'bitbake/bin/bitbake' and refuses.
BitBake keeps a memory-resident server alive after a build so the next
command can reuse it, so the pattern matches an idle server as readily as a
running build, and the message says a build is running. newest_path ranks
candidates by mtime and announces the ones it discarded, without resolving
symlinks first, so a deploy symlink and the file it points at become a
winner and a loser rather than one image.

In both cases the fix to the logic is small, readlink -f before ranking and
a tighter pattern with the matching pid printed. The rule that outlasts the
fix is the one about the message. A guard that refuses without naming its
evidence cannot be argued with: there is nothing to check, so the only
options are to believe it or to disable it, and on a long build people
disable it. Printing the pid, or the path, or the process line costs one
line and turns a verdict into something falsifiable.

This is the same rule as chapter 7's, arrived at from the other side. There
the problem was a check that selected its own input and reported on what it
selected. Here it is a check that rejects and does not report at all. Both
are the same omission: the check knows something the reader needs and keeps
it.

## 83. A binding is cited to a driver line, not recalled

**Context.** The Project 6 specification describes two kernel mechanisms in
one paragraph, in the same confident voice. One is exactly right: the I2C
core derives a client name from a compatible string by taking what follows
the comma, which is how `nxp,pcf8591` binds a driver that has no of_match
table at all. The other is impossible: it names `ssd1307fb` for an SPI
panel, and that driver's Kconfig entry is `depends on FB && I2C` and it is
registered with `module_i2c_driver`.

Nothing about the prose separates them. Both read as settled fact.

**Decision.** Every binding this repository uses is recorded in the
project's `docs/bindings.md` with the source file and line that settled it,
and the negative results are recorded the same way.

**Rejected.** Citing the binding documents under
`Documentation/devicetree/bindings/`, which is what the specification does.
They are a description of intent and they are not what decides whether a
probe happens. A file name there also changes between kernel versions,
which turns a citation into a dead reference.

**Why.** The failure this prevents is not a wrong property. It is a whole
design built on a driver that cannot bind, where the first three things
anybody debugs are the address, the bus speed and the overlay syntax, and
the bus is the fourth at best. The Kconfig line that settles it takes
thirty seconds to read and appears on nobody's list.

**Consequence.** Writing an overlay now includes reading the drivers it
names. That is perhaps an hour per project, and it is the hour that would
otherwise be spent on a board with a dead device and no message anywhere.

---

## 84. A parameter covers what the board varies, a source edit covers what the design chooses

**Context.** Project 6's pin numbers all come from a vendor manual's block
diagram rather than from a net list, so a wrong one is likely and should be
cheap. Device tree overlays have `__overrides__` for exactly that, and the
first draft of the design document also promised a parameter for choosing
between polled and interrupt-driven keys, on the strength of a Raspberry Pi
firmware feature that enables and disables whole fragments.

That feature is not documented in the kernel tree. `arch/arm/boot/dts/
overlays/README` in `rpi-6.6.y` is 258 KB of parameter lists and does not
mention `__overrides__` anywhere; the authoring syntax lives only on a
documentation website. Writing it from memory would have produced a
parameter that silently does nothing.

**Decision.** Parameters expose what a board revision changes: pin numbers,
an I2C address, a pull setting, a polarity, a poll interval. Anything that
changes which driver binds or how it is driven is a source edit, printed as
a diff in the bring-up document with the test to run before making it.

**Rejected.** Using the fragment enable syntax anyway. It is probably
correct and it is used by official overlays, and "probably" is the whole
problem: an overlay parameter that does nothing fails exactly like a
correct one on a board where the thing was going to work regardless.

**Why.** This is the Kconfig rule from chapter 2 applied one layer up. A
fragment line naming a symbol nobody declares is silently ignored; so is a
parameter naming a mechanism the firmware does not implement. Both produce
a build that succeeds and a board that disagrees.

**Consequence.** The interrupt-driven variant costs a rebuild rather than a
reboot. Given that it also costs an evening of `gpiomon` before it should
be trusted at all, the rebuild is not the expensive part.

---

## 85. A checker reports through a variable, never through the stream it shares with its output

**Context.** `explorer-verify` prints one line per peripheral and is the
acceptance test for Project 6. Its first version had a helper that printed
a driver name on stdout for the caller to capture, and called the row
printer itself when a device failed. Every call site therefore looked like

    if i2c_check DS3231 0068 rtc-ds1307 >/dev/null; then

and that redirect discarded the failure rows along with the name. A part
with no driver produced no line at all: ten rows where eleven were
expected, and nothing saying which one was missing.

**Decision.** A function that both reports and returns a value returns the
value through a variable. Output streams belong to output.

**Rejected.** Sending the diagnostic rows to stderr instead. It works, and
it splits one table across two streams so that `explorer-verify > log`
keeps the passes and loses every failure, which is worse than the bug.

**Why.** The exit status was still correct, so a test asserting only on
exit codes would have called this program right. What found it was a test
asserting the **status word of a named row**, which is a different and
better question: it checks what the reader will see rather than what the
shell will see.

**Consequence.** A small amount of awkwardness in POSIX shell, which has no
return values. The alternative is a checker whose worst output is a silent
omission, and an omission is the one error a reader cannot notice.
## 86. A figure is generated from the instrument's own file

Plots are produced by `./go plot` from the histogram files the instruments
write, and never drawn by hand, never assembled from numbers read off a
terminal.

The temptation is real and it arrives at the worst moment. The numbers are
in front of you, the figure is wanted now, and retyping forty pairs into a
plotting script takes five minutes against a round trip to the board. The
result is a figure that looks exactly like a figure made from an
instrument, carries no way to tell the difference, and will be read years
later by someone who assumes the obvious thing.

So the script takes paths, not values. The output embeds no timestamp and
no input path, which means regenerating from unchanged inputs produces
byte-identical output and a rebuilt figure is not a diff. If a figure
cannot be regenerated by pointing the tool at a file the board produced, it
does not go in the repository, however much it is wanted.

This is the same rule as the results table's. A row is a measurement of a
named system or it is not a row. A figure is a rendering of a named capture
or it is not a figure.

## 87. A count axis distinguishes once from never

Logarithmic count axes are the right default for latency histograms here,
because the bulk and the tail differ by three decades and only the tail
matters. But log10(1) is 0, so the obvious mapping puts a one-sample bin at
the baseline, where it is indistinguishable from a bin with nothing in it.

The first figure this repository generated lost all four of its tail bins
that way. The single samples at 44, 69, 76 and 100 microseconds drew flat
along the axis and read as empty, and those four bins are the entire reason
the figure exists. The code even carried a comment explaining that this was
correct.

The axis therefore spans decades plus one band, so a count of one sits a
full band clear of the baseline and zero sits on it.

The general form is worth more than the arithmetic: **a scale whose bottom
value is its own null value cannot be read.** It applies to a log axis with
a count of one, to a colour ramp whose lightest step is the page, and to
any encoding where "the smallest thing that happened" and "nothing
happened" land in the same place. In a histogram of rare events that
collision destroys the only part anybody needed.

It is also a reminder about where this class of defect is caught. No test
would have found it, because the misunderstanding was about what the figure
was for rather than about what the code did. It was found by rendering the
file and looking at it, which is the step that gets skipped because the
program exited zero.

## 88. A control is built by subtracting one symbol, never by omitting the fragment

**Context.** Project 8 compares a PREEMPT_RT kernel against a generic one.
The two builds are one kas file apart, and the control's file sets
`BENCH_RT_KERNEL = "0"`, which in the bbappend means the kernel fragment is
not added to `SRC_URI` at all.

**Decision.** The tuning symbols live in `rt-common.cfg`, applied to both
configurations. The variable under study, `CONFIG_PREEMPT_RT`, lives alone
in `rt.cfg`, applied to one.

**Rejected.** One fragment behind one switch, which is what shipped. It
reads as a single variable and is eight. The control booted without
`NO_HZ_FULL`, without `RCU_NOCB_CPU`, and with a different default cpufreq
governor, and the file's own header asserted that the two differed in one
symbol.

**Why.** A switch that gates a file gates everything in the file. That is
obvious written down and invisible in a kas file that says
`BENCH_RT_KERNEL = "0"`, because the name says kernel and the reader
supplies the word "preemption" from context. The grouping in the fragment
was done for authoring convenience; the experiment needs it grouped by
whether a symbol is the variable or the background.

**Consequence.** A kernel rebuild on both sides whenever the background
changes, rather than on one. That is the correct cost: if a symbol belongs
to the background, both arms must carry it, and if only one arm rebuilds,
it was not the background.

## 89. A check that verifies a fragment cannot speak for a build that has none

**Context.** `./go kconfig` proves every symbol in a kernel fragment
reached the produced `.config`. It is one of this repository's better
checks and it found three real defects the first time it could run.

**Decision.** Where a comparison has two arms, the check runs against both,
and an arm with no fragment to check is reported as unchecked rather than
as passing.

**Rejected.** Leaving it as is, on the grounds that a build with no
fragment has nothing that could have gone wrong. What went wrong was the
absence itself, and the check was the only thing positioned to notice.

**Why.** The check asks "did what I asked for arrive". When nothing was
asked for, the answer is yes, trivially and forever. The evidence file it
produced is real, correct, and describes the other kernel; nothing in it
says the control was never examined, because from the check's point of view
the control was never a subject. A vacuous pass is indistinguishable from a
real one in every artefact the check leaves behind.

**Consequence.** Checks need to report their scope, not only their verdict.
"7 symbols verified against raspberrypi4-64" and "no fragment configured
for this build, nothing verified" are different sentences, and only the
second one would have prevented four rows being measured against a control
that was not one.

This is the same rule as chapter 7's arrived at from a third direction. A
check that selects its own input must say what it selected. A guard that
refuses must say what it matched. And a check with nothing to examine must
say that it examined nothing, rather than passing in silence.

## 90. An instrument sits outside the load it measures under

**Context.** `rt-capture` streams an MCC 118 over SPI while `stress-ng`
runs on the housekeeping cores. It ran at ordinary priority, on the
argument that a capture process competing with the task it measures would
be measuring itself.

**Decision.** The instrument runs at SCHED_FIFO 60: above the load, below
the measured task's 80. It sets that itself rather than relying on its
caller.

**Rejected.** Deepening the ring buffer from one second to five. It works,
and it converts a loud failure into a quiet one: the reader is still
starved, the overrun just arrives later or not at all, and a run that
happened not to overrun is a row taken under conditions no column records.

**Why.** The original argument is about the measured core and was applied
to the wrong one. The load exists to perturb CPU 3. On the housekeeping
cores the instrument is not part of the experiment, it is the apparatus,
and apparatus that competes with the stimulus is not measuring the subject.
Two runs died at 1480000 and 120000 samples before this was obvious.

**Consequence.** A real-time process on the housekeeping cores, which is a
cost. It is bounded: the reader blocks in the library for nearly all of its
life, and 60 leaves the measured task ahead of it. And it sets the priority
itself because the board has neither `chrt` nor `nice`, not even as BusyBox
applets, so the caller could not have done it.

## 91. A column reports what can still change, not what the thing is called

**Context.** The results table has a `governor` column, read back after the
run rather than taken from the flag. With `force_turbo=1` the Raspberry Pi
firmware pins the clock underneath cpufreq: the sysfs interface remains,
`scaling_governor` still says `ondemand`, and `scaling_min_freq` equals
`scaling_max_freq`.

**Decision.** The column is derived from whether min equals max, not from
the policy's name. Equal means `fixed`, whatever the policy calls itself.

**Rejected.** Recording the name and explaining the exception in the
schema. A table whose reader has to remember which rows to discount is a
table with a footnote where a value should be.

**Why.** Reading back rather than trusting the flag was already the right
instinct, and it was applied to the wrong quantity. A governor name is a
policy; what a row needs to know is whether the clock could move. The
project's own schema had even predicted the outcome, "fixed means cpufreq
had nothing to offer, which is what force_turbo=1 looks like", and was
wrong about the mechanism, so the prediction and the code failed together
and neither corrected the other.

**Consequence.** Generalises past this column. Wherever a check reads a
name to infer a capability, the name can survive the capability. Read the
constraint.

## 92. A package in the manifest is not a file on a path

`linux-firmware-rpidistro-bcm43455` was named in the image recipe, its
licence flag was accepted in the kas file, and it appears in the manifest
of all three archived images. The radio still did not work, because the
package installs under `/usr/lib/firmware` and the kernel's firmware
loader searches `/lib/firmware`, and on this image `/lib` is a real
directory rather than a symlink.

Every artefact the build produces answers "was this installed". None of
them answers "can the thing that needs it find it". Those are different
questions and the second one is the one that matters on the board.

The general form: a check that reads the build's own records can only
confirm the build's own intentions. `./go ksym` and `./go kconfig` already
carry this lesson for kernel symbols, where the journal puts it as "did
what I asked for arrive" against "did I ask for what I needed". This is
the same gap one layer out, and it is worse here, because a missing symbol
eventually produces a message and a misplaced file produces ENOENT
attributed to the file rather than to the path.

Verify on the target, by the path the consumer uses.

## 93. A setter that cannot validate its value reports success for a file nothing can read

`bench-wifi-setup` reads `PSK=` from the boot partition and writes
`psk=%s` into a wpa_supplicant configuration. Unquoted, `psk=` means a 64
character hex key, so a bare passphrase is rejected and the whole network
block fails to parse. The script's own header documents the requirement.
The script does not enforce it, prints `configured wlan0 for ...`, and
exits 0.

The card then holds a credential file that looks right, a setup service
that reports success at every boot, and a supplicant that dies on startup
with the real message buried in a unit nobody reads.

A program that transforms a value into a format with rules should either
validate against those rules or normalise into them. Accepting anything
and passing it through is the option that produces a confident wrong
answer, and a confident wrong answer costs more than a refusal.

## 94. When the fix needs a rebuild, stop diagnosing on the board

The radio firmware was on the wrong path. That is fixed in an image
recipe. It cannot be fixed from a serial console, and once the cause was
known every further command on the board was diagnosis for its own sake.

It ran anyway, through four wrong hypotheses, a BusyBox option that does
not exist, three log excerpts pasted into the shell because they were in
fenced blocks, and finally a repair that destroyed the credential it was
meant to quote. It stopped when Joseph said it was not converging, which
it was not.

The rule is about the moment the class of fix becomes clear rather than
about patience. Once a defect is known to live in a build, the console has
nothing left to contribute, and the next step is to write it down and
rebuild. Carrying on costs the thing that was still working.

The corollary, learned the hard way on the same evening: **a repair to a
file holding a credential is not a diagnostic step.** It cannot be undone
from anything in the repository, by design, because the image carries
capability and the card carries identity. Read it, record what it should
say, and let the person who owns the credential write it.

---

## 95. Measured and met are different rungs, and a criterion can be measured and missed

**Context.** The status ladder in the top README had five rungs, from
Planned to Complete, and the table underneath it had already outgrown them:
Project 8 read **Measured** and Project 10 read **In progress**, neither of
which the legend defined. That is the shape of drift the repository already
knows, a claim written when it was true and left standing after the thing
it described changed, and it had reached the one table a reader consults
first.

Bringing Project 8 forward showed why the missing rung mattered. Its matrix
is taken, on the board, with provenance: 18 rows, both kernels, one
session. Under the old ladder its only honest labels were "Built and
running on the board", which undersells a completed measurement, or
"Complete", which is false, because two of its acceptance criteria were
measured and **not met**. Criterion 4 asked for `ext_p999_us` below 50 us
and got 63.9, and asked for the generic kernel to be five times worse and
got 1.4. Criterion 2 asked for 30000 +/- 1 edges, which no row in the file
reaches.

**Decision.** Two rungs added to the legend. **In progress** is for a
project between rungs that names both rather than rounding down.
**Measured** sits above "Built and running on the board" and below
"Complete", and its definition says the thing the ladder previously had no
way to say: a criterion can be measured and not met, and that is a result
rather than a gap.

**Rejected.** Relabelling the two rows to fit the existing five rungs. It
would have made the legend true again in one edit and lost the distinction
that the edit was for. Project 8 would have gone back to reading as
unfinished work when what it has is a finished measurement with two
negative findings in it, one of them the most interesting thing the project
has produced.

**Why.** A ladder whose rungs are claims about evidence has to be able to
express a claim that the evidence refutes. Without a Measured rung, the
only way to record criterion 4 is to leave it at "not started", which is
what it said while the data to answer it sat two directories away, and
which invites a reader to assume it would pass if anyone got round to it.
The bar this project set is one this bench does not reach, and the reason
is visible in every row: an unattributed excursion of several hundred
microseconds at the pin that appears in neither internal instrument.
Naming that is the output.

**Consequence.** Every project now has to distinguish three states that
used to collapse into "not done": not measured, measured and met, measured
and missed. The acceptance tables carry the burden, which is where it
belongs, and the cost is that a row saying "measured, and not met" will
look like a failure to a reader skimming for green ticks. That is the
correct impression of the criterion and the wrong impression of the work,
and the row has to carry enough numbers to make the difference obvious
without being read twice.

---

## 96. A figure obeys the same rule as a row, and lives in the repository

**Context.** Decision 86 settled where a *plot* comes from: the instrument's
own file, never numbers retyped off a terminal. It was written for
histograms, and it left three questions open that a request for better
diagrams brought straight up. Whether a figure drawn from a results table
rather than a capture is allowed. Whether an explanatory diagram may be an
image. And whether any figure may be hosted somewhere else, since the
obvious free tools for drawing a board are all web applications that keep
the drawing in an account.

**Decision.** Three kinds of figure, three rules.

A **data figure** is generated by a tool in this repository from a file the
board produced, and is committed as ASCII SVG. `./go plot` does this for the
instruments' histograms and `./go matrix` for a `results.csv`. The output
carries no timestamp and no input path, so regenerating from unchanged input
is byte-identical and a rebuilt figure is not a diff, and a test compares the
committed figure against the committed data so neither can drift from the
other unnoticed.

An **explanatory figure** stays ASCII or mermaid in `docs/DESIGN.md`. It is
drawn from understanding rather than from data, so decision 86 has nothing
to say about it, and the reasons for text are the ones the walkthrough
already gives: it diffs, it greps, it needs no build step, and it reads in a
terminal.

A **photograph** is admissible as evidence that hardware was assembled the
way the drawing says, and is never the diagram of record. When a photograph
and an ASCII schematic disagree, the schematic is the claim and the
photograph is the observation, and the disagreement is a finding.

**Rejected.** Hosting the figure. The tools that genuinely draw a board with
a HAT and a jumper are web applications, and a link to one is an external
citation, which decision 29 already refuses for text and refuses here for
the same reasons: the reader who arrives at this URL with no context cannot
follow it, the account can lapse, and the drawing then exists nowhere.
Exported and committed is fine; linked is not.

Also rejected: SVG exported from a drawing tool for the *explanatory*
figures. It renders, and it is text only in the sense that a minified
bundle is text. A diagram whose diff is unreadable has given up the property
the format was chosen for.

**Why SVG rather than PNG for the generated ones.** It is text, so the
repository's own checks can see inside it, which is not hypothetical: the
no-dash rule reads `.svg` and a typographic dash pasted into a figure title
fails lint. It renders on GitHub, it scales, and a 720 by 360 figure is five
kilobytes rather than fifty.

**Consequence.** One more thing to regenerate when data changes, and a test
that fails when somebody forgets. Two costs worth naming. The first is that
a figure can only exist where the captures were kept: project 8's paired
matrix has no per-run histograms saved, so no histogram of it can be drawn
at all, and `results/README.md` says so rather than drawing one from summary
columns. The second is that a photograph, once admitted, does not diff and
does not grep, which is a real departure and is why it is confined to
evidence.

## 97. A document that describes a program is a claim about it, and nothing tests it

Project 3's design document carried a data-flow block saying
`analyze.py -> results/<variant>/summary.md`, and named
`docs/before-after.md` beside it. The program printed its summary to stdout
and wrote no file. The other document did not exist. Both were written in
the same hour as the code they described, by the same hand, and both were
wrong the moment they were written.

Nothing caught it. The linter checks links, not claims. The test suite
asserted on the program's behaviour and had no opinion about any document.
Thirty-nine assertions passed while the design document described a program
that did not exist. It surfaced only because someone asked whether the
project was finished and the answer required going to look.

This repository already knows the shape from the other direction: a claim
written when it was true and left standing after the thing changed, which
is what Project 8's "the difference is the cost of a GPIO write" was and
what "Project 2 has not been done" became inside a single session. This is
the same failure with the arrow reversed. The claim was never true, and
being new is no protection at all.

The rule is not "write fewer documents". The design document was right and
the program was behind it: `summary.md` is what the Makefile needs and what
the before-and-after table is assembled from, so the fix was to write the
file, not to soften the sentence. Choosing the other direction is the real
hazard, because editing a document to match the code is always the faster
option and it silently lowers what the project set out to do.

So: **when a document names an artefact, go and look for it.** Not as a
lint rule, because a lint rule would only find paths, and the claims worth
checking are behavioural. As a step, at the point where the work is called
finished, and before it is called finished to anyone else.

## 98. A stub captures everything the program consumes, not only its arguments

**Context.** The destructive scripts of Project 2 are tested with recording
stubs: `dd`, `sfdisk`, `mkfs.ext4` and the rest are replaced by shell
scripts that append their argument list to a file and exit 0, so the tests
run with no board, no root and no loop devices.

The most important number in that project is the sector the first partition
starts at. Below 2048 it overwrites the bootloader, and the symptom is not
an error: the board stops after the SPL banner, or a filesystem will not
mount and `fsck` cannot say why.

`sfdisk` is configured on **stdin**. The partition table is piped to it.

**Decision.** A stub records every channel the real program reads. Where a
tool takes configuration on stdin, the stub captures stdin too, prefixed so
that assertions can tell the two apart.

**Rejected.** Asserting on the pipeline that feeds the stub instead, by
checking the script's source for the `printf`. That tests that the text
exists, not that it reaches the tool, which is a different and weaker
claim, and it passes on a script that builds the table and never sends it.

**Why.** A stub that captures less than the program consumes does not
produce a false pass. It produces a **false accusation**: a correct program
reported as broken. That is worse than it sounds, because the natural
response on the next reading is to weaken the assertion rather than widen
the stub, and the assertion is the thing worth keeping.

It happened twice in one file. The sector-2048 assertion failed against a
script doing exactly the right thing, and then the write-order assertion
failed because it matched `sfdisk /dev/sdz` while the stub records
`sfdisk -q /dev/sdz`. Same shape: the test could not see what it was
asserting about.

**Consequence.** Every recording stub in this repository has the same
exposure. Any tool configured through stdin, a file descriptor, an
environment variable or a configuration file needs a stub that records that
channel, and an assertion that reads it.

## 99. A placeholder that cannot work beats a value that might

**Context.** `extlinux.conf` and `/etc/fstab` name the root filesystem by
`PARTUUID`. Both are written twice on purpose: once by the rootfs build,
which cannot know the identity of a partition that does not exist yet, and
once by the provisioning script that creates it.

So the overlay has to ship something in that field.

**Decision.** It ships `root=PARTUUID=FILLED-BY-FLASH-EMMC`, which cannot
parse and cannot boot.

**Rejected.** Leaving the field absent, and shipping a plausible value
copied from a previous card. The first gives a kernel with no root and an
error a long way from its cause. The second is worse: it boots the wrong
filesystem, or drops to a prompt naming a device that really does exist
somewhere else, and the operator then debugs the wrong machine.

**Why.** The question is not whether the placeholder is wrong. It is
whether being wrong is **visible at the first attempt**. An impossible
value fails once, immediately, with the reason on the console. A plausible
one fails later, quietly, in a way that looks like hardware.

This is the same rule as the results table's blanks, arrived at from the
other side. There the point was that a number nobody measured is worse than
a blank, because the blank is honest. Here the point is that a blank is not
enough when something has to occupy the field, and then the occupant should
be self-evidently a placeholder.

**Consequence.** Anything written twice, once before a value is knowable
and once after, gets a first value that cannot be mistaken for the second.
The script that fills it in matches both the placeholder and any previous
real value, so running it twice is not a special case.

## 100. A pinned input against a moving host: move the number, never patch inside the pin

**Context.** Project 2 pins U-Boot, the kernel and the Debian suite in
`toolchain.env`, because an unpinned build of a bootloader cannot support
the project's claim that the boot chain is known from the SoC ROM upwards.

On 18 September 2026 the pinned U-Boot, `v2024.10`, would not build. It
carries a copy of dtc whose pylibfdt typemaps call
`SWIG_Python_AppendOutput` with two arguments; SWIG 4.3 added a third, and
the host ships SWIG 4.4. `pylibfdt` is not skippable, because
`u-boot-sunxi-with-spl.bin` is a binman image and binman needs it.

**Decision.** Move the tag, and record the reason beside the number rather
than only in the journal.

**Rejected, and why each is worse.**

Patching the vendored dtc inside the pinned tree. The tag then names a tree
that is not what is built, which is precisely the property the pin exists
to provide. A pin that requires a patch is a pin that lies.

Holding the host's SWIG back. This moves the dependency from a file in the
repository to an apt pin on one machine, where nothing in the repository
can state it, nothing checks it, and a fresh clone on a fresh host fails
with no clue why.

**Why.** A pin is a claim about what was built. When the host moves under
it, the honest options are to move the pin or to state the host constraint
where the build can enforce it. Patching inside the pin does neither: it
keeps the number and changes the thing the number refers to.

**Consequence.** The reason lives in `toolchain.env`, next to
`UBOOT_TAG`, because the next reader is looking at the number rather than
at a journal. `docs/BRINGUP.md`'s expected SPL banner moved with it, since
a milestone that names a version is a claim and was one line from being
stale.

This will happen again. Every pinned input in this repository is a bet that
the host stays still, and hosts do not.

## 101. A check's scope is part of its claim, and has to be stated or widened

**Context.** `uboot/build.sh` opens by saying it names whichever dependency
is missing rather than failing partway through a make. Its check was a loop
over `command -v` for five tools. On 18 September 2026 it passed, and the
build then died forty seconds later on
`tools/mkeficapsule.c:20:10: fatal error: gnutls/gnutls.h`.

`command -v` answers a question about executables. Development headers were
never in its field of view. The check was completely correct about the
thing it looked at and completely silent about the rest, and the header
sits at the top of a mandatory host tool.

**Decision.** A check that cannot cover the claim above it is either
widened until it can, or the claim is narrowed to what it actually covers.
Here it was widened: `pkg-config --exists` for `gnutls` and `openssl`,
asking the system where its headers live rather than assuming.

Where the widening itself can be unavailable, the gap is announced. If
`pkg-config` is absent the script prints that the header check is skipped
and that a missing header will surface as a compile error. A skipped check
that says so is a different object from a check that quietly passes.

**Rejected.** A path test, `[ -r /usr/include/gnutls/gnutls.h ]`. The
include directory is multiarch and differs between distributions, so this
is a second wrong answer that is right on one machine, and its failure mode
is worse than the one being fixed: refusing to build on a host where the
header is present and merely elsewhere.

**Why.** This is the fourth guard in this repository to report honestly on
a narrower question than the one being asked:

| Guard | Answered | Was asked |
|---|---|---|
| Project 8 kernel-config check | is the fragment listed | did the option reach the built kernel |
| newest_path | which path is newest | which distinct artefact is newest |
| uboot merge guard | what did merge_config.sh say | is the option in .config |
| uboot dependency loop | are these executables on PATH | can this build start |

None of them is a bug in the ordinary sense. Every one returned the truth.
The defect is the gap between the question the code asks and the sentence
written above it, and that gap is invisible while the check is passing.

**Consequence.** When a script's header makes a promise, the promise is the
specification for its guards, not a description of them. The cheap
discipline: read the comment, then ask what a failure would look like if
the comment were wrong, and check whether the guard would catch it.

The corollary is the reason the skip message exists. An unavailable check
must never be indistinguishable from a satisfied one, which is exactly what
Project 8's control arm cost, twice.

## 102. A fragment states the gates it depends on, not only the options it wants

**Context.** Project 2's kernel fragment asked for `CONFIG_CFG80211`,
`CONFIG_MAC80211`, `CONFIG_BRCMFMAC` and `CONFIG_BRCMFMAC_SDIO`.
`sunxi_defconfig` carries `# CONFIG_WIRELESS is not set`, and all four live
inside that menu. All four were dropped, with no error from kconfig, and
the only reason anyone knew is that `kernel/build.sh` compares every line
of the fragment against the produced `.config`.

The fragment's own header says a fragment should not restate its defconfig,
because a fragment that repeats what it is layered on cannot be read for
its intent. That rule is right and it is what produced the omission.

**Decision.** The rule applies to options the defconfig already provides.
It does not apply to a gate the defconfig has **closed**. A fragment states
every menu gate, dependency and vendor switch that its options sit behind,
because those are overrides rather than restatements. Here that is
`CONFIG_WIRELESS`, `CONFIG_WLAN` and `CONFIG_WLAN_VENDOR_BROADCOM`.

Stating a gate that is already open costs one line and nothing else: the
option is `y` either way, so the check still passes and the file still
reads as intent.

**Rejected.** Relying on kconfig's `select` and `default y` to open the
gates. They do open them in many cases, which is exactly the problem: the
fragment then works on one defconfig and silently produces less on another,
and the difference is invisible until a feature is missing from a board
that boots perfectly.

Also rejected: turning the wireless options on by editing `.config`
directly, which is how this class of problem is usually "fixed" and which
leaves no record of what was asked for.

**Why.** A dropped option in a menu is not a build failure. It is a kernel
that boots, runs, and lacks something. Project 2's version of that is a
board with no wireless interface and nothing in `dmesg` naming a cause,
which is the same failure the modules-before-rootfs ordering exists to
prevent, arriving by a different route.

The general shape: **a request is only meaningful if the thing it depends
on is also requested.** A leaf without its branch is a wish.

**Consequence, and it is not confined to Project 2.** Every kernel fragment
in this repository asks for leaves and trusts the defconfig for the
branches. The Yocto projects' fragments have never been checked for a
closed gate, and `./go kconfig` compares requests against results the same
way this script does, so the check exists there and has simply never
refused. That is not evidence of absence. It is worth one pass over each
fragment, asking of every option which menu it sits in and whether that
menu is open in the defconfig underneath.

A second consequence, from the other defect found in the same run:
`CONFIG_MMC_PWRSEQ_SIMPLE` is not a symbol at all, and the driver it meant,
`PWRSEQ_SIMPLE`, was already enabled by `default y`. A request for a
nonexistent symbol leaves no trace, and when the thing it was reaching for
happens to be on anyway, the line is inert for the life of the project with
nothing ever disagreeing. Only a check that compares requests against
results can see that, because there is no failure to observe.

## 103. Under sudo, ask who invoked you; never read $HOME

**Context.** Project 2 derives its work tree from `$HOME`. The one step
that needs root, building the root filesystem, therefore looked in
`/root/bench` and could not see the kernel built forty minutes earlier by
the ordinary user. `sudo -E` had carried the environment across since the
file was written. The build host's sudo does not implement `-E`: it prints

    sudo: preserving the entire environment is not supported,
    '-E' is ignored

and runs the command anyway.

**Decision.** Any script that can be run under sudo and needs the invoking
user's paths recovers them from `SUDO_USER`, not from `$HOME`:

    _home=$HOME
    if [ "$(id -u)" = 0 ] && [ -n "${SUDO_USER:-}" ]; then
            _home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            [ -n "$_home" ] || _home=$HOME
    fi

`SUDO_USER` is set by sudo itself, so it survives an environment reset for
the same reason the reset exists. `getent` rather than `/home/$SUDO_USER`,
because a home directory is not always under `/home` and assuming so is the
same class of error one layer down.

And where a script needs a whole pinned environment rather than one path,
**sudo goes on the entry point, never on the script.** An entry point that
sources its own configuration establishes it inside the sudo, where nothing
can reset it. That is a structural answer; `-E` is a request the
environment is free to decline.

**Rejected.** Documenting a working incantation,
`sudo env VAR=value ./entry`, which does work everywhere because `env` is a
program rather than a sudo feature. It is one more thing to remember and
type correctly while a password prompt is waiting, and this repository
already decided that a step nobody can get wrong beats a step documented
well. A workaround that lives in a human's memory is not a fix.

Also rejected: detecting the broken sudo and warning. That adds a second
thing that can be wrong and fixes nothing.

**Why.** The deeper hazard is not sudo. It is that **a tool which warns and
continues is more dangerous than one that fails.** `-E` declined its job,
said so in one line above a password prompt, and handed control to a script
with every reason to trust its environment. A non-zero exit would have put
the failure at the door with its reason attached. Instead it surfaced forty
seconds later as a missing file in a directory nobody recognised, and the
only reason it surfaced at all is that the script prints the absolute path
it looked in.

That last detail is the transferable half. **A refusal that names what it
looked for diagnoses failures it was not written for.** The guard here
exists to catch a wrong build *order*; it caught a wrong *environment*,
because the path in its message was the whole answer.

**Consequence.** Every root-needing path in this repository takes sudo on
the entry point. Anything deriving a path from `$HOME` that can run as root
is suspect: the Yocto side's `scripts/common.sh` computes `KAS_WORK_DIR`
the same way, and while nothing there runs under sudo today, nothing
prevents it either.

And every guard gets read once more with this question: if it refuses, does
its message contain enough to diagnose a cause nobody anticipated?

## 104. Refuse what the build can fix; say loudly what it cannot

**Context.** `mkrootfs.sh` refuses four ways and every one of them is a
state the build itself put there: no pinned environment, no kernel version
file, no overlay, no `brcmfmac` in `modules.dep`. Running the right command
in the right order clears all four.

The `brcmfmac` firmware is not like that. The driver needs two files. The
`.bin` comes from Debian's `firmware-brcm80211`. The NVRAM `.txt` beside it
is board specific, Debian does not carry the AP6212 one, and it is fetched
by hand from a vendor image. It is the only input in Project 2 that
`toolchain.env` cannot pin.

A refusal there would be a build blocked on something no rerun can supply.

**Decision.** A guard refuses when the caller can act on the refusal now. A
guard **prints** when the missing thing is real, known, and outside the
build's reach. The printing form gets the same care as a refusal: it names
the file, says what its absence will look like, and points at the document
that says where to get it.

    --- brcm firmware for this chip:
    ---            brcmfmac43430-sdio.bin
    ---            no NVRAM .txt here. It is the one vendor artefact in
    ---            this project: see docs/BRINGUP.md section 5.

**Rejected.** Refusing, which turns one predictable evening into a blocked
build for everyone including the people who already have the file
elsewhere. And saying nothing, which is what produces the evening: without
the NVRAM, `brcmfmac` loads the firmware and then times out bringing the
SDIO clock up, and that failure reads exactly like broken hardware.

**Why.** The question a guard answers is not "is this state wrong". It is
"what should the person reading this do next". Where the answer is *fix it
and rerun*, refusing is the shortest path and a warning is noise that gets
scrolled past. Where the answer is *go and obtain something*, refusing
does not help them obtain it and costs everyone else the build.

The two forms share the standard that matters, which is decision 103's
second half: **the message carries enough to diagnose a cause nobody
anticipated.** A refusal that names only the line, or a warning that says
only "not found", fails that test identically.

**Consequence.** Warnings of this kind are held to the refusal standard or
they are not worth printing. Anything softer becomes the line everyone
learns to ignore, and then the one time it mattered it was on screen and
nobody read it.
