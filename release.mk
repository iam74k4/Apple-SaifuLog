# release.mk — App Store へ出すための make ターゲット。Makefile の末尾で -include する。
#
#   make version                       いまの MARKETING_VERSION を表示する
#   make check-version                 MARKETING_VERSION と CHANGELOG.md の先頭の見出しが一致するか確かめる
#   make archive [BUILD_NUMBER=123]    Release の .xcarchive を build/ に作る
#                                      既定は署名あり。ARCHIVE_SIGNING=NO で署名なし（build.yml と make ci）、
#                                      ARCHIVE_KEYCHAIN=… で署名に使うキーチェーンを指定する（release.yml）
#                                      INTERNAL_BUILD=YES で社内テスト用（診断画面入り。release.yml の mode=testflight）
#   make export-ipa                    アーカイブから .ipa を書き出すだけ（送信しない。疎通確認用）
#   make upload                        アーカイブを App Store Connect へ送る（本当に送信される）
#                                      ビルド番号は make archive の BUILD_NUMBER で決まる（upload では変えられない）
#                                      社内テスト用のアーカイブは INTERNAL_BUILD=YES で送り、TestFlight の社内テスト専用になる
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
# make export-ipa 用。ExportOptions.plist の destination を export に替えた写し。
RELEASE_EXPORT_OPTIONS_LOCAL := build/ExportOptions.export.plist
# make upload 用。ExportOptions.plist の testFlightInternalTestingOnly を INTERNAL_BUILD に合わせた写し。
RELEASE_EXPORT_OPTIONS_UPLOAD := build/ExportOptions.upload.plist

# ビルド番号（CFBundleVersion）の上書き。空なら Config/Base.xcconfig の
# CURRENT_PROJECT_VERSION のまま。App Store Connect は同じ版の中で番号の重複を
# 受け付けないので、CI は実行ごとに増える番号を渡す（release.yml）。
BUILD_NUMBER ?=

# アーカイブの段階で署名するか。既定の YES は、DEVELOPMENT_TEAM と CODE_SIGN_STYLE = Automatic
# （Config/Base.xcconfig）で、Apple Development の証明書と開発用のプロファイルを使って署名する。
# プロファイルは -allowProvisioningUpdates で Xcode が用意する（認証は RELEASE_AUTH か Xcode のアカウント）。
#
# 提出物は署名ありで作る。署名なしのアーカイブにはエンタイトルメントが焼かれず、App Store 向けの
# 署名し直し（export の段階で、クラウド管理の配布証明書で行う）もアーカイブにあるエンタイトルメントしか
# 引き継がない。署名なしのままだと、データ保護（com.apple.developer.default-data-protection）や
# iCloud、App Groups などが提出物から抜ける。
#
# release.yml は YES で作るが、証明書は Secrets に置いた決まったもの（.p12）を使い捨てのキーチェーンに
# 取り込んで ARCHIVE_KEYCHAIN で渡す。使い捨てのランナーで自動署名に任せきりにすると、手元に使える証明書が
# 無いので、実行のたびに Apple Development の証明書が新しく作られ、秘密鍵はランナーと一緒に消える。
# 証明書が溜まるうえ、次の実行で「秘密鍵の無い証明書」を掴んで失敗することがあるため。
#
# build.yml と make ci は NO を渡す。PR ごとに走る CI は証明書（Environment release の Secrets）を
# 読めず、組み立ての経路とアーカイブの検査を通すだけなら署名は要らないため。
#
# 書き出したアプリにエンタイトルメントが載っているかは、make export-ipa（CI は release.yml の mode=export）で
# 確かめる。make export-ipa は下の RELEASE_ENTITLEMENTS と照合し、抜けていれば止まる（release.yml の
# アップロード前の照合は、main で mode=export の照合が通るのを確かめるまで RELEASE_ENTITLEMENTS_CHECK=warn で
# 警告だけにしている）（docs/release-flow.md の「署名ありのアーカイブ」）。
ARCHIVE_SIGNING ?= YES

