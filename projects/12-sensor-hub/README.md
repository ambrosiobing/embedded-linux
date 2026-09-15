# Project 12: a sensor-hub D-Bus service over UART

**Board:** Raspberry Pi 4, with a NUCLEO-H7A3ZI-Q and an X-NUCLEO-IKS5A1.
**Theme:** wire protocols with CBOR, sd-bus system services, polkit, socket
and device activation.

Projects 5 and 10 put sensors under the kernel's IIO subsystem. This one
takes the opposite architecture, and the more common one in industry: the
sensors hang off a microcontroller running its own firmware, and Linux sees
a serial stream.

That puts the interesting engineering at two boundaries neither of the
other projects touches. The wire protocol between the MCU and Linux, which
needs framing, integrity, bounds and a versioning rule. And the IPC
interface between a privileged daemon and unprivileged applications, which
needs an object model, an activation model and an authorisation model.
Both have to fail loudly and recover by themselves, and both are what an
interviewer means by "system integration".

D-Bus is the piece most embedded engineers know only as a name. Here the
service is written with sd-bus, the library systemd itself uses, so the
object model, the two activation paths and the two authorisation layers are
learned by building them.

## State

**Everything on the Linux side is written; the firmware is specified and
not written; nothing has run on hardware.** No image has been built, no
Nucleo has been flashed, and the D-Bus service has never owned a name on a
real bus.

What is proven today, on a laptop and in CI:

| Proven | How |
|---|---|
| The protocol is self-consistent and its parser recovers from every wire fault | `tests/sensorhub-proto-test.sh`, 41 assertions |
| The C and the specification agree byte for byte, including 200 randomised streams | `tests/sensorhub-cabi-test.sh` |
| `sensorhubd` compiles clean with `-Wall -Wextra -Werror` against libsystemd and libcbor | `./go check` and CI |
| The eight files that must agree with each other do | `tests/sensorhub-policy-test.sh`, 53 assertions |
| Every accessor and macro used here exists with the signature used | read out of the upstream headers, see the [journal](JOURNAL.md) |

