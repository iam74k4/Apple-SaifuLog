#!/bin/bash
# App Store のスクリーンショットを撮る。
#
#   ./scripts/app-store-screenshots.sh              日本語と英語で、すべての画面を撮る
#   SCREENSHOT_LANGUAGES=ja ./scripts/app-store-screenshots.sh     日本語だけ
#   SCREENSHOT_SCREENS="home ask" ./scripts/app-store-screenshots.sh  画面を選ぶ
#
# 撮影用のデモ（SaifuLog/ScreenshotDemo/。DEBUG のビルドだけに入る）を使う。アプリを起動引数
# `-SaifuLogScreenshotDemo <画面>` で開くと、メモリの上の架空の記録で撮る画面を開くので、利用者の記録も
# 開発用の表示（診断のボタン）も写らない。Release のビルドに入っていないことは make archive が確かめる。
#
# 流れ: make build（Debug・シミュレータ向け・署名なし）→ 撮影用の iPhone 17 Pro Max のシミュレータ（6.9 インチ、
# 1320 × 2868。無ければ作る）を起動 → ライトの外観・状態バーを 9:41・電波と Wi‑Fi と電池を満タンにする →
# 言語ごと・画面ごとに起動して `xcrun simctl io screenshot` で docs/app-store/screenshots/<言語>/NN-<画面>.png に保存 →
# 透過の層を外す（scripts/screenshot-image.swift）→ 画像の大きさと、透過と Dynamic Island の写り込みが無いことを確かめる。
#
# 撮影用のシミュレータは専用のもの（名前は SCREENSHOT_DEVICE_NAME）を使う。ふだん使うシミュレータの状態バーや外観を
# 書き換えないため。撮り終えたら状態バーの上書きを外す。
#
# 撮ったら、画像を 1 枚ずつ目で確かめる（表示崩れ・開発用の表示・英語の画面の訳し忘れが無いか。写っているのが架空の
# デモの記録だけか）。リポジトリは公開なので、個人の情報や本物の記録を写した画像をコミットしない。
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE_NAME="${SCREENSHOT_DEVICE_NAME:-SaifuLog App Store (iPhone 17 Pro Max)}"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max"
EXPECTED_WIDTH=1320
EXPECTED_HEIGHT=2868
OUTPUT_DIR="${SCREENSHOT_OUTPUT_DIR:-docs/app-store/screenshots}"
APP="build/DerivedData/Build/Products/Debug-iphonesimulator/SaifuLog.app"
# 起動してから撮るまでの秒数（撮影用のデモは、ホームが出てから 0.8 秒待って画面を開く。シートや横に進む動きが済むまで待つ）。
# iOS 27.0 のシミュレータでは、起動して最初の画面が出るまでに 6 秒近くかかることがあり、6 秒では白い画面や、シートを
# 出す前のホームが写った（2026-10-02）。余裕を見て 12 秒にする。
WAIT_SECONDS="${SCREENSHOT_WAIT_SECONDS:-12}"
read -r -a LANGUAGES <<< "${SCREENSHOT_LANGUAGES:-ja en}"
# 撮る順（ファイル名の番号の順）。App Store に並べる順の案でもある。premium（プレミアムのシートの価格と購入のボタン）と
# trial（同じシートの 14 日間の無料体験）は課金アイテムの審査用で、ストアには載せない（ガイドライン 2.3.7。ストアの
# スクリーンショットに価格を入れない）。
read -r -a SCREENS <<< "${SCREENSHOT_SCREENS:-home ask receipt voice report recap premium trial}"
ALL_SCREENS=(home ask receipt voice report recap premium trial)
# 起動したばかりのシミュレータは、しばらくの間 iOS の知らせ（「Apple Intelligence の準備ができました」など）を画面の上に
# 出す。写り込まないよう、起動し直したときはこの秒数だけ待ってから撮る。
BOOT_SETTLE_SECONDS="${SCREENSHOT_BOOT_SETTLE_SECONDS:-45}"

# 撮影用のデモの印（release.mk と SaifuLog/ScreenshotDemo/ScreenshotDemo.swift の marker と同じ値）。
MARKER=$(sed -n 's/^RELEASE_SCREENSHOT_DEMO_MARKER[[:space:]]*:=[[:space:]]*//p' release.mk)
if [ -z "$MARKER" ]; then
	echo "error: release.mk に RELEASE_SCREENSHOT_DEMO_MARKER がありません。" >&2
	exit 1
fi

locale_for() {
	case "$1" in
		ja) echo ja_JP ;;
		en) echo en_US ;;
		*) echo "error: 撮れる言語は ja と en です（いま: $1）。" >&2; exit 1 ;;
	esac
}

number_for() {
	local i
	for i in "${!ALL_SCREENS[@]}"; do
		if [ "${ALL_SCREENS[$i]}" = "$1" ]; then
			printf '%02d' $((i + 1))
			return
		fi
	done
	echo "error: 知らない画面です: $1（撮れるのは ${ALL_SCREENS[*]}）" >&2
	exit 1
}

for language in "${LANGUAGES[@]}"; do locale_for "$language" > /dev/null; done
for screen in "${SCREENS[@]}"; do number_for "$screen" > /dev/null; done

echo "--- ビルド（Debug・シミュレータ向け）"
make build XCODEBUILD_FLAGS=-quiet
if [ ! -d "$APP" ]; then
	echo "error: $APP ができていません。" >&2
	exit 1
