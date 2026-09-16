# Design, Project 04

The four figures this project is specified by, plus the tables behind them.
This is the methodology: what the components are, which of them owns what,
and how a boot and a test run each travel through the system. What happened
while building it is the [journal](../JOURNAL.md); why each choice was made
rather than its alternative is
[DECISIONS](../../../walkthrough/DECISIONS.md).

Drawn as text on purpose, the same as the other projects: diagrams here
survive a diff, can be grepped, and need no build step. Everything needed to
read them is in this file.

**This project's product is a lab rather than a device.** That is what makes
it different from every other project in the repository, and it shows up in
the layout: most of what Project 4 adds is not a Yocto recipe. One kernel
fragment and one image go in `meta-bench`; the server configuration and the
test runner are plain files under `projects/04-netboot-hil/`, because they
run on a machine this repository does not build.

---

## Figure 1: System architecture

Two boards and one cable. The left column is the server, the right column
is the device under test, and every arrow between them is one of four
protocols.

```
  WSL2 host                                     server: Raspberry Pi 4
  +------------------+                          +--------------------------------+
  | Project 1 build  |                          | dnsmasq                        |
  | bench-image      |---- rsync, deploy.sh --->|  DHCP (or proxy) + TFTP        |
  | boot files       |                          |  /srv/tftp                     |
  | rootfs tarball   |                          +--------------------------------+
  +------------------+                          | nfs-kernel-server              |
                                                |  /srv/nfs/dut3, NFS v3         |
  operator                                      +--------------------------------+
  +------------------+   ssh over Wi-Fi         | ser2net                        |
  | laptop           |------------------------->|  tcp 4003 <-> /dev/tty-dut3    |
  | telnet :4003     |                          +--------------------------------+
  +------------------+                          | pytest runner                  |
                                                |  conftest, tests, JUnit XML    |
                                                +--------------------------------+
                                                | GPIO23 in, LEDs out (deferred) |
                                                +----+-------+-------+-----------+
                                                     |       |       |
                              Ethernet, direct cable |       | USB   | GPIO
                                     192.168.7.0/24  |       | TTL   | loopback
                                                     v       v       v
                                                +--------------------------------+
                                                | DUT: Raspberry Pi 3B+          |
                                                |  no microSD card at all        |
                                                +--------------------------------+
                                                | boot ROM in OTP                |
                                                |  DHCP discover, PXE class      |
                                                |  TFTP bootcode.bin             |
                                                +--------------------------------+
                                                | firmware: start.elf, config.txt|
                                                +--------------------------------+
                                                | kernel: ip=dhcp, nfsroot       |
                                                +--------------------------------+
                                                | systemd, getty on serial0      |
                                                +--------------------------------+
                                                | GPIO17 out, loopback wire      |
                                                +--------------------------------+
```

What is ours and what is not:

| Component | Who wrote it | Why it is here |
|---|---|---|
| dnsmasq, nfs-kernel-server, ser2net | Upstream, on Raspberry Pi OS | DHCP, TFTP, NFS and console sharing. No code of ours serves a single byte of the boot |
| pytest | Upstream | The runner is fixtures and assertions, not a framework of our own |
| `server/` configuration | This project | The four files that turn a Pi into this lab, plus an installer |
| `runner/` | This project | A console helper, fixtures, and tests that read like a checklist |
| `netboot.cfg` | This project | The six kernel options a diskless root needs |
| `bench-netboot-image` | This project | The DUT image, in a form NFS and TFTP can consume |

The ratio is the point. A hardware in the loop lab is mostly configuration,
and the parts worth writing are the console helper and the fixtures.

---

## Figure 2: Wiring and schematic

Four connections between the boards, and one of them is a ground wire that
is not optional.

```
  server: Raspberry Pi 4                        DUT: Raspberry Pi 3B+
  +---------------------------+                 +---------------------------+
  |                           |                 |                           |
  | pin 16 GPIO23  <----------|--[ 1k ]---------|---- pin 11 GPIO17         |
  |                (loopback in)                |         (loopback out)    |
  |                           |                 |                           |
  | pin 14 GND     <==========|=================|==== pin 9  GND            |
  |                (common ground, mandatory)   |                           |
  |                           |                 |                           |
  | RJ45  <===================|=================|==== RJ45                  |
  |         direct cable, 192.168.7.1 / .10     |                           |
  |                           |                 |                           |
  | USB-A  <-- USB/TTL cable -----------------> |---- pin 8  GPIO14 TXD     |
  |            white RX, green TX, black GND    |---- pin 10 GPIO15 RXD     |
  |            red 5 V LEFT OPEN                |---- pin 6  GND            |
  |                           |                 |                           |
  | pin 13 GPIO27 ---[330]---|>|--- GND   yellow, running   DEFERRED        |
  | pin 11 GPIO17 ---[330]---|>|--- GND   green,  pass      DEFERRED        |
  | pin 15 GPIO22 ---[330]---|>|--- GND   red,    fail      DEFERRED        |
  +---------------------------+                 +---------------------------+
```

