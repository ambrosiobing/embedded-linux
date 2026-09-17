# Bindings used, with the source that settled each one

One entry per binding in
[the overlay](../../../meta-bench/recipes-bench/bench-explorer700/files/bench-explorer700-overlay.dts),
with the file and line that decided it rather than a recollection of what
the binding looks like.

The reason for citing source rather than documentation: the specification
asserted one of these mechanisms correctly and another one impossibly, in
the same paragraph and the same confident voice, and nothing about the
writing distinguished them. Reading the driver is cheap and it is the only
thing that tells them apart.

All references are Linux 6.6, which is what `linux-raspberrypi` builds on
scarthgap, except where a Raspberry Pi tree is named explicitly.

## maxim,ds3231

**Driver** `drivers/rtc/rtc-ds1307.c`. The compatible is in the of_match
table at line 1106, `{ .compatible = "maxim,ds3231", ... }`, which is why a
chip marked DS3231 is driven by a file named for the DS1307.

**Interface** `/dev/rtc0`, `hwclock`, and systemd's clock restore.

**Worth knowing.** The driver also registers a hwmon temperature channel
for DS3231 devices (`ds3231_hwmon_read_temp`, line 1331), so this board has
two temperature sources before the DS18B20 is plugged in.

## nxp,pcf8574

**Driver** `drivers/gpio/gpio-pcf857x.c`, of_match at line 39,
`{ .compatible = "nxp,pcf8574", (void *)8 }`. The 8 is the line count.

**Interface** a gpiochip, so `/dev/gpiochipN`, `gpioinfo`, `gpioget`.

**Worth knowing.** The driver installs an interrupt chip when the I2C
client has an irq (line 372, `if (client->irq)`), which is what would make
the expander's lines usable as interrupt sources rather than polled ones.
The Explorer 700 wires that line to GPIO21 and this overlay deliberately
does not use it; [DESIGN.md](DESIGN.md) has the argument.

## nxp,pcf8591

**Driver** `drivers/hwmon/pcf8591.c`, and **it has no of_match table at
all**. Only an `i2c_device_id` at line 287 whose name is `pcf8591`.

**Why it binds anyway.** `of_i2c_get_board_info` in
`drivers/i2c/i2c-core-of.c` line 30 fills `info->type` from
`of_alias_from_compatible`, which is `drivers/of/base.c` line 1041 and is
four lines long: it takes the first compatible string, finds the comma with
`strchr`, and copies from one past it. So `nxp,pcf8591` becomes the client
name `pcf8591` and `i2c_match_id` matches the table above.

The specification states this mechanism and states it correctly. It is
cited here rather than trusted because the same paragraph also names a
driver that cannot bind this board's display at all, and the two claims
read identically.

**Interface** hwmon, so `/sys/class/hwmon/hwmonN/in0_input` and
`sensors(1)`. Never IIO.

**Worth knowing.** Single-ended versus differential inputs is a **module
parameter**, `input_mode` at line 21, not a device tree property. On this
board all four inputs leave through a screw terminal, so the default is as
good as any until something is wired to them.

## bosch,bmp280

**Driver** `drivers/iio/pressure/bmp280-i2c.c`, of_match at lines 32 to 37.
Six entries: `bmp085`, `bmp180`, `bmp280`, `bme280`, `bmp380`, `bmp580`.

That list is why the unresolved part identity on this board is cheap. Both
candidates are in the same table with different `chip_info`, so the fix if
the guess is wrong is one string in the overlay and no other change
anywhere.

**Interface** IIO, so `/sys/bus/iio/devices/iio:deviceN/in_pressure_input`
and `in_temp_input`.

**Kernel configuration** `CONFIG_BMP280` is in the Raspberry Pi 3 defconfig
as a module and **`CONFIG_BMP280_I2C` is not in it at all**, which would
give a driver core with no bus glue: the symbol exists, the part never
probes, and nothing reports it.

## solomon,ssd1306, on SPI

**This is the binding the specification gets wrong**, and the reason is
worth stating precisely because it is not a property mistake.

The specification says `solomon,ssd1306fb-i2c` with the `ssd1307fb` driver.
That driver is `drivers/video/fbdev/ssd1307fb.c`; its Kconfig entry
`FB_SSD1307` at `drivers/video/fbdev/Kconfig` line 1928 reads **`depends on
FB && I2C`**, and the driver is registered as an I2C driver. It has no SPI
probe path. No device tree property makes an SPI panel reachable by it.

The Explorer 700's panel is 4-wire SPI: the vendor manual's page 3 draws
CS, RES, D/C, SCK and MOSI, and its chapter 16 tells you to enable SPI
before running the display examples.

**Driver used instead** `drivers/gpu/drm/solomon/ssd130x-spi.c`, of_match
from line 112, taking the plain `solomon,ssd1306` with no bus suffix.

**Required property.** `dc-gpios`, and it is not optional:

```c
dc = devm_gpiod_get(dev, "dc", GPIOD_OUT_LOW);
if (IS_ERR(dc))
        return dev_err_probe(dev, PTR_ERR(dc), "Failed to get dc gpio\n");
```

