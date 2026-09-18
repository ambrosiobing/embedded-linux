# The configuration rationale

The deliverable the specification asks for by name: every symbol in the
debug fragment with its cost and whether it belongs in a production
image. The fragments themselves carry the same reasoning inline; this is
the table you read when deciding what to keep.

Costs are **estimates from what each mechanism does**, not measurements.
The measured column is in the [project README](../README.md) and is blank
until a board has produced it. Where a figure is an order of magnitude
rather than a number, it says so.

## The four symbols a fragment cannot set

Before the table, the finding that came out of verifying it. Four symbols
in the original specification are **promptless**: their value comes from
whatever selects them. Writing one in a `.cfg` is legal, silent and
useless.

```
  a fragment line
        |
        v
  is the symbol prompted?
        |
        +-- yes --> merge_config sets it. It may still be dropped
        |           if its "depends on" is unmet, which is also silent,
        |           and is what ./go kconfig exists to catch.
        |
        +-- no ---> NOTHING HAPPENS. No error. No warning.
                    The symbol keeps the value its selector gives it.
                    |
                    +-- so: find the selector and ask for that instead,
                        and keep the original line as an ASSERTION, so
                        a defconfig that stops selecting it is noticed.
```

| Symbol | Where | Why it cannot be set | Ask for |
|---|---|---|---|
| `CONFIG_DEBUG_INFO` | `lib/Kconfig.debug` | bare `bool`, selected by the Debug information choice | `CONFIG_DEBUG_INFO_DWARF5` |
| `CONFIG_HW_PERF_EVENTS` | `arch/arm64/Kconfig` | `def_bool y depends on ARM_PMU` | `CONFIG_ARM_PMU` |
| `CONFIG_UPROBES` | `arch/Kconfig` | `def_bool n`, selected by `UPROBE_EVENTS` | `CONFIG_UPROBE_EVENTS` |
| `CONFIG_LOCKUP_DETECTOR` | `lib/Kconfig.debug` | bare `bool`, selected by `SOFTLOCKUP_DETECTOR` | `CONFIG_SOFTLOCKUP_DETECTOR` |
| `CONFIG_CONSOLE_POLL` | `lib/Kconfig.kgdb` | bare `bool`, selected by `KGDB_SERIAL_CONSOLE` | already correct in the spec |
| `CONFIG_LOCKDEP` | `lib/Kconfig.debug` | bare `bool`, selected by `PROVE_LOCKING` | `CONFIG_PROVE_LOCKING` |

One more is worth naming because it looks settable and is not available
at all: **`CONFIG_KGDB_LOW_LEVEL_TRAP`** is `depends on X86 || MIPS`. On
arm64 it cannot be turned on at any setting. It reads as though it would
help on this board, and an afternoon can go into it.

## The debugger

| Symbol | Cost | Production? |
|---|---|---|
| `DEBUG_KERNEL` | None by itself. It is a gate that makes other options visible. | Harmless |
| `KGDB` | Small text growth. The debugger is inert until entered. | **No.** Anyone with the console owns the kernel. |
| `KGDB_SERIAL_CONSOLE` | Selects `CONSOLE_POLL` and `MAGIC_SYSRQ`. | No, same reason |
| `KGDB_KDB` | A few tens of kB for the on-console frontend. | No |
| `KGDB_HONOUR_BLOCKLIST` | Negligible. Keeps breakpoints out of the code kgdb runs in. | Would be, if kgdb were |
| `MAGIC_SYSRQ` | Negligible code. | **Only with a restrictive mask.** The default mask is `0x1`; this fragment sets `0x1ff`, which is every function including reboot and crash. On a bench with the cable in reach that is right. On a shipped product it is a reboot key. |

The reason kgdb is not a production option is not its size. It is that
the debugger trusts whoever is on the serial line completely: attaching
gives arbitrary read and write of kernel memory with no authentication of
any kind. That is correct for a debugger and disqualifying for a product.

