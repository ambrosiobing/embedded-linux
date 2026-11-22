/*
 * drmfill - paint a gradient on the 3.5 inch panel through plain DRM.
 *
 * The point of this program is to touch every object a compositor
 * touches, and nothing more: resources, connector, encoder, CRTC, a dumb
 * buffer, a framebuffer, and the dirty ioctl that carries damage. If this
 * works, the panel is a real KMS device and not an emulated framebuffer.
 *
 * WHY IT FINDS THE CARD INSTEAD OF TAKING A PATH
 *
 * The obvious version opens /dev/dri/card1 because that is where the
 * panel is when vc4-kms-v3d is active. It is card0 when vc4 is disabled,
 * and the order can change between kernels. A hard-coded path is
 * therefore a program that paints the HDMI output by accident on a board
 * that is configured slightly differently, and the accident is silent.
 *
 * So the default is to walk the cards and match the driver name, and an
 * explicit path is checked against the same name before anything is
 * drawn. Refusing is the useful behaviour here: the acceptance criterion
 * for this project is that pointing it at the wrong card produces a clear
 * error rather than a picture in the wrong place.
 *
 * SPDX-License-Identifier: MIT
 */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#define PANEL_DRIVER "ili9486"
#define MAX_CARDS 16

static int seconds = 5;
static int force;

static void usage(const char *argv0)
{
	fprintf(stderr,
		"usage: %s [-d /dev/dri/cardN] [-t seconds] [-f]\n"
		"\n"
		"  -d   device to use. Default: the first card whose driver\n"
		"       is " PANEL_DRIVER ".\n"
		"  -t   how long to leave the picture up. Default 5.\n"
		"  -f   draw even if the driver is not " PANEL_DRIVER ".\n",
		argv0);
}

/* Returns the driver name in a buffer the caller owns, or NULL. */
static char *driver_name(int fd)
{
	drmVersionPtr v = drmGetVersion(fd);
	char *name;

	if (!v)
		return NULL;
	name = strndup(v->name, v->name_len);
	drmFreeVersion(v);
	return name;
}

/*
 * Walk /dev/dri/cardN and return the first one driven by PANEL_DRIVER.
 * Prints every card it looked at, because a tool that chooses its own
 * input has to say what it chose and what it rejected. A refusal without
 * evidence cannot be argued with.
 */
static int open_panel(void)
{
	char path[32];
	int i;

	for (i = 0; i < MAX_CARDS; i++) {
		char *name;
		int fd;

		snprintf(path, sizeof(path), "/dev/dri/card%d", i);
		fd = open(path, O_RDWR | O_CLOEXEC);
		if (fd < 0)
			continue;

		name = driver_name(fd);
		if (!name) {
			fprintf(stderr, "%s: cannot read driver name: %s\n",
				path, strerror(errno));
			close(fd);
			continue;
		}

		if (strcmp(name, PANEL_DRIVER) == 0) {
			printf("%s: driver %s, using this one\n", path, name);
			free(name);
			return fd;
		}

		printf("%s: driver %s, not the panel\n", path, name);
		free(name);
		close(fd);
	}

	fprintf(stderr,
		"no card is driven by %s. Is the overlay loaded, and did\n"
		"the ili9486 driver bind? Check:\n"
		"  ls /sys/bus/spi/drivers/ili9486/\n"
		"  dmesg | grep -i ili9486\n",
		PANEL_DRIVER);
	return -1;
}

static int open_named(const char *path)
{
	char *name;
	int fd = open(path, O_RDWR | O_CLOEXEC);

	if (fd < 0) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		return -1;
	}

	name = driver_name(fd);
	if (!name) {
		fprintf(stderr, "%s: cannot read driver name: %s\n", path,
			strerror(errno));
		close(fd);
		return -1;
	}

	if (strcmp(name, PANEL_DRIVER) != 0 && !force) {
		fprintf(stderr,
			"%s is driven by %s, not %s.\n"
			"Refusing, because painting the wrong output is worse\n"
			"than not painting at all. Use -f to override, or run\n"
			"with no -d to let this program find the panel.\n",
			path, name, PANEL_DRIVER);
		free(name);
		close(fd);
		return -1;
	}

	printf("%s: driver %s\n", path, name);
	free(name);
	return fd;
}

