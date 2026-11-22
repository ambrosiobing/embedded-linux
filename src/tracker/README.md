# tracker

Low-power Cat-M and NB-IoT CoAP position tracker and GPIO control tool (`bench-tracker`).

- `tracker-gpio.c`: `libgpiod` v2 utility pulsing modem `PWRKEY` and holding the power-profiler report marker line.
- `tracker`: Pure-stdlib Python AT-command state machine driving attach, PSM, CoAP POST, and sleep cycles.

## Host Build

```sh
make -C src/tracker
```
