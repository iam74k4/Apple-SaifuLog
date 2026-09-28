#!/bin/sh
# アプリのテスト（SaifuLogTests）を動かすシミュレータを選び、xcodebuild の -destination の値を書く。
#
#   ./scripts/pick-simulator.sh     例: platform=iOS Simulator,id=DAE23823-0074-4186-91D3-B1E51FC097F8
#
# いちばん新しい iOS のランタイムにある、最初の iPhone を選ぶ。
# 機種の名前（「iPhone 17 Pro」など）を決め打ちすると、CI のランナーのイメージや手元の Xcode で
# その機種が無くなった日に、テストが「宛先が見つからない」で落ちるため。
# 使えるシミュレータが 1 台も無ければ、何も書かずに 1 で終わる。
#
# Makefile の make test-app が、TEST_DESTINATION を渡されなかったときに呼ぶ（CI の build.yml も同じ）。

set -eu

udid=$(xcrun simctl list devices available | awk '
  # 「-- iOS 26.4 --」の節ごとに、最初の iPhone の UDID を覚える。節は古い版から順に並ぶので、最後に覚えたものが
  # いちばん新しい版のもの。
  /^-- iOS / { in_ios = 1; found = 0; next }
  /^-- / { in_ios = 0; next }
  in_ios && !found && /^ +iPhone/ {
    if (match($0, /\([0-9A-F-]+\)/)) {
      last = substr($0, RSTART + 1, RLENGTH - 2)
      found = 1
    }
  }
  END { if (last != "") print last }
')

if [ -z "$udid" ]; then
  echo "error: 使える iPhone のシミュレータがありません（xcrun simctl list devices available）。" >&2
  exit 1
fi
echo "platform=iOS Simulator,id=$udid"
