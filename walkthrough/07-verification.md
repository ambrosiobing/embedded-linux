# 07. Verification

## The testing ladder

Embedded work has a characteristic problem: the real thing is slow,
scarce and physical. So tests are arranged as a ladder, cheapest first, and
each rung catches a different class of fault.

```
  rung                        cost        needs            catches
  ------------------------------------------------------------------------
  5  hardware in the loop     minutes     the board        everything real
  4  image build              hours       60 GB of disk    recipes, packaging
  3  host compile             seconds     a compiler       API misuse, warnings
  2  logic tests              under 1 s   nothing          the decisions
  1  static checks            under 1 s   nothing          structure, wiring
```

`./go check` is rungs 1 to 3. `./go build` is rung 4. The board is rung 5.

The value of the arrangement is not that the low rungs are thorough. It is
that they are so cheap that there is no excuse for skipping them, and they
catch the mistakes that are most annoying to diagnose from the top.

## What each check catches

| Stage | Catches |
|---|---|
| Static layer checks | A file in `SRC_URI` that was never added, a unit in `SYSTEMD_SERVICE` that `do_install` misses, an incomplete `layer.conf`, a script committed non-executable, a line over 88 columns, a non-ASCII character in a recipe |
| Shell files parse | A syntax error, and CRLF damage after a copy between machines |
| shellcheck | Unquoted expansions, missing `cd` guards, the usual traps |
| State machine | The seven status cases, against a fake `systemctl` |
| Host compile | The daemon built with `-Wall -Wextra -Werror` against real libgpiod v2 headers |

**These have already earned their keep.** The static checks caught
`leds.conf` missing from `SRC_URI` when it was added, and a systemd unit
listed but never installed. The executable bit rule exists because that
exact fault produced a `Permission denied` on a fresh clone, two machines
and several days away from its cause.

## What `./go check` cannot prove

This matters more than the list above, because a check whose limits are
unstated invites false confidence.

| Not covered | Why | Where it is covered |
|---|---|---|
| The recipe | `do_compile` is shell run by BitBake with its own variables. The host compile bypasses it entirely | `./go build` |
| Cross compilation | Host gcc for the host, not the cross compiler against a target sysroot | `./go build` |
| The libgpiod version | The host has 2.2.1, scarthgap ships about 2.1. Both v2, but not the same statement | `./go build` |
| Packaging and units | Whether `FILES` is right, whether units are enabled, whether `/run/bench` is created | boot |
| The kernel fragment | Whether those `CONFIG_` lines reached the kernel | `./go kconfig` |
| The hardware | Whether the LEDs are active high or low, and whether anything lights | the board |

A green `./go check` is necessary and not sufficient. Stating that plainly
is more useful than a longer list of what passed.

## One design decision: a skipped check is a failure

During the first real run, `pkg-config` was missing from the host, so the
compile step silently skipped. Had shellcheck not been complaining at the
same time, the script would have reported success, and a three hour build
would have started with the daemon never once compiled.

That is the worst behaviour a gate can have: passing by not checking.

```sh
if ! command -v pkg-config >/dev/null 2>&1; then
        echo "pkg-config is not installed. Run scripts/host-setup.sh."
        fail=1
```

A missing tool is now a failure that names the tool and the command to fix
it. The same reasoning applies to the shellcheck warnings: two of the four
were real faults, so treating warnings as advice would have meant
re-reading and re-dismissing them forever. The two that were deliberate now
carry a directive saying why.

## Verifying the kernel fragment

A configuration fragment that is quietly ignored is the classic Yocto trap.
The build succeeds. The option is absent. A driver fails on the board a week
later with no clue why.

```sh
$ ./go kconfig
ok        CONFIG_GPIO_CDEV=y
ok        CONFIG_GPIO_CDEV_V1 off
MISMATCH  CONFIG_IIO_SYSFS_TRIGGER=y   (built: not set)
```

It reads every line of `bench.cfg`, including the `# CONFIG_X is not set`
lines, and compares against the `.config` BitBake actually produced. It only
works because `RM_WORK_EXCLUDE` keeps the kernel's work directory.

**This generalises to every later project that touches the kernel.** When
you ask a build system for something, check that you got it, rather than
assuming the absence of an error means success.

## Continuous integration

CI runs rungs 1 to 3 on every push, on an Ubuntu runner, so the layer is
verified even when neither laptop is on.

It does not build the image: that needs 60 GB and three hours. The image job
is opt-in and expects a self-hosted runner with a shared sstate mirror,
which is the same arrangement a team would use. A hosted runner is honest
about what it can and cannot do, and pretending otherwise would produce a
green badge that means nothing.

For Project 4, the hardware in the loop lab, rung 5 becomes automatable: a
Pi 4 network-boots a Pi 3B+, runs a test suite over the serial console, and
reports. That is when CI can finally say something about the board.

---

Previous: [06. Mechanism and policy](06-mechanism-policy.md) | Next: [08. Board bring-up](08-board-bringup.md)
