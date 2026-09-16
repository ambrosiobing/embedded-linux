/*
 * iio-stream - one buffer loop, printed as CSV, from a local or a remote
 * context.
 *
 *     iio-stream [-u URI] [-d DEVICE] [-n SCANS] [-b SAMPLES]
 *
 * The URI is the only thing that differs between reading the sensor on the
 * board and reading it from a PC across the network:
 *
 *     iio-stream                          local, the default
 *     iio-stream -u ip:rpi3.local         through iiod, TCP 30431
 *
 * That is the claim this program exists to make, and the acceptance table
 * checks it by diffing the two outputs.
 *
 * WHY THERE ARE NO OFFSETS IN THIS FILE
 *
 * The obvious buffer loop indexes into each scan with literal byte
 * offsets: 0, 2, 4 for three 16-bit channels and 8 for the timestamp. They
 * are correct for one configuration and wrong for every other, and nothing
 * reports an error when they are wrong. The numbers stay plausible.
 *
 * iio_buffer_first(buf, chn) returns the address of that channel's first
 * sample, and iio_buffer_step(buf) is the distance from one scan to the
 * next. Between them the layout is the library's problem, which is where
 * it belongs: it read the same scan_elements this program would have had
 * to parse.
 *
 * SPDX-License-Identifier: MIT
 */

#include <errno.h>
#include <iio.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_CHANNELS 8

/*
 * Widen one converted sample to int64_t.
 *
 * iio_channel_convert() writes exactly the channel's storage width and no
 * more: two bytes for an s16, four for an s32. Handing it an int64_t and
 * reading the whole thing back leaves six bytes of whatever was on the
 * stack, and the result is a number that is occasionally, spectacularly
 * wrong and usually fine, which is the worst of both.
 *
 * So convert into a scratch of the right width and widen deliberately,
 * which is also the only place the signedness of the channel has to be
 * consulted rather than assumed.
 */
static int64_t widen(const struct iio_data_format *fmt, const void *scratch)
{
    switch (fmt->length / 8) {
    case 1:
        return fmt->is_signed ? (int64_t)*(const int8_t *)scratch
                              : (int64_t)*(const uint8_t *)scratch;
    case 2:
        return fmt->is_signed ? (int64_t)*(const int16_t *)scratch
                              : (int64_t)*(const uint16_t *)scratch;
    case 4:
        return fmt->is_signed ? (int64_t)*(const int32_t *)scratch
                              : (int64_t)*(const uint32_t *)scratch;
    case 8:
        return *(const int64_t *)scratch;
    default:
        return 0;
    }
}

static volatile sig_atomic_t stop;

static void on_signal(int sig)
{
    (void)sig;
    stop = 1;
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s [-u URI] [-d DEVICE] [-n SCANS] [-b SAMPLES]\n"
            "  -u  context URI, default \"local:\"\n"
            "  -d  device name, default \"lsm6dsv16x_accel\"\n"
            "  -n  number of buffer refills, 0 for until interrupted\n"
            "  -b  samples per buffer, default 256\n",
            argv0);
}

