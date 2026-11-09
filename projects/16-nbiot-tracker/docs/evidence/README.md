# Evidence, Project 16

**One file, and it is not about the modem.** This directory said "empty on
purpose, on Monday 21 September 2026" until the image was built.

- [build-2026-11-09.txt](build-2026-11-09.txt), the first build of
  `bench-tracker-image`, Monday 9 November 2026, 3 min 55 s at a 94 percent
  sstate match. It proves **no criterion**: none of the eleven is "the image
  builds". Its own `Proves:` line says so, and its last section says what it
  is not evidence about.

Nothing has been powered. No modem has attached, no PSM value has been
granted, and no current has been measured. The acceptance table in this
project's README marks every criterion accordingly.

What goes here, in the order the criteria are numbered:

- `lsusb` and `dmesg` from the first power-on, which is what decides the
  kernel fragment. Until that exists the fragment is not written.
- the three facts the schematic is waiting for: the HAT's logic-voltage
  jumper setting, the header pins its jumpers occupy, and where the modem's
  supply rail can be separated for the PPK2.
- the AT transcript of a first attach, whole, including the failures.
- `AT+CPSMS?` and the `+CEREG` URC showing the values the network granted,
  which are not the values requested.
- the PPK2 trace of one report cycle, with the report marker on a logic
  channel, and the charge integrated over it.
- the same for eDRX, and the same for the SIM7020E, which is the second
  modem and therefore the control.

A directory with a file explaining why it is empty is more honest than an
absent directory, which reads as an oversight.
