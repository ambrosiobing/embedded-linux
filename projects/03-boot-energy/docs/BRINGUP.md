# Bring-up: Project 03

The order below is not the order the specification lists its steps in, and
the difference is deliberate. Two things have to be settled before any
measurement is worth taking, and one of them can end the project:

- whether the logic port is wired at all, which turns on a pin the
  specification's table does not list: the port has its own VCC reference,
  and without it every marker channel reads nothing;
- whether the markers are in place **before** the baseline is recorded,
  because a baseline taken without them has no phases in it and a baseline
  taken with the optimisations already in is not a baseline.

Nothing here has been done. This file is written so that the first session
with the hardware is spent measuring rather than deciding.

## Before power

**Unplug the micro USB.** The PPK2 is the only supply during every
measurement. The `VDD_5V` header pins and the micro USB 5 V are on the same
net, so leaving the cable in joins two supplies and the PPK2 then measures
part of the current or none of it. That the two are one net is stated in
the specification's wiring table and is **to be confirmed against the
schematic of this board revision**, not taken on trust.

**The console cable's red lead stays open.** It carries 5 V from the host
and is a second supply by another route. White, green and black only.

**Nothing in the NEO Air's own USB.** The PPK2 sources at most 1 A. The
board stays well under that during boot with nothing attached to it, and
`analyze.py` reports the peak current of every run so the limit is checked
by the data rather than assumed once here.

**Every GPIO on this board is 3.3 V with no 5 V tolerance.** The three
logic channels are inputs at the PPK2 end, so nothing should be driving
those pins from the instrument side. Confirm before connecting that D0, D1
and D2 are configured as logic inputs and not as anything else.

## Step 0: what has to exist first

Project 2's system, on the eMMC, booting to a login prompt over the console
at 115200 8N1. Until that exists there is nothing to measure and the rest
of this file cannot start.

Confirm it the plain way, on the micro USB supply with no PPK2 attached,
and only then move the supply.

## Step 1: the logic-level self-test, before anything else

This is acceptance criterion 0 and it is not in the specification's list.
It is promoted because it is a precondition: if it fails, **all three
marker channels fail at once**, and the most likely cause is the pin the
specification's wiring table leaves out.

Wire the supply, **the logic port's own reference**, and D3:

| PPK2 | NEO Air | |
|---|---|---|
| `VOUT` | header pin 2, `VDD_5V` | |
| `GND` | header pin 6, `GND` | |
| logic `VCC` | header pin 1, `SYS_3.3V` | **the one the specification omits** |
| logic `GND` | header pin 6, `GND` | same ground as the supply |
| `D3` | header pin 17, `SYS_3.3V` | pin 1 and pin 17 are one net |

**The logic port has VCC and GND pins of its own**, and VCC is the level
shifter's reference, required between 1.65 and 5.5 V. The specification's
wiring table does not mention it. Leave it unconnected and D0, D1 and D2
read nothing, all three at once, which is exactly the symptom this
self-test exists to detect: it would have reported the method broken and
been believed.

In the Power Profiler desktop app: source meter, 5000 mV, enable power
output. Then **turn the digital channels on**, with the gear icon at the
left of the chart toolbar beside "Lock Y-axis". They are off by default
and the current trace alone shows nothing about D3. Eight rows appear
under the plot.

D3 should read **high**.

If it does, the 3.3 V markers will be seen and the rest of this file
proceeds.

If it does not, work down this list before concluding anything about the
method, because every item is more likely than the instrument being
unable to do what its documentation says:

- the digital channels are still off in the app, and the current trace
  looks identical either way;
- logic `VCC` is not on pin 1, or its jumper has come loose;
- logic `GND` is not connected, so the reference has no return;
- D3 is on pin 1 rather than pin 17 and shares a single contact with the
  reference.

Only when all four are ruled out is this a finding about the instrument,
and then it gets written into `docs/evidence/logic-selftest.txt` with what
was seen. Neither outcome is a failure of the project; only an unrecorded
one is.

## Step 2: the whole harness, and one boot watched by eye

Add the rest:

| PPK2 | NEO Air | What it is |
|---|---|---|
| logic `VCC` | header pin 1, `SYS_3.3V` | stays from step 1, and stays for every run |
| `D1` | header pin 7, PG11 | U-Boot marker |
| `D0` | header pin 12, PA6 | boot-complete marker, and the LED |
| `D2` | debug header pin 3, TXD0 | console TX, in parallel with the cable's white lead |

Supply on, in the app, and watch the current trace. The familiar shape is a
plateau during U-Boot, a ramp through the kernel, and bursts as services
start. None of the markers move yet, because neither has been installed.

This step exists to catch a wiring mistake while there is still a live
display to see it on. Everything after this is a script writing a CSV.

## Step 3: the markers, and only the markers

**The baseline has to have the markers and none of the optimisations**, or
there is nothing to compare against.

U-Boot, stage 1 of `uboot/fragments/fast.config` only:

```
CONFIG_USE_PREBOOT=y
CONFIG_PREBOOT="gpio set PG11"
CONFIG_CMD_GPIO=y
```

Leave `CONFIG_BOOTDELAY` at whatever Project 2 set it to. The trimming
lines in that file are stage 2 and stay commented out until step 6.

Linux: add the node from `board/boot-marker-led.dtsi` to the `leds` node
that `sun8i-h3-nanopi.dtsi` already defines, rebuild the dtb, and generate
the real patch while the tree is in front of you:

```
git -C <tree> format-patch -1 -o projects/03-boot-energy/board/
```

Install the unit and enable it:

```
install -m 0644 board/boot-marker.service /etc/systemd/system/
systemctl enable boot-marker.service
```

Check by eye before measuring anything: the green LED on the breadboard
should light near the end of a boot and stay lit. If it never lights, read
`journalctl -u boot-marker.service` rather than guessing, and check
`/sys/class/leds/boot-marker/` exists at all, which tells apart a device
tree that did not take from a unit that did not run.

## Step 4: the first scripted boot

**Close the Power Profiler desktop app.** It holds the serial port, and
`ppk2_boot.py` then fails with an access error that mentions neither the
app nor the port.

On the Windows host:

```
python measure/ppk2_boot.py COM5 ../results/00-baseline/boot-00.csv
```

`COM5` is an example. The port is whatever the PPK2 enumerated as.

Then look at the file rather than trusting it:

```
python measure/analyze.py ../results/00-baseline --no-summary
```

One run is not a measurement and the program will say so: the first run of
every variant is discarded by rule, so a directory with one file has
nothing kept. That is the expected output here and it is what confirms the
rule is running.

## Step 5: the baseline, six boots

```
cd measure && make measure PORT=COM5 VARIANT=00-baseline N=6
```

Six, not five. The specification asks for five per variant and the first is
discarded, so five would leave four.

Read `results/00-baseline/summary.md`. Three things to check before going
any further:

- **the standard deviations.** If they are already large, something in the
  harness is unstable and no optimisation measured against it will mean
  anything;
- **the peak current**, against the PPK2's 1 A limit;
- **`systemd-analyze time` on the board**, against `t_done` minus the
  kernel start. Acceptance criterion 2 wants those within 0.2 s, and the
  two numbers can only be compared because both use the same definition of
  complete: the startup job queue emptying.

## Step 6: one variant at a time

One change, one fragment, one directory, six boots:

| Variant | Change |
|---|---|
| `10-uboot` | stage 2 of `fast.config`, and `boot_targets=mmc1` in the environment |
| `20-kernel-trim` | `localmodconfig` against a real `lsmod`, then manual trimming, `quiet loglevel=3` |
| `21-kernel-lz4` | the three compression fragments, measured against each other |
| `30-systemd` | the units in `board/units-disabled.txt`, each with its reason |
| `40-final` | everything, then again with `wpa_supplicant@wlan0` disabled |

### How a variant is built

Project 2's build scripts each take one extra fragment through
`NEO_EXTRA_FRAGMENT`, which exists for this project. Unset, they build the
baseline exactly as before.

On the **wsl laptop**, with `toolchain.env` sourced:

```
P3=$PWD/projects/03-boot-energy
```

```
NEO_EXTRA_FRAGMENT=$P3/uboot/fragments/fast.config projects/02-neo-air-mainline/uboot/build.sh
```

```
NEO_EXTRA_FRAGMENT=$P3/kernel/fragments/trim.cfg projects/02-neo-air-mainline/kernel/build.sh
```

**One extra fragment, not a list.** A variant that needs two, such as the
trimming plus a compression choice, is one file made from both:

```
cat $P3/kernel/fragments/trim.cfg $P3/kernel/fragments/lz4.cfg >/tmp/21-kernel-lz4.cfg
```

Concatenating rather than passing two paths keeps the thing that was built
identifiable from one file, which is what the result directory is named
after.

**What the build verifies, and what it cannot.** Both scripts check that
every option in both fragments arrived in the produced `.config`, which is
the check that catches a silently dropped option. It skips comment lines,
so a `# CONFIG_X is not set` line is merged and never verified. The U-Boot
variant here is almost entirely such lines, since its change is to stop
probing what this bench does not have, so confirm those on the board
instead: `usb` and `dhcp` should not be commands U-Boot has.

Capture the `lsmod` for step `20-kernel-trim` from a boot **with the Wi-Fi
up and the console attached**, or `localmodconfig` removes drivers for
everything that was not loaded and the optimised kernel loses them.

For the same variant, find the slow initcalls with the kernel's own tool
rather than by reading timestamps:

```
dmesg > /tmp/dmesg-initcall.txt
```

with `initcall_debug printk.time=1 log_buf_len=4M` appended in
`extlinux.conf`, then on the host `perl scripts/bootgraph.pl` over it.

Fill `docs/before-after.md` from each `summary.md` as it is produced, not
at the end.

## If the marker never rises

In the order that distinguishes the causes fastest:

- **`/sys/class/leds/boot-marker/` missing.** The device tree change did
  not take. The unit is irrelevant until this exists.
- **The unit failed.** `systemctl status boot-marker.service`. It waits on
  `is-system-running --wait`, which returns on `running` or `degraded`, so
  a degraded system still raises the marker.
- **The unit was dropped from the transaction.** This is what an ordering
  cycle looks like, and it is why the unit is ordered only after
  `basic.target` and does its waiting at runtime. If the unit has been
  edited to add `After=multi-user.target`, put it back.
- **The LED lights but D0 reads low.** Back to step 1. This is the logic
  threshold, and it is a property of the instrument and the rail rather
  than of anything on the board.

## If U-Boot's marker never rises

`CONFIG_CMD_GPIO` has to be in the build for `gpio set` to exist at all. A
`preboot` that names a command U-Boot does not have fails silently as far
as the trace is concerned: the board boots normally and D1 stays low.
Check on the console with `gpio set PG11` typed by hand before blaming the
wiring.
