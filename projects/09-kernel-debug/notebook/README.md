# The notebook

Six entries, one per fault and tool. This directory is the deliverable:
the project produces no product, and what it leaves behind is these files
with real console output in them.

**Nothing here has been run yet.** Every output block is empty and marked
`NOT YET RUN`. An empty block is honest. A plausible-looking block written
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

Clear pstore, so an old record cannot be mistaken for a new one:

```sh
sudo rm -f /sys/fs/pstore/*
```

And make sure the terminal is logging to a file. `panic_on_oops` with a
ten second timeout means an unlogged session loses the oops you just
caused, and the board reboots before you finish reading it.
