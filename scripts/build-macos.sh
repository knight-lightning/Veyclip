#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Build on a Mac with macOS 26+ and Xcode 26+." >&2
    exit 1
fi
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    echo "Usage: bash scripts/build-macos.sh [debug|release]" >&2
    exit 1
fi
if [[ "$configuration" == "release" ]]; then xcode_configuration="Release"; else xcode_configuration="Debug"; fi
xcodebuild -project ShareXMac.xcodeproj -scheme ShareXMac \
    -configuration "$xcode_configuration" -derivedDataPath .build/xcode \
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" build
app_path="$PWD/dist/ShareX Mac.app"
mkdir -p dist
ditto ".build/xcode/Build/Products/$xcode_configuration/ShareX Mac.app" "$app_path"
codesign --verify --strict "$app_path"
echo "Built: $app_path"
echo "Launch with: open \"$app_path\""
