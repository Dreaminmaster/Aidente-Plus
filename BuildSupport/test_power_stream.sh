#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
mkdir -p Build
swiftc -parse-as-library Aidente/Views/NativeRibbon.swift BuildSupport/tests/PowerStreamGeometryTests.swift \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target arm64-apple-macosx14.0 \
  -framework AppKit -framework SwiftUI -framework QuartzCore -o Build/PowerStreamGeometryTests
Build/PowerStreamGeometryTests
