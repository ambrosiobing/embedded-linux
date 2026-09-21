"""ctypes bindings for libadxl345.

Twenty lines of binding for a whole driver, and that is the argument for
the API's shape rather than a happy accident. Because adxl.h passes
integers in and plain arrays out, there is no structure to redeclare here:
nothing in this file has to be kept in step with a C struct layout, so a
change to the library's internals cannot break it silently.

The one thing that IS pinned is the soname. CDLL("libadxl345.so.1") asks
for the ABI this file was written against; if the library ever bumps to
.so.2 this import fails loudly at start-up rather than crashing later in a
call with a changed signature.

SPDX-License-Identifier: MIT
"""

import ctypes as C

AXES = 3
FIFO_DEPTH = 32

OK = 0
EIO = -1
EWHO = -2
EPARAM = -3
ETIMEOUT = -4

_lib = C.CDLL("libadxl345.so.1")

_lib.adxl_version.argtypes = [C.POINTER(C.c_int)] * 3
_lib.adxl_version.restype = C.c_int
_lib.adxl_open.argtypes = [C.POINTER(C.c_void_p), C.c_char_p, C.c_int,
                           C.c_int]
_lib.adxl_open.restype = C.c_int
_lib.adxl_start.argtypes = [C.c_void_p, C.c_int, C.c_int]
_lib.adxl_start.restype = C.c_int
_lib.adxl_read.argtypes = [C.c_void_p, C.c_void_p, C.c_int, C.c_int]
_lib.adxl_read.restype = C.c_int
_lib.adxl_stop.argtypes = [C.c_void_p]
_lib.adxl_stop.restype = C.c_int
_lib.adxl_close.argtypes = [C.c_void_p]
_lib.adxl_close.restype = None

# FULL_RES is always on in the library, so the scale is fixed at every
# range and a stored sample does not have to carry the range it was taken
# at to be interpretable.
MILLI_G_PER_COUNT = 3.9


def version():
    """(major, minor, patch) of the library actually loaded."""
    a, b, c = C.c_int(), C.c_int(), C.c_int()
    _lib.adxl_version(C.byref(a), C.byref(b), C.byref(c))
    return a.value, b.value, c.value


class Error(OSError):
    """A library call refused. The code is the ADXL_* value."""

    def __init__(self, code, what):
        self.code = code
        super().__init__("%s failed (%d)" % (what, code))


class Sensor:
    """One handle. One thread: the library allocates its transfer buffer
    per handle, so two Sensors are safe, but sharing one across threads
    is not."""

    def __init__(self, path=b"/dev/i2c-1", addr=0x53, int_gpio=-1):
        self._h = C.c_void_p()
        rc = _lib.adxl_open(C.byref(self._h), path, addr, int_gpio)
        if rc != OK:
            # EWHO is worth naming, because the cause is almost always
            # the other strap address rather than a broken sensor.
            if rc == EWHO:
                raise Error(rc, "open: something answered at 0x%02x and it "
                                "is not an ADXL345; try 0x%02x"
                                % (addr, 0x1D if addr == 0x53 else 0x53))
            raise Error(rc, "open")

    def start(self, range_g=2, rate_hz=100):
        rc = _lib.adxl_start(self._h, range_g, rate_hz)
        if rc != OK:
            raise Error(rc, "start")

    def read(self, max_samples=FIFO_DEPTH, timeout_ms=200):
        """A list of (x, y, z) in raw counts, or [] on timeout.

        Returns what arrived rather than what was asked for, because the
        FIFO delivers a burst and a caller that assumed max_samples would
        read stale values off the end of its own buffer.
        """
        buf = ((C.c_int16 * AXES) * max_samples)()
        rc = _lib.adxl_read(self._h, C.byref(buf), max_samples, timeout_ms)
        if rc == ETIMEOUT:
            return []
        if rc < 0:
            raise Error(rc, "read")
        return [(buf[i][0], buf[i][1], buf[i][2]) for i in range(rc)]

    def stop(self):
        _lib.adxl_stop(self._h)

    def close(self):
        _lib.adxl_close(self._h)
        self._h = C.c_void_p()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False


def milli_g(sample):
    """One (x, y, z) of raw counts as milli-g."""
    return tuple(round(v * MILLI_G_PER_COUNT, 1) for v in sample)
