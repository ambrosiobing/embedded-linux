# Hardware sources for project 4

[docs/DESIGN.md](DESIGN.md) carries the architecture, the lab network, the
boot sequence and the runner. **This page does not repeat any of that.**
It records what the two boards' own documents say about the three things
this lab depends on physically: the network, the power, and the boot ROM.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| Raspberry Pi 3 Model B+ product brief, October 2025 | `vendor page` | **read**, the DUT |
| Raspberry Pi 3 Model B+ reduced schematic, V1.0, 19 March 2018 | `schematic` | **read** |
| Raspberry Pi 4 Model B datasheet, release 1.1, 12 March 2024 | `datasheet` | **read**, the server |
| Raspberry Pi network boot documentation | `vendor page` | **`NOT READ`**, see below |

All three read documents are worked through in
[docs/HARDWARE.md](../../../docs/HARDWARE.md); this page takes only what
bears on this lab.

## The network is asymmetric, and one number says why

**Raspberry Pi 3 Model B+ product brief, page 3:**

> Gigabit Ethernet over USB 2.0 (maximum throughput 300Mbps)

**Raspberry Pi 4 Model B datasheet, section 2.2, page 6:** one Gigabit
Ethernet port, with no such qualification, because on the Pi 4 the
Ethernet controller is not behind USB.

```
   server: Raspberry Pi 4                    DUT: Raspberry Pi 3B+

   +-----------------+                       +------------------+
   | BCM2711         |                       | BCM2837B0        |
   |   native GbE    |                       |   USB 2.0 hub    |
   |                 |                       |      |           |
   |   [ RJ45 ]      |                       |   LAN7515 class  |
   +-------|---------+                       |   GbE over USB   |
           |                                 |      |           |
           +--- 192.168.7.0/24 --------------+-- [ RJ45 ]       |
                                             |                  |
                 up to 1 Gbit/s              | 300 Mbit/s max   |
                                             | shared with      |
                                             | every USB device |
                                             +------------------+
```

**Three consequences for this lab.**

1. **The NFS root is capped at 300 Mbit/s** no matter what the server or
   the switch can do. Any boot time this lab measures is a boot time on a
   300 Mbit/s link.
2. **Ethernet shares the USB 2.0 bus with everything else on the DUT.**
   Plug a USB device into the device under test and the root filesystem's
   transport is sharing bandwidth with it. For a lab whose whole point is
   repeatability, that is a reason to keep the DUT's USB ports empty and
   to say so rather than merely to do it.
3. **Never compare a 3B+ boot with a Pi 4 boot and attribute the
   difference to the kernel or the image.** The transport differs by more
   than a factor of three before anything else is considered. That is the
   same mistake project 8 nearly made with two kernel versions, arriving
   from a different direction: **a comparison differs in one variable or
   it is not a comparison.**

The 300 Mbit/s figure is the manufacturer's own, from the brief. What is
`inferred` here is the attribution to the USB 2.0 hub being shared; the
brief says Ethernet is over USB 2.0 and the Pi 3B+ has four USB 2.0
sockets, and the conclusion that they contend follows from the topology
rather than from a sentence.

## The power cycle this lab cannot do, and the two routes the documents show

`DESIGN.md` is honest about the limitation: the bench has no relay, no
switched USB hub and no smart plug, so the runner reboots the DUT over its
own console and prints a line asking for the plug to be pulled when that
fails. The manual step is counted in the run log rather than hidden, which
is the right treatment.

**Both boards' documents describe a route to a real power cycle**, and
neither is on this bench.

**Route one, the GPIO header.** The Pi 3B+ brief, page 3, lists the input
power as "5 V / 2.5 A DC via micro USB connector" **and** "5 V DC via GPIO
header". So a switched 5 V supply on header pins 2 or 4 would power the
DUT and could be cut under program control.

