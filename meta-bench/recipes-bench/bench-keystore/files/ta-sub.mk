# What the dev kit compiles, and where it looks for headers.
#
# global-incdirs-y adds the directory to the include path of every source
# in this TA. The shared header lives beside the source rather than in an
# include/ subdirectory because there is one of each and a directory with
# one file in it is a directory somebody has to open to find out.
global-incdirs-y += .
srcs-y += bench_keystore_ta.c
