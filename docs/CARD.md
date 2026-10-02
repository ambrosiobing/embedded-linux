# Preparing a microSD card on the win11 aquamarine authoring laptop

Every board project in this repository starts with a card, and the card is
prepared on the same laptop each time. The sequence below is written out
because on Wednesday 30 September 2026 it took about an hour, and every
minute of that went to one question that no document here answered: which
side of the machine currently owns the card reader.

Nothing in this document is specific to one project. The image differs, the
procedure does not.

## 0. Which side owns the reader

**Check this first, before Raspberry Pi Imager is even opened.** The reader
on this laptop is bound to `usbipd`, so it can belong either to Windows or
to WSL, and the two cases look nothing alike:

| Owner | Imager sees the card | Windows drive letter | WSL sees the card |
|---|---|---|---|
| Windows | yes | yes | only through `/mnt/<letter>` with a drvfs mount |
| WSL | **no** | **no** | yes, as a raw block device such as `/dev/sdf` |

The failure this produces is silent and misleading. With the reader
attached to WSL, `Get-Volume` lists only the system drive and the recovery
partition, no drive letter appears, a drvfs probe across letters D to I
finds nothing, and Imager has no destination to offer. Every one of those
readings is correct and none of them says why.

```powershell
cd C:\
usbipd list
```

`Shared` means Windows owns it and it can be attached. `Attached` means WSL
owns it. To hand it back to Windows for flashing:

```powershell
cd C:\
usbipd detach --busid 6-4
```

The bus id is the one the listing gives for the mass storage device. On
this laptop it has been 6-4, and the USB/TTL cable has been 5-2, but a bus
id is a property of which socket a thing is plugged into and must be read
rather than remembered.

## 1. Writing the image

Raspberry Pi Imager, on Windows, with the reader on the Windows side.

**Fill in the settings panel before writing, not after.** It is the only
convenient moment. Set the hostname, enable ssh with a password, set the
username and password, and enter the Wi-Fi name, password and country.

That panel is what decides whether the board is reachable at all. With it
filled in, the board joins the network on first boot and `ssh` is enough.
Without it, the board comes up with no account and no network, and the only
way in is the serial console, which on this laptop means the WSL route
described in Project 1's bring-up document because the Renkforce cable is a
PL2303HXA that the current Prolific Windows driver refuses to drive.

See [[bench-card-credentials-before-eject]]: offer to write the credentials
before the card leaves the reader, every time.

**Imager ejects the card when it finishes verifying.** After that Windows
has dismounted it and no drive letter exists, which reads exactly like a
failed write. Reseat the card in the reader, or replug the reader, and the
letter comes back.

## 2. Editing the boot partition before first boot

Only the FAT boot partition is visible from either side. The ext4 root
filesystem is not, which is expected and does not matter, because
everything worth setting before the first boot is on the boot partition.

**Identify it by content, not by label.** Recent Raspberry Pi OS labels it
`bootfs`, older images label it `boot`, and some cards carry no label at
all. The signature that never lies is `config.txt` beside `cmdline.txt`.
No other partition on this laptop has both.

From WSL with the reader attached, which is the shortest path and needs no
drive letters:

```sh
lsblk                                  # the card is the disk that is not sda, sdb, sdc or sdd
sudo mount /dev/sdf1 /mnt/boot         # partition 1 is the FAT boot partition
ls -1 /mnt/boot                        # expect config.txt and cmdline.txt
```

A reader with no card in it appears in `lsblk` at size `0B`. That is not a
fault and not a permissions problem. It means the slot is empty.

From Windows, or from WSL through drvfs, the same partition is at a drive
letter and `sudo mount -t drvfs E: /mnt/boot` reaches it.

**Turning on a bus before the first boot** saves a `raspi-config` round trip
and a reboot:

```sh
grep -n i2c /mnt/boot/config.txt                        # shipped commented out
echo 'dtparam=i2c_arm=on' | sudo tee -a /mnt/boot/config.txt
tail -n 5 /mnt/boot/config.txt                          # confirm it is on its own line
```

The read-back is not ceremony, and it checks two different things.

An append joins the previous line when the file does not end in a newline,
and a `dtparam` glued to the end of another directive is ignored without
complaint.

