# release.mk — App Store へ出すための make ターゲット。Makefile の末尾で -include する。
#
#   make version                       いまの MARKETING_VERSION を表示する
#   make check-version                 MARKETING_VERSION と CHANGELOG.md の先頭の見出しが一致するか確かめる
#   make archive [BUILD_NUMBER=123]    Release の .xcarchive を build/ に作る
#   make export-ipa                    アーカイブから .ipa を書き出すだけ（送信しない。疎通確認用）
#   make upload                        アーカイブを App Store Connect へ送る（本当に送信される）
#
# 認証: 環境変数 ASC_API_KEY_ID / ASC_API_ISSUER_ID / ASC_API_KEY_PATH（.p8 のパス）が
# 3 つとも揃っていれば App Store Connect API キーで認証する。1 つも無ければ、Xcode に
# サインインしているアカウントを使う（手元向け）。
#
# ふだんのリリースは CI（.github/workflows/release.yml）が行う。手元の archive / upload は
# CI が使えないときの逃げ道。流れの全体は docs/release-flow.md を参照。
#
# 開発用のターゲット（generate / build / test / clean / open）は Makefile にある。
# ここで同じ名前を定義すると後勝ちで黙って上書きされるので、ターゲットは上の 5 つ
# （と内部用の release-auth / release-args）だけにし、変数には RELEASE_ を付けて
# 名前の衝突を避ける。

RELEASE_PROJECT        := SaifuLog.xcodeproj
RELEASE_SCHEME         := SaifuLog
RELEASE_ARCHIVE        := build/SaifuLog.xcarchive
RELEASE_EXPORT_DIR     := build/export
RELEASE_EXPORT_OPTIONS := Config/ExportOptions.plist
# Makefile の make build と同じ場所。リポジトリの中（build/、.gitignore 済み）に置き、
# make clean でまとめて消えるようにする。
RELEASE_DERIVED_DATA   := build/DerivedData
# make export-ipa 用。ExportOptions.plist の destination だけを export に替えた写し。
RELEASE_EXPORT_OPTIONS_LOCAL := build/ExportOptions.export.plist

# ビルド番号（CFBundleVersion）の上書き。空なら Config/Base.xcconfig の
# CURRENT_PROJECT_VERSION のまま。App Store Connect は同じ版の中で番号の重複を
# 受け付けないので、CI は実行ごとに増える番号を渡す（release.yml）。
BUILD_NUMBER ?=

# アーカイブの段階で署名するか。CI は NO を渡す。
#
# 使い捨てのランナーで自動署名のまま archive すると、そのたびに Apple Development
# 証明書が新しく作られ、秘密鍵はランナーと一緒に消える。証明書が溜まるうえ、次の実行で
# 「秘密鍵の無い証明書」を掴んで失敗することがある。App Store 向けの署名は export の
# 段階で（クラウド管理の配布証明書で）掛け直されるので、archive は署名なしで足りる。
#
# ただし署名なしのアーカイブにはエンタイトルメントが焼かれない。iCloud や App Groups
# などの Capability を足したら、make export-ipa の出力に載っているかを必ず確かめる
# （docs/release-flow.md の「Capability（iCloud など）を足すとき」）。
ARCHIVE_SIGNING ?= YES

# 3 つとも揃っているときだけ API キーの認証フラグを付ける。
RELEASE_AUTH = $(if $(and $(ASC_API_KEY_ID),$(ASC_API_ISSUER_ID),$(ASC_API_KEY_PATH)),-authenticationKeyPath "$(ASC_API_KEY_PATH)" -authenticationKeyID "$(ASC_API_KEY_ID)" -authenticationKeyIssuerID "$(ASC_API_ISSUER_ID)")

.PHONY: version check-version archive export-ipa upload release-auth release-args

# バージョンの読み方は scripts/check-version.sh の 1 か所に寄せている。
# CI（build / release / tag-release）もこれを呼ぶので、書式を変えても片方だけ
# 読めなくなることがない。
version:
	@./scripts/check-version.sh --print

check-version:
	@./scripts/check-version.sh

