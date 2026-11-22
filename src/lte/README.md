# lte

Cellular modem GPIO controller, watchdog, and Prometheus metrics exporter (`bench-lte`).

- `lte-gpio.c`: `libgpiod` v2 utility driving the modem `PWRKEY` and `FLIGHT` lines.
- `lte-watchdog`: Escalating cellular bearer supervisor (`nmcli` -> `mmcli --reset` -> `lte-gpio pwrkey`).
- `lte-exporter`: Collects ModemManager and routing state into Prometheus textfile metrics.

## Host Build

```sh
make -C src/lte
```
