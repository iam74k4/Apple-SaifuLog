# SaifuLog — XcodeGen で Xcode プロジェクトを生成し、ビルドとテストを行う。
#
# Xcode 27 以降と XcodeGen（brew install xcodegen）が必要:
#
#   開発
#     make generate             project.yml から SaifuLog.xcodeproj を生成する
#     make build                生成 → シミュレータ向けに署名なしでビルド（CI と同じ経路）
#     make test                 SaifuLogCore のテスト（swift test）
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

# DerivedData をリポジトリの中（build/、.gitignore 済み）に置く。
# make clean で確実に消せるようにし、CI でも手元でも同じ場所を使うため。
DERIVED_DATA := build/DerivedData

# xcodebuild に足す引数（例: make build XCODEBUILD_FLAGS=-quiet）。
XCODEBUILD_FLAGS ?=

.PHONY: all generate build test open clean check-xcodegen

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
		CODE_SIGNING_ALLOWED=NO \
		$(XCODEBUILD_FLAGS)

# コアは SwiftUI / SwiftData / FoundationModels に依存しないので、シミュレータを起動せずに
# macOS 上の swift test だけで回せる。速く、CI のランナーの機種にも左右されない。
test:
	swift test --package-path $(CORE_PACKAGE)

open: generate
	open $(PROJECT)

clean:
	rm -rf build $(PROJECT) $(CORE_PACKAGE)/.build
	@echo "Cleaned."

# リリース用のターゲット（version / check-version / archive / export-ipa / upload）。
# 無くても開発用のターゲットは動くように、- を付けて読み込む。
-include release.mk
