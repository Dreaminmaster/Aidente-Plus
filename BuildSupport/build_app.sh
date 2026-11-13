#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
build_dir="$project_dir/Build"
module_dir="$build_dir/Modules"
object_dir="$build_dir/Objects"
module_cache_dir="$build_dir/ModuleCache"
dist_dir="$project_dir/Dist"
final_app_dir="$dist_dir/Aidente.app"
app_dir="$build_dir/.packaging/Aidente.app"
sdk=$(xcrun --sdk macosx --show-sdk-path)
target="arm64-apple-macosx14.0"
signing_identity="${AIDENTE_SIGNING_IDENTITY:--}"
signing_options=(--timestamp=none)
if [[ "$signing_identity" == "-" ]]; then
    if [[ "${AIDENTE_RELEASE_BUILD:-0}" == "1" ]]; then
        print -u2 "Release build requires AIDENTE_SIGNING_IDENTITY (Developer ID Application)."
        exit 1
    fi
    print -u2 "Administrator-install build: ad-hoc integrity signing; no Apple notarization."
else
    if ! security find-identity -v -p codesigning | grep -F -- "$signing_identity" >/dev/null; then
        print -u2 "Requested signing identity is not available. No ad-hoc fallback."
        exit 1
    fi
    signing_options=(--timestamp --options runtime)
fi

if [[ ! -d "$sdk" ]]; then
    sdk=$(xcrun --sdk macosx --show-sdk-path)
fi

mkdir -p "$module_dir" "$object_dir" "$module_cache_dir" "$dist_dir"

clang \
    -c "$project_dir/Vendor/SMCKit/Sources/SMC/smc.c" \
    -I "$project_dir/Vendor/SMCKit/Sources/SMC/include" \
    -isysroot "$sdk" \
    -mmacosx-version-min=14.0 \
    -fmodules \
    -fmodules-cache-path="$module_cache_dir" \
    -o "$object_dir/smc.o"

swiftc \
    -parse-as-library \
    -emit-module \
    -emit-module-path "$module_dir/SMCKit.swiftmodule" \
    -emit-library \
    -static \
    -module-name SMCKit \
    "$project_dir"/Vendor/SMCKit/Sources/SMCKit/*.swift \
    -I "$project_dir/Vendor/SMCKit/Sources/SMC/include" \
    -sdk "$sdk" \
    -target "$target" \
    -module-cache-path "$module_cache_dir" \
    -o "$build_dir/libSMCKit.a"

swiftc \
    -parse-as-library \
    -emit-module \
    -emit-module-path "$module_dir/Defaults.swiftmodule" \
    -emit-library \
    -static \
    -module-name Defaults \
    "$project_dir"/Vendor/Defaults/Sources/Defaults/*.swift \
    -sdk "$sdk" \
    -target "$target" \
    -module-cache-path "$module_cache_dir" \
    -o "$build_dir/libDefaults.a"

swiftc \
    -parse-as-library \
    -emit-module \
    -emit-module-path "$module_dir/AidenteShared.swiftmodule" \
    -emit-library \
    -static \
    -module-name AidenteShared \
    "$project_dir"/Shared/*.swift \
    -sdk "$sdk" \
    -target "$target" \
    -module-cache-path "$module_cache_dir" \
    -o "$build_dir/libAidenteShared.a"

swiftc \
    -parse-as-library \
    -emit-module \
    -emit-module-path "$module_dir/smc_power.swiftmodule" \
    -emit-library \
    -static \
    -module-name smc_power \
    "$project_dir"/SMCPower/*.swift \
    -I "$module_dir" \
    -I "$project_dir/Vendor/SMCKit/Sources/SMC/include" \
    -sdk "$sdk" \
    -target "$target" \
    -module-cache-path "$module_cache_dir" \
    -o "$build_dir/libsmc_power.a"

app_sources=("$project_dir"/Aidente/**/*.swift)

