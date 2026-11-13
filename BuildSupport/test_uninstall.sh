#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [[ ! -d "$sdk" ]]; then sdk=$(xcrun --sdk macosx --show-sdk-path); fi
sh -n BuildSupport/install_local_control.sh
swiftc -parse-as-library BuildSupport/tests/UninstallPlanTests.swift \
    -sdk "$sdk" -target arm64-apple-macosx14.0 \
    -I Build/Modules -L Build -lAidenteShared -o Build/UninstallPlanTests
Build/UninstallPlanTests
python3 BuildSupport/tests/test_complete_uninstall.py
swiftc -parse-as-library BuildSupport/tests/LocalInstallerTests.swift     Aidente/Services/LocalControlInstaller.swift     -sdk "$sdk" -target arm64-apple-macosx14.0     -I Build/Modules -L Build -lAidenteShared -o Build/LocalInstallerTests
Build/LocalInstallerTests