# アーカイブの署名に使うキーチェーン（ARCHIVE_SIGNING=YES のときだけ渡せる）。渡すと、codesign に
# --keychain でこのキーチェーンを使わせる（OTHER_CODE_SIGN_FLAGS）。同じ証明書がほかのキーチェーンにも
# あると、codesign がどちらを使うか決められずに止まることがあるため（セルフホストのランナーや手元の Mac）。
# xcodebuild が署名の証明書を探すのはキーチェーンの検索リストなので、このキーチェーンは検索リストにも
# 入れておく（release.yml の「署名の証明書を一時キーチェーンに取り込む」はそうしている）。
# 手元でログインキーチェーンの証明書を使うなら渡さない。
ARCHIVE_KEYCHAIN ?=

# アプリのエンタイトルメントのファイル（project.yml の entitlements.path）。make export-ipa が、
# 書き出したアプリにここのキーがすべて載っているかを照合する。見つからなければ照合しない。
RELEASE_ENTITLEMENTS ?= $(firstword $(wildcard SaifuLog/*.entitlements SaifuLog/*/*.entitlements Config/*.entitlements))

# 照合で抜けが見つかったときの扱い。error（既定）は止め、warn は警告を出して続ける。
#
# release.yml のアップロード前の照合だけは、いまは warn を渡している。release.yml のアーカイブは署名あり
# （証明書を取り込んで ARCHIVE_SIGNING=YES）にしたが、その経路はまだ一度も通していない。error にすると、
# 経路のどこかが食い違っていたときに、develop → main をマージするたびにリリースが止まる。
# 所有者が main で mode=export を走らせ、照合が通ることを確かめたら、warn を外して error に戻す
# （docs/release-flow.md の「署名ありのアーカイブ」）。
RELEASE_ENTITLEMENTS_CHECK ?= error

# 社内テスト用のビルドにするか（YES / NO）。YES にすると、アプリのターゲットに Swift の条件 INTERNAL_DIAGNOSTICS が付き
# （project.yml の SAIFULOG_INTERNAL_BUILD）、実機での確認に使う診断画面（SaifuLog/Diagnostics）が入る。
# make upload は YES のアーカイブを TestFlight の社内テスト専用（testFlightInternalTestingOnly）で送る。社内テスト専用の
# ビルドは、審査にも外部テストにも出せない（Apple が受け付けない）。
#
# YES を渡すのは release.yml の mode=testflight だけ。main へのマージ（push）や mode=submit / upload / export は
# NO（既定）のままにする。取り違えても App Store へ出すビルドに診断画面が入らないように、archive・export-ipa・upload は
# アーカイブの中身（下の RELEASE_INTERNAL_MARKER）が INTERNAL_BUILD と合うかを確かめ、合わなければ止まる。
# xcodebuild には常に SAIFULOG_INTERNAL_BUILD=$(INTERNAL_BUILD) を渡す（手元の Secrets.xcconfig などで YES に
# していても、NO のアーカイブは NO で作る）。
INTERNAL_BUILD ?= NO

# 診断画面の入ったアプリにだけある文字列。SaifuLog/Diagnostics/DiagnosticsReport.swift の buildMarker と同じ値にする
# （変えるときは両方）。ずれると、社内テスト用のアーカイブが「印が見つからない」で止まるので気づける。
RELEASE_INTERNAL_MARKER := SaifuLog-InternalDiagnostics-v1

# アーカイブのアプリに診断画面が入っているかを、INTERNAL_BUILD と照らし合わせるシェルの文（archive・export-ipa・upload の
# レシピで使う）。grep が読めないファイルに当たった（終了コード 2）ときも止める（入っていないと見なして通さない）。
RELEASE_INTERNAL_CHECK = \
	case "$(INTERNAL_BUILD)" in \
		YES | NO) ;; \
		*) echo "error: INTERNAL_BUILD は YES か NO を指定してください（いま: $(INTERNAL_BUILD)）。"; exit 1 ;; \
	esac; \
	app=$$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:ApplicationPath" "$(RELEASE_ARCHIVE)/Info.plist" 2>/dev/null); \
	if [ -z "$$app" ] || [ ! -d "$(RELEASE_ARCHIVE)/Products/$$app" ]; then \
		echo "error: $(RELEASE_ARCHIVE) にアプリが見つかりません。make archive から作り直してください。"; exit 1; \
	fi; \
	grep -r -a -F -q "$(RELEASE_INTERNAL_MARKER)" "$(RELEASE_ARCHIVE)/Products/$$app"; \
	case $$? in \
		0) found=YES ;; \
		1) found=NO ;; \
		*) echo "error: $(RELEASE_ARCHIVE)/Products/$$app を読めず、診断画面が入っているかを確かめられませんでした。"; exit 1 ;; \
	esac; \
	if [ "$$found" = YES ] && [ "$(INTERNAL_BUILD)" != YES ]; then \
		echo "error: このアーカイブのアプリには診断画面（社内テスト用）が入っています（$(RELEASE_INTERNAL_MARKER) が見つかった）。App Store へ出すビルドに入れないため止めます。"; \
		echo "       Swift の条件 INTERNAL_DIAGNOSTICS をほかの場所（project.yml・Config/*.xcconfig）で足していないか、診断画面のコードが \#if DEBUG || INTERNAL_DIAGNOSTICS の外に出ていないかを確かめてください。"; \
		echo "       社内テスト用として送るなら INTERNAL_BUILD=YES を渡してください（TestFlight の社内テスト専用になり、審査には出せません）。"; \
		exit 1; \
	fi; \
	if [ "$$found" = NO ] && [ "$(INTERNAL_BUILD)" = YES ]; then \
		echo "error: INTERNAL_BUILD=YES ですが、アーカイブのアプリに診断画面の印（$(RELEASE_INTERNAL_MARKER)）が見つかりません。"; \
		echo "       アーカイブを make archive INTERNAL_BUILD=YES で作ったか、project.yml の SAIFULOG_INTERNAL_BUILD から SWIFT_ACTIVE_COMPILATION_CONDITIONS への組み立てが変わっていないか、SaifuLog/Diagnostics/DiagnosticsReport.swift の buildMarker が release.mk の RELEASE_INTERNAL_MARKER と同じ値かを確かめてください。"; \
		exit 1; \
	fi; \
	if [ "$$found" = YES ]; then \
		echo "診断画面: 入っている（社内テスト用。TestFlight の社内テスト専用で送る）"; \
	else \
		echo "診断画面: 入っていない"; \
	fi

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
	@case "$(INTERNAL_BUILD)" in \
		YES | NO) ;; \
		*) echo "error: INTERNAL_BUILD は YES か NO を指定してください（いま: $(INTERNAL_BUILD)）。"; exit 1 ;; \
	esac
	@# キーチェーンの指定が黙って無視されたり、無いキーチェーンを codesign に渡して署名の段階
	@# （アーカイブの終わり近く）で落ちたりしないように、ここで止める。
	@if [ -n "$(ARCHIVE_KEYCHAIN)" ]; then \
		if [ "$(ARCHIVE_SIGNING)" != YES ]; then \
			echo "error: ARCHIVE_KEYCHAIN は ARCHIVE_SIGNING=YES のときだけ渡せます（いま: ARCHIVE_SIGNING=$(ARCHIVE_SIGNING)）。"; exit 1; \
		fi; \
		if [ ! -f "$(ARCHIVE_KEYCHAIN)" ]; then \
			echo "error: ARCHIVE_KEYCHAIN のキーチェーンがありません: $(ARCHIVE_KEYCHAIN)"; exit 1; \
		fi; \
	fi

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
		SAIFULOG_INTERNAL_BUILD=$(INTERNAL_BUILD) \
		$(if $(filter NO,$(ARCHIVE_SIGNING)),CODE_SIGNING_ALLOWED=NO) \
		$(if $(ARCHIVE_KEYCHAIN),OTHER_CODE_SIGN_FLAGS="--keychain $(ARCHIVE_KEYCHAIN)") \
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
	@# 診断画面（社内テスト用）が INTERNAL_BUILD のとおりに入っているか（入っていないか）を、できあがったアプリで確かめる。
	@# ビルドの設定だけを信じると、条件をほかの場所で足したときや、診断画面のコードが #if の外に出たときに気づけない。
	@$(RELEASE_INTERNAL_CHECK)

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
	@$(RELEASE_INTERNAL_CHECK)
	rm -rf "$(RELEASE_EXPORT_DIR)"
	@mkdir -p "$(dir $(RELEASE_EXPORT_OPTIONS_LOCAL))"
	cp "$(RELEASE_EXPORT_OPTIONS)" "$(RELEASE_EXPORT_OPTIONS_LOCAL)"
	/usr/libexec/PlistBuddy -c "Set :destination export" "$(RELEASE_EXPORT_OPTIONS_LOCAL)"
	@# 送るとき（make upload）と同じ設定で書き出す。
	/usr/libexec/PlistBuddy -c "Set :testFlightInternalTestingOnly $(if $(filter YES,$(INTERNAL_BUILD)),true,false)" "$(RELEASE_EXPORT_OPTIONS_LOCAL)"
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
			hint="署名なし（ARCHIVE_SIGNING=NO）のアーカイブにはエンタイトルメントが焼かれません。アーカイブを署名ありで作ったかを確かめてください（docs/release-flow.md の「署名ありのアーカイブ」）。"; \
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
# 社内テスト用のアーカイブ（INTERNAL_BUILD=YES）は、testFlightInternalTestingOnly を true にした写しで送る。
# 診断画面の入ったビルドが、審査や外部テストへ回らないようにするため（Apple が社内テスト専用のビルドを受け付けない）。
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
	@$(RELEASE_INTERNAL_CHECK)
	@if [ -t 0 ] && [ -z "$$CI" ]; then \
		build=$$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$(RELEASE_ARCHIVE)/Info.plist" 2>/dev/null); \
		printf '%s' "ビルド $$build を App Store Connect へ送信します$(if $(filter YES,$(INTERNAL_BUILD)),（TestFlight の社内テスト専用）)。よろしいですか？ [y/N] "; \
		read answer; \
		case "$$answer" in y | Y | yes) ;; *) echo "やめました。"; exit 1 ;; esac; \
	fi
	rm -rf "$(RELEASE_EXPORT_DIR)"
	@mkdir -p "$(dir $(RELEASE_EXPORT_OPTIONS_UPLOAD))"
	cp "$(RELEASE_EXPORT_OPTIONS)" "$(RELEASE_EXPORT_OPTIONS_UPLOAD)"
	/usr/libexec/PlistBuddy -c "Set :testFlightInternalTestingOnly $(if $(filter YES,$(INTERNAL_BUILD)),true,false)" "$(RELEASE_EXPORT_OPTIONS_UPLOAD)"
	xcodebuild -exportArchive \
		-archivePath "$(RELEASE_ARCHIVE)" \
		-exportOptionsPlist "$(RELEASE_EXPORT_OPTIONS_UPLOAD)" \
		-exportPath "$(RELEASE_EXPORT_DIR)" \
		-allowProvisioningUpdates $(RELEASE_AUTH)
	@echo "App Store Connect へ送信しました。処理が終わると TestFlight に現れます$(if $(filter YES,$(INTERNAL_BUILD)),（社内テスト専用。審査や外部テストには出せません）)。"
