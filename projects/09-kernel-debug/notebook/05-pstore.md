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
[01](01-oops.md), after stripping the `<N>` syslog level prefixes that a
dmesg record keeps and a console record does not. Both sides are 46 lines
and they agree on all 46.

Entry 01's block is **not** a live serial capture, which both entries
claimed until later the same day. The serial console on this image has
never worked: `disable-bt` blanks `uart0_pins` and the firmware does not
fill it, so `ttyAMA0` is an enabled console with an unmuxed transmit pin.
The block is the **console** record, `console-ramoops-0`, which is why it
has no level prefixes, and the carriage returns that made `decode.sh` say
"a serial capture" came from a Windows clipboard.

Two defects turned up in that block, both invisible to a reader and both
found by diffing rather than reading. The `Code:` line was missing the
trailing space the kernel emits, 105 bytes against 104. And an entire
line, `CPU features: ...`, was absent. Both restored, after which all 55
lines of the console record's span match.

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

What would have been missed without the tool: **everything, and more than
this entry used to claim.** It said the oops in entry 01 was captured live
because a terminal happened to be logging. There was no live capture. The
serial console has never worked on this image, so pstore is not the backup
that caught a crash nobody watched, it is the **only** reason any record
of either crash exists at all. Both entries 01 and 05 rest on this
backend, and a bench with a dead console and no pstore would have produced
nothing from a whole day of deliberate crashing.

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

**Half of the region arithmetic was wrong, and the wrong half is not the
one I first accused.** The old text read: "there is room for roughly six
dmesg records plus a rolling console capture. The seventh crash
overwrites the first." The six is right, and the device tree now confirms
it. The second sentence is not: it is never the seventh crash, it is the
next boot's first crash, for the reason two sections above. Six zones
exist and no run can reach the third, because the cursor restarts at zero
every boot.

Worth separating, because I conflated them for an hour: the six came from
the overlay README rather than from the board, which made it
**unverified**. It did not make it wrong, and calling it doubtful was its
own small error. The fix for an unverified number is to measure it, not
to distrust it.

## What the region holds, all of it measured

Measured on Tuesday 6 October 2026:

| Quantity | Value | How |
|---|---|---|
| `console-ramoops-0` size | 32,756 bytes | `ls -l` on the board, before and after a crash |
| dmesg record size as read | 27,240 to 27,283 bytes | the four evidence files |
| dmesg records present at once | 2 | three crashes, never a third file |
| dmesg zones that exist | 6 | `(0x20000 - 0x8000) / 0x4000`, all three sizes measured |
| zone taken by a new boot's first dump | zone 0 | `ls -l` before and after |

Also measured, from the probe lines in the board's own log:

```
[    0.000000] OF: reserved mem: 0x000000000b000000..0x000000000b01ffff (128 KiB) map non-reusable ramoops@b000000
[    0.385447] pstore: Using crash dump compression: deflate
[    0.385619] printk: console [ramoops-1] enabled
[    0.387005] pstore: Registered ramoops as persistent store backend
[    0.387099] ramoops: using 0x20000@0xb000000, ecc: 0
```

That confirms `total-size=0x20000` against the overlay README, and it
says the compression outright. The records read larger than a 16 kB zone
because they are deflated in the zone and decompressed on read, which is
now the kernel's statement rather than my arithmetic.

`record-size` and `console-size` were read from the device tree the
firmware actually applied, on the board:

```sh
ssh root@BOARD "cat /proc/device-tree/reserved-memory/ramoops@b000000/record-size" | od -An -tx1
```

BusyBox `od` has no `-A`, so the bytes come across and GNU `od` on the
laptop formats them. Four bytes each, big endian:
`record-size = 00004000`, `console-size = 00008000`. Both match the
overlay README exactly, which makes the zone count arithmetic on measured
numbers: `(0x20000 - 0x8000) / 0x4000` is **six dmesg zones**.

**None of the four records contains those probe lines**, which is a
property of where each record begins and not of ramoops. Each holds the
tail of the log buffer that fit one compressed zone, and they begin at
board times 0.383732, 0.396773 and 0.438597. Two of the three start after
0.387099 outright. The third starts about 2 ms before the probe window,
and since probe ordering shifts by a few milliseconds between boots, the
likely reading is that in that boot the lines fell just off the front.
That last part is inference: the evidence that would settle it is the
earliest log of a boot that no longer exists.

**Settled since this entry was first written, and the corrections are
mine rather than the file's:**

- ~~The console zone is not recording.~~ **Settled, and the first
  reading was wrong.** `console-ramoops-0` is unchanged in both size and
  mtime across a fresh panic and a reboot, still 32,756 bytes of a 32,768
  byte zone, and it **is** recording. Comparing the bytes rather than the
  metadata showed different content, beginning mid word at
  `mcblk0p2 rootfstype=ext4 ...`, which is what a circular buffer looks
  like when it is read from a wrap point. A full ring has a fixed size and
  a first write that never happens again, so size and mtime are both
  static while the contents roll. Inferring behaviour from metadata is
  what produced the wrong answer; one `diff` produced the right one.
Nothing in the geometry is still open. The one item that is appears two
sections below, and it is smaller than it was.

One further measured oddity, with an explanation that is reasoning and
not evidence: `console-ramoops-0` carries an mtime of `Jun 26 2025` while
the dmesg records carry the crash time. The console zone is written from
very early boot, before systemd-timesyncd has corrected the clock on a
board with no RTC, so its first write would land at whatever date the
rootfs starts with. Plausible, unverified, and recorded as such.

## The -28 is a refusal by design, and every record here is truncated

Entry [01](01-oops.md)'s oops carries this between the end of the trace
and the panic:

```
[ 2057.724969] pstore: backend (ramoops) writing error (-28)
```

`-28` is `ENOSPC`, and two dumps from that same crash succeeded, which
made it look like a partial failure. It is not a failure. Both of the
obvious causes are dead on measurement: there are six dmesg zones and
that boot used two, so it was not zone exhaustion, and the console zone
is a wrapping ring that cannot run out of space. What remains is in
`ramoops_pstore_write` in the tree that built this kernel:

```c
	/*
	 * Explicitly only take the first part of any new crash.
	 * If our buffer is larger than kmsg_bytes, this can never happen,
	 * and if our buffer is smaller than kmsg_bytes, we don't want the
	 * report split across multiple records.
	 */
	if (record->part != 1)
		return -ENOSPC;
```

pstore offered a second chunk of the log and ramoops declined it, on
purpose, rather than split one report across records. The evidence agrees
from the outside: every dmesg record taken on this bench is `Part1`, the
string `Part` occurs exactly once in each file, and no `Part2` has ever
been stored.

**So every pstore dmesg record here is a truncated log and not a complete
one.** It holds what fits one zone and the remainder is discarded, which
is why the three records begin at board times 0.383732, 0.396773 and
0.438597 rather than at zero. That applies to anything entries 02 to 04
recover from pstore as well, and it is the reason a serial console is
still worth having attached: the console prints everything, the record
keeps one zone.

Why a second part was offered at all is one layer further down and is
left as reasoning rather than measurement. `pstore_dump` keeps taking
chunks while the total written is under `pstore.kmsg_bytes`, and the
total it accumulates is the **compressed** size. A 16 kB zone holding
deflated text can come well under that threshold, which would send the
loop around again for a part the backend then refuses. Plausible,
consistent with everything above, and not verified here.

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
