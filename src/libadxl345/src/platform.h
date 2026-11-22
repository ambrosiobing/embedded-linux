/*
 * platform.h - the seam between the library and the bus.
 *
 * Four functions and an open/close pair. The real implementation is
 * platform.c against i2c-dev; tests/fake_platform.c implements the same
 * six against an in-memory register map and is linked in its place.
 *
 * THE SEAM IS AT LINK TIME AND NOT BEHIND A FUNCTION POINTER, on purpose.
 * A vtable would be swappable at run time, which nothing here needs, and
 * it would put an indirect call in the read path and a pointer in the
 * handle that the tests would then have to set up. Two targets in
 * CMakeLists.txt, each with one of the two files, is the whole mechanism.
 *
 * The cost is that a single binary cannot hold both, so there is no
 * "--fake" flag on the real tool. That is the right trade: a production
 * library that can be told to fabricate readings is a worse thing than an
 * extra test binary.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef ADXL_PLATFORM_H
#define ADXL_PLATFORM_H

#include <stdint.h>

/*
 * Opaque to the library. platform.c makes it a file descriptor plus a
 * libgpiod request; fake_platform.c makes it an index into a register
 * array. src/adxl.c never looks inside either.
 */
typedef struct adxl_plat adxl_plat;

/*
 * Open the bus and claim the interrupt line if int_gpio is not negative.
 * Returns 0, or a negative errno-shaped code with errno set.
 */
int adxl_plat_open(adxl_plat **out, const char *path, int addr, int int_gpio);

void adxl_plat_close(adxl_plat *p);

/*
 * Register reads and writes. The index is 8 bits, which is the whole
 * register map of this part, and the ADXL345 auto-increments on a
 * multi-byte I2C read, so one transaction fetches a whole FIFO entry.
 */
int adxl_plat_write(adxl_plat *p, uint8_t reg, const uint8_t *buf, int len);
int adxl_plat_read(adxl_plat *p, uint8_t reg, uint8_t *buf, int len);

/*
 * Wait for INT1 to assert, or for the timeout. Returns 1 if the line
 * asserted, 0 on timeout, negative on error.
 *
 * With no interrupt wired this sleeps for the timeout and returns 0, so
 * the caller falls back to polling the FIFO status register without a
 * second code path.
 */
int adxl_plat_wait(adxl_plat *p, int timeout_ms);

void adxl_plat_sleep_ms(int ms);

#endif /* ADXL_PLATFORM_H */