## Symbols and scripts

| Symbol | Cost | Production? |
|---|---|---|
| `DEBUG_INFO_DWARF5` | **The largest single cost here.** `vmlinux` goes from roughly 20 MB to well over 100 MB. | No, and it does not need to be: `vmlinux` is not on the card. The cost is build time and host disk, not image size. |
| `DEBUG_INFO_REDUCED` off | Keeps type information that reduced debug info drops. Larger again. | No |
| `GDB_SCRIPTS` | A few files next to `vmlinux`. Nothing on the target. | Free either way |
| `KALLSYMS_ALL` | A few hundred kB in the kernel image, on the target. | Plain `KALLSYMS` yes, `_ALL` usually not |

**The distinction that matters here:** debug information lives in
`vmlinux` on the host and **does not ship**. The stripped `Image` that
goes on the card is close to the same size with or without it.
`KALLSYMS_ALL` is the opposite: it is in the running kernel and is paid
for on every boot.

## Tracing

| Symbol | Cost | Production? |
|---|---|---|
| `FTRACE` | The menu gate. Nothing alone. | Gate only |
| `FUNCTION_TRACER` | **A call at the entry of every kernel function.** With `DYNAMIC_FTRACE` those are patched to no-ops until a tracer is enabled, so the runtime cost when idle is close to zero; the image grows by a few percent. | Defensible with `DYNAMIC_FTRACE`. Several distributions ship it. |
| `DYNAMIC_FTRACE` | A table of call sites. Buys back the idle cost above. | Yes, if `FUNCTION_TRACER` is on |
| `FUNCTION_GRAPH_TRACER` | Entry and exit instrumentation. | With the above |
| `IRQSOFF_TRACER` | Instruments every interrupt-disable and enable. Measurable even when idle. | **No.** This is the one that costs while nothing is tracing. |
| `PREEMPT_TRACER` | As above for preempt-disable. Needs `PREEMPTION`. | No |
| `STACK_TRACER` | Checks stack depth at each function entry when enabled. | No |
| `FTRACE_SYSCALLS` | Metadata per syscall. Small. | Defensible |
| `KPROBES`, `KPROBE_EVENTS`, `UPROBE_EVENTS` | Small text, and an arbitrary-code hook into the kernel. | **No.** Same argument as kgdb: it is a supported mechanism for running code in kernel context. |
| `BLK_DEV_IO_TRACE` | Instruments the block layer. | No |

`IRQSOFF_TRACER` is the one to argue about, because it is the only tool
in this project that finds the `lock` fault, and it is also the one whose
cost is paid whether or not anybody is tracing. That is the trade the
project exists to make visible: **the tool that finds the silent fault is
the one you cannot afford to leave on.**

## Performance counters

| Symbol | Cost | Production? |
|---|---|---|
| `PERF_EVENTS` | Moderate text. Sampling costs only while sampling. | Often yes |
| `ARM_PMU` | Driver for the hardware counters. | Yes, and without it perf silently has no cycles or cache misses, which is worse than no perf at all |

## Crash capture

| Symbol | Cost | Production? |
|---|---|---|
| `PSTORE`, `PSTORE_RAM` | A reserved RAM region, here 128 kB, plus a small write on panic. | **Yes, and it is the recommendation.** This is the cheapest useful thing in the whole fragment. |
| `PSTORE_CONSOLE` | Part of that region, continuously written. | Yes |
| `PSTORE_DEFLATE_COMPRESS` | Compression on the way in, so more fits. | Yes |
| `PANIC_ON_OOPS` | None. It changes policy, not code. | **A product decision, not a debug one.** An oops means the kernel is in an undefined state; continuing may corrupt data. For a debug lab it guarantees the crash reaches pstore. Runtime-settable through `/proc/sys/kernel/panic_on_oops`. |

