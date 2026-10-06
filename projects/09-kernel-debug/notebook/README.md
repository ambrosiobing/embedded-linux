# The notebook

Six entries, one per fault and tool. This directory is the deliverable:
the project produces no product, and what it leaves behind is these files
with real console output in them.

**Three of the six have been run**, all on Tuesday 6 October 2026 except
where noted: [01](01-oops.md) and [05](05-pstore.md) in full, and part
four of [06](06-lockdep-kasan.md), which carries real KFENCE reports from
two boots. Each says so in its first line. Entries 03 and 04, and parts one to
three of 06, are empty and marked `NOT YET RUN`.

[02](02-kgdb.md) is **blocked rather than merely unrun**, and says why in
its first paragraph. It is the only one of the six that needs the serial
console, and this image enables a console on a UART whose pins
`disable-bt` left unmuxed. The mux is fixed and measured; the console
still produces nothing, and a second fault is unidentified. Entries 03,
04 and 06 need only ssh and a board that is up. An empty block is honest. A plausible-looking block written
from expectation would be the single worst thing this repository could
contain, because the whole point of the project is learning to tell a
real report from a tool that found nothing.

| Entry | Fault | Tool | The thing it teaches |
|---|---|---|---|
| [01-oops.md](01-oops.md) | `null` | console, `decode.sh` | An address is not a location until something resolves it |
| [02-kgdb.md](02-kgdb.md) | `null` | gdb, live | What the registers held, which no log can tell you |
| [03-ftrace.md](03-ftrace.md) | `lock` | irqsoff tracer | Finding a fault that produces no message at all |
| [04-perf.md](04-perf.md) | `lock` | `perf record` | Where the time went, which is a different question |
| [05-pstore.md](05-pstore.md) | `null`, SysRq `c` | ramoops | Evidence from a board that has already rebooted |
| [06-lockdep-kasan.md](06-lockdep-kasan.md) | `uaf`, `leak` | KASAN, kmemleak, lockdep | Faults with no symptom, ever |

## The format each entry follows

Fixed on purpose, because the value of a notebook is in comparing entries:

1. **Symptom.** What you would see if you did not know what you did.
2. **Tool, and why that one.**
3. **Exact commands**, copy-pasteable, labelled by which machine.
4. **Raw output**, not a paraphrase, with the tool's version.
5. **Conclusion**, and what would have been missed without the tool.

Rule five is the one worth keeping: **every finding is recorded with the
tool version, the exact command and the raw output.** A paraphrase of a
KASAN report is worth nothing six months later, because the detail you
will want is the one you did not think was interesting.

## Before each entry

Clear pstore, so an old record cannot be mistaken for a new one. There is
no `sudo` on this image and no password on root, so the commands in these
entries are written without it:

```sh
rm -f /sys/fs/pstore/*
```

Make sure the terminal is logging to a file before anything is triggered.
`panic_on_oops` is set and no panic timeout is, so the board reads
`panic_on_oops 1` and `panic 0` and **halts** rather than rebooting. An
unlogged session therefore loses the oops permanently, and the only way to
restart a halted board is to pull the power, which is a cold cycle that
also loses the ramoops region. Setting the timeout first is what gets the
board back warm with its records intact:

```sh
sysctl -w kernel.panic=10
```

That is a runtime setting. `CONFIG_PANIC_TIMEOUT` is set nowhere in this
layer, so it has to be typed on every boot until it is.
