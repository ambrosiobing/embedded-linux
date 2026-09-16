#!/bin/sh
#
# keystore-policy-test.sh - the four commands and the rules between them,
# without a secure world.
#
# The trusted application cannot be compiled here: it needs the OP-TEE
# development kit, which needs a cross toolchain and an optee-os build.
# What can be checked is its *policy*, which is the part with the rules
# in it, and which is the part that would be wrong.
#
# tests/keystore_model.py is a second implementation of those rules,
# written from the comments in bench_keystore_ta.c and the parameter
# table in bench_keystore_ta.h rather than from the C. This file drives
# it through the sequences a device actually goes through: provisioning,
# a reboot, a second provisioning attempt, and the two ways a person
# destroys a key.
#
# What is proven: that the rules are consistent and that the provisioning
# procedure in docs/BRINGUP.md ends in the state it claims.
#
# What is not proven: that bench_keystore_ta.c implements these rules.
# Only a board can show that, and the acceptance table says so.
#
#   sh tests/keystore-policy-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=${PYTHON:-python3}

"$PYTHON" -u - "$ROOT/tests" <<'PYTHON'
import sys

sys.path.insert(0, sys.argv[1])

from keystore_model import (CMD_EXPORT_ONCE, CMD_GENERATE, CMD_SIGN,
                            CMD_STATUS, EXPECTED_TYPES, KEY_LEN, MAC_LEN,
                            MEMREF_IN, MEMREF_OUT, NONE, TEE_SUCCESS,
                            TEE_ERROR_ACCESS_CONFLICT, TEE_ERROR_ACCESS_DENIED,
                            TEE_ERROR_BAD_PARAMETERS, TEE_ERROR_ITEM_NOT_FOUND,
                            TEE_ERROR_NOT_SUPPORTED, TEE_ERROR_SHORT_BUFFER,
                            VALUE_OUT, KeystoreTA, reboot)

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


def hexname(result):
    return "0x%08x" % result


# -------------------------------------------- a device out of the box

ta = KeystoreTA()

res, value = ta.invoke(CMD_STATUS, EXPECTED_TYPES[CMD_STATUS])
check("a fresh device reports no key", (res, value), (TEE_SUCCESS,
                                                      (False, False)))

res, _ = ta.invoke(CMD_SIGN, EXPECTED_TYPES[CMD_SIGN], msg=b"hello")
check("signing without a key is ITEM_NOT_FOUND", hexname(res),
      hexname(TEE_ERROR_ITEM_NOT_FOUND))

res, _ = ta.invoke(CMD_EXPORT_ONCE, EXPECTED_TYPES[CMD_EXPORT_ONCE],
                   out_len=KEY_LEN)
check("exporting without a key is ITEM_NOT_FOUND too", hexname(res),
      hexname(TEE_ERROR_ITEM_NOT_FOUND))

# --------------------------------------------------------- provisioning

res, _ = ta.invoke(CMD_GENERATE, EXPECTED_TYPES[CMD_GENERATE])
check("generate succeeds once", hexname(res), hexname(TEE_SUCCESS))

res, value = ta.invoke(CMD_STATUS, EXPECTED_TYPES[CMD_STATUS])
check("and the device now has a key, unlocked", value, (True, False))

res, _ = ta.invoke(CMD_GENERATE, EXPECTED_TYPES[CMD_GENERATE])
check("a second generate is refused, not silently obeyed", hexname(res),
      hexname(TEE_ERROR_ACCESS_CONFLICT))

res, first = ta.invoke(CMD_SIGN, EXPECTED_TYPES[CMD_SIGN], msg=b"hello")
check("signing works", hexname(res), hexname(TEE_SUCCESS))
check("and produces 32 bytes", len(first), MAC_LEN)

res, exported = ta.invoke(CMD_EXPORT_ONCE, EXPECTED_TYPES[CMD_EXPORT_ONCE],
                          out_len=KEY_LEN)
check("export-once works once", hexname(res), hexname(TEE_SUCCESS))
check("and returns the key", len(exported), KEY_LEN)

res, _ = ta.invoke(CMD_EXPORT_ONCE, EXPECTED_TYPES[CMD_EXPORT_ONCE],
                   out_len=KEY_LEN)
check("a second export is ACCESS_DENIED", hexname(res),
      hexname(TEE_ERROR_ACCESS_DENIED))

res, value = ta.invoke(CMD_STATUS, EXPECTED_TYPES[CMD_STATUS])
check("status now reports key and locked", value, (True, True))

# ------------------------------------------------------------- a reboot

ta = reboot(ta)

res, value = ta.invoke(CMD_STATUS, EXPECTED_TYPES[CMD_STATUS])
check("the key survives a reboot", value, (True, True))

res, again = ta.invoke(CMD_SIGN, EXPECTED_TYPES[CMD_SIGN], msg=b"hello")
check("and signs the same input to the same bytes", again, first)

