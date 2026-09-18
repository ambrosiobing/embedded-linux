# Portfolio evidence

What goes here, and how each item is produced. Empty until the board has
actually run; nothing in this folder should be written from expectation.

This project is blocked on something no Linux work can unblock: the
firmware is specified and not written, and [firmware/README.md](../../firmware/README.md)
says why that is deliberate. Until a Nucleo streams frames, the daemon has
no peer, and the two criteria the [project README](../../README.md) marks
met are met in CI rather than on a bus.

| File | How to produce it |
|---|---|
| `introspect.xml` | `busctl introspect org.bench.SensorHub1 /org/bench/SensorHub1 --xml-interface` on the board. Criterion 1 wants two methods, four properties and one signal, and the XML to validate |
| `soak-1h.txt` | The hub at 100 Hz for an hour, then `FramesDropped` read once at each end beside a client's own count of signals received. Criterion 2 is that the first stays at zero and the two counts agree |
| `setrate.txt` | `hubctl monitor` in one shell, `hubctl rate 200` in another. Criterion 3 wants three things from one capture: the call returning inside 250 ms, `PropertiesChanged` following it, and the measured rate at 200 +/- 2 Hz |
| `polkit-denied.txt` | Two shells, two users. A member of `bench` calling `Calibrate` and getting a reply inside 3 s, and a non-member getting `AccessDenied`. Criterion 4, and it is the one that proves the policy file is doing something rather than merely being installed |
| `replug.txt` | `journalctl -f -u sensorhubd` across an unplug and a replug. Criterion 5 wants the unit stopped within 2 s, started within 3 s, and the first signal within another second |
| `version-mismatch.txt` | Two firmware builds, the second with a bumped major. Criterion 6 is that the daemon refuses the stream, logs once rather than per frame, and exposes the mismatch through `ProtocolVersion` without crashing |
| `openocd-flash.txt` | Flashing the Nucleo from the Pi over OpenOCD and restarting the unit, timed. Criterion 7 is under 30 s, and the number to record is the whole cycle rather than the flash alone |

The introspection file is the one to take first. It needs no firmware, only
a running daemon on a real bus, and it turns "written" into "owns a name".