| Signal | DUT pin | Server pin | Note |
|---|---|---|---|
| Console TXD | 8, GPIO14 | USB port, cable white lead | 115200 8N1 |
| Console RXD | 10, GPIO15 | USB port, cable green lead | |
| Console GND | 6 | cable black lead | The red 5 V lead stays open |
| Loopback | 11, GPIO17 | 16, GPIO23 | 1 kOhm in series |
| Common ground | 9 | 14 | One jumper wire, and it is not optional |
| Ethernet | RJ45 | RJ45 | Direct cable, both ends auto-crossover |
| Yellow LED | | 13, GPIO27 | Deferred, see below |
| Green LED | | 11, GPIO17 | Deferred |
| Red LED | | 15, GPIO22 | Deferred |

**The series resistor** limits current if both boards ever drive the line as
outputs. Both are 3.3 V parts, so there is no level shifting to do, but a
software mistake that makes GPIO23 an output while the DUT drives GPIO17 is
a short between two pins without it.

**The ground wire is the one people skip.** Two boards on separate supplies
with no common ground give a loopback signal that floats, and a floating
input reads correctly often enough to look like it works. That is worse than
failing. It is in the specification's pitfalls for the same reason.

**The red 5 V lead of the USB/TTL cable is never connected.** Both boards
have their own supply, and two supplies back-feeding through a serial cable
is the ordinary way to reset a board in the middle of a boot.

**The LEDs are deferred.** The bench's LED parts are Joy-IT LinkerKit
LK-LED10 modules with a 2.0 mm socket, which standard 2.54 mm jumper wires
cannot mate with. This is the same blocker Project 1 recorded, and the
runner is written so the indication is optional rather than assumed: pass
and fail are the pytest exit status, the JUnit XML and the console log,
which is what a CI system reads anyway.

---

## Figure 3: Bench layout

The specification draws both boards plugged into a router. This bench has no
router and no wired modem at all, so it uses the other topology the
specification provides: a direct cable, with the server acting as the DHCP
server rather than a proxy.

```
        Wi-Fi: Android phone hotspot
        (the operator reaches the server this way)
                     :
                     :  ssh, telnet 4003
                     v
    +--------------------------------+          +---------------------------+
    |     Raspberry Pi 4  (server)   |          |  Raspberry Pi 3B+  (DUT)  |
    |                                |          |                           |
    |  eth0  192.168.7.1/24          |==========|  eth0  192.168.7.10, DHCP |
    |  wlan0 to the phone hotspot    |  RJ45    |                           |
    |                                |  direct  |  NO microSD CARD          |
    |  USB-A ------------------------|--TTL-----|  pins 8, 10, 6            |
    |  GPIO23 <---------[1k]---------|----------|  GPIO17                   |
    |  GND    <======================|==========|  GND                      |
    +-------------+------------------+          +-------------+-------------+
          |                                                   |
      USB-C 5V 3A                                        micro USB 5V
```

Three things about this layout are worth saying out loud.

**The DUT has no card in it.** That is not a detail, it is the whole point:
the boot ROM in OTP is the only thing on the board that runs before the
network does. If a card is left in, the board boots from it and the lab
proves nothing.

**The server needs both its interfaces.** `eth0` is the lab network and has
a static address; `wlan0` is how a human reaches the server at all. Losing
the second one means walking to the board with a keyboard.

**Nothing here reaches the internet.** `192.168.7.0/24` is an island with
two hosts on it. The server's `dnsmasq` runs with `port=0`, so it is a DHCP
and TFTP server and not a resolver, and the DUT gets no default route and no
DNS. A test that needs to fetch something from the internet will not work,
and that is the correct shape for a lab.

---

## Figure 4: One automated run, as a sequence