**Worse, and easier to miss: `config.txt` is divided into conditional
sections.** A Raspberry Pi OS `config.txt` ends with per-model blocks such
as `[pi4]`, `[pi5]` and `[all]`, and every directive belongs to whichever
section header precedes it. An appended line therefore inherits the last
section in the file. If that is `[all]` the setting applies to every board
and all is well. If the file happens to end inside `[pi5]`, the same line
applies only to a Pi 5 and does nothing at all on a Pi 3B+, with no error
anywhere.

So `tail -n 5 config.txt` is read for the section header above the new
line, not only for the line itself:

```
[all]
dtparam=i2c_arm=on        <- applies to every board, correct
```

```
[pi5]
dtparam=i2c_arm=on        <- applies to a Pi 5 only, silently wrong here
```

When the tail shows the wrong section, append `[all]` on its own line
before the directive rather than moving the directive.

**Confirm the credentials are on the card** while it is still in the reader:

```sh
ls -1 /mnt/boot
```

A `custom.toml`, or a `firstrun.sh` beside a `userconf.txt`, means Imager
wrote them. None of those means the card will boot to something you cannot
log into, and rewriting it now costs minutes rather than an evening.

**Unmount before pulling the card**, so the write is flushed:

```sh
sudo umount /mnt/boot
```

## 3. After the first boot

With the credentials written, the board is on the network and `ssh` reaches
it. The serial console is the tool for a board that does not boot, not the
tool for a board that has not been tried yet.

## 4. Keeping a copy of a card before it is reused

This bench has one card, so every project that wants it takes it from
another one. A card written by Imager and then left alone can be made again
from the same image file. A card that has been worked on cannot.

    sudo -v
    nohup sudo BENCH_IMAGE_DIR=<store> sh scripts/card-archive.sh <project> /dev/sdX > ~/card-archive.log 2>&1 &
    tail -f ~/card-archive.log
    ./go card-archive list

**Launch it with `nohup`, not in a foreground shell.** It reads the card
twice, which on a reader giving 15 MB/s is about forty minutes for a 16 GB
card, and a foreground run dies with its terminal. On Thursday 1 October
2026 the first real run was killed at forty-two per cent by a closed tab,
and the `sudo -v` is there because a backgrounded `sudo` cannot show a
password prompt. **Do not let the laptop sleep either**, because suspending
it drops the usbipd attachment and the card disappears mid-read.

**`nohup` is not enough on WSL.** On Friday 2 October 2026 a nohup'd run died
anyway, and `wsl -l -v` reported the Ubuntu distro `Stopped` with `usbipd
list` showing the reader back at `Shared`. nohup blocks SIGHUP from a
terminal; it cannot keep a process alive when the virtual machine hosting it
stops. Closing the terminal, `wsl --shutdown`, a `Stop-Process` on `wsl.exe`
and WSL's own idle timeout all end the run, and the single `Stopped` line does
not say which happened. So leave the WSL window open and untouched for the
whole read, and monitor from PowerShell instead, which needs no WSL session at
all because the image is being written to a path on `C:`:

    Get-ChildItem Desktop\embedded-linux-bench\images\<project>-card\<stamp> | Select-Object Name,Length,LastWriteTime

Checking from inside WSL is actively worse: re-entering a stopped distro
starts it, which destroys the evidence of whether it had stopped. Run
`wsl -l -v` from PowerShell first.

**The size plateaus long before the read ends, and that is not a stall.** The
written data sits near the front of the card and the rest is unwritten ext4
free space that gzip collapses to nothing, so on Friday 2 October 2026 the
file reached 1,547,436,032 bytes with seven minutes of reading still to go.
That figure is within 786,432 bytes of 1,546,649,600, the size of the fragment
abandoned on Thursday 1 October 2026. The discriminator is `.dd.log`, whose size and timestamp
keep advancing in both cases.

A killed run leaves `<name>.img.gz.partial`, which is not an archive and
cannot be read as one. That naming exists because the first interrupted run
left a 1.55 GB file with an archive's exact name and no records beside it,
and the card was an hour from being overwritten on the strength of it.
**An archive is finished when `PROVENANCE.txt` and `SHA256SUMS` are both
there and `sha256sum -c SHA256SUMS` says `OK`.** Nothing less counts, and
the image file alone counts least of all.