res, _ = ta.invoke(CMD_EXPORT_ONCE, EXPECTED_TYPES[CMD_EXPORT_ONCE],
                   out_len=KEY_LEN)
check("the lock survives the reboot too", hexname(res),
      hexname(TEE_ERROR_ACCESS_DENIED))

res, _ = ta.invoke(CMD_GENERATE, EXPECTED_TYPES[CMD_GENERATE])
check("and so does the refusal to regenerate", hexname(res),
      hexname(TEE_ERROR_ACCESS_CONFLICT))

# ------------------------------------------- the two ways to lose a key

# Deleting /var/lib/tee. There is no recovery, and the point of asserting
# it is that the device comes back looking brand new: no key, not locked,
# and happy to generate a different one that no verifier knows.
wiped = KeystoreTA()
wiped.storage.objects = dict(ta.storage.objects)
wiped.storage.wipe()
res, value = wiped.invoke(CMD_STATUS, EXPECTED_TYPES[CMD_STATUS])
check("wiping storage leaves a device that looks new", value, (False, False))
res, _ = wiped.invoke(CMD_GENERATE, EXPECTED_TYPES[CMD_GENERATE])
check("and it will happily make a key nobody can verify", hexname(res),
      hexname(TEE_SUCCESS))

# The other way: a device that was locked before it was exported. The TA
# writes the lock after the key has been handed out precisely so that
# this cannot happen, and the model says what it would mean if it did.
stuck = KeystoreTA()
stuck.invoke(CMD_GENERATE, EXPECTED_TYPES[CMD_GENERATE])
stuck.storage.write("bench.export-lock", b"\x01")
res, _ = stuck.invoke(CMD_EXPORT_ONCE, EXPECTED_TYPES[CMD_EXPORT_ONCE],
                      out_len=KEY_LEN)
check("a lock written before an export strands the key", hexname(res),
      hexname(TEE_ERROR_ACCESS_DENIED))
res, value = stuck.invoke(CMD_STATUS, EXPECTED_TYPES[CMD_STATUS])
check("and status is the only way to see it: key yes, locked yes", value,
      (True, True))
res, _ = stuck.invoke(CMD_SIGN, EXPECTED_TYPES[CMD_SIGN], msg=b"x")
check("such a device still signs, and nothing can check it", hexname(res),
      hexname(TEE_SUCCESS))

# --------------------------------------------------- parameter contracts

ta2 = KeystoreTA()
ta2.invoke(CMD_GENERATE, EXPECTED_TYPES[CMD_GENERATE])

res, _ = ta2.invoke(CMD_SIGN, (MEMREF_IN, MEMREF_IN, NONE, NONE), msg=b"x")
check("an output slot declared as input is BAD_PARAMETERS", hexname(res),
      hexname(TEE_ERROR_BAD_PARAMETERS))

res, _ = ta2.invoke(CMD_SIGN, (MEMREF_IN, MEMREF_OUT, MEMREF_IN, NONE),
                    msg=b"x")
check("so is an extra parameter nobody asked for", hexname(res),
      hexname(TEE_ERROR_BAD_PARAMETERS))

res, _ = ta2.invoke(CMD_STATUS, (MEMREF_OUT, NONE, NONE, NONE))
check("status with a memref instead of a value is refused", hexname(res),
      hexname(TEE_ERROR_BAD_PARAMETERS))

res, need = ta2.invoke(CMD_SIGN, EXPECTED_TYPES[CMD_SIGN], msg=b"x",
                       out_len=8)
check("a short output buffer is SHORT_BUFFER", hexname(res),
      hexname(TEE_ERROR_SHORT_BUFFER))
check("and the caller is told how much it needs", need, MAC_LEN)

res, _ = ta2.invoke(99, (NONE, NONE, NONE, NONE))
check("an unknown command is NOT_SUPPORTED", hexname(res),
      hexname(TEE_ERROR_NOT_SUPPORTED))

# Every command's expected types are distinct, so a client that sends the
# wrong command's layout is caught rather than being accidentally valid.
layouts = list(EXPECTED_TYPES.values())
check("no two commands share a parameter layout",
      len(set(layouts)), len(layouts))

# ------------------------------------------- two devices, two keys

a, b = KeystoreTA(), KeystoreTA(rng=lambda n: bytes([0xAA] * n))
a.invoke(CMD_GENERATE, EXPECTED_TYPES[CMD_GENERATE])
b.invoke(CMD_GENERATE, EXPECTED_TYPES[CMD_GENERATE])
_, mac_a = a.invoke(CMD_SIGN, EXPECTED_TYPES[CMD_SIGN], msg=b"same input")
_, mac_b = b.invoke(CMD_SIGN, EXPECTED_TYPES[CMD_SIGN], msg=b"same input")
check("two devices sign the same input differently", mac_a != mac_b, True)

print()
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTHON
