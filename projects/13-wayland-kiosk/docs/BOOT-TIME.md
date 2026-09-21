# Boot time: power-on to first dashboard frame

Acceptance criterion 1 is **under 10 s, measured three times**. This is
where those numbers go.

**Status: NOT YET MEASURED.** Every table below is empty. A blank is
honest; a number that was never taken is a claim the first careful reader
will check.

## The instrument problem, first

**`systemd-analyze` is blind to most of this timeline.** It reports user
space, and takes the firmware and loader figures from whatever the
firmware hands it, which on this platform is not the whole story.

```
  |<---- firmware ---->|<---- kernel ---->|<-------- user space -------->|
  |  bootcode, EEPROM  |  decompress,     |  systemd, seatd/logind,      |
  |  start4.elf,       |  probe, mount    |  weston, PAM session,        |
  |  device tree,      |  root            |  bench-hmi, FIRST FRAME      |
  |  overlays          |                  |                              |
  |                    |                  |                              |
  |  serial console with timestamps       |  systemd-analyze             |
  |<------------------------------------->|<---------------------------->|
```

So two instruments, and the serial cable is in the parts list for a
project that otherwise has a screen.

**"First dashboard frame" is not a systemd event.** No unit reaching
`active` corresponds to a pixel. The three ways to pin it down, in
increasing honesty and decreasing convenience:

| Method | What it really measures | Good enough? |
|---|---|---|
| `systemd-analyze` total | user space finishing, not a frame | no, it can finish before weston draws |
| A log line from `bench-hmi` after its first `lv_timer_handler` | the client believing it drew | close, and cheap |
| A stopwatch in shot with the screen, on video | the frame a human sees | **yes**, and it is what the specification asks for |

The specification asks for a 15 s video with a visible stopwatch, and
that is the number that goes in the headline row. The other two are
recorded beside it because when they disagree, the disagreement is the
interesting part.

## Method

Three runs, cold each time. Power removed between runs, not `reboot`: a
warm reboot skips firmware work and would flatter the result.

**On the host**, with the terminal logging and timestamps on:

```bash
picocom --logfile boot-$(date +%F-%H%M%S).log localhost:5550
```

picocom has no timestamp option of its own; `ts` from `moreutils` or a
terminal that stamps lines is what supplies them. Record which was used,
because a timestamp applied by the host measures when the byte arrived,
not when it was printed, and at 115200 baud that is a real difference on
a long line.

**On the board over ssh**, after it is up:

```sh
systemd-analyze
```

```sh
systemd-analyze critical-chain weston.service
```

```sh
systemd-analyze blame | head -n 20
```

```sh
systemd-analyze plot > /tmp/boot.svg
```

Then `scp` the plot off. **Not over the serial line**: it is tens of
kilobytes of XML and the cable does about 11 kB/s.

## Results: before trimming

| Run | Firmware + kernel (serial) | User space (`systemd-analyze`) | Stopwatch to first frame |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

`systemd-analyze` verbatim:

```
NOT YET MEASURED
```

`systemd-analyze critical-chain weston.service`:

```
NOT YET MEASURED
```

`systemd-analyze blame`, first twenty:

```
NOT YET MEASURED
```

Plot: `evidence/boot-before.svg` (not yet produced).

## What was trimmed

The specification's trim list is written for Raspberry Pi OS Lite. **A
Yocto image does not start from there**, and most of the list does not
apply. Recording that is the point rather than a disappointment: it says
something true about the two distributions.

| Trim | Applies to this image? | Done | Effect |
|---|---|---|---|
| mask `NetworkManager-wait-online` | **no**, not installed | | |
| mask `ModemManager` | **no**, not installed | | |
| mask `bluetooth` | maybe, the BSP enables the radio | | |
| mask `apt-daily` timers | **no**, there is no apt | | |
| mask `rpi-eeprom-update` | **no**, Raspberry Pi OS only | | |
| `disable_splash=1` | yes | already set in `kas/bench-kiosk.yml` | |
| `boot_delay=0` | yes | already set in `kas/bench-kiosk.yml` | |
| `quiet` on the kernel line | yes | not set: see below | |
| keep `ssh` | yes | deliberately kept | |

### `quiet` is not set, and that is a choice

It would save some console output at 115200 baud. It would also remove
the kernel messages that the **other half of the measurement depends
on**: the serial log is the only instrument for the firmware and kernel
phases, and `quiet` is precisely a switch that silences it.

So the order is: measure with the console loud, trim everything else,
then decide whether `quiet` is worth taking the instrument away. Setting
it first would be measuring with the ruler in a drawer.

### `DefaultDependencies=no` is not set either

It buys a few hundred milliseconds, and the unit then needs its own
ordering written by hand against the seat broker, the tty and the
filesystems. That is a large increase in the number of ways to get a
silent ordering bug, for a gain likely smaller than the spread between
three runs. **Measure the spread first**: if it is 400 ms, a 300 ms
optimisation is not measurable and should not be claimed.

## Results: after trimming

| Run | Firmware + kernel | User space | Stopwatch to first frame |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

Plot: `evidence/boot-after.svg` (not yet produced).

## The comparison the specification also asks for

A short table against the alternatives, once they exist. Nothing here is
measurable until the first column is.

| Stack | Boot to first frame | RSS (compositor + client) | CPU at idle |
|---|---|---|---|
| weston kiosk + LVGL (**this project**) | | | |
| cage + LVGL (needs meta-wayland) | | | |
| Qt 6 with `eglfs_kms`, no compositor | | | |

The third row is the interesting one and the honest competitor: it is the
classic embedded Qt deployment and it removes the compositor entirely.
**Whether a compositor earns its cost is a real question**, and a project
about the graphics stack that never asks it has skipped the part an
interviewer would care about.

---

Back to [DESIGN.md](DESIGN.md), the
[debugging document](DEBUGGING.md), or the
[project README](../README.md).
