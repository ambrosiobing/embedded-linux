/*
 * tracker-gpio - the two GPIO lines Project 16 needs.
 *
 *   tracker-gpio pwrkey [ms]   pulse the modem's power key
 *   tracker-gpio marker-hold   drive the instrument marker until signalled
 *   tracker-gpio info          print the chip, the offsets and the state
 *
 * Mechanism only, no policy: whether to power the modem on and when to
 * mark a report is the tracker's business, and it reaches this program by
 * name through PATH so the whole state machine runs on a laptop against a
 * stub. That split is Project 15's and it is here for the same reason.
 *
 * Why this is not Project 15's lte-gpio, which does nearly the same thing.
 * That program lives in bench-lte, whose package pulls ModemManager,
 * NetworkManager and a Python interpreter into any image that installs it.
 * This project's whole argument is that a tracker installs none of those.
 * Sharing the binary would mean sharing the dependency, so the fifty lines
 * are copied rather than the package reused, and that is a deliberate
 * trade rather than an oversight.
 *
 * MARKER-HOLD BLOCKS, AND HAS TO.
 *
 * A process that requests a line, drives it and exits gives the line back
 * to the kernel, which returns it to an input. A marker set that way would
 * be a spike of a few milliseconds rather than an interval, and the charge
 * integrated between its edges would be the charge of nothing at all. So
 * the marker is held for as long as the process lives, and the tracker
 * ends the interval by ending the process. Project 15 learned the same
 * thing about its FLIGHT line, from the other direction: there, releasing
 * the line let a pull-up put the radio into flight mode.
 *
 * What that costs, stated because it lands inside a published number. The
 * interval the PPK2 integrates is bounded by this process starting and
 * stopping, so process startup sits inside the interval rather than
 * outside it. The measured charge per report is therefore slightly high.
 * That is the safe direction for a budget, and the size of it should be
 * measured once and recorded rather than assumed to be negligible.
 *
 * NOTHING IS DRIVEN WITHOUT AN OFFSET IN THE CONFIGURATION.
 *
 * There is no default pin, and that is the point. A GPIO offset is a
 * property of a HAT revision and of a board revision, not of a part, and a
 * wrong offset does not fail safely: it drives whatever else is on that
 * pin, on a board that is by then unattended. The SIM7070G HAT's logic
 * voltage is selectable between 5 V and 3.3 V by a 0-ohm resistor, and 5 V
 * into a Pi GPIO destroys the pin. So with nothing configured this program
 * refuses, says which key it wanted, and exits non-zero. The refusal is
 * visible rather than silent, which is the state this project is in on
 * Monday 21 September 2026: the board has not been read yet.
 *
 * Written against the libgpiod v2 API.
 *
 * SPDX-License-Identifier: MIT
 */

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <gpiod.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define TRACKER_CONF  "/etc/bench/tracker.conf"
/*
 * The Raspberry Pi 3, not the Pi 4. Project 15's tool defaults to
 * pinctrl-bcm2711 because it runs on a Pi 4, and the two labels differ.
 * A tool that found the wrong chip would still find lines at the offsets
 * it was given, which is the failure that looks like success.
 */
#define DEFAULT_LABEL "pinctrl-bcm2835"
#define CONSUMER      "tracker-gpio"
#define UNSET         ((unsigned int)-1)

struct config {
	unsigned int pwrkey;
	unsigned int marker;
	long press_ms;
	bool pwrkey_active_low;
	bool marker_active_low;
	char chip_label[64];
};

static volatile sig_atomic_t stop_requested;

static void on_signal(int sig)
{
	(void)sig;
	stop_requested = 1;
}

/*
 * Key=value, and the same three traps the tracker's own reader handles:
 * a byte order mark on the first key, CRLF endings, and a final line with
 * no newline. The file is written on Windows after flashing, so all three
 * are the ordinary case rather than the exotic one.
 */
