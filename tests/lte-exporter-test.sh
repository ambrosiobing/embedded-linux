#!/bin/sh
#
# lte-exporter-test.sh - the metrics text, without a modem.
#
# The exporter's whole job is turning two tools' output into a format a
# third tool parses, so the interesting failures are all in the parsing and
# the formatting. Both ends are stubbed here: mmcli and ip are replaced,
# and the output is checked as text rather than scraped.
#
# The format check is the part worth having. promtool would do it properly
# and is not installable on every host, so this asserts the rules that
# actually get broken by hand: a sample line whose value is not a number, a
# metric with no TYPE, and a label set that is not one-hot when it claims
# to be.
#
#   sh tests/lte-exporter-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-lte/files/lte-exporter
PYTHON=${PYTHON:-python3}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/fake"
BENCH_TEST_DIR=$WORK/fake
export BENCH_TEST_DIR

pass=0
fail=0

check() {
	if [ "$2" = "$3" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: wanted '$3', got '$2'"
		fail=$((fail + 1))
	fi
}

cat >"$WORK/bin/mmcli" <<'STUB'
#!/bin/sh
for arg in "$@"; do
	case $arg in
	--signal-get)
		echo "modem.signal.refresh.rate  : 10"
		echo "modem.signal.lte.rsrp      : -97.00"
		echo "modem.signal.lte.rsrq      : -11.00"
		echo "modem.signal.lte.snr       : 6.20"
		echo "modem.signal.5g.rsrp       : --"
		exit 0
		;;
	--location-get)
		if [ -f "$BENCH_TEST_DIR/no-fix" ]; then
			echo "modem.location.gps.latitude  : --"
			echo "modem.location.gps.longitude : --"
			exit 0
		fi
		echo "modem.location.gps.latitude  : 47.376900"
		echo "modem.location.gps.longitude : 8.541700"
		echo "modem.location.gps.altitude  : 408.00"
		exit 0
		;;
	--signal-setup=*) exit 0 ;;
	esac
done
echo "modem.generic.device-identifier   : deadbeef"
echo "modem.generic.state               : connected"
echo "modem.generic.signal-quality.value : 61"
STUB

cat >"$WORK/bin/ip" <<'STUB'
#!/bin/sh
cat "$BENCH_TEST_DIR/routes"
STUB

chmod +x "$WORK/bin"/*
PATH=$WORK/bin:$PATH
export PATH

cat >"$WORK/lte.conf" <<'CONF'
uplinks = eth0 wwan0
export_location = 0
CONF

cat >"$BENCH_TEST_DIR/routes" <<'ROUTES'
default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.42 metric 100
default via 10.64.64.64 dev wwan0 proto static metric 700
ROUTES

collect() {
	"$PYTHON" "$SUT" --config "$WORK/lte.conf" --stdout >"$WORK/out.prom" 2>"$WORK/err"
}

has() {
	count=$(grep -c -- "$1" "$WORK/out.prom" 2>/dev/null) || count=0
	printf '%s\n' "$count"
}

# ------------------------------------------------ both uplinks, eth0 wins

collect
check "modem reported present" "$(has '^lte_modem_present 1$')" "1"
check "state connected is 1" "$(has 'lte_modem_state{state="connected"} 1')" "1"
check "state registered is 0" "$(has 'lte_modem_state{state="registered"} 0')" "1"
check "rsrp parsed" "$(has '^lte_signal_rsrp_dbm -97$')" "1"
check "rsrq parsed" "$(has '^lte_signal_rsrq_db -11$')" "1"
check "snr parsed" "$(has '^lte_signal_snr_db 6.2$')" "1"
check "quality became a ratio" "$(has '^lte_signal_quality_ratio 0.61$')" "1"
check "default route is eth0" "$(has 'lte_default_route_via{dev="eth0"} 1')" "1"
check "wwan0 is not carrying it" "$(has 'lte_default_route_via{dev="wwan0"} 0')" "1"
check "location off by default" "$(has 'lte_gnss')" "0"

# The one-hot claim has to hold, or a dashboard sums two states into two.
states=$(grep -c 'lte_modem_state{.*} 1$' "$WORK/out.prom")
check "exactly one state is hot" "$states" "1"

# ------------------------------------------ the cable is out, LTE carries

cat >"$BENCH_TEST_DIR/routes" <<'ROUTES'
default via 10.64.64.64 dev wwan0 proto static metric 700
ROUTES
collect
check "failover: wwan0 now holds the route" \
	"$(has 'lte_default_route_via{dev="wwan0"} 1')" "1"
check "failover: eth0 reports zero, not absent" \
	"$(has 'lte_default_route_via{dev="eth0"} 0')" "1"

# A series that disappears when a device goes down leaves the last value
# on the dashboard for ever. Both uplinks are reported every time.
check "failover: both uplinks still reported" \
	"$(has 'lte_default_route_via')" "4"

# --------------------------------------------------- lowest metric wins

cat >"$BENCH_TEST_DIR/routes" <<'ROUTES'
default via 10.64.64.64 dev wwan0 proto static metric 700
default via 192.168.1.1 dev eth0 proto dhcp metric 100
ROUTES
collect
check "route order does not decide, the metric does" \
	"$(has 'lte_default_route_via{dev="eth0"} 1')" "1"

# ------------------------------------------------------------- location

printf 'export_location = 1\n' >>"$WORK/lte.conf"
collect
check "location on: a fix is reported" "$(has '^lte_gnss_fix 1$')" "1"
check "location on: latitude" "$(has '^lte_gnss_latitude_degrees 47.3769$')" "1"
check "location on: altitude" "$(has '^lte_gnss_altitude_meters 408$')" "1"

touch "$BENCH_TEST_DIR/no-fix"
collect
check "no fix: reported as zero, not omitted" "$(has '^lte_gnss_fix 0$')" "1"
check "no fix: no stale coordinates" "$(has 'lte_gnss_latitude')" "0"
rm -f "$BENCH_TEST_DIR/no-fix"

# ------------------------------------------------ no modem at all

cat >"$WORK/bin/mmcli" <<'STUB'
#!/bin/sh
exit 1
STUB
chmod +x "$WORK/bin/mmcli"
collect
check "no modem: a file is still written" "$(has '^lte_modem_present 0$')" "1"
check "no modem: no signal metrics invented" "$(has 'lte_signal_rsrp')" "0"
check "no modem: the route is still reported" "$(has 'lte_default_route_via')" "2"

# ------------------------------------------------------- format check

"$PYTHON" - "$WORK/out.prom" <<'PYCHECK'
import sys

problems = []
declared = set()
with open(sys.argv[1], encoding="ascii") as handle:
    for number, line in enumerate(handle, 1):
        line = line.rstrip("\n")
        if not line:
            continue
        if line.startswith("#"):
            parts = line.split()
            if len(parts) >= 3 and parts[1] == "TYPE":
                declared.add(parts[2])
            continue
        name, _, value = line.rpartition(" ")
        name = name.split("{")[0]
        if not name:
            problems.append(f"line {number}: no metric name")
            continue
        if name not in declared:
            problems.append(f"line {number}: {name} has no TYPE line before it")
        try:
            float(value)
        except ValueError:
            problems.append(f"line {number}: {value!r} is not a number")

for problem in problems:
    print("FAILED   format:", problem)
sys.exit(1 if problems else 0)
PYCHECK
echo "ok       output parses as Prometheus text"
pass=$((pass + 1))

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