**And the schematic says what that costs.** The reduced schematic's POWER
IN block shows the micro USB connector `J1` feeding a resettable fuse
`F1`, marked `MF-MSMF250/X`, with an `SMBJ5.0A` transient suppressor
across the output. The header's 5 V pins sit on the same net **downstream
of that protection**. Feeding the board through the header therefore
bypasses both the fuse and the clamp. That is a real trade and it should
be made deliberately rather than discovered.

**Route two, Power over Ethernet, which is the better one for this lab.**
The Pi 3B+ brief lists "Power over Ethernet (PoE)-enabled (requires
separate PoE HAT)"; the Pi 4 datasheet, section 2.2, lists "1x Gigabit
Ethernet port (supports PoE with add-on PoE HAT)". The 3B+ schematic shows
where the power is taken from: a four way header, `J14`, carrying the
Ethernet transformer centre taps `TR0_TAP` through `TR3_TAP` from the
magnetics at `J10`.

**Why PoE is the right shape here and not merely another option.** This
lab already runs an isolated Ethernet island with exactly two hosts on it.
A managed PoE switch with per-port power control would put the DUT's power
on the same cable as its boot transport and under the same program that
drives the test, turning "ask a human to pull the plug" into a command.
Nothing else on this bench offers that.

**What it would cost, and the open question.** A PoE HAT and a managed PoE
switch, neither here. And one thing no document read answers: **whether a
PoE HAT leaves header pins 6, 8 and 10 reachable**, which this lab needs
for the DUT's serial console. The power itself comes off `J14`, not the 40
pin header, but a HAT still sits on the 40 pin header. That is a question
for the PoE HAT's own documentation and it is `NOT READ`.

## The boot ROM, which is the one claim with no source at all

`DESIGN.md` rests on three statements about the DUT's boot ROM:

| Claim | Where it comes from now |
|---|---|
| the boot ROM in OTP runs before anything else, so a soft reboot re-enters network boot | **unsourced** |
| the Pi 3B+ can network boot without an OTP bit being programmed first | **unsourced** |
| it sends a DHCP vendor class and reads option 43, then fetches from a TFTP directory named after the board's serial number | **unsourced** |

**None of these is in either board document.** The product brief and the
datasheet describe products; the boot ROM's behaviour is in Raspberry Pi's
separate network boot documentation, which was reached on Wednesday
7 October 2026 and **served a truncated page** that did not include the
section.

**They are also, all three, working.** `run-log-20-boots.txt` in this
directory is twenty boots of evidence that the sequence does what the
design says. So the evidence level here is **`measured`, not `NOT READ`**,
and that distinction matters: the lab is not resting on an unverified
belief, it is resting on a verified behaviour whose documentation has not
been read.

**What reading the document would add** is the one thing twenty successful
boots cannot: knowing which of these behaviours is guaranteed and which is
incidental to this board revision and this bootloader version. A lab built
on an incidental behaviour works until a firmware update, and then stops
working for a reason nobody can look up.

So this stays on the list, and the right form of the open question is not
"does network boot work" but **"which parts of what we observe are
specified"**.

## Two small things from the brief that belong in the bring-up notes

**The DUT has no card in it, and the brief explains the hazard from the
other side.** `DESIGN.md` says a card left in means the board boots from
it and the lab proves nothing. Worth adding the manufacturer's own
instruction from page 4 of the brief: whilst powered, avoid handling the
board, or handle it by the edges. A card swap on a running board is the
commonest reason to touch one.

**And the surface.** Also page 4: place the board on a stable, flat,
**non-conductive** surface where no conductive item can touch it. This lab
has two boards, two power supplies, a USB to TTL cable and an Ethernet
cable on a desk at once, which is the configuration that instruction is
about.

## Still `NOT READ`

| Document | What it would settle |
|---|---|
| Raspberry Pi network boot documentation | all three boot ROM claims above, and whether they are specified or incidental |
| the official PoE HAT's documentation | whether header pins 6, 8 and 10 stay reachable under it, which decides whether route two is usable here |
| the Pi 3B+'s Ethernet controller datasheet | whether the 300 Mbit/s figure is a bus limit or a controller limit, which decides whether it can ever be improved |
