# Failover measurements

Three scenarios, each with a number attached, because "it failed over" is
not a result. All of them are run from a bench client on the access point,
not from the Pi: what matters is what a user of the gateway experiences.

**Nothing here has been measured yet.** The tables are the plan, and the
acceptance criteria they test against are in
[the project README](../README.md). Leaving them empty is deliberate:
Project 1 kept its build-times table empty until the build had run on this
bench, and a number that was never measured is worse than a blank.

## Method

On the client:

```sh
ping -O -D 1.1.1.1 | tee ping.log
```

`-O` prints a line for every missed reply, which turns the outage into a
countable thing rather than a gap in the output. `-D` timestamps each line.

On the Pi, in a second window:

```sh
journalctl -f -u NetworkManager -u ModemManager -u lte-watchdog
```

The measurement is the number of consecutive "no answer" lines, which at
one ping per second is the outage in seconds.

## A note on what "the cable" means here

This bench has no Ethernet cable within reach, so the primary uplink is a
USB wireless adapter on `wan0` at metric 100, joining the network the cable
would have reached. Journal entry 25 has why.

That changes how the scenarios are provoked, and it is worth being precise
about which of them is weakened.

| Scenario | With a cable | Here |
|---|---|---|
| 1, carrier loss | Unplug it. A physical event the kernel sees immediately | `nmcli dev disconnect wan0`, or power off the home access point. The second is a real carrier loss and the better test |
| 2, live carrier, dead upstream | Unplug the home router's own uplink | Identical. Nothing about it depends on the medium |
| 3, the modem stops | `AT+CFUN=0` | Identical |

Scenario 1 is the weakened one: a software disconnect proves NetworkManager
withdraws the routes, which is most of what matters, but it does not prove
the driver notices a carrier that vanished. Powering off the access point
does, and takes longer to recover, so record which method each run used.

## Scenario 1: the cable comes out

The carrier drops, so NetworkManager withdraws the eth0 routes at once and
no connectivity check is involved. This should be the fastest of the three.

| Run | Method | Replies lost, out | Replies lost, back |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

Acceptance: at most 5 replies lost on the way out. The way back may take up
to 90 s, because eth0 has to get an address and then pass a connectivity
check before its metric is trusted again.

## Scenario 2: a live cable behind a dead upstream

Unplug the home router's own uplink and leave the Pi's cable in. The
carrier stays up, so nothing in the kernel notices. Only the connectivity
check catches this, and the detection floor is therefore the check
interval, 60 s.

| Run | Time to switch | Time to switch back | Notes |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

Acceptance: detected within two connectivity intervals and traffic moves to
LTE.

This is the scenario that justifies the connectivity check existing at all.
Without it the box sits happily behind a dead router with a perfectly good
LTE uplink idle beside it, which is the failure that makes people distrust
failover.

## Scenario 3: the modem itself stops

Force it with `AT+CFUN=0` on the AT port, which is a clean way to make the
module stop being a modem without unplugging anything.

| Run | Level reached | Time to a connected bearer | Notes |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |

Acceptance: a connected bearer within 4 minutes, and the counters in
`watchdog.prom` show which levels were used.

The counters are the evidence, not the journal: a level reached is
`lte_recoveries_total{level="N"}` going up by one, and it is visible on a
dashboard long after the journal has rotated.

Expect level 1 to be enough for `AT+CFUN=0`, because `nmcli con up lte`
re-enables the modem on its way to building the bearer. If level 1 does not
fix it, that is worth a journal entry: it means the cheap rung is cheaper
than it is useful, and the ladder should start higher.

## Scenario 4: a ten minute load test

Not a failover, but the one that catches the power problem.

```sh
iperf3 -c <server> -t 600 -R
journalctl -k | grep -i voltage
```

Acceptance: no undervoltage message in the kernel log.

| Run | Throughput | Undervoltage lines | Supply used |
|---|---|---|---|
| 1 | | | |

## What these numbers are not

They are one carrier, one cell, one afternoon. Cellular latency and
re-registration time vary by an order of magnitude between a quiet rural
cell and a busy urban one, and between carriers on the same cell. The
numbers are a record of this bench, not a specification anyone should
inherit. Project 3's rule applies here as much as there: a measurement
taken once is an anecdote, and it becomes a specification only when
something takes it again on demand.
