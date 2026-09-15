#!/bin/sh
#
# sensorhub-policy-test.sh - the eight files that have to agree with each
# other, checked against each other.
#
# A D-Bus service is not one artefact, it is a name that appears in eight
# places: the daemon's source, the bus policy, the activation file, the
# polkit action, the polkit rule, the udev rule, the systemd unit and the
# recipe that installs them. Every one of those is a string typed by hand,
# and a single character wrong in any of them produces a failure whose
# symptom is somewhere else entirely:
#
#   name wrong in the bus policy     the daemon starts and cannot own its
#                                    name, and blames sd-bus
#   unit name wrong in the .service  bus activation times out with no log
#   symlink wrong in the udev rule   BindsTo binds to a device unit that
#                                    never exists, so unplugging does
#                                    nothing and nobody notices until it
#                                    matters
#   action id wrong in the rule      polkit denies, correctly, and the
#                                    rule that was supposed to allow it
#                                    sits there looking right
#
# None of that needs hardware to catch. It needs somebody to compare the
# strings, which is what this file does.
#
#   sh tests/sensorhub-policy-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=${PYTHON:-python3}

BENCH_ROOT=$ROOT
export BENCH_ROOT

exec "$PYTHON" - <<'PYTEST'
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.environ["BENCH_ROOT"]
FILES = os.path.join(ROOT, "meta-bench", "recipes-bench", "bench-sensorhub",
                     "files")
RECIPE = os.path.join(ROOT, "meta-bench", "recipes-bench", "bench-sensorhub",
                      "bench-sensorhub_0.1.bb")

passed = 0
failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        print("ok       %s" % label)
        passed += 1
    else:
        print("FAILED   %s: wanted %r, got %r" % (label, want, got))
        failed += 1


def read(name):
    with open(os.path.join(FILES, name), encoding="utf-8") as handle:
        return handle.read()


def define(source, name):
    """The value of a #define STRING in the daemon."""
    match = re.search(r'#define\s+%s\s+"([^"]*)"' % name, source)
    return match.group(1) if match else None


daemon = read("sensorhubd.c")
recipe = open(RECIPE, encoding="utf-8").read()

IFACE = define(daemon, "IFACE")
OBJ = define(daemon, "OBJ")
ACTION = define(daemon, "POLKIT_CALIBRATE")
TTY = define(daemon, "DEFAULT_TTY")

check("the daemon names an interface", IFACE, "org.bench.SensorHub1")
check("and an object path", OBJ, "/org/bench/SensorHub1")
check("and a polkit action", ACTION, "org.bench.sensorhub.calibrate")
check("and a device", TTY, "/dev/sensorhub")

# The interface name carries its major version. That is the whole
# versioning rule for the bus half of the project, so it is worth an
# assertion rather than a sentence: a breaking change becomes SensorHub2
# served next to this one, not a quiet change of signature.
check("the interface name ends in its major version",
      bool(re.search(r"[A-Za-z]\d+$", IFACE)), True)
check("the object path is the interface as a path",
      OBJ, "/" + IFACE.replace(".", "/"))

# --------------------------------------------------------- the bus policy

policy_xml = read("org.bench.SensorHub1.conf")
try:
    policy = ET.fromstring(policy_xml)
    check("the bus policy is well formed XML", policy.tag, "busconfig")
except ET.ParseError as error:
    check("the bus policy is well formed XML", str(error), "no parse error")
    policy = ET.Element("busconfig")

owners = [p for p in policy.findall("policy") if p.get("user")]
check("exactly one user may own the name", len(owners), 1)
check("and it is the daemon's user", owners[0].get("user"), "sensorhub")
check("that policy grants own", [a.get("own") for a in owners[0].findall("allow")],
      [IFACE])

defaults = [p for p in policy.findall("policy")
            if p.get("context") == "default"]
check("there is a default context policy", len(defaults), 1)
allows = defaults[0].findall("allow")
check("the default context may send to the service",
      any(a.get("send_destination") == IFACE for a in allows), True)
check("and may receive its signals",
      any(a.get("receive_sender") == IFACE for a in allows), True)

# The mistake that matters: an own rule outside the owner's policy would
# let any process on the bus claim the name and impersonate the service.
check("nobody else may own the name",
      any(a.get("own") for a in allows), False)
check("and nothing is granted to everyone by a missing user attribute",
      any(p.get("user") is None and p.get("context") is None
          for p in policy.findall("policy")), False)

# ------------------------------------------------------ bus activation

service = read("org.bench.SensorHub1.service")
service_keys = dict(
    line.split("=", 1) for line in service.splitlines()
    if "=" in line and not line.startswith("["))

check("the activation file names the interface",
      service_keys.get("Name"), IFACE)
check("it hands the start to systemd",
      service_keys.get("SystemdService"), "sensorhubd.service")
check("it runs as the daemon's user", service_keys.get("User"), "sensorhub")
# Exec is required by the D-Bus spec and must never be used here: systemd
# owns the lifecycle, and a bus that could also spawn the daemon directly
# would produce two of them.
check("and the direct exec is disabled", service_keys.get("Exec"),
      "/bin/false")

# ------------------------------------------------------------- the unit

