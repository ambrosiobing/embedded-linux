# 05. kas and layers

## The problem kas solves

Setting up a Yocto build by hand means: clone poky at some revision, clone
meta-openembedded at a compatible revision, clone meta-raspberrypi at
another, `source oe-init-build-env`, then hand edit two generated files,
`conf/bblayers.conf` to list the layers and `conf/local.conf` to set the
machine and a dozen variables.

Every one of those decisions then lives in an untracked file inside a build
directory that `.gitignore` excludes. Six months later nobody can say which
revisions produced the shipped image.

This is the origin of most "works on my machine" in embedded Linux, and it
is a lifecycle problem rather than a convenience one. A build you cannot
reconstruct is a product you cannot support.

## What kas does instead

One tracked YAML file declares the whole thing. `kas build kas/bench-rpi4.yml`
clones each repository at the stated revision, generates both conf files,
and runs BitBake.

```
  kas/bench-rpi4.yml  (tracked, reviewed, tagged)
            |
            +--> clone poky @ scarthgap
            +--> clone meta-openembedded @ scarthgap
            +--> clone meta-raspberrypi @ scarthgap
            +--> generate conf/bblayers.conf
            +--> generate conf/local.conf
            +--> bitbake bench-image
```

The build directory becomes disposable, because everything that shaped it is
in the file.

## Reading ours

```yaml
machine: raspberrypi4-64      # the board: CPU tune, firmware, device tree
distro: poky                  # policy: libc, init manager defaults, features
target: bench-image           # what to build
```

Those three are the only things that change between the three kas files.
`bench-rpi3.yml` includes this one and overrides `machine`; `bench-dev.yml`
overrides `target`. The pins are never duplicated.

```yaml
repos:
  bench:
    layers:
      meta-bench:
```

A repository entry with no `url` means "the repository containing this
file". Its root is not a layer, since it holds twenty projects, so the layer
inside it is named explicitly.

```yaml
  poky:
    url: https://git.yoctoproject.org/poky
    branch: scarthgap
    layers:
      meta:
      meta-poky:
```

### Branch now, commit hash before release

A branch is a moving target: build today and in six months and you get
different trees. That is right while developing and wrong for anything you
call reproducible.

```sh
kas dump --lock kas/bench-rpi4.yml > kas/bench-rpi4.lock.yml
```

rewrites each branch as the exact commit that was just built. That locked
file is what gets tagged at a release, and it is what a maintenance rebuild
three years later starts from. See [09. Lifecycle](09-lifecycle.md).

### The local.conf fragments

| Setting | Why |
|---|---|
| `INIT_MANAGER = "systemd"` | The status daemon is a systemd unit, and later projects use timers, socket activation and D-Bus |
| `ENABLE_UART = "1"` | Brings the serial console up in firmware, early enough to catch a kernel panic |
| `IMAGE_FSTYPES = "wic.bz2 wic.bmap"` | A partitioned image plus its block map, so flashing skips empty blocks |
| `INHERIT += "rm_work"` | Deletes each recipe's work directory after packaging. The difference between 60 GB and several hundred |
| `RM_WORK_EXCLUDE += "linux-raspberrypi bench-status"` | Keeps the two that actually get debugged. This is what makes `./go kconfig` possible at all |
| `INHERIT += "buildhistory"` and `BUILDHISTORY_COMMIT = "1"` | Records what each image contained and commits it to its own git repository |
| `DL_DIR`, `SSTATE_DIR` | Caches outside the build tree, so `./go clean` is cheap |
| `BB_NUMBER_THREADS`, `PARALLEL_MAKE` | Parallelism. Match to your core count |

`rm_work` and `RM_WORK_EXCLUDE` are a good example of a trade being made
explicitly rather than by default. Disk is reclaimed everywhere except the
two places where you will want to look when something is wrong.

## The four files that make a layer

### 1. `conf/layer.conf`

```
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb ${LAYERDIR}/recipes-*/*/*.bbappend"
BBFILE_COLLECTIONS += "bench"
BBFILE_PRIORITY_bench = "10"
LAYERDEPENDS_bench = "core openembedded-layer raspberrypi"
LAYERSERIES_COMPAT_bench = "scarthgap"
```

