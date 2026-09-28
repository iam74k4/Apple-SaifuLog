# release.mk — App Store へ出すための make ターゲット。Makefile の末尾で -include する。
#
#   make version                       いまの MARKETING_VERSION を表示する
#   make check-version                 MARKETING_VERSION と CHANGELOG.md の先頭の見出しが一致するか確かめる
#   make archive [BUILD_NUMBER=123]    Release の .xcarchive を build/ に作る
#   make export-ipa                    アーカイブから .ipa を書き出すだけ（送信しない。疎通確認用）
#   make upload                        アーカイブを App Store Connect へ送る（本当に送信される）
#                                      ビルド番号は make archive の BUILD_NUMBER で決まる（upload では変えられない）
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
# ただし署名なしのアーカイブにはエンタイトルメントが焼かれない。データ保護
# （com.apple.developer.default-data-protection）や iCloud、App Groups などを
# エンタイトルメントに足したら、make export-ipa（CI は release.yml の mode=export）で
# 書き出したアプリに載っているかを必ず確かめる。make export-ipa は下の
# RELEASE_ENTITLEMENTS と照合し、抜けていれば止まる（release.yml のアップロード前の照合は、
# 署名ありのアーカイブを入れるまで RELEASE_ENTITLEMENTS_CHECK=warn で警告だけにしている）
# （docs/release-flow.md の「Capability（iCloud など）を足すとき」）。
ARCHIVE_SIGNING ?= YES

