# Project 04: a network-boot hardware-in-the-loop lab

**Boards:** Raspberry Pi 4 as server, Raspberry Pi 3B+ as device under test.
**Theme:** TFTP and NFS root, udev, serial consoles, automated tests.

Every project after this one produces images and kernels that have to be
tried on real hardware, many times, and swapping a microSD card each time is
the reason that does not happen. A Raspberry Pi 3B+ fetches its firmware and
kernel over Ethernet from its boot ROM and mounts its root over NFS, so a
new build is one `rsync` from running on the board. Put a serial console, a
test runner and a status indicator next to that and the result is a small
hardware in the loop lab of the kind every embedded team runs, built from
two boards on a desk.

**This is the only project whose product is a lab rather than a device.**
That shows in the layout: most of what it adds is not a Yocto recipe. One
kernel fragment and one image go in `meta-bench`; the server configuration
and the runner are plain files, because they run on a machine this
repository does not build.

## State

**Written, tested where it can be, and never run on hardware.** The console
protocol and the server configuration are both verified on a laptop, 47
assertions between them. Nothing has booted over the network yet, and the
acceptance table says which is which.

Two things are deferred with written reasons, and one of them is inherited:
the status LEDs, for the same connector incompatibility that blocked Project
1, and automatic power cycling, which needs a part the bench does not have.

## What this project adds to the repository

| Path | What |
|---|---|
| `server/dnsmasq.d/` | Two topologies: a direct cable, and both boards on a router. Install exactly one |
| `server/exports`, `server/udev/`, `server/ser2net.yaml` | The NFS export, a stable console name, and the console shared over TCP |
| `server/leds.py`, `server/install.sh` | Optional indication, and an installer that refuses to guess |
| `runner/console.py` | Expect over a serial console, with framing that works |
| `runner/conftest.py` | Deploy, reboot, log in, hand over a console |
| `runner/test_boot.py`, `runner/test_hw.py` | The checklist, including one test that cannot pass without a wire |
| `runner/deploy.sh` | Build output into the TFTP directory and the NFS export, together |
| `meta-bench/recipes-kernel/linux/files/netboot.cfg` | The six kernel options a diskless root needs |
| `meta-bench/recipes-bench/bench-netboot/` | A network configuration that does not take the root filesystem's interface away from the kernel |
| `meta-bench/recipes-core/images/bench-netboot-image.bb` | The DUT image, as a tarball rather than a disk image |
| `kas/bench-netboot.yml` | `./go netboot` |
| `tests/hil-console-test.sh`, `tests/hil-server-config-test.sh` | What can be proven without two boards |

## Running it

```sh
./go netboot                    # bench-netboot-image for the Pi 3B+
sudo sh server/install.sh isolated
cd runner && sh deploy.sh && pytest
```

[docs/DESIGN.md](docs/DESIGN.md) is the methodology: the architecture, the
wiring, the bench layout, the sequence of a run, and the table of who owns
which device. Read it before the bring-up notes.

[docs/BRINGUP.md](docs/BRINGUP.md) is the board work in order, including the
step that has to be done once before anything is automated.

[docs/netboot-flow.md](docs/netboot-flow.md) is DHCP, TFTP and NFS as the
logs show them, which is how every failure here is diagnosed.

## The two ideas worth taking from this project

**A serial console has no framing, so make some.** Output arrives as a
stream of bytes, and a shell prompt is just characters that usually turn up
at the end. Every command `console.py` sends carries a unique end marker and
comes back with its exit status attached. The alternative, matching on a
prompt, works until a command prints something that looks like one.

That framing has two subtleties, both found by the test rather than by
thinking. The marker appears twice, because the console echoes the command
before running it, and the pattern has to require digits after it so that it
cannot match the echo. And the marker cannot be a timestamp: the first
version used `time.monotonic_ns()`, whose resolution is about 15 ms on some
hosts, so two commands in quick succession got the same marker and the
second returned the first one's output.