# 3 つのうち一部だけが入っていると、上の $(and) で認証フラグがまるごと落ち、
# xcodebuild は Xcode のアカウントを探しにいって原因の分かりにくいエラーになる。先に止める。
release-auth:
	@n=0; \
	if [ -n "$(ASC_API_KEY_ID)" ]; then n=$$((n + 1)); fi; \
	if [ -n "$(ASC_API_ISSUER_ID)" ]; then n=$$((n + 1)); fi; \
	if [ -n "$(ASC_API_KEY_PATH)" ]; then n=$$((n + 1)); fi; \
	if [ $$n -ne 0 ] && [ $$n -ne 3 ]; then \
		echo "error: ASC_API_KEY_ID / ASC_API_ISSUER_ID / ASC_API_KEY_PATH は 3 つとも指定してください（手元で Xcode のアカウントを使うなら 3 つとも外す）。"; \
		exit 1; \
	fi; \
	if [ $$n -eq 3 ] && [ ! -f "$(ASC_API_KEY_PATH)" ]; then \
		echo "error: ASC_API_KEY_PATH の .p8 がありません: $(ASC_API_KEY_PATH)"; \
		exit 1; \
	fi; \
	if [ $$n -eq 3 ]; then \
		echo "認証: App Store Connect API キー"; \
	else \
		echo "認証: Xcode にサインインしているアカウント"; \
	fi

# 引数の書き間違いは、プロジェクトの生成やアーカイブ（数分かかる）より前に止める。
# App Store Connect のビルド番号は「ピリオドで区切った 3 つまでの整数」しか受け付けない。
release-args:
	@case "$(BUILD_NUMBER)" in \
		"") ;; \
		*[!0-9.]* | .* | *. | *..* | *.*.*.*) \
			echo "error: BUILD_NUMBER「$(BUILD_NUMBER)」は整数（ピリオド区切りで 3 つまで）にしてください。"; exit 1 ;; \
	esac
	@case "$(ARCHIVE_SIGNING)" in \
		YES | NO) ;; \
		*) echo "error: ARCHIVE_SIGNING は YES か NO を指定してください（いま: $(ARCHIVE_SIGNING)）。"; exit 1 ;; \
	esac

# 提出に使うアーカイブは、バージョンと CHANGELOG が揃っていることを前提にする。
# ずれたまま出すと、App Store のリリースノートが別の版のものになる。
archive: release-args check-version release-auth generate
	rm -rf "$(RELEASE_ARCHIVE)"
	xcodebuild archive \
		-project $(RELEASE_PROJECT) \
		-scheme $(RELEASE_SCHEME) \
		-configuration Release \
		-destination 'generic/platform=iOS' \
		-archivePath "$(RELEASE_ARCHIVE)" \
		-derivedDataPath "$(RELEASE_DERIVED_DATA)" \
		$(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)) \
		$(if $(filter NO,$(ARCHIVE_SIGNING)),CODE_SIGNING_ALLOWED=NO) \
		-allowProvisioningUpdates $(RELEASE_AUTH)
	@# できあがったアーカイブの中身で確かめる。Info.plist の CFBundleVersion が
	@# $$(CURRENT_PROJECT_VERSION) を参照していないと、BUILD_NUMBER を渡しても番号が変わらず、
	@# アップロードの段階で「同じビルド番号がある」と弾かれる。ここで先に止める。
	@# アイコンも同じ理由で見る。AppIcon が空でもビルドとアーカイブは通ってしまい、
	@# App Store Connect がアップロードを弾いて初めて分かる（main へマージした後になる）。
	@# AppIcon に画像があれば actool がアプリの Info.plist に CFBundleIcons を足すので、その有無で確かめる。
	@plist="$(RELEASE_ARCHIVE)/Info.plist"; \
	ver=$$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$$plist" 2>/dev/null); \
	build=$$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$$plist" 2>/dev/null); \
	want=$$(./scripts/check-version.sh --print); \
	if [ -z "$$ver" ] || [ -z "$$build" ]; then \
		echo "error: アーカイブにアプリが入っていません（$$plist に ApplicationProperties が無い）。アプリのターゲットの SKIP_INSTALL が NO か確かめてください。"; \
		exit 1; \
	fi; \
	if [ "$$ver" != "$$want" ]; then \
		echo "error: アーカイブのバージョン $$ver が MARKETING_VERSION $$want と違います。Info.plist の CFBundleShortVersionString が \$$(MARKETING_VERSION) を参照しているか確かめてください。"; \
		exit 1; \
	fi; \
	if [ -n "$(BUILD_NUMBER)" ] && [ "$$build" != "$(BUILD_NUMBER)" ]; then \
		echo "error: アーカイブのビルド番号 $$build が BUILD_NUMBER=$(BUILD_NUMBER) と違います。Info.plist の CFBundleVersion が \$$(CURRENT_PROJECT_VERSION) を参照しているか確かめてください。"; \
		exit 1; \
	fi; \
	app=$$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:ApplicationPath" "$$plist" 2>/dev/null); \
	if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName" "$(RELEASE_ARCHIVE)/Products/$$app/Info.plist" >/dev/null 2>&1; then \
		echo "error: アプリにアイコンが入っていません（$(RELEASE_ARCHIVE)/Products/$$app/Info.plist に CFBundleIcons が無い）。SaifuLog/Resources/Assets.xcassets/AppIcon.appiconset に 1024x1024 の PNG（透過なし）を置き、Contents.json の filename で参照してください。"; \
		exit 1; \
	fi; \
	echo "アーカイブ: $(RELEASE_ARCHIVE)（バージョン $$ver、ビルド $$build）"

