#!/bin/sh
#
# keystore-header-test.sh - one number, written in five places.
#
# bench_keystore_ta.h is the contract. Four other files restate parts of
# it because they cannot include a C header: the Python binding, the TA's
# makefile, the recipe that installs the result, and the model the policy
# test drives. A restated value is a value that drifts, and the drift is
# silent: the TA builds, the client builds, and TEEC_OpenSession fails
# with an error that names a missing file rather than a wrong UUID.
#
# So this file parses the header and compares.
#
# The check that matters most is the UUID, because it appears as a C
# macro of eleven separate integers, as a string, as a file name in a
# makefile, as a variable in a recipe and as a string in Python, and the
# eleven-integer form is the one nobody proof-reads.
#
#   sh tests/keystore-header-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=${PYTHON:-python3}

"$PYTHON" -u - "$ROOT" <<'PYTHON'
import os
import re
import sys

root = sys.argv[1]
files = os.path.join(root, "meta-bench", "recipes-bench", "bench-keystore")
src = os.path.join(files, "files")
sys.path.insert(0, os.path.join(root, "tests"))
sys.path.insert(0, src)

passed = 0
failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        print("ok       %s" % label)
        passed += 1
    else:
        print("FAILED   %s: wanted %r, got %r" % (label, want, got))
        failed += 1


def read(*parts):
    with open(os.path.join(*parts), encoding="utf-8") as handle:
        return handle.read()


header = read(src, "bench_keystore_ta.h")

# ------------------------------------------------ the UUID, five ways

# The C macro: 0x7b53ed98, 0xcbfb, 0x42ec, { 0x92, 0xb6, ... }
numbers = re.findall(r"0x([0-9a-fA-F]+)", header.split("UUID_STR")[0])
check("the UUID macro has eleven fields", len(numbers), 11)

parts = [n.lower().rjust(w, "0") for n, w in
         zip(numbers, [8, 4, 4] + [2] * 8)]
from_macro = "%s-%s-%s-%s-%s" % (parts[0], parts[1], parts[2],
                                 "".join(parts[3:5]), "".join(parts[5:]))

match = re.search(r'BENCH_KEYSTORE_UUID_STR\s+"([0-9a-f-]+)"', header)
check("the header has a string form", match is not None, True)
from_string = match.group(1)

check("the macro and the string agree", from_macro, from_string)

makefile = read(src, "ta-Makefile")
match = re.search(r"^BINARY\s*=\s*(\S+)", makefile, re.M)
check("the TA makefile names a BINARY", match is not None, True)
check("and it is the UUID, because that is the file name OP-TEE looks for",
      match.group(1), from_string)

recipe = read(files, "bench-keystore_0.1.bb")
match = re.search(r'^TA_UUID\s*=\s*"([0-9a-f-]+)"', recipe, re.M)
check("the recipe names the same UUID", match.group(1), from_string)

import benchkey

check("and so does the Python binding", benchkey.UUID, from_string)

cli = read(src, "benchkey-cli.c")
check("the CLI prints it from the header rather than restating it",
      "BENCH_KEYSTORE_UUID_STR" in cli and from_string not in cli, True)

# ------------------------------------------------------- command ids


def define(name):
    match = re.search(r"^#define\s+%s\s+(\d+)" % name, header, re.M)
    if not match:
        raise SystemExit("keystore-header-test: %s is not in the header"
                         % name)
    return int(match.group(1))


import keystore_model as model

for suffix, py_name in (("GENERATE", "CMD_GENERATE"),
                        ("SIGN", "CMD_SIGN"),
                        ("EXPORT_ONCE", "CMD_EXPORT_ONCE"),
                        ("STATUS", "CMD_STATUS")):
    value = define("BENCH_CMD_" + suffix)
    check("%s is %d in the binding" % (py_name, value),
          getattr(benchkey, py_name), value)
    check("and in the policy model", getattr(model, py_name), value)

ids = [define("BENCH_CMD_" + s)
       for s in ("GENERATE", "SIGN", "EXPORT_ONCE", "STATUS")]
check("the four command ids are distinct", len(set(ids)), 4)

# ------------------------------------------------------------- lengths

check("MAC_LEN agrees with the binding", benchkey.MAC_LEN,
      define("BENCH_MAC_LEN"))
check("KEY_LEN agrees with the binding", benchkey.KEY_LEN,
      define("BENCH_KEY_LEN"))
check("MAC_LEN agrees with the model", model.MAC_LEN,
      define("BENCH_MAC_LEN"))

match = re.search(r"#define\s+BENCH_KEY_BITS\s+\(BENCH_KEY_LEN\s*\*\s*8\)",
                  header)
check("KEY_BITS is derived from KEY_LEN rather than written twice",
      match is not None, True)

# --------------------------------------------------- object names


def string_define(name):
    match = re.search(r'^#define\s+%s\s+"([^"]+)"' % name, header, re.M)
    return match.group(1) if match else None


check("the key object name agrees with the model",
      model.OBJ_KEY, string_define("BENCH_OBJ_KEY"))
check("the lock object name agrees with the model",
      model.OBJ_LOCK, string_define("BENCH_OBJ_LOCK"))

# ------------------------------------------------ the socket and events

check("the LED socket path is the same in C and Python",
      benchkey.LED_SOCKET,
      re.search(r'#define\s+BENCHKEY_LED_SOCKET\s+"([^"]+)"',
                read(src, "benchkey.h")).group(1))

bench_h = read(src, "benchkey.h")
for name, value in (("BENCHKEY_EVENT_SIGNED", benchkey.EVENT_SIGNED),
                    ("BENCHKEY_EVENT_ERROR", benchkey.EVENT_ERROR)):
    match = re.search(r"#define\s+%s\s+'(.)'" % name, bench_h)
    check("%s is the same byte in C and Python" % name,
          match.group(1).encode("ascii"), value)

# The LED daemon has to understand every event anyone sends it. It is a
# third restatement, and the one where a typo means an LED that never
# lights rather than an error anybody sees.
leds = read(src, "benchkey-leds")
for value in (benchkey.EVENT_SIGNED, benchkey.EVENT_ERROR):
    literal = 'b"%s"' % value.decode("ascii")
    check("the LED daemon handles %s" % literal, literal in leds, True)

print()
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTHON
