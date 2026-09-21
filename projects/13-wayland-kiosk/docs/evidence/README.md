# Evidence

Raw output from the board goes here, unedited. Nothing in this directory
yet, because no board has run this image.

What belongs here, named by the document that refers to it:

| File | Referred to by | What it is |
|---|---|---|
| `boot-before.svg` | [BOOT-TIME.md](../BOOT-TIME.md) | `systemd-analyze plot`, before trimming |
| `boot-after.svg` | [BOOT-TIME.md](../BOOT-TIME.md) | the same, after |
| `drm-info.txt` | [DEBUGGING.md](../DEBUGGING.md) | `drm_info`, once there is a recipe for it |
| `libinput-corners.txt` | [DEBUGGING.md](../DEBUGGING.md) | `libinput debug-events` while touching each corner |
| `wayland-info.txt` | [DEBUGGING.md](../DEBUGGING.md) | the compositor's globals, showing `wl_seat` touch capability |
| `wayland-debug-client.txt` | [DEBUGGING.md](../DEBUGGING.md) | `WAYLAND_DEBUG=1` on the client, first 50 lines |
| `bench-gfx.txt` | [BRINGUP.md](../BRINGUP.md) | all four layers on a healthy board |
| `lsmod.txt` | [BRINGUP.md](../BRINGUP.md) | which modules actually loaded, which is the only honest basis for narrowing `kernel-modules` to a named list later |

**Raw, not a paraphrase.** The value of a stored `libinput` trace six
months later is in the detail nobody thought was interesting at the time.
Include the tool version at the top of each capture.

**A capture from a board that was not healthy is still evidence**, as
long as it says so. The failure captures are the more useful half of
`DEBUGGING.md`, because a document that only ever shows working output
teaches nobody to recognise the other kind.
