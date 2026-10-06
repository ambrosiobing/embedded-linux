# 05: the crash nobody was watching

**Status: RUN on Tuesday 6 October 2026**, on a Raspberry Pi 3 Model B
Plus Rev 1.3 running the image archived as `2026-10-05_a743c9c`. Both
captures this entry needs were taken, and the run changed four things
this file used to say.

## Symptom

The board rebooted. You were not at the terminal, or the terminal was not
logging, and the oops scrolled past. This is the ordinary case rather
than the exception: a crash you were watching is a lucky crash.

## Tool, and why this one

ramoops, through pstore. A reserved region of ordinary DRAM keeps its
contents across a warm reset, so the kernel writes its last messages
there on the way down and the next boot can read them.

The region is not configured by the kernel fragment. It comes from the
`ramoops` device tree overlay in `config.txt`, because its address has to
be memory the page allocator never touches, and that is a property of the
board's memory map rather than of the kernel.

## Commands

There is no `sudo` on this image and root has no password, so none of
these carry one.

**Copy first.** This is not tidiness. The run below establishes that the
first crash after any reboot overwrites `dmesg-ramoops-0`, so a second
crash destroys the record of the first one. Whatever is already in
`/sys/fs/pstore` comes off the board before anything new is triggered.
**On JPTOUPM678, WSL bash**, because its redirection passes bytes through
unchanged where PowerShell's rewrites line endings:

```sh
for f in console-ramoops-0 dmesg-ramoops-0 dmesg-ramoops-1; do
	ssh root@BOARD "cat /sys/fs/pstore/$f" > EVIDENCE/$f.txt
done
wc -c EVIDENCE/*
```

Reading a pstore file does not unlink it, so this leaves the board as it
was. Compare the byte counts against `ls -l` on the board before going
on; that comparison is the gate.

**Then the crash**, over ssh, which needs no serial console because the
whole point is that nobody is watching:

```sh
sysctl -w kernel.panic=10
echo c > /proc/sysrq-trigger
```

The two are one operation and belong in one command. With `panic` at `0`,
which is what this image boots with, the board **halts** instead of
rebooting, the only way to restart it is to pull the power, and a cold
power cycle clears the DRAM region. The crash would then destroy the
record it just wrote. See entry [01](01-oops.md) for why the timeout is a
runtime step at all.

The ssh session dies on the second line. That is the expected result.

**Then read it back**, after about forty seconds:

```sh
ssh root@BOARD "uptime; ls -l /sys/fs/pstore/"
ssh root@BOARD "cat /sys/fs/pstore/dmesg-ramoops-0" > EVIDENCE/sysrq.txt
```

## Raw output

Four files, all under `../docs/evidence/`, listed here because this entry
quotes fragments and the files are the evidence:

```
32756  pstore-2026-10-06-console-ramoops-0.txt
27281  pstore-2026-10-06-dmesg-ramoops-0.txt        Oops#1 Part1
27240  pstore-2026-10-06-dmesg-ramoops-1.txt        Panic#2 Part1
27283  pstore-2026-10-06-sysrq-dmesg-ramoops-0.txt  Panic#1 Part1
```

Each record opens with a one line header that pstore writes, naming which
dump it is and which part. Those headers are how two records from one
crash were told apart from two records from two crashes.

**The recovered oops.** `dmesg-ramoops-0` from the crash of Tuesday 6
October 2026 at 02:55 was diffed against the block committed in entry
[01](01-oops.md), which is what the serial console printed live, after
stripping the `<N>` syslog level prefixes that pstore keeps and the
console does not. Both sides are 46 lines and they agree on all 46.

They did not at first. One line differed invisibly, and it was the
`Code:` line, where the kernel emits a trailing space that the path from
console through picocom through a terminal through the clipboard had
dropped. 105 bytes in the record, 104 in the committed block. The byte
was restored in entry 01 rather than explained away.

**The SysRq capture.** From
`pstore-2026-10-06-sysrq-dmesg-ramoops-0.txt`. These are selected lines
and not a contiguous quote: the frames between `Call trace:` and
`sysrq_handle_crash` are in the file and are not reproduced here.

