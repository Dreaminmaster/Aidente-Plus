#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swiftc -parse-as-library BuildSupport/tests/MenuItemOrderingTests.swift -I Build/Modules -L Build -lAidenteShared -o Build/MenuItemOrderingTests
Build/MenuItemOrderingTests