`BBFILES` is the glob that finds recipes, which is why directory naming is
not decoration: `recipes-bench/bench-status/bench-status_0.1.bb` matches
`recipes-*/*/*.bb`.

`BBFILE_PRIORITY` decides who wins when two layers provide the same recipe.
Higher beats lower; ours is 10 against poky's 5.

`LAYERDEPENDS` makes a missing layer fail immediately with a clear message
instead of as a confusing missing recipe later. `LAYERSERIES_COMPAT` states
which Yocto release the layer was written against, so using it with another
warns rather than breaking silently.

### 2. The image recipe

```
require recipes-core/images/core-image-minimal.bb
IMAGE_FEATURES += "ssh-server-openssh debug-tweaks"
IMAGE_INSTALL:append = " libgpiod libgpiod-tools i2c-tools bench-status"
```

`IMAGE_FEATURES` are higher level than packages: `ssh-server-openssh` pulls
the server, its configuration and its units together.

`debug-tweaks` leaves root without a password. Right for a bench board on an
isolated network, wrong for anything else, which is why the recipe carries a
comment saying exactly what to replace it with. Removing it is a
pre-production task, listed in [09. Lifecycle](09-lifecycle.md).

### The override syntax

| Form | Meaning |
|---|---|
| `VAR = "x"` | Set |
| `VAR += "x"` | Append at parse time |
| `VAR:append = " x"` | Append after everything else has had its say |
| `VAR:remove = "x"` | Remove an element |
| `VAR:raspberrypi4-64 = "x"` | Only for that machine |
| `VAR:class-native = "x"` | Only for the native build of the recipe |
| `SYSTEMD_SERVICE:${PN}` | Belongs to this package, not the recipe |

`:append` does not insert a space, hence the leading space inside the
quotes. Forgetting it silently glues two package names together into one
that does not exist.

### 3. The application recipe

```
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade..."
SRC_URI = "file://bench-status.c file://bench-state ..."
DEPENDS = "libgpiod"
inherit systemd pkgconfig features_check
S = "${WORKDIR}"
do_compile() { ... }
do_install() { install -Dm0755 bench-status ${D}${bindir}/bench-status }
SYSTEMD_SERVICE:${PN} = "bench-status.service bench-state.timer"
```

The licence checksum is not bureaucracy. Yocto refuses to build if the
licence text changes underneath you, so an upstream quietly relicensing is
caught rather than shipped. In a product that matters: the licence manifest
is a deliverable, not a formality.

`${D}` is the staging directory that becomes the package. Nothing is ever
installed onto the build host.

`inherit` brings in classes: `systemd` installs and enables units,
`pkgconfig` points `pkg-config` at the target sysroot rather than the host,
`features_check` fails early and readably if the distro lacks systemd.

### 4. The bbappend

```
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://bench.cfg"
```

This is the mechanism that makes layers work. `meta-raspberrypi` owns the
kernel recipe and we never edit it. A `.bbappend` with a matching name is
parsed straight afterwards and adds to it. The `%` in
`linux-raspberrypi_%.bbappend` is a wildcard over the version, so the append
survives the BSP bumping its kernel.

`bench.cfg` is a kernel configuration fragment:

```
CONFIG_GPIO_CDEV=y
# CONFIG_GPIO_CDEV_V1 is not set
CONFIG_IIO=y
CONFIG_SPI_SPIDEV=m
```

**A fragment, not a copied `.config`.** A copy is thousands of lines, pins
you to one kernel version, and hides which twelve options you actually care
about. A fragment is a list of decisions with reasons, and it survives the
BSP rebasing onto a new kernel.

The risk with fragments is that a typo or an unsatisfied dependency makes an
option silently absent: the build succeeds and a driver fails on the board a
week later. That is why `./go kconfig` exists and compares every line of the
fragment against the `.config` that was actually built, including the lines
that ask for an option to stay off.

---

Previous: [04. BitBake](04-bitbake.md) | Next: [06. Mechanism and policy](06-mechanism-policy.md)