int main(int argc, char **argv)
{
    const char *uri = "local:";
    const char *device_name = "lsm6dsv16x_accel";
    unsigned int refills = 40;
    unsigned int buffer_samples = 256;
    int opt;

    while ((opt = getopt(argc, argv, "u:d:n:b:h")) != -1) {
        switch (opt) {
        case 'u': uri = optarg; break;
        case 'd': device_name = optarg; break;
        case 'n': refills = (unsigned int)strtoul(optarg, NULL, 10); break;
        case 'b': buffer_samples = (unsigned int)strtoul(optarg, NULL, 10); break;
        default: usage(argv[0]); return 2;
        }
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);

    struct iio_context *ctx = iio_create_context_from_uri(uri);
    if (!ctx) {
        fprintf(stderr, "no context at %s: %s\n", uri, strerror(errno));
        fprintf(stderr,
                "  local:  needs the drivers bound; try iio-probe\n"
                "  ip:...  needs iiod running and reachable on 30431\n");
        return 1;
    }

    struct iio_device *dev = iio_context_find_device(ctx, device_name);
    if (!dev) {
        fprintf(stderr, "no device named %s in this context\n", device_name);
        fprintf(stderr, "devices present:\n");
        for (unsigned int i = 0; i < iio_context_get_devices_count(ctx); i++) {
            const struct iio_device *d = iio_context_get_device(ctx, i);
            const char *name = iio_device_get_name(d);
            fprintf(stderr, "  %s\n", name ? name : iio_device_get_id(d));
        }
        iio_context_destroy(ctx);
        return 1;
    }

    /*
     * Enable every scan channel the device has, rather than a list of
     * names written here. A hard-coded list is the same mistake as a
     * hard-coded offset one level up: it works on the accelerometer and
     * silently reads nothing on the magnetometer, whose channels are
     * called in_magn_x and not in_accel_x.
     *
     * A channel with no scan element is not part of the buffer and
     * enabling it is meaningless, so those are skipped rather than
     * treated as an error.
     */
    struct iio_channel *channels[MAX_CHANNELS];
    unsigned int enabled = 0;

    for (unsigned int i = 0; i < iio_device_get_channels_count(dev); i++) {
        struct iio_channel *chn = iio_device_get_channel(dev, i);

        if (iio_channel_is_output(chn))
            continue;
        if (!iio_channel_is_scan_element(chn))
            continue;
        if (enabled >= MAX_CHANNELS) {
            fprintf(stderr, "more than %d scan channels; raise MAX_CHANNELS\n",
                    MAX_CHANNELS);
            iio_context_destroy(ctx);
            return 1;
        }
        iio_channel_enable(chn);
        channels[enabled++] = chn;
    }

    if (enabled == 0) {
        fprintf(stderr, "%s has no scan elements, so it has no buffer.\n",
                device_name);
        fprintf(stderr, "Read it through sysfs instead: iio-rate poll %s\n",
                device_name);
        iio_context_destroy(ctx);
        return 1;
    }

    struct iio_buffer *buf = iio_device_create_buffer(dev, buffer_samples, false);
    if (!buf) {
        fprintf(stderr, "cannot create a buffer on %s: %s\n", device_name,
                strerror(errno));
        /*
         * The overwhelmingly common cause, and the one the message has to
         * name because the errno does not: an IIO buffer has exactly one
         * reader. If iiod is serving this device to the network, a local
         * client cannot open it, and the reverse is equally true.
         */
        fprintf(stderr,
                "An IIO buffer has one reader. If iiod is running and a\n"
                "client is attached, stop one of them: systemctl stop iiod\n");
        iio_context_destroy(ctx);
        return 1;
    }

    for (unsigned int i = 0; i < enabled; i++)
        printf("%s%s", i ? "," : "", iio_channel_get_id(channels[i]));
    printf("\n");

    for (unsigned int n = 0; (refills == 0 || n < refills) && !stop; n++) {
        ssize_t got = iio_buffer_refill(buf);

        if (got < 0) {
            fprintf(stderr, "refill failed: %s\n", strerror((int)-got));
            break;
        }

        ptrdiff_t step = iio_buffer_step(buf);
        char *end = iio_buffer_end(buf);

        /*
         * One base pointer per channel, then walk all of them together in
         * step. This is the whole reason no offsets appear in this file:
         * iio_buffer_first() knows where each channel starts because the
         * library parsed the scan layout, and step is the distance from
         * one scan to the next whatever that layout is.
         */
        char *base[MAX_CHANNELS];
        for (unsigned int i = 0; i < enabled; i++)
            base[i] = iio_buffer_first(buf, channels[i]);

        for (char *p = base[0]; p < end; p += step) {
            ptrdiff_t advance = p - base[0];

            for (unsigned int i = 0; i < enabled; i++) {
                const struct iio_data_format *fmt =
                    iio_channel_get_data_format(channels[i]);
                int64_t scratch = 0;
                int64_t value;

                /*
                 * convert() applies endianness, the shift and sign
                 * extension, within the channel's own storage width. It
                 * does not apply scale, which is a separate attribute and
                 * must never be applied to a timestamp.
                 */
                iio_channel_convert(channels[i], &scratch, base[i] + advance);
                value = widen(fmt, &scratch);

                if (fmt->with_scale && !strstr(iio_channel_get_id(channels[i]),
                                               "timestamp")) {
                    printf("%s%.6f", i ? "," : "", (double)value * fmt->scale);
                } else {
                    printf("%s%lld", i ? "," : "", (long long)value);
                }
            }
            printf("\n");
        }
    }

    iio_buffer_destroy(buf);
    iio_context_destroy(ctx);
    return 0;
}
