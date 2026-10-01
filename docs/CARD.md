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

    sudo ./go card-archive 10-iio-iks4a1 /dev/sdX
    ./go card-archive list

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
