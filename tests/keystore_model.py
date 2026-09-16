"""A model of the keystore TA, written from its documented rules.

Not a copy of bench_keystore_ta.c. This is a second implementation of the
same four commands, written from the comments in that file and from the
parameter table in bench_keystore_ta.h, so that the two are independent
statements of one policy and a test can compare them.

What it models: persistent objects that survive a reboot, the four
commands, their parameter types, and the five error results those rules
can produce. What it does not model: cryptography, the SMC path, the
supplicant, or anything about the secure world being secure. The HMAC
here is Python's, and the point is never the number that comes out, it is
which command refused and why.

The error values are from lib/libutee/include/tee_api_defines.h in
optee_os 4.1.0, read rather than recalled. ACCESS_CONFLICT is 0xFFFF0003
and 0xFFFF000C is OUT_OF_MEMORY; getting those two the wrong way round
was a real defect in the CLI's error table, found by writing this file.

SPDX-License-Identifier: MIT
"""

import hashlib
import hmac

TEE_SUCCESS = 0x00000000
TEE_ERROR_ACCESS_DENIED = 0xFFFF0001
TEE_ERROR_ACCESS_CONFLICT = 0xFFFF0003
TEE_ERROR_BAD_PARAMETERS = 0xFFFF0006
TEE_ERROR_ITEM_NOT_FOUND = 0xFFFF0008
TEE_ERROR_NOT_SUPPORTED = 0xFFFF000A
TEE_ERROR_OUT_OF_MEMORY = 0xFFFF000C
TEE_ERROR_SHORT_BUFFER = 0xFFFF0010

CMD_GENERATE = 0
CMD_SIGN = 1
CMD_EXPORT_ONCE = 2
CMD_STATUS = 3

MAC_LEN = 32
KEY_LEN = 32

OBJ_KEY = "bench.hmac-key"
OBJ_LOCK = "bench.export-lock"

# Parameter type tuples, in the order the TA checks them. The model
# compares these by equality exactly as TEE_PARAM_TYPES does, because the
# real failure is a client and a TA that disagree by one slot.
NONE = "none"
MEMREF_IN = "memref-in"
MEMREF_OUT = "memref-out"
VALUE_OUT = "value-out"

EXPECTED_TYPES = {
    CMD_GENERATE: (NONE, NONE, NONE, NONE),
    CMD_SIGN: (MEMREF_IN, MEMREF_OUT, NONE, NONE),
    CMD_EXPORT_ONCE: (MEMREF_OUT, NONE, NONE, NONE),
    CMD_STATUS: (VALUE_OUT, NONE, NONE, NONE),
}


class SecureStorage:
    """Persistent objects. A dict that survives a reboot and not a wipe."""

    def __init__(self):
        self.objects = {}

    def exists(self, name):
        return name in self.objects

    def write(self, name, value):
        self.objects[name] = value

    def read(self, name):
        return self.objects[name]

    def wipe(self):
        """What deleting /var/lib/tee does. There is no recovery."""
        self.objects = {}


class KeystoreTA:
    def __init__(self, storage=None, rng=None):
        self.storage = storage if storage is not None else SecureStorage()
        # A deterministic key generator, so a test can assert that two
        # generates on two devices differ without depending on entropy.
        self._rng = rng or (lambda n: bytes(range(n)))

    def invoke(self, cmd, types=None, msg=b"", out_len=MAC_LEN):
        """One command. Returns (result, value) as the client would see it."""
        if cmd not in EXPECTED_TYPES:
            return TEE_ERROR_NOT_SUPPORTED, None
        if types is not None and types != EXPECTED_TYPES[cmd]:
            return TEE_ERROR_BAD_PARAMETERS, None

        if cmd == CMD_GENERATE:
            return self._generate()
        if cmd == CMD_SIGN:
            return self._sign(msg, out_len)
        if cmd == CMD_EXPORT_ONCE:
            return self._export_once(out_len)
        return self._status()

    # Never overwrite a key: a second provisioning run must not silently
    # invalidate every record the first one's key already signed.
    def _generate(self):
        if self.storage.exists(OBJ_KEY):
            return TEE_ERROR_ACCESS_CONFLICT, None
        self.storage.write(OBJ_KEY, self._rng(KEY_LEN))
        return TEE_SUCCESS, None

    def _sign(self, msg, out_len):
        if out_len < MAC_LEN:
            return TEE_ERROR_SHORT_BUFFER, MAC_LEN
        if not self.storage.exists(OBJ_KEY):
            return TEE_ERROR_ITEM_NOT_FOUND, None
        key = self.storage.read(OBJ_KEY)
        return TEE_SUCCESS, hmac.new(key, msg, hashlib.sha256).digest()

    # The lock is checked first and written last. The other order loses
    # the key on any failure in between: locked, with nothing exported,
    # and the only way out is a wipe that invalidates everything signed
    # so far.
    def _export_once(self, out_len):
        if self.storage.exists(OBJ_LOCK):
            return TEE_ERROR_ACCESS_DENIED, None
        if out_len < KEY_LEN:
            return TEE_ERROR_SHORT_BUFFER, KEY_LEN
        if not self.storage.exists(OBJ_KEY):
            return TEE_ERROR_ITEM_NOT_FOUND, None
        key = self.storage.read(OBJ_KEY)
        self.storage.write(OBJ_LOCK, b"\x01")
        return TEE_SUCCESS, key

    def _status(self):
        return TEE_SUCCESS, (self.storage.exists(OBJ_KEY),
                             self.storage.exists(OBJ_LOCK))


def reboot(ta):
    """A new TA instance against the same storage.

    The TA holds no state between sessions by design, so a reboot is
    modelled as throwing the instance away and keeping the objects. If
    this function ever needed to carry something across, that would be
    the finding.
    """
    return KeystoreTA(storage=ta.storage, rng=ta._rng)