`devm_gpiod_get` and not `devm_gpiod_get_optional`. A 4-wire SPI interface
has no room for the control byte that carries data-versus-command on I2C,
so the pin is the mechanism rather than a convenience. `reset-gpios` is
optional (`devm_gpiod_get_optional`, `ssd130x.c` line 1066) and is wired on
this board, so it is declared.

**Interface** DRM, so `/dev/dri/card0`. A `/dev/fbN` exists only through
the fbdev shim, which the driver sets up with
`drm_fbdev_generic_setup(drm, 32)` at `ssd130x.c` line 1125.

**That 32 is the second thing the specification gets wrong.** It describes
writing packed 1 bit per pixel rows, 16 bytes per line. The framebuffer is
32 bits per pixel XRGB8888, 128 by 64 by 4 is 32768 bytes, and the kernel
converts to the panel's own R1 format itself (`drm_format_info(DRM_FORMAT_R1)`,
line 616). `explorer-oled` reads `bits_per_pixel` from sysfs rather than
assuming either.

**Checked against the reference implementation.**
`arch/arm/boot/dts/overlays/ssd1306-spi-overlay.dts` in `rpi-6.6.y` binds
the same panel on the same bus and agrees on every point: the compatible,
disabling `&spidev0`, `reset-gpios` active low, `dc-gpios` active high, and
the byte offsets in `__overrides__`.

## w1-gpio, w1_therm

**Driver** `drivers/w1/masters/w1-gpio.c`, of_match at line 62,
`{ .compatible = "w1-gpio" }` with no vendor prefix, which is unusual and
correct.

**Property name.** The data line is an unnamed descriptor at index 0
(`devm_gpiod_get_index(dev, NULL, 0, gflags)`, line 107), so the property
is plain `gpios`. Index 1 is an optional pull-up enable pin (line 114),
which this board does not have.

**Interface** `/sys/bus/w1/devices/28-*/temperature`, in milli degrees.

**Worth knowing.** `w1_master_slave_count` on the master is what separates
"no bus" from "bus with nothing on it", and on this board that distinction
is load bearing: the DS18B20 ships loose and plugs into a three-pin header.

## gpio-ir-receiver

**Driver** `drivers/media/rc/gpio-ir-recv.c`, of_match at line 198.

**Property names.** Unnamed descriptor again (`devm_gpiod_get(dev, NULL,
GPIOD_IN)`, line 76), so plain `gpios`. The keymap comes from
`linux,rc-map-name` (line 101), defaulting to `RC_MAP_EMPTY` when absent,
which is `"rc-empty"` in `include/media/rc-map.h` line 250.

**Interface** `/sys/class/rc/rc0` and an input device named
`gpio_ir_recv`, which is a literal in the driver
(`GPIO_IR_DEVICE_NAME`, line 19) and not something the overlay can set.
The udev rule matches on it.

**Worth knowing.** A receiver with no **decoder** produces raw timings and
never a scancode, which reads as broken hardware. `CONFIG_RC_DECODERS` and
at least one protocol are as necessary as the receiver driver.

## gpio-leds

**Driver** `drivers/leds/leds-gpio.c`.

**Interface** `/sys/class/leds/<label>`.

**Worth knowing.** `linux,default-trigger` names a trigger by string, and a
name the kernel does not have leaves the LED on its default with no
complaint. That is why `CONFIG_LEDS_TRIGGER_HEARTBEAT` is named in the
fragment even though the Pi defconfig already sets it.

## gpio-keys-polled

**Driver** `drivers/input/keyboard/gpio_keys_polled.c`, `CONFIG_KEYBOARD_GPIO_POLLED`
at `drivers/input/keyboard/Kconfig` line 249.

**Interface** `/dev/input/eventN`.

**Why polled and not `gpio-keys`.** Four of this joystick's five contacts
are on an I2C expander. Those are sleeping lines, and a driver using the
atomic GPIO accessors refuses them at probe. `gpio-keys-polled` uses the
sleeping accessors, which is also what lets one node hold four expander
lines and one SoC pin as a single input device.

**Name.** The parent node's `label` property becomes the input device
name. `explorer-verify` and the udev rule both match on it, which is
checked by `tests/explorer-overlay-test.sh` because nothing else would
notice the two drifting apart.

## gpio-beeper

**Driver** `drivers/input/misc/gpio-beeper.c`. The compatible is
`BEEPER_MODNAME`, defined at line 15 as `"gpio-beeper"`.

**Interface** an input device that accepts `EV_SND` with code `SND_BELL`
(line 40, line 88). Unnamed descriptor, so plain `gpios`.

**Worth knowing.** It handles `SND_BELL` only, not `SND_TONE`. A frequency
cannot be set, because the driver drives a level rather than a waveform.
`pwm-beeper` would give tones, and on this board the PWM-capable pins it
would need are taken: GPIO18 by the IR receiver and GPIO19 by the
display's reset.
