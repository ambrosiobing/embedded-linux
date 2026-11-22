/*
 * platform.c - i2c-dev and libgpiod v2 behind the four-function seam.
 *
 * Two things here are worth reading rather than skimming.
 *
 * I2C_RDWR RATHER THAN read() AND write(). The obvious implementation is
 * write(fd, &reg, 1) then read(fd, buf, len), and it works almost always.
 * Between those two calls the kernel may let another client of the same
 * bus issue its own transfer, which leaves the ADXL345's internal address
 * pointer somewhere else and returns the wrong registers with no error.
 * I2C_RDWR sends both messages as one transaction with a repeated start,
 * which is the whole reason the ioctl exists.
 *
 * ONE BUFFER PER HANDLE. A static buffer is the easy way to write this
 * file and it makes the library quietly non-reentrant: two handles on two
 * threads then corrupt each other's transfers, intermittently, under
 * load. The buffer is small, so it is allocated with the handle.
 *
 * SPDX-License-Identifier: MIT
 */

#include "platform.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>

#include <gpiod.h>

/* One register index plus the longest burst the library asks for, which
 * is a full FIFO entry of six bytes. Rounded up so a future multi-entry
 * read needs no change here. */
#define PLAT_BUF 64

struct adxl_plat {
	int fd;
	int addr;
	struct gpiod_line_request *irq;
	uint8_t buf[PLAT_BUF];
};

/*
 * Claim INT1 as a rising-edge input, or return NULL.
 *
 * Its own function because the v2 request is four objects that all have
 * to be freed on every path, and doing that with gotos inside the open
 * path made the open path unreadable. NULL is a legitimate result: the
 * library then polls.
 */
static struct gpiod_line_request *request_irq_line(int offset)
{
	struct gpiod_chip *chip;
	struct gpiod_line_settings *settings;
	struct gpiod_line_config *lcfg;
	struct gpiod_request_config *rcfg;
	struct gpiod_line_request *req = NULL;
	unsigned int off = (unsigned int)offset;

	/*
	 * By path rather than by number: the chip numbering moves when an
	 * expander probes first, which this bench has already been bitten
	 * by once in Project 1.
	 */
	chip = gpiod_chip_open("/dev/gpiochip0");
	if (!chip)
		return NULL;

	settings = gpiod_line_settings_new();
	lcfg = gpiod_line_config_new();
	rcfg = gpiod_request_config_new();

	if (settings && lcfg && rcfg) {
		gpiod_line_settings_set_direction(
			settings, GPIOD_LINE_DIRECTION_INPUT);
		gpiod_line_settings_set_edge_detection(
			settings, GPIOD_LINE_EDGE_RISING);
		gpiod_request_config_set_consumer(rcfg, "adxl345");
		if (gpiod_line_config_add_line_settings(lcfg, &off, 1,
							settings) == 0)
			req = gpiod_chip_request_lines(chip, rcfg, lcfg);
	}

	if (rcfg)
		gpiod_request_config_free(rcfg);
	if (lcfg)
		gpiod_line_config_free(lcfg);
	if (settings)
		gpiod_line_settings_free(settings);
	gpiod_chip_close(chip);
	return req;
}

int adxl_plat_open(adxl_plat **out, const char *path, int addr, int int_gpio)
{
	adxl_plat *p;

	if (!out || !path)
		return -EINVAL;

	p = calloc(1, sizeof(*p));
	if (!p)
		return -ENOMEM;

	p->fd = open(path, O_RDWR | O_CLOEXEC);
	if (p->fd < 0) {
		int e = -errno;
		free(p);
		return e;
	}
	p->addr = addr;

	/*
	 * I2C_SLAVE is deliberately NOT set. It binds the descriptor to one
	 * address for the plain read/write path, and every transfer here
	 * carries its own address in the message. Setting it would also make
	 * the descriptor refuse when an in-kernel driver holds the address,
	 * which is a refusal worth having, but it belongs to the library's
	 * open rather than here: see the ownership table in the design.
	 */

	if (int_gpio >= 0)
		p->irq = request_irq_line(int_gpio);

	/*
	 * A failed interrupt request is not fatal and is not silent either:
	 * p->irq stays NULL, adxl_plat_wait then reports a timeout every
	 * time, and the library polls. The caller asked for an interrupt and
	 * did not get one, which the application says out loud.
	 */
	*out = p;
	return 0;
}

void adxl_plat_close(adxl_plat *p)
{
	if (!p)
		return;
	if (p->irq)
		gpiod_line_request_release(p->irq);
	if (p->fd >= 0)
		close(p->fd);
	free(p);
}

int adxl_plat_write(adxl_plat *p, uint8_t reg, const uint8_t *buf, int len)
{
	struct i2c_msg msg;
	struct i2c_rdwr_ioctl_data xfer;

	if (!p || len < 0 || len + 1 > PLAT_BUF)
		return -EINVAL;

	p->buf[0] = reg;
	if (len)
		memcpy(p->buf + 1, buf, (size_t)len);

	msg.addr = (uint16_t)p->addr;
	msg.flags = 0;
	msg.len = (uint16_t)(len + 1);
	msg.buf = p->buf;

	xfer.msgs = &msg;
	xfer.nmsgs = 1;

	return ioctl(p->fd, I2C_RDWR, &xfer) < 0 ? -errno : 0;
}

int adxl_plat_read(adxl_plat *p, uint8_t reg, uint8_t *buf, int len)
{
	struct i2c_msg msg[2];
	struct i2c_rdwr_ioctl_data xfer;

	if (!p || !buf || len <= 0)
		return -EINVAL;

	p->buf[0] = reg;

	/* Write the index, repeated start, then read. One transaction. */
	msg[0].addr = (uint16_t)p->addr;
	msg[0].flags = 0;
	msg[0].len = 1;
	msg[0].buf = p->buf;

	msg[1].addr = (uint16_t)p->addr;
	msg[1].flags = I2C_M_RD;
	msg[1].len = (uint16_t)len;
	msg[1].buf = buf;

	xfer.msgs = msg;
	xfer.nmsgs = 2;

	return ioctl(p->fd, I2C_RDWR, &xfer) < 0 ? -errno : 0;
}

int adxl_plat_wait(adxl_plat *p, int timeout_ms)
{
	int rc;

	if (!p)
		return -EINVAL;
	if (!p->irq) {
		adxl_plat_sleep_ms(timeout_ms);
		return 0;
	}

	rc = gpiod_line_request_wait_edge_events(p->irq,
						 (int64_t)timeout_ms * 1000000);
	if (rc < 0)
		return -errno;
	if (rc == 0)
		return 0;

	/*
	 * The event has to be consumed or the next wait returns immediately
	 * on the same edge and the caller spins.
	 */
	{
		struct gpiod_edge_event_buffer *eb =
			gpiod_edge_event_buffer_new(1);
		if (eb) {
			gpiod_line_request_read_edge_events(p->irq, eb, 1);
			gpiod_edge_event_buffer_free(eb);
		}
	}
	return 1;
}

void adxl_plat_sleep_ms(int ms)
{
	struct timespec ts;

	if (ms <= 0)
		return;
	ts.tv_sec = ms / 1000;
	ts.tv_nsec = (long)(ms % 1000) * 1000000L;
	nanosleep(&ts, NULL);
}
