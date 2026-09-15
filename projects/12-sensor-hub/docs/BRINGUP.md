# Bring-up: from a flashed card to a client counting signals

In order, because a fault introduced at step 2 is unrecognisable at step 8.

Nothing below has been performed. It is the plan, written alongside the
code, and the [journal](../JOURNAL.md) is where it gets corrected once it
meets hardware.

## 0. Before the power goes on

| Check | Why |
|---|---|
| The IKS5A1 is seated on the Arduino headers of the Nucleo | It draws its 3.3 V from there; nothing external powers it |
| The micro-USB cable is a **data** cable | A charge-only cable powers the Nucleo perfectly and never enumerates. This is the single most common half hour lost on this project |
| Nothing is connected to the red lead of the USB/TTL cable, if you use one | The Nucleo is already powered from USB, and 5 V back into a powered board kills a regulator |
| The Pi has its own USB-C supply | The Pi powering a Nucleo over USB is fine; a Pi on a weak supply powering one is not |

## 1. The device has to exist before anything else

Boot `bench-hub-image`, plug the Nucleo into a USB-A port of the Pi.

```sh
dmesg | grep -i cdc_acm
ls -l /dev/ttyACM* /dev/sensorhub
lsusb | grep -i st-link
```

Three failures, in the order they happen:

| Symptom | Cause |
|---|---|
| Nothing in `lsusb` | The cable, or the Nucleo is not powered. Its LD1 should be lit |
| `lsusb` finds it, no `cdc_acm` line in `dmesg` | `kernel-module-cdc-acm` is not in the image. `core-image-minimal` installs no modules at all, and this is the third project to find that out |
| `/dev/ttyACM0` exists, `/dev/sensorhub` does not | The udev rule did not match. `lsusb` prints the product ID; compare it with the one in `80-sensorhub.rules` |

**The product ID is the line to check on a new board.** ST uses 0x3748,
0x374b, 0x374e and others across ST-LINK versions, and the V3E on this
Nucleo is not the V2-1 on older ones. If it differs:

```sh
udevadm info -a -n /dev/ttyACM0 | grep -m2 'idVendor\|idProduct'
```

then fix the rule in the layer and rebuild rather than editing it on the
board, where the next flash will overwrite it.

## 2. Look at the raw stream before writing anything

Before the daemon, confirm that frames are arriving and that they are the
frames the specification describes.

```sh
stty -F /dev/sensorhub 921600 raw -echo
timeout 2 od -An -tx1 -N 64 < /dev/sensorhub
```

Expect `a5 01` to appear regularly. `a5` is the start of frame and `01`
is the protocol major version. If the first bytes after a reset are
garbage, that is the ST-LINK handing over what it buffered before the
reset; the daemon flushes it at startup for exactly this reason.

If `a5 01` never appears but bytes do, the baud rate is wrong. If nothing
arrives at all, the firmware is not running or USART3 is not routed to the
ST-LINK through the solder bridges.

## 3. The daemon, by hand first

```sh
systemctl stop sensorhubd 2>/dev/null
sudo -u sensorhub /usr/bin/sensorhubd /dev/sensorhub
```

Running it in the foreground as its own user is the fastest way to find
the two failures that are otherwise confusing:

| Message | Meaning |
|---|---|
| `cannot own org.bench.SensorHub1` | The bus policy is missing or names a different user. Check `/usr/share/dbus-1/system.d/` |
| `/dev/sensorhub: Permission denied` | The `sensorhub` user is not in the group that owns the device. The udev rule sets `GROUP="dialout"` and the unit sets `SupplementaryGroups=dialout` |

The first line it prints on success names the interface, the object and
the device. Leave it running for the next step.

## 4. Introspect, which needs no client

```sh
busctl --system introspect org.bench.SensorHub1 /org/bench/SensorHub1
```

Two methods, four properties, one signal, plus the two standard
interfaces sd-bus provides. If `Properties` or `Introspectable` are
missing, the vtable was registered on the wrong path.

```sh
busctl --system get-property org.bench.SensorHub1 /org/bench/SensorHub1 \
       org.bench.SensorHub1 FirmwareVersion
busctl --system monitor org.bench.SensorHub1
```

