# 01: the NULL dereference, read off the console

**Status: NOT YET RUN.** No board has produced the output below.

## Symptom

The board prints a page of register dump and reboots ten seconds later.
If the terminal was not logging, there is nothing left at all.

This is the easy fault and it is first for exactly that reason: it is the
only one of the four that announces itself, so it is what proves the
toolchain works before the three silent faults need it.

## Tool, and why this one

The console plus `decode_stacktrace.sh`. An oops contains addresses. An
address is not a location until something resolves it against the build
that produced it, and doing that by hand with `addr2line` for each frame
is the slow version of the same thing.

## Commands

**On the board over the picocom console**, with the terminal logging:

```sh
sudo modprobe buggy
echo null | sudo tee /sys/kernel/debug/buggy/trigger
```

**On the authoring laptop (Windows)**, against the log the terminal kept:

```bash
./projects/09-kernel-debug/host/decode.sh vmlinux oops.log ./modules
```

The third argument is the directory holding `buggy.ko`. Without it the
frames inside the module stay unresolved, and the script says so rather
than leaving you to notice.

## Raw output

Tool versions:

```
NOT YET RUN
```

The raw oops, as logged:

```
NOT YET RUN
```

The same trace, decoded:

```
NOT YET RUN
```

## Conclusion

To be written once the above is real. The claim it should support is
acceptance criterion 1: the decoded trace names a source line in
`buggy.c`, and specifically `fault_null`.

## What to check while you are here

- **Does the fault address match the direction?** `fault_null` writes
  rather than reads, so the oops should say a write at address 0. If it
  says a read, something other than what you think is faulting.
- **Did the heartbeat LED go dark?** It should, at the panic, and stay
  dark until the reboot.
- **Is the pstore copy there afterwards?** That is entry
  [05](05-pstore.md), and it is the same crash seen from a board that has
  already restarted.

## The mistake this entry exists to make once, cheaply

Decoding against the wrong `vmlinux`. It does not fail. It produces a
backtrace with plausible function names from the other build, and there
is nothing in the output that says so. If the decoded names look odd, the
first suspect is the symbol file, not the kernel.
