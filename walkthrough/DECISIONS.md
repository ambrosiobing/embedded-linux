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

**Consequence.** A slower first build and a steeper learning curve, in
exchange for the ability to discuss the trade honestly rather than
theoretically.

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
checks every line, including the ones asking for an option to stay off. That
check only works because `RM_WORK_EXCLUDE` keeps the kernel work directory.

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

Previous: [10. Generalising](10-generalising.md) | Index: [Walkthrough](README.md)