swiftc \
    -parse-as-library -swift-version 5 -strict-concurrency=minimal \
    -whole-module-optimization -c -module-name Aidente \
    -emit-const-values-path "$build_dir/Aidente.swiftconstvalues" \
    -const-gather-protocols-list "$project_dir/BuildSupport/AppIntentProtocols.json" \
    "${app_sources[@]}" \
    -I "$module_dir" -I "$project_dir/Vendor/SMCKit/Sources/SMC/include" \
    -sdk "$sdk" -target "$target" -module-cache-path "$module_cache_dir" \
    -o "$build_dir/Aidente.o"

swiftc "$build_dir/Aidente.o" \
    -L "$build_dir" -lDefaults -lAidenteShared -lsmc_power -lSMCKit "$object_dir/smc.o" \
    -framework AppKit -framework SwiftUI -framework AppIntents -framework IOKit \
    -framework ServiceManagement -framework UserNotifications -framework CoreAudio -framework ApplicationServices \
    -sdk "$sdk" -target "$target" -o "$build_dir/Aidente"

swiftc \
    -swift-version 5 \
    -strict-concurrency=minimal \
    -module-name AidenteReader \
    "$project_dir/Helper/Helper.swift" \
    "$project_dir/Helper/main.swift" \
    -I "$module_dir" \
    -L "$build_dir" \
    -lAidenteShared \
    -lsmc_power \
    -lSMCKit \
    "$object_dir/smc.o" \
    -I "$project_dir/Vendor/SMCKit/Sources/SMC/include" \
    -framework Foundation \
    -framework IOKit \
    -sdk "$sdk" \
    -target "$target" \
    -module-cache-path "$module_cache_dir" \
    -o "$build_dir/AidenteReader"

swiftc \
    -swift-version 5 \
    -strict-concurrency=minimal \
    -module-name AidenteControl \
    "$project_dir/ChargingHelper/ChargingHelper.swift" \
    "$project_dir/ChargingHelper/EnergyModeController.swift" \
    "$project_dir/ChargingHelper/NativeChargeRegisters.swift" \
    "$project_dir/ChargingHelper/main.swift" \
    -I "$module_dir" \
    -L "$build_dir" \
    -lAidenteShared \
    -lsmc_power \
    -lSMCKit \
    "$object_dir/smc.o" \
    -I "$project_dir/Vendor/SMCKit/Sources/SMC/include" \
    -framework Foundation \
    -framework IOKit \
    -framework Security \
    -sdk "$sdk" \
    -target "$target" \
    -module-cache-path "$module_cache_dir" \
    -o "$build_dir/AidenteControl"

swiftc \
    -swift-version 5 \
    "$project_dir/CLI/main.swift" \
    -framework Foundation \
    -sdk "$sdk" \
    -target "$target" \
    -module-cache-path "$module_cache_dir" \
    -o "$build_dir/AidenteCLI"

swiftc \
    -swift-version 5 \
    "$project_dir/UpdaterHelper/main.swift" \
    -framework Foundation \
    -sdk "$sdk" \
    -target "$target" \
    -module-cache-path "$module_cache_dir" \
    -o "$build_dir/AidenteUpdater"

# Build in a hidden staging folder. Keep the last usable Dist app until the
# new bundle has passed metadata generation and signature verification.
rm -rf -- "$build_dir/.packaging"
mkdir -p "$build_dir/.packaging"

mkdir -p \
    "$app_dir/Contents/MacOS" \
    "$app_dir/Contents/Resources" \
    "$app_dir/Contents/XPCServices/com.aidente.app.reader.xpc/Contents/MacOS" \
    "$app_dir/Contents/Library/LaunchDaemons"

cp "$build_dir/Aidente" "$app_dir/Contents/MacOS/Aidente"
cp "$project_dir/BuildSupport/Info.plist" "$app_dir/Contents/Info.plist"
cp -R "$project_dir/BuildSupport/Localizations/"*.lproj "$app_dir/Contents/Resources/"
cp "$project_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$project_dir/BuildSupport/install_local_control.sh" "$app_dir/Contents/Resources/install_local_control.sh"
cp "$build_dir/AidenteCLI" "$app_dir/Contents/Resources/aidente"
cp "$build_dir/AidenteUpdater" "$app_dir/Contents/Resources/AidenteUpdater"

