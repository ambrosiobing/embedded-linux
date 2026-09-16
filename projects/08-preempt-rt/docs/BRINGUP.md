# Bring-up: from a flashed card to sixteen rows

In order. Each step ends with something that either works or says why not,
because the alternative is arriving at step 9 with a fault introduced at
step 2.

Nothing below has been performed. It is the plan, written while the code
was written, and it will be corrected in the [journal](../JOURNAL.md) as
soon as it meets hardware.

## 0. Before the power goes on

Power off, HAT off.

| Check | Why |
|---|---|
| The HAT's address links are at 0 | `rt-capture --address 0` is the default, and `daqhats_list_boards` will say otherwise |
| Nothing else is on the 40 pin header | The HAT owns SPI0, three address lines and the ID EEPROM pins |
| The jumper from pin 38 goes to CH0 and the one from pin 39 goes to AGND | A signal without its ground reference reads as noise around an arbitrary offset |
| A heatsink or a fan is fitted | A bare Pi 3B throttles inside a 60 s `stress-ng` run, and `rt-run` will refuse to start once it does |
| The USB/TTL cable is on pins 8, 10 and 6, red lead not connected | Under load, ssh is the first thing to stall. The console is how the run that went wrong gets diagnosed |

Count the pins twice. Pin 38 and pin 40 are adjacent, and pin 40 is
GPIO21, which the vendor documentation names as the DAQ HAT interrupt line.

## 1. Boot a kernel and prove the hardware, before caring which kernel

Two images exist and their userspace is identical:

| Build | Kernel | Use |
|---|---|---|
| `./go rt` | 6.12.93 with `PREEMPT_RT` | the variable |
| `./go rt-generic` | 6.12.93 without it | the control |

Either will do for this step and the three after it, because nothing in
the HAT, the wiring or the threshold depends on the preemption model.
Flash one and boot it:

```sh
uname -r                       # 6.12.x
cat /sys/kernel/realtime       # 1 on the rt build, absent on the control
gpiodetect                     # gpiochip0, pinctrl-bcm2835 on a Pi 3B
```

**This step originally said `bench-rt-image` "carries the generic BSP
kernel".** It never did: `BENCH_RT_KERNEL = "1"` is in `kas/bench-rt.yml`,
so that image has always carried the real-time kernel. The control is a
separate build, `kas/bench-rt-generic.yml`, which exists because the
original control, `bench-image`, is on 6.6 and would have put six kernel
versions inside the comparison. See journal entry 29.

**Keep the kernel you are not running.** Both builds write to the same
deploy directory and the later one wins, so save the first before building
the second:

```sh
mkdir -p ~/bench/kernel-rt
cd ~/bench/build/tmp/deploy/images/raspberrypi3-64
cp Image modules-*.tgz ~/bench/kernel-rt/
cp *.dtb ~/bench/kernel-rt/ && cp -r overlays ~/bench/kernel-rt/
```

then later, against a card flashed with the other one:

```sh
./go rt-kernel install /mnt/boot /mnt/root ~/bench/kernel-rt
```

## 2. The HAT has to be visible before anything else

```sh
ls /dev/spidev0.0              # needs ENABLE_SPI_BUS=1 in the kas file
ls /proc/device-tree/hat/      # product, product_id, uuid, vendor
cat /proc/device-tree/hat/product
daqhats_list_boards            # Address 0: MCC 118
```

Three failures and what each means:

| Symptom | Cause |
|---|---|
| No `/dev/spidev0.0` | Either `dtparam=spi=on` is missing from `config.txt`, or `kernel-module-spidev` is not in the image. `lsmod \| grep spidev` tells you which |
| `/proc/device-tree/hat/` is missing | The firmware did not read the ID EEPROM. Reseat the HAT; check pins 27 and 28 are not obstructed |
| `daqhats_list_boards` finds nothing while the device tree entry exists | The library found the board and could not talk to it. That is SPI, not the EEPROM |

## 3. Confirm the wire by hand

Before any automation, prove that the pin the software will drive is the
pin the instrument is reading.

```sh
# Hold GPIO20 high in the background, for as long as timeout allows
timeout 20 gpioset -c gpiochip0 20=1 &
python3 -c "from daqhats import mcc118; print(mcc118(0).a_in_read(0))"
# expect about 3.3

wait                            # the line is released here
python3 -c "from daqhats import mcc118; print(mcc118(0).a_in_read(0))"
# expect about 0.0
```

About 3.3 and about 0.0. Anything in between, or a reading that does not
change, is a wiring fault, and every later number would be noise.

The background job and the `timeout` are not decoration. In libgpiod v2 a
line is only driven while the process holding it is alive, and the kernel
returns the line to its default the moment that process exits. A `gpioset`
run in the foreground and then read afterwards would read 0 V both times
and look exactly like a broken jumper.

## 4. Optional, and only for the rows that need it: slow the edge

Series 1 kohm from pin 38, 10 nF from CH0 to AGND. See
[METHOD.md](METHOD.md) for why. With it, `rt-analyze` reports
`subsample_fraction` near 1; without it, near 0 and a warning on stderr.

It is worth doing this once with a 60 s capture in each configuration and
putting both numbers in the table, because that comparison is itself a
result: it shows how much of a published jitter figure can be an artefact
of the instrument.

## 5. A first run, no isolation, no load

```sh
rt-run -d 10 smoke
```

Ten seconds, generic kernel, nothing tuned. What to look for, in order:

1. it refuses nothing, so the kernel and the claims agree
2. `rt-capture` reports about a million samples and no overrun
3. `ext_edges` is 5000 for a 10 s run at 1 kHz toggling
4. `ext_mean_us` is near 2000 and `clock_offset_ppm` is a few tens
5. the internal and external maxima are within a few microseconds of
   each other