static void trim(char *s)
{
	size_t len = strlen(s);

	while (len > 0 && (s[len - 1] == '\n' || s[len - 1] == '\r' ||
			   s[len - 1] == ' ' || s[len - 1] == '\t'))
		s[--len] = '\0';
}

static bool parse_offset(const char *value, unsigned int *out)
{
	char *end;
	unsigned long parsed;

	errno = 0;
	parsed = strtoul(value, &end, 10);
	if (errno != 0 || end == value || *end != '\0' || parsed > 1024)
		return false;
	*out = (unsigned int)parsed;
	return true;
}

static void read_config(struct config *cfg)
{
	FILE *fp;
	char line[256];
	bool first = true;

	cfg->pwrkey = UNSET;
	cfg->marker = UNSET;
	cfg->press_ms = 1200;   /* SIMCom parts want about a second */
	cfg->pwrkey_active_low = false;
	cfg->marker_active_low = false;
	snprintf(cfg->chip_label, sizeof(cfg->chip_label), "%s", DEFAULT_LABEL);

	fp = fopen(TRACKER_CONF, "r");
	if (!fp)
		return;

	while (fgets(line, sizeof(line), fp)) {
		char *key = line, *value;

		if (first) {
			first = false;
			if (strncmp(key, "\xef\xbb\xbf", 3) == 0)
				key += 3;
		}
		trim(key);
		while (*key == ' ' || *key == '\t')
			key++;
		if (*key == '\0' || *key == '#')
			continue;
		value = strchr(key, '=');
		if (!value)
			continue;
		*value++ = '\0';
		trim(key);

		if (strcmp(key, "pwrkey_gpio") == 0)
			parse_offset(value, &cfg->pwrkey);
		else if (strcmp(key, "marker_gpio") == 0)
			parse_offset(value, &cfg->marker);
		else if (strcmp(key, "pwrkey_press_ms") == 0)
			cfg->press_ms = strtol(value, NULL, 10);
		else if (strcmp(key, "pwrkey_active_low") == 0)
			cfg->pwrkey_active_low = (strcmp(value, "1") == 0);
		else if (strcmp(key, "marker_active_low") == 0)
			cfg->marker_active_low = (strcmp(value, "1") == 0);
		else if (strcmp(key, "gpio_chip") == 0)
			snprintf(cfg->chip_label, sizeof(cfg->chip_label),
				 "%s", value);
	}
	fclose(fp);
}

/*
 * Find the chip by label rather than by /dev/gpiochipN. The number is
 * assigned in probe order and a Pi with an overlay loaded can shift it,
 * which is the class of bug that only appears once something else is
 * plugged in.
 */
static struct gpiod_chip *open_chip_by_label(const char *label)
{
	char path[64];
	int i;

	for (i = 0; i < 32; i++) {
		struct gpiod_chip *chip;
		struct gpiod_chip_info *info;
		bool match;

		snprintf(path, sizeof(path), "/dev/gpiochip%d", i);
		chip = gpiod_chip_open(path);
		if (!chip)
			continue;
		info = gpiod_chip_get_info(chip);
		if (!info) {
			gpiod_chip_close(chip);
			continue;
		}
		match = strcmp(gpiod_chip_info_get_label(info), label) == 0;
		gpiod_chip_info_free(info);
		if (match)
			return chip;
		gpiod_chip_close(chip);
	}
	return NULL;
}

static struct gpiod_line_request *request_output(struct gpiod_chip *chip,
						 unsigned int offset,
						 bool active_low,
						 enum gpiod_line_value initial)
{
	struct gpiod_line_settings *settings;
	struct gpiod_line_config *line_cfg;
	struct gpiod_request_config *req_cfg;
	struct gpiod_line_request *request = NULL;

	settings = gpiod_line_settings_new();
	line_cfg = gpiod_line_config_new();
	req_cfg = gpiod_request_config_new();
	if (!settings || !line_cfg || !req_cfg)
		goto out;

