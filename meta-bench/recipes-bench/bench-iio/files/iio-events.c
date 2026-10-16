/*
 * iio-events - print the IIO events a device raises, one per line.
 *
 *     iio-events DEVICE [-n COUNT] [-t SECONDS]
 *
 * DEVICE is a name as it appears in /sys/bus/iio/devices/iio:deviceN/name,
 * the same spelling iio-rate takes, because which iio:deviceN a driver
 * got is decided at probe and changes between boots while the name does
 * not.
 *
 * WHY THIS EXISTS, WHICH IS A GAP RATHER THAN A PREFERENCE
 *
 * Events do not arrive through the buffer character device and they are
 * not readable from the shell. The IIO core hands them out through a
 * second file descriptor obtained with an ioctl on /dev/iio:deviceN, and
 * reading it needs a program. The kernel tree ships tools/iio/
 * iio_event_monitor, which two of Project 5's documents name as the
 * evidence for its sixth acceptance criterion; nothing in this layer
 * packages it and no bench image has ever contained it. So the criterion
 * named a tool that was shipped to no board, which is the same shape as
 * the i2c-dev packaging defect of Friday 9 October 2026 and was found
 * the same way, by reading what the image installs before asking the
 * board a question it could not answer.
 *
 * WHAT IT DOES NOT DO
 *
 * It does not enable anything. An IIO event fires only while its _en
 * attribute under events/ is 1, and arming one is a decision about the
 * hardware that belongs to whoever is running the test:
 *
 *     echo 1 > /sys/bus/iio/devices/iio:device0/events/in_accel_*_en
 *
 * A device with no events/ directory at all is reported as such rather
 * than waited on, because an empty wait and an impossible wait look the
 * same from the outside and only one of them is worth sitting through.
 *
 * SPDX-License-Identifier: MIT
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <linux/iio/events.h>
#include <linux/iio/types.h>

#define IIO_DEVICES "/sys/bus/iio/devices"

static volatile sig_atomic_t stop;

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: iio-events DEVICE [-n COUNT] [-t SECONDS]\n"
		"\n"
		"  DEVICE     the name in /sys/bus/iio/devices/iio:deviceN/name\n"
		"  -n COUNT   stop after COUNT events, default: no limit\n"
		"  -t SECONDS stop after SECONDS, default: no limit\n"
		"\n"
		"Enable an event first, or nothing will arrive:\n"
		"  echo 1 > /sys/bus/iio/devices/iio:deviceN/events/<name>_en\n");
	exit(2);
}

/*
 * The device number whose name attribute equals want, or -1. The search
 * is over the directory rather than over a guessed range, so a board
 * with gaps in its numbering behaves the same as one without.
 */
static int device_number_of(const char *want)
{
	struct dirent *ent;
	DIR *dir;
	int found = -1;

	dir = opendir(IIO_DEVICES);
	if (!dir)
		return -1;

	while ((ent = readdir(dir))) {
		char path[256], name[128];
		FILE *f;
		int n;

		if (sscanf(ent->d_name, "iio:device%d", &n) != 1)
			continue;

		snprintf(path, sizeof(path), IIO_DEVICES "/iio:device%d/name", n);
		f = fopen(path, "r");
		if (!f)
			continue;

		if (fgets(name, sizeof(name), f)) {
			name[strcspn(name, "\n")] = '\0';
			if (!strcmp(name, want))
				found = n;
		}
		fclose(f);

		if (found >= 0)
			break;
	}

	closedir(dir);
	return found;
}

static const char *chan_type_name(int type)
{
	switch (type) {
	case IIO_ACCEL:		return "accel";
	case IIO_ANGL_VEL:	return "anglvel";
	case IIO_MAGN:		return "magn";
	case IIO_TEMP:		return "temp";
	case IIO_PRESSURE:	return "pressure";
	default:		return "other";
	}
}

static const char *modifier_name(int mod)
{
	switch (mod) {
	case IIO_NO_MOD:		return "";
	case IIO_MOD_X:			return "x";
	case IIO_MOD_Y:			return "y";
	case IIO_MOD_Z:			return "z";
	case IIO_MOD_X_OR_Y_OR_Z:	return "x|y|z";
	default:			return "mod?";
	}
}

static const char *event_type_name(int type)
{
	switch (type) {
	case IIO_EV_TYPE_THRESH:	return "thresh";
	case IIO_EV_TYPE_MAG:		return "mag";
	case IIO_EV_TYPE_ROC:		return "roc";
	case IIO_EV_TYPE_CHANGE:	return "change";
	case IIO_EV_TYPE_GESTURE:	return "gesture";
	default:			return "type?";
	}
}