**A netbooted board has a circular dependency and the kernel says so.** A
module lives in the root filesystem, the root filesystem is on the network,
and the network needs a driver. `ROOT_NFS` is declared `depends on
NFS_FS=y`, and that `=y` inside a `depends` line is Kconfig's way of saying
"this one cannot be a module". The Ethernet driver has the same problem
without the kernel saying so, which is why `CONFIG_USB_LAN78XX=y` carries a
comment explaining itself.

## Acceptance criteria

The six criteria the project is specified against, with what has been shown.
"Configured" means a file says so; "measured" means a board did.

| # | Criterion | State |
|---|---|---|
| 1 | With no card inserted, the 3B+ reaches a login prompt over NFS root within 60 s, and the dnsmasq log shows the offer and every transfer | Configured, not observed |
| 2 | `/dev/tty-dut3` exists after every replug into the same port | Configured. The rule matches a placeholder port until the real one is read on the server |
| 3 | `pytest` completes a full run including the soft reboot in under 3 minutes and writes `results.xml` | Not measured |
| 4 | Twenty consecutive runs pass without manual intervention | Not measured. [run-log-20-boots.txt](docs/run-log-20-boots.txt) is the empty template |
| 5 | A deliberately broken deployment fails at the login step, the red LED comes on, and the console log shows why | Partly reachable. The failure and the log work; the LED is deferred |
| 6 | The loopback test fails when the jumper is pulled, proving it measures hardware | Not measured, and it is the criterion this project exists to be able to make |

Beyond the specification, three things this repository asserts:

| # | Criterion | State |
|---|---|---|
| 7 | The DUT is proven to have no card in it, not merely to be mounted over NFS | Asserted by `test_no_local_disk_was_used` |
| 8 | The console framing survives an echoing console, a silent one, empty output, and output that looks like a prompt | Asserted, 15 assertions in `tests/hil-console-test.sh` |
| 9 | The server configuration still says the things that make it work | Asserted, 32 assertions in `tests/hil-server-config-test.sh` |

## What is tested without hardware

| Check | Command | Covers |
|---|---|---|
| Console protocol | `sh tests/hil-console-test.sh` | Marker framing against a fake board: the echo, exit status including non-zero, multi-line output, no echo at all, empty output, output containing a prompt, the timeout message, the log, and marker uniqueness |
| Server invariants | `sh tests/hil-server-config-test.sh` | `port=0`, the exact option 43 string, TFTP root, the two topologies differing, the island offering no route or DNS, `no_root_squash` scoped to the lab subnet, ser2net on localhost, and nothing naming `ttyUSB0` as a device to open |
| Kernel fragment | `./go ksym -f netboot` | That all six options are real Kconfig symbols, before an hour of building |

What none of it proves: that a boot ROM answers, that an NFS root mounts, or
that a wire carries a signal. Only two boards show that.

## Deferred, with reasons

| Item | Why | What would un-defer it |
|---|---|---|
| The three status LEDs | The bench's LED parts are Joy-IT LinkerKit LK-LED10 modules with a 2.0 mm socket, and standard 2.54 mm jumper wires cannot mate with it. The same blocker Project 1 recorded | Three bare LEDs and three 330 ohm resistors. `leds.py` and the fixture already handle both cases, and the indication is reporting rather than measurement |
| Automatic power cycling | No relay, no switched USB hub and no smart plug. The PPK2 could switch 5 V but its 1 A limit is below what a 3B+ draws with Ethernet active at boot | A USB power switch driven from a server GPIO. It is the first purchase this lab would justify, and until then the manual step is printed and counted |
| A second DUT | The specification's stretch goal, with the NanoPi NEO Air loading a kernel over `tftpboot` from U-Boot | Project 2, which brings that board up in the first place |
| A `bench-lab-image` | The server runs Raspberry Pi OS because it is the instrument rather than the product, and four configuration files are cheaper than a week of `PACKAGECONFIG` | The day the lab itself has to be reproducible from source |