The device letter is read fresh every time. The same reader on the same
laptop came back as `sdf` and then as `sde` within the hour, because a
usbipd re-attach does not reclaim the letter it had.

**Turn off USB power saving before a long read, or it will not finish.**
Two attempts died at 448 and 496 seconds against a pass needing 828, both
without an I/O error, with `usbipd list` still showing the reader under
Connected and its state back to `Shared`. The device was never lost to
Windows, only to WSL. One setting fixed it, and it has TWO values:

    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setactive SCHEME_CURRENT

**Thursday 1 October 2026 set only the AC value, and that was found out on
Friday 2 October 2026.** `/setacvalueindex` writes the mains value alone, so
the battery value stayed at `Enabled` and the whole remedy depended on nobody
unplugging the laptop, which was written down nowhere. Read both back before
a long run and want `0x00000000` twice:

    powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226

plus clearing **Allow the computer to turn off this device to save power**
on every USB Root Hub and Generic USB Hub in Device Manager. The throughput
is the corroboration: 15 and 16 MB/s on the attempts that died, 19 MB/s on
the one that finished. A link being periodically told to power down is
slower before it is cut.

`usbipd attach --wsl --busid <BUSID> --auto-attach` is worth running anyway,
because it re-attaches within seconds of the device reappearing. It cannot
rescue a read in flight: the file descriptor dies with the device and `dd`
has already failed by the time it is back.

**The size of a card image says nothing about whether it is complete.** A
run killed at 42 per cent produced 1,546,649,600 bytes and the finished one
produced 1,562,322,561, one per cent apart, because the written data is near
the front of the card and the rest is unwritten ext4 free space that gzip
collapses to nothing. `du -h` prints `1.5G` for both. That is why the
records are the definition above and not the image.

When a run has been left with the end-to-end comparison skipped, it can be
settled later without re-archiving:

    sudo scripts/card-archive.sh verify <store dir> /dev/sdX

It checks that the stored image still hashes to its own record, which tells a
damaged archive apart from a changed card, and then that the card hashes to
the same value. The result is appended to `PROVENANCE.txt` with the date and
a statement that it was not part of the original run.

The reader is on the WSL side for this, attached with `usbipd`, and nothing
on the card may be mounted: a filesystem being written to images
inconsistently. The program refuses rather than guessing, and the four
refusals are worth knowing before the card is in the reader, because each
one is a mistake that reads like something else:

- the disk carrying the running root filesystem, which is the laptop
- any device with a mounted filesystem on it
- anything larger than 128 GB, which is a system disk and not a card
- anything with no `config.txt` on its first partition, which is not a
  Raspberry Pi card at all

It reads the card twice. The first pass writes the image, the second reads
the card again and compares, because a hash of what was just written proves
only that the gzip stream is complete. Fifteen minutes becomes thirty, and
`BENCH_CARD_SKIP_VERIFY=1` turns the second pass off and says so in the
`PROVENANCE.txt` rather than leaving an unverified archive looking verified.

**This is not `./go archive`, and the difference is the rebuild line.**
`./go archive` keeps a built image whose provenance ends in one `git
checkout` and one `kas build`. A card image has no such line: what is on it
was done by hand and the `PROVENANCE.txt` says so. The store keeps them
side by side, with `-card` on the directory name, because they are put back
by different tools.

The result is a `.img.gz`, which Raspberry Pi Imager reads without
unpacking. Choose Operating System, then Use custom. **Do not let Imager
apply its OS customisation to a card image**: the hostname, the user and the
ssh keys are already inside it, and the customisation rewrites them on first
boot.

## What this document is for

Three of the traps above cost real time on Wednesday 30 September 2026 and
none of them is discoverable from the symptom:

1. A reader attached to WSL is invisible to Windows, and every Windows
   query returns a correct, unhelpful answer.
2. Imager ejects the card on completion, so the drive letter disappears at
   exactly the moment the card is finished and wanted.
3. A reader with no card reads `0B` rather than reporting an empty slot.

None of them is a fault in any tool. Each is a state that looks like a
fault, and the cost of each is the time spent looking in the wrong place.
