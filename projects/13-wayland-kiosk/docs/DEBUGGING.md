# Debugging the graphics stack, layer by layer

**This is the portfolio piece.** The dashboard is the excuse; this
document is the deliverable. It is the thing to show in an interview
about graphics on Linux, because it is the part that transfers: the panel
changes, the toolkit changes, and the question "which layer is wrong"
does not.

**Status: NOT YET RUN.** Every output block below is empty and marked
`NOT YET RUN`. An empty block is honest. A plausible-looking block
written from expectation would be the worst thing this document could
contain, because its entire value is in showing what a **real** healthy
output looks like, so that an unhealthy one is recognisable.

## The table

| # | Layer | Tool | Healthy answer |
|---|---|---|---|
| 1 | firmware found the panel | `dmesg \| grep -iE 'vc4\|rpi_touchscreen'` | overlay loaded, panel MCU answered on I2C |
| 2 | KMS sees a connected output | `drm_info`, `bench-gfx drm` | `DSI-1` connected at 800x480, **and which card** |
| 3 | the pipeline is composited | `/sys/kernel/debug/dri/N/state` | one active plane holding the client buffer |
| 4 | raw touch reaches the kernel | `evtest /dev/input/eventN` | `ABS_MT_POSITION_X/Y`, `BTN_TOUCH`, `SYN` |
| 5 | touch is mapped to the output | `libinput debug-events --verbose` | `TOUCH_DOWN` at the corner you touched |
| 6 | the compositor started | `journalctl -u weston.service -b` | backend chosen, seat acquired, output named |
| 7 | it offers what a client needs | `wayland-info` | `xdg_wm_base`, `wl_seat` **with touch** |
| 8 | the client speaks the protocol | `WAYLAND_DEBUG=1` on the **client** | `wl_touch.down`, `frame`, `commit` |
| 9 | the widget layer reacted | LVGL log at `LV_LOG_LEVEL_WARN` | the button callback ran |

**Bisect, do not read top to bottom.** A failure lives at exactly one
layer. Start at row 2 or row 5; each answer removes half the stack, and
four commands settle almost everything. Reading from the firmware up is
how an evening goes into a problem that was three commands deep.

---

## Layer 1: did the firmware find the panel

```sh
dmesg | grep -iE 'vc4|v3d|ft5x06|rpi_touchscreen|edt'
```

```
NOT YET RUN
```

---

## Layer 2: KMS

```sh
bench-gfx drm
```

```
NOT YET RUN
```

`drm_info` is the specification's tool here and is **not in the image**:
there is no recipe for it in oe-core, meta-oe or meta-raspberrypi.
`bench-gfx drm` covers the part that matters (which card carries a
connected connector, and the atomic state) by reading sysfs and debugfs,
and says so when `drm_info` is absent rather than pretending the question
was asked. Packaging it is named in the README as not done.

### The two-cards trap

The single most useful fact about this platform. `vc4` has the
connectors; `v3d` is a render node with none. A compositor that opens the
wrong one reports "no outputs" and nothing else.

```sh
for c in /sys/class/drm/card[0-9]*; do echo "$c: $(cat "$c/device/uevent" | grep DRIVER)"; done
```

```
NOT YET RUN
```

**The numbering is not stable across kernel versions**, which is why
nothing in this project hardcodes `card1`.

---

## Layer 3: is anything actually being composited

```sh
cat /sys/kernel/debug/dri/*/state
```

```
NOT YET RUN
```

An active plane with a framebuffer attached is the proof that the client
buffer reached the hardware. A connected output with no active plane is a
compositor that is running and drawing nothing.

---

## Layer 4: raw evdev

```sh
evtest /dev/input/eventN
```

```
NOT YET RUN
```

`evtest` is **not in the image** and BusyBox has no equivalent, so this
layer is reachable only through `bench-gfx input`, which lists the
devices and their names, and through libinput above it. Named in the
README as a gap with its reason.

---

## Layer 5: libinput, where rotation is applied

```sh
libinput debug-events --verbose
```

Touch the **top left of the picture**.

```
NOT YET RUN
```

This is the layer where the calibration matrix and the output mapping are
applied, so it is the layer that answers "is touch rotated correctly".
The kernel below it knows nothing about rotation; the compositor above it
receives already-mapped coordinates.

**If the corner is wrong, correct it here (in udev), never in the
application.** A matrix in a udev property survives an application
rebuild, a toolkit change and a compositor change. The same correction in
the dashboard survives none of them and has to be found again by the next
person.

---

## Layer 6: the compositor

```sh
journalctl -u weston.service -b --no-pager | head -n 40
```

```
NOT YET RUN
```

### The two messages that mean something other than what they say

| Message | What it is not | What it is |
|---|---|---|
| `could not connect to seat` | a permission problem on `/dev/dri` | the seat broker. logind (through the unit's PAM session) or seatd |
| `no outputs` | a broken panel or ribbon | the compositor opened the DRM card without connectors |

Both send people to the wrong layer, which is why they are in a table
rather than a sentence.

---

## Layer 7: what the compositor offers

```sh
wayland-info | grep -E 'xdg_wm_base|wl_seat|wl_shm'
```

```
NOT YET RUN
```

`wl_seat` must advertise **touch** capability. A seat with only pointer
and keyboard gives a dashboard that ignores fingers, which looks exactly
like a toolkit problem and is not one.

---

## Layer 8: the protocol

```sh
WAYLAND_DEBUG=1 bench-hmi 2>&1 | head -n 50
```

```
NOT YET RUN
```

**On the client. Never on the compositor.** On the compositor it prints
every frame of every client; on a dashboard redrawing twice a second that
buries the journal and the thing you were looking for with it.

What to look for: `wl_touch.down` arriving, and `wl_surface.commit` going
out. One without the other localises the problem to a side.

---

## Layer 9: the toolkit

`LV_USE_LOG` is on at `LV_LOG_LEVEL_WARN`, so LVGL complains on stderr,
which the unit sends to the journal.

```sh
journalctl -u weston.service -b | grep -i lvgl
```

```
NOT YET RUN
```

---

## The deliberate faults

The specification asks for one fault injected at each layer, with a note
on which tool showed it first. That is the exercise that turns the table
above from a list into a skill.

| Fault to inject | Expected first sign | Layer it should point at |
|---|---|---|
| Unplug the keyboard | `wl_seat` loses keyboard capability | 7 |
| Break the calibration matrix in udev | wrong corner in `libinput debug-events` | 5 |
| Point the compositor at the v3d card | `no outputs` in the journal | 6, pointing at 2 |
| Remove `[autolaunch]` from weston.ini | compositor up, no client | 8 |
| Unload `edt_ft5x06` | no touch device in `bench-gfx input` | 4 |

```
NOT YET RUN
```

**Record which tool showed each one first, and whether it was the tool
the table predicts.** Where it was not, the table is what needs
correcting, because a document that disagrees with the board is the
document that is wrong.

---

Back to [DESIGN.md](DESIGN.md), the
[bring-up notes](BRINGUP.md), or the [project README](../README.md).
