#!/usr/bin/env bash
# Lint and simulate. This is what CI runs, and what you should run locally
# before pushing - identical command, so a green pipeline means something.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== verilator $(verilator --version) ==="

echo
echo "=== lint ==="
# --lint-only with -Wall on the whole design. Warnings are treated as failures:
# in RTL, a width mismatch or an inferred latch is a bug that has not happened
# yet, not a style opinion.
verilator --lint-only -Wall --timing \
    rtl/pkt_pkg.sv rtl/frame_parse.sv rtl/resp_gen.sv rtl/parser_top.sv \
    --top-module parser_top

echo
echo "=== simulate ==="
make -C tb clean >/dev/null 2>&1 || true
make -C tb

echo
echo "=== results ==="
# cocotb writes JUnit XML; fail the build if any testcase reported a failure.
python - <<'PY'
import sys, glob, xml.etree.ElementTree as ET

files = glob.glob("tb/results.xml")
if not files:
    print("no results.xml produced - the simulation did not run")
    sys.exit(1)

failures = 0
total = 0
for path in files:
    for case in ET.parse(path).getroot().iter("testcase"):
        total += 1
        bad = list(case.iter("failure")) + list(case.iter("error"))
        status = "FAIL" if bad else "pass"
        if bad:
            failures += 1
        print(f"  {status:4}  {case.get('name')}")

print(f"\n{total - failures}/{total} passed")
sys.exit(1 if failures else 0)
PY
