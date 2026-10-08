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
| Raspberry Pi network boot documentation, AsciiDoc source | `vendor page` | **read Thursday 8 October 2026** |

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

## The boot ROM, and the three claims the lab rests on

`DESIGN.md` rests on three statements about the DUT's boot ROM:

| Claim | Where it came from on Wednesday 7 October 2026 |
|---|---|
| the boot ROM in OTP runs before anything else, so a soft reboot re-enters network boot | **unsourced** |
| the Pi 3B+ can network boot without an OTP bit being programmed first | **unsourced** |
| it sends a DHCP vendor class and reads option 43, then fetches from a TFTP directory named after the board's serial number | **unsourced** |

**None of these is in either board document.** The product brief and the
datasheet describe products; the boot ROM's behaviour is in Raspberry Pi's
separate network boot documentation, which on Wednesday 7 October 2026
**served a truncated page** that did not include the section.

**They are also, all three, working.** `run-log-20-boots.txt` in this
directory is twenty boots of evidence that the sequence does what the
design says. So the evidence level was **`measured`, not `NOT READ`**, and
that distinction matters: the lab was not resting on an unverified belief,
it was resting on a verified behaviour whose documentation had not been
read.

**That documentation was read on Thursday 8 October 2026**, from its
AsciiDoc source rather than the rendered page, and the section below works
through what it settles and what it does not. The short version: the
second claim is specified in one sentence, the DHCP half of the third is
specified, and the other two remain measurements with no sentence anywhere
to back them.

So this stays on the list, and the right form of the open question is not
"does network boot work" but **"which parts of what we observe are
specified"**.

## The network boot documentation is read, and it settles one claim of three

**Source: Raspberry Pi documentation, "Network boot your Raspberry Pi",
read Thursday 8 October 2026** from the project's own source at
`raspberrypi/documentation`, file
`documentation/asciidoc/computers/remote-access/network-boot-raspberry-pi.adoc`
on the `master` branch.

**Provenance, because the first attempt failed.** The rendered page at
`raspberrypi.com/documentation/computers/remote-access.html` returned a
truncated document twice on Wednesday 7 October 2026, with the network
boot section missing. The AsciiDoc source is the same text before
rendering, it is complete, and it is version controlled, which makes it a
better citation than the page. **Where a vendor publishes its
documentation as source, read the source.**

### Claim 2 is settled outright, and the answer is that nothing is needed

This page listed three claims the lab rests on and marked all three
unsourced. The second was whether the Pi 3B+ can network boot without an
OTP bit being programmed first.

> This section only applies to the Raspberry Pi 3 Model B, as network boot
> is enabled on the Raspberry Pi 3 Model B+ at the factory.

**So there is nothing to do.** The `program_usb_boot_mode=1` dance, the
reboot, the `vcgencmd otp_dump` check and the removal of the line
afterwards are all for the plain Model B. The DUT here is a **3B+**, and
it arrives able to do this.

That matters more than a settled footnote usually does, because **the
procedure for the wrong board is destructive in a particular way**: the
OTP is one-time programmable, so a bit set on a board that did not need it
cannot be unset. Reading this before following a tutorial written for the
other board is the whole value.

**And the check for the other board is worth recording anyway**, in case
the DUT is ever swapped for a plain Model B: after programming,
`vcgencmd otp_dump | grep 17:` should read `17:3020000a`.

### Claim 3 is half settled, and the document gives the other half away

The third claim was that the board sends a DHCP vendor class and reads
option 43, then fetches from a TFTP directory named after its serial
number.

**The DHCP half is confirmed**, in dnsmasq's own terms. The document's
server configuration is:

```
   port=0
   dhcp-range=<broadcast address>,proxy
   log-dhcp
   enable-tftp
   tftp-root=/tftpboot
   pxe-service=0,"Raspberry Pi Boot"
```

Two things follow that the design should state explicitly. It is a
**proxy** DHCP arrangement, so the existing network keeps handing out
addresses and this server answers only the boot part. And the match is on
a **PXE service string**, `"Raspberry Pi Boot"`, which is how dnsmasq
expresses the vendor class and option 43 exchange that `DESIGN.md`
describes.

