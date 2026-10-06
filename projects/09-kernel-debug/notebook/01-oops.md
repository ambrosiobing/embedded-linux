# 01: the NULL dereference, read off the console

**Status: RUN on Tuesday 6 October 2026**, on a Raspberry Pi 3 Model B
Plus Rev 1.3 running the image archived as `2026-10-05_a743c9c`. Every
block below is real console text.

## Symptom

The board prints a page of register dump and stops. Whether it then
reboots is a setting, and the one this image shipped with is covered
under "what the run corrected" below. If the terminal was not logging,
there is nothing left at all.

This is the easy fault and it is first for exactly that reason: it is the
only one of the four that announces itself, so it is what proves the
toolchain works before the three silent faults need it.

## Tool, and why this one

The console plus `decode_stacktrace.sh`. An oops contains addresses. An
address is not a location until something resolves it against the build
that produced it, and doing that by hand with `addr2line` for each frame
is the slow version of the same thing.

## Commands

**On JPTOUPM678, WSL bash**, before anything is triggered. The console is
the only place a panic prints, so this has to be running first:

```sh
picocom --baud 115200 --logfile /home/bing/proj09-oops-$(date +%F-%H%M).log /dev/ttyUSB0
```

**On the board**, over ssh, which keeps the console clean for the panic:

```sh
sysctl -w kernel.panic=10
rm -f /sys/fs/pstore/*
modprobe buggy
echo null > /sys/kernel/debug/buggy/trigger
```

The ssh session dies on the last line. That is the expected result.

**On JPTOUPM678, WSL bash**, against the log picocom kept:

```sh
sed -n '/Unable to handle kernel NULL pointer/,/end trace/p' <logfile> > oops.txt
./projects/09-kernel-debug/host/decode.sh <vmlinux> oops.txt <dir holding buggy.ko>
```

The third argument is the directory holding `buggy.ko`, and it must be the
unstripped one from the BitBake work directory, not the `.ko.xz` under
`package/` or `image/`. Without it the frames inside the module stay
unresolved, and the script says so rather than leaving you to notice.

## Raw output

Tool versions:

```
kernel      6.6.63-v8, as the oops banner below reports it
addr2line   GNU addr2line (GNU Binutils) 2.42.0.20240723
            from the kernel recipe's own recipe-sysroot-native
picocom     v3.1
decoder     scripts/decode_stacktrace.sh, from the kernel source tree that
            produced the vmlinux it was given
```

The raw oops, as logged. This block was checked line by line against
`docs/evidence/pstore-2026-10-06-dmesg-ramoops-0.txt`, the copy ramoops
kept in DRAM across the reboot, and the two agree on all 46 lines of the
oops. They did not at first: the `Code:` line ends with a trailing space
that the kernel emits and the clipboard path dropped, so the block below
was one byte short until Tuesday 6 October 2026. A difference that does
not render is the one a reader cannot catch by eye, which is the argument
for keeping the pstore copy as a file rather than only quoting it.


