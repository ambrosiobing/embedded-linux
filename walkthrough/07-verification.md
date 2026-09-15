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
| State machine | Seven status cases, against a fake `systemctl` |
| WiFi provisioning | Seven cases over credentials written on Windows: CRLF endings, a byte order mark, a missing final newline, missing fields, file permissions |
| Host compile | Three C programs built with `-Wall -Wextra -Werror` against real libgpiod v2 headers |
| Edge timing arithmetic | Project 8's period recovery against a synthesised square wave whose edge times are known before the program runs, in both the resolved and the unresolved edge regime |
| Run protocol | The measurement order, core confinement, an isolation claim checked against the kernel in both directions, the throttle gate, and an overrun voiding a run |
| Interrupt affinity | A movable interrupt that was not moved, told apart from a per-CPU timer that cannot be |

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
| The hardware | Whether output values reach the pins as voltages. Still unverified: the bench LED modules cannot be connected with the cables available | the board, deferred |

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
lines, and compares against a real `.config`. Which one it reads turned out
to matter, and the next section is about that.

**This generalises to every later project that touches the kernel.** When
you ask a build system for something, check that you got it, rather than
assuming the absence of an error means success.

Project 8 is where that stopped being a precaution. `CONFIG_PREEMPT_RT`
depends on `ARCH_SUPPORTS_RT`, which `arch/arm64` gained in 6.12, and the
BSP default on this release is 6.6. A fragment asking for it on 6.6 names a
symbol that has no prompt: kconfig drops it without a word, the build
succeeds, and the board boots a kernel that is not preemptible. Nothing
anywhere says so except the check, `/sys/kernel/realtime`, and a latency
histogram that looks disappointing for reasons nobody would guess.

That is also why `rt.cfg` names the other three members of the preemption
choice as explicitly off. A fragment that only states what it wants gives
the checker nothing to notice when the kernel quietly chose something
else.

## What the kernel check taught us about checks

`./go kconfig` originally read the `.config` from the build tree, protected
by `RM_WORK_EXCLUDE`. That works only when the build actually compiled the
kernel. After a build directory was deleted and every subsequent build was a
complete shared-state hit, the kernel was never compiled, no work directory
existed, and the check had nothing to read.

The fix was to move the evidence closer to the truth. `CONFIG_IKCONFIG_PROC`
puts the running kernel's own configuration at `/proc/config.gz`, and
`./go kconfig /tmp/config` verifies against that. The claim goes from "the
fragment reached a build directory" to "the fragment reached the kernel this
board is executing", which is both stronger and permanent.

A smaller instance of the same thing: `systemd-analyze` is not in the image,
so the boot-time criterion looked unmeasurable. systemd logs the figure to
its own journal at the end of startup, so the number was already there. The
tool was missing; the measurement was not.

**The pattern worth taking:** when a check cannot run, ask whether the
evidence exists somewhere better, before adding machinery to recreate the
place it used to live.

## Continuous integration

CI runs rungs 1 to 3 on every push, so the layer is verified even when
neither laptop is on.

Two things about that runner were learned the hard way, over thirteen
consecutive failures nobody read.

**It is pinned to `ubuntu-24.04`, not `ubuntu-latest`.** A floating runner
image is a moving dependency in exactly the way a git branch is, and this
repository's entire rule is to name the version.

**libgpiod is built from tag `v2.1.3` rather than installed from apt.** No
Ubuntu LTS packages libgpiod v2: 24.04 ships 1.6.3, and v2 only arrived in
24.10. The daemon targets v2, so the check compiled against the wrong major
version and produced forty lines of implicit-declaration errors. The step
now prints the version and fails with one sentence if it is not 2.x, rather
than with a wall of symbol errors.

The job also discovers the files it checks, by shebang and by extension,
rather than naming them. A hand-maintained list is a list that new files do
not join, and the failure is silent: the check passes because it never
looked.

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
