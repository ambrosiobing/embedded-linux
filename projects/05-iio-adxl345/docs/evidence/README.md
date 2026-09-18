# Evidence, Project 5

Empty on purpose.

Every acceptance criterion in this project's README that is marked "Not
started" needs either a kernel tree or a board, and this project has had
neither. Nothing has been compiled, nothing has probed, and no reading has
been taken.

What goes here when that changes, in the order the criteria are numbered:

- the build log showing three `.ko` produced, for criterion 1
- `dmesg` from a probe that found `DEVID` 0xe5, and from one that did not,
  for criterion 2
- the four sysfs reads with the board flat, for criterion 3
- a capture decoded by `iio-decode`, for criterion 5
- `iio_event_monitor` output while the board is tapped, for criterion 6
- two `iio-rate` runs on the same board, one per driver, for criterion 7
- `./go ksym -f adxl345` and `./go kconfig -f adxl345`, for criterion 8

A directory with a file explaining why it is empty is more honest than an
absent directory, which reads as an oversight.
