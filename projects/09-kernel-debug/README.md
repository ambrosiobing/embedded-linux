# Project 9: kernel debugging lab, kgdb, ftrace, perf and pstore

**Board:** Raspberry Pi 3B+. **Theme:** finding a fault with the tool made
for it, over the same USB/TTL cable the other projects use only as a
login console.

**Read this paragraph first.** This project is unlike the other nineteen:
**it produces no product.** No service, no driver, no image anyone would
ship. It produces a toolbox and a notebook. The thing being engineered is
a set of four deliberate faults and the path from each one to the tool
that exposes it, and the reason that is worth a week is in one table:

| Fault | What the kernel does when it happens |
|---|---|
| `null` | Oops, panic, reboot. Announces itself. |
| `lock` | **Nothing.** The system is three seconds late. |
| `uaf` | **Nothing, usually.** Reads the right value most times. |
| `leak` | **Nothing, ever.** Out of memory in a month. |

Three of the four produce no symptom at the moment they happen. The tool
has to be in place and understood *before* the fault, because afterwards
there is nothing to look at. That is the argument for building this
before Project 5 writes a driver and Project 8 measures latency, both of
which get easier once these workflows are in hand.

## State

**Everything is written and nothing has been run.** No image has been
built, no board has been booted, no fault has been triggered. There are no
measurements in this README, and the rows that will hold them say so.

What is proven today, on a laptop:

| Proven | How |
|---|---|
| The console splitter refuses a held device and names the pid and process | `tests/debug-proxy-test.sh`, 18 assertions |
| It refuses a missing device, a missing `agent-proxy`, and says when it could not check at all | the same suite |
| The oops decoder refuses rather than silently using the host `addr2line` on an arm64 `vmlinux` | `tests/debug-decode-test.sh`, 19 assertions |
| It passes `auto`, the modules directory and the log on stdin, and names every input it chose | the same suite |
| Both guards fire when removed and go quiet when restored | each mutated and rerun; 6 and 2 assertions failed respectively |
| Four symbols in the specification's fragment are silent no-ops | read out of the Kconfig at `rpi-6.6.y`; see below |
| `ramoops`, `gpio-led` and `disable-bt` overlays exist with the parameters used | the overlay README at `rpi-6.6.y` |
| `systemd` mounts pstore and then archives and unlinks it | `src/shared/mount-setup.c` and `systemd-pstore.service` at v255 |
| The module recipe's package is `kernel-module-buggy`, not `bench-buggy` | `module.bbclass` at scarthgap, and oe-core's own `hello-mod` |

### The finding worth carrying to other projects

The specification's kernel fragment contains **four symbols that a
fragment cannot set.** They are promptless: their value comes from
whatever selects them, and writing them in a `.cfg` produces no error, no
warning and no effect.

| Written as a request | What it actually is | Ask for this instead |
|---|---|---|
| `CONFIG_DEBUG_INFO` | bare `bool`, selected by the Debug information choice | `CONFIG_DEBUG_INFO_DWARF5` |
| `CONFIG_HW_PERF_EVENTS` | `def_bool y depends on ARM_PMU` | `CONFIG_ARM_PMU` |
| `CONFIG_UPROBES` | `def_bool n`, selected by `UPROBE_EVENTS` | `CONFIG_UPROBE_EVENTS` |
| `CONFIG_LOCKUP_DETECTOR` | bare `bool`, selected by `SOFTLOCKUP_DETECTOR` | `CONFIG_SOFTLOCKUP_DETECTOR` |