```
Panic#1 Part1
<6>[ 5495.984752] sysrq: Trigger a crash
<0>[ 5495.990953] Kernel panic - not syncing: sysrq triggered crash
<4>[ 5495.997837] CPU: 1 PID: 1538 Comm: sh Tainted: G    B              6.6.63-v8 #1
<4>[ 5496.013942] Call trace:
<4>[ 5496.040782]  sysrq_handle_crash+0x40/0x88
<4>[ 5496.045910]  __handle_sysrq+0x124/0x2b8
<4>[ 5496.050824]  write_sysrq_trigger+0x8c/0xc0
```

Two things there are worth more than the panic line. The taint field
reads `G    B` with no `O`, so no out of tree module was loaded: the
module from entries 01 to 04 plays no part in this capture, which is what
this entry has always claimed and had never shown. And the bottom three
frames are the whole path from a `write` on a proc file to a deliberate
panic, which is the same thing the control two sections down proves from
outside the kernel.

## Conclusion

**Acceptance criterion 2 is met, and its wording describes a state the
hardware cannot be left in.** The criterion asks that
`/sys/fs/pstore/dmesg-ramoops-0` hold the same oops after the reboot, and
that the SysRq crash make a second capture. Both happened and both are
captured. They cannot both be on the board at the end, because the SysRq
crash necessarily overwrote the record holding the oops. The README row
says so rather than passing quietly.

What would have been missed without the tool: the entire crash. The oops
in entry 01 was captured live only because a terminal happened to be
logging. This one was read off a board that had already rebooted, from a
session the crash itself had disconnected, with nothing watching.

## The cursor lives in RAM, and that is the whole behaviour

**This is the finding worth carrying out of the entry.** Three records
were on the board. The SysRq crash produced no `dmesg-ramoops-2`. It
overwrote `dmesg-ramoops-0`, the record holding the oops, and left
`dmesg-ramoops-1` untouched.

The reason is in `fs/pstore/ram.c` in the tree that built this kernel,
`build/tmp/work-shared/raspberrypi3-64/kernel-source`:

```c
	prz = cxt->dprzs[cxt->dump_write_cnt];                  /* 366 */
	cxt->dump_write_cnt =
		(cxt->dump_write_cnt + 1) % cxt->max_dump_cnt;  /* 389 */
```

`dump_write_cnt` is a field of the in-RAM context. Nothing restores it
from the persistent region, because the region has nowhere to keep it. So
it starts at zero on every boot, and **the first dump after any reboot
lands in zone zero**, regardless of how many zones exist or how many of
them hold records. The header numbering says the same from the other
side: the oops boot produced `Oops#1` then `Panic#2`, and the next boot's
single dump is `Panic#1`.

The consequence is the ordering rule in the Commands section above, and
it is structural rather than cautious. Any crash destroys the oldest
record from the previous boot. There is no accumulating archive in that
region. There is one boot's worth of dumps, and the moment the board
restarts and crashes again, the front of it is gone.

## The sysrq mask is not consulted on this path

`kernel.sysrq` on this image reads `16`, which is the sync command alone.
`sysrq_crash_op` carries `.enable_mask = SYSRQ_ENABLE_DUMP`, so by the
mask the crash should have been refused. It was not, because
`write_sysrq_trigger` dispatches without asking for the mask to be
checked, and the keyboard path and the proc path do not pass the same
flag.

That was established by a control rather than by reading, which is why it
can be believed. SysRq `m` prints memory statistics and carries the
**identical** `enable_mask`, so it tests the same gate without crashing
anything:

```
[ 5394.318241] sysrq: Show Memory
[ 5394.322380] Mem-Info:
```

It ran, with the mask at `16`. Whatever gates the crash, it is not
`kernel.sysrq`, so nothing on the board had to be changed to make
criterion 2 reachable. Had the mask been raised first as a precaution,
two things would have changed at once and this would never have been
known.

## What the run corrected in this entry

**The commands said to clear pstore first.** They said
`sudo rm -f /sys/fs/pstore/*` before triggering, on the grounds that an
old record must not be mistaken for a new one. That instruction destroys
the previous boot's evidence in the service of tidiness, and the headers
make the confusion it guards against impossible anyway, since every
record says which dump it is. Copying first replaced it.

**Every command carried `sudo`.** This image has none.

**The second capture was said to need magic SysRq from the serial
terminal**, with a note about sending a break in picocom. It does not.
`/proc/sysrq-trigger` over ssh is enough, and it suits an entry about
evidence from an unwatched board better than a keystroke does.

