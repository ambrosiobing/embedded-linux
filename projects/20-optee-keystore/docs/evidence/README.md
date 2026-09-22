# Portfolio evidence

What goes here, and how each item is produced. Nothing in this folder is
written from expectation.

What is here today, Tuesday 22 September 2026:

| File | What it is |
|---|---|
| `boot-console-2026-09-22.txt` | The picocom log of two boots of the modular image, whole: firmware, TF-A, OP-TEE, U-Boot, the fifteen `fdt` commands, login, then `modprobe optee` and the hang. The fifth and sixth sightings of the mailbox stopping one second after the first call into the secure world. Carriage returns and the nulls of three serial breaks stripped, the Ethernet MAC redacted. Journal entries 28 and 29 read from it |

Still to copy from the build host: `rpi3-manifest.xml`, the `repo
manifest -r` of the secure-world build, every OP-TEE component at
`refs/tags/4.1.0` and TF-A at v2.6, from `out/` in the OP-TEE build
checkout. Journal entry 18 describes it.

A secure world has started, six times, and no call into it has ever
returned. The [project README](../../README.md)
marks two criteria "policy proven against a model" and one "met in
software", and the distinction those phrases carry is the whole point of
this folder: a model can prove that the policy is consistent, and only a
board can prove that a MAC came out of a secure world.

| File | How to produce it |
|---|---|
| `boot-console.txt` | The serial console of a boot that satisfies criterion 1, kept whole: three banners in order, then `dmesg` reporting the OP-TEE revision, then `/dev/tee0` present. The order is the claim, so a summary of it is not the evidence. The file above is not this one: the revision line never appears in it, which is the finding |
| `xtest-report.txt` | `xtest` on this image, whole output. Criterion 2 is zero failures, and the run also states which suites the build actually included |
| `generate-twice.txt` | `benchkey generate` twice, with a hexdump of the object under `/var/lib/tee` between them. Criterion 3 wants success, then `ACCESS_CONFLICT`, and a file that is visibly not plaintext |
| `sign-across-reboot.txt` | `benchkey sign` of one input, a reboot, the same call again, and `benchkey export-once` twice. Criterion 4 is the same 32 bytes both times and an export that works exactly once |
| `verify.txt` | The verifier against a real device record and against an altered one. Criterion 5 is **met in software** against the canonicalisation suite; this file is the same command against records a TEE produced |
| `timing.txt` | A signing call timed over enough repetitions to quote a distribution rather than one number. Criterion 6 is under 1 ms |
| `ta-missing.txt` | The TA removed, then the client run. Criterion 7 wants `TEEC_OpenSession` failing with `ITEM_NOT_FOUND` and origin `TEE`, which is a different failure from the TA being present and refusing |
| `leds.jpg` | The red LED lit for the criterion above. Deferred on the same terms as Project 1: it needs three bare LEDs or an LK-Cable |

Two of these carry a caveat worth writing beside the number when the time
comes. The Pi 3 has no secure boot and no hardware unique key, so nothing
here is a claim about confidentiality against an attacker with the board;
[THREAT-MODEL.md](../THREAT-MODEL.md) says what is and is not in scope.
