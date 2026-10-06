# 02: the same fault, live under gdb

**Status: BLOCKED on Tuesday 6 October 2026, not merely unrun.** No board
has produced the output below, and two things stand in the way that the
rest of the notebook does not share.

**The serial console has never worked on this image.** kgdb speaks the gdb
remote protocol over `ttyAMA0`, so this is the one entry of the six that
cannot be driven over ssh. `disable-bt` blanks `uart0_pins` and leaves the
real pin values to firmware that does not supply them, so `ttyAMA0` has
been an enabled console with an unmuxed transmit pin. Adding
`dtoverlay=uart0,txd0_pin=14,rxd0_pin=15,pin_func=4` fixes the mux,
measured as `pin 14 (gpio14): 3f201000.serial ... function alt0`, and the
console still produced nothing on the host. A second fault remains between
a correctly muxed GPIO14 and the laptop, with the USB adapter and both
signal leads already cleared by a loopback test. `kas/bench-debug.yml`
carries the measurements.

**`lxmod` cannot work as written.** It is `lx-symbols .`, and the `lx-`
commands need `scripts/gdb/linux/constants.py` generated into the kernel
build directory. Yocto does not run the `scripts_gdb` target, and
`ls scripts/gdb` in that directory fails. The mechanism underneath is
`add-symbol-file buggy.ko <addr>` with the address from
`/sys/module/buggy/sections/.text` on the board, which needs none of it,
and this entry should document both once it can run.

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

**On JPTOUPM678, WSL bash**, first. Not aquamarine: this takes a
`/dev/ttyUSB0`, and the serial adapter, the cross `gdb` and the
`vmlinux` are all on that laptop.

```bash
./go proxy /dev/ttyUSB0
```

**On the board over the picocom console** (port 5550), put the kernel in
the debugger:

```sh
echo g > /proc/sysrq-trigger
```

`kernel.sysrq` on this image reads `16`, the sync command alone, and that
does not matter: `/proc/sysrq-trigger` does not consult the mask at all.
Measured in entry [05](05-pstore.md) with a harmless control before
anything irreversible depended on it. So `g` works as written, and
nothing needs raising first.

The heartbeat LED freezes here. That is the confirmation the kernel has
actually stopped, available before gdb says anything. Freezes rather than
goes dark: the trigger's timer stops with the kernel, so the LED holds
whatever brightness it had at that instant, and since heartbeat is off
most of the time it usually looks dark.

**On JPTOUPM678, WSL bash**, in the directory holding `vmlinux`:

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
echo null > /sys/kernel/debug/buggy/trigger
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