	gpiod_line_settings_set_direction(settings,
					  GPIOD_LINE_DIRECTION_OUTPUT);
	gpiod_line_settings_set_active_low(settings, active_low);
	gpiod_line_settings_set_output_value(settings, initial);
	if (gpiod_line_config_add_line_settings(line_cfg, &offset, 1,
						settings) < 0)
		goto out;
	gpiod_request_config_set_consumer(req_cfg, CONSUMER);
	request = gpiod_chip_request_lines(chip, req_cfg, line_cfg);

out:
	if (req_cfg)
		gpiod_request_config_free(req_cfg);
	if (line_cfg)
		gpiod_line_config_free(line_cfg);
	if (settings)
		gpiod_line_settings_free(settings);
	return request;
}

static int refuse(const char *key, const char *what)
{
	fprintf(stderr,
		"tracker-gpio: refusing to %s: %s is not set in %s.\n"
		"tracker-gpio: there is no default, because a GPIO offset is a\n"
		"tracker-gpio: property of this HAT on this board revision and\n"
		"tracker-gpio: a wrong one drives whatever else is on the pin.\n"
		"tracker-gpio: read the header, then set %s.\n",
		what, key, TRACKER_CONF, key);
	return 2;
}

static void sleep_ms(long ms)
{
	struct timespec ts;

	ts.tv_sec = ms / 1000;
	ts.tv_nsec = (ms % 1000) * 1000000L;
	nanosleep(&ts, NULL);
}

static int do_pwrkey(struct config *cfg, int argc, char **argv)
{
	struct gpiod_chip *chip;
	struct gpiod_line_request *request;
	long press = cfg->press_ms;

	if (cfg->pwrkey == UNSET)
		return refuse("pwrkey_gpio", "pulse the power key");
	if (argc > 0)
		press = strtol(argv[0], NULL, 10);

	chip = open_chip_by_label(cfg->chip_label);
	if (!chip) {
		fprintf(stderr, "tracker-gpio: no gpiochip labelled %s\n",
			cfg->chip_label);
		return 1;
	}
	request = request_output(chip, cfg->pwrkey, cfg->pwrkey_active_low,
				 GPIOD_LINE_VALUE_INACTIVE);
	if (!request) {
		fprintf(stderr, "tracker-gpio: cannot request offset %u: %s\n",
			cfg->pwrkey, strerror(errno));
		gpiod_chip_close(chip);
		return 1;
	}
	gpiod_line_request_set_value(request, cfg->pwrkey,
				     GPIOD_LINE_VALUE_ACTIVE);
	sleep_ms(press);
	gpiod_line_request_set_value(request, cfg->pwrkey,
				     GPIOD_LINE_VALUE_INACTIVE);
	printf("pwrkey: offset %u pulsed for %ld ms\n", cfg->pwrkey, press);

	gpiod_line_request_release(request);
	gpiod_chip_close(chip);
	return 0;
}

