#!/bin/sh
# 購入のテスト（SaifuLogTests/StoreKitPurchaseTests）を動かし、1 つも飛ばされずに通ったことを確かめる。
#
#   ./scripts/test-storekit.sh <宛先> <DerivedData> <結果の .xcresult> [xcodebuild に足す引数…]
#
# make test-storekit が、make build-tests でビルドしたものを渡して呼ぶ（CI の build.yml も同じ）。
#
# 購入のテストは、SKTestSession が使えないシミュレータ（iOS 26.3・26.4。Apple の不具合）では飛ばす作りにしている
# （本物の App Store の Sandbox につながり、購入の確認を待ち続けるため）。飛ばしただけでは結果は成功のままなので、
# CI が緑のまま購入・返金・承認待ち・復元の不具合を通してしまう。ここでは次の 2 つで、飛ばしたことを失敗にする。
# - テストに REQUIRE_STOREKIT_TESTS=1 を渡す（xcodebuild は TEST_RUNNER_ を外してテストに渡す）。テストの側は、
#   使えないシミュレータなら飛ばさずに失敗する（`StoreKitTestEnvironment.isRequired`）。
# - 結果の数（通った・失敗した・飛ばした）をログに出し、飛ばしたものが 1 つでもあるか、通ったものが 0 なら失敗にする。

set -eu

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <宛先> <DerivedData> <結果の .xcresult> [xcodebuild に足す引数…]" >&2
  exit 2
fi
destination=$1
derived_data=$2
result=$3
shift 3

rm -rf "$result"
status=0
TEST_RUNNER_REQUIRE_STOREKIT_TESTS=1 xcodebuild test-without-building \
  -project SaifuLog.xcodeproj \
  -scheme SaifuLog \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  -only-testing:SaifuLogTests/StoreKitPurchaseTests \
  -resultBundlePath "$result" \
  "$@" || status=$?

if [ ! -d "$result" ]; then
  echo "error: 購入のテストの結果（$result）がありません。xcodebuild が途中で止まった可能性があります。" >&2
  exit 1
fi

# xcodebuild が失敗していても、数は出してから終わる（飛ばしたのか落ちたのかをログだけで分かるように）。
xcrun xcresulttool get test-results summary --path "$result" --compact | python3 -c '
import json
import sys

summary = json.load(sys.stdin)
passed = summary.get("passedTests", 0)
failed = summary.get("failedTests", 0)
skipped = summary.get("skippedTests", 0)
print(f"StoreKitPurchaseTests: 通った {passed}・失敗 {failed}・飛ばした {skipped}")
if skipped > 0:
    print(f"::error::購入のテストが {skipped} 件飛ばされました。SKTestSession が使えないシミュレータで動かした可能性があります（STOREKIT_TEST_OS を確かめてください）。")
    sys.exit(1)
if passed == 0:
    print("::error::購入のテストが 1 件も通っていません。")
    sys.exit(1)
' || status=1

exit "$status"