unit = read("sensorhubd.service")
unit_keys = {}
for line in unit.splitlines():
    if "=" in line and not line.startswith(("[", "#")):
        key, value = line.split("=", 1)
        unit_keys.setdefault(key, []).append(value)


def one(key):
    values = unit_keys.get(key, [])
    return values[0] if len(values) == 1 else values


check("the unit is bus activated", one("Type"), "dbus")
check("and claims the same name", one("BusName"), IFACE)
check("it runs the daemon on the stable device",
      one("ExecStart"), "/usr/bin/sensorhubd " + TTY)
check("it runs as the same user", one("User"), "sensorhub")

# BindsTo has to name the device unit that corresponds to the symlink the
# udev rule creates. systemd escapes a device path by dropping the leading
# slash and replacing the rest with dashes.
device_unit = TTY.lstrip("/").replace("/", "-") + ".device"
check("it is bound to the device unit for that device",
      one("BindsTo"), device_unit)
check("and ordered after it", one("After"), device_unit)

for key, value in (("ProtectSystem", "strict"), ("ProtectHome", "yes"),
                   ("NoNewPrivileges", "yes"), ("PrivateTmp", "yes"),
                   ("RestrictAddressFamilies", "AF_UNIX"),
                   ("MemoryDenyWriteExecute", "yes"),
                   ("SystemCallFilter", "@system-service"),
                   ("CapabilityBoundingSet", ""),
                   ("DevicePolicy", "closed")):
    check("hardening: %s=%s" % (key, value), one(key), value)

check("it restarts only on failure", one("Restart"), "on-failure")

# ---------------------------------------------------------- the udev rule

udev = read("80-sensorhub.rules")
check("udev creates the symlink the unit expects",
      'SYMLINK+="%s"' % TTY.rsplit("/", 1)[-1] in udev, True)
check("and tags the device for systemd", 'TAG+="systemd"' in udev, True)
check("and wants the unit when it appears",
      'ENV{SYSTEMD_WANTS}="sensorhubd.service"' in udev, True)
check("and tells ModemManager to keep away",
      'ENV{ID_MM_DEVICE_IGNORE}="1"' in udev, True)
check("and matches on both vendor and product",
      bool(re.search(r'ATTRS\{idVendor\}=="[0-9a-f]{4}"', udev)) and
      bool(re.search(r'ATTRS\{idProduct\}=="[0-9a-f]{4}"', udev)), True)

# -------------------------------------------------------------- polkit

action_xml = read("org.bench.sensorhub.policy")
try:
    actions = ET.fromstring(action_xml)
    check("the polkit action is well formed XML", actions.tag, "policyconfig")
except ET.ParseError as error:
    check("the polkit action is well formed XML", str(error), "no parse error")
    actions = ET.Element("policyconfig")

ids = [a.get("id") for a in actions.findall("action")]
check("it declares exactly the action the daemon asks about", ids, [ACTION])

action = actions.find("action")
check("it has a description for the prompt",
      bool(action is not None and action.findtext("description")), True)
check("and a message", bool(action is not None and action.findtext("message")),
      True)
defaults_el = action.find("defaults") if action is not None else None
check("its default is not a blanket yes",
      defaults_el is not None and
      "yes" not in [defaults_el.findtext("allow_any"),
                    defaults_el.findtext("allow_inactive")], True)

rule = read("50-sensorhub.rules")
check("the rule is about the same action", ACTION in rule, True)
group_match = re.search(r'isInGroup\("([^"]+)"\)', rule)
check("the rule grants a group", bool(group_match), True)
group = group_match.group(1) if group_match else None
check("and the recipe creates that group",
      'GROUPADD_PARAM:${PN} = "--system %s"' % group in recipe, True)
check("the rule returns a decision", "polkit.Result.YES" in rule, True)

# ------------------------------------------------------------ the recipe

# useradd puts the user name last, after the options. Extracting it
# rather than searching for the string means this compares the user the
# recipe creates against the user the policy and the unit name, which is
# the thing that can actually be wrong.
useradd = re.search(r'USERADD_PARAM:\$\{PN\}\s*=\s*"((?:[^"\\]|\\.)*)"',
                    recipe, re.S)
created_user = re.sub(r"\s+", " ", useradd.group(1)).strip().split()[-1] \
    if useradd else None
check("the recipe creates the user the policy and the unit name",
      created_user, "sensorhub")
check("the unit is installed but not enabled",
      'SYSTEMD_AUTO_ENABLE:${PN} = "disable"' in recipe, True)
check("because activation is the point", 'SYSTEMD_SERVICE:${PN} = '
      '"sensorhubd.service"' in recipe, True)

# Every file that is fetched has to be installed. A file added to SRC_URI
# and forgotten in do_install is a file that exists in the build and not on
# the board, which is the failure that looks like a bug in the daemon.
src_uri = re.search(r'SRC_URI = "(.*?)"', recipe, re.S).group(1)
fetched = re.findall(r"file://(\S+)", src_uri)
install = recipe.split("do_install()", 1)[1]
compiled = {"proto.c", "proto.h", "sensorhubd.c"}
missing = [name for name in fetched
           if name not in compiled and name not in install]
check("every fetched file is installed or compiled", missing, [])

print("")
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTEST
