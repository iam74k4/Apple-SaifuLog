# SaifuLog-Apple

ひとことで記録できる iPhone の家計簿アプリ「SaifuLog（サイフログ）」。文章の理解は
端末内の AI（Apple の Foundation Models）で行い、家計のデータを端末の外に出さない。

## 現在の到達点
- 初期構成の段階。プロジェクトの骨組み・CI/CD・ドキュメントと、**ひとこと入力の試作**まで。
  - 試作済み: 一行の読み取り（端末内 AI、使えない端末ではキーワード辞書）、タイムライン、記録直後の
    「取り消す」、長押しでの記録の削除（確認つき）、今月の支出と収入の合計。画面は縦向きのみ。
    保存先のデータ保護は NSFileProtectionComplete（ロック中は読めないようにする。実機での確認はまだ。
    release.yml は開発用の証明書で署名したアーカイブから提出物を作るようにしたが、証明書の Secrets の登録と、
    main で `mode=export` の照合が通るかの確認はまだ。`docs/design.md` §5-4）。
  - **未実装:** 直す・予算・レシート・質問・まとめ・設定・プレミアム（StoreKit）・修正の記憶。
- プロダクトの決定事項と未決事項は `docs/design.md` にある。仕様に迷ったらまずそこを見る。
- README などに、実装していない機能を「できる」と書かない。予定は「予定」と書く。
  逆に、機能を足したら README・`docs/design.md`・`PRIVACY.md` の「予定」も外す。

## Git 運用ルール（統一）

### ブランチ戦略（リポジトリ共通ルール）
- **`main`**: リリース済みの安定版のみ。
- **`develop`**: 統合ブランチ。すべての作業の統合先（GitFlow）。**develop へ直接コミットしない。**
- **作業ブランチ**: **必ず `develop` から切る**。完了後に `develop` へマージ（PR）する。
  - 命名例: `feature/<概要>`, `fix/<概要>`, `docs/<概要>`, `chore/<概要>`
  - 例: `git checkout develop && git pull && git checkout -b feature/one-line-input`

**`main` へのマージがリリースの合図になる。** App Store Connect へのアップロードと審査への
提出が自動で走り、配信が始まるとタグと GitHub Release が自動で作られる（`docs/release-flow.md`）。
リリースするつもりのない変更を main へ入れない。

**develop → main は merge commit でだけマージする**（main の Ruleset は merge しか許さない）。
squash や rebase で入れると main にだけあるコミットができ、次のリリースから毎回
`Config/Base.xcconfig` と `CHANGELOG.md` で衝突するため。作業ブランチ → develop は squash でよい。

### コミットメッセージ（Conventional Commits で統一）
`<type>: <要約>` 形式で書く。type は以下を用いる:

| type | 用途 |
|------|------|
| `feat` | 新機能 |
| `fix` | バグ修正 |
| `docs` | ドキュメントのみの変更 |
| `chore` | ビルド・設定・雑務など（プロダクトコード非変更） |
| `refactor` | 挙動を変えないリファクタリング |
| `test` | テストの追加・修正 |
| `perf` | パフォーマンス改善 |
| `style` | フォーマット等（挙動非変更） |

例:
```
feat: parse amount from one-line input
chore: set up XcodeGen project and CI
docs: add privacy policy
```

## 開発の前提

### ビルド
- プロジェクトは `project.yml` から XcodeGen で生成する。`SaifuLog.xcodeproj` は生成物で
  `.gitignore` 済み。**設定の変更は xcodeproj ではなく `project.yml` と `Config/Base.xcconfig` に行う。**
  xcodeproj を直接いじっても、次の `make generate` で消える。
- `make generate` — `project.yml` から `SaifuLog.xcodeproj` を生成する
- `make build` — 生成してから `xcodebuild build -scheme SaifuLog`（汎用 iOS シミュレータ向け、
  署名なし、`SIM_ARCHS`（既定 arm64）だけ）。CI の最初のステップと同じ経路
- `make test` — `swift test --package-path Packages/SaifuLogCore`（コアのテスト）
- `make build-tests` — アプリ側のテスト（`SaifuLogTests/`、Swift Testing）を `xcodebuild build-for-testing` で
  ビルドする（汎用のシミュレータ向け、署名なし）。`make build` はスキームの build アクション（SaifuLog だけ）
  なので、テストのターゲットが壊れても `make build` だけでは気づけない
- `make test-app` — アプリ側のテストをシミュレータで動かす（`build-tests` の後に `test-without-building`、
  `-only-testing:SaifuLogTests`）。SwiftData の保存・読み込みの条件や保存の失敗の扱いなど、コアに置けない部分。
  機種は `scripts/pick-simulator.sh` が、いちばん新しい iOS の iPhone を選ぶ（`TEST_DESTINATION=…` で上書きできる）
- `make ci` — 必須チェック `build`（build.yml）と同じ 6 つ（`make build`・`make test`・`make build-tests`・
  `make test-app`・`make check-version`・`make archive ARCHIVE_SIGNING=NO BUILD_NUMBER=99999`）を順に通す。
  **`make build` が通るだけでは CI が通るとは限らない。** PR の前はこれを通す
