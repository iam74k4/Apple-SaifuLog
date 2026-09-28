# リリースフロー

`develop` を `main` へマージすると、そこから先は自動で進む。アーカイブ、署名、
App Store Connect へのアップロード、審査への提出、配信後のタグ打ちまで、
人が押すボタンは無い。

> **現状:** 仕組みは用意してあるが、まだ一度も通していない（最初のリリース前）。
> 初回は下の「[一度だけの準備](#一度だけの準備)」と「[初回リリース（0.1.0）の進め方](#初回リリース010の進め方)」から始める。

---

## 全体像

```
作業ブランチ（feature/… など。develop から切る）
   │  PR（CI: build）
   ▼
develop で統合
   │  バージョンを上げ、CHANGELOG を整える
   ▼
PR: develop → main ─ マージ ─▶ release.yml
                                  │
                                  ├─ upload（macOS: xcode-27）
                                  │    make archive で .xcarchive を作り（署名なし）、
                                  │    make upload でクラウド署名して App Store Connect へ送る
                                  │
                                  └─ submit（Linux）
                                       ビルドの処理を待ち、
                                       バージョンを用意し、
                                       CHANGELOG をリリースノートに入れ、
                                       審査に提出する
                                  ▼
                              Apple の審査
                                  │  通れば自動で配信開始（AFTER_APPROVAL）
                                  ▼
                            tag-release.yml（3 時間おき）
                               配信中を見つけたら
                               タグ v<version> と GitHub Release を作る
```

| 誰が | 何を |
|---|---|
| 自動（build.yml） | PR と push のたびに `make build`・`make test`・`make check-version` と、署名なしの `make archive`（提出物と同じ Release・実機向けの組み立てを、マージ前に一度通す。バージョン・ビルド番号・アイコンがアプリの Info.plist に入っているかも見る） |
| 自動（release.yml / upload） | アーカイブ、クラウド署名、App Store Connect へのアップロード |
| 自動（release.yml / submit） | 処理待ち、バージョンの用意、リリースノート、**審査への提出** |
| 自動（tag-release.yml） | 配信を検知してタグと GitHub Release を作成 |
| 人 | バージョンを上げる、CHANGELOG を書く、App Store Connect の Web でしかできない設定、リジェクトの対応 |

タグを最後に打つのは、リジェクトされた場合に「タグはあるのに世に出ていない」版を
残さないため。release.yml はタグの有無で「配信済みか」を判定しているので、先に打つと
リジェクト後の出し直しもスキップされてしまう。

### ブランチ運用

- **`main`** はリリース済みの版だけ。**`main` へのマージがリリースの合図になる。**
  リリースするつもりのない変更を main へ入れない。
- **`develop`** は統合ブランチ。直接コミットせず、作業ブランチからの PR でだけ変える。
- 作業ブランチは `develop` から切る（`feature/…`、`fix/…`、`docs/…`、`chore/…`）。
  コミットは Conventional Commits（`CLAUDE.md`）。
- **develop → main の PR は「Create a merge commit」でマージする。** Squash すると、
  main にだけ存在するコミットができて develop と履歴が分かれ、次の develop → main で
  身に覚えのない差分や衝突が出る。作業ブランチ → develop は squash でよい。

### 二重に出さないための歯止め

- `main` のバージョンに対応するタグ（`v<MARKETING_VERSION>`）が既にあれば、release.yml は
  何もしない。リリース後にドキュメント修正だけを main へ入れても、二重アップロードは起きない。
- 同じバージョンが App Store Connect で既に配信中なら、submit ジョブは
  「MARKETING_VERSION を上げてください」と言って止まる。
- 同じバージョンが審査待ち・審査中なら、submit ジョブはビルドを差し替えずに止まる
  （アップロードしたビルドは TestFlight に残るだけ）。
- tag-release.yml はタグと GitHub Release が既にあれば即座に終わる。タグだけがあって Release が
  無い（前回の実行が Release の作成で落ちた）ときは、配信状況を見直さずに Release だけを作る。
- release.yml は同時に 1 つしか走らない（`concurrency`）。続けてマージしても、前の
  アップロードを途中で打ち切らない。

---

## 一度だけの準備

### 1. Apple 側で用意するもの

証明書やプロビジョニングプロファイルを手で作る必要は**無い**。署名は export の段階で
Xcode が用意する（自動署名 + クラウド管理の配布証明書）。要るのは次のものだけ。

| もの | どこで | 補足 |
|---|---|---|
| Apple Developer Program | developer.apple.com | チーム ID は `NL9ZXK2SGR` |
| **Bundle ID の登録** | Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs | `com.iam74k4.SaifuLog`（Explicit）。Capability は今は要らない |
| **アプリレコード** | App Store Connect → アプリ → **+** → 新規 App | プラットフォーム iOS、プライマリ言語は日本語、Bundle ID は上のもの、SKU は任意（例 `saifulog-ios`） |
| App Store Small Business Program | developer.apple.com/app-store/small-business-program | 加入すると手数料が 15% になる（`docs/design.md` §6）。申し込みは別途 |

Bundle ID を先に登録するのは、CI の export が**自動署名でもアプリ ID は登録しない**ため
（`xcodebuild -help` の `signingStyle` の説明）。手元の Xcode で一度実機にビルドすれば
自動で登録されるが、CI だけで回すなら先に作っておく。

### 2. App Store Connect API キーを作る

App Store Connect → **ユーザとアクセス** → **統合**（Integrations）→
**App Store Connect API** → チームキー → **+**。

- ロールは **Admin**。CI の export は、クラウド管理の配布証明書を API キーの権限で
  作る・使う。これには Admin が要り、App Manager や Developer だと
  「Cloud signing permission error」で止まる。Admin はアップロード、バージョンの作成、
  審査への提出の権限も含むので、キーは 1 本で足りる
- 作成すると **Issuer ID** と **キー ID** が表示され、**.p8 ファイルは一度しか
  ダウンロードできない**。安全な場所に保管する
- Admin のキーは強い。置き場所は次の Environment Secrets だけにし、漏れた疑いが
  あれば同じ画面ですぐに取り消す（取り消して作り直し、Secrets を差し替えるだけで済む）
- リポジトリは公開なので、.p8 をリポジトリに置かない（`.gitignore` で `*.p8` を除外済み）

### 3. Environment（`release`）の Secrets に入れる

リポジトリ Secrets ではなく **Environment Secrets** に置く。App Store へ提出できる
鍵なので、読める範囲を main を通ったコードだけに絞るため。

1. Settings → **Environments** → New environment → 名前は `release`
2. **Deployment branches and tags** を `Selected branches and tags` にし、`main`
   だけを許可する。これで他のブランチからは鍵が解決されず、workflow_dispatch でも
   走らせられない
3. **Environment secrets** → Add secret で下の表を登録する

**Required reviewers は付けないこと。** `tag-release.yml` は 3 時間おきの cron で
動き、その大半は「タグと Release が既にある」で即座に終わる。承認を必須にすると、その
すべてが承認待ちで止まる。

| Secret 名 | 中身 |
|---|---|
| `ASC_API_KEY_ID` | API キーのキー ID（10 文字の英数字） |
| `ASC_API_ISSUER_ID` | Issuer ID（UUID 形式） |
| `ASC_API_KEY_P8` | .p8 ファイルの中身そのまま（`-----BEGIN PRIVATE KEY-----` から末尾まで） |

証明書の .p12 やプロファイルの Secret は要らない。

### 4. 振る舞いを変えたいとき（Variables、任意）

こちらは秘密ではないので、**リポジトリの** Variables に置く
（Settings → Secrets and variables → Actions → Variables タブ）。既定のままで
よければ何もしなくてよい。

`ASC_AUTO_SUBMIT` は submit ジョブの job-level `if` で読んでおり、そこは
Environment が解決される前に評価される。Environment 側に置くと効かないため、
リポジトリ Variables に置く。

| 変数名 | 既定 | 効果 |
|---|---|---|
| `ASC_AUTO_SUBMIT` | （未設定 = 提出する） | `false` にすると、main へのマージではアップロードだけして審査に出さない。手動実行で `mode=submit` を選んだときは、この値に関係なく提出する |
| `ASC_RELEASE_TYPE` | `AFTER_APPROVAL` | `MANUAL` にすると、審査を通っても自分で配信開始を押すまで公開されない |
| `BUILD_NUMBER_OFFSET` | `0` | ビルド番号の底上げ。下の「[ビルド番号の決め方](#ビルド番号の決め方)」 |

`ASC_RELEASE_TYPE=MANUAL` にした場合、審査通過後に App Store Connect で
「このバージョンをリリース」を押すまで配信は始まらない。tag-release.yml は
配信が始まるまでタグを打たないので、押し忘れるとタグも付かない。

### 5. App Store Connect（Web）でしかできない初回設定

API では済ませられない、または一度だけなので Web で行うもの。ここが済んでいないと、
submit ジョブは提出の段階で止まる（アップロードまでは進む）。

| 項目 | 場所 | 内容 |
|---|---|---|
| アプリ情報 | アプリ → 一般 → App 情報 | 名前（日本語の表記は `docs/design.md` §13 で未決）、サブタイトル（案: ja「ひとことで家計簿」/ en「Budget in one line」）、カテゴリ（ファイナンス）、コンテンツ配信権 |
| 年齢制限 | App 情報 → 年齢制限 | 質問に答える |
| 価格と配信状況 | 価格および配信状況 | 無料。配信する国と地域。**Apple Silicon 搭載の Mac と Apple Vision Pro での配信をオフにする**（iPhone 向けのアプリは、既定のままだとこれらでも配信される。README の「Mac には対応しません」と揃えるため） |
| App のプライバシー | App のプライバシー | プライバシーポリシーの URL（`PRIVACY.md`）と、「データの収集なし」の回答（`docs/design.md` §11） |
| スクリーンショット | バージョン → iPhone | **6.9 インチ**（1320 × 2868 など）が必須。小さい画面の分は自動で縮小される |
| 説明文など | バージョン | 説明、キーワード、**サポート URL（必須）**、著作権。英語ローカライズを出すなら en の分も |
| App Review に関する情報 | バージョン → App Review に関する情報 | 連絡先と審査メモ。AI の機能は Apple Intelligence 対応機種でしか動かないこと、非対応機種でも記録はできること、ログインが要らないことを書いておく |
| 輸出コンプライアンス | （Info.plist で回答） | `project.yml` で `ITSAppUsesNonExemptEncryption = NO` を入れている。未回答のビルドだと `asc.py wait-build` が止まる |
| EU のトレーダー申告 | ビジネス | EU で配信するには、トレーダーかどうかの申告が要る。トレーダーの場合は住所などが EU のストアに表示される |
| 契約・税金・口座 | ビジネス | 無料アプリだけなら不要。プレミアム（App 内課金）を出す前に有料 App 契約と口座・税の情報が要る |

### 6. ブランチと保護ルール

`develop` がまだ無ければ、`main` から作る。

```bash
git checkout main && git pull
git checkout -b develop
git push -u origin develop
```

**既定のブランチは `main` のままにする。** tag-release.yml の cron は既定ブランチの
定義で動き、Environment `release` は main からの実行しか許さないため。既定を develop に
すると、cron の実行が Environment に弾かれる。その代わり、PR を作るときは base が
`develop` になっているかを毎回確かめる（Dependabot の PR は設定で develop 宛てにしてある）。

main と develop の保護は **Ruleset** で行う（Settings → Rules → Rulesets →
New ruleset → New branch ruleset）。

| 設定 | 値 | 理由 |
|---|---|---|
| Ruleset name | `main-develop` など | |
| Enforcement status | Active | |
| Target branches | Add target → Include by pattern → `main`、`develop` の 2 つ | |
| Restrict deletions | オン | develop → main をマージしたときの「ブランチの自動削除」や手違いで、統合ブランチが消えないように |
| Require a pull request before merging | オン（Required approvals は **0**） | 直接 push を止める。1 人で開発していると自分の PR は承認できないので、承認数は 0 にする |
| Require status checks to pass | オン → Add checks → **`build`** | CI の通っていない変更を入れない。`build` は build.yml のジョブ名 |
| Block force pushes | オン | 履歴の書き換えを止める |
| Bypass list | 空 | 抜け道を作らない（緊急時は一時的に Ruleset を Disabled にする） |

- `build` は、build.yml が一度でも走らないと候補に出てこない。先にこのブランチを push して
  PR を作り、build が走ってから Ruleset を作る。
- 「Require branches to be up to date before merging」は付けなくてよい。develop → main は
  もともと最新で、作業ブランチ → develop で毎回の取り込みを強いる手間の方が大きい。
- Settings → General → Pull Requests で **Allow merge commits** を有効にしておく
  （develop → main に使う）。

---

## 毎回のリリース手順

人がやるのは 2 つだけ。

1. **develop で仕上げる**（作業ブランチ → PR で）
   - `Config/Base.xcconfig` の `MARKETING_VERSION` を上げる。
     ビルド番号（`CURRENT_PROJECT_VERSION`）は CI が付けるので触らない
   - `CHANGELOG.md` の「未リリース」の内容を新しいバージョン見出し
     （`## [X.Y.Z] - YYYY-MM-DD`）に移す。**この節がそのまま App Store の
     「このバージョンでの変更点」と GitHub Release の本文になる。** App Store は
     Markdown を表示しないので、太字・リンク・バッククォートを使わず、`- ` の
     箇条書きと平文で、利用者の目線で書く
   - `make check-version` で一致を確かめる（CI でも検査される）
   - 実機での確認は、手元の Xcode から入れて行う（TestFlight のビルドは main へのマージで初めてできる）
2. **PR: develop → main を作り、build が通ったら「Create a merge commit」でマージする**

あとは待つ。目安は、アップロードまで 15〜30 分、App Store Connect の処理に 10 分〜1 時間、
審査は多くが 1 日以内（混んでいると数日）。審査に通れば配信が始まり、3 時間以内に tag-release.yml が
`v<version>` のタグと GitHub Release を作る。

### 初回リリース（0.1.0）の進め方

初回だけは、署名の経路と Web の設定がまだ一度も通っていないので、段階を分ける。

1. 「一度だけの準備」の 1〜4 と 6 を済ませる。**リポジトリ変数 `ASC_AUTO_SUBMIT` を
   `false` にしておく**（最初のマージではアップロードだけにする）
   - アプリアイコン（1024 × 1024 の PNG）が `AppIcon.appiconset` に入っていることを確かめる。
     App Store Connect はアイコンの無いビルドを受け付けない。今は仮のアイコンが入っていて、
     消えていれば build.yml の `make archive` が止める（下の「[アプリアイコン](#アプリアイコンappiconappiconset)」）
2. develop → main をマージする。release.yml の upload が走り、ビルドが App Store Connect に届く
   - export（署名）で落ちたら、Actions → release → **Run workflow** → `mode=export` で、
     何も送らずに署名の経路だけを繰り返し試せる。ログに署名とエンタイトルメントが出る
3. TestFlight に処理済みのビルドが現れたら、内部テスターとして実機に入れて確かめる
4. 「一度だけの準備」の 5（Web の設定）を済ませる。初回の版は App Store Connect が
   自動で作る「1.0（提出準備中）」を、submit ジョブが `0.1.0` に書き換えて使う
   - アイコンを仮のまま審査に出すか、配色を決めて差し替えてから出すかをここで決める。
     差し替えるなら、入れ替えを作業ブランチ → develop → main とマージしてから 5 へ進む
     （`ASC_AUTO_SUBMIT` が `false` のままなので、マージではアップロードだけが走る。
     5 の Web から出すときは、新しいアイコンのビルドを選ぶ）
5. 審査に出す。どちらかで行う
   - Actions → release → Run workflow → `mode=submit`（アーカイブからやり直し、
     新しいビルド番号で送って提出する）
   - App Store Connect の Web で、3 のビルドを選んで「審査に提出」
6. `ASC_AUTO_SUBMIT` を消す（以降はマージで審査まで進む）

2〜5 の間も tag-release.yml は 3 時間おきに走る。App Store Connect に `0.1.0` の版がまだ無い
（自動でできた「1.0」のまま）ので、「まだ配信前」として何もせずに終わる（失敗にはならない）。

初回の版には「このバージョンでの変更点」の欄が無い。submit ジョブはリリースノートを
入れられずに警告を出すが、そのまま提出へ進む（失敗ではない）。

### リジェクトされたら

自動では何も起きない（`REJECTED` などの状態で止まり、tag-release.yml は
タグを打たない）。

- **アプリを直す必要があるとき:** パッチバージョンを上げて develop → main をやり直すのが
  素直。submit ジョブはリジェクトされた版の入れ物を使い回して出し直そうとするが、この経路は
  まだ一度も通していない。失敗したら App Store Connect の Web から提出する。
- **メタデータだけのとき、または返答で解決したとき:** App Store Connect の Web で直して
  出し直す。配信が始まれば tag-release.yml がタグを打つので、こちらで何かする必要はない。

### うまくいかないとき

| 症状 | 原因と対処 |
|---|---|
| `DEVELOPER_DIR ... がありません` | ランナーのイメージで Xcode が入れ替わった。ログに並ぶ Xcode から選び、build.yml と release.yml の `DEVELOPER_DIR` を一緒に直す |
| XcodeGen の `shasum` が FAILED | 取ってきた zip が固定した版と違う。値を書き換えて通さず、XcodeGen の Release の digest を確かめる |
| `Environment「release」の Secrets ... が足りません` | 「一度だけの準備」の 3 |
| ジョブが始まらずに Environment の保護ルールで止まる | main 以外のブランチから手動実行した。Environment `release` は main からしか使えない（意図どおり） |
| export で `Cloud signing permission error` | API キーのロールが Admin でない |
| export でプロファイルが作れない（アプリ ID が無い） | Bundle ID `com.iam74k4.SaifuLog` が未登録。「一度だけの準備」の 1 |
| アップロードでビルド番号の重複を言われる | 手元から大きい番号で送った、または release.yml の名前を変えた。`BUILD_NUMBER_OFFSET` で底上げする |
| `make archive` が `アプリにアイコンが入っていません` で止まる／アップロードでアイコンが無い（`CFBundleIconName` や `Missing required icon`）と言われる | `AppIcon.appiconset` に画像が無いか、`Contents.json` の `filename` で参照されていない。1024 × 1024 の PNG を置いて参照する（下の「[アプリアイコン](#アプリアイコンappiconappiconset)」） |
| アップロードで `Invalid large app icon`（透過・アルファチャンネル）と言われる | 1024 × 1024 の PNG に透過（アルファチャンネル）がある。透過なしで書き出し直す。`sips -g hasAlpha <PNG>` が `no` になればよい |
| `輸出コンプライアンス（暗号の使用）が未回答です` | Info.plist に `ITSAppUsesNonExemptEncryption` が入っていない。`project.yml` を直すか、TestFlight でそのビルドに回答してから submit ジョブを再実行する |
| `秒待ちましたが処理が終わりませんでした` | App Store Connect の処理が遅い。処理が終わったのを確かめてから、失敗した submit ジョブだけを **Re-run failed jobs** で再実行する（アップロードはやり直さない） |
| `... のため、ビルドを差し替えられません` | 審査中の版があるのに、バージョンを上げずに main へマージした。差し替えたいなら Web で審査から取り下げてから再実行、不要ならそのままでよい |
| `既に配信済み ... MARKETING_VERSION を上げてください` | バージョンの上げ忘れ |
| タグ `v<version>` はあるのに GitHub Release が無い | tag-release.yml がタグの push の後、Release の作成で落ちた。次の実行（3 時間以内。急ぐなら手動実行）で Release だけが作られる。タグは打ち直されない |

---

## 中身

### `release.mk`

`Makefile` の末尾で読み込む、提出用のターゲット。手元でも CI でも同じものを使う。

| ターゲット | 何をするか |
|---|---|
| `make version` | いまの `MARKETING_VERSION` を表示する |
| `make check-version` | `MARKETING_VERSION` と CHANGELOG 先頭の見出しの一致を確かめる |
| `make archive` | Release の `.xcarchive` を `build/` に作る。`BUILD_NUMBER=…` でビルド番号を上書き、`ARCHIVE_SIGNING=NO` で署名なし（CI）。できたアプリの Info.plist にバージョン・ビルド番号・アイコンが入っているかを確かめる |
| `make export-ipa` | アーカイブから `.ipa` を書き出すだけ。**送信しない。** 署名とエンタイトルメントを表示する |
| `make upload` | `Config/ExportOptions.plist` で書き出し、そのまま App Store Connect へ送る。手元の端末では確認を挟む |

認証は、環境変数 `ASC_API_KEY_ID` / `ASC_API_ISSUER_ID` / `ASC_API_KEY_PATH`（.p8 のパス）が
3 つとも揃っていれば API キー、無ければ Xcode にサインインしているアカウント。
どちらでも `-allowProvisioningUpdates` を付け、プロファイルの用意を Xcode に任せる。

CI がアーカイブを**署名なし**で作るのは、使い捨てのランナーで自動署名すると、実行のたびに
開発用の証明書が新しく作られ、その秘密鍵がランナーと一緒に消えるため。App Store 向けの
署名は export の段階でクラウド管理の配布証明書を使って掛け直される。

### `Config/ExportOptions.plist`

| キー | 値 | 理由 |
|---|---|---|
| `method` | `app-store-connect` | App Store Connect 向け。旧名の `app-store` は非推奨 |
| `destination` | `upload` | 書き出したものをそのまま送る（既定は手元に書き出すだけ） |
| `teamID` | `NL9ZXK2SGR` | |
| `signingStyle` | `automatic` | プロファイルとクラウド管理の配布証明書を Xcode に用意させる |
| `manageAppVersionAndBuildNumber` | `false` | 既定は YES。Xcode がビルド番号を書き換えると、`asc.py wait-build` が番号でビルドを見つけられない |
| `uploadSymbols` | `true` | クラッシュレポートを読めるようにする |
| `testFlightInternalTestingOnly` | `false` | 審査に出すビルドなので、社内テスト専用にしない |

### アプリアイコン（`AppIcon.appiconset`）

`SaifuLog/Resources/Assets.xcassets/AppIcon.appiconset` に 1024 × 1024 の PNG を 1 枚置き、
`Contents.json` の `filename` で参照する。ホーム画面などの小さい大きさは Xcode（actool）が作る。

- **アイコンが無いと、App Store Connect がアップロードを弾く。** AppIcon が空でもビルドと
  アーカイブは通ってしまうので、`make archive` の最後でアプリの Info.plist に `CFBundleIcons` が
  あるかを見て、無ければ止める。build.yml も `make archive` を通すので、main へのマージ前
  （PR の段階）で気づける
- 透過（アルファチャンネル）を入れない。透過があってもアップロードで弾かれる。角は丸めない
  （iOS が丸める）
- アイコンは「カードがのぞく財布」。ライト（白地に黒い財布）・ダーク（濃紺の地にグレーの財布）・
  色付き（tinted。黒地に白〜灰の財布で、iOS が色を付ける）の 3 枚を置き、iPhone の外観設定で
  自動的に切り替わる。元の SVG は `design/icon/` にあり、qlmanage で 1024px に書き出してから
  透過を落として（JPEG 経由で PNG に戻す）差し替える

### ビルド番号の決め方

`CFBundleVersion` は「同じ版の中で、前に送ったものより必ず大きい」ことが求められる。
release.yml は実行番号から機械的に付ける。

```
BUILD_NUMBER = BUILD_NUMBER_OFFSET + run_number × 100 + run_attempt
```

`run_number` は release.yml の実行ごとに増えて戻らず、失敗したジョブの再実行では
`run_attempt` だけが増える。これでリジェクト後の出し直しや再実行でも番号がぶつからない。
release.yml の名前を変える（`run_number` が 1 に戻る）か、手元から大きい番号で送ったときは、
リポジトリ変数 `BUILD_NUMBER_OFFSET` にそれより大きい値を入れる。

`Config/Base.xcconfig` の `CURRENT_PROJECT_VERSION`（1）は手元のビルド用で、CI では使わない。
手元から `make upload` するときは、CI の番号より大きい `BUILD_NUMBER` を渡す。

### `scripts/asc.py`

App Store Connect API を叩く小さな道具。3 つの操作だけを持つ。

| 操作 | 何をするか |
|---|---|
| `wait-build` | アップロードしたビルドの処理（`processingState`）が `VALID` になるのを待つ。輸出コンプライアンスが未回答なら止まる |
| `submit` | バージョンを用意し（無ければ作る。編集中の版があれば番号を書き換えて使う）、ビルドを紐づけ、リリースノートを入れ、審査に出す |
| `state` | いまそのバージョンがどう扱われているかを表示する。`--require-live` を付けると判定に使え、配信中なら終了コード 0、配信前なら 2（版がまだ App Store Connect に無い提出前も 2。`NOT_FOUND` と表示する）、それ以外の失敗は 1 で終わる（tag-release.yml が使う） |

認証は API キーから作る ES256 の JWT。依存は PyJWT だけで、HTTP は標準ライブラリ。
.p8 は `ASC_API_KEY_P8`（中身）か `ASC_API_KEY_PATH`（パス）で渡す。後者は release.mk と
同じ環境変数なので、手元からも試せる（`pip install "pyjwt[crypto]"` が要る）。
fastlane を持ち込むと metadata ディレクトリ一式をリポジトリで管理することになるため、
必要な部分だけを自前で持っている。

審査への提出は 3 手に分かれている（入れ物を作る → バージョンを入れる →
`submitted=true` にする）。最後の一手を忘れると「作ったのに出ていない」状態になるので、
手で API を叩くときは注意する。

リリースノートは ja と en の両方に同じもの（日本語）を入れる。アップデートの版では
全ロケールでこの欄が必須で、空だと提出で弾かれるため、空よりはよいと割り切っている。

### `scripts/changelog-section.sh`

`CHANGELOG.md` から `## [X.Y.Z]` の節だけを取り出す。App Store のリリースノート
（`--plain` で Markdown の記号を外す）と GitHub Release の本文の両方がこれを使う。
二か所で別々に書くと食い違うため。

### `scripts/check-version.sh`

`Config/Base.xcconfig` の `MARKETING_VERSION` を読み、CHANGELOG 先頭のバージョン見出しと
比べる。`--print` で版だけを出す。build.yml、release.yml、tag-release.yml、`make version` が
すべてこれを通るので、版の読み方は 1 か所しかない。ubuntu のランナーでも動くよう POSIX sh で書いている。

### ランナーと道具の版

| もの | 値 | 置き場所 |
|---|---|---|
| ランナー | `xcode-27`（パブリックプレビュー。Xcode 27.0 と iOS 27 SDK） | build.yml / release.yml の `runs-on` |
| Xcode | `/Applications/Xcode_27.0.app` | 同 `DEVELOPER_DIR` |
| XcodeGen | 2.46.0（公式 zip を SHA-256 で照合） | 同 `XCODEGEN_VERSION` / `XCODEGEN_SHA256` |

`macos-latest`（macos-26）の Xcode は 26.x 止まりで iOS 27 SDK が無い。iOS 27 の API を
使った時点で CI だけが落ちるので、Xcode 27 の入った `xcode-27` を使っている。
GA でラベルが変わったら、build.yml と release.yml を一緒に直す。どれも Dependabot の
対象外なので、上げるときは手で、意図的な PR で上げる。

### cron の注意

`tag-release.yml` の `schedule` は、**このリポジトリの既定ブランチ（`main`）に
あるファイル**で動く。ワークフローを直したら、main に入るまで反映されない。
develop へマージしただけでは、次のリリースで main に入るまで古い定義のまま動く。
cron の時刻は UTC。

また GitHub は、60 日間まったく動きの無いリポジトリで scheduled workflow を
自動的に止める。長く触っていない状態でリリースしたときは、Actions タブで
有効になっているかを確認する（止まっていても、tag-release は手動実行できる）。

---

## この先やれること

| やれること | 手段 |
|---|---|
| 英語のリリースノートを分ける | CHANGELOG に英語の節を持たせ、`asc.py` の `set_whats_new` でロケールごとに入れ分ける |
| 審査結果を通知する | `scripts/asc.py state` を cron で回して通知する |
| 審査状態の変化を待たずに拾う | App Store Connect の Webhook（公開 URL の受け口が要る） |
| スクリーンショットや説明文もリポジトリで管理する | fastlane `deliver` に寄せる |
| 段階的リリース（Phased Release） | `appStoreVersionPhasedReleases` を叩く |
| main へのマージ前に TestFlight で確かめる | develop 用に `testFlightInternalTestingOnly=true` の書き出しを足す（Environment の配備ブランチも見直す） |

### Capability（iCloud など）を足すとき

CI のアーカイブは署名なしなので、エンタイトルメントがアーカイブに焼かれない。iCloud
（CloudKit）、App Groups、プッシュ通知などを足したら、main へ入れる前に
`mode=export` で走らせ、ログの「エンタイトルメント」に載っているかを確かめる。
抜け落ちていたら、アーカイブを署名ありに切り替える。

- 開発用の証明書（.p12）を Secret に入れ、使い捨てのキーチェーンに取り込んでから
  `ARCHIVE_SIGNING=YES` でアーカイブする。プロファイルは `-allowProvisioningUpdates` と
  API キーで Xcode が用意する

Capability を足すときは、あわせて Bundle ID の設定（Identifiers）でその Capability を
有効にする。export はアプリ ID の設定を変えないため。

### exportArchive の upload が失敗したら

`xcodebuild -exportArchive` の `destination=upload` が使えなくなったときの乗り換え先
（どれも同じ API キーで動く）。差し替えるのは release.yml の「App Store Connect へ
アップロード」ステップだけで、submit 以降はそのまま使える。

- `make export-ipa` で `.ipa` を書き出してから送る
  - **Transporter**（Mac App Store の Apple 製アプリ。手で送るときの逃げ道）
  - `xcrun altool --upload-package`（非推奨扱いが続いている）
  - **fastlane** `pilot upload`（`upload_to_testflight`）
- App Store Connect の Build Upload API（REST）を直接呼ぶ

---

## 関連ファイル

- `.github/workflows/release.yml` — main マージでアップロードし、審査に出す
- `.github/workflows/tag-release.yml` — 配信を検知してタグと GitHub Release を作る
- `.github/workflows/build.yml` — PR と push のビルド確認 CI（必須チェック `build`）
- `.github/dependabot.yml` — GitHub Actions の版上げ PR（develop 宛て）
- `release.mk` — `make version` / `check-version` / `archive` / `export-ipa` / `upload`
- `Config/ExportOptions.plist` — 書き出しと送信の設定
- `Config/Base.xcconfig` — バージョンの正（`MARKETING_VERSION`）
- `scripts/asc.py` — App Store Connect API を叩く道具
- `scripts/changelog-section.sh` — CHANGELOG から該当バージョンの節を取り出す
- `scripts/check-version.sh` — バージョンを読み、CHANGELOG との一致を確かめる
- `CHANGELOG.md` — 変更履歴（各節がリリースノートになる）
