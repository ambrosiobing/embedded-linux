/*
 * adxl.h - the public API of libadxl345.
 *
 * Six functions, an opaque handle, and arrays out. Nothing in this header
 * mentions a register, a bus or a struct the caller has to allocate, which
 * is what lets the Python bindings be twenty lines of ctypes with no
 * structure definitions at all.
 *
 * The rule this header follows: anything that could change when the
 * driver changes must not be visible here. A caller that compiled against
 * version 1.0 keeps working against 1.4 because there is nothing in the
 * ABI to break except these six signatures.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef ADXL_H
#define ADXL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Everything is built with -fvisibility=hidden, so a symbol is exported
 * only by saying so. That is the mechanism behind acceptance criterion 4:
 * nm -D must list exactly six defined text symbols, and an accidental
 * export fails that check rather than silently widening the ABI.
 */
#define ADXL_API __attribute__((visibility("default")))

/* X, Y, Z. Named rather than 3, because a bare 3 in a caller's array
 * declaration is the kind of thing that survives a change to 6. */
#define ADXL_AXES 3

/* The FIFO is 32 entries deep in hardware. A caller may ask for fewer. */
#define ADXL_FIFO_DEPTH 32

/* Return codes. Negative, so a caller can test < 0 and a count can share
 * the return value of adxl_read without ambiguity. */
#define ADXL_OK 0
#define ADXL_EIO (-1)      /* the bus refused, errno is set */
#define ADXL_EWHO (-2)     /* something answered and it is not an ADXL345 */
#define ADXL_EPARAM (-3)   /* a caller argument is out of range */
#define ADXL_ETIMEOUT (-4) /* no sample within the timeout */
#define ADXL_ENOMEM (-5)

typedef struct adxl_dev adxl_dev;

/* Library version, not the protocol version. Bump the minor for added
 * behaviour, the major only for a change that breaks the six below. */
ADXL_API int adxl_version(int *major, int *minor, int *patch);

/*
 * Open a sensor.
 *
 * i2c_path  the bus, "/dev/i2c-1" on a Raspberry Pi header.
 * addr      7-bit. 0x53 with SDO low, 0x1D with SDO high. Passed in
 *           rather than compiled in because which one it is depends on a
 *           strap this bench has not read yet.
 * int_gpio  BCM offset of INT1, or negative for "not wired". With no
 *           interrupt the library polls, which works and is worse.
 *
 * Verifies DEVID reads 0xE5 before returning success, so a wrong address
 * fails here with ADXL_EWHO rather than producing plausible rubbish
 * later.
 */
ADXL_API int adxl_open(adxl_dev **out, const char *i2c_path, int addr,
                       int int_gpio);

/*
 * Start measuring.
 *
 * range_g   2, 4, 8 or 16. Full resolution is always on, so the scale
 *           stays 3.9 mg per count at every range and only the clipping
 *           point moves.
 * rate_hz   one of the ADXL345's output data rates: 12, 25, 50, 100, 200,
 *           400, 800, 1600, 3200. Anything else is ADXL_EPARAM rather
 *           than a silent round to the nearest.
 */
ADXL_API int adxl_start(adxl_dev *d, int range_g, int rate_hz);

/*
 * Read up to max samples, returning how many arrived.
 *
 * Returns a non-negative count, or a negative ADXL_* code. The count is
 * the point: the FIFO delivers a burst, and a caller that assumed it
 * always got max would read stale samples off the end of its own array.
 *
 * samples is [max][ADXL_AXES] of raw counts. Multiply by 3.9 mg to get
 * acceleration; the library does not, because integers cross the ctypes
 * boundary without a float conversion in the middle.
 */
ADXL_API int adxl_read(adxl_dev *d, int16_t samples[][ADXL_AXES], int max,
                       int timeout_ms);

/* Stop measuring. The handle stays open and adxl_start may follow. */
ADXL_API int adxl_stop(adxl_dev *d);

/* Close and free. Safe on NULL, so a caller's error path needs no test. */
ADXL_API void adxl_close(adxl_dev *d);

#ifdef __cplusplus
}
#endif

#endif /* ADXL_H */
