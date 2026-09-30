# SaifuLog — XcodeGen で Xcode プロジェクトを生成し、ビルドとテストを行う。
#
# Xcode 27 以降と XcodeGen（brew install xcodegen）が必要:
#
#   開発
#     make generate             project.yml から SaifuLog.xcodeproj を生成する
#     make build                生成 → シミュレータ向けに署名なしでビルド（CI と同じ経路）
#     make test                 SaifuLogCore のテスト（swift test）
#     make build-tests          アプリのテスト（SaifuLogTests）をビルドする（動かさない。CI と同じ経路）
#     make test-app             アプリのテストをシミュレータで動かす（TEST_DESTINATION で宛先を変えられる。購入のテストは除く）
#     make test-storekit        購入のテスト（SKTestSession）を、それが動く iOS の版（STOREKIT_TEST_OS）のシミュレータで動かし、
#                               1 つでも飛ばされたら失敗にする
#     make check-strings        String Catalog とコードの文字列の整合を確かめる（make build の後に）
#     make ci                   CI（build.yml）と同じ 8 つ（build / check-strings / test / build-tests / test-app /
#                               test-storekit / check-version / 署名なしの archive）
#     make open                 生成して Xcode で開く
#     make clean                生成物とビルドの残りを消す
#
#   リリース（release.mk）
#     make version / check-version / archive / export-ipa / upload
#
# SaifuLog.xcodeproj は生成物で、コミットしない。設定は project.yml と Config/Base.xcconfig に書く。
# xcodeproj を直接いじっても、次の make generate で消える。

PROJECT      := SaifuLog.xcodeproj
SCHEME       := SaifuLog
CORE_PACKAGE := Packages/SaifuLogCore

# 実機やシミュレータの機種を指定しない汎用の宛先。CI のランナーに入っているシミュレータの
# 機種や OS の版に左右されずにビルドできる。
DESTINATION  := generic/platform=iOS Simulator

# シミュレータ向けにビルドする CPU。汎用の宛先では ONLY_ACTIVE_ARCH が効かず、指定しないと
# 使わない x86_64 まで毎回コンパイルして時間が約 2 倍になる。CI のランナーも手元の Mac も
# Apple シリコンなので arm64 だけにする（Intel の Mac なら make build SIM_ARCHS=x86_64）。
# 提出用の archive（generic/platform=iOS）はもともと arm64 だけなので関係しない。
SIM_ARCHS    ?= arm64

# DerivedData をリポジトリの中（build/、.gitignore 済み）に置く。
# make clean で確実に消せるようにし、CI でも手元でも同じ場所を使うため。
DERIVED_DATA := build/DerivedData

# xcodebuild に足す引数（例: make build XCODEBUILD_FLAGS=-quiet）。
XCODEBUILD_FLAGS ?=

# アプリのテスト（SaifuLogTests）を動かすシミュレータ。渡さなければ、入っているシミュレータから
# いちばん新しい iOS の iPhone を選ぶ（scripts/pick-simulator.sh）。機種の名前を決め打ちすると、
# CI のランナーのイメージや手元の Xcode でその機種が無くなった日に落ちるため。
# 例: make test-app TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro'
TEST_DESTINATION ?= $(shell ./scripts/pick-simulator.sh)

# 購入のテスト（SaifuLogTests/StoreKitPurchaseTests）を動かすシミュレータの iOS の版。SKTestSession は iOS 26.3・26.4 の
# シミュレータでは xcodebuild test から使えず（Apple の不具合。設定ファイルを渡せず、本物の Sandbox につながる）、
# テストは飛ばされる。いちばん新しい版を選ぶ TEST_DESTINATION では購入のテストが 1 つも動かないまま CI が緑になるので、
# 動くことを確かめた版を決めて動かす。ほかの版で動くと確かめたら、ここを変える（CI の build.yml も同じ値を読む）。
STOREKIT_TEST_OS ?= 27.0
# 例: make test-storekit STOREKIT_TEST_DESTINATION='platform=iOS Simulator,OS=26.2,name=iPhone 17 Pro'
STOREKIT_TEST_DESTINATION ?= $(shell ./scripts/pick-simulator.sh $(STOREKIT_TEST_OS) 2>/dev/null)
# 購入のテストの結果。飛ばした数を数えるのに使う（scripts/test-storekit.sh）。
STOREKIT_TEST_RESULT := build/StoreKitPurchaseTests.xcresult

