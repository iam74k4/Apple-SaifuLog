#!/bin/sh
# 購入のテスト（make test-storekit）に使う版の iPhone のシミュレータを用意し、xcodebuild の -destination の値を書く。
#
#   ./scripts/prepare-storekit-simulator.sh 26.2
#
# CI の build.yml が make test-storekit の前に呼ぶ。SKTestSession は iOS 26.3・26.4 のシミュレータでは
# xcodebuild test から使えない（Apple の不具合）ので、動くことを確かめた版（Makefile の STOREKIT_TEST_OS）で動かす。
# ランナーのイメージにその版のランタイムが無ければ xcodebuild -downloadPlatform で入れ（数 GB・数分かかる）、
# その版の iPhone が無ければ作る。手元では、ランタイムを入れる前に確かめたいときだけ使う（make test-storekit は
# ランタイムを入れず、無ければ入れ方を示して止まる）。

set -eu

os="${1:?iOS の版を渡してください（例: 26.2）}"

if destination=$(./scripts/pick-simulator.sh "$os" 2>/dev/null); then
  echo "$destination"
  exit 0
fi

# 「iOS 26.2 (26.2 - 23C54) - com.apple.CoreSimulator.SimRuntime.iOS-26-2」の行から、その版のランタイムの ID を読む。
runtime_id() {
  xcrun simctl list runtimes available | awk -v os="$os" '$1 == "iOS" && $2 == os { id = $NF } END { if (id != "") print id }'
}

if [ -z "$(runtime_id)" ]; then
  echo "iOS $os のシミュレータのランタイムがないので入れます（xcodebuild -downloadPlatform iOS -buildVersion ${os}）。" >&2
  xcodebuild -downloadPlatform iOS -buildVersion "$os" >&2
fi
runtime=$(runtime_id)
if [ -z "$runtime" ]; then
  echo "error: iOS $os のシミュレータのランタイムを入れられませんでした。" >&2
  exit 1
fi

# そのランタイムで動く iPhone の機種のうち、いちばん新しいもの（動く iOS の下限がいちばん高いもの）で作る。
device_type=$(xcrun simctl list runtimes -j | python3 -c '
import json
import sys

runtime = sys.argv[1]
for entry in json.load(sys.stdin)["runtimes"]:
    if entry["identifier"] != runtime:
        continue
    phones = [t for t in entry.get("supportedDeviceTypes", []) if t.get("productFamily") == "iPhone"]
    if phones:
        print(max(phones, key=lambda t: t.get("minRuntimeVersion", 0))["identifier"])
    break
' "$runtime")
if [ -z "$device_type" ]; then
  echo "error: iOS $os のランタイムで動く iPhone の機種がありません。" >&2
  exit 1
fi
xcrun simctl create "iPhone (iOS $os)" "$device_type" "$runtime" >&2
./scripts/pick-simulator.sh "$os"
