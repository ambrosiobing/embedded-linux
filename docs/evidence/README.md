# Portfolio evidence

What goes here, and how each item is produced. Empty until the board has
actually run; nothing in this folder should be written from expectation.

| File | How to produce it |
|---|---|
| `boot-console.log` | `picocom -b 115200 --logfile docs/evidence/boot-console.log /dev/ttyUSB0`, then power the board on. Text, not a screenshot, so that the timings can be read and quoted. |
| `packages.txt` | `./go packages > docs/evidence/packages.txt` |
| `kconfig-check.txt` | `./go kconfig > docs/evidence/kconfig-check.txt` |
| `reproduce.txt` | `./go reproduce > docs/evidence/reproduce.txt`, the diff of the two buildhistory package lists |
| `sdk-check.txt` | `./go sdk-check > docs/evidence/sdk-check.txt`, plus the output of running the binary on the board |
| `leds.mp4` | About 20 s: green, then `systemctl stop sshd.socket`, red, then `systemctl start sshd.socket`, green again |
| `build-times.md` | Wall-clock of the first build and of a warm rebuild, with the host's core count and RAM |
