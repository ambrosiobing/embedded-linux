/*
 * bench-diag - the bench's voltmeter, continuity tester and logic probe,
 * built out of the GPIO lines that are already on every board here.
 *
 * WHY THIS EXISTS.
 *
 * There is no handheld multimeter on this bench. On Tuesday 21 October
 * 2026 an ADXL345 answered nothing on either bus for five hours, and the
 * cause turned out to be that its VCC and its GND were the same net: both
 * went to a breadboard's +V rail and that rail was fed from header pin 9,
 * which is a ground. The part had no supply at all, through every scan and
 * five probe failures with -121.
 *
 * It was found with nothing but gpioget, by reading a line twice under
 * opposite bias settings. That worked, and doing it by hand took twelve
 * commands and a paragraph of arithmetic per answer, which is why the
 * method is in a program now rather than in a journal entry.
 *
 * THE ONE IDEA. A GPIO configured as an input is a one-bit voltmeter with
 * a threshold near 1.3 V. One reading cannot tell a driven line from a
 * floating one, because a floating line reads whatever the internal bias
 * resistor says. TWO readings can:
 *
 *     pull-up  pull-down   the line is
 *        0         0       driven low by something
 *        1         1       driven high by something
 *        1         0       floating, nothing on it
 *
 * The fourth combination, 0 under a pull-up and 1 under a pull-down,
 * cannot happen and is reported as a fault in the measurement rather
 * than silently folded into one of the other three.
 *
 * WHAT IT CANNOT DO, said here because a tool that overstates itself is
 * worse than no tool. It cannot read a number, so a rail at 3.3 V and one
 * drooping to 2.1 V are the same answer. It cannot go above 3.3 V, so a
 * 5 V rail is out of reach and connecting one to a GPIO would damage it.
 * It cannot measure resistance or current; the PPK2 does current. And it
 * can only see what is referenced to this board's ground, which excludes
 * the Nucleo, the modem HATs and the isolated side of the CAN board.
 *
 * SPDX-License-Identifier: MIT
 */

/*
 * Before the includes, and deliberately. sleep() is POSIX, and a strict
 * -std=c11 hides every POSIX name, so the watch subcommand fails to
 * compile with an implicit declaration that -Werror then turns into an
 * error. This repository has paid for that one before.
 */
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <gpiod.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define CONSUMER "bench-diag"

enum verdict {
	V_DRIVEN_HIGH,
	V_DRIVEN_LOW,
	V_FLOATING,
	V_IMPOSSIBLE,
	V_ERROR,
};

static const char *verdict_name(enum verdict v)
{
	switch (v) {
	case V_DRIVEN_HIGH:
		return "DRIVEN-HIGH";
	case V_DRIVEN_LOW:
		return "DRIVEN-LOW";
	case V_FLOATING:
		return "FLOATING";
	case V_IMPOSSIBLE:
		return "IMPOSSIBLE";
	default:
		return "ERROR";
	}
}

/*
 * A bare "gpiochip0" is what gpioget takes and what anybody types, so it
 * is accepted here too rather than being a second thing to remember.
 */
static struct gpiod_chip *open_chip(const char *name)
{
	char path[64];
	struct gpiod_chip *chip;

	if (name[0] == '/')
		snprintf(path, sizeof(path), "%s", name);
	else
		snprintf(path, sizeof(path), "/dev/%s", name);

	chip = gpiod_chip_open(path);
	if (!chip)
		fprintf(stderr, "%s: cannot open %s: %s\n", CONSUMER, path,
			strerror(errno));
	return chip;
}

/*
 * Reading one line under one bias. The request is taken and released
 * every time rather than held, because holding an input is what stops
 * the next subcommand, and anybody else, from asking the same question.
 */
static int read_once(struct gpiod_chip *chip, unsigned int offset,
		     enum gpiod_line_bias bias, int *out)
{
	struct gpiod_line_settings *settings = NULL;
	struct gpiod_line_config *line_cfg = NULL;
	struct gpiod_request_config *req_cfg = NULL;
	struct gpiod_line_request *request = NULL;
	enum gpiod_line_value value;
	int rc = -1;

	settings = gpiod_line_settings_new();
	line_cfg = gpiod_line_config_new();
	req_cfg = gpiod_request_config_new();
	if (!settings || !line_cfg || !req_cfg)
		goto out;

	gpiod_line_settings_set_direction(settings,
					  GPIOD_LINE_DIRECTION_INPUT);
	gpiod_line_settings_set_bias(settings, bias);

	if (gpiod_line_config_add_line_settings(line_cfg, &offset, 1,
						settings))
		goto out;

	gpiod_request_config_set_consumer(req_cfg, CONSUMER);

