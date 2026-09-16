# Walkthrough

Why this repository is built the way it is, and how the same reasoning
applies to the other nineteen projects and to embedded Linux work in
general.

Project 1 is the worked example throughout, because it is the one that
has been built and booted. Project 15 is the second, and where it
contradicts what is written here the contradiction is in its journal. The last two documents pull back from it: where each piece belongs
in a product lifecycle, and what changes when the board, the peripheral or
the stage of the project changes.

## Read in order

| | Document | What it answers |
|---|---|---|
| 01 | [Context](01-context.md) | What embedded Linux is, what these twenty projects are for, what is on the bench |
| 02 | [Build systems](02-build-systems.md) | Vendor image, Buildroot or Yocto, and what BitBake, Poky and OpenEmbedded each are |
| 03 | [Workflow](03-workflow.md) | Three machines, why the repository moves between them, and the three traps that creates |
| 04 | [BitBake](04-bitbake.md) | What happens during those three hours, and why the second build takes minutes |
| 05 | [kas and layers](05-kas-and-layers.md) | Where versions live, and the four files that make up a layer |
| 06 | [Mechanism and policy](06-mechanism-policy.md) | Why the status daemon is two programs, and how that made it testable without hardware |
| 07 | [Verification](07-verification.md) | What each check proves, and the more important question of what it cannot |
| 08 | [Board bring-up](08-board-bringup.md) | Flashing, the serial console, LED polarity, and the SDK |
| 09 | [Lifecycle](09-lifecycle.md) | Prototype, test, pre-production, production, field, maintenance, and what changes at each |
| 10 | [Generalising](10-generalising.md) | Other boards, other peripherals, and where all twenty projects sit |
| | [Decisions](DECISIONS.md) | A log of choices, each with the alternative that was rejected and why |
| | [Design, Project 1](../projects/01-yocto-image/docs/DESIGN.md) | The four figures: architecture, schematic, bench layout, UML sequence, plus the software components |
| | [Journal](../projects/01-yocto-image/JOURNAL.md) | What actually happened while building Project 1, in order, including the false starts |
| | [Design, Project 04](../projects/04-netboot-hil/docs/DESIGN.md) | The network-boot lab: architecture, wiring, bench layout, the sequence of a test run, and who owns which device |
| | [Journal, Project 04](../projects/04-netboot-hil/JOURNAL.md) | Two console-framing defects a fake board found, and a failure mode with no symptom |
| | [Design, Project 15](../projects/15-lte-router/docs/DESIGN.md) | The LTE router: architecture, schematic, bench, the watchdog state machine, and who owns which interface |
| | [Journal, Project 15](../projects/15-lte-router/JOURNAL.md) | Where this project departed from its own specification, and why |

## The through-line

One idea connects every document here.

**On a laptop you install an operating system somebody else built. On an
embedded device you build it yourself, and you are answerable for every byte
in it.**

Everything else follows. Pinning layers to a commit follows from it. Kernel
changes as fragments rather than a copied configuration follows from it. So
does keeping policy in systemd and mechanism in C, refusing to claim
reproducibility you have not measured, and leaving the build-times table
empty until the build has run on your own machine.

## Diagrams

Diagrams here are text: mermaid for sequence and state diagrams, which
GitHub renders inline, and ASCII for structure and wiring. Nothing needs a
build step, everything survives a diff, and `grep` finds it all.

## A note on what is proven

These documents distinguish between what has been verified and what has
not, because that distinction is the whole point of the exercise.

Verified so far: the image builds from source in 194 minutes over 5095
tasks and reproduces identically from the same commit; the board boots with
no failed units; the status daemon runs and owns its three GPIO lines; every
option in the kernel fragment reached the built `.config`; every package in
the image is justified in writing; and the board joins a wireless network.

Not yet: the SDK has not been generated, and two items are deferred with
written reasons, the LED indication and the serial console. Where a document
describes something unproven, it says so.
