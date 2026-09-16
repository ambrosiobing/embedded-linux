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
| The jumper from pin 38 goes to CH0 and the one from pin 39 goes to the GND terminal beside it | A signal without its ground reference reads as noise around an arbitrary offset. The board is single-ended and its terminal blocks are labelled GND, not AGND; there are five of them and they are one net. Use the nearest, for the shortest return path |
| A heatsink or a fan is fitted | A bare Pi throttles inside a 60 s `stress-ng` run, and `rt-run` will refuse to start once it does. The 3B has less headroom than the 4 |
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
uname -v                       # PREEMPT_RT on the rt build, not on the control
gpiodetect                     # pinctrl-bcm2711 on a Pi 4, bcm2835 on a 3B
cat /proc/cmdline              # which console= the firmware gave you
ls /dev/ttyS0 /dev/ttyAMA0     # which UART is on pins 8 and 10
```

**Check which UART the console is on, before the governor rows.** On the
Pi 3 the PL011 (`ttyAMA0`) is wired to the Bluetooth module by default and
pins 8 and 10 get the mini-UART (`ttyS0`). The mini-UART derives its baud
rate from the VPU core clock, which is why `ENABLE_UART = "1"` in
`kas/bench-rpi4.yml` makes the firmware pin `core_freq`.

This project changes CPU governors between rows and sets `force_turbo=1`
for two of them, so it is worth knowing which UART is carrying the console
before a row produces garbage on the wire and the garbage gets read as a
crash. If the console is on `ttyS0` and the output is unstable across a
governor change, `dtoverlay=disable-bt` in `config.txt` gives the header
the PL011 instead, at the cost of Bluetooth, which nothing here uses.

Record what was actually observed. The paragraph above is the reason for
looking, not a prediction of what you will see.

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
cd ~/bench/build/tmp/deploy/images/raspberrypi4-64
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
# Hold GPIO20 high in the background, then drive it low. Two runs, not one
# release: see below for why releasing proves nothing on this BSP.
gpioset -c gpiochip0 20=1 & GPID=$!
sleep 1
python3 -c "from daqhats import mcc118; print('high:', mcc118(0).a_in_read(0))"
kill $GPID

gpioset -c gpiochip0 20=0 & GPID=$!
sleep 1
python3 -c "from daqhats import mcc118; print('low: ', mcc118(0).a_in_read(0))"
kill $GPID
```

Measured on a Pi 4 with an MCC 118: **3.2977 V** high, **0.00113 V** low.
Undriven, before either command, the same input read **0.078 to 0.083 V**,
and that third number is worth knowing: actively driven low is a
millivolt, merely undriven is eighty. A disconnected jumper looks like the
latter.

About 3.3 and about 0.0. Anything in between, or a reading that does not
change, is a wiring fault, and every later number would be noise.

**Two things here were wrong until hardware said so.**

`timeout` is **not in this image**. The original version of this step used
it to bound the background `gpioset`, and on the board it fails with
`timeout: command not found`, so `gpioset` never runs at all and both reads
return the undriven baseline. That looks exactly like a broken jumper and
is not one. `kill $GPID` does the same job with nothing extra installed.

**Releasing the line does not pull it low on this BSP.** The boot log says
so:

```
pinctrl-bcm2835 fe200000.gpio: GPIO_OUT persistence: yes
```

Stock libgpiod v2 drives a line only while the requesting process lives,
and the kernel returns it to its default when that process exits. The
Raspberry Pi pinctrl driver keeps the output state instead. So killing
`gpioset` left the pin at 3.3 V, and the second read returned exactly the
same value to sixteen decimal places, which is one unchanged ADC code and
not a stuck instrument.

Hence two `gpioset` runs rather than one release. Drive high, read, drive
low, read. That tests the thing the measurement actually depends on, which
is that the pin follows what the software asks of it.

## 4. Optional, and only for the rows that need it: slow the edge

Series 1 kohm from pin 38, 10 nF from CH0 to GND. See
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
head -4 $BENCH_WORK/build/tmp/work-shared/raspberrypi4-64/kernel-source/Makefile
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
zcat /proc/config.gz | grep -E '^CONFIG_PREEMPT|^# CONFIG_PREEMPT'
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
