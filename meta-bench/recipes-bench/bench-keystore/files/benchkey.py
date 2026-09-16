"""benchkey: sign a record inside the TEE, from Python.

Two things live here, and only one of them needs a board.

`canonical()` turns a record into the exact bytes that get signed. It is
pure, it is tested, and it is the single most important function in this
project, because the signer and the verifier are different programs on
different machines and a signature is only meaningful if both serialise
the record identically.

`BenchKey` is a ctypes wrapper over libbenchkey, and needs the TEE.

## The canonical form, and why each rule is there

    json.dumps(record_without_mac,
               sort_keys=True,
               separators=(",", ":"),
               ensure_ascii=True,
               allow_nan=False).encode("ascii")

| Rule | Without it |
|---|---|
| drop `mac` | the signer signs a record with no mac and the verifier one with a mac, so nothing ever verifies |
| `sort_keys=True` | two dicts with the same contents in a different insertion order sign differently |
| `separators=(",", ":")` | the default is `", "` and `": "`, with spaces, so a signer using the default and a verifier using this produce different bytes over identical data |
| `ensure_ascii=True` | a non-ASCII value could be encoded two ways, and the two sides would have to agree on which |
| `allow_nan=False` | Python writes `NaN` and `Infinity`, which are not JSON, so the record would be unverifiable by anything that is not Python. Better to fail while signing |

The third row is not hypothetical. The first version of this project took
the signer's line from one place and the verifier's from another, and they
differed by exactly those two spaces, which means every record would have
verified as BAD with nothing in the output to say why. There is now one
function, in one file, shipped to both sides, and a test that holds the
two together.

## What this does not solve

A verifier written in another language has to reproduce this byte for
byte, and the hard part is not the separators, it is the floats: Python
chooses the shortest representation that round-trips, and another language
may not. The way out is to keep floats out of signed records, or to sign
a byte string that was never a dict. Said here rather than discovered
later.

SPDX-License-Identifier: MIT
"""

import ctypes
import ctypes.util
import json

UUID = "7b53ed98-cbfb-42ec-92b6-fe56e7682c5c"

# Restated from bench_keystore_ta.h, because a ctypes binding cannot
# include a C header. tests/keystore-header-test.sh parses that header and
# checks these against it, which is the only thing keeping two copies of
# one number from drifting apart.
CMD_GENERATE = 0
CMD_SIGN = 1
CMD_EXPORT_ONCE = 2
CMD_STATUS = 3

MAC_LEN = 32
KEY_LEN = 32

LED_SOCKET = "/run/benchkey-leds.sock"
EVENT_SIGNED = b"S"
EVENT_ERROR = b"E"

# From benchkey.h.
OK = 0
ERR_NOT_OPEN = -1
ERR_TEE = -2
ERR_ARGS = -3


class BenchKeyError(RuntimeError):
    """A TEE failure, carrying the two numbers that identify it."""

    def __init__(self, what, result, origin, origin_name):
        super().__init__("%s failed: 0x%08x, origin %s"
                         % (what, result, origin_name))
        self.what = what
        self.result = result
        self.origin = origin
        self.origin_name = origin_name


def canonical(record):
    """The exact bytes that get signed. See the module docstring."""
    without_mac = {k: v for k, v in record.items() if k != "mac"}
    return json.dumps(without_mac,
                      sort_keys=True,
                      separators=(",", ":"),
                      ensure_ascii=True,
                      allow_nan=False).encode("ascii")


def notify(event):
    """Tell the LED daemon, best effort, never raising.

    A datagram to a path that may not exist. The failure modes are all
    immediate: no socket is ENOENT, a full queue is EAGAIN, and neither
    of them is a reason for a signature to fail.
    """
    import socket

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        sock.setblocking(False)
        try:
            sock.sendto(event, LED_SOCKET)
        finally:
            sock.close()
    except OSError:
        pass


class BenchKey:
    """One context, one session, held open for the life of the object."""

    def __init__(self, library=None):
        path = library or ctypes.util.find_library("benchkey") or \
            "libbenchkey.so.1"
        self.lib = ctypes.CDLL(path)
        self._declare()
        self.opened = False

    def _declare(self):
        lib = self.lib
        lib.benchkey_open.restype = ctypes.c_int
        lib.benchkey_close.restype = None
        lib.benchkey_generate.restype = ctypes.c_int
        lib.benchkey_last_result.restype = ctypes.c_uint32
        lib.benchkey_last_origin.restype = ctypes.c_uint32
        lib.benchkey_origin_name.restype = ctypes.c_char_p
        lib.benchkey_origin_name.argtypes = [ctypes.c_uint32]
        lib.benchkey_sign.restype = ctypes.c_int
        lib.benchkey_sign.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                      ctypes.c_void_p, ctypes.c_size_t]
        lib.benchkey_export_once.restype = ctypes.c_int
        lib.benchkey_export_once.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                             ctypes.POINTER(ctypes.c_size_t)]
        lib.benchkey_status.restype = ctypes.c_int
        lib.benchkey_status.argtypes = [ctypes.POINTER(ctypes.c_int),
                                        ctypes.POINTER(ctypes.c_int)]

    def _fail(self, what):
        result = self.lib.benchkey_last_result()
        origin = self.lib.benchkey_last_origin()
        name = self.lib.benchkey_origin_name(origin).decode("ascii")
        notify(EVENT_ERROR)
        raise BenchKeyError(what, result, origin, name)

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, *exc):
        self.close()

    def open(self):
        if self.opened:
            return
        if self.lib.benchkey_open() != OK:
            self._fail("open")
        self.opened = True

    def close(self):
        if self.opened:
            self.lib.benchkey_close()
            self.opened = False

    def generate(self):
        if self.lib.benchkey_generate() != OK:
            self._fail("generate")

    def sign(self, data):
        """HMAC-SHA256 of `data`, computed in the secure world."""
        mac = ctypes.create_string_buffer(MAC_LEN)
        if self.lib.benchkey_sign(data, len(data), mac, MAC_LEN) != OK:
            self._fail("sign")
        notify(EVENT_SIGNED)
        return mac.raw[:MAC_LEN]

    def export_once(self):
        buf = ctypes.create_string_buffer(KEY_LEN)
        out = ctypes.c_size_t(0)
        if self.lib.benchkey_export_once(buf, KEY_LEN,
                                         ctypes.byref(out)) != OK:
            self._fail("export-once")
        return buf.raw[:out.value]

    def status(self):
        has_key = ctypes.c_int(0)
        locked = ctypes.c_int(0)
        if self.lib.benchkey_status(ctypes.byref(has_key),
                                    ctypes.byref(locked)) != OK:
            self._fail("status")
        return {"key": bool(has_key.value), "locked": bool(locked.value)}

    def sign_record(self, record):
        """Return a copy of `record` with a "mac" field added.

        A copy, not the original. A sink that mutated the caller's record
        would leave a "mac" in it, and the next call would then sign a
        record that already carried one; canonical() drops it, so the
        signature would still verify, and the record would accumulate a
        field that was signed once and overwritten after. Copying is
        cheaper than reasoning about that every time.
        """
        signed = dict(record)
        signed["mac"] = self.sign(canonical(record)).hex()
        return signed