static int do_marker_hold(struct config *cfg)
{
	struct gpiod_chip *chip;
	struct gpiod_line_request *request;
	struct sigaction sa;
	sigset_t blocked, original;

	if (cfg->marker == UNSET)
		return refuse("marker_gpio", "hold the instrument marker");

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_signal;
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);

	/*
	 * BLOCK THE TWO SIGNALS BEFORE TOUCHING THE LINE, AND WAIT WITH
	 * sigsuspend RATHER THAN pause.
	 *
	 * The obvious loop, "while (!stop_requested) pause();", has a race
	 * that is invisible until it matters: a SIGTERM delivered between
	 * the test and the pause sets the flag, finds no pause to interrupt,
	 * and the process then sleeps until the next signal that never
	 * comes. Project 15's lte-gpio has the same loop in its flight-hold
	 * and gets away with it, because there the cost is a unit that takes
	 * its stop timeout to die.
	 *
	 * Here the cost is silent and lands in a published number. The
	 * tracker ends a report by terminating this process and waits five
	 * seconds before resorting to SIGKILL. If the signal falls in the
	 * window, the marker line stays HIGH for those five seconds, the
	 * PPK2 integrates five extra seconds of post-report current into the
	 * charge budget, and nothing anywhere says so. A measurement that is
	 * wrong and reports itself as fine is the failure this whole project
	 * is arranged to avoid.
	 *
	 * Blocking first and then atomically unblocking inside sigsuspend
	 * closes the window: a signal arriving before the wait is held
	 * pending and delivered the moment the wait begins.
	 */
	sigemptyset(&blocked);
	sigaddset(&blocked, SIGTERM);
	sigaddset(&blocked, SIGINT);
	if (sigprocmask(SIG_BLOCK, &blocked, &original) != 0) {
		fprintf(stderr, "tracker-gpio: cannot block signals: %s\n",
			strerror(errno));
		return 1;
	}

	chip = open_chip_by_label(cfg->chip_label);
	if (!chip) {
		fprintf(stderr, "tracker-gpio: no gpiochip labelled %s\n",
			cfg->chip_label);
		return 1;
	}
	request = request_output(chip, cfg->marker, cfg->marker_active_low,
				 GPIOD_LINE_VALUE_ACTIVE);
	if (!request) {
		fprintf(stderr, "tracker-gpio: cannot request offset %u: %s\n",
			cfg->marker, strerror(errno));
		gpiod_chip_close(chip);
		return 1;
	}
	/*
	 * Announced on stdout and flushed, so the caller can wait for the
	 * line to be high before it starts the thing being measured. Without
	 * the flush the message sits in a buffer until exit, by which time
	 * it describes something that has already finished.
	 */
	printf("marker: offset %u held active\n", cfg->marker);
	fflush(stdout);

	/*
	 * sigsuspend installs the original mask, waits, and restores the
	 * blocked one, all as one uninterruptible step. It always returns
	 * -1 with EINTR, which is why its result is not checked.
	 */
	while (!stop_requested)
		sigsuspend(&original);
	sigprocmask(SIG_SETMASK, &original, NULL);

	gpiod_line_request_set_value(request, cfg->marker,
				     GPIOD_LINE_VALUE_INACTIVE);
	gpiod_line_request_release(request);
	gpiod_chip_close(chip);
	return 0;
}

static int do_info(struct config *cfg)
{
	struct gpiod_chip *chip;

	printf("chip label:  %s\n", cfg->chip_label);
	if (cfg->pwrkey == UNSET)
		printf("pwrkey_gpio: not set, so pwrkey refuses\n");
	else
		printf("pwrkey_gpio: %u, active %s, %ld ms\n", cfg->pwrkey,
		       cfg->pwrkey_active_low ? "low" : "high", cfg->press_ms);
	if (cfg->marker == UNSET)
		printf("marker_gpio: not set, so the trace has no report "
		       "markers and criterion 6 cannot be met\n");
	else
		printf("marker_gpio: %u, active %s\n", cfg->marker,
		       cfg->marker_active_low ? "low" : "high");

	chip = open_chip_by_label(cfg->chip_label);
	if (!chip) {
		printf("chip:        not present on this host\n");
		return 0;
	}
	printf("chip:        found\n");
	gpiod_chip_close(chip);
	return 0;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: tracker-gpio pwrkey [ms]\n"
		"       tracker-gpio marker-hold\n"
		"       tracker-gpio info\n");
}

int main(int argc, char **argv)
{
	struct config cfg;

	if (argc < 2) {
		usage();
		return 2;
	}
	read_config(&cfg);

	if (strcmp(argv[1], "pwrkey") == 0)
		return do_pwrkey(&cfg, argc - 2, argv + 2);
	if (strcmp(argv[1], "marker-hold") == 0)
		return do_marker_hold(&cfg);
	if (strcmp(argv[1], "info") == 0)
		return do_info(&cfg);

	usage();
	return 2;
}
