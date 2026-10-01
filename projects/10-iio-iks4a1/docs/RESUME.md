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
echo lsm6dso16is 0x6a > /sys/bus/i2c/devices/i2c-1/new_device
insmod /root/build-st/st_lsm6dsx.ko
insmod /root/build-st/st_lsm6dsx_i2c.ko
insmod /root/build-magn/st_sensors.ko
insmod /root/build-magn/st_sensors_i2c.ko
insmod /root/build-magn/st_magn.ko
insmod /root/build-magn/st_magn_i2c.ko
insmod /root/build-magn/st_pressure.ko
insmod /root/build-magn/st_pressure_i2c.ko
modprobe iio-trig-hrtimer
systemctl restart iiod
```

**The `new_device` line is what binds `0x6a`, and it is not a workaround for
a missing driver.** `st_lsm6dsx` has always carried `st,lsm6dso16is`; what is
missing is any device-tree node declaring a device at that address, and I2C
does not probe blind. Instantiating the client by name matches the driver's
own I2C ID table. It is placed before the `insmod` so the driver meets a
client already waiting, which is the order that needs no second step. The
durable fix is a node for `st,lsm6dso16is` at `0x6a` in the shield's overlay,
beside the ones that already declare `0x1e`, `0x5d` and `0x6b`, and it is not
written yet.

**The `systemctl restart iiod` is not optional and the reason is an ordering
trap.** `iiod` enumerates the IIO devices once, at startup, and systemd
starts it at boot, which is before any of the modules above exist. A remote
context then connects, answers, and lists only `cpu_thermal`, `rpi_volt` and
`sht4x`, the three hwmon devices libiio surfaces through its hwmon backend.
The symptom reads as a network problem and is a stale service. It cost the
first remote attempt of criterion 5 on Thursday 1 October 2026. A local
context is unaffected, because it is rebuilt every time a program starts.

**Order matters and the dependency is one-directional.** `st_sensors` is the
common layer `st_magn` and `st_pressure` both link against, so it goes
first, and each `_i2c` module after the core it registers with. The three
sets were built against one `Module.symvers` in `/root/build-magn`, which is
why they load against each other without complaint.

**Nothing here survives a reboot, and that is the state to expect.** The
modules were installed nowhere: no `modules_install`, no `depmod`, no
`/etc/modules-load.d`. Thursday 1 October 2026 at 19:32 a fresh boot
presented exactly three devices to libiio, `cpu_thermal`, `rpi_volt` and
`sht4x`, all three of them hwmon devices surfaced through libiio's hwmon
backend, and no IIO devices at all. That is not a fault, it is what `insmod`
means, and the archived image carries the same property: a restore gives a
card that needs this sequence run, not a board that boots into the working
state.

Making it persistent is a real improvement and is not done: copying the
eight `.ko` files into `/lib/modules/$(uname -r)/extra`, running `depmod -a`
and listing them in `/etc/modules-load.d/bench-iio.conf` would turn
criterion 1 from a property of a live session into a property of the card.

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
| 1 | met, Thursday 1 October 2026 | nothing. Five `working` rows, six IIO devices, no `not-bound` |
| 2 | met | nothing. Met twice, on two inventories of the same image a day apart |
| 3 | met, Thursday 1 October 2026 | nothing. 3.341 us on the hrtimer trigger |
| 4 | half met | the interrupt line. CPU is measured; interrupt counts are not measurable here |
| 5 | met, Thursday 1 October 2026 | nothing. 1000 samples each way, identical columns, on `lis2mdl` rather than the accelerometer because IRQ 185 delivers nothing |
| 6, 7 | met | nothing |
| 8 | criterion defective | a decision about restating it, not more measurement |
| 9 | met | nothing |

**On criterion 5 and the libiio version.** `bench-iio_0.1.bb` warns that
libiio 1.0 replaced buffers with blocks and removed `iio_buffer_refill`, so
`iio-stream.c` is 0.x code that would fail to compile against 1.0. Debian 13
trixie ships 0.26-2, the last of the 0.x line, and the program built with no
warnings on Thursday 1 October 2026. That concern is therefore settled for
this board and open for any host that has moved to 1.x.

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

## The card is archived, and where

Thursday 1 October 2026, 19:04. The whole card is kept as a flashable image
on the win11 skyhorizon demo laptop, outside the WSL virtual disk:

    C:\Users\skyhorizon\Desktop\embedded-linux-bench\images\
        proj10-iio-iks4a1-card\2026-10-01_9cd6302\

1,562,322,561 bytes compressed, from 15,728,640,000 on the card,
decompressing to sha256
`35cc6c221846efa9fe04764892c698cad35b9a63c292fcd23c78a0458925f6f9`. Both the
stored image and the card were read again and hashed to that value, so this
is a verified copy, and `PROVENANCE.txt` beside it records the comparison
with its date and the fact that it was done after the archive rather than
during it.

**Why that matters for this project in particular.** Nothing in this
repository rebuilds that card. The `linux-source-6.18` tree under `/usr/src`,
the four out-of-tree ST drivers built against it, the programs placed by hand
and the measurements under `/var/lib/bench` are in no recipe here. Restoring
it is Raspberry Pi Imager reading the `.img.gz` directly, about seventeen
minutes, and the provenance carries the warning not to let Imager apply its
OS customisation, which would rewrite the hostname, the user and the ssh keys
already inside the image.

**The card was deliberately not reused afterwards.** Criterion 5 needs `iiod`
and libiio on this system, and criterion 4's interrupt half needs the shield
back on the board, so the work continues on the card rather than on a restore
of it. The archive exists so that the next project wanting the card costs
seventeen minutes instead of an afternoon.
