#!/bin/zsh
set -euo pipefail
project_dir=${0:A:h:h}
cd "$project_dir"
sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk"
if [[ ! -d "$sdk" ]]; then sdk=$(xcrun --sdk macosx --show-sdk-path); fi
swiftc -parse-as-library BuildSupport/tests/FeatureCompletionTests.swift ChargingHelper/EnergyModeController.swift \
    -sdk "$sdk" -target arm64-apple-macosx14.0 -I Build/Modules -L Build -lAidenteShared -o Build/FeatureCompletionTests
Build/FeatureCompletionTests
python3 - <<'PY'
import json,pathlib
path=pathlib.Path('Dist/Aidente.app/Contents/Resources/Metadata.appintents/extract.actionsdata')
data=json.loads(path.read_bytes())
text=path.read_text()
assert len(data['actions']) == 18
assert len(data['autoShortcuts']) == 3
for name in ['TopUpIntent','PauseChargingIntent','SetChargeLimitIntent','GetBatteryPercentageIntent','GetTemperatureIntent','SetMagSafeLEDIntent','PreventSleepIntent','EnableHighPowerIntent']:
 assert name in text, name
print('PASS: native App Intents metadata contains control and query actions')
PY