.PHONY: all generate build build-tests test test-app test-storekit print-storekit-os check-strings ci open clean check-xcodegen

all: build

# xcodegen が無いと「command not found」だけで止まり、何を入れればよいか分からない。
check-xcodegen:
	@command -v xcodegen >/dev/null 2>&1 || { \
		echo "error: xcodegen が見つかりません。brew install xcodegen で入れてください。"; \
		echo "       SaifuLog.xcodeproj は project.yml から生成するため、ビルドの前に必要です。"; \
		exit 1; \
	}

generate: check-xcodegen
	xcodegen generate --spec project.yml

# 署名なし（CODE_SIGNING_ALLOWED=NO）にするのは、証明書の無い CI のランナーでも
# 手元と同じコマンドで通すため。署名が要るのは提出用の archive（release.mk）だけ。
build: generate
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		ARCHS=$(SIM_ARCHS) \
		CODE_SIGNING_ALLOWED=NO \
		$(XCODEBUILD_FLAGS)

# コアは SwiftUI / SwiftData / FoundationModels に依存しないので、シミュレータを起動せずに
# macOS 上の swift test だけで回せる。速く、CI のランナーの機種にも左右されない。
test:
	swift test --package-path $(CORE_PACKAGE)

# アプリのテスト（SaifuLogTests）と、スキームのテストに入っている全ターゲットをビルドする（動かさない）。
# make build はスキームの build アクション（SaifuLog だけ）なので、テストのターゲットがコンパイルできなく
# なっても通ってしまう。宛先と引数は make build と同じ（汎用のシミュレータ・署名なし・SIM_ARCHS だけ）。
build-tests: generate
	xcodebuild build-for-testing \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		ARCHS=$(SIM_ARCHS) \
		CODE_SIGNING_ALLOWED=NO \
		$(XCODEBUILD_FLAGS)

