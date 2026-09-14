# 02. Build systems

## Three ways to get Linux onto a board

| | Vendor image | Buildroot | Yocto Project |
|---|---|---|---|
| What it is | An SD card image someone else built | Builds one root filesystem from source | Builds a whole distribution from source |
| Time to first boot | Minutes | About an hour | One to three hours |
| Do you know what is in it | No | Yes | Yes, package by package |
| Package manager on target | Yes, and large | No, by design | Optional, with your own feed |
| Incremental rebuild | Not applicable | Fast, whole image | Fast, per package, via shared state |
| Reproducible in three years | No | Mostly | Yes, that is the point |
| Learning curve | None | A weekend | Weeks |
| Where you meet it | Prototypes, hobby work | Fixed function appliances | Product lines, automotive, industrial |

### Vendor image

Raspberry Pi OS. Right answer for an afternoon, wrong answer for a product:
a few thousand packages you did not choose, no way to say why any of them
are there, and next year's release differs in ways nobody recorded. You also
cannot shrink it safely, because you do not know what would break.

It still has a place. In [09. Lifecycle](09-lifecycle.md) it is the correct
choice for the first hour of hardware bring-up, when the question is only
whether the board is alive.

### Buildroot

Compiles a root filesystem from source with a kernel style `menuconfig`.
Small, fast, and readable in an afternoon: the whole system is makefiles you
can follow.

Its deliberate limitation is that the filesystem is one indivisible unit.
There are no packages on the target and no update path other than replacing
the whole image. For a sensor node that never changes, that is a feature and
not a shortcoming. `daqring` uses it for exactly that reason.

### Yocto

Builds a distribution: every package individually with its dependencies and
licence, a package feed if you want one, and a cross SDK that matches the
image exactly. Considerably more machinery, and what organisations with more
than one product use, because the second product reuses the first one's
work.

## Why Yocto here, and not Buildroot

`daqring` already demonstrates Buildroot. Doing Project 1 in Yocto means the
pair covers both major build systems, which is usually the first question in
an interview for this kind of role. The honest answer to "which is better"
is that they solve different problems, and having used both is the only way
to say that convincingly.

It is also the right tool for this specific job. Project 1 has to produce an
SDK for nineteen later projects, and SDK generation is a Yocto feature that
Buildroot only approximates.

## The vocabulary, because four names confuse everyone

```
        Yocto Project              the umbrella: releases, LTS schedule, docs
              |
        +-----+------+
        |            |
      Poky        BitBake          Poky: the reference distribution
        |                          BitBake: the build engine, a Python program
  OpenEmbedded-Core                OE-Core: the shared recipe base
        |
    meta-*  layers                 vendor and community layers stack on top
```

| Name | What it actually is |
|---|---|
| **BitBake** | The engine. Reads recipes, computes a task graph, runs it. The thing that takes three hours |
| **OpenEmbedded** | The shared recipe base: how to build gcc, systemd, openssh and several thousand others |
| **Poky** | The reference distribution. OE-Core plus BitBake plus defaults, bundled to work out of the box |
| **Yocto Project** | The umbrella organisation and the release train |

"Building with Yocto" means: run BitBake, over recipes from OpenEmbedded,
with Poky's defaults, plus the layers you add.

## The two ideas the rest depends on

**A recipe** describes how to build one thing: where the source comes from,
what it depends on, how to configure, compile, install and package it.
`openssh_9.6p1.bb` is a recipe. So is `bench-status_0.1.bb`.

**A layer** is a directory of recipes plus a little configuration, stacked
on top of other layers.

```
  +-----------------------------------------------+
  |  meta-bench          your image, app, kernel   |   priority 10
  +-----------------------------------------------+
  |  meta-raspberrypi    BSP: firmware, kernel, DT |   priority 9
  +-----------------------------------------------+
  |  meta-oe             extra packages, libgpiod  |   priority 6
  +-----------------------------------------------+
  |  meta, meta-poky     OE-Core and Poky defaults |   priority 5
  +-----------------------------------------------+
```

Layers stack rather than merge. A higher layer extends or overrides a lower
one without editing it, through a `.bbappend` file or a higher priority.

This is what makes the arrangement survivable. You never patch poky. When
the next release lands, poky is replaced wholesale and your layer moves
across unchanged, or with the few edits its release notes demand.

It is also why the real deliverable of Project 1 is the layer and not the
image. The image is an output. The layer is the thing you maintain.

## Release names

Yocto releases are named, and LTS releases are supported for four years.
This repository pins to **scarthgap**, which is 5.0 LTS. Moving to the next
LTS is three edits in one file, described in
[05. kas and layers](05-kas-and-layers.md).

Choosing LTS over the latest release is a lifecycle decision: a product that
ships needs security updates for longer than a six month release provides.

---

Previous: [01. Context](01-context.md) | Next: [03. Workflow](03-workflow.md)
