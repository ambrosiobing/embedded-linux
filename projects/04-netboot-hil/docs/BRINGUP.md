# Bring-up, Project 04

From two bare boards to an automated test run. Read [DESIGN.md](DESIGN.md)
first: this file assumes you know which component owns what, and the
ownership table there is the answer to most of what goes wrong.

Nothing below has been run on hardware. Every command is written from the
specification, the dnsmasq and kernel documentation, and the recipes in this
project, and the point of the journal is that the first run will contradict
some of it. Where a step says "record this", write the answer into this file
or into [netboot-flow.md](netboot-flow.md).

## 0. Before power

| Check | Why |
|---|---|
| The DUT has **no microSD card in it** | Not a detail, the whole point. A card in the slot means the board boots from it and the lab proves nothing |
| It is the **3B+**, not the plain Pi 3 | The 3B+ ships with network boot enabled in OTP. Enabling it on a Pi 3 means burning `program_usb_boot_mode=1`, which is permanent, and the specification warns against it |
| The USB/TTL cable's **red lead is not connected** | Both boards have their own supply. Two supplies meeting through a serial cable is the ordinary way to reset a board mid-boot |
| The **common ground wire** is in | A loopback with no shared ground floats, and a floating input reads correctly often enough to look like it works |
| Both boards have their own supply | The server is USB-C, the DUT is micro USB |

## 1. The server, once

Raspberry Pi OS Lite on the Pi 4, on its own card. The Project 15 router
image is a different card and the two do not mix: that image runs an access
point on `wlan0` and has no dnsmasq.

Then, from this directory on the server:

```bash
sudo sh server/install.sh isolated
```

`isolated` because this bench has no wired modem. The server becomes the
DHCP server for `192.168.7.0/24`, which is a cable with two hosts on it.
Use `proxy` instead only if both boards are plugged into a real router.

The installer deliberately leaves two things undone and says so at the end.

**The static address on `eth0`.** Whatever manages networking on the server
has to give `eth0` the address `192.168.7.1/24` and then leave it alone. Two
things configuring one interface is the commonest way to lose a lab network,
and it is the same failure the DUT has in a different costume.

**The USB port path in the udev rule.** Cheap USB/TTL adapters carry no
serial number, so the rule matches the physical port instead:

```bash
udevadm info -a -n /dev/ttyUSB0 | grep -m3 -E 'KERNELS|idVendor|idProduct'
```

Put that `KERNELS` value into `/etc/udev/rules.d/99-bench-tty.rules`, then:

```bash
sudo udevadm control --reload && sudo udevadm trigger
ls -l /dev/tty-dut3
```

**A note on the cable.** The bench's Renkforce USB/TTL adapter is a
PL2303HXA, which Windows refuses to drive and which is why Project 1's
serial console was deferred. Here it plugs into a Linux machine, where the
`pl2303` driver handles it without comment. The cable was never the problem;
the host was.

## 2. The DUT's serial number, once

Read from a normal SD boot, before the card comes out for good:

```bash
grep Serial /proc/cpuinfo
```

The last eight hex digits name the TFTP directory. Record it here, and set
it for the deploy:

```bash
export HIL_DUT_SERIAL=xxxxxxxx
```

Serial number of this bench's DUT: **not yet read**.

## 3. Build and deploy the image

On the build host:

```bash
./go netboot
```

That is `bench-netboot-image` for `raspberrypi3-64`: the bench image with
the NFS client, kernel IP autoconfiguration and the `lan78xx` Ethernet
driver built in, emitted as a tarball rather than a disk image because an
NFS export is a directory tree.

Check the fragment actually reached the kernel before believing any of it:

```bash
./go ksym -f netboot
./go kconfig -f netboot "$(find ~/bench/build/tmp/work -path '*linux-raspberrypi*' -name .config | head -1)"
```

Then, on the server:

```bash
cd projects/04-netboot-hil/runner && sh deploy.sh
```

## 4. Boot it by hand, watching the server

This is the step to do slowly, once, because it is where the eight protocol
steps become familiar and every later failure is diagnosed against them.

```bash
journalctl -fu dnsmasq
```