```
[ 2057.431067] buggy: triggering null
[ 2057.435145] buggy: about to dereference 0000000000000000
[ 2057.441807] Unable to handle kernel NULL pointer dereference at virtual address 0000000000000000
[ 2057.450912] Mem abort info:
[ 2057.453903]   ESR = 0x0000000096000045
[ 2057.457844]   EC = 0x25: DABT (current EL), IL = 32 bits
[ 2057.463360]   SET = 0, FnV = 0
[ 2057.466521]   EA = 0, S1PTW = 0
[ 2057.469838]   FSC = 0x05: level 1 translation fault
[ 2057.474951] Data abort info:
[ 2057.477967]   ISV = 0, ISS = 0x00000045, ISS2 = 0x00000000
[ 2057.483625]   CM = 0, WnR = 1, TnD = 0, TagAccess = 0
[ 2057.488853]   GCS = 0, Overlay = 0, DirtyBit = 0, Xs = 0
[ 2057.494359] user pgtable: 4k pages, 39-bit VAs, pgdp=0000000007a90000
[ 2057.501008] [0000000000000000] pgd=0000000000000000, p4d=0000000000000000, pud=0000000000000000
[ 2057.511190] Internal error: Oops: 0000000096000045 [#1] PREEMPT SMP
[ 2057.518371] Modules linked in: buggy(O) brcmfmac_wcc brcmfmac brcmutil cfg80211 rfkill sch_fq_codel ipv6
[ 2057.529617] CPU: 0 PID: 372 Comm: sh Tainted: G    B   W  O       6.6.63-v8 #1
[ 2057.537718] Hardware name: Raspberry Pi 3 Model B Plus Rev 1.3 (DT)
[ 2057.544854] pstate: 60000005 (nZCv daif -PAN -UAO -TCO -DIT -SSBS BTYPE=--)
[ 2057.552715] pc : fault_null+0x3c/0x60 [buggy]
[ 2057.557981] lr : fault_null+0x2c/0x60 [buggy]
[ 2057.563242] sp : ffffffc083813c60
[ 2057.567456] x29: ffffffc083813c60 x28: ffffff8008588000 x27: 0000000000000000
[ 2057.575521] x26: 0000000000000000 x25: 0000000000000000 x24: ffffffc07ae223b0
[ 2057.583595] x23: ffffffc07ae22278 x22: ffffffc083813c88 x21: 0000000000000005
[ 2057.591659] x20: ffffffc07ae223b0 x19: ffffffc07ae20000 x18: 0000000000000006
[ 2057.599714] x17: 0000000000000020 x16: 0000000000000002 x15: 0000000000000028
[ 2057.607755] x14: 0000000000000001 x13: 000000000000de89 x12: 0000000000000000
[ 2057.615781] x11: ffffffc0826e393c x10: ffffffc081591c74 x9 : ffffffc08013e43c
[ 2057.623804] x8 : ffffffc083813888 x7 : 0000000000000000 x6 : 0000000000000001
[ 2057.631835] x5 : ffffffc0819d5000 x4 : ffffffc0819d5440 x3 : 0000000000000000
[ 2057.639874] x2 : 0000000000001234 x1 : 0000000000000000 x0 : ffffffc07ae22028
[ 2057.647913] Call trace:
[ 2057.651216]  fault_null+0x3c/0x60 [buggy]
[ 2057.656121]  trigger_write+0x16c/0x190 [buggy]
[ 2057.661456]  full_proxy_write+0x68/0xc8
[ 2057.666179]  vfs_write+0xd0/0x320
[ 2057.670348]  ksys_write+0x7c/0x120
[ 2057.674605]  __arm64_sys_write+0x24/0x38
[ 2057.679378]  invoke_syscall+0x50/0x128
[ 2057.683968]  el0_svc_common.constprop.0+0xc8/0xf0
[ 2057.689499]  do_el0_svc+0x24/0x38
[ 2057.693613]  el0_svc+0x50/0xf8
[ 2057.697440]  el0t_64_sync_handler+0x120/0x130
[ 2057.702557]  el0t_64_sync+0x190/0x198
[ 2057.706949] Code: f942e261 d2824682 90000020 9100a000 (f9000022) 
[ 2057.713783] ---[ end trace 0000000000000000 ]---
[ 2057.724969] pstore: backend (ramoops) writing error (-28)
[ 2057.731100] Kernel panic - not syncing: Oops: Fatal exception
[ 2057.737559] SMP: stopping secondary CPUs
[ 2057.742207] Kernel Offset: disabled
[ 2057.752445] Memory Limit: none
[ 2057.761920] Rebooting in 10 seconds..
```

The same trace, decoded. Only the frames are quoted; the register block
and the preamble come through unchanged:

```
decode.sh: stripped    46 carriage returns, a serial capture

[ 2057.552715] pc : fault_null (/usr/src/debug/bench-buggy/0.1/buggy.c:109) buggy
[ 2057.557981] lr : fault_null (/usr/src/debug/bench-buggy/0.1/buggy.c:109) buggy
[ 2057.647913] Call trace:
[ 2057.651216] fault_null (/usr/src/debug/bench-buggy/0.1/buggy.c:109) buggy
[ 2057.656121] trigger_write (/usr/src/debug/bench-buggy/0.1/buggy.c:235) buggy
[ 2057.661456] full_proxy_write (fs/debugfs/file.c:244 (discriminator 1))
[ 2057.666179] vfs_write (fs/read_write.c:582)
[ 2057.670348] ksys_write (fs/read_write.c:637)
[ 2057.674605] __arm64_sys_write (fs/read_write.c:646)
[ 2057.679378] invoke_syscall (arch/arm64/include/asm/current.h:19 arch/arm64/kernel/syscall.c:56)
[ 2057.683968] el0_svc_common.constprop.0 (arch/arm64/kernel/syscall.c:141)
[ 2057.689499] do_el0_svc (arch/arm64/kernel/syscall.c:154)
[ 2057.693613] el0_svc (arch/arm64/include/asm/daifflags.h:28 arch/arm64/kernel/entry-common.c:133 arch/arm64/kernel/entry-common.c:144 arch/arm64/kernel/entry-common.c:679)
[ 2057.697440] el0t_64_sync_handler (arch/arm64/kernel/entry-common.c:697)
[ 2057.702557] el0t_64_sync (arch/arm64/kernel/entry.S:599)
```

## Conclusion

**Acceptance criterion 1 is met.** The decoded trace names a source line
in `buggy.c`, and the function is `fault_null`:

    fault_null (/usr/src/debug/bench-buggy/0.1/buggy.c:109) buggy

`buggy.c:109` is `victim->magic = 0x1234;`, which is the write the module
exists to perform.

Three things in the raw oops agree with that line, and the agreement is
what makes the decode trustworthy rather than merely plausible:

| In the oops | In the source |
|---|---|
| `WnR = 1`, a write not a read | the module writes deliberately, and says why in a comment |
| fault address `0000000000000000` | `victim` is never assigned |
| `x2 : 0000000000001234` | the constant on line 109 is `0x1234` |

That third row is the one worth keeping. This entry warns below about
decoding against the wrong `vmlinux`, which produces plausible names and
says nothing. A different build would not have put `0x1234` in a register,
so the constant in the register file is independent evidence that the
symbols and the running kernel are the same build.

