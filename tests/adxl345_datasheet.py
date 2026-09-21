"""The ADXL345 register map, transcribed from the datasheet.

WHY THIS FILE EXISTS, AND IT IS NOT DUPLICATION

tests/fake_platform.c uses the same register numbers as src/adxl.c, so
the whole fake-bus suite passes whether those numbers are right or not.
Change REG_POWER_CTL from 0x2d to 0x2c and every assertion still holds:
the library writes to 0x2c, the fake stores at 0x2c, the test reads back
0x2c and agrees with itself. The part would never come out of standby and
nothing in the suite would notice.

So this file is a SECOND, INDEPENDENT source for the same facts, written
from the datasheet rather than from the code. The test compares the two.
When they disagree, one of them is wrong and a human has to decide which,
which is the whole value: a single source cannot be checked against
anything.

Transcribed on Monday 21 September 2026 from the ADXL345 datasheet,
Analog Devices, register map and the output data rate table. Nothing here
was copied from src/adxl.c; that is the point, and a reader who updates
one of the two files without the other has defeated the exercise.

SPDX-License-Identifier: MIT
"""

# Register addresses, datasheet Table 19. This is the whole map the
# library has any business with, including one it deliberately does not
# use; REQUIRED below says which it must name.
REGISTERS = {
    "DEVID": 0x00,
    "BW_RATE": 0x2C,
    "POWER_CTL": 0x2D,
    "INT_ENABLE": 0x2E,
    "INT_MAP": 0x2F,
    "INT_SOURCE": 0x30,
    "DATA_FORMAT": 0x31,
    "DATAX0": 0x32,
    "FIFO_CTL": 0x38,
    "FIFO_STATUS": 0x39,
}

# The registers the library MUST name to do its job. INT_SOURCE is in
# the map above and deliberately not here: see the note in src/adxl.c.
# Comparing against the full map instead would make "the library does not
# use this register" look like a defect, which is how a linter teaches
# people to add things they do not need.
REQUIRED = ("DEVID", "BW_RATE", "POWER_CTL", "INT_ENABLE", "INT_MAP",
            "DATA_FORMAT", "DATAX0", "FIFO_CTL", "FIFO_STATUS")

# The fixed value DEVID always reads. It is the only way to tell this part
# from anything else that answers at the same address.
DEVID_VALUE = 0xE5

# POWER_CTL bit 3. Clear is standby, set is measuring.
POWER_CTL_MEASURE = 0x08

# DATA_FORMAT bit 3. Set means the scale stays 3.9 mg per count at every
# range and only the clipping point moves.
DATA_FORMAT_FULL_RES = 0x08

# DATA_FORMAT bits 1:0, the measurement range.
RANGE_BITS = {2: 0x00, 4: 0x01, 8: 0x02, 16: 0x03}

# BW_RATE bits 3:0, the output data rate. Datasheet Table 7. The codes are
# NOT a simple function of the frequency, which is exactly why a
# transcription is worth having: an arithmetic shortcut would be wrong.
RATE_CODES = {
    12: 0x07,     # 12.5 Hz, the datasheet's 0111
    25: 0x08,
    50: 0x09,
    100: 0x0A,
    200: 0x0B,
    400: 0x0C,
    800: 0x0D,
    1600: 0x0E,
    3200: 0x0F,
}

# INT_ENABLE and INT_SOURCE bit 1, the watermark.
INT_WATERMARK = 0x02

# FIFO_CTL bits 7:6. Stream is 10, bypass is 00.
FIFO_CTL_STREAM = 0x80
FIFO_CTL_BYPASS = 0x00

# FIFO_STATUS bits 5:0, the number of entries held. Six bits, so the
# mask is 0x3f even though the FIFO is only 32 deep.
FIFO_STATUS_ENTRIES = 0x3F
FIFO_DEPTH = 32

# One FIFO entry: X, Y, Z as little-endian signed 16-bit.
ENTRY_BYTES = 6

# The two addresses the SDO strap selects.
ADDRESSES = (0x53, 0x1D)

# Scale with FULL_RES set, in milli-g per count.
MILLI_G_PER_COUNT = 3.9
