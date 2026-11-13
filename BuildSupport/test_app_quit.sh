#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p Build/QuitFixture.app/Contents/MacOS
/usr/libexec/PlistBuddy -c Clear -c 'Add :CFBundleExecutable string QuitFixture' -c 'Add :CFBundleIdentifier string com.aidente.tests.quitfixture' -c 'Add :CFBundleName string Aidente Quit Fixture' -c 'Add :CFBundlePackageType string APPL' Build/QuitFixture.app/Contents/Info.plist >/dev/null
swiftc BuildSupport/diagnostics/QuitFixture.swift -o Build/QuitFixture.app/Contents/MacOS/QuitFixture
codesign --force --sign - Build/QuitFixture.app
swiftc -parse-as-library BuildSupport/tests/AppQuitIntegrationTests.swift Aidente/Services/AppQuitService.swift -o Build/AppQuitIntegrationTests
Build/AppQuitIntegrationTests "$PWD/Build/QuitFixture.app"
