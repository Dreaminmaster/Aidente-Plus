#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
mkdir -p Build
swiftc -parse-as-library Shared/ManagementPreferenceMigration.swift Shared/PowerConnectionSnapshot.swift BuildSupport/tests/ManagementSetupTests.swift -o Build/ManagementSetupTests
Build/ManagementSetupTests