# アプリのエンタイトルメントのファイル（project.yml の entitlements.path）。make export-ipa が、
# 書き出したアプリにここのキーがすべて載っているかを照合する。見つからなければ照合しない。
RELEASE_ENTITLEMENTS ?= $(firstword $(wildcard SaifuLog/*.entitlements SaifuLog/*/*.entitlements Config/*.entitlements))

# 照合で抜けが見つかったときの扱い。error（既定）は止め、warn は警告を出して続ける。
#
# release.yml のアップロード前の照合だけは、いまは warn を渡している。CI のアーカイブは署名なし
# （ARCHIVE_SIGNING=NO）で、書き出しの段階の署名し直しはアーカイブにあるエンタイトルメントしか引き継がない
# ので、照合は必ず抜けを見つける。error のままだと、develop → main をマージするたびにリリースが止まる。
# 署名ありのアーカイブ（証明書の取り込み）を release.yml に入れ、mode=export で照合が通ることを確かめたら、
# warn を外して error に戻す（docs/release-flow.md の「Capability（iCloud など）を足すとき」）。
RELEASE_ENTITLEMENTS_CHECK ?= error

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
	default=$$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*\([0-9.]*\).*/\1/p' Config/Base.xcconfig); \
	if [ -n "$(BUILD_NUMBER)" ] && [ "$(BUILD_NUMBER)" = "$$default" ]; then \
		msg="BUILD_NUMBER=$(BUILD_NUMBER) は Config/Base.xcconfig の CURRENT_PROJECT_VERSION と同じ値なので、ビルド番号の上書きが Info.plist に届いているかは確かめられていません。既定値と違う値を渡してください。"; \
		if [ "$$GITHUB_ACTIONS" = true ]; then echo "::warning title=release.mk::$$msg"; else echo "warning: $$msg"; fi; \
	fi; \
	app=$$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:ApplicationPath" "$$plist" 2>/dev/null); \
	if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName" "$(RELEASE_ARCHIVE)/Products/$$app/Info.plist" >/dev/null 2>&1; then \
		echo "error: アプリにアイコンが入っていません（$(RELEASE_ARCHIVE)/Products/$$app/Info.plist に CFBundleIcons が無い）。SaifuLog/Resources/Assets.xcassets/AppIcon.appiconset の画像（1024x1024 の PNG、透過なし。ライトは必須、ダーク・色付きは任意）が消えていないか、Contents.json の filename で参照されているかを確かめてください。"; \
		exit 1; \
	fi; \
	echo "アーカイブ: $(RELEASE_ARCHIVE)（バージョン $${ver}、ビルド $${build}）"

# 送信せずに .ipa を書き出す。署名（クラウド管理の配布証明書）と API キーの権限が
# 足りているかを、App Store Connect に何も残さずに確かめられる。
# 書き出した .app の署名とエンタイトルメントも表示する。エンタイトルメントを足したときに、
# 署名なしのアーカイブ（ARCHIVE_SIGNING=NO）から抜け落ちていないかをここで見る。
# RELEASE_ENTITLEMENTS があれば、そのキーがすべて載っているかを照合し、抜けていれば止まる
# （目で見るだけだと、ログに流れて見落とす）。RELEASE_ENTITLEMENTS_CHECK=warn なら警告だけ出して続ける。
export-ipa: release-auth
	@case "$(RELEASE_ENTITLEMENTS_CHECK)" in \
		error | warn) ;; \
		*) echo "error: RELEASE_ENTITLEMENTS_CHECK は error か warn を指定してください（いま: $(RELEASE_ENTITLEMENTS_CHECK)）。"; exit 1 ;; \
	esac
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
	status=0; \
	if [ -n "$(RELEASE_ENTITLEMENTS)" ]; then \
		echo "--- 照合: $(RELEASE_ENTITLEMENTS)"; \
		codesign -d --entitlements - --xml "$$app" > "$$tmp/entitlements.plist" 2>/dev/null || true; \
		missing=""; \
		for key in $$(plutil -p "$(RELEASE_ENTITLEMENTS)" | sed -n 's/^  "\([^"]*\)" => .*/\1/p'); do \
			/usr/libexec/PlistBuddy -c "Print :$$key" "$$tmp/entitlements.plist" >/dev/null 2>&1 || missing="$$missing $$key"; \
		done; \
		if [ -n "$$missing" ]; then \
			msg="書き出したアプリに、$(RELEASE_ENTITLEMENTS) のエンタイトルメントが載っていません:$${missing}"; \
			hint="署名なし（ARCHIVE_SIGNING=NO）のアーカイブにはエンタイトルメントが焼かれません。docs/release-flow.md の「Capability（iCloud など）を足すとき」に従い、アーカイブを署名ありに切り替えてください。"; \
			if [ "$(RELEASE_ENTITLEMENTS_CHECK)" = warn ]; then \
				if [ "$$GITHUB_ACTIONS" = true ]; then echo "::warning title=エンタイトルメントの照合::$${msg} $${hint}"; fi; \
				echo "warning: $${msg}"; \
				echo "         $${hint}"; \
				echo "         RELEASE_ENTITLEMENTS_CHECK=warn なので止めずに続けます（このアプリには上のエンタイトルメントが載っていません）。"; \
			else \
				echo "error: $${msg}"; \
				echo "       $${hint}"; \
				status=1; \
			fi; \
		else \
			echo "OK: $(RELEASE_ENTITLEMENTS) のキーはすべて載っています。"; \
		fi; \
	fi; \
	rm -rf "$$tmp"; \
	exit $$status

# Config/ExportOptions.plist（destination=upload）で書き出し、そのまま App Store Connect へ送る。
# 送った時点で戻る。App Store Connect 側の処理（10 分〜1 時間）は待たない
# （CI では release.yml の submit ジョブが scripts/asc.py wait-build で待つ）。
#
# 手元の端末から叩いたときだけ確認を挟む。本当に送信され、同じビルド番号では
# 二度と送れなくなるため。CI（CI=true、標準入力が端末でない）では聞かない。
upload: release-auth
	@test -d "$(RELEASE_ARCHIVE)" || { echo "error: $(RELEASE_ARCHIVE) がありません。先に make archive を実行してください。"; exit 1; }
	@# ビルド番号はアーカイブの中にもう焼かれている。make upload BUILD_NUMBER=… と渡しても
	@# 番号は変わらず、App Store Connect に「同じビルド番号がある」と弾かれるので、先に止める。
	@build=$$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$(RELEASE_ARCHIVE)/Info.plist" 2>/dev/null); \
	if [ -n "$(BUILD_NUMBER)" ] && [ "$$build" != "$(BUILD_NUMBER)" ]; then \
		echo "error: make upload は BUILD_NUMBER を読みません（アーカイブのビルド番号は $${build}）。make archive BUILD_NUMBER=$(BUILD_NUMBER) でアーカイブを作り直してから送ってください。"; \
		exit 1; \
	fi
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