fi
# 撮影用のデモの印が Debug のアプリにあることを確かめる。無ければデモが入っていない（撮れない）うえ、release.mk の
# 「Release に入っていないか」の確かめも空振りしている（印の値の食い違い）。
if ! grep -r -a -F -q "$MARKER" "$APP"; then
	echo "error: Debug のアプリに撮影用のデモの印（$MARKER）が見つかりません。SaifuLog/ScreenshotDemo/ScreenshotDemo.swift の marker と release.mk の RELEASE_SCREENSHOT_DEMO_MARKER が同じ値かを確かめてください。" >&2
	exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")

echo "--- シミュレータ（$DEVICE_NAME）"
# いちばん新しい iOS のランタイムに、撮影用のシミュレータを探す（無ければ作る）。
read -r RUNTIME UDID < <(xcrun simctl list -j runtimes devices | python3 -c '
import json, sys
name, device_type = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin)
runtimes = [r for r in data["runtimes"] if r.get("isAvailable") and r.get("platform") == "iOS"
            and any(t.get("identifier") == device_type for t in r.get("supportedDeviceTypes", []))]
if not runtimes:
    sys.exit("error: iPhone 17 Pro Max を動かせる iOS のランタイムがありません。Xcode の Settings → Components で入れてください。")
runtime = max(runtimes, key=lambda r: [int(p) for p in r["version"].split(".")])["identifier"]
devices = [d for d in data["devices"].get(runtime, []) if d.get("name") == name and d.get("isAvailable")]
print(runtime, devices[0]["udid"] if devices else "-")
' "$DEVICE_NAME" "$DEVICE_TYPE")
if [ -z "${RUNTIME:-}" ]; then
	echo "error: シミュレータのランタイムを読めませんでした。" >&2
	exit 1
fi
if [ "$UDID" = "-" ]; then
	UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")
	echo "作りました: $UDID（$RUNTIME）"
fi
echo "UDID: $UDID（$RUNTIME）"

state=$(xcrun simctl list -j devices | python3 -c '
import json, sys
udid = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for d in devices:
        if d["udid"] == udid:
            print(d["state"])
' "$UDID")
if [ "$state" != "Booted" ]; then
	xcrun simctl boot "$UDID"
	xcrun simctl bootstatus "$UDID" -b > /dev/null
	echo "起動しました。iOS の知らせが消えるのを ${BOOT_SETTLE_SECONDS} 秒待ちます。"
	sleep "$BOOT_SETTLE_SECONDS"
fi
trap 'xcrun simctl status_bar "$UDID" clear > /dev/null 2>&1 || true' EXIT
xcrun simctl ui "$UDID" appearance light
# 電池は満タンで、充電中の印（稲妻）を出さない。charged にすると満タンでも稲妻が付き、充電中に見える。
xcrun simctl status_bar "$UDID" override \
	--time "9:41" \
	--dataNetwork wifi --wifiMode active --wifiBars 3 \
	--cellularMode active --cellularBars 4 \
	--operatorName "" \
	--batteryState discharging --batteryLevel 100
xcrun simctl install "$UDID" "$APP"

failed=0
for language in "${LANGUAGES[@]}"; do
	locale=$(locale_for "$language")
	mkdir -p "$OUTPUT_DIR/$language"
	for screen in "${SCREENS[@]}"; do
		out="$OUTPUT_DIR/$language/$(number_for "$screen")-$screen.png"
		# Dynamic Island の黒い形がときどき写り込むので、写っていたら撮り直す（3 回まで）。
		for attempt in 1 2 3; do
			xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
			xcrun simctl launch "$UDID" "$BUNDLE_ID" \
				-AppleLanguages "($language)" -AppleLocale "$locale" \
				-SaifuLogScreenshotDemo "$screen" > /dev/null
			sleep "$WAIT_SECONDS"
			xcrun simctl io "$UDID" screenshot --type=png "$out" > /dev/null 2>&1
			if ! xcrun swift scripts/screenshot-image.swift has-island "$out"; then
				break
			fi
			echo "Dynamic Island が写り込みました。撮り直します（$out、${attempt} 回目）。"
		done
		# App Store Connect は透過の層（アルファチャンネル）のある画像を受け付けないので、層を外す。
		xcrun swift scripts/screenshot-image.swift flatten "$out"
		island=no
		if xcrun swift scripts/screenshot-image.swift has-island "$out"; then island=yes; fi
		width=$(sips -g pixelWidth "$out" | awk '/pixelWidth/ { print $2 }')
		height=$(sips -g pixelHeight "$out" | awk '/pixelHeight/ { print $2 }')
		alpha=$(sips -g hasAlpha "$out" | awk '/hasAlpha/ { print $2 }')
		if [ "$width" != "$EXPECTED_WIDTH" ] || [ "$height" != "$EXPECTED_HEIGHT" ]; then
			echo "error: $out の大きさが ${width} × ${height} です（${EXPECTED_WIDTH} × ${EXPECTED_HEIGHT} のはず）。" >&2
			failed=1
		elif [ "$alpha" != no ]; then
			echo "error: $out に透過の層が残っています（App Store Connect が受け付けません）。" >&2
			failed=1
		elif [ "$island" = yes ]; then
			echo "error: $out に Dynamic Island の黒い形が写っています（3 回撮り直しても消えませんでした）。" >&2
			failed=1
		else
			echo "OK: $out（${width} × ${height}、透過なし）"
		fi
	done
done
xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true

if [ "$failed" -ne 0 ]; then
	exit 1
fi
echo "撮り終えました。画像を 1 枚ずつ目で確かめてください（表示崩れ・開発用の表示・訳し忘れ・架空の記録だけか）。"