**The serial-number directory is not documented**, and the document hands
you the answer without stating it. It says to note the serial number "so
that the board can be identified by the TFTP/DHCP server", and gives the
command to find it:

```
   grep Serial /proc/cpuinfo | cut -d ' ' -f 2 | cut -c 9-16
```

**That `cut -c 9-16` produces exactly the eight hexadecimal characters
this lab uses as a directory name.** The document then walks the reader
through a **flat** `/tftpboot` with no per-board subdirectory at all, and
never says what the eight characters are for.

So the status of that half is: **`measured`, over twenty boots, with the
vendor's own command producing exactly the string the lab uses, and no
sentence anywhere saying the bootloader looks there.** That is better than
it was and it is not a citation. The honest form is that the behaviour is
real, reproducible, and apparently undocumented.

### Claim 1 is still only measured, and that is now a positive statement

The first claim was that the boot ROM in OTP runs before anything else, so
a soft reboot re-enters network boot.

**The document does not say it.** What it says is that the OTP bit
"enables network booting", and that a Pi 3B so programmed "attempts to
boot from USB, and from the network, if it can't boot from the SD card".
That describes a boot order, not what happens on a warm reset.

**So claim 1 remains `measured`**, and
[`run-log-20-boots.txt`](run-log-20-boots.txt) is the evidence. Twenty
soft reboots that re-entered network boot is strong, and the risk it
leaves is the one this page already named: a behaviour that is incidental
rather than specified can change in a firmware update, and nobody can look
up whether it was promised.

### Two warnings from the document worth carrying

**The vendor hedges on networking equipment**, in a note before anything
else:

> Due to the huge range of networking devices and routers available, we
> can't guarantee that network booting will work with any device. We have
> had reports that, if you cannot get network booting to work, disabling
> STP frames on your network might help.

**This lab has already avoided that entirely, by accident.** Its network
is `192.168.7.0/24` with exactly two hosts and a cable between them: no
switch, no router, no spanning tree, nothing to send an STP frame. The
isolation that `DESIGN.md` chose for determinism also removes the
commonest reported cause of network boot failing.

That is worth writing down as a reason the design is right, rather than
leaving it as a coincidence somebody later undoes by putting a switch in
the middle.

**And the Pi 4 does this differently.** On a Pi 4 the boot order lives in
the bootloader EEPROM, set through `raspi-config` and verified with
`vcgencmd bootloader_config` reading `0xf21`, rather than in OTP. In this
lab the Pi 4 is the **server** and never network boots, so none of that
applies; it is recorded because the two mechanisms share a name and not an
implementation, and a note about "the boot order" means different things
on the two boards in this lab.

### What this changes about the open item

The page's open question was stated as "which parts of what we observe are
specified". It now has an answer for each of the three:

| Claim | Status after reading |
|---|---|
| the boot ROM runs before anything else, so a soft reboot re-enters network boot | **`measured`**, twenty boots. Not stated in the document |
| the 3B+ network boots without programming anything | **specified**, in one sentence, and the opposite procedure is irreversible on the wrong board |
| DHCP vendor class and option 43 | **specified**, as `pxe-service=0,"Raspberry Pi Boot"` with a proxy DHCP range |
| the TFTP directory named after the serial number | **`measured`**, with the vendor's own command producing exactly that string and no sentence explaining it |

**Two of four are now sourced and two are honestly labelled.** That is the
useful outcome: the lab was not resting on anything false, and it now
knows which of its foundations are promises and which are observations.

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
| ~~Raspberry Pi network boot documentation~~ | **read Thursday 8 October 2026.** Two of the claims are specified, two are measured and apparently undocumented; the table above says which |
| the official PoE HAT's documentation | whether header pins 6, 8 and 10 stay reachable under it, which decides whether route two is usable here |
| the Pi 3B+'s Ethernet controller datasheet | whether the 300 Mbit/s figure is a bus limit or a controller limit, which decides whether it can ever be improved |
