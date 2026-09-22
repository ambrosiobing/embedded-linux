# The descriptor tree, walked

**This is the portfolio piece.** The specification calls it the interview
document, and the reason is that it is the part of USB that host-side
work never shows: what the host actually reads during enumeration, and
why the device can be exactly these three functions and not four.

**Status: NOT YET READ FROM A BOARD.** Every output block below is empty
and marked `NOT YET RUN`. The budget above them is arithmetic and was
written first, on purpose: the specification asks for the budget to be
written **before** the gadget is built and checked against `lsusb -v` at
the end, so that the check is a prediction being tested rather than a
description being copied.

## The budget, written first

The BCM2711's `dwc2` controller has **EP0 plus seven data endpoints**.
EP0 is the bidirectional control endpoint every device has and is not
part of the seven.

| Function | Endpoint | Type | Direction | For |
|---|---|---|---|---|
| `f_ecm` | 1 | interrupt | IN | link up/down notifications |
| | 2 | bulk | IN | frames to the host |
| | 3 | bulk | OUT | frames from the host |
| `f_acm` | 4 | interrupt | IN | serial state: DCD, DSR, ring |
| | 5 | bulk | IN | bytes to the host |
| | 6 | bulk | OUT | bytes from the host |
| `f_hid` | 7 | interrupt | IN | the 8-byte keyboard report |
| | | | | **7 of 7 used, none spare** |

```
  EP0   control       always present, not one of the seven
  EP1   ecm  int  IN   +
  EP2   ecm  bulk IN   |  CDC Ethernet
  EP3   ecm  bulk OUT  +
  EP4   acm  int  IN   +
  EP5   acm  bulk IN   |  CDC ACM
  EP6   acm  bulk OUT  +
  EP7   hid  int  IN   -  the report
        ^
        +-- full. Mass storage needs two more and there are none.
```

### Five interfaces, not three

The count that surprises people, and acceptance criterion 1 checks it.

Each CDC function is a **pair** of interfaces, grouped by an Interface
Association Descriptor so the host binds one driver across both:

| Interface | Class | Belongs to |
|---|---|---|
| 0 | CDC Communications (0x02) | ECM control |
| 1 | CDC Data (0x0a) | ECM data |
| 2 | CDC Communications (0x02) | ACM control |
| 3 | CDC Data (0x0a) | ACM data |
| 4 | HID (0x03) | keyboard |

So: **one device, one configuration, five interfaces, seven endpoints.**
That is the sentence to check the board against.

### Why HID needs only one endpoint

The keyboard sends and never receives on an endpoint of its own. The
host's LED state (Caps Lock, Num Lock) arrives as a **control transfer on
EP0**, a `SET_REPORT` request, not on an interrupt OUT. That is why the
report descriptor has Output items but the budget has no HID OUT
endpoint, and it is the detail that makes the descriptor and the endpoint
count agree.

Reading the LED state back is a stretch goal: `read(2)` on `/dev/hidg0`
returns those reports.

## What to read back, and against what

On a **Linux host**, with the Pi plugged in:

```sh
lsusb -d 1d6b:0104 -v
```

```
NOT YET RUN
```

The four lines worth grepping for, and what each should say:

```sh
lsusb -d 1d6b:0104 -v | grep -E 'bNumInterfaces|bInterfaceClass|bEndpointAddress|MaxPower'
```

```
NOT YET RUN
```

| Field | Expected | Why it matters |
|---|---|---|
| `bNumConfigurations` | 1 | the script builds `configs/c.1` and nothing else |
| `bNumInterfaces` | 5 | two CDC pairs plus HID, see above |
| `bEndpointAddress` count | 7 | the budget, confirmed by the device |
| `MaxPower` | 500 mA | what `configs/c.1/MaxPower` asked for |
| `idVendor:idProduct` | `1d6b:0104` | Linux Foundation, composite gadget |

**`MaxPower` is a request, not a grant.** The device asks; the host may
refuse and many hosts simply do not enforce it. A gadget that asks for
500 mA on a port that supplies 100 is still enumerated, and then browns
out under load, which presents as a board that resets during `iperf3`
rather than as a power problem.

## The three functions from the host's side

### Ethernet

```sh
ip link
nmcli dev status     # or: networkctl status
```

```
NOT YET RUN
```

The interface name is derived from the MAC the gadget hands out, which is
why `host_addr` is **fixed and locally administered** in the script: a
random address every boot means a new interface name every boot, and
every host-side rule that refers to it stops matching.

### Serial

```sh
ls -l /dev/serial/by-id/
```

```
NOT YET RUN
```

Expected to contain `usb-Bench_Pi_4_composite_gadget_bench-0001-if02`.
**The `if02` suffix is the interface number**, and it is the ACM control
interface from the table above. That suffix is the clearest evidence that
the interface numbering came out as predicted.

```sh
picocom -b 115200 /dev/ttyACM0
```

```
NOT YET RUN
```

A login prompt, from `serial-getty@ttyGS0` on the Pi, with no
configuration on the host at all.

### Keyboard

```sh
sudo evtest         # pick the "Bench Pi 4 composite gadget" entry
```

```
NOT YET RUN
```

## On a Windows host

The specification asks for this and it is a real difference rather than a
footnote.

| Function | Windows 11 in-box driver | Works? |
|---|---|---|
| HID keyboard | `kbdhid` / `hidusb` | yes, always |
| CDC ACM | `usbser.sys`, appears as a COM port | yes |
| CDC **ECM** | **none** | **no** |
| CDC **NCM** | `UsbNcm` class driver | yes |

**This is why the script takes `NET=ecm` or `NET=ncm` as an environment
variable rather than as a build option.** The same board on a Linux desk
and on a Windows desk is the same image with a different unit drop-in:

```
systemctl edit bench-gadget.service
[Service]
Environment=NET=ncm
```

RNDIS is the third option, works on Windows, and is deliberately not
offered: it is being retired upstream and it is not a standard class.

A WSL2 shell does **not** see the device unless it is forwarded with
`usbipd-win`. Use the Windows tools for this step rather than debugging
why `lsusb` inside WSL shows nothing.

## What the board should be checked against

Paste the real `lsusb -v` above and then answer these in writing:

1. Is `bNumInterfaces` 5? If it is 3, the Interface Association
   Descriptors are missing and the host has bound one driver per
   interface rather than one per function.
2. Are there exactly 7 `bEndpointAddress` lines? If there are 6, one
   function did not bind, and `dmesg` on the Pi says which.
3. Does the ACM symlink end in `if02`? If it ends in `if00`, the
   functions were linked into the configuration in a different order
   than this document predicts, and every host-side rule that names an
   interface number needs revisiting.

**Where the board disagrees with this document, the document is what
needs correcting.** It was written from the specification and from the
Kconfig, not from a device, and that is exactly the kind of claim this
repository has been wrong about before.

---

Back to [DESIGN.md](DESIGN.md), the [bring-up notes](BRINGUP.md), or the
[project README](../README.md).
