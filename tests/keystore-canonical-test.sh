#!/bin/sh
#
# keystore-canonical-test.sh - the contract between the signer and the
# verifier, which are two programs on two machines.
#
# A signature is only meaningful if both sides turn a record into exactly
# the same bytes. They are written at different times, run on different
# hardware and share nothing but a function, so the function is the
# contract and this file is what holds it.
#
# The case that matters most is the one that was wrong first. The signing
# side was written as
#
#     json.dumps(rec, sort_keys=True)
#
# and the verifying side as
#
#     json.dumps(rec, sort_keys=True, separators=(",", ":"))
#
# which differ by two spaces per field. Every record would have verified
# as BAD, with nothing anywhere to say why: the data is intact, the key is
# right, the HMAC is correct, and the two sides hashed different bytes.
# The first assertion below is that difference, kept as a test so that the
# two spellings can never quietly come back.
#
#   sh tests/keystore-canonical-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/bench-keystore/files
PYTHON=${PYTHON:-python3}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp "$SRC/benchkey.py" "$SRC/benchkey-verify" "$WORK/"

cat >"$WORK/run.py" <<'PYTHON'
import hashlib
import hmac
import json
import os
import subprocess
import sys

sys.path.insert(0, sys.argv[1])
work = sys.argv[1]

from benchkey import canonical

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


KEY = bytes.fromhex(
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
RECORD = {"host_ts": 1789000000.5, "acc": [1.0, -2.0, 3.0],
          "mask": "00e00000", "mac_addr": "C0:11:22:33:44:55"}


def sign(record, key=KEY):
    """What the TA does, in Python. The bytes are what matters here."""
    return hmac.new(key, canonical(record), hashlib.sha256).hexdigest()


# --------------------------------------- the two spellings, side by side

loose = json.dumps({k: v for k, v in RECORD.items() if k != "mac"},
                   sort_keys=True).encode()
check("the default separators are not the canonical ones",
      loose == canonical(RECORD), False)
check("and the canonical form is the one without spaces",
      canonical(RECORD).decode("ascii").startswith('{"acc":['), True)
check("the loose form is what would have been signed",
      loose.decode("ascii").startswith('{"acc": ['), True)

# --------------------------------------------------- the five rules

check("key order does not matter",
      canonical({"b": 2, "a": 1}), canonical({"a": 1, "b": 2}))
check("and the output is sorted", canonical({"b": 2, "a": 1}),
      b'{"a":1,"b":2}')

signed = dict(RECORD)
signed["mac"] = "ab" * 32
check("the mac field is dropped before signing",
      canonical(signed), canonical(RECORD))

# The character below is written as a Python escape so that this file
# stays ASCII, which scripts/lint.py enforces on every shell file. That is
# not a workaround around the test: it is the same discipline the test is
# checking, which is that a byte outside ASCII must never be allowed to
# depend on how a file was saved or which locale read it.
check("non-ASCII is escaped, so the signed bytes are pure ASCII",
      canonical({"name": "B\u00fclach"}), b'{"name":"B\\u00fclach"}')

for bad in (float("nan"), float("inf")):
    try:
        canonical({"v": bad})
    except ValueError:
        print("ok       %r is refused rather than signed" % bad)
        passed += 1
    else:
        print("FAILED   %r was serialised" % bad)
        failed += 1

# ------------------------------------------------------- the round trip

mac = sign(RECORD)
record = dict(RECORD)
record["mac"] = mac

key_path = os.path.join(work, "device.key")
with open(key_path, "w", encoding="ascii") as handle:
    handle.write(KEY.hex() + "\n")


def verify(records):
    """Run benchkey-verify over a list of records, return (rc, stdout)."""
    lines = "\n".join(json.dumps(r) for r in records) + "\n"
    proc = subprocess.run(
        [sys.executable, os.path.join(work, "benchkey-verify"),
         "--key", key_path],
        input=lines, capture_output=True, text=True,
        env=dict(os.environ, PYTHONPATH=work))
    return proc.returncode, proc.stdout


rc, out = verify([record])
check("a signed record verifies", "OK " in out, True)
check("and the exit code is 0", rc, 0)

# One byte changed anywhere in the record.
tampered = dict(record)
tampered["acc"] = [1.0, -2.0, 3.5]
rc, out = verify([tampered])
check("a tampered record is BAD", "BAD" in out, True)
check("and the exit code says so", rc, 1)

# The signature itself changed.
forged = dict(record)
forged["mac"] = ("0" * 63) + "1"
rc, out = verify([forged])
check("a forged mac is BAD", "BAD" in out, True)

# Structurally wrong macs, which a stream from a broker will contain
# sooner or later.
rc, out = verify([{"a": 1}])
check("a record with no mac is reported, not crashed on",
      "---" in out, True)
check("and that alone is not a failure", rc, 0)

rc, out = verify([dict(record, mac="not hex")])
check("a mac that is not hex is BAD", "BAD" in out, True)
rc, out = verify([dict(record, mac="abcd")])
check("a mac of the wrong length is BAD", "BAD" in out, True)

# A record signed by a different device.
other = hmac.new(bytes(32), canonical(RECORD), hashlib.sha256).hexdigest()
rc, out = verify([dict(RECORD, mac=other)])
check("another device's key does not verify", "BAD" in out, True)

# A whole stream, which is how it is really used.
rc, out = verify([record, tampered, record])
check("a stream reports each record", out.count("OK ") == 2, True)
check("and counts them", "2 ok, 1 bad" in out, True)

# ------------------------------------------- the signer side, end to end


class FakeTee:
    """Stands in for the TA: HMAC with a key it will not hand over."""

    def __init__(self, key):
        self.key = key
        self.calls = 0

    def sign(self, data):
        self.calls += 1
        return hmac.new(self.key, data, hashlib.sha256).digest()


def sign_record(tee, record):
    """The body of BenchKey.sign_record, without the ctypes layer."""
    out = dict(record)
    out["mac"] = tee.sign(canonical(record)).hex()
    return out


tee = FakeTee(KEY)
produced = sign_record(tee, RECORD)
check("the signer produces a verifiable record",
      verify([produced])[0], 0)
check("and does not modify the record it was given",
      "mac" in RECORD, False)

# Signing a record that already carries a mac must produce the same
# signature, because canonical() drops the field on both sides. Without
# that rule, re-publishing a record would invalidate it.
again = sign_record(tee, produced)
check("re-signing a signed record gives the same mac",
      again["mac"], produced["mac"])
check("the fake TA was called once per signature", tee.calls, 2)

print()
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTHON

"$PYTHON" -u "$WORK/run.py" "$WORK"
