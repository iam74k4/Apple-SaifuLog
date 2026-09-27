# SaifuLog-Apple

ひとことで記録できる iPhone の家計簿アプリ「SaifuLog（サイフログ）」。文章の理解は
端末内の AI（Apple の Foundation Models）で行い、家計のデータを端末の外に出さない。

## 現在の到達点
- 初期構成の段階。プロジェクトの骨組み・CI/CD・ドキュメントと、**ひとこと入力の試作**まで。
  - 試作済み: 一行の読み取り（端末内 AI、使えない端末ではキーワード辞書）、タイムライン、記録直後の
    「取り消す」、今月の支出と収入の合計。
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
  署名なし）。CI と同じ経路なので、手元で通れば CI でも通る
- `make test` — `swift test --package-path Packages/SaifuLogCore`（コアのテスト）
- `make clean` / `make open` — 生成物の削除 / Xcode で開く
- `release.mk`（Makefile の末尾で読み込む）:
  - `make version` — いまの `MARKETING_VERSION` を表示する
  - `make check-version` — `MARKETING_VERSION` と CHANGELOG 先頭の見出しの一致を確かめる
  - `make archive` — Release の .xcarchive を `build/` に作る。`BUILD_NUMBER=…` でビルド番号を上書きできる。
    できたアプリの Info.plist にバージョン・ビルド番号・アイコンが入っているかも確かめる（CI の build でも走る）
  - `make export-ipa` — アーカイブから .ipa を書き出すだけ（送信しない）。署名とエンタイトルメントの確認用
  - `make upload` — `Config/ExportOptions.plist` で App Store Connect へ送る。認証は
    App Store Connect API キー（環境変数 `ASC_API_KEY_ID` / `ASC_API_ISSUER_ID` / `ASC_API_KEY_PATH`）
- 署名のチームは `Config/Base.xcconfig` の `DEVELOPMENT_TEAM`。手元で別のチームを使うときは
  `.gitignore` 済みの `Config/Secrets.xcconfig` で上書きする（Base.xcconfig が `#include?` で読む）。
  追跡しているファイルを書き換えると、うっかりコミットして全員の署名が変わるため。
- 対象: iPhone のみ（`TARGETED_DEVICE_FAMILY = 1`）、iOS 26.0 以上、Swift 6（strict concurrency complete）。
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
- 文字列は String Catalog（`.xcstrings`）で、開発言語 ja に en を足す。ホーム画面の表示名は
  `SaifuLog/Resources/InfoPlist.xcstrings` の `CFBundleDisplayName`（ja「サイフログ」/ en「SaifuLog」）。
- アプリアイコンは `Resources/Assets.xcassets/AppIcon.appiconset/` の 3 枚（1024 × 1024・透過なし）。
  `AppIcon.png`（ライト: 白地に黒い財布）、`AppIcon-Dark.png`（ダーク）、`AppIcon-Tinted.png`（色付き）。
  元の SVG は `design/icon/`。**AppIcon を空にしない。** 空でもビルドは通るが、App Store Connect が
  アップロードを弾く（`make archive` の検査で止まる）。

### AI の扱い
- AI はすべて端末内（Foundation Models）。クラウドの API は使わない。サーバーも持たない。
- **数字は AI に計算させない。** AI には文章から値（総額・人数・カテゴリなど）を取り出させ、
  割り算・合計・平均・残りはコード（SaifuLogCore）で計算する。端末内モデルは小さく、計算を誤るため。
- Apple Intelligence が使えない端末（非対応機種・オフ・モデル準備中）や、生成が失敗したときは、
  キーワード辞書によるルールベース解析に切り替える。**AI が無くても記録できるアプリであること。**
- 記録の直後に必ず「直す」「取り消す」を出す。

### プライバシーと秘密情報
- 解析・広告・トラッキングの SDK を入れない。1 つでも入れると、`PRIVACY.md` と App Store の
  プライバシー表示（データの収集なし）の両方が崩れる。データの扱いを変えるときは `PRIVACY.md` を先に直す。
- **リポジトリは公開。** 証明書、.p8 などの鍵、個人情報をコミットしない。CI の鍵は GitHub の
  Environment Secrets に置く（`docs/release-flow.md`）。

### コードの書き方
- コメントは「なぜそうするか」を日本語で書く。何をしているかはコードで分かるようにする。

## ドキュメント
- `docs/design.md` — プロダクトの設計と決定事項（入力と AI、収益化、画面、未決事項）
- `docs/release-flow.md` — リリースフロー（main マージで App Store Connect へ自動アップロード）
- `PRIVACY.md` — プライバシーポリシー（草案。施行日は初回リリース時に確定）
- `CHANGELOG.md` — 変更履歴（先頭の見出しがバージョンの検査とリリースノートに使われる）