```mermaid
sequenceDiagram
    participant R as pytest runner
    participant D as deploy.sh
    participant C as DUT console
    participant B as boot ROM + firmware
    participant S as dnsmasq + nfsd
    participant K as kernel + systemd

    R->>D: deploy the build
    D->>S: rsync boot files to /srv/tftp, rootfs to /srv/nfs
    D-->>R: done
    Note over R: yellow LED, if one is wired
    R->>C: "sudo reboot"
    C->>B: reset
    B->>S: DHCP discover, PXE vendor class
    S-->>B: offer, option 43 "Raspberry Pi Boot", TFTP address
    B->>S: TFTP bootcode.bin, start.elf, config.txt, kernel, dtb
    B->>K: start the kernel
    K->>S: ip=dhcp, then mount /srv/nfs/dut3 over NFS v3
    K-->>C: "Mounted root (nfs filesystem)", then "login:"
    R->>C: log in, then command plus a unique end marker
    C->>K: over serial0
    K-->>C: output, exit status
    C-->>R: return code and body
    Note over R: repeat for every test; read GPIO23 for the loopback;<br/>green or red at session end
```

Two properties of this sequence are the reason the runner is shaped the way
it is.

**The reboot is soft, and that is a limitation rather than a design.** The
bench has no relay, no switched USB hub and no smart plug, so the runner
asks the DUT to reboot over its own console. This works because the boot ROM
runs on every reset, so a soft reboot re-enters network boot. It does not
work when the DUT is wedged badly enough not to answer, and then the runner
prints a line asking for the plug to be pulled. That manual step is counted
in the run log rather than hidden.

**Every command carries its own end marker.** A serial console has no
framing: output arrives as a stream and a prompt is just some characters
that usually appear at the end. `run()` appends `echo __END_<timestamp>__ $?`
to every command and reads until that exact string, which gives both a
reliable end of output and the exit status. Matching on a prompt instead is
the classic way to write a console helper that works until a command prints
something that looks like a prompt.

---

## Data flow

```
  WSL2 host          server: Raspberry Pi 4                       DUT: Raspberry Pi 3B+
  +-----------+      +------------------------------------+       +---------------------+
  | Project 1 |      | /srv/tftp/<serial>/ firmware+kernel|       | boot ROM (OTP)      |
  | build     |rsync | /srv/nfs/dut3/      rootfs         |       |  DHCP discover, PXE |
  +-----------+----->|                                    |<------|  vendor class       |
                     | dnsmasq: DHCP + TFTP               |------>|  option 43, TFTP    |
                     |                                    |------>|  bootcode.bin ...   |
                     | nfsd: /srv/nfs/dut3 (NFS v3)       |<=====>|  kernel: nfsroot    |
                     |                                    |       |  systemd, getty     |
                     | ser2net :4003 <- /dev/tty-dut3     |<-TTL--|  serial0 console    |
                     |   ^ socket://localhost:4003        |       |                     |
                     | pytest runner (Console fixture)    |<------|  GPIO17 (loopback)  |
                     |   -> LEDs, if wired                | GPIO23|                     |
                     +------------------------------------+       +---------------------+
```

---

## Who owns what

The commonest way to break a lab is to give one resource two owners. This
table is the answer to "why did the console go quiet" and "why did the DUT
stop booting".

| Resource | Owner | What must not also touch it |
|---|---|---|
| `/dev/tty-dut3` | `ser2net` | A human running `picocom` or `minicom` on the device node. Attach to `telnet localhost 4003` instead, which is what the multiplexing is for |
| TCP 4003 | `ser2net` | Two test runs at once. `kickolduser: true` means the newer connection wins rather than both getting half the bytes |
| `eth0` on the server | A static address, set once | NetworkManager or `dhcpcd` also managing it. On Raspberry Pi OS that means telling the one in use to leave it alone |
| DHCP on 192.168.7.0/24 | `dnsmasq` on the server | Any other DHCP server. This is why the direct cable topology is simpler than the router one: there is nothing else on the wire |
| `/srv/nfs/dut3` | `nfsd`, exported to the DUT | `deploy.sh` rsyncing into it while the DUT has it mounted. Deploy happens before the reboot, never during a run |
| `/srv/tftp` | `dnsmasq` | The same |
| GPIO23 on the server | The runner, as an input | Anything that makes it an output. That is what the series resistor protects against |
| GPIO17 on the DUT | The test, as an output | The server's own GPIO17, which is a different pin on a different board and happens to be the green LED line. Two boards, two GPIO17s, one wiring table |

