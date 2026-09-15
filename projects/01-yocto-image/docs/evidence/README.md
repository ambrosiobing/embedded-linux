# Portfolio evidence

What goes here, and how each item is produced. Empty until the board has
actually run; nothing in this folder should be written from expectation.

| File | How to produce it |
|---|---|
| `boot-timing.txt` | `systemd-analyze && systemd-analyze blame \| head -20 && dmesg \| head -40` on the board. Settles the 15 second criterion without needing a serial capture |
| `packages.txt` | `./go packages > projects/01-yocto-image/docs/evidence/packages.txt` |
| `kconfig-check.txt` | Best taken against the running kernel rather than a build tree, since a build that is a complete sstate hit never compiles one: `scp root@BOARD:/proc/config.gz /tmp/`, `zcat /tmp/config.gz > /tmp/config`, then `./go kconfig /tmp/config` |
| `reproduce.txt` | `./go reproduce > projects/01-yocto-image/docs/evidence/reproduce.txt`, the diff of the two buildhistory package lists |
| `sdk-check.txt` | `./go sdk-check > projects/01-yocto-image/docs/evidence/sdk-check.txt`, plus the output of running the binary on the board |
| `state-transition.txt` | `bench-state show`, then `systemctl stop sshd.socket`, then `bench-state show` again. The state machine on hardware, without needing LEDs |
| `leds.mp4` | Deferred. Needs three bare LEDs or an LK-Cable, see the project README |
| `build-times.md` | Wall-clock of the first build and of a warm rebuild, with the host's core count and RAM |
