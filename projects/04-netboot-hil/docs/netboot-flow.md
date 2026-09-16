# The boot, protocol by protocol

Reading this is how every failure in Project 4 gets diagnosed. A board that
will not netboot is silent, has no console output to read, and no state on
it to inspect, so the only evidence is on the server: the dnsmasq journal,
a packet capture, and the NFS server's own counters.

Nothing below has been captured on this bench yet. The excerpts are what
each step looks like, marked as such; the real transcripts replace them
once the lab runs, and that replacement is part of the acceptance criteria
rather than a nicety.

## The two commands to have open

```bash
journalctl -fu dnsmasq
```

```bash
sudo tcpdump -i eth0 -n -v port 67 or port 68 or port 69
```

The first shows what dnsmasq decided. The second shows what actually went
on the wire, which is the one that settles arguments about option 43.

## Step 1 and 2: the boot ROM asks, dnsmasq answers

A few seconds after power, the ROM broadcasts a DHCP discover carrying a
PXE vendor class. The interesting part of the answer is not the address.

```
dnsmasq-dhcp[...]: DHCPDISCOVER(eth0) b8:27:eb:xx:xx:xx
dnsmasq-dhcp[...]: tags: eth0
dnsmasq-dhcp[...]: DHCPOFFER(eth0) 192.168.7.10 b8:27:eb:xx:xx:xx
dnsmasq-dhcp[...]: requested options: 43:vendor-encap, 60:vendor-class
dnsmasq-dhcp[...]: next server: 192.168.7.1
dnsmasq-dhcp[...]: sent size: 17 option: 43 vendor-encap ...
```

**What has to be true.** Option 43 must carry the string
`Raspberry Pi Boot`, and `next server` must be the server's address. The
ROM ignores an offer without option 43 and it does so silently: no log line,
no retry message, just a board that sits dark.

If the journal shows the offer and the board still does nothing, look at the
wire:

```bash
sudo tcpdump -i eth0 -n -v port 67 | grep -A5 'Vendor-Option'
```

Very old bootcode versions wanted the string with three trailing spaces.
That is worth knowing and almost never the cause now.

**The commonest failure here is not a configuration mistake.** The ROM does
not retry forever. If dnsmasq is restarting, or the server is busy enough to
answer late, the ROM gives up. A board that boots on the second try and not
the first is usually this rather than anything intermittent in the wiring.

## Step 3: bootcode.bin, from the root

```
dnsmasq-tftp[...]: sent /srv/tftp/bootcode.bin to 192.168.7.10
```

**`bootcode.bin` is fetched from the TFTP root, never from the serial
directory.** The ROM asks for it before it knows anything about itself, so a
copy inside `/srv/tftp/<serial>/` alone is never found. `deploy.sh` copies
it to both places for this reason and says so at the line that does it.

## Step 4: the firmware fetches the rest

```
dnsmasq-tftp[...]: sent /srv/tftp/<serial>/start.elf to 192.168.7.10
dnsmasq-tftp[...]: sent /srv/tftp/<serial>/fixup.dat to 192.168.7.10
dnsmasq-tftp[...]: sent /srv/tftp/<serial>/config.txt to 192.168.7.10
dnsmasq-tftp[...]: sent /srv/tftp/<serial>/cmdline.txt to 192.168.7.10
dnsmasq-tftp[...]: sent /srv/tftp/<serial>/bcm2710-rpi-3-b-plus.dtb to ...
dnsmasq-tftp[...]: sent /srv/tftp/<serial>/kernel8.img to 192.168.7.10
```

A `file not found` line here is the good case: it names exactly what is
missing. Expect a few of them even on a healthy boot, because the firmware
probes for files that legitimately do not exist.

The serial number is the last eight hex digits of the `Serial` line in the
DUT's `/proc/cpuinfo`, read once from a normal SD boot. Without a
serial-numbered directory everything is served from the root, which works
for exactly one DUT.

## Step 5: the console wakes up

Until now the console has been silent, because nothing has been running.
The firmware does not print. The first output is the kernel, and its arrival
is the boundary between "the network boot worked" and "the kernel is now
the problem".

## Step 6: a second DHCP exchange

```
dnsmasq-dhcp[...]: DHCPDISCOVER(eth0) b8:27:eb:xx:xx:xx
dnsmasq-dhcp[...]: DHCPREQUEST(eth0) 192.168.7.10 b8:27:eb:xx:xx:xx
dnsmasq-dhcp[...]: DHCPACK(eth0) 192.168.7.10 b8:27:eb:xx:xx:xx
```

**This is not a retry.** The boot ROM's lease is not handed to the kernel,
so the kernel's `ip=dhcp` does its own exchange. Two discovers in the log is
correct. One means the kernel's network never came up, which on a 3B+ means
`CONFIG_USB_LAN78XX` was not built in.

On the console:

```
IP-Config: Complete:
     device=eth0, hwaddr=b8:27:eb:xx:xx:xx, ipaddr=192.168.7.10,
     mask=255.255.255.0, gw=255.255.255.255
```

## Step 7: the root filesystem

```
VFS: Mounted root (nfs filesystem) on device 0:15.
```

That line is what the test fixture waits for. Before it, everything is
firmware and kernel; after it, the image under test is running.

On the server:

```bash
nfsstat -s
```

The failures here are specific and each has one cause:

| Console says | Cause |
|---|---|
| `Unable to mount root fs on unknown-block(0,0)` | The kernel has no NFS root support, or no network. Check the fragment reached the `.config` |
| `nfs: server 192.168.7.1 not responding` | The export is not reachable. `showmount -e localhost` on the server |
| `mount: permission denied` | The export does not name the DUT's subnet, or `no_root_squash` is missing |
| Boots, then stops a second later | The interface was reconfigured out from under the mount. See `10-eth0-netboot.network` and its `KeepConfiguration=yes` |

That last one is worth expanding because it is the least obvious. The kernel
configured `eth0` and mounted root over it; then systemd-networkd started,
took the interface over, and dropped the address for a moment. The process
reading from the root filesystem during that moment was systemd-networkd.

## Step 8: userspace

```
Poky (Yocto Project Reference Distro) 5.0.20 raspberrypi3-64 ttyS0
raspberrypi3-64 login:
```

From here the console is an ordinary shell and `runner/console.py` takes
over. Everything after this point is a software problem rather than a lab
problem, which is the whole purpose of the eight steps above: they tell you
which of the two you have.

## Where the evidence goes

- The dnsmasq journal for one clean boot, replacing the excerpts above.
- One `tcpdump` capture of the offer showing option 43, because that is the
  step with the least visible failure mode.
- The console log of the same boot, which `console.py` writes without being
  asked.