int main(int argc, char **argv)
{
	const char *path = NULL;
	drmModeRes *res = NULL;
	drmModeConnector *conn = NULL;
	drmModeEncoder *enc = NULL;
	/*
	 * Zeroed at declaration rather than with a memset further down,
	 * because the error paths above that point jump to out: and the
	 * cleanup there reads cd.size.
	 */
	struct drm_mode_create_dumb cd = { 0 };
	struct drm_mode_map_dumb md = { 0 };
	drmModeModeInfo mode;
	drmModeClip clip = { 0 };
	uint32_t handles[4] = { 0 }, pitches[4] = { 0 }, offsets[4] = { 0 };
	uint32_t fb_id = 0, crtc_id = 0;
	uint16_t *px = MAP_FAILED;
	uint32_t x, y;
	int fd = -1, rc = 1, opt, i;

	while ((opt = getopt(argc, argv, "d:t:fh")) != -1) {
		switch (opt) {
		case 'd':
			path = optarg;
			break;
		case 't':
			seconds = atoi(optarg);
			break;
		case 'f':
			force = 1;
			break;
		default:
			usage(argv[0]);
			return opt == 'h' ? 0 : 2;
		}
	}

	fd = path ? open_named(path) : open_panel();
	if (fd < 0)
		return 1;

	res = drmModeGetResources(fd);
	if (!res) {
		fprintf(stderr, "drmModeGetResources: %s\n", strerror(errno));
		goto out;
	}

	/*
	 * The first CONNECTED connector, not simply the first one. A tiny
	 * driver has exactly one, so this loop normally runs once; written
	 * as a loop because "connectors[0] is the panel" is the same class
	 * of assumption as "card1 is the panel".
	 */
	for (i = 0; i < res->count_connectors; i++) {
		conn = drmModeGetConnector(fd, res->connectors[i]);
		if (conn && conn->connection == DRM_MODE_CONNECTED &&
		    conn->count_modes > 0)
			break;
		if (conn) {
			drmModeFreeConnector(conn);
			conn = NULL;
		}
	}
	if (!conn) {
		fprintf(stderr, "no connected connector with a mode\n");
		goto out;
	}

	mode = conn->modes[0];
	printf("connector %u, mode %ux%u\n", conn->connector_id,
	       mode.hdisplay, mode.vdisplay);

	enc = drmModeGetEncoder(fd, conn->encoder_id);
	crtc_id = (enc && enc->crtc_id) ? enc->crtc_id : res->crtcs[0];

	cd.width = mode.hdisplay;
	cd.height = mode.vdisplay;
	cd.bpp = 16;
	if (ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &cd)) {
		fprintf(stderr, "create dumb: %s\n", strerror(errno));
		goto out;
	}

	handles[0] = cd.handle;
	pitches[0] = cd.pitch;
	if (drmModeAddFB2(fd, cd.width, cd.height, DRM_FORMAT_RGB565, handles,
			  pitches, offsets, &fb_id, 0)) {
		fprintf(stderr, "addfb2: %s\n", strerror(errno));
		goto out;
	}

	md.handle = cd.handle;
	if (ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &md)) {
		fprintf(stderr, "map dumb: %s\n", strerror(errno));
		goto out;
	}

	px = mmap(NULL, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
		  md.offset);
	if (px == MAP_FAILED) {
		fprintf(stderr, "mmap: %s\n", strerror(errno));
		goto out;
	}

	/* RGB565: red in bits 15..11, green 10..5, blue 4..0. */
	for (y = 0; y < cd.height; y++)
		for (x = 0; x < cd.width; x++)
			px[y * (cd.pitch / 2) + x] =
				(uint16_t)(((x * 31 / cd.width) << 11) |
					   ((y * 63 / cd.height) << 5));

	if (drmModeSetCrtc(fd, crtc_id, fb_id, 0, 0, &conn->connector_id, 1,
			   &mode)) {
		fprintf(stderr,
			"setcrtc: %s\n"
			"If this is EACCES or EPERM, something else holds the\n"
			"device. A DRM master is exclusive; switch the console\n"
			"away with chvt and try again.\n",
			strerror(errno));
		goto out;
	}

	/*
	 * What a compositor does after every frame. On this panel it is the
	 * difference between sending one rectangle and sending the whole
	 * 2.46 Mbit frame: the driver has a shadow buffer and copies only
	 * what user space declares dirty. The legacy SetCrtc path above
	 * already triggered a full update, so the picture would appear
	 * without this call; the call is here because partial updates need
	 * a clip list and this program exists to show the real path.
	 */
	clip.x2 = (uint16_t)cd.width;
	clip.y2 = (uint16_t)cd.height;
	if (drmModeDirtyFB(fd, fb_id, &clip, 1)) {
		/*
		 * ENOSYS means the driver has no dirty callback, which is
		 * legal and not this driver. Report and carry on: the
		 * picture is already up.
		 */
		fprintf(stderr, "dirtyfb: %s (picture is up regardless)\n",
			strerror(errno));
	}

	printf("gradient up for %d s\n", seconds);
	sleep((unsigned int)seconds);
	rc = 0;

out:
	if (px != MAP_FAILED)
		munmap(px, cd.size);
	if (fb_id)
		drmModeRmFB(fd, fb_id);
	if (enc)
		drmModeFreeEncoder(enc);
	if (conn)
		drmModeFreeConnector(conn);
	if (res)
		drmModeFreeResources(res);
	if (fd >= 0)
		close(fd);
	return rc;
}
