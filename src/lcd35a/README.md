# lcd35a

Userspace utilities for the 3.5-inch SPI DRM panel (`ili9486`) and resistive touch controller (`ads7846`).

- `drmfill.c`: Locates the `ili9486` DRM card by driver name and paints a gradient test frame.
- `lcd35a-corners`: Computes a libinput `LIBINPUT_CALIBRATION_MATRIX` from four raw corner readings.
- `lcd35a-verify`: On-target diagnostic script checking DRM panel, touch input, and overlay state.

## Host Build

```sh
make -C src/lcd35a
```
