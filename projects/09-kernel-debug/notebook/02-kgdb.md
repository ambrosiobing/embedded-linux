# 02: the same fault, live under gdb

**Status: NOT YET RUN.** No board has produced the output below.

## Symptom

The same NULL dereference as entry [01](01-oops.md). The difference is
not the fault, it is the question: entry 01 asks *where* it happened,
this one asks *what the registers held when it did*. No log can answer
the second, because by the time there is a log the state is gone.

## Tool, and why this one

kgdb, through agent-proxy. The board is stopped rather than dead, so
every variable is readable and the faulting instruction has not executed
yet when the breakpoint hits.

## Commands

**On the authoring laptop (Windows)**, first:

```bash
./go proxy /dev/ttyUSB0
```

**On the board over the picocom console** (port 5550), put the kernel in
the debugger:

```sh
echo g | sudo tee /proc/sysrq-trigger
```

The heartbeat LED freezes here. That is the confirmation the kernel has
actually stopped, available before gdb says anything.

**On the authoring laptop (Windows)**, in the directory holding `vmlinux`:

```bash
gdb-multiarch -x projects/09-kernel-debug/host/gdbinit vmlinux
```

Then, at the gdb prompt:

```
kgdb
lxmod
break fault_null
continue
```

**On the board over the picocom console**, in the other window:

```sh
echo null | sudo tee /sys/kernel/debug/buggy/trigger
```

Back at the gdb prompt, when it stops:

```
bt
info registers
print victim
lx-dmesg
```

## Raw output

Tool versions:

```
NOT YET RUN
```

The session:

```
NOT YET RUN
```

## Conclusion

To be written. The claim it should support is acceptance criterion 3:
gdb stops in `fault_null`, the backtrace carries module symbols, and
`lx-dmesg` works. `print victim` should show `0x0`, which is the whole
difference between reading a backtrace and seeing the cause.

## Things that go wrong here, in the order they usually do

| Symptom | Cause |
|---|---|
| gdb connects and every frame is a raw address | `lxmod` not run, so `buggy.ko` symbols are not loaded. Looks like a corrupted stack; is not. |
| gdb times out connecting | The board is not in the debugger. The LED tells you before gdb does. |
| Garbage on the console, or gdb complains about packets | A terminal is on `/dev/ttyUSB0` directly instead of on port 5550. Two programs, one cable. |
| Symbols resolve to the wrong functions | A `vmlinux` from a different build. Silent, and the reason `nokaslr` is on the command line. |
| `/sys/module/kgdboc/parameters/kgdboc` is empty | kgdboc never attached. See BRINGUP step 4. |

## Worth trying while you are stopped

`CONFIG_KGDB_KDB` is built in, so the board also has kdb, which needs no
host at all. From the console, the SysRq break followed by `g` drops into
a kdb prompt instead. Comparing what kdb can do (`bt`, `ps`, `md`) with
what gdb can do (source lines, structure members, expressions) is the
stretch goal the specification names, and it is a paragraph here rather
than a separate build.