# アプリのテストをシミュレータで動かす。先に build-tests を通し（変わったところだけビルドし直す）、
# できたものを test-without-building でそのまま動かす。
# コアのテスト（SaifuLogCoreTests）は make test の swift test で回しているので、ここでは SaifuLogTests だけ。
# 購入のテスト（StoreKitPurchaseTests）は除き、make test-storekit で動かす。いちばん新しい版のシミュレータでは
# SKTestSession が動かずに飛ばされ、飛ばしたことが結果の成功に紛れるため。
# 宛先が id= で決まっているときは、先に起動して起動し終えるまで待つ（simctl bootstatus -b）。起動の途中で
# テストのアプリを開こうとすると「Busy (Application failed preflight checks)」で落ちることがあるため。
test-app: build-tests
	@test -n "$(TEST_DESTINATION)" || { echo "error: アプリのテストを動かすシミュレータがありません。TEST_DESTINATION で宛先を渡してください。"; exit 1; }
	@udid=$$(printf '%s\n' '$(TEST_DESTINATION)' | sed -n 's/.*id=\([0-9A-Fa-f-]*\).*/\1/p'); \
		if [ -n "$$udid" ]; then xcrun simctl bootstatus "$$udid" -b >/dev/null; fi
	xcodebuild test-without-building \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(TEST_DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:SaifuLogTests \
		-skip-testing:SaifuLogTests/StoreKitPurchaseTests \
		$(XCODEBUILD_FLAGS)

# 購入のテスト（StoreKit の設定ファイルと SKTestSession）を、STOREKIT_TEST_OS の版のシミュレータで動かす。
# テストに REQUIRE_STOREKIT_TESTS=1 を渡して、使えないシミュレータでは飛ばさずに失敗させ、結果の数をログに出して、
# 1 つでも飛ばされたら失敗にする（scripts/test-storekit.sh）。その版のシミュレータが無ければ、入れ方を示して止まる
# （ランタイムは数 GB あるので、手元では勝手に入れない。CI は scripts/prepare-storekit-simulator.sh で入れる）。
test-storekit: build-tests
	@test -n "$(STOREKIT_TEST_DESTINATION)" || { \
		echo "error: iOS $(STOREKIT_TEST_OS) の iPhone のシミュレータがありません。購入のテストは SKTestSession の動く版で動かします。"; \
		echo "       ./scripts/prepare-storekit-simulator.sh $(STOREKIT_TEST_OS) で入れるか（xcodebuild -downloadPlatform iOS -buildVersion $(STOREKIT_TEST_OS)）、"; \
		echo "       STOREKIT_TEST_DESTINATION で宛先を渡してください。"; \
		exit 1; \
	}
	@udid=$$(printf '%s\n' '$(STOREKIT_TEST_DESTINATION)' | sed -n 's/.*id=\([0-9A-Fa-f-]*\).*/\1/p'); \
		if [ -n "$$udid" ]; then xcrun simctl bootstatus "$$udid" -b >/dev/null; fi
	./scripts/test-storekit.sh '$(STOREKIT_TEST_DESTINATION)' $(DERIVED_DATA) $(STOREKIT_TEST_RESULT) $(XCODEBUILD_FLAGS)

# 購入のテストを動かす iOS の版を書く。CI の build.yml が、その版のシミュレータを用意するのに使う
# （版を Makefile の 1 か所だけに書くため）。
print-storekit-os:
	@echo $(STOREKIT_TEST_OS)

# String Catalog（Localizable.xcstrings）とコードの文字列が食い違っていないかを確かめる（scripts/check-strings.py）。
# 足りないキー・使われていないキー・en の無いキー・ja と en の書式指定子の不一致があれば失敗する。
# ビルドの中では確かめられない（Xcode は足りないキーを、カタログを開いたときにしか足さない）ので、make build が
# 書き出した Debug の .stringsdata（コードの中の訳す文字列の一覧）を使う。make build の後に走らせる（build.yml も同じ順）。
# Debug を使うのは、診断画面（DEBUG と社内テスト用のビルドだけ）の文字列も数えるため。
check-strings:
	python3 scripts/check-strings.py \
		--catalog SaifuLog/Resources/Localizable.xcstrings \
		--stringsdata-dir $(DERIVED_DATA)/Build/Intermediates.noindex/SaifuLog.build/Debug-iphonesimulator/SaifuLog.build/Objects-normal

# 必須チェック build（.github/workflows/build.yml）と同じ確認を手元で通す。make build が
# 通っても、CI はテスト（コア・アプリ・購入）・版の検査・提出用のアーカイブまで見るので、それだけでは足りない。
# 引数は build.yml と同じにする（片方を変えたらもう片方も）。BUILD_NUMBER が xcconfig の
# 既定値（1）と重ならないのは、ビルド番号の上書きの検査を素通りさせないため。
# CI は失敗しても残りのステップを続けるが、こちらは最初の失敗で止まる。
ci:
	$(MAKE) build
	$(MAKE) check-strings
	$(MAKE) test
	$(MAKE) build-tests
	$(MAKE) test-app
	$(MAKE) test-storekit
	$(MAKE) check-version
	$(MAKE) archive ARCHIVE_SIGNING=NO BUILD_NUMBER=99999

open: generate
	open $(PROJECT)

clean:
	rm -rf build $(PROJECT) $(CORE_PACKAGE)/.build
	@echo "Cleaned."

# リリース用のターゲット（version / check-version / archive / export-ipa / upload）。
# 無くても開発用のターゲットは動くように、- を付けて読み込む。
-include release.mk
