# Threat model

Written before the code, because the interesting thing about this project
is the list of what it cannot do, and a list like that written afterwards
reads as an excuse.

**One sentence:** on a Raspberry Pi 3 the secure world is a software
convention, not a hardware boundary, so this project demonstrates the
GlobalPlatform APIs, the boot flow and the debugging tools, and protects
nothing against an attacker who can run code as root.

## What the boundary is made of, layer by layer

```
  what the drawing suggests               what the Pi 3 actually enforces
  ---------------------------             --------------------------------

  +-----------------------+
  |   secure world        |               NS bit in the CPU: real.
  |   TZDRAM 0x10100000   |  <----------  The core does track which world
  |   15 MB, "protected"  |               it is in, and S-EL1 is a real
  +-----------------------+               privilege level.
             ^
             |  a wall                    The wall around the memory:
             |                            NOT real. There is no TZASC on
  +-----------------------+               BCM2837, so nothing stops a
  |   normal world        |               normal-world master from reading
  |   Linux, your code    |               that address range.
  +-----------------------+

  +-----------------------+               DMA: also not fenced. The GPU,
  |   GPU, USB, DMA       |  ---------->  USB and DMA engines address
  +-----------------------+               memory without passing through
                                          a filter the secure world owns.
```

That is the whole of it. The CPU distinguishes the two worlds; the memory
system does not.

## The three things this board cannot do

| Property | What a secure SoC does | What the Pi 3 does | So |
|---|---|---|---|
| **Verify the secure world at boot** | ROM checks a signature on the first image against a fused public key | The GPU loads `armstub8.bin` from an unsigned FAT partition | Anyone with the card writes their own secure world |
| **Derive a per-device storage key** | A hardware unique key, fused per part, never readable | OP-TEE derives from a constant that is in the published source | One device's secure storage decrypts another's |
| **Keep secure memory private** | A TrustZone address-space controller fences the secure DRAM | No such controller on BCM2837 | Root, or any DMA master, can read the TA's memory |

Each row alone is enough to end the discussion, which is the point of
listing all three: this is not one missing feature that a later patch
fixes.

## What is still true, and worth the effort

The parts that are real are the parts that transfer:

- The **API surface** is the GlobalPlatform TEE Internal Core API and TEE
  Client API, and it is identical on an i.MX8 or an STM32MP1. The TA
  source in this project moves to a board with fused keys unchanged.
- The **boot flow** is real: TF-A, a resident EL3 monitor, an SPD, BL32,
  BL33. Reading a three-banner console and knowing what each banner means
  is a skill that does not depend on whether the keys are fused.
- The **key never crosses the SMC boundary** in this design. That is a
  property of the code, not of the silicon, and it is what makes the code
  worth moving to silicon that enforces it.
- The **failure modes** are real: a missing supplicant, an unsigned TA, a
  parameter type mismatch, a deleted storage directory. All of them behave
  the same way on hardware that does enforce the boundary.

## The four attackers, and which ones this stops

| Attacker | Capability | Stopped? |
|---|---|---|
| A normal-world program, unprivileged | Calls `libteec`, opens a session | **Yes.** It can ask for a signature and cannot read the key |
| Someone with the SD card, offline | Reads and writes the FAT and the rootfs | **No.** They replace `armstub8.bin` with a secure world that prints the key |
| Root on the running board | Anything in the normal world, including `/dev/mem` and DMA | **No.** TZDRAM is readable, so the key is readable |
| Physical, with a logic analyser | Bus probing, glitching | **No**, and no software answer exists at this level |

Row one is the only yes, and it is not nothing: it is the property that a
compromised gateway process cannot exfiltrate a key, which is the
scenario a fleet operator actually faces. It is just not the property the
word "secure" implies to a reader who has not read this page.

## What the export-once command is for, and what it admits

`CMD_EXPORT_ONCE` hands the raw key to the normal world exactly once and
then writes a lock object; every later call returns
`TEE_ERROR_ACCESS_DENIED`.

That is a deliberate hole, and it exists because the verifier needs the
same secret: HMAC is symmetric. The design of the hole matters more than
its existence:

- it is **one command**, auditable in one place, rather than a key file
  that a provisioning script copies around
- it is **irreversible**, so a board in the field cannot be talked into
  exporting again
- it is **visible**: `benchkey status` reports `locked: yes`, so a device
  that has not been locked is identifiable

The honest version of this in a product does not have the hole at all,
and the stretch goal says how: ECDSA P-256 instead of HMAC, exporting
only the public key, and a verifier that needs no secret. The reason this
project ships the symmetric version first is that HMAC in secure storage
is about eighty lines of TA and asymmetric signing is four times that,
and the eighty-line version teaches the same three mechanisms.

## The sentence to use, and the one to avoid

Do not write, on a CV or anywhere else:

> Secure key storage on the Raspberry Pi.

Write:

> An OP-TEE trusted application and its normal-world client on the Pi 3
> reference platform: key generation and HMAC signing inside the TEE,
> secure storage, and a written threat model of what the platform does
> not enforce.

The second one is longer and it is the one that survives the follow-up
question, which is always some form of "and what stops root from reading
it". The answer is "on this board, nothing, and here is the table".

## What would have to change to make the first sentence true

Useful to know, because it is the same list an evaluation board vendor
publishes:

1. A SoC with fused secure boot, so the first stage verifies the next.
2. A hardware unique key, so `TEE_STORAGE_PRIVATE` is per device.
3. A TZASC or equivalent, so secure DRAM is fenced from normal-world
   masters and from DMA.
4. A TA signing key held somewhere other than the build tree.
5. Secure boot state reflected in what the TA will do, so a board booted
   with a development image refuses to use a production key.

Items one to three are silicon. Items four and five are process, and
could be done on this board, and would still not make it secure, which is
the clearest illustration of why the list is ordered this way.

---

Back to the [design](DESIGN.md) or on to the
[project README](../README.md).
