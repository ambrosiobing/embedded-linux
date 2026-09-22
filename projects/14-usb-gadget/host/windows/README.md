# The Windows host side

**Nothing is installed on Windows.** All three functions are standard
classes with in-box drivers, which is the point of using CDC and
boot-protocol HID rather than anything custom. This document says which
driver binds to what, and the one thing that genuinely does not work.

**Status: NOT YET SEEN.** No board has enumerated on a Windows machine.
The table below is what the specification and the class definitions say
should happen, and it is written as a prediction to be checked.

## What Device Manager should show

| Function | Appears under | In-box driver | Works? |
|---|---|---|---|
| HID keyboard | Keyboards | `kbdhid` / `hidusb` | yes, always |
| CDC ACM | Ports (COM & LPT), as a COM port | `usbser.sys` | yes |
| CDC **NCM** | Network adapters | `UsbNcm` class driver | yes |
| CDC **ECM** | shows as an unknown device | **none** | **no** |

## The one thing that does not work, and the fix

**Windows has no in-box ECM driver.** It has never had one. A gadget
built with `NET=ecm` enumerates on Windows with a working keyboard, a
working COM port, and a network interface that stays an unrecognised
device in Device Manager.

That is not a fault to debug. It is a missing class driver, and the fix
is to build the gadget with the class Windows does support.

**On the board over the picocom console:**

```sh
systemctl edit bench-gadget.service
```

Add:

```
[Service]
Environment=NET=ncm
```

Then:

```sh
systemctl restart bench-gadget.service
```

This is why `NET` is an environment variable on the unit rather than a
build-time option: **the same image goes to a Linux desk and a Windows
desk, and only the drop-in differs.**

### Why not RNDIS

RNDIS works on Windows without a drop-in and is deliberately not offered.
It is a Microsoft protocol rather than a USB class, it is being retired
upstream, and newer Windows builds have restricted it for security
reasons. NCM is the standard and is the right thing to learn.

## Checking it

Windows has no `lsusb`. The equivalents:

```
Device Manager, View > Devices by connection
```

shows the composite device with its three child functions, which is the
closest thing to the interface tree that `lsusb -v` prints.

```
pnputil /enum-devices /connected
```

lists the bound drivers from a command prompt.

The COM port number is assigned by Windows and is not stable across
ports; Device Manager under **Ports (COM & LPT)** is where to read it.
There is no Windows equivalent of the `/dev/pi-console` symlink that
`70-pi-gadget.rules` gives on Linux.

## WSL2 does not see the device

A WSL2 shell has no USB access of its own. `lsusb` inside WSL will not
show the gadget no matter what is plugged in, and that is not a symptom
of anything being wrong.

To reach it from WSL the device has to be forwarded explicitly with
[usbipd-win](https://github.com/dorssel/usbipd-win). For this project
that is rarely worth it: **use the Windows tools for the Windows checks**
and the Pi's own serial console for everything else.

This matters on this bench specifically, because the build laptop is WSL
and the instinct is to check from there.

## What to capture as evidence

A Device Manager screenshot with all three functions bound goes in
[`../../docs/evidence/`](../../docs/evidence/) as `device-manager.png`.
It is the one piece of evidence in this project that cannot be text.
