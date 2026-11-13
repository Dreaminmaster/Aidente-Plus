#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [[ ! -d "$sdk" ]]; then sdk=$(xcrun --sdk macosx --show-sdk-path); fi
for test_name in CalibrationProgressTests HeatProtectionTests; do
    swiftc -parse-as-library "BuildSupport/tests/$test_name.swift" \
        -sdk "$sdk" -target arm64-apple-macosx14.0 \
        -I Build/Modules -L Build -lAidenteShared -o "Build/$test_name"
    "Build/$test_name"
done
swiftc -parse-as-library BuildSupport/tests/MenuBarConfigurationTests.swift \
    Aidente/Models/MenuBarConfiguration.swift Aidente/Models/PopoverWidget.swift \
    Aidente/DefaultsKeys.swift Aidente/AidenteL10n.swift \
    -sdk "$sdk" -target arm64-apple-macosx14.0 \
    -I Build/Modules -I Vendor/SMCKit/Sources/SMC/include \
    -L Build -lDefaults -lsmc_power -lSMCKit Build/Objects/smc.o \
    -framework IOKit -o Build/MenuBarConfigurationTests
Build/MenuBarConfigurationTests --ui-preview
