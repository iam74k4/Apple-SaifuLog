#!/bin/bash
# 本物の端末内 AI（Foundation Models）の答え方のテスト（SaifuLogTests/AIEvaluation/ の AIEvaluationTests）を動かし、
# 1 つも飛ばされずに通ったことを確かめる。
#
#   ./scripts/test-ai.sh <宛先> <DerivedData> <結果の .xcresult> [xcodebuild に足す引数…]
#
# make test-ai が、make build-tests でビルドしたものを渡して呼ぶ。CI（build.yml）と make ci では動かさない（GitHub の
# ランナーの Mac では Apple Intelligence を使えず、モデルの答えは版や端末で揺れるため）。指示文・AI に渡すもの・AI の答えの
# 扱いを変えたときと、リリースの前に、Apple Intelligence をオンにした Mac で動かす。シミュレータの中の端末内 AI は、Mac の
# Apple Intelligence（とそのモデル）を使う。
#
# テストは Apple Intelligence が使えなければ飛ばす作り（Xcode の Test で動かしたときのため）。飛ばしただけでは結果は成功の
# ままで、何も確かめていないのに通ったように見えるので、ここでは次の 2 つで、飛ばしたことを失敗にする。
# - テストに REQUIRE_AI_EVALUATION=1 を渡す（xcodebuild は TEST_RUNNER_ を外してテストに渡す）。テストの側は、AI が使えなければ
#   飛ばさずに、使えない理由（Apple Intelligence がオフ・モデルの準備中など）をつけて失敗する（`AIEvaluation.requireModel()`）。
# - 結果の数（通った・失敗した・飛ばした）を出し、飛ばしたものが 1 つでもあるか、1 つも動かなければ失敗にする。
#
# 落ちたテストは動かし直さない。モデルの答えの揺れは、テストの側で表ごとの割合として許している（動かし直して通っても、答え方が
# 崩れていないとは言えない）。件ごとの答えとかかった時間は、テストのログ（xcodebuild の出力と結果の .xcresult）に表で出る。

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

rm -rf "$result"
status=0
# モデルはひとつずつ順に呼ぶ（テストの側も .serialized にしている）。同時に呼ぶと待ち合わせで遅くなり、時間を測れないため。
TEST_RUNNER_REQUIRE_AI_EVALUATION=1 xcodebuild test-without-building \
  -project SaifuLog.xcodeproj \
  -scheme SaifuLog \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  -only-testing:SaifuLogTests/AIEvaluationTests \
  -parallel-testing-enabled NO \
  -resultBundlePath "$result" \
  ${extra[@]+"${extra[@]}"} || status=$?

if [ ! -d "$result" ]; then
  echo "error: AI の答え方のテストの結果（${result}）がありません。xcodebuild が途中で止まった可能性があります。" >&2
  exit 1
fi

summary_status=0
xcrun xcresulttool get test-results summary --path "$result" --compact | python3 -c '
import json
import sys

summary = json.load(sys.stdin)
passed = summary.get("passedTests", 0)
failed = summary.get("failedTests", 0)
skipped = summary.get("skippedTests", 0)
print(f"AIEvaluationTests: 通った {passed}・失敗 {failed}・飛ばした {skipped}")
if skipped > 0:
    print(f"error: AI の答え方のテストが {skipped} 件飛ばされました。Mac の Apple Intelligence がオンで、モデルを入れ終えているかを確かめてください。")
    sys.exit(1)
if passed == 0 and failed == 0:
    print("error: AI の答え方のテストが 1 件も動きませんでした（-only-testing の名前がテストと合っているかを確かめてください）。")
    sys.exit(1)
' || summary_status=$?

if [ "$status" -ne 0 ]; then
  echo "error: AI の答え方のテストが落ちました。どの件がどう外れたかは、テストの失敗のメッセージ（xcodebuild の出力か ${result}）の表を見てください。" >&2
  exit "$status"
fi
exit "$summary_status"