	request = gpiod_chip_request_lines(chip, req_cfg, line_cfg);
	if (!request)
		goto out;

	value = gpiod_line_request_get_value(request, offset);
	if (value == GPIOD_LINE_VALUE_ERROR)
		goto out;

	*out = (value == GPIOD_LINE_VALUE_ACTIVE) ? 1 : 0;
	rc = 0;
out:
	if (request)
		gpiod_line_request_release(request);
	if (req_cfg)
		gpiod_request_config_free(req_cfg);
	if (line_cfg)
		gpiod_line_config_free(line_cfg);
	if (settings)
		gpiod_line_settings_free(settings);
	return rc;
}

/* The two readings and the table from the header comment. */
static enum verdict probe(struct gpiod_chip *chip, unsigned int offset,
			  int *up_out, int *down_out)
{
	int up, down;

	if (read_once(chip, offset, GPIOD_LINE_BIAS_PULL_UP, &up))
		return V_ERROR;
	if (read_once(chip, offset, GPIOD_LINE_BIAS_PULL_DOWN, &down))
		return V_ERROR;

	if (up_out)
		*up_out = up;
	if (down_out)
		*down_out = down;

	if (up == 1 && down == 1)
		return V_DRIVEN_HIGH;
	if (up == 0 && down == 0)
		return V_DRIVEN_LOW;
	if (up == 1 && down == 0)
		return V_FLOATING;
	return V_IMPOSSIBLE;
}

/*
 * Whether a line is already somebody else's. Driving a line a driver
 * holds, or reading one and re-muxing it out from under a controller, is
 * how a diagnostic becomes the fault. The I2C pins are the case that
 * matters: reading them works and leaves the bus dead until a reboot,
 * because libgpiod does not put the pin mux back.
 */
static bool line_is_used(struct gpiod_chip *chip, unsigned int offset,
			 const char **consumer)
{
	static char held[64];
	struct gpiod_line_info *info;
	bool used;

	info = gpiod_chip_get_line_info(chip, offset);
	if (!info)
		return false;

	used = gpiod_line_info_is_used(info);
	if (used && consumer) {
		const char *name = gpiod_line_info_get_consumer(info);

		snprintf(held, sizeof(held), "%s", name ? name : "unnamed");
		*consumer = held;
	}
	gpiod_line_info_free(info);
	return used;
}

static int cmd_level(struct gpiod_chip *chip, unsigned int offset)
{
	const char *consumer = NULL;
	enum verdict v;
	int up, down;

	if (line_is_used(chip, offset, &consumer))
		printf("note     line %u is held by %s\n", offset, consumer);
		puts("         so this reads a line under someone else's control");

	v = probe(chip, offset, &up, &down);
	printf("pull-up %d  pull-down %d  ->  %s\n", up, down, verdict_name(v));

	switch (v) {
	case V_DRIVEN_LOW:
		puts("         Something is holding this line down against a pull-up.");
		break;
	case V_DRIVEN_HIGH:
		puts("         Something is holding this line up against a pull-down.");
		break;
	case V_FLOATING:
		puts("         Nothing is on this line. An open lead, an open");
		puts("         contact, or a part with no supply all read this way,");
		puts("         and this cannot tell them apart.");
		break;
	case V_IMPOSSIBLE:
		puts("         A pull-up cannot read lower than a pull-down.");
		puts("         Suspect the measurement, not the circuit.");
		break;
	default:
		return 1;
	}

	puts("         NOT looked at: the voltage's value, anything above 3.3 V,");
	puts("         and anything not referenced to this board's ground.");
	return 0;
}

static int cmd_rail(struct gpiod_chip *chip, unsigned int offset)
{
	enum verdict v = probe(chip, offset, NULL, NULL);

	if (v == V_ERROR)
		return 1;
	if (v == V_DRIVEN_HIGH) {
		puts("SUPPLY-PRESENT   above 1.3 V, beating a pull-down");
		puts("         NOT established: 3.3 V rather than 2 V");
		return 0;
	}
	printf("NO-SUPPLY        %s\n", verdict_name(v));
	puts("                 Probe the part's own row, never a breadboard power");
	puts("                 rail: a rail and a row are different conductors");
	puts("                 unless a lead joins them.");
	return 0;
}

static int cmd_ground(struct gpiod_chip *chip, unsigned int offset)
{
	enum verdict v = probe(chip, offset, NULL, NULL);

	if (v == V_ERROR)
		return 1;
	if (v == V_DRIVEN_LOW) {
		puts("GROUNDED         held down against an internal pull-up");
		return 0;
	}
	printf("NOT-GROUNDED     %s\n", verdict_name(v));
	return 0;
}

