# Measurement, Project 16

The project exists to produce one number: the charge a position report
costs, in millicoulombs, over a stated interval. Everything in this
directory serves that number, and the acceptance table in the project
README refuses to call it measured until a board has produced it.

## What is here on Monday 21 September 2026

| File | What | State |
|---|---|---|
| `budget.py` | Charge, duration, mean, peak and idle current from a capture, with the refusals that stop a dishonest number being printed | **written, 24 assertions passing** |
| the capture program | Records one report cycle from the PPK2 | **not written**, and blocked: see below |

`budget.py` reads the capture schema that
`projects/03-boot-energy/measure/ppk2_boot.py` already writes, which is
`t_s, i_ua, d0, d1, d2` at a fixed interval.
Reusing that schema rather than inventing one is why the arithmetic could
be written and tested before its own capture program exists, and it means a
capture taken by either project can be read by either tool.

It imports nothing outside the standard library, unlike Project 3's
`analyze.py`, which needs numpy. That is deliberate: the test suite then
runs on the Windows authoring laptop rather than only on the machine with
the scientific stack installed.

## Why the capture program is not written yet

It needs the marker GPIO offset, and that is one of the three facts still
to be read off the board. `docs/evidence/README.md` lists all three. A
capture program written against a guessed pin would drive whatever else is
on that pin, and the HAT's logic voltage is selectable between 5 V and
3.3 V by a 0-ohm resistor, so a wrong guess there is a destroyed input
rather than a wrong reading.

The arithmetic has no such dependency, so it was written first.

## The instrument, and the three limits it imposes

All three are quoted facts from elsewhere in this repository rather than
anything measured here.

**The PPK2 stops at 1 A.** Project 15 records this as "The PPK2 cannot
measure this, at 1 A maximum". Project 3 measured a 1233 mA peak, above
that rating, and had to withdraw the figure. A sample at the ceiling is not
a reading: the real current was higher by an unknown amount, so the charge
under it is an underestimate. `budget.py` therefore **refuses** a capture
with any sample at or above 99 percent of the ceiling, rather than printing
a total that looks fine. That refusal is acceptance criterion 7.

**Above 400 mA, source-meter mode needs the second micro-USB connector.**
Project 3 has the evidence. `budget.py` prints a reminder when the peak is
above it, and says plainly that this is a reminder and not a reading,
because the capture file does not record which connectors were in use.

**The PPK2 goes on the modem's supply rail, not the system's.** A Raspberry
Pi 3 idles in the hundreds of milliamps and the instrument stops at 1 A, so
measuring the whole board would clip before the modem did anything
interesting. The consequence, stated so nobody looks for it here: this
project does not measure the processor's own draw. That is a separate
question and Project 3's tooling can already take it.

## Before power, every time

The supply is the hazard, as it was on Project 5.

- The HAT takes 5 V from the header, and during a measurement **the PPK2
  must be the only supply**. Project 3 states it plainly: leaving the other
  cable connected "joins two supplies and the PPK2 then measures" something
  that is not the device.
- Both PPK2 connectors, before anything is switched on, because the peak
  here will be above 400 mA.
- 2G must be locked out with `AT+CNMP=38` before any capture. A GPRS
  transmit burst on this class of part is in the region of 2 A, which is
  twice the instrument's ceiling. That figure is reasoning from the part's
  class and not a bench measurement, which is exactly why the lockout is
  cheaper than finding out.
- Close the Power Profiler desktop application first. It holds the serial
  port, and the failure is an unhelpful access-denied from the serial layer
  rather than anything naming the application. Project 3 lost time to this.

## What a run produces, and what it does not

`budget.py` prints `charge_mc` beside `duration_s` on purpose. A charge
without the interval it covers is not a measurement, it is a number, and
the interval is set by how long that particular report took rather than by
anything chosen in advance.

`duration_s` is bounded by the marker process starting and stopping, and
process startup is inside that interval rather than outside it, so the
charge reads slightly high. That is the safe direction for a budget. The
size of it should be measured once rather than assumed negligible, and
until it has been, no figure from here is quoted to better than about a
millisecond of its interval.
