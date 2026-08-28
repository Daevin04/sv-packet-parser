#!/usr/bin/env bash
# Provision a bare container and run the test suite. Used to reproduce the CI
# environment locally, and by CI itself when the image lacks the toolchain.
set -euo pipefail

apt-get update -qq >/dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    verilator make g++ >/dev/null 2>&1

pip install -q --disable-pip-version-check 'cocotb>=1.9,<2.0'

exec bash /work/scripts/run_tests.sh
