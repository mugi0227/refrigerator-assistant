#!/bin/bash
set -euo pipefail
# The Swift package uses its released Apple XCFramework, not Android LFS assets.
export GIT_LFS_SKIP_SMUDGE=1
cd "$(dirname "$0")/.."
node scripts/prepare-ios.mjs
mkdir -p ios/build
swiftc ios/Fridge/AIStartupGuard.swift ios/Fridge/AIEngineLifetime.swift scripts/ai-startup-test/main.swift -o ios/build/test-ai-startup
ios/build/test-ai-startup
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
xcodegen generate --spec ios/project.yml
# The Gemma recovery build uses the precompiled LiteRT framework.
xcodebuild -project ios/Fridge.xcodeproj -scheme Fridge -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath ios/build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
mkdir -p ios/build/ipa/Payload
cp -R ios/build/Build/Products/Release-iphoneos/Fridge.app ios/build/ipa/Payload/
cd ios/build/ipa
zip -qry Fridge-unsigned.ipa Payload
python3 ../../../scripts/validate-ios-ipa.py Fridge-unsigned.ipa
echo "IPA: ios/build/ipa/Fridge-unsigned.ipa (AltServer/AltStore signs it on installation)"