- `make clean` / `make open` — 生成物の削除 / Xcode で開く
- `release.mk`（Makefile の末尾で読み込む）:
  - `make version` — いまの `MARKETING_VERSION` を表示する
  - `make check-version` — `MARKETING_VERSION` と CHANGELOG 先頭の見出しの一致を確かめる
  - `make archive` — Release の .xcarchive を `build/` に作る。`BUILD_NUMBER=…` でビルド番号を上書きできる。
    既定は署名あり。`ARCHIVE_SIGNING=NO` で署名なし（build.yml と `make ci`）、`ARCHIVE_KEYCHAIN=…` で署名に使う
    キーチェーンを指定する（release.yml が、証明書を取り込んだ使い捨てのキーチェーンを渡す）。
    できたアプリの Info.plist にバージョン・ビルド番号・アイコンが入っているかも確かめる（CI の build でも走る）
  - `make export-ipa` — アーカイブから .ipa を書き出すだけ（送信しない）。署名とエンタイトルメントを表示し、
    エンタイトルメントのファイル（`SaifuLog/SaifuLog.entitlements`）のキーが載っていなければ止まる
    （`RELEASE_ENTITLEMENTS_CHECK=warn` なら警告だけ）。release.yml はアップロードの前に必ずこれを通す。
    release.yml のアーカイブは署名あり（Apple Development の証明書を一時キーチェーンに取り込む）にしたが、
    その経路はまだ一度も通していないので、所有者が main で `mode=export` の照合が通るのを確かめるまでは `warn` を渡している
  - `make upload` — `Config/ExportOptions.plist` で App Store Connect へ送る。ビルド番号はアーカイブに
    焼かれた値で、`make upload BUILD_NUMBER=…` では変わらない（違う値を渡すと止まる）。番号を変えるときは
    `make archive BUILD_NUMBER=…` から。認証は App Store Connect API キー
    （環境変数 `ASC_API_KEY_ID` / `ASC_API_ISSUER_ID` / `ASC_API_KEY_PATH`）
- 署名のチームは `Config/Base.xcconfig` の `DEVELOPMENT_TEAM`。手元で別のチームを使うときは
  `.gitignore` 済みの `Config/Secrets.xcconfig` で上書きする（Base.xcconfig が `#include?` で読む）。
  追跡しているファイルを書き換えると、うっかりコミットして全員の署名が変わるため。
  別のチームで実機に入れるなら `ORG_PREFIX`（Bundle ID の接頭辞）も上書きする。
  `com.iam74k4.SaifuLog` は作者のチームで登録済みで、チームだけ替えると自動署名が失敗する。
- エンタイトルメントは `project.yml` の `targets.SaifuLog.entitlements.properties` に書く。
  `SaifuLog/SaifuLog.entitlements` は `make generate` が書き出す生成物（直接書き換えても消える）だが、
  コミットはする。いまは `com.apple.developer.default-data-protection = NSFileProtectionComplete` だけ。
  エンタイトルメントは署名ありのアーカイブにしか焼かれない。release.yml は開発用の証明書（Environment `release` の
  Secrets `APPLE_DEV_CERT_P12_BASE64` / `APPLE_DEV_CERT_P12_PASSWORD`）で署名してアーカイブする。build.yml と
  `make ci` のアーカイブは署名なしで、エンタイトルメントは焼かれない（組み立ての確認だけなので要らない）。
  仕組みと証明書の年に一度の更新は `docs/release-flow.md` の「署名ありのアーカイブ」、Capability を足したときに
  見ることは「Capability（iCloud など）を足すとき」。
- 対象: iPhone のみ（`TARGETED_DEVICE_FAMILY = 1`）、縦向きのみ（`project.yml` の
  `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`）、iOS 26.0 以上、Swift 6（strict concurrency complete）。
  ビルドは Xcode 27（iOS 27 SDK）。iOS 27 でしか使えない API は `if #available(iOS 27, *)` で囲い、
  iOS 26 でも動く道を残す。

### バージョン
- 正は `Config/Base.xcconfig` の `MARKETING_VERSION`（と `CURRENT_PROJECT_VERSION`）。ほかの場所に
  バージョンを書かない。二か所で別々に持つと食い違うため。
- `CHANGELOG.md` の先頭のバージョン見出し（`## [X.Y.Z]`）を `MARKETING_VERSION` と一致させる。
  CI の `make check-version` がずれを止める。
- CHANGELOG の各バージョンの節は、そのまま App Store の「このバージョンでの変更点」と
  GitHub Release の本文になる。App Store は Markdown を表示しないので、節の中では太字・リンク・
  バッククォートを使わず、`- ` の箇条書きと平文で、利用者の目線で書く（内部の型名やファイル名は書かない）。

### コードの置き場所
- `SaifuLog/` — アプリ本体。SwiftUI の画面（`Views/`）、SwiftData のモデル（`Models/`）、
  Foundation Models を使う部分（`AI/`）、`Resources/`（Assets、String Catalog など）。