`FirmwareVersion` reads `unknown` until a HELLO has arrived. If it stays
`unknown` while samples flow, the firmware is not sending HELLO after
reset, which the protocol requires.

## 5. SetRate, and the reason the property changes late

```sh
busctl --system call org.bench.SensorHub1 /org/bench/SensorHub1 \
       org.bench.SensorHub1 SetRate u 200
busctl --system get-property org.bench.SensorHub1 /org/bench/SensorHub1 \
       org.bench.SensorHub1 RateHz
```

The property should read 200, and it only reads 200 because the hub
acknowledged. Two failures worth causing on purpose:

```sh
# out of range: rejected before anything reaches the wire
busctl --system call ... SetRate u 5000        # InvalidArgs

# with the Nucleo in reset: nothing acknowledges
busctl --system call ... SetRate u 200         # Error.NoAck after 200 ms
```

`NoAck` arriving after about 200 ms rather than after the bus timeout is
the thing to check. A handler that blocked longer would hang every client
of the daemon, not only this one.

## 6. Activation, both ways

Stop the daemon and let the bus start it:

```sh
systemctl stop sensorhubd
systemctl status sensorhubd          # inactive
busctl --system get-property org.bench.SensorHub1 /org/bench/SensorHub1 \
       org.bench.SensorHub1 RateHz
systemctl status sensorhubd          # active, started by the call
```

Then let udev start it:

```sh
journalctl -f -u sensorhubd &
# unplug the Nucleo
#   expect: the unit stops within about two seconds, BindsTo
# plug it back in
#   expect: udev, the device unit, the service, then the first signal
```

If unplugging does nothing, `BindsTo` is bound to a device unit that does
not exist, which means `TAG+="systemd"` is missing from the udev rule.
The unit name systemd uses for `/dev/sensorhub` is `dev-sensorhub.device`:

```sh
systemctl status dev-sensorhub.device
```

## 7. polkit, from two accounts

```sh
# as root, or as a member of bench
hubctl calibrate                     # replies within about 3 s

# as a user who is not in bench
sudo -u nobody hubctl calibrate      # AccessDenied
```

A denial that arrives instantly is the rule working. A denial that takes
thirty seconds means `AllowUserInteraction` got turned back on and polkit
went looking for an agent that is not there.

To grant it:

```sh
usermod -aG bench someuser           # then log in again
```

If a member of `bench` is still denied, check that polkit loaded the rule
at all. With duktape rather than mozjs a syntax error is reported
differently, and `journalctl -u polkit` is where it says so.

## 8. The measurement the criteria ask for

```sh
hubctl rate 200
hubctl monitor 10
```

Three numbers come back and all three matter: the signal rate measured
over the window, the `RateHz` property, and the rate computed from the
hub's own timestamps. The first two disagreeing means signals are being
lost between the daemon and the client; the third disagreeing with the
other two means the hub's timer is not what it claims.

For criterion 2, leave it running:

```sh
hubctl monitor 3600
busctl --system get-property ... FramesDropped     # expect 0
```

## 9. Flashing, once there is something to flash

```sh
systemctl stop sensorhubd
openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
        -c "program sensorhub.elf verify reset exit"
systemctl start sensorhubd
```

Under 30 seconds end to end is the criterion. Stopping the unit first is
not optional: the reset drops the tty, and flashing while the daemon holds
it produces a burst of CRC errors.

## 10. The version mismatch, deliberately

The last criterion needs two firmware builds, one with
`PROTO_VERSION` bumped to 2. Flash it and watch:

```sh
journalctl -u sensorhubd | tail -3
busctl --system get-property ... ProtocolVersion    # 2
busctl --system get-property ... FramesDropped      # not climbing
```

One log line, not one per frame. The property carries the number the hub
is actually speaking. The daemon keeps running and emits no signals, which
is what "refuse the stream" has to mean: a daemon that crashed would be
restarted by systemd and would crash again, and a daemon that carried on
decoding would publish samples from a layout it does not understand.

---

Back to the [project README](../README.md), the
[protocol](PROTOCOL.md) or the [design](DESIGN.md).