What none of that proves: that the daemon owns its name, that the polkit
rule grants what it should, that udev names the device, or that a single
frame has ever crossed a wire. See
[Acceptance criteria](#acceptance-criteria).

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-bench/bench-sensorhub/files/proto.[ch]` | The wire protocol: framing, CRC-16, CBOR encoding and an incremental parser. Compiled into the firmware **and** the daemon |
| `.../files/sensorhubd.c` | The daemon: sd-bus vtable, sd-event loop, libcbor decoding, polkit |
| `.../files/hubctl` | A Python client that knows nothing about the wire |
| `.../files/*.conf, *.service, *.policy, *.rules` | Bus policy, bus activation, polkit action, polkit rule, udev rule, systemd unit |
| `meta-bench/recipes-core/images/bench-hub-image.bb` | `bench-image` plus the bus, polkit, the daemon and OpenOCD |
| `kas/bench-hub.yml` | The polkit distro feature, and a much smaller JavaScript engine for it |
| `tests/sensorhub_reference.py` | An independent second implementation of the protocol, in Python |
| `tests/sensorhub-*.sh` | Three suites: the protocol, the C against the specification, and the files against each other |

## Running it

```sh
./go check               # about 2 minutes, no board and no Nucleo
./go hub                 # bench-hub-image for the Raspberry Pi 4
./go flash /dev/sdX
```

On the board, without writing any client code:

```sh
busctl --system introspect org.bench.SensorHub1 /org/bench/SensorHub1
busctl --system call org.bench.SensorHub1 /org/bench/SensorHub1 \
       org.bench.SensorHub1 SetRate u 200
busctl --system monitor org.bench.SensorHub1
```

and with it:

```sh
hubctl                   # firmware, protocol, rate, dropped frames
hubctl rate 200
hubctl monitor 10        # counts signals, compares against the property
hubctl calibrate         # denied unless you are in the bench group
```

[docs/PROTOCOL.md](docs/PROTOCOL.md) is the specification of record: the
frame, the message catalogue, the bounds, the resynchronisation rule, the
bandwidth budget and both versioning rules. It was written before any code.

[docs/DESIGN.md](docs/DESIGN.md) is the methodology: architecture,
schematic, bench layout, the interface as a class, the two reply
strategies as sequences, the activation state machine and the two
authorisation layers.

[docs/BRINGUP.md](docs/BRINGUP.md) is the board work in order, from the
first `dmesg | grep cdc_acm` to a client counting signals.

[firmware/README.md](firmware/README.md) is what is not written yet, in
enough detail to be written: the CubeMX settings, the file list, and the
sampling loop.

## What is in the image beyond Project 1, and why

| Package | Why it is there | What breaks without it |
|---|---|---|
| `dbus` | The system bus. `core-image-minimal` with systemd does not install it | no bus, and the daemon exits at `sd_bus_open_system` |
| `dbus-tools` | `dbus-monitor` and `dbus-send` | nothing, until a bus question gets strange |
| `polkit` | Answers whether a caller may calibrate | `Calibrate` fails for everybody, including root |
| `libcbor` | Decodes untrusted payloads | no daemon |
| `python3-dbus-next` | The client builds its proxy from introspection | `hubctl` only |
| `openocd` | Flashes the hub over the same USB cable | the update path needs a laptop and a debugger |
| `kernel-module-cdc-acm` | `core-image-minimal` installs no kernel modules at all | the device enumerates, `dmesg` shows the descriptor, and no tty ever appears |

The last row is the third time this repository has paid for the same
lesson: the radio driver in Project 1, `spidev` in Project 8, and now the
ACM driver. A Yocto image contains the modules you named and no others.

## Acceptance criteria

| # | Criterion | Evidence | State |
|---|---|---|---|
| 1 | `busctl introspect` shows two methods, four properties and one signal, and the XML validates | the introspection output | **written**, needs a board |
| 2 | At 100 Hz for an hour, `FramesDropped` stays at zero and the signal count matches the hub's | the property and a counting client | **not started** |
| 3 | `SetRate 200` returns within 250 ms, `PropertiesChanged` follows, and the measured rate is 200 +/- 2 Hz | `hubctl monitor` after `hubctl rate` | **not started** |
| 4 | A user outside the `bench` group gets `AccessDenied` on `Calibrate`; a member gets a reply within 3 s | two shells, two users | **not started** |
| 5 | Unplugging stops the unit within 2 s; replugging starts it within 3 s and the first signal follows within another second | `journalctl -f -u sensorhubd` across a replug | **not started** |
| 6 | A firmware with a bumped major version makes the daemon refuse the stream, log once, and expose the mismatch without crashing | the `ProtocolVersion` property and one log line | **written and reviewed**, needs two firmware builds |
| 7 | Flashing with OpenOCD from the Pi and restarting the unit takes under 30 s | timed | **not started** |
| 8 | The two implementations of the protocol agree | `tests/sensorhub-cabi-test.sh` | **met**, in CI |
| 9 | The eight files that name each other agree | `tests/sensorhub-policy-test.sh` | **met**, 53 assertions |

Criteria 8 and 9 are not in the original list. They were added because they
are the two things that can be proven without hardware, and a project whose
only checks need hardware is a project that gets debugged on hardware.

## What is tested without hardware

| Check | Command | Covers |
|---|---|---|
| The protocol | `sh tests/sensorhub-proto-test.sh` | Frozen wire vectors, the CRC check value, preferred serialisation, the bounds, and a parser fed garbage, split frames, corrupted CRCs, absurd lengths and a lost byte |
| The C against the spec | `sh tests/sensorhub-cabi-test.sh` | Every encoder byte for byte, the CRC over 500 random buffers, and the parser over 200 randomised streams, through ctypes |
| The files against each other | `sh tests/sensorhub-policy-test.sh` | Interface name, object path, action id, device path and unit name, compared across the daemon, the bus policy, the activation file, the polkit action and rule, the udev rule, the unit and the recipe |
| The daemon compiles | `./go check` | `-Wall -Wextra -Werror` against libsystemd and libcbor, which is the only check anywhere that reads the vtable |

Not covered, and only a board can cover it: that the name can be owned,
that polkit answers as the rule says, that udev fires, that `BindsTo`
stops the unit, that the ST-LINK enumerates, and every number in criteria
2 to 7.

## Departures from the original scope

| # | As originally scoped | Here | Why |
|---|---|---|---|
| 1 | tinycbor in the firmware for encoding | Hand-written encoding in `proto.c`, shared by both ends | The five payloads are fixed in shape; encoding them is forty lines with no dependency and no allocation. Decoding stays a library's job, because that input is untrusted |
| 2 | `proto.c` implements framing; CBOR is separate | `proto.c` implements both | They are one protocol. Splitting them would mean two files to keep in step across two toolchains |
| 3 | The daemon in four source files | Two: the protocol and the daemon | The protocol is the part that is shared and separately testable. The rest is one event loop, and splitting an event loop across files hides the thing worth seeing |
| 4 | Properties declared with `offsetof` | Explicit getters | `offsetof` with a signature is unchecked: a field whose C type does not match compiles cleanly and reads the wrong bytes. Four lines each buys the compiler's opinion |
| 5 | `CheckAuthorization` with `AllowUserInteraction = 1` | 0 | A system service must not block a bus call while polkit looks for an agent. The project's own pitfall list warns about exactly that, and the rule makes interaction unnecessary |
| 6 | polkit as built by default | Built with duktape instead of mozjs | SpiderMonkey is tens of megabytes of rootfs and one of the longest compiles in the build, to run eleven lines of rule. The risk is stated in `kas/bench-hub.yml` |
| 7 | A meson build | The recipe's `do_compile`, like every other bench recipe | Two source files. A build system would be the largest thing in the directory |

## Pitfalls, and what guards each one

| Pitfall | Guard |
|---|---|
| A charge-only micro-USB cable | The bring-up notes check `dmesg` for the `cdc_acm` line before anything else |
| ModemManager probing the new ACM device with AT commands | `ENV{ID_MM_DEVICE_IGNORE}="1"` in the udev rule, asserted by a test |
| A handler blocking past the bus timeout | `SetRate` is bounded at 200 ms from the monotonic clock; `Calibrate` defers its reply |
| `sd_bus_emit_signal` at a rate that fills a slow client's queue | The payload is 56 bytes and the maximum rate is documented as 1 kHz |
| A method that needs `CAP_SYS_ADMIN` because the flag was forgotten | `SD_BUS_VTABLE_UNPRIVILEGED` on both methods, with the reason in a comment |
| OpenOCD and the daemon sharing the ST-LINK | Flashing resets the device, which drops the tty, which stops the unit through `BindsTo`. The CRC errors during a flash are counted, not fatal |
| The red 5 V lead of the USB/TTL cable | Named in the schematic and in the bring-up notes, both times in the same sentence as the consequence |
| A length field corrupted into nonsense | The parser rejects anything above 512 and steps forward one byte, never trusting the length it was told |

---

[Journal](JOURNAL.md) | [Protocol](docs/PROTOCOL.md) |
[Design](docs/DESIGN.md) | [Bring-up](docs/BRINGUP.md) |
[Firmware](firmware/README.md)
