#!/bin/zsh
# Live, read-only PowerUI contract checks; does not install or write valid limits.
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
mkdir -p Build
swiftc -parse-as-library SMCPower/NativeChargeLimit.swift \
    BuildSupport/tests/NativeChargeLimitReadOnlyTests.swift \
    -o Build/NativeChargeLimitReadOnlyTests
Build/NativeChargeLimitReadOnlyTests
