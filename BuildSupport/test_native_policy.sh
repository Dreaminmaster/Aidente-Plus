#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
swiftc -parse-as-library BuildSupport/tests/NativeChargePolicyTests.swift \
    -I Build/Modules -L Build -lAidenteShared -o Build/NativeChargePolicyTests
Build/NativeChargePolicyTests
