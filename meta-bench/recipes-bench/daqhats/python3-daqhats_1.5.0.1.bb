SUMMARY = "Python bindings for the MCC DAQ HAT library"
DESCRIPTION = "A ctypes wrapper over libdaqhats. Pure Python: the module \
loads the shared library at import time and calls into it, so there is no \
extension to compile and nothing architecture-specific in this package \
beyond its dependency on the library."
HOMEPAGE = "https://github.com/mccdaq/daqhats"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=14d452bb31a1ae3c2fb70163065ffbc8"

SRC_URI = "git://github.com/mccdaq/daqhats.git;protocol=https;branch=master"
SRCREV = "dc66583068372d95c87261eec8c6f9c2fd3c78bd"

S = "${WORKDIR}/git"

inherit setuptools3

# A separate recipe rather than a second package inside libdaqhats. The two
# halves are built by different mechanisms, a makefile and setup.py, and
# putting both in one recipe means one of them fights the class that
# provides do_compile. They share the SRCREV, which is the thing that
# actually has to stay in step.

# ctypes is the whole mechanism: daqhats/hats.py does cdll.LoadLibrary and
# every call is a ctypes call. The OE python3 split puts ctypes in its own
# package, so leaving it implicit gives an image that boots and an import
# that fails, which is the failure this repository has already paid for
# once with kernel modules.
RDEPENDS:${PN} += "\
    libdaqhats \
    python3-core \
    python3-ctypes \
"

# numpy is deliberately absent from that list. mcc118.py imports it inside
# a_in_scan_read_numpy and nowhere else, so the ordinary read path works
# without it and forcing 30 MB on every user of this package would be
# wrong. bench-rt-image installs numpy because the capture script chooses
# the numpy path; that is the image's decision, recorded there.
#
# Worth knowing before sizing anything: that path allocates float64, so a
# 60 s scan at 100 kS/s is 48 MB in flight. rt-capture casts to float32 on
# the way to disk, which is where the 24 MB figure comes from.