What would have been missed without the tool: the function name is in the
raw trace already, so the tool is not what tells you it was `fault_null`.
What it adds is the line, and with it the difference between knowing which
function faulted and knowing which statement did. In a function of three
statements that is a small gain. In `trigger_write` it is the whole
answer.

## What the run corrected in this entry

Four things this document said before Tuesday 6 October 2026 that the run
showed to be wrong.

**The decode does not run on the authoring laptop.** It was written as
"on the authoring laptop (Windows)". aquamarine has no aarch64 binutils
and no kernel source tree, and `decode.sh` refuses without both. It runs
on JPTOUPM678, where the BitBake work directory holds the `vmlinux`, the
unstripped `buggy.ko` and `scripts/decode_stacktrace.sh`.

**There is no `sudo` on this image.** The commands said `sudo modprobe`
and `sudo tee`. The board's only account is root and `debug-tweaks`
leaves it without a password, so the `sudo` is noise at best.

**The LED freezes, it does not go dark.** The check below used to ask
whether the heartbeat LED went dark at the panic. At `SMP: stopping
secondary CPUs` the timer driving the trigger stops, so the LED holds
whatever brightness it had at that instant. It usually looks dark because
heartbeat is off most of the time, and `DESIGN.md` already had the right
word in its sequence figure: it freezes.

**The board did not reboot on its own, and that was a configuration gap.**
`debug.cfg` sets `CONFIG_PANIC_ON_OOPS=y` and explains that this is what
gets the oops written to pstore rather than merely printed. Nothing sets a
panic timeout, so the board read `panic_on_oops 1` and `panic 0`: it
panics and halts. A halted Raspberry Pi 3B+ can only be restarted by
pulling the power, which is a cold cycle, and the ramoops region is
ordinary DRAM. The run set `kernel.panic=10` first, so the board rebooted
itself warm and the records survived.

## What to check while you are here

- **Does the fault address match the direction?** `fault_null` writes
  rather than reads, so the oops should say a write at address 0. On this
  run: `WnR = 1` and address `0000000000000000`. If it says a read,
  something other than what you think is faulting.
- **Did the heartbeat LED freeze?** It should, at the panic, and stay
  frozen until the reboot restarts the trigger.
- **Is the pstore copy there afterwards?** That is entry
  [05](05-pstore.md), and it is the same crash seen from a board that has
  already restarted. On this run, after the reboot:

```
-r--r--r--    1 root     root         32756 console-ramoops-0
-r--r--r--    1 root     root         27281 dmesg-ramoops-0
-r--r--r--    1 root     root         27240 dmesg-ramoops-1
```

  Note that the oops itself contains `pstore: backend (ramoops) writing
  error (-28)`, which is `ENOSPC`, and yet two dmesg records exist. One
  write failed among several that succeeded, which is not the same thing as
  ramoops having failed. The two records read about 27 kB each, and whether
  that exceeds a single record has not been checked: the region and its
  record size come from the ramoops overlay in the Raspberry Pi tree, which
  this repository does not carry and `debug.cfg:137` says so explicitly.
  Reconciling the `-28` against that geometry is entry 05's work, not this
  entry's.

## A frame that looks like an off-by-one and is not

`trigger_write` decodes to `buggy.c:235`, which is `return len;`. The call
is on line 234, `faults[i].fn();`. That frame holds a **return address**,
which points at the instruction after the call, so it resolves to the
following line. Every frame below the faulting one in any backtrace has
this property. It is worth knowing before you spend ten minutes deciding
the symbols are wrong.

## The mistake this entry exists to make once, cheaply

Decoding against the wrong `vmlinux`. It does not fail. It produces a
backtrace with plausible function names from the other build, and there is
nothing in the output that says so. If the decoded names look odd, the
first suspect is the symbol file, not the kernel. The `0x1234` in `x2` is
how this run ruled it out.

## And the one this run made, which cost an hour

The first decode resolved every kernel frame perfectly and neither module
frame, reporting:

```
WARNING! Modules path isn't set, but is needed to parse this symbol
fault_null+0x3c/0x60 buggy]
```

The modules path was set, `decode.sh` printed it, the directory was right
and the module in it was unstripped. Three hypotheses were formed and all
three were wrong, each from reading part of the problem instead of running
it. Tracing the parser with `bash -x` answered it in one line:

```
module=$'[buggy]\r'
module=$'buggy]\r'
find <modpath> -name $'buggy]\r.ko*'
```

A serial console emits CRLF and picocom records the stream verbatim, so
every line ends `\r\n`. `decode_stacktrace.sh` takes the module name from
the last token by stripping a leading `[` and a trailing `]`, and a
carriage return sitting after the `]` makes that second strip match
nothing. Kernel frames are unaffected because their last token has no
brackets, so the output looks almost right and only the frames the oops
was caused for are missing.

`decode.sh` now strips carriage returns before the parser sees the log and
reports how many it removed. The lesson generalises past this script: the
only way a log reaches the host on this bench is a serial capture, so CRLF
is the normal case and not an edge one.