/*
 * Continuity, which is the one subcommand that drives a line, and so the
 * one that can do damage. Three refusals guard it, and each prints what
 * it matched, because a refusal without evidence gets switched off.
 */
static int drive_and_sense(struct gpiod_chip *chip, unsigned int drive,
			   unsigned int sense, int level, int *out)
{
	struct gpiod_line_settings *settings = NULL;
	struct gpiod_line_config *line_cfg = NULL;
	struct gpiod_request_config *req_cfg = NULL;
	struct gpiod_line_request *request = NULL;
	enum gpiod_line_bias bias;
	int rc = -1;

	settings = gpiod_line_settings_new();
	line_cfg = gpiod_line_config_new();
	req_cfg = gpiod_request_config_new();
	if (!settings || !line_cfg || !req_cfg)
		goto out;

	gpiod_line_settings_set_direction(settings,
					  GPIOD_LINE_DIRECTION_OUTPUT);
	gpiod_line_settings_set_output_value(settings,
					     level ? GPIOD_LINE_VALUE_ACTIVE :
						     GPIOD_LINE_VALUE_INACTIVE);
	if (gpiod_line_config_add_line_settings(line_cfg, &drive, 1, settings))
		goto out;

	gpiod_request_config_set_consumer(req_cfg, CONSUMER);
	request = gpiod_chip_request_lines(chip, req_cfg, line_cfg);
	if (!request)
		goto out;

	/*
	 * The sense bias opposes the drive, so a conducting lead has to win
	 * against a resistor rather than merely agree with one. Without
	 * that, a floating sense line would follow its own bias and read as
	 * continuity in one of the two directions.
	 */
	bias = level ? GPIOD_LINE_BIAS_PULL_DOWN : GPIOD_LINE_BIAS_PULL_UP;
	rc = read_once(chip, sense, bias, out);
out:
	if (request)
		gpiod_line_request_release(request);
	if (req_cfg)
		gpiod_request_config_free(req_cfg);
	if (line_cfg)
		gpiod_line_config_free(line_cfg);
	if (settings)
		gpiod_line_settings_free(settings);
	return rc;
}

static int cmd_continuity(struct gpiod_chip *chip, unsigned int drive,
			  unsigned int sense)
{
	const char *consumer = NULL;
	enum verdict before;
	int high, low;

	if (drive == sense) {
		fprintf(stderr,
			"%s: refusing: both lines are %u, a pin against itself\n",
			CONSUMER, drive);
		return 2;
	}
	if (line_is_used(chip, drive, &consumer)) {
		fprintf(stderr, "%s: refusing to drive line %u: held by %s\n",
			CONSUMER, drive, consumer);
		return 2;
	}
	if (line_is_used(chip, sense, &consumer)) {
		fprintf(stderr, "%s: refusing: sense line %u is held by %s\n",
			CONSUMER, sense, consumer);
		return 2;
	}

	/*
	 * The interlock that matters. Driving an output into something that
	 * is already driven is the one way this tool can damage a board, so
	 * the sense line has to be floating before anything is driven into
	 * it. A ground pin reads DRIVEN-LOW, which is exactly the accident
	 * worth refusing: an output into a ground pin sources far more than
	 * a pin is rated for.
	 */
	before = probe(chip, sense, NULL, NULL);
	if (before == V_ERROR)
		return 1;
	if (before != V_FLOATING) {
		fprintf(stderr, "%s: refusing: sense line %u reads %s\n",
			CONSUMER, sense, verdict_name(before));
		fprintf(stderr,
			"       before anything was driven. Driving into a line\n"
			"       something else holds is how a pin dies. If it is\n"
			"       a ground or a supply, use level, rail or ground.\n");
		return 2;
	}

	if (drive_and_sense(chip, drive, sense, 1, &high))
		return 1;
	if (drive_and_sense(chip, drive, sense, 0, &low))
		return 1;

	printf("driven high -> %d   driven low -> %d   ", high, low);
	if (high == 1 && low == 0) {
		puts("CONDUCTS");
		puts("         That path carries a level in both directions,");
		puts("         so the lead and both its ends are good.");
		puts("         NOT established: anything past the pins themselves. A");
		puts("         male pin sitting in an unsoldered module's plated hole");
		puts("         is beyond the reach of this or any external test.");
		return 0;
	}
	if (high == 0 && low == 1) {
		puts("OPEN");
		puts("         The sense line followed its own bias both times, so");
		puts("         nothing crossed. A broken lead, an unseated end, or");
		puts("         nothing plugged in at all.");
		return 0;
	}
	puts("INCONCLUSIVE");
	puts("         The two directions disagree in a way neither continuity");
	puts("         nor an open circuit produces. Suspect the measurement.");
	return 1;
}

