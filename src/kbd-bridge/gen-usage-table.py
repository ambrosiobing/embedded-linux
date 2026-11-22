#!/usr/bin/env python3
"""Generate usage_table.h from the kernel's own hid-input.c.

    gen-usage-table.py <hid-input.c> <usage_table.h>

WHY GENERATED AND NOT TYPED

The bridge needs to turn a Linux keycode into a HID usage. The kernel
already has that mapping, in the other direction, as

    static const unsigned char hid_keyboard[256] = { ... };

in drivers/hid/hid-input.c, where the INDEX is the HID usage and the
VALUE is the Linux keycode. Typing the inverse by hand is 100 or so
lines of numbers that nobody will ever proofread, and a single
transposition produces a keyboard where one key types a different letter
on the host. Generating it makes the table complete, traceable to a
kernel revision, and reproducible.

THE AMBIGUITY, AND HOW IT IS RESOLVED

The forward map is not injective: several usages map to the same
keycode. In rpi-6.6.y for example usages 0x31 and 0x32 both map to
keycode 43 (KEY_BACKSLASH), and keycode 111 (KEY_DELETE) appears three
times.

Inverting it therefore needs a rule, and the rule here is THE LOWEST
USAGE WINS. That is the usage a real keyboard sends for the key: the
duplicates are alternate positions on national layouts and the
keypad-equals variants, which a boot-protocol keyboard does not
distinguish. The generated header records every collision in a comment
so the choice is visible rather than silent.

KEY_UNKNOWN (240) means the kernel has no mapping for that usage, and
those entries are skipped entirely rather than inverted into a keycode
that would then type something arbitrary.
"""
import re
import sys


def parse_forward_table(source_text):
    """Return a list of 256 keycodes indexed by HID usage."""
    match = re.search(
        r"static\s+const\s+unsigned\s+char\s+hid_keyboard\s*\[\s*256\s*\]"
        r"\s*=\s*\{(.*?)\};",
        source_text, re.S)
    if not match:
        raise SystemExit("hid_keyboard[256] not found: has the kernel "
                         "renamed or reshaped the table?")

    body = match.group(1)
    # The table writes unmapped entries as the macro "unk", which
    # hid-input.c defines as KEY_UNKNOWN.
    body = body.replace("unk", "240")

    values = [int(v) for v in re.findall(r"\b\d+\b", body)]
    if len(values) != 256:
        raise SystemExit("hid_keyboard has %d entries, expected 256"
                         % len(values))
    return values


def invert(forward):
    """keycode -> lowest HID usage that maps to it, and the collisions."""
    reverse = {}
    collisions = {}
    for usage, keycode in enumerate(forward):
        # 0 is "no event", 1 to 3 are the error roll-over codes, and 240
        # is KEY_UNKNOWN. None of them is a key.
        if keycode == 0 or keycode == 240:
            continue
        if usage <= 3:
            continue
        if keycode in reverse:
            collisions.setdefault(keycode, [reverse[keycode]]).append(usage)
            continue
        reverse[keycode] = usage
    return reverse, collisions


def emit(reverse, collisions, source_name):
    largest = max(reverse)
    lines = [
        "/* SPDX-License-Identifier: MIT",
        " *",
        " * Linux keycode to HID usage. GENERATED, DO NOT EDIT.",
        " *",
        " * Produced by gen-usage-table.py from the kernel's own",
        " * %s, by inverting hid_keyboard[256]." % source_name,
        " * Regenerate rather than patch:",
        " *",
        " *     python3 gen-usage-table.py hid-input.c usage_table.h",
        " *",
        " * Entries the kernel maps to KEY_UNKNOWN are omitted, so a zero",
        " * here means 'this key has no HID usage' and the caller must",
        " * drop the event rather than send usage 0, which is the",
        " * reserved 'no event' code.",
        " */",
        "",
        "#ifndef BENCH_USAGE_TABLE_H",
        "#define BENCH_USAGE_TABLE_H",
        "",
        "#include <stdint.h>",
        "",
        "/* Indexed by Linux keycode. %d entries." % (largest + 1),
        " *",
        " * Collisions in the forward table, resolved by taking the",
        " * LOWEST usage, listed here so the choice is visible:",
    ]
    if collisions:
        for keycode in sorted(collisions):
            usages = ", ".join("0x%02x" % u for u in sorted(collisions[keycode]))
            lines.append(" *   keycode %-3d <- usages %s  (chose 0x%02x)"
                         % (keycode, usages, min(collisions[keycode])))
    else:
        lines.append(" *   none")
    lines += [
        " */",
        "static const uint8_t keycode_to_usage[%d] = {" % (largest + 1),
    ]

    row = []
    for keycode in range(largest + 1):
        row.append("0x%02x," % reverse.get(keycode, 0))
        if len(row) == 12:
            lines.append("\t" + " ".join(row))
            row = []
    if row:
        lines.append("\t" + " ".join(row))

    lines += [
        "};",
        "",
        "#define KEYCODE_TO_USAGE_MAX %d" % largest,
        "",
        "#endif /* BENCH_USAGE_TABLE_H */",
        "",
    ]
    return "\n".join(lines)


def main(argv):
    if len(argv) != 3:
        raise SystemExit(__doc__.strip().splitlines()[2].strip())

    with open(argv[1], "r", errors="replace") as handle:
        text = handle.read()

    forward = parse_forward_table(text)
    reverse, collisions = invert(forward)

    # Three spot checks against the HID usage tables, so that a
    # restructured kernel table cannot silently produce a plausible but
    # wrong header. These are the three every HID document opens with.
    expected = {30: 0x04, 48: 0x05, 2: 0x1e}   # a, b, 1
    for keycode, usage in expected.items():
        if reverse.get(keycode) != usage:
            raise SystemExit(
                "sanity check failed: keycode %d should map to usage 0x%02x, "
                "got 0x%02x. The kernel table has changed shape."
                % (keycode, usage, reverse.get(keycode, 0)))

    with open(argv[2], "w", newline="\n") as handle:
        handle.write(emit(reverse, collisions, argv[1].split("/")[-1]))

    print("usage_table.h: %d keycodes mapped, %d collisions resolved"
          % (len(reverse), len(collisions)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