reader_dir="$app_dir/Contents/XPCServices/com.aidente.app.reader.xpc"
cp "$build_dir/AidenteReader" "$reader_dir/Contents/MacOS/AidenteReader"
cp "$project_dir/BuildSupport/ReaderInfo.plist" "$reader_dir/Contents/Info.plist"

cp "$build_dir/AidenteControl" "$app_dir/Contents/MacOS/AidenteControl"
# 0.2.0 registered this legacy relative path. Keep a signed compatibility
# copy for one upgrade cycle so macOS background-item metadata cached from the
# Keep a signed copy in the launch-daemon directory for macOS background-item
# registration compatibility.
cp "$build_dir/AidenteControl" "$app_dir/Contents/Library/LaunchDaemons/AidenteControl"
cp \
    "$project_dir/ChargingHelper/com.aidente.app.control.plist" \
    "$app_dir/Contents/Library/LaunchDaemons/com.aidente.app.control.plist"

cp \
    "$project_dir/BuildSupport/Aidente.icns" \
    "$app_dir/Contents/Resources/Aidente.icns"

printf '%s\n' "${app_sources[@]}" > "$build_dir/AppIntentSources.list"
printf '%s\n' "$build_dir/Aidente.swiftconstvalues" > "$build_dir/AppIntentConstValues.list"
toolchain_dir=$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain
if [[ ! -d "$toolchain_dir" ]]; then toolchain_dir=$(xcrun --find swiftc); toolchain_dir=${toolchain_dir:h:h:h}; fi
xcode_build=$(xcodebuild -version | awk '/Build version/{print $3}')
xcrun appintentsmetadataprocessor \
    --output "$app_dir/Contents/Resources" --toolchain-dir "$toolchain_dir" \
    --module-name Aidente --sdk-root "$sdk" --xcode-version "$xcode_build" \
    --platform-family macOS --deployment-target 14.0 --target-triple "$target" \
    --source-file-list "$build_dir/AppIntentSources.list" \
    --swift-const-vals-list "$build_dir/AppIntentConstValues.list"

codesign \
    --force \
    --sign "$signing_identity" \
    "${signing_options[@]}" \
    --identifier com.aidente.app.updater \
    "$app_dir/Contents/Resources/AidenteUpdater"
codesign \
    --force \
    --sign "$signing_identity" \
    "${signing_options[@]}" \
    --identifier com.aidente.app.control \
    "$app_dir/Contents/MacOS/AidenteControl"
codesign \
    --force \
    --sign "$signing_identity" \
    "${signing_options[@]}" \
    --identifier com.aidente.app.control \
    "$app_dir/Contents/Library/LaunchDaemons/AidenteControl"
codesign \
    --force \
    --sign "$signing_identity" \
    "${signing_options[@]}" \
    --identifier com.aidente.app.reader \
    "$reader_dir"
codesign \
    --force \
    --sign "$signing_identity" \
    "${signing_options[@]}" \
    --identifier com.aidente.app \
    "$app_dir"

codesign --verify --deep --strict --verbose=2 "$app_dir"
if [[ "${AIDENTE_RELEASE_BUILD:-0}" == "1" ]]; then
    for signed_component in "$app_dir" "$app_dir/Contents/MacOS/AidenteControl"; do
        codesign --verify --strict -R '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$signed_component"
    done
fi
backup_dir="$build_dir/.last-successful-bundle"
rm -rf -- "$backup_dir"
if [[ -e "$final_app_dir" ]]; then mv "$final_app_dir" "$backup_dir"; fi
if ! mv "$app_dir" "$final_app_dir"; then
    if [[ -e "$backup_dir" ]]; then mv "$backup_dir" "$final_app_dir"; fi
    exit 1
fi
rm -rf -- "$backup_dir" "$build_dir/.packaging"
echo "$final_app_dir"