static int cmd_watch(struct gpiod_chip *chip, unsigned int offset,
		     unsigned int seconds)
{
	unsigned int elapsed = 0;

	puts("# second  pull-up  pull-down  verdict");
	for (;;) {
		enum verdict v;
		int up, down;

		v = probe(chip, offset, &up, &down);
		printf("%8u  %7d  %9d  %s\n", elapsed, up, down,
		       verdict_name(v));
		fflush(stdout);

		if (seconds && elapsed >= seconds)
			return 0;
		sleep(1);
		elapsed++;
	}
}

/*
 * Every unused line on the chip, both biases. This is the subcommand for
 * "something is shorted and I do not know what to", and it is read as a
 * pattern rather than line by line: a row of FLOATING with two
 * DRIVEN-LOW in it names the two lines worth looking at.
 *
 * Used lines are skipped rather than read, and they are LISTED, because a
 * scan that quietly leaves lines out teaches you to trust a partial
 * answer.
 */
static int cmd_scan(struct gpiod_chip *chip)
{
	struct gpiod_chip_info *info;
	size_t lines, i;
	unsigned int skipped = 0;

	info = gpiod_chip_get_info(chip);
	if (!info) {
		fprintf(stderr, "%s: cannot read chip info\n", CONSUMER);
		return 1;
	}
	lines = gpiod_chip_info_get_num_lines(info);
	gpiod_chip_info_free(info);

	printf("# line  pull-up  pull-down  verdict\n");
	for (i = 0; i < lines; i++) {
		const char *consumer = NULL;
		enum verdict v;
		int up, down;

		if (line_is_used(chip, (unsigned int)i, &consumer)) {
			printf("%6zu  held by %s, not read\n", i, consumer);
			skipped++;
			continue;
		}
		v = probe(chip, (unsigned int)i, &up, &down);
		printf("%6zu  %7d  %9d  %s\n", i, up, down, verdict_name(v));
	}
	printf("# %zu lines, %u skipped because something holds them\n", lines,
	       skipped);
	return 0;
}

static void usage(void)
{
	puts("bench-diag - voltmeter, logic probe and continuity from GPIO");
	puts("");
	puts("  level      <chip> <line>           driven high, low, floating");
	puts("  rail       <chip> <line>           is a supply present");
	puts("  ground     <chip> <line>           is this net tied to ground");
	puts("  continuity <chip> <drive> <sense>  does a lead conduct");
	puts("  watch      <chip> <line> [secs]    the reading once a second");
	puts("  scan       <chip>                  every unused line");
	puts("");
	puts("<chip> is gpiochip0 or /dev/gpiochip0. <line> is a BCM GPIO number,");
	puts("not a header pin number: header pin 18 is line 24 on a Raspberry Pi.");
	puts("");
	puts("It reads a threshold near 1.3 V and never a value, it cannot go above");
	puts("3.3 V, and it sees only what shares this board's ground. Connecting a");
	puts("5 V rail to a GPIO damages it, so check the pin before the command.");
}

int main(int argc, char **argv)
{
	struct gpiod_chip *chip;
	unsigned long a, b;
	const char *cmd;
	int rc;

	if (argc < 2) {
		usage();
		return 2;
	}
	cmd = argv[1];
	if (!strcmp(cmd, "-h") || !strcmp(cmd, "--help")) {
		usage();
		return 0;
	}
	if (argc < 3) {
		usage();
		return 2;
	}

	chip = open_chip(argv[2]);
	if (!chip)
		return 1;

	if (!strcmp(cmd, "scan")) {
		rc = cmd_scan(chip);
		goto done;
	}

	if (argc < 4) {
		usage();
		rc = 2;
		goto done;
	}
	a = strtoul(argv[3], NULL, 10);

	if (!strcmp(cmd, "level")) {
		rc = cmd_level(chip, (unsigned int)a);
	} else if (!strcmp(cmd, "rail")) {
		rc = cmd_rail(chip, (unsigned int)a);
	} else if (!strcmp(cmd, "ground")) {
		rc = cmd_ground(chip, (unsigned int)a);
	} else if (!strcmp(cmd, "watch")) {
		b = (argc > 4) ? strtoul(argv[4], NULL, 10) : 0;
		rc = cmd_watch(chip, (unsigned int)a, (unsigned int)b);
	} else if (!strcmp(cmd, "continuity")) {
		if (argc < 5) {
			usage();
			rc = 2;
			goto done;
		}
		b = strtoul(argv[4], NULL, 10);
		rc = cmd_continuity(chip, (unsigned int)a, (unsigned int)b);
	} else {
		fprintf(stderr, "%s: unknown command %s\n", CONSUMER, cmd);
		usage();
		rc = 2;
	}
done:
	gpiod_chip_close(chip);
	return rc;
}
