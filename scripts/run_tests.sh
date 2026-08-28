#!/usr/bin/env bash
# Lint and simulate every example configuration. This is what CI runs and what
# you should run locally before pushing - identical command, so a green pipeline
# means something.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGS=(market telemetry)

RTL_CORE="rtl/pkt_pkg.sv rtl/frame_parse.sv rtl/resp_gen.sv rtl/parser_top.sv"

echo "=== $(verilator --version) ==="

echo
echo "=== lint ==="
# -Wall with warnings as failures. In RTL a width mismatch or an inferred latch
# is a bug that has not happened yet, not a style opinion. Each configuration is
# linted separately: parameters change what elaborates, so a config can be
# clean while another is not.
for cfg in "${CONFIGS[@]}"; do
    echo "--- $cfg ---"
    # shellcheck disable=SC2086
    verilator --lint-only -Wall --timing \
        $RTL_CORE "rtl/examples/${cfg}_filter_top.sv" \
        --top-module "${cfg}_filter_top"
done

echo
echo "=== simulate ==="
for cfg in "${CONFIGS[@]}"; do
    echo "--- $cfg ---"
    make -C tb clean CONFIG="$cfg" >/dev/null 2>&1 || true
    make -C tb CONFIG="$cfg"
done

echo
echo "=== results ==="
python - <<'PY'
import sys, glob, xml.etree.ElementTree as ET

files = sorted(glob.glob("tb/results_*.xml"))
if not files:
    print("no results produced - the simulation did not run")
    sys.exit(1)

failures = total = 0
for path in files:
    config = path.split("results_")[1].removesuffix(".xml")
    print(f"\n  [{config}]")
    for case in ET.parse(path).getroot().iter("testcase"):
        total += 1
        bad = list(case.iter("failure")) + list(case.iter("error"))
        if bad:
            failures += 1
        print(f"    {'FAIL' if bad else 'pass'}  {case.get('name')}")

print(f"\n{total - failures}/{total} passed across {len(files)} configurations")
sys.exit(1 if failures else 0)
PY
