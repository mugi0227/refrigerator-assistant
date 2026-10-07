#!/bin/bash
set -euo pipefail
export GIT_LFS_SKIP_SMUDGE=1
cd "$(dirname "$0")/.."
node scripts/prepare-ios.mjs
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
xcodegen generate --spec ios/project.yml
SIMULATOR_ID=$(xcrun simctl list devices available --json | python3 -c 'import sys,json; data=json.load(sys.stdin); phones=[d for devices in data["devices"].values() for d in devices if d["name"].startswith("iPhone")]; print(phones[-1]["udid"])')
xcodebuild -project ios/Fridge.xcodeproj -scheme Fridge -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -derivedDataPath ios/build-simulator \
  -resultBundlePath ios/build-simulator/UI.xcresult CODE_SIGNING_ALLOWED=NO test
