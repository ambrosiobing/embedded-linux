# Hardware sources for project 19

[docs/DESIGN.md](DESIGN.md) carries the partition layout, the ownership
table, the boot counter and the failure paths. **This page does not repeat
any of that.** It records the one piece of hardware this entire project
runs on, which nobody has written down, and the one claim about an LED
that turns out to be about software.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| Raspberry Pi 3 Model B product page | `vendor page` | **read Wednesday 7 October 2026**; it is a bullet list and there is no brief or datasheet for this board |
| Raspberry Pi 4 Model B datasheet, release 1.1 | `datasheet` | read, for the SD interface figure, with the caveat that it is a different board |
| **the microSD cards in use** | | **`NOT READ`, and not even identified** |

## The card is the hardware, and nobody knows which card it is

Every other project on this bench has a part whose document could be read.
This one does not. **The hardware of project 19 is a microSD card.** Two
root partitions, a FAT boot partition, a U-Boot environment and a boot
counter all live on it, and the specification insists on a second card
because the FAT partition is not updatable by any bundle.

**And the card is not identified anywhere in this repository.** Not its
make, not its model, not its capacity, not its speed class, not its
endurance rating.

That is a bigger gap here than in project 1, where it only costs the
reproducibility of a timing figure. Here it bears on the thing the project
exists to demonstrate.

## The write pattern, laid out, because it is the argument

```
   every boot              U-Boot: saveenv    ->  uboot.env on FAT p1
                                                  16 KiB, rewritten

   every update            rauc install       ->  the whole inactive
                                                  root partition

   every update            fw_setenv x2       ->  uboot.env again

   every mark-good         fw_setenv          ->  uboot.env again
```

`DESIGN.md` already calls the `uboot.env` row a hazard and solves the
dirty-page half of it by mounting the FAT partition with `sync`. Its own
note says the cost is nothing "because the only runtime writer is a 16 KiB
file twice per update".

**The part that is not addressed is the first line.** U-Boot calls
`saveenv` on **every boot**, not twice per update. A 16 KiB file rewritten
on every boot of a board that is deliberately rebooted over and over to
exercise failure paths is a different write pattern from the one the note
describes.

**Whether that matters is a property of the card and cannot be answered
without knowing which card it is.**

- a modern card with good wear levelling spreads 16 KiB rewrites across
  its whole flash and will outlive the project by orders of magnitude
- a cheap card with a small translation table can map a hot 16 KiB region
  onto a few physical blocks, and FAT metadata is the classic place for
  that to bite
- an "endurance" or "high endurance" card is sold specifically for this
  pattern

**No claim is made here about which it is.** The point is that the
question is currently unanswerable, and answering it costs one line in the
evidence directory: the make, model and capacity of each card, read off
the card.

## The SD interface, and the caveat on the only number available

**Raspberry Pi 4 Model B datasheet, section 5.1.4, page 11:** the
dedicated SD card socket supports 1.8 V DDR50 mode at a peak bandwidth of
50 megabytes per second.

**This project's board is a Raspberry Pi 3, not a Pi 4**, and no Raspberry
Pi document gives an equivalent card interface figure for it. So the
50 MB/s number is `inferred` for this board and should not be used for a
timing claim here.

**One nearby claim on this page was wrong and is corrected.** It said the
Pi 3 has no electrical specification at all. It has one, for its GPIO
pins, in the GPIO section of Raspberry Pi's documentation, found on
Friday 9 October 2026; see [docs/HARDWARE.md](../../../docs/HARDWARE.md).
What that document does **not** cover is the SD card interface, so this
particular gap is real and the sentence above stands.

What it does bound usefully, as an order of magnitude: writing a whole
root partition during `rauc install` is the heaviest single operation in
the project, and it is interface-bound rather than CPU-bound. A slot that
takes a long time to install is normal and is not evidence of anything
wrong.

## The LED claim is about software, not hardware

`DESIGN.md` says a lit LED means a write is in progress and the card must
not lose power, with blinking meaning something else.

**That is true because of a kernel LED trigger, not because of the
board.** On these boards the activity LED is bound to an `mmc0` trigger by
default, so it follows card activity; the hardware merely provides an LED
that something can drive.

**The Pi 3B+ reduced schematic shows what the hardware part actually is:**
`D5`, the green LED marked "ACT", is switched by a small transistor from a
net named `STATUS_LED_G`, and `D6`, the red "PWR" LED, from `STATUS_LED_R`.
Where those nets originate was **not legible at the resolution read**, so
even the hardware half is only partly sourced, and that is recorded in
[docs/HARDWARE.md](../../../docs/HARDWARE.md).

**Why this is worth a paragraph rather than a footnote.** The instruction
"do not pull the power while the LED is lit" is a safety instruction in a
project about surviving power loss. If the LED's meaning comes from a
device tree binding, then **an image that changes the trigger changes the
meaning of the instruction**, silently, and the instruction stays in the
document looking correct. That is the same failure shape as a claim
written when it was true and left standing after the thing it described
changed.

So the safe form is to state the dependency: the LED means card activity
**while the `mmc0` trigger is bound to it**, and any image for this
project should assert that rather than assume it.

## What the Pi 3's own document contributes, which is one row

| From the product page | Relevance here |
|---|---|
| "Micro SD port for loading your operating system and storing data" | confirms there is one card slot and therefore one card, which is why the second card is a spare rather than a second slot |
| "Upgraded switched Micro USB power source up to 2.5A" | the supply, and the thing that gets pulled in a power-loss test |
| production until at least January 2028 | |

**Nothing about the card interface, the LEDs, or write behaviour.** For a
project whose entire surface is storage, the host's own document says
nothing usable, which is the strongest argument yet for recording what the
card is.

## Reflections on the wiring, of which there is one lead and it matters

**This project has no wiring except power**, and power is the instrument.
A power-loss test is performed by removing the supply, and `DESIGN.md`
counts the manual step rather than hiding it, the same way project 4 does.

**The rewiring worth considering, and the answer is the same as project
4's.** A switched supply under program control would turn every power-loss
test into a command. The Pi 3's product page gives the input as micro USB
up to 2.5 A; the Pi 3B+ brief adds "5 V DC via GPIO header" as a second
route, and the 3B+ schematic shows that the header route bypasses the
input fuse and the transient clamp. For **this** project, where the whole
point is to cut power at awkward moments, a switched inline USB supply is
the right shape and the header route is not: deliberately interrupting
power through a path that has no fuse, repeatedly, is asking for the one
failure the fuse exists to prevent.

**Neither exists on this bench**, which is why the manual step stands.

## Still `NOT READ`

| Document | Why it matters |
|---|---|
| **the microSD cards' own specifications** | the write endurance question above, and it starts with identifying them, which needs no document at all |
| a Raspberry Pi 3 SD interface figure | does not exist; the Pi 4 number is the nearest and is for a different board |
| the `ledtrig-mmc` or device tree binding in use | would turn the LED instruction from a convention into an assertion the image can check |