static const char *direction_name(int dir)
{
	switch (dir) {
	case IIO_EV_DIR_EITHER:		return "either";
	case IIO_EV_DIR_RISING:		return "rising";
	case IIO_EV_DIR_FALLING:	return "falling";
	case IIO_EV_DIR_SINGLETAP:	return "singletap";
	case IIO_EV_DIR_DOUBLETAP:	return "doubletap";
	default:			return "dir?";
	}
}

/*
 * The events directory exists only when some channel declares an
 * iio_event_spec. Saying so costs one stat and saves a wait that could
 * never end.
 */
static bool has_events_directory(int number)
{
	char path[256];
	struct stat st;

	snprintf(path, sizeof(path), IIO_DEVICES "/iio:device%d/events", number);
	return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

int main(int argc, char **argv)
{
	const char *want;
	long limit = 0, seconds = 0;
	int number, fd, event_fd, i, ret;
	time_t deadline = 0;
	long seen = 0;

	if (argc < 2)
		usage();

	want = argv[1];
	for (i = 2; i < argc; i++) {
		if (!strcmp(argv[i], "-n") && i + 1 < argc)
			limit = strtol(argv[++i], NULL, 10);
		else if (!strcmp(argv[i], "-t") && i + 1 < argc)
			seconds = strtol(argv[++i], NULL, 10);
		else
			usage();
	}

	number = device_number_of(want);
	if (number < 0) {
		fprintf(stderr, "iio-events: no IIO device named %s.\n"
			"       iio-probe lists what is present.\n", want);
		return 1;
	}

	if (!has_events_directory(number)) {
		fprintf(stderr,
			"iio-events: iio:device%d has no events directory, so "
			"its driver\n"
			"       declares no event and none can arrive. On "
			"Project 5's driver\n"
			"       that also means INT1 was not wired when it "
			"probed.\n", number);
		return 1;
	}

	char path[64];

	snprintf(path, sizeof(path), "/dev/iio:device%d", number);
	fd = open(path, O_RDONLY | O_NONBLOCK);
	if (fd < 0) {
		fprintf(stderr, "iio-events: cannot open %s: %s\n",
			path, strerror(errno));
		return 1;
	}

	/*
	 * The event descriptor is a second file, handed out by the core
	 * on request. Closing the device node afterwards is deliberate:
	 * the event descriptor keeps its own reference, and holding the
	 * buffer node open would make a capture by another program fail
	 * with EBUSY for no reason anyone could see from here.
	 */
	ret = ioctl(fd, IIO_GET_EVENT_FD_IOCTL, &event_fd);
	if (ret < 0 || event_fd < 0) {
		fprintf(stderr, "iio-events: %s gives no event descriptor: %s\n",
			path, strerror(errno));
		close(fd);
		return 1;
	}
	close(fd);

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	if (seconds > 0)
		deadline = time(NULL) + seconds;

	printf("# iio-events on iio:device%d, named %s\n", number, want);
	printf("timestamp_ns,channel,modifier,type,direction\n");
	fflush(stdout);

	while (!stop) {
		struct iio_event_data event;
		struct pollfd pfd = {
			.fd = event_fd,
			.events = POLLIN,
		};
		int timeout = 1000;
		ssize_t got;

		if (deadline && time(NULL) >= deadline)
			break;

		ret = poll(&pfd, 1, timeout);
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			fprintf(stderr, "iio-events: poll: %s\n", strerror(errno));
			break;
		}
		if (ret == 0)
			continue;

		got = read(event_fd, &event, sizeof(event));
		if (got < 0) {
			if (errno == EAGAIN || errno == EINTR)
				continue;
			fprintf(stderr, "iio-events: read: %s\n", strerror(errno));
			break;
		}
		if (got != (ssize_t)sizeof(event)) {
			fprintf(stderr, "iio-events: short read, %zd bytes\n", got);
			break;
		}

		printf("%lld,%s,%s,%s,%s\n",
		       (long long)event.timestamp,
		       chan_type_name(IIO_EVENT_CODE_EXTRACT_CHAN_TYPE(event.id)),
		       modifier_name(IIO_EVENT_CODE_EXTRACT_MODIFIER(event.id)),
		       event_type_name(IIO_EVENT_CODE_EXTRACT_TYPE(event.id)),
		       direction_name(IIO_EVENT_CODE_EXTRACT_DIR(event.id)));
		fflush(stdout);

		seen++;
		if (limit > 0 && seen >= limit)
			break;
	}

	close(event_fd);
	fprintf(stderr, "iio-events: %ld event(s)\n", seen);
	return 0;
}
