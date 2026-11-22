# kbd-bridge

Bridges a physical USB keyboard grabbed via `libevdev` to a USB HID gadget (`/dev/hidg0`) with a macro FIFO.

- `kbd_bridge.c`: `libevdev` + `poll()` daemon translating Linux input keycodes to boot-protocol HID reports.
- `usage_table.h`: Checked-in Linux keycode to HID usage lookup table.
- `gen-usage-table.py`: Generator that parses the kernel's `hid-input.c` to produce `usage_table.h`.

## Host Build

```sh
make -C src/kbd-bridge
```
