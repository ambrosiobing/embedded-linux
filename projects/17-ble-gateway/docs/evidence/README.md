# Portfolio evidence

What goes here, and how each item is produced. Empty until the board has
actually run; nothing in this folder should be written from expectation.

The STWIN.box has never been near the Pi. That matters more here than in
most projects, because the field table in [PROTOCOL.md](../PROTOCOL.md)
has never been checked against a captured frame, and the decoder suite
passes against bytes this repository invented. A suite of 29 passing
assertions against synthetic frames is worth having and it is not evidence
about the peripheral.

| File | How to produce it |
|---|---|
| `first-connect.btsnoop` | `btmon -w` across one connection, kept as the raw capture. Criterion 1 wants three things visible in it: LE Create Connection, the CCCD write of `0x0001`, and Handle Value Notifications |
| `first-connect.md` | The walk-through of the capture above, packet by packet, written once so the next reader does not need to open a decoder |
| `frames.txt` | At least three frames lifted from that trace, one per characteristic, with the bytes and the decoded values side by side. Criterion 2 is **partly met** without this file, and this is what moves it: the same suite, run against bytes the peripheral actually sent |
| `rate.txt` | The CSV and `mosquitto_sub` side by side for the same minute, with the connection interval read from the capture. Criterion 3 is that the row rate matches what that interval implies |
| `link-loss.txt` | `journalctl` across a battery removal and replacement, with `systemctl show -p NRestarts` at both ends. Criterion 4 wants red inside the supervision timeout plus 1 s, green again inside 30 s, and `NRestarts` still 0. The logic is proven against a fake link; this is the radio saying the same thing |
| `soak-24h.txt` | `systemctl show -p MemoryCurrent` at the start and the end of a day, with the restart count. Criterion 5 |
| `security-score.txt` | `systemd-analyze security stwin-gw.service`. Criterion 6 is a score below 5, and the unit already carries a comment per directive explaining what each one buys |

The capture is the first file to take and everything else is easier
afterwards, because `frames.txt` comes out of it rather than out of a
second session.