If the edge count is roughly half or double what it should be, the
threshold is wrong for the actual swing: measure it with
`a_in_read` and set `RT_THRESHOLD` to the midpoint rather than assuming
1.65.

## 6. Install the RT kernel beside the generic one

First build it, and check the fragment before paying for the compile:

```sh
./go bitbake bench-rt -c kernel_configme virtual/kernel
head -4 $BENCH_WORK/build/tmp/work-shared/raspberrypi3-64/kernel-source/Makefile
./go ksym -f rt
./go kconfig -f rt
./go rt
```

Four checks before the compile, and each answers a different question. All
of them together take minutes; `do_compile` is most of an hour.

| Step | Question | What a wrong answer looks like |
|---|---|---|
| `head -4 Makefile` | did the version pin take | `PATCHLEVEL = 6`, so `ARCH_SUPPORTS_RT` is absent and `PREEMPT_RT` can never be set |
| `./go ksym -f rt` | does every fragment line name a real symbol | a line that is a typo or a module object rather than an option |
| `./go kconfig -f rt` | did the fragment reach the `.config` | `PREEMPT_RT` requested and missing, which is the whole risk of this project |
| `./go rt` | does it build | |

Two things about that list are worth stating rather than assuming.

**`kernel_configme`, not `unpack`.** `do_unpack` puts the git tree in
`${WORKDIR}/git` and `do_unpack[cleandirs]` empties `STAGING_KERNEL_DIR`
on the way past. What fills it is `do_kernel_checkout`, a separate task
from `kernel-yocto.bbclass`. Stopping at `unpack` leaves an empty
`kernel-source` directory and `./go ksym` with nothing to read.
`kernel_configme` runs fetch, checkout and patch, and then merges the
fragments into a real `.config`, which is what makes the third check
possible before the build rather than after it.

**`ksym` cannot catch a failed version pin**, which is why the Makefile is
read separately. `CONFIG_PREEMPT_RT` is declared, with a prompt, in 6.6 as
well as 6.12; what 6.6 lacks is `ARCH_SUPPORTS_RT` on arm64, and that is a
dependency rather than a declaration. `ksym` checks that a symbol exists
and is settable, not that its dependencies are met, so on a 6.6 tree it
prints `ok CONFIG_PREEMPT_RT` and tells you nothing.

From `ksym`, expect two lines reported as consequences rather than
requests, both already marked in `rt.cfg`: `IRQ_FORCED_THREADING`, which
arm64 selects unconditionally, and `LOCKUP_DETECTOR`, which the two
detectors select.

Then power off, card out, into a reader.

```sh
./go rt-kernel install /mnt/boot /mnt/root
./go rt-kernel status /mnt/boot
```

Then edit `cmdline.txt` by hand, on one line, appending:

```
isolcpus=3 nohz_full=3 rcu_nocbs=3 irqaffinity=0-2
```

All four, and the first three together. `isolcpus` alone leaves the
scheduler tick and the RCU callbacks on the core that is supposed to have
neither, and they arrive in bursts, which is the shape that shows up in the
tail of the histogram rather than in the mean.

Keep a copy of the original `cmdline.txt` next to it. The matrix needs both.

## 7. The first RT boot

Console attached, because this is the boot that can fail.

```sh
uname -v                       # contains PREEMPT_RT
cat /sys/kernel/realtime       # 1
cat /sys/devices/system/cpu/isolated    # 3
cat /proc/cmdline
zcat /proc/config.gz > /tmp/config
```

Copy that config back to the build host and check it against both
fragments:

```sh
./go kconfig -f rt /tmp/config
```

This is the step that catches a fragment which was silently dropped. It
matters more here than in Project 1, because `CONFIG_PREEMPT_RT` has no
prompt on a kernel without `ARCH_SUPPORTS_RT` and disappears without a
warning.

**If the board does not come up:** card out, reader, and

```sh
./go rt-kernel select /mnt/boot generic
```

then restore the original `cmdline.txt`. One line each, from any laptop.

## 8. Interrupts

```sh
rt-irq-affinity show
rt-irq-affinity set 0-2
rt-irq-affinity check
```

`set` will report a handful it could not move. That is expected: per-CPU
timers and IPIs are owned by the kernel and return EIO on a write. `check`
distinguishes them from a device interrupt that could have been moved and
was not, by writing an interrupt's own affinity back to it: a write that
succeeds means the kernel would have accepted a move.

Write down which ones are immovable. It belongs in the results discussion,
because it is the honest answer to "is the core really isolated".

## 9. The matrix

One row per invocation, in the order in the
[README](../README.md#results), which groups by kernel and then by
isolation so that reboots are minimised.

```sh
rt-run -i -a -g performance -L
```

Between rows:

- let the board cool until `vcgencmd get_throttled` reads `0x0` again.
  `rt-run` refuses to start otherwise, which is the guard working rather
  than a nuisance
- for a governor change, nothing else is needed
- for an isolation change, edit `cmdline.txt` and reboot
- for a kernel change, `rt-kernel select` and reboot

For the `fixed` governor rows, add `force_turbo=1` to `config.txt` and
leave `-g` off. Note what that costs: the ARM clock is pinned at the turbo
frequency, the board runs hotter, and the Pi's warranty bit is set
permanently. It is worth one pair of rows and not more.

## 10. Copy the results back

```sh
scp root@BOARD:/var/lib/bench/rt/results.csv projects/08-preempt-rt/results/
scp root@BOARD:'/var/lib/bench/rt/*hist.txt' projects/08-preempt-rt/results/
```

Then the histograms, plotted on a logarithmic count axis so the tail is
visible, and the written comparison of the internal and external numbers
that the acceptance criteria ask for.

---

Back to the [project README](../README.md), or the
[method](METHOD.md).
