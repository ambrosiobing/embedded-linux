# Resuming project 10 after the board is unplugged

Written Thursday 1 October 2026, when the Raspberry Pi 3B+ came off the
bench. Nothing here is a plan; it is the state the next session starts
from, so that it does not have to be rediscovered.

## What is lost when the board powers down, and what it costs to rebuild

| | cost to restore |
|---|---|
| The out-of-tree modules, `insmod`ed and never installed | a two minute rebuild |
| `industrialio`, `regmap-i2c` and the rest, loaded by hand | four `modprobe` lines |
| The accelerometer's rate and full-scale registers | two `i2cset` writes |
| The disabled state of IRQ 185 | cleared by the power cycle, which is the one thing a reboot fixes |

Nothing is lost that matters. The kernel source package, the headers and
`/root/build-st` survive on the card.

## The sequence that brings it back

```sh
modprobe industrialio
modprobe industrialio-triggered-buffer
modprobe regmap-i2c
insmod /root/build-st/st_lsm6dsx.ko
insmod /root/build-st/st_lsm6dsx_i2c.ko
```

If `/root/build-st` is gone, the Makefile is in
[driver-build-2026-10-01.txt](evidence/driver-build-2026-10-01.txt) along
with the `tar` line that extracts the sources from the installed
`linux-source-6.18`.

The programs in `/usr/local/bin` are copies from the working tree and need
`sed -i 's/\r$//'` after every `scp`, because that tree carries CRLF while
the repository does not. Journal entry 33 has the reason.

## Where each criterion actually stands

| # | state | what it is waiting for |
|---|---|---|
| 1 | part met | `st_magn` and `st_pressure`, built like `st_lsm6dsx` |
| 2 | met | nothing |
| 3 | not started | `st_sensors` plus `st_magn`, so the LIS2MDL gets a device |
| 4 | half met | the interrupt line. CPU is measured; interrupt counts are not measurable here |
| 5 | not started | `iiod` and libiio, neither yet on the board |
| 6, 7 | met | nothing |
| 8 | criterion defective | a decision about restating it, not more measurement |
| 9 | met | nothing |

## The two things the bench itself needs

**The interrupt jumper.** Spurious edges outnumber real FIFO assertions by
twenty to fifty times, the factor is not constant, and the mechanism is
not identified. A shorter wire, or a few hundred ohms in series at the
shield end, is what stands between criterion 4 and passing as written. No
amount of software changes this and no further runs will characterise it.

**The supply.** Eight `Undervoltage detected` events in eleven hours, each
six to eight seconds. Every capture of Wednesday and Thursday was taken on
it. Nothing in the data points at corruption, but it is the only physical
candidate for the one free-fall sample that was never explained.

## What the next session should not redo

The wiring is confirmed three independent ways: UM3239 Rev 5 Table 4, the
overlay registering IRQ 185 on GPIO24, and `INT1_CTRL` reading `0x08` with
the line quiet for eleven hours and active only while the buffer was
enabled. It is right. The interrupt problem is signal integrity, not
connectivity.

The address map is measured and matches the factory solder bridges, and the
0.68 percent sensitivity error is one constant that holds across two
full-scale ranges to 36 parts per million.

And `0x70` does not name the part: the plain LSM6DSV and the LSM6DSV16X
share that WHO_AM_I. UM3239 Table 1 names it.
