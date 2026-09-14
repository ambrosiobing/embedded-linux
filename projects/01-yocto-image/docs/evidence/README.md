# Portfolio evidence

What goes here, and how each item is produced. Empty until the board has
actually run; nothing in this folder should be written from expectation.

| File | How to produce it |
|---|---|
| `boot-console.log` | `picocom -b 115200 --logfile projects/01-yocto-image/docs/evidence/boot-console.log /dev/ttyUSB0`, then power the board on. Text, not a screenshot, so that the timings can be read and quoted. |
| `packages.txt` | `./go packages > projects/01-yocto-image/docs/evidence/packages.txt` |
| `kconfig-check.txt` | `./go kconfig > projects/01-yocto-image/docs/evidence/kconfig-check.txt` |
| `reproduce.txt` | `./go reproduce > projects/01-yocto-image/docs/evidence/reproduce.txt`, the diff of the two buildhistory package lists |
| `sdk-check.txt` | `./go sdk-check > projects/01-yocto-image/docs/evidence/sdk-check.txt`, plus the output of running the binary on the board |
| `state-transition.txt` | `bench-state show`, then `systemctl stop sshd.socket`, then `bench-state show` again. The state machine on hardware, without needing LEDs |
| `leds.mp4` | Deferred. Needs three bare LEDs or an LK-Cable, see the project README |
| `build-times.md` | Wall-clock of the first build and of a warm rebuild, with the host's core count and RAM |