That last row is a trap the numbering creates: the specification uses
GPIO17 on the DUT for the loopback and GPIO17 on the server for the green
LED. They are unrelated pins that share a number, and any sentence about
"GPIO17" has to say which board.

---

## The boot chain, in the order the DUT does it

Knowing this sequence is what makes the dnsmasq log readable, and reading
that log is how every failure in this project gets diagnosed.

| Step | What happens | Where it shows |
|---|---|---|
| 1 | Boot ROM broadcasts DHCP discover with a PXE vendor class | `dnsmasq` log, `DHCPDISCOVER` |
| 2 | dnsmasq answers with an address, option 43 `Raspberry Pi Boot`, and its own address as TFTP server | `DHCPOFFER`, and `tcpdump -v` if the ROM ignores it |
| 3 | ROM fetches `bootcode.bin` **from the TFTP root**, not from the serial directory | `TFTP sent /srv/tftp/bootcode.bin` |
| 4 | `bootcode.bin` fetches `start.elf`, `fixup.dat`, `config.txt`, first from `/srv/tftp/<serial>/` then from the root | A run of `TFTP sent` lines |
| 5 | Firmware reads `config.txt` and `cmdline.txt`, loads the kernel and the device tree | The console goes from silent to kernel output |
| 6 | Kernel brings up `eth0` with `ip=dhcp`, which is a second DHCP exchange | Another `DHCPDISCOVER` in the log, from the kernel this time |
| 7 | Kernel mounts the NFS export as root | `VFS: Mounted root (nfs filesystem)` |
| 8 | systemd starts, `getty` opens `serial0` | `login:` on the console |

**Step 3 is the one that catches people.** `bootcode.bin` must be in the
TFTP root even when everything else lives in the serial-numbered directory,
because the ROM asks for it before it knows anything about itself.

**Step 6 is a second DHCP exchange**, not a continuation of the first. The
ROM's lease is not handed to the kernel. Seeing two discovers in the log is
correct, and seeing only one means the kernel's network did not come up.

---

## What the kernel has to provide

Six options, in `meta-bench/recipes-kernel/linux/files/netboot.cfg`. Every
one of them was checked against the kernel's own Kconfig in 6.6 rather than
written from memory, which is the discipline journal entry 17 of Project 15
bought.

```
CONFIG_NFS_FS=y          must be =y, not =m: ROOT_NFS depends on NFS_FS=y
CONFIG_NFS_V3=y          nfsroot handles v3 best
CONFIG_ROOT_NFS=y        depends on NFS_FS=y && IP_PNP
CONFIG_IP_PNP=y          kernel-level IP autoconfiguration
CONFIG_IP_PNP_DHCP=y     depends on IP_PNP
CONFIG_USB_LAN78XX=y     the 3B+ Ethernet, and it must be built in
```

**Two of these are `=y` for a reason that is the same reason twice.** A
module lives in the root filesystem. The root filesystem is on the network.
The network needs the driver. `CONFIG_USB_LAN78XX=m` produces a kernel that
cannot reach the module it needs in order to reach the modules, and the
board stops with a message about being unable to mount root. `ROOT_NFS`
states its half of this in its own `depends on NFS_FS=y`, which is unusual
enough in Kconfig to be worth noticing: it is the only way to say "this one
cannot be a module".

The Pi 3B+ Ethernet is `lan78xx` and it is USB attached, which is why a
wired Pi 3B+ also needs the USB host controller built in. That comes from
the `raspberrypi3-64` machine configuration already.

---

## Why the server runs Raspberry Pi OS

Every other project in this repository builds its own image. This one does
not, for the server.

The specification says Raspberry Pi OS Lite, and the reason is that the
server is not the product. It is the instrument. dnsmasq, NFS and ser2net on
a distribution take ten minutes to install and are configured by four files
that live in this repository, which is what `server/install.sh` does. The
same lab built as a Yocto image would be a week of `PACKAGECONFIG` work to
produce something nobody measures.

The DUT is the opposite: it boots **our** image, and that is the whole point
of the lab. A build from Project 1 or any later project is one `rsync` away
from running on real hardware.

Building a `bench-lab-image` is a legitimate stretch goal and is recorded as
one. It would matter the day the lab itself needs to be reproducible from
source, which is a different project from the one specified here.

---

Design first, then the [bring-up](BRINGUP.md), then
[netboot-flow.md](netboot-flow.md) for the protocol traces and
[run-log-20-boots.txt](run-log-20-boots.txt) for the evidence.
