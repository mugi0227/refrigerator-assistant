#!/bin/bash
set -euo pipefail
export GIT_LFS_SKIP_SMUDGE=1
cd "$(dirname "$0")/.."
mkdir -p local/native-runtime-fixture ios/FridgeRuntimeTests/Fixtures
MODEL_PATH="$PWD/local/native-runtime-fixture/gemma-4-E2B-it.litertlm"
MODEL_URL=$(python3 -c 'import re; print(re.search(r"https://huggingface[^\"]+",open("ios/Fridge/ModelStore.swift").read()).group())')
if [ ! -f "$MODEL_PATH" ]; then
  curl --fail --location --retry 2 --connect-timeout 30 --max-time 900 "$MODEL_URL" -o "$MODEL_PATH.partial"
  mv "$MODEL_PATH.partial" "$MODEL_PATH"
fi
python3 - "$MODEL_PATH" <<'PY'
import hashlib,json,re,sys
from pathlib import Path
p=Path(sys.argv[1]); source=Path('ios/Fridge/ModelStore.swift').read_text()
expected=int(re.search(r'expectedBytes: Int64 = ([\d_]+)',source).group(1).replace('_',''))
assert p.stat().st_size==expected, 'Incomplete real model fixture'
print('Actual model fixture:',p.stat().st_size,'bytes; SHA256:',hashlib.file_digest(p.open('rb'),'sha256').hexdigest())
Path('ios/FridgeRuntimeTests/Fixtures/config.json').write_text(json.dumps({'modelPath':str(p)}))
PY
node scripts/prepare-ios.mjs
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
xcodegen generate --spec ios/project.yml
SIMULATOR_ID=$(xcrun simctl list devices available --json | python3 scripts/choose-ios-simulator.py)
collect_results() {
  # XCTest may use a cloned simulator container rather than the selected UDID.
  # Copy only this app's uniquely named diagnostics, including after a timeout.
  python3 - <<'PY'
from pathlib import Path
import shutil
devices = Path.home() / 'Library/Developer/CoreSimulator/Devices'
for folder in devices.glob('*/data/Containers/Data/Application/*/Documents/NativeAI'):
    target = Path('ios/build-runtime/native-logs') / folder.parent.parent.name
    shutil.copytree(folder, target, dirs_exist_ok=True)
PY
  DATA_CONTAINER=$(xcrun simctl get_app_container "$SIMULATOR_ID" jp.mugilab.fridge data 2>/dev/null || true)
  if [ -n "$DATA_CONTAINER" ] && [ -d "$DATA_CONTAINER/Documents/GemmaProbe-CI" ]; then
    mkdir -p ios/build-runtime/probe-logs
    cp -R "$DATA_CONTAINER/Documents/GemmaProbe-CI/." ios/build-runtime/probe-logs/
  fi
  if [ -n "$DATA_CONTAINER" ] && [ -d "$DATA_CONTAINER/Documents/NativeAI" ]; then
    mkdir -p ios/build-runtime/native-logs
    cp -R "$DATA_CONTAINER/Documents/NativeAI/." ios/build-runtime/native-logs/
  fi
  for suite in Runtime Reference; do
    if [ -d "ios/build-runtime/$suite.xcresult" ]; then
      xcrun xcresulttool get test-results summary --path "ios/build-runtime/$suite.xcresult" > "ios/build-runtime/$suite-summary.json" || true
      xcrun xcresulttool export attachments --path "ios/build-runtime/$suite.xcresult" --output-path "ios/build-runtime/$suite-attachments" || true
    fi
  done
}
trap collect_results EXIT
# Keep the production engine's complete food -> recovery -> recipes sequence in
# one process. The unmodified upstream control gets a fresh test-host process;
# native model teardown/reinitialization is a known unresolved runtime condition.
result=0
xcodebuild -project ios/Fridge.xcodeproj -scheme FridgeRuntime -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID,arch=arm64" -derivedDataPath ios/build-runtime \
  -resultBundlePath ios/build-runtime/Runtime.xcresult CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 360 \
  -skip-testing:FridgeRuntimeTests/ReferenceProbeTests "$@" test || result=1
xcodebuild -project ios/Fridge.xcodeproj -scheme FridgeRuntime -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID,arch=arm64" -derivedDataPath ios/build-runtime \
  -resultBundlePath ios/build-runtime/Reference.xcresult CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 240 \
  -only-testing:FridgeRuntimeTests/ReferenceProbeTests "$@" test-without-building || result=1
exit "$result"