`PSTORE_PMSG` is deliberately off: the Raspberry Pi ramoops overlay has no
`pmsg-size` parameter, so there is no way to give it a region from
`config.txt`. The symbol would build and the device would never appear.

## The detectors that need no trigger

| Symbol | Cost | Production? |
|---|---|---|
| `PROVE_LOCKING` (lockdep) | **Large.** Bookkeeping on every lock acquisition, and memory for the dependency graph. Order-of-magnitude slower locking. | **No.** Development and CI only. |
| `DEBUG_ATOMIC_SLEEP` | Checks for sleeping in atomic context. | No |
| `DEBUG_SPINLOCK`, `DEBUG_MUTEXES`, `DEBUG_RT_MUTEXES` | Extra state and checks per lock. | No |
| `SOFTLOCKUP_DETECTOR` | A per-CPU watchdog thread and a timer. Small. | **Yes.** Cheap, and it turns a hung box into a message. |
| `DETECT_HUNG_TASK` | Periodic scan of blocked tasks. Small. | Yes |
| `WQ_WATCHDOG` | Detects stalled workqueues. Small. | Yes |

Lockdep is the most valuable tool here per unit of effort, because it
needs no trigger and no reproduction: it reports a lock ordering that
*could* deadlock on a run where it did not. It is also among the most
expensive. That pairing is why it belongs in a debug image that gets run
regularly rather than in a build nobody exercises.

## Memory, and why the split is where it is

| Symbol | Cost | Production? |
|---|---|---|
| `DEBUG_KMEMLEAK` | Bookkeeping per allocation and a scan on demand. Significant but usable. | No |
| `KFENCE` | **Designed to be cheap.** Samples one allocation every 100 ms and guards only those. | **Yes.** This is its entire argument, and it is the answer to "we cannot afford KASAN". |
| `SLUB_DEBUG` | Off until `slub_debug=` on the command line. | Yes, since it is inert by default |
| `KASAN` | **1 byte of shadow per 8 bytes of memory.** On this 1 GB board, about 128 MB gone before userspace starts, plus roughly 2x on kernel time. | **No.** Test kernels only. |
| `KASAN_OUTLINE` | A helper call per access. Slower than inline, smaller kernel. | With KASAN |
| `KASAN_STACK`, `KASAN_VMALLOC` | More coverage, more cost. `VMALLOC` is what covers module memory, which is where this project's faults live. | With KASAN |

**This is why there are two images.** kmemleak and KFENCE are in the
ordinary debug image, so three of the four faults are reachable from one
kernel. Only `uaf` needs the KASAN image. The split is by cost, and it is
a decision about how the lab runs rather than an accident of which
symbols happen to be cheap.

`KASAN_HW_TAGS` is the cheap flavour and is **not available on this
board**: it needs `ARM64_MTE`, which is Armv8.5, and the BCM2837 is a
Cortex-A53 at Armv8.0. Worth knowing before reaching for it.

## What a production image would keep

Reading the "production?" column back, the defensible debug configuration
for something that ships is short:

```
  PSTORE + PSTORE_RAM + PSTORE_CONSOLE + PSTORE_DEFLATE_COMPRESS
  SOFTLOCKUP_DETECTOR + DETECT_HUNG_TASK + WQ_WATCHDOG
  KFENCE
  KALLSYMS (not _ALL)
  PERF_EVENTS + ARM_PMU
  SLUB_DEBUG (inert until slub_debug= is passed)
  FUNCTION_TRACER + DYNAMIC_FTRACE      <- argue about this one
```

Everything else in this fragment is a development tool, and most of them
are development tools specifically because they either cost while idle
(`IRQSOFF_TRACER`, lockdep, KASAN) or because they hand kernel-level
control to whoever reaches the console (`KGDB`, `KPROBES`, an unrestricted
SysRq mask).

---

Back to [DESIGN.md](DESIGN.md) or the [project README](../README.md).
