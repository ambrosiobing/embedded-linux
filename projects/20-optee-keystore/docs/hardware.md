# Hardware sources for project 20

[docs/DESIGN.md](DESIGN.md) carries the architecture and
[docs/THREAT-MODEL.md](THREAT-MODEL.md) carries what this project does and
does not defend against. **This page does not repeat either.** It answers
a question the other hardware pages on this bench do not have to:
**how do you cite an absence?**

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## The claim this whole project is built on

The README's first paragraph says the Raspberry Pi 3 has no secure boot,
no hardware unique key and no controller that keeps the normal world out
of secure memory, and that the firmware loads the secure world from an
unsigned FAT partition.

**That is a claim about things that are not there.** Nothing in a product
page or a peripherals document says "this part does not have a memory
firewall", because documents describe what exists. An absence cannot be
read off a specification; it can only be inferred from silence, which is
weak, or found stated by somebody who went looking, which is strong.

**Somebody did go looking, and they wrote it down.**

## The citation, and it is unusually blunt

**Source: the OP-TEE documentation, "Raspberry Pi 3" platform page.** Read
Wednesday 7 October 2026.

> This port of Trusted Firmware A and OP-TEE to Raspberry Pi 3 **IS NOT
> SECURE!**

and, on what the hardware lacks, that while the processor provides Arm
TrustZone exception states it lacks

> the mechanisms and hardware required to implement secure boot, memory,
> peripherals or other secure functions

and on what follows:

> Use of OP-TEE or TrustZone capabilities within this package **does not
> result** in a secure implementation

and on what it is for: the package is provided solely for **educational
purposes and prototyping**.

**That is the best possible source for this claim**, and it is better than
a Broadcom datasheet would have been. It is written by the people who did
the port, it is specific about which capabilities are missing, and it
states the consequence rather than leaving the reader to draw it. The
README's paragraph is now citable word for word.

| Claim in the README | Evidence |
|---|---|
| no secure boot | `vendor page`, OP-TEE platform documentation |
| no mechanism for secure memory or secure peripherals | `vendor page`, the same |
| TrustZone exception states do exist on the processor | `vendor page`, the same, and `datasheet` by implication from the Cortex-A53 |
| no hardware unique key | **still `inferred`**: the OP-TEE page does not use that phrase, and "the mechanisms and hardware required to implement secure boot, memory, peripherals or other secure functions" covers it without naming it |
| the firmware loads the secure world from an unsigned FAT partition | **`measured`**: it is what this bench's own boot does, and it follows from there being no secure boot |

**The fourth row is the one to keep honest.** "No hardware unique key" is
a specific statement about a specific facility, and the quoted sentence is
a general one. It is almost certainly right, it is the normal reading, and
it is one step of inference beyond what the page says. Marking it is the
difference between a threat model and a slogan.

## Why this is the right way round, and not a disappointment

It would be easy to read this page as a list of things the bench cannot
do. It is the opposite, and the project already knows it: **the value here
is in knowing exactly which guarantees are absent**, because that is what
a threat model is.

A trusted application that stores a key on a Pi 3 is a correct
demonstration of the TEE Client API, of secure storage as an interface,
and of the normal-world and secure-world split as an architecture. It is
not a secure key store, and the only thing that would make the project
dishonest is failing to say so. [THREAT-MODEL.md](THREAT-MODEL.md) exists
for that, and it now has a citation rather than an assertion.

**The general form, which is worth having on this bench**: when the thing
you need to establish is an absence, do not look for it in the
manufacturer's document. Look for somebody who tried to build on it and
documented what they could not do. For hardware security that is almost
always a porting project; for a peripheral it is often a driver's comments.

## What the host documents do and do not contribute

| Document | What it says relevant to this project |
|---|---|
| Raspberry Pi 3 Model B product page | nothing about security; it is a bullet list, and the board has no brief and no datasheet |
| Raspberry Pi 3 Model B+ product brief | nothing about security |
| BCM2835 ARM Peripherals | **no TrustZone chapter at all**; it documents the peripheral block and says nothing about secure or non-secure access control |
| Raspberry Pi 4 Model B datasheet | nothing about security |

**That last row in the BCM2835 document is itself weak evidence and should
be treated as such.** A document that predates the Pi 3 and describes a
different part not mentioning a facility is not proof the facility is
absent. It is consistent with the OP-TEE statement and it does not
independently support it.

## The one hardware fact that is this project's practical limit

The secure world is loaded from the **FAT boot partition**, which is the
same partition the bench writes credentials to after flashing, as
[docs/CARD.md](../../../docs/CARD.md) describes, and the same one project
19 writes its U-Boot environment to.

**So the card is the trust boundary, and it is a microSD card in a slot.**
Anybody who can take the card out can replace the secure world. On this
bench that is the correct and expected state of affairs, because the port
is for education and prototyping. It is worth writing down because it
makes the limit concrete rather than abstract: the attacker model that
defeats this project entirely is **a hand**.

## Still `NOT READ`

| Document | What it would settle, and whether it exists |
|---|---|
| a BCM2837 security or TrustZone reference | would settle the hardware unique key question directly. **Probably does not exist publicly**; Broadcom publishes the peripherals document and little else for this part |
| Arm's TrustZone documentation for Cortex-A53 | would separate what the **core** provides, which is real, from what the **SoC around it** provides, which is the part that is missing. That distinction is the whole of why this port is insecure, and it is currently stated rather than sourced |

**The second row is the interesting one and it is gettable.** Arm
publishes its architecture documentation openly, and the distinction
between core-level TrustZone and SoC-level enforcement is exactly the
thing a reader of this project will want explained. That would turn the
OP-TEE warning from a verdict into an explanation.
