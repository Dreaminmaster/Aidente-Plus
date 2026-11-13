#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
sdk=$(xcrun --sdk macosx --show-sdk-path)
swiftc -parse-as-library BuildSupport/tests/ImmediateStateObserverTests.swift \
  -sdk "$sdk" -target arm64-apple-macosx14.0 -I Build/Modules -L Build -lAidenteShared \
  -o Build/ImmediateStateObserverTests
Build/ImmediateStateObserverTests