- `Packages/SaifuLogCore/` — 純粋なロジック（金額・日付の読み取り、キーワード辞書による解析、
  割り勘や合計・残りの計算など）とそのテスト。**FoundationModels / SwiftData / SwiftUI を入れない。**
  CI の macOS ランナー上で `swift test` を回すため、platforms は `.iOS(.v26), .macOS(.v14)` に保つ。
- 文字列は String Catalog（`.xcstrings`）で、開発言語 ja に en を足す。開発言語を ja にしているのは
  意図どおり（日本語と英語のどちらも優先言語に無い端末では日本語で出る。理由は `docs/design.md` §10）。
  ホーム画面の表示名は
  `SaifuLog/Resources/InfoPlist.xcstrings` の `CFBundleDisplayName`（ja「サイフログ」/ en「SaifuLog」）。
- アプリアイコンは `Resources/Assets.xcassets/AppIcon.appiconset/` の 3 枚（1024 × 1024・透過なし）。
  `AppIcon.png`（ライト: 白地に黒い財布）、`AppIcon-Dark.png`（ダーク）、`AppIcon-Tinted.png`（色付き）。
  元の SVG は `design/icon/`。**AppIcon を空にしない。** 空でもビルドは通るが、App Store Connect が
  アップロードを弾く（`make archive` の検査で止まる）。

### AI の扱い
- AI はすべて端末内（Foundation Models）。クラウドの API は使わない。サーバーも持たない。
- **数字は AI に計算させない。** AI には文章から値（金額と日付の表記・カテゴリ・品目・収入か）を
  取り出させ、換算・割り勘の割り算・日付の計算・合計・平均・残りはコード（SaifuLogCore）で行う。
  端末内モデルは小さく、計算を誤るため。割り勘の人数もモデルに尋ねず、入力からコードが決める。
- **件の分け方はコードで決める。** 一行を `EntryInput` で 1 件ずつの区間に分け、モデルには区間ごとに
  1 件だけ生成させる（`SaifuLog/AI/SegmentedExtraction.swift`）。記録の配列を返させると、1 件の入力にも
  余分な要素や同じ記録の繰り返しが返るため。
- **AI の結果は入力と突き合わせてから使う**（`ExtractedEntry.resolveAll`）。件数が区間の数と合わないか、
  金額がその区間に書かれていなければ AI の結果を捨て、ルールベースで読み直す。日付・収入・品目は入力の側で
  正す（入力の指す日と合わない日付は使わない、打ち消しの語があれば収入にしない、区間に書かれていない品目は
  ルールベースのメモに置き換える）。照合はコアに置き、`swift test` で確かめる。
- 指示文と `@Guide` には具体的な数字や単位の例を書かない。モデルが入力に無くても写して返すため。
- Apple Intelligence が使えない端末（非対応機種・オフ・モデル準備中）や、生成が失敗したときは、
  キーワード辞書によるルールベース解析に切り替える。**AI が無くても記録できるアプリであること。**
- 記録の直後に必ず「直す」「取り消す」を出す（いまあるのは「取り消す」）。記録は長押しでいつでも
  削除できるようにする（確認つき。VoiceOver の操作からも）。

### プライバシーと秘密情報
- 解析・広告・トラッキングの SDK を入れない。1 つでも入れると、`PRIVACY.md` と App Store の
  プライバシー表示（データの収集なし）の両方が崩れる。データの扱いを変えるときは `PRIVACY.md` を先に直す。
- **リポジトリは公開。** 証明書、.p8 などの鍵、個人情報をコミットしない。CI の鍵と署名用の証明書（.p12）は
  GitHub の Environment Secrets に置く（`docs/release-flow.md`）。Actions のログも誰でも読めるので、
  ワークフローで証明書の名前や Secrets の中身を出さない。
- ワークフローの `uses:` はコミットの SHA で固定し、版をコメントに書く（`@<SHA> # v7.0.1`）。
  Dependabot が組で書き換える。`scripts/asc.py` の依存は `scripts/requirements.in` を直し、
  `pip-compile --generate-hashes` で `scripts/requirements.txt`（生成物）を作り直す（手順はファイルの先頭）。
- 脆弱性の報告は非公開の窓口（GitHub の Private vulnerability reporting。`SECURITY.md`）で受ける。

### コードの書き方
- コメントは「なぜそうするか」を日本語で書く。何をしているかはコードで分かるようにする。

## ドキュメント
- `docs/design.md` — プロダクトの設計と決定事項（入力と AI、収益化、画面、未決事項）
- `docs/release-flow.md` — リリースフロー（main マージで App Store Connect へ自動アップロード）
- `PRIVACY.md` — プライバシーポリシー（草案。初回リリースの手順で草案の注記を外し、施行日を入れて
  main へ入れてから審査に出す。`docs/release-flow.md` の「初回リリース（0.1.0）の進め方」）
- `SECURITY.md` — 脆弱性・プライバシーの問題の非公開の報告窓口
- `CHANGELOG.md` — 変更履歴（先頭の見出しがバージョンの検査とリリースノートに使われる）
- `LICENSE` — 権利留保。個人が自分の端末で試すための clone・ビルドだけを許可（再配布・公開・商用は不可）
