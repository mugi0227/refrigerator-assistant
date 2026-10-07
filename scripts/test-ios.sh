#!/bin/bash
set -euo pipefail
export GIT_LFS_SKIP_SMUDGE=1
cd "$(dirname "$0")/.."
node scripts/prepare-ios.mjs
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
xcodegen generate --spec ios/project.yml
SIMULATOR_ID=$(xcrun simctl list devices available --json | python3 -c 'import sys,json; data=json.load(sys.stdin); phones=[(tuple(int(n) for n in runtime.split("iOS-")[1].split("-")),d["name"],d["udid"]) for runtime,devices in data["devices"].items() if "iOS-" in runtime for d in devices if d["name"].startswith("iPhone")]; print(max(phones)[2])')
collect_results() {
  if [ -f ios/build-simulator/Build/Products/Debug-iphonesimulator/Fridge.app/Info.plist ]; then
    cp ios/build-simulator/Build/Products/Debug-iphonesimulator/Fridge.app/Info.plist ios/build-simulator/app-info.plist
  fi
  if [ -d ios/build-simulator/UI.xcresult ]; then
    xcrun xcresulttool get test-results summary --path ios/build-simulator/UI.xcresult > ios/build-simulator/summary.json || true
    xcrun xcresulttool export attachments --path ios/build-simulator/UI.xcresult --output-path ios/build-simulator/screenshots || true
  fi
}
trap collect_results EXIT
xcodebuild -project ios/Fridge.xcodeproj -scheme Fridge -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID,arch=arm64" -derivedDataPath ios/build-simulator \
  -resultBundlePath ios/build-simulator/UI.xcresult CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