Power the DUT. Within a few seconds the log should show `DHCPDISCOVER`, an
offer carrying option 43, then a run of `sent /srv/tftp/...` lines, then a
**second** `DHCPDISCOVER` from the kernel. The console goes from silent to
kernel output, then `VFS: Mounted root (nfs filesystem)`, then `login:`.

[netboot-flow.md](netboot-flow.md) has each step, what it looks like, and
the specific failure that belongs to it.

If the board sits dark with an offer in the log, the ROM did not like the
offer. Look at the wire rather than at dnsmasq's opinion of itself:

```bash
sudo tcpdump -i eth0 -n -v port 67
```

## 5. The console, shared

```bash
telnet localhost 4003
```

Ctrl-] then `quit` to leave. This is the same console the runner uses, which
is what ser2net is for: attach while no test is running, and `kickolduser`
means the next run takes it back rather than both getting half the bytes.

Never open `/dev/tty-dut3` directly. Two readers on one device node is the
failure where a test hangs with no explanation, having read the half of the
output that the other reader did not.

## 6. The loopback wire

DUT pin 11 (GPIO17) through 1 kOhm to server pin 16 (GPIO23), and DUT pin 9
to server pin 14 for ground. By hand first, before any test believes it:

On the DUT:

```bash
gpioset -t0 -c gpiochip0 17=1
```

On the server, in another window:

```bash
gpioget -c gpiochip0 23
```

Then `0` on the DUT and read again. Two boards, two chips called
`gpiochip0`, two pins called GPIO17, and only one of them is in this test:
the DUT's. The server's GPIO17 is the green LED line.

## 7. The first automated run

```bash
cd projects/04-netboot-hil/runner && pytest
```

What should happen: the deploy runs, the DUT is asked to reboot over its own
console, the fixture waits for the NFS mount line and the login prompt, and
then each test costs a second or two. `results.xml` is written for any CI
system to read.

The one manual step is printed rather than hidden. If the DUT does not
answer its console, the fixture says so and asks for the plug to be pulled;
count those in [run-log-20-boots.txt](run-log-20-boots.txt), because the
project's own claim is about how few of them there are.

## 8. Prove the tests can fail

A test suite that has never failed is not a test suite. Two deliberate
breakages, both of which are acceptance criteria:

**Break the deployment.** Put a typo in `cmdline.txt` in the TFTP directory
and run again. The board should fail at the login step, not at a Python
traceback, and the console log should show why.

**Pull the loopback jumper** and run `test_gpio_loopback`. It must fail.
That is the difference between a test that measures hardware and a test
that measures a variable.

## 9. Twenty boots

```bash
for i in $(seq 1 20); do
    echo "=== run $i  $(date -Is)"
    pytest -q || echo "=== run $i FAILED"
done 2>&1 | tee ../docs/run-log-20-boots.txt
```

Record how many needed a hand. That number is the honest measure of this
lab, and the first purchase it would justify is a USB power switch driven
from a server GPIO.

## Pitfalls, in the order they usually happen

| Symptom | Cause |
|---|---|
| Board dark, nothing in the dnsmasq log | Not on the same wire, or the ROM gave up before dnsmasq answered |
| Offer in the log, board still dark | Option 43 missing or wrong. Check with `tcpdump -v` |
| `file not found` for `bootcode.bin` | It is only in the serial directory. It must be in the TFTP root too |
| Kernel starts, `unable to mount root` | `CONFIG_USB_LAN78XX` or the NFS options are not built in. `./go kconfig` |
| Only one DHCP exchange in the log | The kernel's network never came up, same cause as above |
| Boots, then freezes a second into userspace | The interface was reconfigured out from under the NFS mount. `KeepConfiguration=yes` |
| `mount: permission denied` | The export lacks `no_root_squash` or does not name the DUT's subnet |
| Loopback passes with the wire pulled | No common ground. The input is floating |
| A run hangs with no output | Something else has `/dev/tty-dut3` open. Use `telnet localhost 4003` |
| Tests pass on a board with a card in it | They do not: `test_no_local_disk_was_used` exists for exactly this |
