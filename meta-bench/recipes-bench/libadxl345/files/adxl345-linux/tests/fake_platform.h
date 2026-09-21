/*
 * fake_platform.h - what the tests can ask the fake bus.
 *
 * Only the test binary includes this. The library never does, which is
 * why the fake can grow an interface like this without widening anything
 * the library depends on.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef FAKE_PLATFORM_H
#define FAKE_PLATFORM_H

#include <stdint.h>

#define FAKE_LOG_MAX 512

#define FAKE_WRITE 1
#define FAKE_READ 2

struct fake_entry {
	int kind;
	uint8_t reg;
	uint8_t value;
};

struct fake_log {
	struct fake_entry entry[FAKE_LOG_MAX];
	int count;
	int waits;
	int closed;
	int open_addr;
	int open_int_gpio;
};

/* Clear the register file and the log, and set DEVID so that adxl_open
 * identifies the part. Every test case starts here. */
void fake_reset(void);

/* Override DEVID, so a test can prove adxl_open refuses a part that
 * answers and is not an ADXL345. */
void fake_set_devid(uint8_t v);

/* Pretend the FIFO holds this many entries. */
void fake_set_fifo(int entries);

/* Read back what the library wrote, to assert on configuration rather
 * than on return codes. */
uint8_t fake_reg(uint8_t r);

/* The ordered transfer log, for assertions about sequence. */
const struct fake_log *fake_get_log(void);

/* Forget the transfers so far and keep everything else: the register
 * file, the FIFO, the open and close counts. For an assertion about the
 * ORDER of one operation's writes, called immediately before it, so the
 * log holds that operation and nothing earlier.
 *
 * Without this, "the first write to POWER_CTL" is the standby write
 * adxl_open makes, which precedes every configuration write, and an
 * ordering claim about start or stop is judged against a write that
 * belongs to neither. Two such claims failed in CI on Monday 21
 * September 2026 with the library's order correct on both paths. */
void fake_log_clear(void);

#endif /* FAKE_PLATFORM_H */
