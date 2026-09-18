# 05: the crash nobody was watching

**Status: NOT YET RUN.** No board has produced the output below.

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

**On the board over the picocom console.** Clear first, so an old record
cannot be mistaken for a new one:

```sh
sudo rm -f /sys/fs/pstore/*; ls /sys/fs/pstore/
```

Cause the crash:

```sh
echo null | sudo tee /sys/kernel/debug/buggy/trigger
```

Wait for the reboot, then:

```sh
ls -l /sys/fs/pstore/
sudo cat /sys/fs/pstore/dmesg-ramoops-0
```

The second capture, using magic SysRq, which crashes on purpose and
exercises the path without involving the module at all:

```sh
echo c | sudo tee /proc/sysrq-trigger
```

From the serial terminal the same key can be sent as a break followed by
the letter. In picocom the break is Ctrl-A then Ctrl-Backslash.

## Raw output

```
NOT YET RUN
```

The recovered oops:

```
NOT YET RUN
```

The SysRq capture:

```
NOT YET RUN
```

## Conclusion

To be written. The claim it should support is acceptance criterion 2:
`dmesg-ramoops-0` holds the same oops, and the SysRq crash produces a
second capture.

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

`bench-debug-image` masks that unit so the records stay put. Confirm:

```sh
systemctl is-enabled systemd-pstore.service    # expect: masked
```

If it is not masked, look in `/var/lib/systemd/pstore/` instead.

## What the region can and cannot hold

The overlay is configured with `total-size=0x20000` (128 kB),
`record-size=0x4000` (16 kB) and `console-size=0x8000` (32 kB), so there
is room for roughly six dmesg records plus a rolling console capture.
The seventh crash overwrites the first. Clearing after each capture is
not tidiness, it is what keeps the numbering meaningful.

`console-size` is not the upstream default, which is 0.
`CONFIG_PSTORE_CONSOLE` without it is a feature with nowhere to write,
which is the same class of silent nothing as a promptless Kconfig symbol.
