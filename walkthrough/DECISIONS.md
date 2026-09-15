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

Previous: [10. Generalising](10-generalising.md) | Index: [Walkthrough](README.md)