# 送信せずに .ipa を書き出す。署名（クラウド管理の配布証明書）と API キーの権限が
# 足りているかを、App Store Connect に何も残さずに確かめられる。
# 書き出した .app の署名とエンタイトルメントも表示する。Capability を足したときに、
# 署名なしのアーカイブ（ARCHIVE_SIGNING=NO）から抜け落ちていないかをここで見る。
export-ipa: release-auth
	@test -d "$(RELEASE_ARCHIVE)" || { echo "error: $(RELEASE_ARCHIVE) がありません。先に make archive を実行してください。"; exit 1; }
	rm -rf "$(RELEASE_EXPORT_DIR)"
	@mkdir -p "$(dir $(RELEASE_EXPORT_OPTIONS_LOCAL))"
	cp "$(RELEASE_EXPORT_OPTIONS)" "$(RELEASE_EXPORT_OPTIONS_LOCAL)"
	/usr/libexec/PlistBuddy -c "Set :destination export" "$(RELEASE_EXPORT_OPTIONS_LOCAL)"
	xcodebuild -exportArchive \
		-archivePath "$(RELEASE_ARCHIVE)" \
		-exportOptionsPlist "$(RELEASE_EXPORT_OPTIONS_LOCAL)" \
		-exportPath "$(RELEASE_EXPORT_DIR)" \
		-allowProvisioningUpdates $(RELEASE_AUTH)
	@ipa=$$(ls "$(RELEASE_EXPORT_DIR)"/*.ipa 2>/dev/null | head -n 1); \
	if [ -z "$$ipa" ]; then echo "error: $(RELEASE_EXPORT_DIR) に .ipa ができていません。"; exit 1; fi; \
	tmp=$$(mktemp -d); \
	unzip -q "$$ipa" -d "$$tmp"; \
	app=$$(ls -d "$$tmp"/Payload/*.app | head -n 1); \
	echo "書き出し: $$ipa"; \
	echo "--- 署名"; \
	codesign -dv "$$app" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier)='; \
	echo "--- エンタイトルメント"; \
	codesign -d --entitlements - "$$app" 2>/dev/null; \
	rm -rf "$$tmp"

# Config/ExportOptions.plist（destination=upload）で書き出し、そのまま App Store Connect へ送る。
# 送った時点で戻る。App Store Connect 側の処理（10 分〜1 時間）は待たない
# （CI では release.yml の submit ジョブが scripts/asc.py wait-build で待つ）。
#
# 手元の端末から叩いたときだけ確認を挟む。本当に送信され、同じビルド番号では
# 二度と送れなくなるため。CI（CI=true、標準入力が端末でない）では聞かない。
upload: release-auth
	@test -d "$(RELEASE_ARCHIVE)" || { echo "error: $(RELEASE_ARCHIVE) がありません。先に make archive を実行してください。"; exit 1; }
	@if [ -t 0 ] && [ -z "$$CI" ]; then \
		build=$$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$(RELEASE_ARCHIVE)/Info.plist" 2>/dev/null); \
		printf '%s' "ビルド $$build を App Store Connect へ送信します。よろしいですか？ [y/N] "; \
		read answer; \
		case "$$answer" in y | Y | yes) ;; *) echo "やめました。"; exit 1 ;; esac; \
	fi
	rm -rf "$(RELEASE_EXPORT_DIR)"
	xcodebuild -exportArchive \
		-archivePath "$(RELEASE_ARCHIVE)" \
		-exportOptionsPlist "$(RELEASE_EXPORT_OPTIONS)" \
		-exportPath "$(RELEASE_EXPORT_DIR)" \
		-allowProvisioningUpdates $(RELEASE_AUTH)
	@echo "App Store Connect へ送信しました。処理が終わると TestFlight に現れます。"
