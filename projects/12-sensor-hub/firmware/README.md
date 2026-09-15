# The firmware side: what exists, and what does not

**Not written.** This directory contains no project and no source, and
that is deliberate rather than unfinished.

What does exist is the half of the firmware that matters and is portable:
`proto.c` and `proto.h` in the layer are compiled into the firmware
unchanged. Framing, the CRC and the CBOR encoding of all five message
types are therefore already written, already frozen against golden vectors
and already compared byte for byte against an independent implementation
in CI. What is missing is the part that is specific to one vendor's HAL:
clock setup, I2C, DMA and a timer.

## Why it is not here

An STM32CubeIDE project is several thousand lines of generated code,
pinned to one version of one vendor's code generator, that cannot be
built, tested or reviewed anywhere in this repository's toolchain. Writing
one by hand and committing it would produce a directory that looks like
working firmware and has never been compiled. This repository has one rule
about that, applied to the board work of every project: say what has not
been done.

The generated project belongs on the machine that runs CubeMX, and what
belongs here is everything needed to regenerate it and the part that is
not generated.

## What to generate

New STM32CubeIDE project for **NUCLEO-H7A3ZI-Q**, board selected rather
than MCU selected, so that the ST-LINK and the clock tree come configured.

| Peripheral | Setting | Why |
|---|---|---|
| I2C1 | PB8 SCL, PB9 SDA, 400 kHz, fast mode | The Arduino D15 and D14 pins the shield sits on. Confirm against the MB1363 user manual for your board revision before trusting it |
| USART3 | PD8 TX, PD9 RX, 921600 baud, 8N1 | The virtual COM port, through the Nucleo's default solder bridges. 921600 rather than 115200: see the bandwidth budget in PROTOCOL.md |
| USART3 TX | DMA, normal mode, memory to peripheral | A blocking transmit at 1 kHz would spend a third of the budget waiting on the UART |
| TIM | 1 kHz update interrupt | The sampling tick. The rate divider in software, so SET_RATE does not reprogram a timer |
| Second USART | optional, any Zio pin | Trace output while the VCP is busy carrying frames |

## What to add

| Source | From |
|---|---|
| `lsm6dsv32x_reg.c`, `.h` | ST's `STMems_Standard_C_drivers` repository |
| `proto.c`, `proto.h` | This repository, unchanged, from `meta-bench/recipes-bench/bench-sensorhub/files/` |

If the X-CUBE-MEMS1 release in use already ships an IKS5A1 BSP, its
`iks5a1_motion_sensors.c` wrappers can be used instead of calling the
register driver directly. They are wrappers over the same driver, so
nothing about the protocol changes either way.

No CBOR library. That is the point of encoding by hand: tinycbor would be
a noticeable fraction of the image for five payloads whose shape never
changes.

## The sampling loop

`proto.c` provides everything except the HAL calls, so the loop is short:

```c
#include "proto.h"

static volatile int tick;        /* set by the 1 kHz timer interrupt */
static uint32_t divider = 10;    /* 1 kHz / 10 = the default 100 Hz */

static void send_sample(uint64_t t_us, const float a[3], const float g[3],
                        float temp)
{
    uint8_t frame[PROTO_MAX_FRAME];
    uint8_t payload[128];
    int n, total;

    n = proto_encode_sample(payload, sizeof payload, t_us, a, g, temp);
    if (n < 0)
        return;                  /* cannot happen with a 128 byte buffer */
    total = proto_frame(frame, sizeof frame, PROTO_SAMPLE, payload,
                        (size_t)n);
    if (total > 0)
        HAL_UART_Transmit_DMA(&huart3, frame, (uint16_t)total);
}
```

and the command side is the same parser Linux uses:

```c
static struct proto_parser parser;

static void on_frame(void *user, uint8_t version, uint8_t type,
                     const uint8_t *payload, size_t len)
{
    /* Decode the one integer each command carries, acknowledge, act. */
}

/* in the USART3 RX callback */
proto_parser_push(&parser, rx_chunk, rx_len, on_frame, NULL);
```

Three rules the firmware has to keep, all of them from PROTOCOL.md:

1. **HELLO after every reset**, before any sample, carrying the minor
   version, the firmware version string and the sensor names. The daemon
   logs it and publishes the firmware version.
2. **ACK every command**, with the type being acknowledged and a status.
   `SetRate` on the Linux side waits 200 ms for it and fails the D-Bus
   call if it does not come.
3. **Acknowledge before acting on SET_RATE**, or at least before the next
   sample goes out at the new rate. The daemon changes its property when
   the ACK arrives, and a sample at the new rate arriving first would make
   the property briefly wrong.

## Flashing, from the Pi

The same USB cable carries SWD, so the board that reads the sensor also
programs it. `bench-hub-image` includes OpenOCD for exactly this.

```sh
# on the Pi
systemctl stop sensorhubd          # the reset closes and reopens the CDC
openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
        -c "program sensorhub.elf verify reset exit"
```

Stopping the unit first is not optional: the reset drops the tty, and a
flash while the daemon holds it produces a burst of CRC errors and a
restart. `BindsTo` will stop the unit anyway when the device disappears,
but doing it deliberately keeps the journal readable.

## Testing the firmware half without a Nucleo

`proto.c` is the firmware's protocol implementation, and it is already
covered: `tests/sensorhub-cabi-test.sh` compiles that exact file and
compares every encoder and the parser against an independent Python
implementation, including 200 randomised streams. A bug in the framing on
the firmware side is a bug CI already catches.

What that cannot cover is the HAL half: whether the DMA transfer
completes before the next one starts, whether the I2C read blocks the
tick, whether the timestamp comes from a monotonic source. Those need the
board.

---

Back to the [project README](../README.md), or the
[protocol](../docs/PROTOCOL.md).
