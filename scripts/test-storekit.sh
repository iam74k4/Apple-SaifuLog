#!/bin/bash
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
#
# 落ちたテストは 1 回だけ、そのテストだけを動かし直す。CI のランナーでは SKTestSession（Xcode のローカルの StoreKit の
# サーバー）が時々応えなくなり（ログに「Received failure in response from Xcode」「Server Error 1050」）、購入や返金の
# 途中で 1 分の制限を超えて落ちることがあった。動かし直して通れば成功にするが、どのテストが 1 回目に落ちたかを
# 警告（::warning::）に残す。本物の不具合なら 2 回目も落ちるので、失敗のまま止まる。飛ばしたものがあるときは
# 動かし直さない（使えないシミュレータで動かしている。動かし直しても直らない）。

set -eu

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <宛先> <DerivedData> <結果の .xcresult> [xcodebuild に足す引数…]" >&2
  exit 2
fi
destination=$1
derived_data=$2
result=$3
shift 3
extra=("$@")

# 購入のテストを動かす。$1 は結果の .xcresult、残りは -only-testing の引数。
run_tests() {
  local out=$1
  shift
  rm -rf "$out"
  local code=0
  TEST_RUNNER_REQUIRE_STOREKIT_TESTS=1 xcodebuild test-without-building \
    -project SaifuLog.xcodeproj \
    -scheme SaifuLog \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    "$@" \
    -resultBundlePath "$out" \
    ${extra[@]+"${extra[@]}"} || code=$?
  if [ ! -d "$out" ]; then
    echo "error: 購入のテストの結果（${out}）がありません。xcodebuild が途中で止まった可能性があります。" >&2
    return 1
  fi
  return "$code"
}

# 結果の数をログに出す。終了コード: 0 = 飛ばしたもの無しで 1 件以上通った、2 = 飛ばしたものがある、3 = 1 件も通っていない。
# 失敗したテストがあるかは xcodebuild の終了コードで見る（ここでは数を出すだけ）。
summarize() {
  local label=$1 path=$2
  xcrun xcresulttool get test-results summary --path "$path" --compact | LABEL="$label" python3 -c '
import json
import os
import sys

summary = json.load(sys.stdin)
label = os.environ["LABEL"]
passed = summary.get("passedTests", 0)
failed = summary.get("failedTests", 0)
skipped = summary.get("skippedTests", 0)
print(f"StoreKitPurchaseTests{label}: 通った {passed}・失敗 {failed}・飛ばした {skipped}")
if skipped > 0:
    print(f"::error::購入のテストが {skipped} 件飛ばされました。SKTestSession が使えないシミュレータで動かした可能性があります（STOREKIT_TEST_OS を確かめてください）。")
    sys.exit(2)
if passed == 0:
    # 動かし直し（落ちたものだけを動かす）では、落ちたままなら 0 件になる。そのときは最後の「動かし直しても落ちた」で知らせる。
    if not label:
        print("::error::購入のテストが 1 件も通っていません。")
    sys.exit(3)
'
}

# xcodebuild から宛先のシミュレータが見えるまで待つ（最大 2 分）。
# CI では、iOS 26.2 のランタイムを入れた直後に xcodebuild が新しいシミュレータをまだ知らず、
# 「Unable to find a device matching the provided destination specifier」で 1 件も動かずに落ちたことがある
# （同じイメージ・同じ手順の直前の実行は通っていた）。見えないまま時間切れになっても、そのまま進めて xcodebuild のエラーを出す。
wait_for_destination() {
  local udid
  udid=$(printf '%s\n' "$destination" | sed -n 's/.*id=\([0-9A-Fa-f-]*\).*/\1/p')
  [ -n "$udid" ] || return 0
  local tries=0
  while [ "$tries" -lt 12 ]; do
    if xcodebuild -project SaifuLog.xcodeproj -scheme SaifuLog -showdestinations 2>/dev/null | grep -q "id:${udid}"; then
      return 0
    fi
    tries=$((tries + 1))
    echo "宛先のシミュレータ（${udid}）がまだ xcodebuild から見えません。10 秒待ちます（${tries}/12）。" >&2
    sleep 10
  done
  echo "::warning::宛先のシミュレータ（${udid}）が 2 分待っても xcodebuild から見えませんでした。" >&2
}

# 落ちたテストの識別子（例: StoreKitPurchaseTests/purchaseNotAllowed()）を 1 行ずつ書く。
failed_tests() {
  xcrun xcresulttool get test-results tests --path "$1" --compact | python3 -c '
import json
import sys

def walk(node):
    if node.get("nodeType") == "Test Case" and node.get("result") == "Failed" and node.get("nodeIdentifier"):
        print(node["nodeIdentifier"])
    for child in node.get("children") or []:
        walk(child)

for node in json.load(sys.stdin).get("testNodes", []):
    walk(node)
'
}

wait_for_destination
status=0
run_tests "$result" -only-testing:SaifuLogTests/StoreKitPurchaseTests || status=$?
[ -d "$result" ] || exit 1

summary_code=0
summarize "" "$result" || summary_code=$?
# 1 件も動かなかった（宛先が見つからないなど、テストより前で止まった）ときは、宛先が見えるのを待って全体を 1 回動かし直す。
# 動いたうえで 1 件も通らなかったとき（全部落ちた）は、下の「落ちたものだけを動かし直す」に任せる。
if [ "$summary_code" -eq 3 ] && [ -z "$(failed_tests "$result")" ]; then
  echo "::warning::購入のテストが 1 件も動きませんでした。宛先のシミュレータが見えるのを待って、全体を 1 回動かし直します。"
  wait_for_destination
  status=0
  run_tests "$result" -only-testing:SaifuLogTests/StoreKitPurchaseTests || status=$?
  [ -d "$result" ] || exit 1
  summary_code=0
  summarize "（動かし直し）" "$result" || summary_code=$?
fi
if [ "$summary_code" -eq 2 ]; then
  exit 1
fi
if [ "$summary_code" -eq 3 ] && [ -z "$(failed_tests "$result")" ]; then
  echo "::error::購入のテストが 1 件も動きませんでした（動かし直しても同じ）。" >&2
  exit 1
fi
if [ "$status" -eq 0 ]; then
  exit 0
fi

failed=$(failed_tests "$result")
if [ -z "$failed" ]; then
  echo "error: xcodebuild は失敗しましたが、落ちたテストが結果にありません。" >&2
  exit 1
fi

retry_args=()
while IFS= read -r test_id; do
  [ -n "$test_id" ] && retry_args+=("-only-testing:SaifuLogTests/${test_id}")
done <<EOF
$failed
EOF

echo "::warning::購入のテストのうち次が落ちたので、そのテストだけを 1 回動かし直します: $(printf '%s ' $failed)"
retry_result="${result%.xcresult}-retry.xcresult"
retry_status=0
run_tests "$retry_result" "${retry_args[@]}" || retry_status=$?
[ -d "$retry_result" ] || exit 1

retry_summary=0
summarize "（動かし直し）" "$retry_result" || retry_summary=$?
if [ "$retry_status" -eq 0 ] && [ "$retry_summary" -eq 0 ]; then
  echo "::warning::購入のテストのうち $(printf '%s ' $failed)は 1 回目に落ち、動かし直すと通りました（CI のランナーの SKTestSession が応えなくなることがある）。何度も出るなら、テストか StoreKit の扱いを見直してください。"
  exit 0
fi
echo "::error::購入のテストは動かし直しても落ちました。" >&2
exit 1