**The region arithmetic was wrong.** The old text read: "there is room
for roughly six dmesg records plus a rolling console capture. The seventh
crash overwrites the first." It is not the seventh crash, it is the next
boot's first crash, for the reason two sections above. And the six was
arithmetic on parameters read from the Raspberry Pi overlay README rather
than measured on the board. What replaces it is below, including the part
that is still unmeasured.

## What the region holds, and what is still unmeasured

Measured on Tuesday 6 October 2026:

| Quantity | Value | How |
|---|---|---|
| `console-ramoops-0` size | 32,756 bytes | `ls -l` on the board, before and after a crash |
| dmesg record size as read | 27,240 to 27,283 bytes | the four evidence files |
| dmesg records present at once | 2 | three crashes, never a third file |
| zone taken by a new boot's first dump | zone 0 | `ls -l` before and after |

From the Raspberry Pi overlay README rather than from the board:
`total-size=0x20000`, `record-size=0x4000`, `console-size=0x8000`.

**The records read larger than a record.** 27 kB of plain text cannot fit
in a 16,384 byte zone, so pstore stores them deflated and decompresses on
read. That follows from two numbers, and it holds only as long as the
16 kB is right, which is one of the numbers still taken on trust.

**Still open, and named rather than guessed:**

- **`max_dump_cnt`**, the number of dmesg zones. Two records have been
  seen at once, which is a lower bound and not the value. The cursor
  behaviour above means no experiment crossing a reboot can measure it,
  so it needs either the probe time log or the device tree properties the
  firmware applied, under `/proc/device-tree/reserved-memory/`.
- **The console zone is not recording.** `console-ramoops-0` is unchanged
  in both size and mtime across a fresh panic and a reboot, still 32,756
  bytes of a 32,768 byte zone. Either it filled and stopped, or it is
  being written somewhere this entry has not looked.
- **The `-28` in entry 01's oops.** `pstore: backend (ramoops) writing
  error (-28)` is `ENOSPC`, printed between the end of the oops and the
  panic, and two dumps from that same crash succeeded. The candidates are
  a dump needing a zone that was already taken, and a console write to
  the full zone above. The two open items settle between them, so this one
  waits rather than picking.

One further measured oddity, with an explanation that is reasoning and
not evidence: `console-ramoops-0` carries an mtime of `Jun 26 2025` while
the dmesg records carry the crash time. The console zone is written from
very early boot, before systemd-timesyncd has corrected the clock on a
board with no RTC, so its first write would land at whatever date the
rootfs starts with. Plausible, unverified, and recorded as such.

## If /sys/fs/pstore is empty, read this before suspecting ramoops

**This is the trap this project found before it ever built anything, and
it is the most useful thing in the notebook.**

`systemd` mounts `/sys/fs/pstore` itself. Then
`systemd-pstore.service` copies every record to
`/var/lib/systemd/pstore/` and **deletes the original**:
`Storage=external` and `Unlink=yes` are the compile-time defaults, and
the unit is ordered `Before=sysinit.target`, so it has finished long
before you get a login prompt.

So the sequence on a stock image is:

```
  panic  ->  ramoops writes the record  ->  reboot
         ->  systemd mounts /sys/fs/pstore
         ->  systemd-pstore.service moves everything to
             /var/lib/systemd/pstore/ and unlinks it
         ->  you log in and /sys/fs/pstore is EMPTY
```

Nothing is broken and nothing is lost. The evidence moved, and every
instruction ever written about pstore says to look somewhere it is no
longer. The Raspberry Pi overlay README says the same in one line.

`bench-debug-image` masks that unit so the records stay put. Measured on
this board rather than intended:

```sh
systemctl is-enabled systemd-pstore.service    # masked
```

The mount is real now too:

```
pstore on /sys/fs/pstore type pstore (rw,nosuid,nodev,noexec,relatime)
```

It was not, until a mount unit went into the image. That half of the
story is journal entries 20 and 22.

`console-size` is not the upstream default, which is 0.
`CONFIG_PSTORE_CONSOLE` without it is a feature with nowhere to write,
which is the same class of silent nothing as a promptless Kconfig symbol.

## The mistake this entry exists to make once, cheaply

Reaching for the second capture before securing the first. Everything
here worked, and the only reason the oops record still exists is that it
was copied to a file twenty minutes before a deliberate crash overwrote
it. The instruction that used to stand at the top of this entry would
have cleared it on purpose.
