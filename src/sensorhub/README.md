# sensorhub

Project 12 userspace daemon (`sensorhubd`) and D-Bus CLI client (`hubctl`).

- `proto.[ch]`: Framed CRC-16 + CBOR wire protocol parser (shared with firmware).
- `sensorhubd.c`: `sd-bus` / `sd-event` daemon exposing `org.bench.SensorHub1` on the system bus with polkit calibration authorization.
- `hubctl`: Python `dbus-next` client CLI.

## Host Build

```sh
make -C src/sensorhub
```
