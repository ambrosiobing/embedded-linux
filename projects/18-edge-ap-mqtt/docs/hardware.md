# Hardware sources for project 18

[docs/DESIGN.md](DESIGN.md) carries the architecture, the ownership table,
the FullMAC reasoning and the open question about which board is on the
bench. **This page does not repeat any of that.** It records what the two
hosts' own documents say about the radio, and the answer is a neat pair of
complementary silences.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| Raspberry Pi 3 Model B product page | `vendor page` | **read Wednesday 7 October 2026** |
| Raspberry Pi 3 Model B+ product brief, October 2025 | `vendor page` | **read Wednesday 7 October 2026** |
| BCM43438 or BCM43455 datasheets | `datasheet` | **`NOT READ`**, and Cypress and Infineon do not publish them openly |

## Each document states exactly what the other omits

This is the finding and it is almost funny.

| | Raspberry Pi 3 Model B | Raspberry Pi 3 Model B+ |
|---|---|---|
| wireless **chip** named | **yes**: "BCM43438 wireless LAN and Bluetooth Low Energy (BLE) on board" | **no** |
| wireless **bands** named | **no**, the page says nothing about 2.4 or 5 GHz | **yes**: "2.4 GHz and 5 GHz IEEE 802.11b/g/n/ac wireless LAN, Bluetooth 4.2, BLE" |
| Ethernet | "100 Base" | "Gigabit Ethernet over USB 2.0 (maximum throughput 300Mbps)" |
| SoC | BCM2837, 1.2 GHz | BCM2837B0, 1.4 GHz |
| document type | a web page with a bullet list, **no PDF at all** | a five page product brief |

**So `DESIGN.md`'s table is half sourced and half not.** The `BCM43438`
row for the Pi 3 is the manufacturer's own word. The `BCM43455` row for
the 3B+ and the Pi 4 is **not**: it comes from the firmware filename
`brcmfmac43455-sdio.bin`, which is Linux's name for it, not Raspberry Pi's.

That is the fourth time this pattern has appeared on this bench. The
ILI9486 in project 7, the FT5406 in project 13, the `dwc2` dual-role port
in project 14 and now the 43455: **the Linux driver names the part and the
manufacturer does not.** It is reliable and it is not a citation, and the
rows should say so.

**And the 2.4 GHz assumption, which the design depends on.** This project
targets a 2.4 GHz access point. On a Pi 3 that is not a choice, because a
BCM43438 is a 2.4 GHz part. **The product page does not say that**, so the
single-band restriction is `inferred` from the chip's well known identity
rather than cited. On a 3B+ the brief does say both bands, so 5 GHz would
be available there and the design is leaving something on the table it has
not had to decide about.

## Which board it is, answered without the radio

`DESIGN.md` says the open question is settled by one line of `dmesg` on
the first boot, and it is right that this must not be guessed, because
project 1 lost two rounds to an assumed radio.

**The documents offer two cheaper answers that do not involve the radio at
all**, which matters because the radio is the thing that may not come up:

1. **Ethernet speed.** The Pi 3 is 100 Base; the 3B+ is Gigabit over USB.
   `ethtool eth0` or the link rate in `dmesg` distinguishes them, and it
   works whether or not any wireless firmware is present.
2. **`/proc/cpuinfo`.** The `Revision` field identifies the board model
   outright, and needs nothing but a shell.

**All three checks should agree.** If they do not, that is the finding,
not a nuisance: two of them reading one board and one reading another
means something about the image or the hardware is not what it is thought
to be. Keeping all three rather than picking one is the cheap version of
this repository's rule that a check should name what it did not look at.

## Modular certification covers the hardware; the software still has to behave

**Raspberry Pi 3 Model B+ product brief, page 2:**

> The dual-band wireless LAN comes with modular compliance certification

That sentence is about designing the board into a product. **It does not
mean an access point built on it is automatically compliant**, and this
project is building an access point rather than using a station.

The part that compliance depends on is in software, and this repository
already handles it properly:
`meta-bench/recipes-bench/bench-ap/files/hostapd.conf.in` sets
`country_code`, the setup script refuses a country code that is not two
capital letters, and the recipe's own comment explains that `wireless-regdb`
and `iw` are what give a regulatory request something to resolve against.
`DESIGN.md`'s design is careful here and the datasheet reading does not
improve on it.

**One small thing it does suggest.** `bench-ap-setup` defaults `COUNTRY`
to `DE`, and this bench is in Austria. The default is a sensible neutral
choice and the card file is where identity belongs, exactly as
[docs/CARD.md](../../../docs/CARD.md) has it. Still: **the card for this
project should carry `COUNTRY=AT`**, and the fact that it works without
being set is precisely why it is easy to leave wrong.

## The other radio, and what neither document says

Both boards carry Bluetooth as well, and this project does not use it. The
Pi 3 page says "Bluetooth Low Energy (BLE)"; the 3B+ brief says
"Bluetooth 4.2, BLE".

**Neither document says that Bluetooth and the serial console contend**,
which on these boards they famously do: the Bluetooth module is attached
to the PL011 UART, which is why `disable-bt` exists and why project 9
spent an evening on a console that was never muxed. That is recorded in
[project 9's hardware page](../../09-kernel-debug/docs/hardware.md).

It matters here because **this project's access path is the access point
itself**: with no Ethernet cable and the radio serving rather than
associating, a serial console is the fallback when `hostapd` refuses to
start. So the image for this project should be built knowing whether its
console works, and that is a question answered in project 9 rather than
here.

## Reflections on the wiring, of which there is none

**This project has no wiring at all.** One board, one power supply, one
radio that is already on it. Every decision is about configuration, and
every hardware risk is about identity: which chip, which firmware, which
regulatory domain.

**That makes it the clearest case on the bench for reading documents
rather than probing.** There is nothing to probe. A continuity test tells
you nothing about whether `brcmfmac43430-sdio.bin` is the file this board
wants. The only instruments that apply are `dmesg`, `ethtool`,
`/proc/cpuinfo` and the two vendor documents above, and between them they
answer everything except the band question.

## Still `NOT READ`

| Document | Why it matters, and whether it is gettable |
|---|---|
| BCM43438 and BCM43455 datasheets | would confirm the bands and the AP mode capability from the part rather than from the firmware. **Probably not gettable**: these are not openly published |
| the `brcmfmac` firmware's own feature list | the FullMAC question `DESIGN.md` raises, whether WPA3-SAE is supported, is answered by the firmware rather than by any datasheet. `iw phy` on the running board reports what the firmware advertises, which is a measurement and is the right instrument here |

**The second row is the actionable one.** The design records WPA3 as a
thing to try on the board rather than to promise, which is correct. `iw
phy` turns "try it" into "ask it", and it needs no documents at all.
