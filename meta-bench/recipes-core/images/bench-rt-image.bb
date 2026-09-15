SUMMARY = "Bench image with a real-time kernel and both latency instruments"
DESCRIPTION = "The bench image with PREEMPT_RT underneath it and the two \
instruments of Project 8 on top: cyclictest, which measures the kernel \
from inside the task being scheduled, and an MCC 118 DAQ HAT, which \
measures the same task from outside through a wire. stress-ng supplies the \
load, and the analysis runs on the board so that a run can be judged \
before the card is carried back to a desk."

require recipes-core/images/bench-image.bb

LICENSE = "MIT"

IMAGE_INSTALL:append = " \
    bench-rt \
    libdaqhats \
    libdaqhats-tools \
    python3-daqhats \
    python3-numpy \
    rt-tests \
    stress-ng \
    util-linux-taskset \
    kernel-module-spidev \
"

# rt-tests is cyclictest and its relatives. It is the reference instrument,
# and it is the one everybody else in the field quotes, which is exactly
# why this project does not stop there.
#
# util-linux-taskset is not optional decoration: every pitfall in this
# project is some process running where it was not supposed to. Without
# taskset the capture script and stress-ng land on whatever core the
# scheduler likes, and the isolated core stops being isolated without
# anything reporting an error.
#
# python3-numpy is 30 MB of image for an analysis that could be done on a
# laptop. It is here because the alternative is a 24 MB capture file per
# run, sixteen runs, and a feedback loop that goes through an SD card
# reader. Analysing on the board turns a bad row into a two-minute retry.

# The generic kernel is not in this image, and it cannot be: a Yocto image
# carries one kernel. The fallback the project needs is at the card level
# rather than the image level, which is what scripts/rt-kernel-install.sh
# does: it copies this image's kernel onto a card that already boots the
# generic one, under a second name, and switches config.txt. A boot failure
# then costs one line edited on the FAT partition from any laptop.

# Room for the capture files, the histograms and the results of a full
# matrix. A 60 s capture at 100 kS/s is 24 MB as float32, and the scratch
# copy lives in /dev/shm rather than here, but the histograms and the CSV
# stay on the card between reboots because rebooting is part of the method.
IMAGE_ROOTFS_EXTRA_SPACE = "524288"
