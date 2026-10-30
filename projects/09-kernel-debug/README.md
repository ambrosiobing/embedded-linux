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

**The image is built and the first fault is measured.** As of Tuesday 6
October 2026 the debug image has been built and booted on a Raspberry Pi 3
Model B Plus Rev 1.3, the `null` fault has been triggered and decoded, and
criterion 1 in the table below carries a result rather than a blank. Eight
of the twelve rows are still blank, and they are blank because nobody has
taken those measurements yet.

Three findings came off those boots that no laptop could have produced:
the overlays named in `config.txt` were not on the card, `bench-status`
and the `gpio-led` overlay both claimed GPIO17, and KFENCE reported two
faults in the USB stack that nothing in this project injected. All three
are in the journal, and the first two are now checked by
`scripts/check-overlays.sh` and by an ownership row in `docs/DESIGN.md`.

What was proven on a laptop before any of that, and still is:

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
| [docs/hardware.md](docs/hardware.md) | The parts, from the BCM2835 register tables down to the wire, with what was decided before wiring and what was rewired afterwards |
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
| 1 | `decode_stacktrace.sh` resolves the NULL dereference to a source line in `buggy.c` | measured | met Tuesday 6 October 2026: `fault_null` at `buggy.c:109`, the line holding `victim->magic = 0x1234;`, with `x2 : 0000000000001234` in the register dump agreeing. [notebook/01](notebook/01-oops.md) |
| 2 | `/sys/fs/pstore/dmesg-ramoops-0` holds the same oops after the reboot, and the SysRq crash makes a second capture | measured | met Tuesday 6 October 2026, and **the wording describes a state the hardware cannot be left in**: the recovered record matched entry 01's block on all 46 lines, and the SysRq crash then overwrote it, because the ramoops zone cursor restarts at zone 0 on every boot. Both captures are in `docs/evidence/`. [notebook/05](notebook/05-pstore.md) |
| 3 | gdb stops at a breakpoint in `fault_null`, prints a backtrace with module symbols, and `lx-dmesg` works | measured | **blocked Tuesday 6 October 2026**, on two counts. kgdb needs the serial console, and this image enables one on a UART whose pins `disable-bt` left unmuxed; the mux is fixed and measured, and the console still produces nothing, with a second fault unidentified. And `lx-symbols` needs `scripts/gdb` generated into the kernel build directory, which Yocto does not do. [notebook/02](notebook/02-kgdb.md) |
| 4 | The irqsoff tracer reports a maximum within 5 percent of 3 s with `fault_lock` in the stack | measured | **met Friday 30 October 2026**, both clauses. **3000307 us** against a band of 2850000 to 3150000, so within 0.01 per cent of 3 s, and `fault_lock` named three times in the output: `ended at: fault_lock`, `_raw_spin_unlock_irqrestore <-fault_lock`, and the head of the stack trace above `trigger_write`. An independent witness makes the figure quotable rather than merely read: `buggy`'s own log lines at 1358.697300 and 1361.706056 give 3.008756 s, agreeing to within the printk overhead. **The first attempt failed and that is the finding.** With the tracer's default function tracing on, a three second window overruns the per-CPU buffer and the longest window it kept was **2025 us in `klogd`, ending in `console_unlock`**, which is the `dwc_otg` log storm rather than the fault. One knob, `options/function-trace` off, and nothing else, produced the correct measurement. The tool made for this fault needs configuring for the fault's magnitude ([irqsoff-2026-10-30.txt](docs/evidence/irqsoff-2026-10-30.txt)) |
| 5 | `perf report` attributes most lock-fault samples to `fault_lock` or `__delay` | measured | **criterion unreachable, measured Friday 30 October 2026, and the reason is the sharpest result in this project.** Zero of 4000 `cycles:P` samples have a program counter in `fault_lock` or `__delay`; three mention `fault_lock` in a callchain only, at the moment the interrupt mask lifts, which is also why `_raw_spin_unlock_irqrestore` tops the profile at 18.06 per cent. **The mechanism is measured, not argued**: the largest gap between consecutive samples is 0.024, 0.028 and 0.036 s on CPUs 0, 1 and 2, and **3.004 s on CPU 3**. On a Cortex-A53 the PMU interrupt is an ordinary interrupt, `fault_lock` holds `spin_lock_irqsave` throughout, and an interrupt that cannot be taken cannot carry a sample. So the fault disables the instrument the criterion names. **Three instruments now agree on one number**: the tracer's 3.000307 s, `buggy`'s own printk gap of 3.008756 s, and perf's 3.004 s silence. **A restatement is proposed and not applied**, since changing a criterion is Joseph's call: ask for the sampling gap on the affected CPU rather than for samples inside the window. One error of mine is recorded with it, that `perf record -a` took three idle CPUs along with the one that mattered ([perf-lock-2026-10-30.txt](docs/evidence/perf-lock-2026-10-30.txt)) |
| 6 | KASAN reports the use after free with allocation and free stacks | measured | |
| 7 | kmemleak lists 64 unreferenced 256-byte objects after the leak | measured | **met Friday 30 October 2026**, both numbers exactly: **64** unreferenced objects, **64** of them at size 256, matching `LEAK_OBJECTS` and `LEAK_OBJECT_SZ` in `buggy.c`. Two further confirmations that these are the criterion's objects and not some coincidental leak: the hex dump is `a5` repeated, because `fault_leak` memsets each block to `0xa5`, and the backtrace names `fault_leak+0x38/0x80 [buggy]` under `trigger_write`. Two scans with a wait between them, because kmemleak will not report an object below its minimum age and a single immediate scan returning nothing would be a false negative rather than a result. **Exactly 64 and not a multiple of it**, after the module had already been cycled ten times for criterion 9, which confirms that exit path leaks nothing and strengthens criterion 9 from a second direction. Unaffected by the `dwc_otg` log flood, since kmemleak is read from debugfs rather than the ring buffer ([kmemleak-2026-10-30.txt](docs/evidence/kmemleak-2026-10-30.txt)) |
| 8 | The debug kernel boots to a login prompt in under 40 s | measured | **met Friday 30 October 2026**, at 24.287 s against a limit of 40: 7.252 s kernel plus 17.035 s userspace. The monotonic timeline gives the criterion's own wording directly, `Reached target Login Prompts` at **21.552 s**, so both the total and the prompt itself are inside the limit. Raspberry Pi 3B+, `bench-debug-image` flashed from the archive at `proj09-bench-debug/2026-10-18_9429c89`, joined over wireless. **`systemd-analyze` is not in this image**, so the figure is systemd's own `Startup finished` journal line, which is the number that tool reads and reports. The wall clock in the same line says June, because this board has no RTC and `Reached target System Time Set` came at 19.573 s, after most of the boot; the monotonic column is the one to read ([boot-time-2026-10-30.txt](docs/evidence/boot-time-2026-10-30.txt)) |
| 9 | The module loads and unloads ten times with no warnings | measured | **met Friday 30 October 2026.** Ten cycles, no load or unload failure, nothing left in `lsmod`. The window contained 15 warning lines and a count is not a verdict, so they were read: every one is `dwc_otg` calling `disable_irq()` from hard interrupt context, reported by this kernel's atomic-sleep checking, in `swapper` rather than `modprobe`. **The control is what makes excluding them legitimate**: clearing the log and touching nothing for twenty seconds gives **60** such lines, all from `dwc` or `hcd`, a higher rate than the cycling window held, so the module produced none of them. The only module-related item is the `O` in `Tainted: G B W O`, which reports an out-of-tree module rather than a fault ([module-cycle-2026-10-30.txt](docs/evidence/module-cycle-2026-10-30.txt)). **Two findings came out of it, both bigger than the criterion**: that `dwc_otg` violation is a real defect this debug kernel caught unprompted at about one report per second, and at roughly thirty lines each it turns the ring buffer over in under a minute, which evicted `buggy`'s own init message and is a live hazard for criterion 6's KASAN dump |
| 10 | The debug fragment sets only symbols that exist and are settable | configured | verified against `rpi-6.6.y`; four corrected |
| 11 | The faulty module cannot fire at load time | configured | **met, re-verified Friday 30 October 2026** against the tree: no `KERNEL_MODULE_AUTOLOAD` assignment anywhere, only the recipe comment explaining its absence; `buggy_init` calls no fault; and all four sit behind a `strcmp` against the `faults[]` table in `trigger_write`, so each needs its keyword written by hand. The ten load and unload cycles taken for criterion 9 are the measured confirmation: loading it forty times over, counting the earlier runs, fired nothing |
| 12 | The production kernel is untouched by any of this | configured | **met, re-verified Friday 30 October 2026**: two switches, not one. `BENCH_DEBUG_KERNEL ?= "0"` gates `debug.cfg` and `BENCH_KASAN_KERNEL ?= "0"` gates `kasan.cfg`, each adding its file to `SRC_URI` only when set to 1. The separation is deliberate and the bbappend says why: a switch that gates a file gates everything in it, so one switch covering both would make every kgdb session pay 128 MB of shadow memory and a factor of two in speed. `kasan.cfg` is additive to `debug.cfg` and unusable alone, since a KASAN kernel with no symbols, console or pstore reports a use after free to nobody, which is why `kas/bench-debug-kasan.yml` sets both |

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
