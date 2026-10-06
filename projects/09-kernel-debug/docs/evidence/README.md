# Evidence

Verbatim output, kept as files because the notebook quotes fragments and a
fragment cannot be checked. The convention for this repository is that an
evidence file carries a header saying what was run, on what, when, and
what it proves. These particular files cannot: they are kernel records
whose exact bytes are the evidence, and one of the findings in notebook
entry [05](../../notebook/05-pstore.md) came from a single trailing space.
So the header lives here, one section per capture, and the files stay
untouched.

## pstore records, Tuesday 6 October 2026

**What was run.** Nothing, for the first three. They are the records
ramoops wrote into reserved DRAM during the crash of Tuesday 6 October
2026 at 02:55 and kept across the warm reboot, read off the board with:

```sh
ssh root@BOARD "cat /sys/fs/pstore/NAME"
```

from win11 skyhorizon demo laptop, WSL bash as `bing@JPTOUPM678`. WSL
rather than PowerShell because PowerShell 5.1 redirection writes UTF-16LE
and rewrites line endings, and these bytes matter.

The fourth is the record from the deliberate SysRq crash later the same
day, read back the same way after the board rebooted on its own.

**On what.** Raspberry Pi 3 Model B Plus Rev 1.3, kernel 6.6.63-v8, image
archived as `2026-10-05_a743c9c`.

| File | Header | Bytes | What it is |
|---|---|---|---|
| `pstore-2026-10-06-console-ramoops-0.txt` | none | 32,756 | the rolling console zone, unchanged across a later panic and reboot |
| `pstore-2026-10-06-dmesg-ramoops-0.txt` | `Oops#1 Part1` | 27,281 | the NULL dereference, dumped at the oops |
| `pstore-2026-10-06-dmesg-ramoops-1.txt` | `Panic#2 Part1` | 27,240 | the same crash, dumped again at the panic |
| `pstore-2026-10-06-sysrq-dmesg-ramoops-0.txt` | `Panic#1 Part1` | 27,283 | the SysRq crash, which overwrote zone 0 |

Every record carries `<N>` syslog level prefixes that the serial console
does not, and each holds the whole kernel log buffer from about board time
0.38 seconds, so anything the kernel printed earlier is cut off the front.

**What they prove.**

- **Acceptance criterion 2.** Lines 385 to 430 of
  `pstore-2026-10-06-dmesg-ramoops-0.txt`, with the level prefixes
  stripped, are byte identical to the 46 line raw oops block in notebook
  entry [01](../../notebook/01-oops.md). The fourth file holds
  `Kernel panic - not syncing: sysrq triggered crash` with
  `write_sysrq_trigger` in its stack, which is the second capture the
  criterion asks for.
- **That the two cannot coexist.** The fourth file is the third crash and
  it took zone 0 rather than a free zone, overwriting the first file's
  record on the board. Entry 05 has the reason.
- **That the SysRq path runs without the module.** The fourth file's taint
  field reads `G    B` with no `O`.
- **A second sighting of the firmware warning** at
  `drivers/firmware/raspberrypi.c:69`, and a third of the `hub_port_init`
  KFENCE report, both from the boot that preceded the oops. Journal
  entries 18 and 19 hold the first sightings.

**What is not in them.** No ramoops or pstore probe lines, because those
are printed before the point where these records begin. The zone count is
therefore still unmeasured; entry 05 says so and says where to look.