`CONFIG_CONSOLE_POLL` is a fifth of the same kind, and the specification
names it correctly as a consequence rather than a request. All six are
still written in [`debug.cfg`](../../meta-bench/recipes-kernel/linux/files/debug.cfg),
in a block labelled as assertions, so that `./go kconfig` notices if a
future defconfig stops selecting one. **A fragment is a list of requests,
and a request the kernel silently ignores looks exactly like one it
granted.**

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/debug.cfg` | The toolbox: kgdb, ftrace, perf, pstore, lockdep, kmemleak, KFENCE |
| `meta-bench/recipes-kernel/linux/files/kasan.cfg` | The expensive half, additive and on its own switch |
| `meta-bench/recipes-bench/bench-buggy/` | The layer's **first out-of-tree kernel module**, four faults behind one debugfs trigger |
| `meta-bench/recipes-core/images/bench-debug-image.bb` | `bench-image` plus the tools, and the one thing it masks |
| `kas/bench-debug.yml` and `kas/bench-debug-kasan.yml` | Two kernels, two switches, one of which is useless alone |
| `projects/09-kernel-debug/host/` | The first thing in this repository that is deliberately **in no image** |
| `tests/debug-proxy-test.sh` and `tests/debug-decode-test.sh` | 37 assertions, no board and no cable |
| `projects/09-kernel-debug/docs/figures/` | Seven TikZ drawings, each compiling on its own |

## Running it

```sh
./go lint                    # static checks, no Yocto host needed
sh tests/debug-proxy-test.sh
sh tests/debug-decode-test.sh
```

On the **build laptop (WSL)**:

```bash
./go debug
```

```bash
./go debug-kasan
```

```bash
./go flash /dev/sdX
```

On the **authoring laptop (Windows)**, once the card is in the board and
the cable is in the laptop:

```bash
./go proxy /dev/ttyUSB0
```

Then a terminal on port 5550 and gdb on 5551. The full sequence, with
what each step should print, is in
[docs/BRINGUP.md](docs/BRINGUP.md).

## Documents

| File | What |
|---|---|
| [docs/DESIGN.md](docs/DESIGN.md) | The drawings, the ownership table, and the fault matrix |
| [docs/CONFIG-RATIONALE.md](docs/CONFIG-RATIONALE.md) | Every symbol, its cost, and whether it belongs in production |
| [docs/BRINGUP.md](docs/BRINGUP.md) | First boot, in order, with the checks that catch the silent failures |
| [notebook/](notebook/) | Six entries, one per fault and tool, with raw output |
| [JOURNAL.md](JOURNAL.md) | What was decided and why |

## Acceptance criteria

Measured rows are blank until a board has produced them. A blank is
honest; a number that was never measured is a claim the first careful
reader will check.

| # | Criterion | Kind | Status |
|---|---|---|---|
| 1 | `decode_stacktrace.sh` resolves the NULL dereference to a source line in `buggy.c` | measured | |
| 2 | `/sys/fs/pstore/dmesg-ramoops-0` holds the same oops after the reboot, and the SysRq crash makes a second capture | measured | |
| 3 | gdb stops at a breakpoint in `fault_null`, prints a backtrace with module symbols, and `lx-dmesg` works | measured | |
| 4 | The irqsoff tracer reports a maximum within 5 percent of 3 s with `fault_lock` in the stack | measured | |
| 5 | `perf report` attributes most lock-fault samples to `fault_lock` or `__delay` | measured | |
| 6 | KASAN reports the use after free with allocation and free stacks | measured | |
| 7 | kmemleak lists 64 unreferenced 256-byte objects after the leak | measured | |
| 8 | The debug kernel boots to a login prompt in under 40 s | measured | |
| 9 | The module loads and unloads ten times with no warnings | measured | |
| 10 | The debug fragment sets only symbols that exist and are settable | configured | verified against `rpi-6.6.y`; four corrected |
| 11 | The faulty module cannot fire at load time | configured | no `KERNEL_MODULE_AUTOLOAD`, every fault behind an explicit keyword |
| 12 | The production kernel is untouched by any of this | configured | both fragments behind `?= "0"` switches |

### Criterion 2 needs a note, and it is the most useful thing here

As specified, criterion 2 **would have failed on a stock image**, and not
because ramoops was broken.

`systemd` mounts `/sys/fs/pstore` itself, and then
`systemd-pstore.service` copies every record to `/var/lib/systemd/pstore/`
and **deletes it**: `Storage=external` and `Unlink=yes` are the
compile-time defaults, and the unit runs `Before=sysinit.target`, so it
has finished long before a login prompt. The Raspberry Pi overlay README
says the same thing in one line.

So you reboot after a panic, look in `/sys/fs/pstore`, find it empty, and
conclude ramoops is not working. It is working; something else got there
first and took the evidence with it.

`bench-debug-image` masks that unit, and says why in the recipe. **Two
managers on one resource**, found by writing the ownership table before
the recipes, which is the whole reason that table is written first.

## Going further

The specification's stretch goals, with what each would cost here:

- **kdb without a host.** Already built in (`CONFIG_KGDB_KDB`), so this is
  a notebook entry rather than a build.
- **`bpftrace` on `trigger_write`.** Needs BTF and a bigger kernel;
  `CONFIG_DEBUG_INFO_BTF` is not set today.
- **kexec and `crash` instead of ramoops.** Deliberately not built. The
  kexec path interacts with the reserved ramoops region and the firmware
  boot flow, and a half-working crash dump is worse than a pstore that
  works. `kexec-tools` is **not** in the image for that reason.
- **The KASAN kernel on the Pi 4** from Project 8, to price the shadow
  memory against a board with more of it.
