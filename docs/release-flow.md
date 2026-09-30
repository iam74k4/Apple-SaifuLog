# リリースフロー

`develop` を `main` へマージすると、そこから先は自動で進む。アーカイブ、署名、
App Store Connect へのアップロード、審査への提出、配信後のタグ打ちまで、
人が押すボタンは無い。

> **現状:** 仕組みは用意してあるが、まだ一度も通していない（最初のリリース前）。
> 初回は下の「[一度だけの準備](#一度だけの準備)」と「[初回リリース（0.1.0）の進め方](#初回リリース010の進め方)」から始める。
> 配信後にタグと GitHub Release を作る tag-release.yml は、最初のリリースまで Actions で無効にしてある（2026-09-30 から）。
> 初めて main へマージするときに有効に戻す（「[既定のブランチ](#既定のブランチ)」と「初回リリース」の 2）。

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
                                  │    承認済みの版でないかを App Store Connect で確かめ、
                                  │    開発用の証明書を使い捨てのキーチェーンに取り込み、
                                  │    make archive で署名ありの .xcarchive を作り、
                                  │    make export-ipa で送らずに書き出してエンタイトルメントを照合し
                                  │    （main で確かめるまでは、抜けていても警告だけ）、
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
                               App Store Connect で配信中の版を見つけたら、
                               そのビルドを作ったコミットに
                               タグ v<version> と GitHub Release を作る
```

| 誰が | 何を |
|---|---|
| 自動（build.yml） | PR と push のたびに `make build`・`make check-strings`（String Catalog とコードの文字列の整合）・`make test`（コアのテスト）・`make build-tests` と `make test-app`（アプリのテストのビルドと、シミュレータでの実行）・`make test-storekit`（購入のテストを、SKTestSession が動く iOS 26.2 のシミュレータで。1 つでも飛ばされたら失敗）・`make check-version` と、署名なしの `make archive`（提出物と同じ Release・実機向けの組み立てを、マージ前に一度通す。バージョン・ビルド番号・アイコンがアプリの Info.plist に入っているかと、社内テスト用の診断画面と家族との家計の共有と撮影用のデモが入っていないかも見る） |
| 自動（release.yml / upload） | 承認済みの版ならスキップ、アーカイブ（開発用の証明書で署名）、エンタイトルメントの照合（送らずに書き出す。いまは抜けていても警告だけ）、クラウド署名、App Store Connect へのアップロード |
| 自動（release.yml / submit） | 処理待ち、バージョンの用意、リリースノート、**審査への提出** |
| 自動（tag-release.yml） | 配信を検知し、配信されたビルドを作ったコミットにタグと GitHub Release を作成（最初のリリースまでは無効にしてあり、初めて main へマージするときに人が有効に戻す） |
| 人 | バージョンを上げる、CHANGELOG を書く、App Store Connect の Web でしかできない設定、リジェクトの対応 |
| 人（任意）→ release.yml の `mode=testflight` | main へマージする前の develop のビルドを、診断画面入りで TestFlight の社内テスト専用に送る（審査には出ない。下の「[TestFlight で実機に入れる（社内テスト）](#testflight-で実機に入れる社内テスト)」） |

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
  main にだけ存在するコミットができて develop と履歴が分かれ、次の develop → main から毎回
  `Config/Base.xcconfig` と `CHANGELOG.md` で衝突する。main の Ruleset は merge しか許さない
  ようにしてある（下の「[6. ブランチと保護ルール](#6-ブランチと保護ルール)」）。作業ブランチ → develop は squash でよい。

### 二重に出さないための歯止め

- `main` のバージョンに対応するタグ（`v<MARKETING_VERSION>`）が既にあれば、release.yml は
  何もしない。リリース後にドキュメント修正だけを main へ入れても、二重アップロードは起きない。
- タグがまだ無くても、その版が App Store Connect で承認済み以降（配信待ち・配信中など）なら、
  release.yml はアップロードせずに notice を出して終わる（`asc.py state --require-open`）。承認から
  tag-release がタグを打つまでの間（最大 3 時間。`ASC_RELEASE_TYPE=MANUAL` なら配信を押すまで）に
  版を上げずにマージしても、赤で落ちない。
- 同じバージョンが App Store Connect で既に配信中なら、submit ジョブは
  「MARKETING_VERSION を上げてください」と言って止まる。
- 同じバージョンが審査待ち・審査中なら、submit ジョブはビルドを差し替えずに止まる
  （アップロードしたビルドは TestFlight に残るだけ）。
- 前の版が審査中・配信待ちのまま次の版を main へ入れると、submit ジョブは新しい版を作らずに、
  前の版が片づいてから再実行するよう案内して止まる（App Store Connect は進行中の版を 1 つしか
  持てない）。前の版のタグと Release は、配信が始まれば tag-release.yml が付ける。
- tag-release.yml はタグと GitHub Release が既にあれば即座に終わる。タグだけがあって Release が
  無い（前回の実行が Release の作成で落ちた）ときは、配信状況を見直さずに Release だけを作る。
- release.yml は同時に 1 つしか走らない（`concurrency`）。続けてマージしても、前の
  アップロードを途中で打ち切らない。待っている実行が、後から来た実行（手動実行など）に
  置き換えられて取り消されることもない（`queue: max`）。
- 審査に出す（submit ジョブ）のは main の実行だけ（job の `if` で `github.ref == refs/heads/main` を明示）。
  App Store へ出せる形で送る `mode=submit` / `mode=upload` を main 以外から走らせると、upload ジョブの最初で止まる。
  develop から送れるのは `mode=testflight` の社内テスト専用のビルド（`testFlightInternalTestingOnly`）だけで、
  Apple が審査にも外部テストにも出させない。
- `mode=testflight` は、タグ（`v<version>`）があってもスキップしない（何度送ってもよい。ビルド番号は実行ごとに増える）。
  ただし配信済み（タグあり）や承認済みの版には Apple が新しいビルドを受け付けないので、アーカイブの前に止まり、
  版を上げるよう案内する。
- 診断画面（社内テスト用）は `INTERNAL_BUILD=YES` のアーカイブ（`mode=testflight`）にだけ入る。main への push と
  `mode=submit` / `upload` / `export` は `INTERNAL_BUILD=NO` で作り、release.mk ができたアプリの中身を見て、
  診断画面が入っていれば止める（アーカイブの直後と、書き出し・アップロードの前）。
- 家族・パートナーとの家計の共有（実機で確かめる前の機能。`docs/design.md` §5-5）も同じく、`INTERNAL_BUILD=YES` のアーカイブでだけ
  有効になる。release.mk は、`INTERNAL_BUILD=NO` のアーカイブで有効になっていれば（印の文字列 `RELEASE_HOUSEHOLD_MARKER` があるか、
  Info.plist に `CKSharingSupported` があれば）止める。
- App Store のスクリーンショットを撮るための撮影用のデモ（`SaifuLog/ScreenshotDemo/`）は DEBUG のビルドだけに入る。release.mk は、
  どのアーカイブ（`INTERNAL_BUILD` によらない）にも印の文字列 `RELEASE_SCREENSHOT_DEMO_MARKER` があれば止める。

---

## 一度だけの準備

### 1. Apple 側で用意するもの

配布用の証明書（Apple Distribution）やプロビジョニングプロファイルを手で作る必要は**無い**。
App Store 向けの署名は export の段階で Xcode が用意する（自動署名 + クラウド管理の配布証明書）。
手で用意する証明書は、アーカイブの署名に使う開発用の証明書（Apple Development）の .p12 だけ
（下の「[署名ありのアーカイブ](#署名ありのアーカイブ)」）。要るのは次のもの。

| もの | どこで | 補足 |
|---|---|---|
| Apple Developer Program | developer.apple.com | チーム ID は `NL9ZXK2SGR` |
| **Bundle ID の登録** | Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs | `com.iam74k4.SaifuLog`（Explicit）。Capability の **Data Protection** をオンにして **Complete Protection** を選ぶ（エンタイトルメント `default-data-protection` と揃える）。**iCloud**（CloudKit。コンテナ `iCloud.com.iam74k4.SaifuLog` を割り当てる）と **Push Notifications** もオンにする（iCloud 同期。下の「[Capability（iCloud など）を足すとき](#capabilityicloud-などを足すとき)」）。済み |
| **アプリレコード** | App Store Connect → アプリ → **+** → 新規 App | プラットフォーム iOS、プライマリ言語は日本語、Bundle ID は上のもの、SKU は任意（例 `saifulog-ios`） |
| **端末の登録（1 台以上）** | Certificates, Identifiers & Profiles → Devices | アーカイブは開発用のプロファイルで署名するので、チームに登録した端末が 1 台も無いとプロファイルを作れない。手元の Xcode でその iPhone に一度ビルドすれば自動で登録される |
| **開発用の証明書（.p12）** | Xcode → 設定 → Accounts → Manage Certificates… | アーカイブの署名に使う Apple Development の証明書。書き出し方と年に一度の更新は「[署名ありのアーカイブ](#署名ありのアーカイブ)」 |
| App Store Small Business Program | developer.apple.com/app-store/small-business-program | 加入すると手数料が 15% になる（`docs/design.md` §6）。申し込みは別途 |

Bundle ID を先に登録するのは、CI の export が**自動署名でもアプリ ID は登録しない**ため
（`xcodebuild -help` の `signingStyle` の説明）。手元の Xcode で一度実機にビルドすれば
自動で登録されるが、CI だけで回すなら先に作っておく。Data Protection も同じ理由で、export は
アプリ ID の Capability を変えないので、先にオンにしておく（アプリは
`project.yml` のエンタイトルメントで保存先を NSFileProtectionComplete にしている。`docs/design.md` §5-4）。iCloud と
Push Notifications も同じ理由で先にオンにしておく（エンタイトルメントに iCloud のコンテナと `aps-environment` がある）。

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
鍵なので、読める範囲を保護ルールの掛かったブランチ（main と develop）のコードだけに絞るため。

1. Settings → **Environments** → New environment → 名前は `release`
2. **Deployment branches and tags** を `Selected branches and tags` にし、`main` と `develop`
   だけを許可する（Add deployment branch or tag rule で 1 つずつ足す）。これでほかのブランチからは鍵が解決されず、
   workflow_dispatch でも走らせられない
   - `develop` は、develop のビルドを TestFlight で試す `mode=testflight` のために足す（「[TestFlight で実機に入れる（社内テスト）](#testflight-で実機に入れる社内テスト)」）。
     足さなければ、develop からの手動実行は Environment の保護ルールで始まらない（main へのリリースには影響しない）
   - develop を足すと、審査に出すのを main に限っているのは Environment の設定ではなく、ワークフローの条件になる。
     submit ジョブは `github.ref == refs/heads/main` のときしか走らず、App Store へ出せる形で送る `mode=submit` /
     `mode=upload` も main 以外からは upload ジョブの最初で止まる。develop から送れる社内テスト専用のビルドは、Apple が
     審査にも外部テストにも出させない
   - ただし、これらの条件は走らせるブランチ側の `release.yml` に書かれている。develop に入った PR でこの条件を外せば、
     develop から Admin の鍵で審査に出せる。main だけを許していたときは Environment の設定そのものが main に絞っていたが、
     いまそれを防いでいるのは develop の Ruleset（直接 push できない、PR と `build` が必須）だけ。承認数は 0 なので
     （「6. ブランチと保護ルール」）、人の目を通ることまでは保証しない。`.github/workflows/` を変える PR は、develop へ
     マージする前に差分を自分で見る
   - 作業ブランチ（`feature/*` など）は足さない。保護ルールの無いブランチから Admin 権限の鍵を読めるようになるため。
     作業ブランチのビルドを試すときは、develop へマージしてから走らせる
3. **Environment secrets** → Add secret で下の表を登録する

**Required reviewers は付けないこと。** `tag-release.yml` は 3 時間おきの cron で
動き、その大半は「タグと Release が既にある」で即座に終わる。承認を必須にすると、その
すべてが承認待ちで止まる。

| Secret 名 | 中身 |
|---|---|
| `ASC_API_KEY_ID` | API キーのキー ID（10 文字の英数字） |
| `ASC_API_ISSUER_ID` | Issuer ID（UUID 形式） |
| `ASC_API_KEY_P8` | .p8 ファイルの中身そのまま（`-----BEGIN PRIVATE KEY-----` から末尾まで） |
| `APPLE_DEV_CERT_P12_BASE64` | 開発用の証明書（Apple Development）の .p12 を base64 にしたもの（`base64 -i <ファイル>` の出力） |
| `APPLE_DEV_CERT_P12_PASSWORD` | その .p12 を書き出したときに付けたパスワード |

.p12 の書き出し方は下の「[署名ありのアーカイブ](#署名ありのアーカイブ)」。配布用の証明書（Apple Distribution）や
プロファイルの Secret は要らない。

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
| `BUILD_NUMBER_OFFSET` | `0` | ビルド番号の底上げ。0 以上の整数で、先頭に 0 を付けない（`010` はシェルが 8 進数として読むので、release.yml と tag-release.yml が止める）。下の「[ビルド番号の決め方](#ビルド番号の決め方)」 |

`ASC_RELEASE_TYPE=MANUAL` にした場合、審査通過後に App Store Connect で
「このバージョンをリリース」を押すまで配信は始まらない。tag-release.yml は
配信が始まるまでタグを打たないので、押し忘れるとタグも付かない。

### 5. App Store Connect（Web）でしかできない初回設定

API では済ませられない、または一度だけなので Web で行うもの。ここが済んでいないと、
submit ジョブは提出の段階で止まる（アップロードまでは進む）。

| 項目 | 場所 | 内容 |
|---|---|---|
| アプリ情報 | アプリ → 一般 → App 情報 | 名前（日本語は「サイフログ」で登録済み。英語の名前の案は [`app-store/metadata.en.md`](app-store/metadata.en.md)）、サブタイトル、カテゴリ（プライマリはファイナンス。セカンダリの案も）、コンテンツ配信権。文は [`app-store/metadata.ja.md`](app-store/metadata.ja.md) と [`app-store/metadata.en.md`](app-store/metadata.en.md) |
| 年齢制限 | App 情報 → 年齢制限 | 質問への回答の案と結果（4+）は [`app-store/age-rating.md`](app-store/age-rating.md) |
| 価格と配信状況 | 価格および配信状況 | 無料。配信する国と地域。**Apple Silicon 搭載の Mac と Apple Vision Pro での配信をオフにする**（iPhone 向けのアプリは、既定のままだとこれらでも配信される。README の「Mac と Apple Vision Pro では配信しません」と揃えるため）。**iPad は外せない**（iPhone 専用のアプリも iPad の App Store で配信され、iPhone 版が拡大して動く） |
| App のプライバシー | App のプライバシー | プライバシーポリシーの URL（`https://github.com/iam74k4/SaifuLog-Apple/blob/main/PRIVACY.md`。草案の注記を外して main へ入れてから。下の「初回リリース」の 4）と、「データの収集なし」の回答。回答の案と機能ごとの根拠（購入・声・iCloud なども）は [`app-store/privacy-answers.md`](app-store/privacy-answers.md)（方針は `docs/design.md` §11） |
| スクリーンショット | バージョン → iPhone | **6.9 インチ**（1320 × 2868）が必須。小さい画面の分は自動で縮小される。`./scripts/app-store-screenshots.sh` で、撮影用のデモ（DEBUG のビルドだけにある架空の記録。診断のボタンなど開発用の表示は出さない）を日本語と英語で撮り、`docs/app-store/screenshots/` に置いてある。使うのは `01`〜`06`（`07`・`08` は課金アイテムの審査用で、価格が写るのでストアには載せない）。作り方と確かめることは [`app-store/README.md`](app-store/README.md) |
| 説明文など | バージョン | 説明、プロモーション用テキスト、キーワード、**サポート URL（必須）**、著作権。日本語と英語の文と文字数は [`app-store/metadata.ja.md`](app-store/metadata.ja.md)・[`app-store/metadata.en.md`](app-store/metadata.en.md)。サポート URL のページは [`support.md`](support.md)（main に入るのは初めてのリリースのとき） |
| App Review に関する情報 | バージョン → App Review に関する情報 | 連絡先（App Store Connect にだけ入れる）と審査メモ。審査メモの案（ログイン不要・課金アイテムの試し方・AI が Apple Intelligence 非対応の端末では辞書で動くこと・マイクとカメラの用途・iCloud 同期は任意で既定オフ・データを開発者に送らないこと）は [`app-store/review-notes.md`](app-store/review-notes.md)。審査は iPad で行われることもあるので、提出の前に iPad のシミュレータ（iPhone 版の互換モード）でも一通り動くことを確かめる |
| 輸出コンプライアンス | （Info.plist で回答） | `project.yml` で `ITSAppUsesNonExemptEncryption = NO` を入れている。未回答のビルドだと `asc.py wait-build` が止まる |
| EU のトレーダー申告 | ビジネス | EU で配信するには、トレーダーかどうかの申告が要る。トレーダーの場合は住所などが EU のストアに表示される |
| 契約・税金・口座 | ビジネス | 無料アプリだけなら不要。プレミアム（App 内課金）を出す前に有料 App 契約（Paid Apps）と口座・税の情報が要る。済んでいないと、アプリの中で商品を読めず、⑨ に「価格を読み込めませんでした」と出る |
| App 内課金 | 収益化 → App 内課金 | プレミアムと 14 日間の体験の 2 つ（下の「[8. App 内課金（プレミアム）を審査に出す](#8-app-内課金プレミアムを審査に出す)」） |

### 6. ブランチと保護ルール

`develop` がまだ無ければ、`main` から作る。

```bash
git checkout main && git pull
git checkout -b develop
git push -u origin develop
```

#### 既定のブランチ

**既定のブランチは `develop` にする**（2026-09-29 に `main` から替えた）。GitHub は手動実行（workflow_dispatch）を、
既定ブランチにワークフローのファイルがあるときにしか受け付けない。`main` を既定にしたままだと、初めてのリリースで
`main` に入るまで release.yml が無く、develop からの `mode=testflight`（TestFlight の社内テスト）も
`mode=export`（署名つきアーカイブの確認）も走らせられない（`workflow release.yml not found on the default branch`）。

その代わりに受け入れていること:
- tag-release.yml の cron は既定ブランチにある定義で動くので、まだ main へ入れていない（リリースを通っていない）
  develop の tag-release.yml が、App Store Connect の鍵を持って 3 時間おきに動く（Environment `release` は
  develop からの実行も許す）。守りは develop の Ruleset（直接 push できず、PR と `build` が必須。承認は 0 人）だけに
  なるので、`.github/workflows/` を変える PR は中身を見てからマージする。判定に読むのは常に main の中身
  （`ref: main`）で、main にまだリリースの中身が無いうちは何もせずに終わる。
- PR の base は既定で develop になる。main へは release の PR（develop → main）だけを出す。

**tag-release は、最初のリリースまで止めてある。** 所有者の判断で、2026-09-30 に Actions → tag-release → 「…」→
**Disable workflow** で無効にした。main にまだリリースの中身が無いうちは、動いても何もせずに終わるだけで、止めても失うものが
無い。そこで、上のとおり develop の定義が App Store Connect の鍵を持って 3 時間おきに動くのを、最初のリリースまでは止めておく。無効の間は cron で
動かず、手動実行（Run workflow）もできない（GitHub は無効にしたワークフローを手動でも走らせない）。

- **初めて main へマージするときに有効に戻す**（Actions → tag-release → **Enable workflow**。「[初回リリース（0.1.0）の進め方](#初回リリース010の進め方)」の 2）。
  戻し忘れると、審査を通って配信が始まっても、タグ `v<version>` と GitHub Release が作られない
- 戻し忘れたまま配信が始まったときは、有効に戻してから Actions → tag-release → Run workflow で手動実行する（`sha` は空でよい。
  配信されたビルドから、タグを打つコミットを割り出す）
- 有効に戻したかは、Actions → tag-release を開いて Enable workflow のボタンが出ていないことで確かめる。`gh workflow list --all` でも、
  状態が `active`（無効なら `disabled_manually`）と出る

#### 保護ルール（Ruleset）

main と develop の保護は **Ruleset** で行う（Settings → Rules → Rulesets →
New ruleset → New branch ruleset）。**main 用と develop 用の 2 つに分ける。** 許すマージの方法
（Allowed merge methods）は Ruleset ごとの設定で、main だけを merge に絞るため。

| 設定 | `main` の Ruleset | `develop` の Ruleset | 理由 |
|---|---|---|---|
| Ruleset name | `main` | `develop` | |
| Enforcement status | Active | Active | |
| Target branches | Include by pattern → `main` | Include by pattern → `develop` | |
| Restrict deletions | オン | オン | develop → main をマージしたときの「ブランチの自動削除」や手違いで、統合ブランチが消えないように |
| Require a pull request before merging | オン（Required approvals は **0**） | オン（Required approvals は **0**） | 直接 push を止める。1 人で開発していると自分の PR は承認できないので、承認数は 0 にする |
| └ Allowed merge methods | **Merge だけ** | Merge と Squash | develop → main を squash や rebase で入れると、main にだけあるコミットができて develop と履歴が分かれ、次のリリースから毎回 `Config/Base.xcconfig` と `CHANGELOG.md` で衝突する。作業ブランチ → develop は squash でよい |
| Require status checks to pass | オン → Add checks → **`build`** | オン → Add checks → **`build`** | CI の通っていない変更を入れない。`build` は build.yml のジョブ名 |
| Block force pushes | オン | オン | 履歴の書き換えを止める |
| Bypass list | 空 | 空 | 抜け道を作らない（緊急時は一時的に Ruleset を Disabled にする） |

- `build` は、build.yml が一度でも走らないと候補に出てこない。先にこのブランチを push して
  PR を作り、build が走ってから Ruleset を作る。
- 「Require branches to be up to date before merging」は付けなくてよい。develop → main は
  もともと最新で、作業ブランチ → develop で毎回の取り込みを強いる手間の方が大きい。
- Settings → General → Pull Requests で **Allow merge commits**（develop → main に使う）と
  **Allow squash merging**（作業ブランチ → develop に使う）を有効にしておく。どちらかを切ると、
  Ruleset で許していても選べなくなる。

### 7. リポジトリのセキュリティの設定

| 設定 | 場所 | 理由 |
|---|---|---|
| Private vulnerability reporting を有効にする | Settings → Code security → Private vulnerability reporting | 脆弱性やプライバシーの問題を非公開で受け取る窓口（`SECURITY.md`、`PRIVACY.md` のお問い合わせ）。公開リポジトリで Admin 権限の鍵を CI に持たせているので、Issues に書かれる前に受け取れるようにする |
| actions の SHA での固定を必須にする | Settings → Actions → General → Actions permissions の **Require actions to be pinned to a full-length commit SHA** | ワークフローの `uses:` はすべてコミットの SHA で固定してある（版はコメント）。タグの付け替えで中身が差し替わっても、鍵を持つジョブで知らないコードが動かないようにする。設定で必須にすると、タグで書いた `uses:` が紛れ込んだときに止まる |
| 使える actions を GitHub 製に限る | 同じ画面で **Allow iam74k4, and select non-iam74k4, actions and reusable workflows** を選び、**Allow actions created by GitHub** だけにチェックを入れる | 使っているのは `actions/checkout` と `actions/setup-python` だけ。ほかを足すときは、ここと一緒に見直す |

### 8. App 内課金（プレミアム）を審査に出す

プレミアム（⑨。`docs/design.md` §6・§9）の課金アイテムは App Store Connect に登録済み。**製品 ID は変えない**（アプリのコアの
`PremiumProduct` と `Config/SaifuLog.storekit` に同じ値を書いている。変えると買った人がプレミアムを使えなくなる）。

| 製品 ID | 種類 | 価格 | ファミリー共有 | 表示名（ja / en） |
|---|---|---|---|---|
| `com.iam74k4.SaifuLog.premium` | 非消耗型 | ¥1,800（日本基準） | オン | サイフログ プレミアム / SaifuLog Premium |
| `com.iam74k4.SaifuLog.trial14` | 非消耗型 | ¥0 | オフ | 14日間の無料体験 / 14-day Trial |

App ID の In-App Purchase の Capability は、明示的な App ID なら最初から有効（エンタイトルメントのファイルに足すものは無い）。

**App 内課金を初めて出すときは、アプリのバージョンと一緒に審査に出す**（App Store Connect のバージョンのページの
「App 内課金とサブスクリプション」で 2 つを選んでから、バージョンを審査に提出する。課金アイテムだけを先に出すことはできない）。
その前に、課金アイテムごとに次を入れて「提出準備完了」にしておく。

**カテゴリ別の予算の進み（使った額との比べ）を画面に出すまで、App 内課金を審査に出さない（この決め事は見直し中。所有者が決めるまでは出さない）。**
決めたときの理由は、買って使えるプレミアムの機能が予算の画面でカテゴリ別の予算の額を決める欄だけで、買っても目に見えて変わるものが
無い App 内課金として、審査（ガイドライン 2.1・3.1.1）で差し戻されるおそれがあることだった。家計への質問を出したので、いまは
買うと質問の回数の制限（無料は月 10 回）がなくなり、目に見えて変わる（下の審査メモの例もそう書いている）。一方で、カテゴリ別の
予算の額はまだどの画面の数字にも使っていない（`docs/design.md` §6-1・§13）ので、その欄だけでは差し戻されるおそれが残る。
進みの出し場所（§13 の「カテゴリ別の予算の出し方」）を決めて作ってから出すか、質問の回数を理由に先に出すかを決め、下の審査メモも
それに合わせて書き直して出す。

1. **審査用のスクリーンショット（課金アイテムごとに 1 枚）: ⑨ プレミアムのシート。** `./scripts/app-store-screenshots.sh` が撮る
   `docs/app-store/screenshots/<言語>/07-premium.png`（価格・「買い切り・ファミリー共有対応」・購入のボタン。プレミアムの分）と
   `08-trial.png`（「14日間の無料体験」の説明と「14日間の無料体験を始める」。体験の説明が、期間・終わっても課金されないこと・
   終わった後に使えなくなるものを示していることが伝わるように。体験の分）を使う。価格は日本の App Store の表示（¥1,800）で写る
   （撮影用のデモは App Store の商品を読まずに、日本の価格の表示を出す。[`app-store/README.md`](app-store/README.md)）。
2. **審査メモ（課金アイテムごと）。** 英語の文と日本語の対訳は [`app-store/review-notes.md`](app-store/review-notes.md) の
   「課金アイテムの審査メモ」。アプリのバージョンの「App Review に関する情報」の審査メモ（ログイン不要・プレミアムの入口・
   体験は 0 円で始められること・マイクの用途など）も同じファイルにある。上のとおり出すかは見直し中なので、決め事を変えたら
   審査メモも合わせて書き直してから出す。
3. 表示名と説明（ja と en）。アプリの中の表示（`Config/SaifuLog.storekit` のローカライズ）と食い違わないようにする。体験の英語の
   表示名は、ガイドライン 3.1.1 の名前の決まり（「XX-day Trial」）に合わせた「14-day Trial」（`app-store/review-notes.md`）。
   App Store Connect の英語のローカライズを直すのは所有者の作業（[`app-store/README.md`](app-store/README.md) の「App Store Connect で所有者がすること」）。
4. 審査の前に、Sandbox のテスター（ユーザとアクセス → Sandbox）で実機に TestFlight のビルドを入れ、購入・体験・復元を一通り試す
   （`docs/design.md` §15 の「これから」）。

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
   - `make check-version` で一致を確かめる（CI でも検査される）。PR の前に `make ci` を通すと、
     CI（`build`）と同じ 8 つを手元で確かめられる
   - 実機での確認は、手元の Xcode から入れるか、develop を `mode=testflight` で TestFlight の社内テストへ送って行う
     （下の「[TestFlight で実機に入れる（社内テスト）](#testflight-で実機に入れる社内テスト)」）
2. **PR: develop → main を作り、build が通ったら「Create a merge commit」でマージする**
   （main の Ruleset は merge しか許さないので、ほかの方法は選べない）

あとは待つ。目安は、アップロードまで 15〜30 分、App Store Connect の処理に 10 分〜1 時間、
審査は多くが 1 日以内（混んでいると数日）。審査に通れば配信が始まり、3 時間以内に tag-release.yml が
配信されたビルドを作ったコミットに `v<version>` のタグと GitHub Release を作る。

### 初回リリース（0.1.0）の進め方

初回だけは、署名の経路と Web の設定がまだ一度も通っていないので、段階を分ける。

1. 「一度だけの準備」の 1〜4、6、7 を済ませる。**リポジトリ変数 `ASC_AUTO_SUBMIT` を
   `false` にしておく**（最初のマージではアップロードだけにする）
   - アプリアイコン（財布のライト・ダーク・色付きの 3 枚。1024 × 1024 の PNG）が
     `AppIcon.appiconset` に入っていることを確かめる。App Store Connect はアイコンの無いビルドを
     受け付けない。消えていれば build.yml の `make archive` が止める
     （下の「[アプリアイコン](#アプリアイコンappiconappiconset)」）
2. **tag-release を有効に戻してから**、develop → main をマージする。release.yml の upload が走り、ビルドが App Store Connect に届く
   - マージの直前に Actions → tag-release → **Enable workflow** を押す（最初のリリースまで無効にしてある。「[既定のブランチ](#既定のブランチ)」）。
     **戻し忘れると、配信が始まってもタグと GitHub Release が作られない。** マージの前に有効にしても、main にリリースの中身が
     入るまでは何もせずに終わり、入った後も配信中の版が無いうちは何もしない（下の「2〜7 の間も」）ので、先に戻してかまわない
   - アップロードの前の「送る前に書き出して確かめる（送信しない）」で、書き出したアプリに
     エンタイトルメント（データ保護の `default-data-protection`、iCloud のサービスとコンテナ、`aps-environment`）が
     載っているかと、値（`aps-environment` が `production` に替わっているかなど）を照合する。
     アーカイブは開発用の証明書で署名してあるので、合っていれば `OK: … のキーはすべて載っています` と
     `OK: エンタイトルメントの値はすべて期待どおりです。` が出る。
     ただしこの経路はまだ一度も通していないので、照合は警告（run の Annotations）を出すだけで、
     抜けていてもアップロードは続ける。警告が出たビルドは、保存先のデータ保護が既定のクラス
     （初回のロック解除後は常に復号）のままになる
   - 証明書の取り込み、アーカイブの署名、export（署名）のどこかで落ちたら、Actions → release →
     **Run workflow** → `mode=export` で、何も送らずに署名の経路とエンタイトルメントの照合だけを
     繰り返し試せる（こちらの照合は、抜けていれば止まる）
   - 照合の警告が出たビルドは審査に出さない。審査の前に、6 で照合が通ることを確かめる
3. TestFlight に処理済みのビルドが現れたら、内部テスターとして実機に入れて確かめる
4. **`PRIVACY.md` を確定させる。** 冒頭の「草案 / Draft」の注記を外し、施行日（Effective date）に
   日付を入れ、最終更新日も揃える。内容が実装と合っているかもここで見直す。作業ブランチ → develop →
   main とマージする（`ASC_AUTO_SUBMIT` が `false` のままなので、main へのマージではアップロード
   だけが走る）。`CLAUDE.md` の「ドキュメント」にある `PRIVACY.md` の説明（草案）も一緒に直す。
   審査に出すポリシーの URL が「Draft」と書かれたページのままにならないようにするため
5. 「一度だけの準備」の 5（Web の設定）と 8（App 内課金の審査用のスクリーンショットと審査メモ）を済ませる。
   入れる文とスクリーンショットは [`app-store/`](app-store/README.md) にある（入れる前に、中身がいまの実装と合っているかを見直し、
   スクリーンショットは撮り直す）。プライバシーポリシーの URL には、4 で確定させた main の `PRIVACY.md` を、サポート URL には
   main の `docs/support.md` を入れる（どちらも main に入ってから開けることを確かめる）
   - **CloudKit のスキーマを Production に出す**（「[Capability（iCloud など）を足すとき](#capabilityicloud-などを足すとき)」の
     「CloudKit のスキーマ」）。出さないと、配信したアプリで iCloud 同期が働かない。出す前に、記録と予算の項目の型が暗号化
     （Encrypted …）になっているかを確かめる（同じ節の 2。`docs/design.md` §5-3。出した後は変えられない）
6. **審査に出す前に、エンタイトルメントの照合が通ることを確かめる。** アップロード前の照合はまだ警告だけで、
   データ保護が抜けていても送ってしまう。抜けたビルドを審査に出さないための関門なので、ここが済むまで 7 に進まない
   - main で Actions → release → Run workflow → `mode=export` を走らせ、「書き出すだけ（送信しない）」が緑で
     `OK: SaifuLog/SaifuLog.entitlements のキーはすべて載っています` と `OK: エンタイトルメントの値はすべて期待どおりです。` が
     出ることを確かめる（こちらの照合は、抜けていれば止まる）
   - 通ったら、「[照合を止める扱いに戻す](#照合を止める扱いに戻す所有者が確かめてから)」の 3 の PR
     （`RELEASE_ENTITLEMENTS_CHECK=warn` を外す）を develop → main とマージする（`ASC_AUTO_SUBMIT` が `false`
     なので、アップロードだけが走る）。7 の `mode=submit` はアーカイブからやり直すので、こうしておけば、その実行で
     抜けたときにアップロードの前に止まる
   - エンタイトルメントの照合の警告（run の Annotations）が出たビルドは審査に出さない。原因を直して送り直し、
     照合が通ってから出す。7 で Web からビルドを選ぶときは、そのビルドを送った run の「送る前に書き出して確かめる
     （送信しない）」に `OK: …` の行があるものを選ぶ
7. 審査に出す。**`mode=submit` で出す。**
   - Actions → release → Run workflow → `mode=submit`（アーカイブからやり直し、
     新しいビルド番号で送って提出する）。初回の版は App Store Connect が自動で作る
     「1.0（提出準備中）」で、submit ジョブがこれを `0.1.0`（`MARKETING_VERSION`）に書き換えて使う
   - App Store Connect の Web から出すときは、**先にバージョン番号を 1.0 から 0.1.0
     （`MARKETING_VERSION` と同じ値）に書き換えてから**、ビルドを選んで「審査に提出」を押す。
     1.0 のままだと 0.1.0 のビルドを選べないか、1.0 として配信されてしまう。後者だと tag-release.yml が
     版の食い違い（1.0 と 0.1.0）で赤く止まり、タグと Release が作られない
8. `ASC_AUTO_SUBMIT` を消す（以降はマージで審査まで進む）

2〜7 の間も tag-release.yml は 3 時間おきに走る（2 で有効に戻したので）。App Store Connect に配信中の版がまだ無いので、
「配信中の版はまだありません」として何もせずに終わる（失敗にはならない）。審査を通って配信が始まったら、3 時間以内に
タグ `v0.1.0` と GitHub Release ができていることを確かめる（できていなければ、tag-release が有効になっているかを見る）。

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
| `Environment「release」の Secrets ... が足りません` | 「一度だけの準備」の 3。証明書の 2 つ（`APPLE_DEV_CERT_P12_*`）なら「[署名ありのアーカイブ](#署名ありのアーカイブ)」 |
| `.p12 を取り込めません` | `APPLE_DEV_CERT_P12_PASSWORD` が書き出したときのパスワードと違う、または .p12 が macOS の読めない形式（openssl で作ったものなど）。キーチェーンアクセスか Xcode で書き出し直す |
| `.p12 に Apple Development の証明書と秘密鍵が入っていません` | 別の種類の証明書（Apple Distribution など）を書き出したか、秘密鍵を含めずに書き出した。「[署名ありのアーカイブ](#署名ありのアーカイブ)」の手順で書き出し直す |
| `証明書のチーム（…）が Config/Base.xcconfig の DEVELOPMENT_TEAM（…）と違います` | 別のチームの証明書を書き出した。`NL9ZXK2SGR` のチームの Apple Development の証明書にする |
| `Apple Development の証明書の期限が切れています`（30 日前からは期限が近いという警告） | 期限は 1 年。「[年に一度の更新](#年に一度の更新)」 |
| アーカイブで `Your team has no devices from which to generate a provisioning profile` | チームに端末が 1 台も登録されていない。開発用のプロファイルは登録端末が無いと作れない。「一度だけの準備」の 1 |
| ジョブが始まらずに Environment の保護ルールで止まる | Environment `release` の配備ブランチ（`main` と `develop`）以外から手動実行した（意図どおり）。develop からの `mode=testflight` で止まるなら、配備ブランチに `develop` を足していない（「一度だけの準備」の 3） |
| `mode=submit は main からだけ走らせられます`（`mode=upload` も同じ） | develop などから、App Store へ出せる形で送る mode を選んだ。develop のビルドを実機で試すなら `mode=testflight` にする |
| `v<version> は配信済み（タグあり）で、Apple はこの版の新しいビルドを TestFlight にも受け付けません`（承認済みのときも同じ） | 承認された版は閉じ、TestFlight 用のビルドも送れない。作業ブランチで `MARKETING_VERSION` と CHANGELOG の先頭の見出しを次の版に上げて develop へ入れてから、`mode=testflight` を走らせ直す |
| `このアーカイブのアプリには診断画面（社内テスト用）が入っています` | `INTERNAL_BUILD=NO`（App Store へ出すビルド）のアーカイブに診断画面が入った。`INTERNAL_DIAGNOSTICS` を `project.yml` や `Config/*.xcconfig` で足していないか、診断画面のコードが `#if DEBUG \|\| INTERNAL_DIAGNOSTICS` の外に出ていないかを確かめる |
| `INTERNAL_BUILD=YES ですが、アーカイブのアプリに診断画面の印（…）が見つかりません` | `mode=testflight` のアーカイブに診断画面が入らなかった。`project.yml` の `SAIFULOG_INTERNAL_BUILD` から `SWIFT_ACTIVE_COMPILATION_CONDITIONS` への組み立てと、`SaifuLog/Diagnostics/DiagnosticsReport.swift` の `buildMarker` が `release.mk` の `RELEASE_INTERNAL_MARKER` と同じ値かを確かめる |
| `このアーカイブのアプリでは家計の共有（実機で確かめる前の機能）が有効になっています` / `App Store へ出すビルドのアプリの Info.plist に CKSharingSupported があります` | `INTERNAL_BUILD=NO` のアーカイブで家族との家計の共有が有効になった。`SaifuLog/Household/HouseholdSharing.swift` の `enabledMarker` が `#if DEBUG \|\| INTERNAL_DIAGNOSTICS` の外で値を持っていないか、`project.yml` の `SAIFULOG_HOUSEHOLD_SHARING` と `INFOPLIST_FILE` の選び方が変わっていないかを確かめる |
| `INTERNAL_BUILD=YES ですが、アーカイブのアプリに家計の共有の印（…）が見つかりません` / `CKSharingSupported が true ではありません` | `mode=testflight` のアーカイブで家計の共有が有効にならなかった。`enabledMarker` が `release.mk` の `RELEASE_HOUSEHOLD_MARKER` と同じ値か、`HouseholdHost.start` が印をログに書いているか、`SAIFULOG_HOUSEHOLD_SHARING` が `SAIFULOG_INTERNAL_BUILD` を引いているかを確かめる |
| `このアーカイブのアプリには撮影用のデモ（DEBUG のビルドだけの仕組み）が入っています` | Release のアーカイブに撮影用のデモが入った。`SaifuLog/ScreenshotDemo/` と、それを呼ぶ場所（`SaifuLogApp`・`AppRootView`・`HomeView`・`PurchaseManager`・`PremiumSheet`）が `#if DEBUG` の外に出ていないか、Release の構成に `DEBUG` の条件を足していないかを確かめる |
| `UIBackgroundModes に remote-notification がありません` | Info.plist を 2 つ（`SaifuLog/Info.plist`・`SaifuLog/Info-HouseholdSharing.plist`）に分けたうちの片方から消えた。両方に同じ中身（`CKSharingSupported` のほか）を保つ |
| 「依存を入れる」などの `pip install` が `--require-hashes` や `--only-binary` のエラーで止まる | `scripts/requirements.txt` のハッシュと合わない、またはランナーの Python の版に合う wheel が無い。手で書き換えず、`scripts/requirements.in` の先頭にある手順（`pip-compile --generate-hashes --strip-extras`）で作り直す。Python の版（`setup-python` の `3.12`）を変えたときも作り直す |
| export で `Cloud signing permission error` | API キーのロールが Admin でない |
| export でプロファイルが作れない（アプリ ID が無い） | Bundle ID `com.iam74k4.SaifuLog` が未登録。「一度だけの準備」の 1 |
| アーカイブか export で、プロファイルに `com.apple.developer.default-data-protection` が無いと言われる | Bundle ID の設定で Data Protection（Complete Protection）がオンになっていない。「一度だけの準備」の 1 |
| 「送る前に書き出して確かめる」に `書き出したアプリに、… のエンタイトルメントが載っていません` の警告が出る（`mode=export` の実行ではこのエラーで止まる） | アーカイブにエンタイトルメントが焼かれていない。署名なし（`ARCHIVE_SIGNING=NO`）のアーカイブだとこうなる。「アーカイブを作る」が `ARCHIVE_SIGNING=YES` で走ったか、ログの署名の行を確かめる（「[署名ありのアーカイブ](#署名ありのアーカイブ)」）。ふだんのリリースは照合が警告だけなので、そのまま送られ、そのビルドにはエンタイトルメントが載っていない |
| `v<version> は承認済み（…）で、タグが付くのを待っています` の notice が出て、アップロードがスキップされる | 承認から tag-release がタグを打つまでの間に、版を上げずに main へマージした。その版にはもうビルドを送れないので、何も送らずに終えている（失敗ではない）。待てば tag-release がタグを打つ。急ぐなら Actions → tag-release → Run workflow で手動実行する。マージした変更を出すには、版を上げて develop → main をやり直す |
| アップロードでビルド番号の重複を言われる | 手元から大きい番号で送った、または release.yml の名前を変えた。`BUILD_NUMBER_OFFSET` で底上げする |
| `BUILD_NUMBER_OFFSET は 0 以上の整数（先頭に 0 を付けない）にしてください` | リポジトリ変数 `BUILD_NUMBER_OFFSET` に `010` のような値が入っている。先頭の 0 を外す |
| `make upload は BUILD_NUMBER を読みません` | 手元で `make upload BUILD_NUMBER=…` とした。ビルド番号はアーカイブに焼かれている。`make archive BUILD_NUMBER=…` で作り直してから `make upload` する |
| `make archive` が `アプリにアイコンが入っていません` で止まる／アップロードでアイコンが無い（`CFBundleIconName` や `Missing required icon`）と言われる | `AppIcon.appiconset` に画像が無いか、`Contents.json` の `filename` で参照されていない。1024 × 1024 の PNG を置いて参照する（下の「[アプリアイコン](#アプリアイコンappiconappiconset)」） |
| アップロードで `Invalid large app icon`（透過・アルファチャンネル）と言われる | 1024 × 1024 の PNG に透過（アルファチャンネル）がある。透過なしで書き出し直す。`sips -g hasAlpha <PNG>` が `no` になればよい |
| `輸出コンプライアンス（暗号の使用）が未回答です` | Info.plist に `ITSAppUsesNonExemptEncryption` が入っていない。`project.yml` を直すか、TestFlight でそのビルドに回答してから submit ジョブを再実行する |
| `秒待ちましたが処理が終わりませんでした` | App Store Connect の処理が遅い。処理が終わったのを確かめてから、失敗した submit ジョブだけを **Re-run failed jobs** で再実行する（アップロードはやり直さない） |
| `... のため、ビルドを差し替えられません` | 審査中の版があるのに、バージョンを上げずに main へマージした。差し替えたいなら Web で審査から取り下げてから再実行、不要ならそのままでよい |
| `前の版 X が … のため、Y の版を作れません` | 前の版の審査中（または配信待ちの間）に、版を上げて main へマージした。App Store Connect は進行中の版を 1 つしか持てない。前の版の配信が始まるか、リジェクトされる（取り下げる）のを待ってから、失敗した submit ジョブだけを **Re-run failed jobs** で再実行する。アップロードはやり直さなくてよい。前の版のタグと Release は tag-release が付ける |
| 審査への追加で 409 が返り、Apple の理由（`errors[].detail` と `associatedErrors`）が並んで止まる | 提出に必要なものが足りない（スクリーンショット、説明文、サポート URL、年齢制限、App のプライバシーなど）。ログに並んだ理由を App Store Connect の Web で直してから、失敗した submit ジョブを **Re-run failed jobs** で再実行する。この版が既に入れ物に入っていただけのとき（前回の実行が提出の手前で落ちたなど）は、`asc.py` が入れ物の中身を確かめて先へ進むので、止まらない |
| `既に配信済み ... MARKETING_VERSION を上げてください` | バージョンの上げ忘れ |
| 配信が始まって 3 時間たっても、タグ `v<version>` も GitHub Release も無い（tag-release の実行も無い） | tag-release が無効のまま（最初のリリースまで無効にしてある）。Actions → tag-release → Enable workflow で有効に戻し、Run workflow で手動実行する（「[既定のブランチ](#既定のブランチ)」）。60 日間動きの無いリポジトリで GitHub が止めたときも同じ（「[cron の注意](#cron-の注意)」） |
| タグ `v<version>` はあるのに GitHub Release が無い | tag-release.yml がタグの push の後、Release の作成で落ちた。次の実行（3 時間以内。急ぐなら手動実行）で Release だけが作られる。タグは打ち直されない |
| tag-release が `release.yml の実行を逆算できません` / `実行 #N が見つかりません` / `コミット … の版は …で、v… と合いません` で止まる | 配信されたビルドから、タグを打つコミットを割り出せなかった（手元から送ったビルド、配信待ちの版があるうちに `BUILD_NUMBER_OFFSET` を変えた、App Store Connect の版番号を `MARKETING_VERSION` に揃えずに提出した、など）。配信されたビルドを作ったコミットを確かめ、Actions → tag-release → Run workflow の `sha` にそのコミットを入れて手動実行する（下の「[`tag-release.yml`](#tag-releaseyml)」） |

---

## TestFlight で実機に入れる（社内テスト）

main へマージする前の develop のビルドを、TestFlight で自分の iPhone に入れて確かめる。release.yml を `mode=testflight`
で手動実行すると、診断画面入りのビルドを TestFlight の**社内テスト専用**（`testFlightInternalTestingOnly`）で送る。
審査には出ない（submit ジョブは走らず、社内テスト専用のビルドは Apple が審査にも外部テストにも出させない）。

### 一度だけの準備（TestFlight）

1. 「[一度だけの準備](#一度だけの準備)」の 1〜3・6・7 を済ませる（Bundle ID とアプリレコード、API キー、証明書の Secrets、保護ルール）
2. **Environment `release` の配備ブランチに `develop` を足す**（所有者の作業）。Settings → Environments → `release` →
   Deployment branches and tags → Add deployment branch or tag rule → `develop`。足したあと何で安全を保つか（と、その限界）は「一度だけの準備」の 3
3. App Store Connect → アプリ → **TestFlight** → 内部テストの **+** でグループを作り（名前は任意。例: 「所有者」）、
   テスターに自分を足す
   - 内部テスターになれるのは、App Store Connect のチームのユーザ（最大 100 人）。Apple Developer Program の所有者は、そのまま足せる
   - グループの自動配信をオンにしておくと、処理が済んだビルドが自動でテスターに届く
4. iPhone に App Store から **TestFlight** アプリを入れ、App Store Connect と同じ Apple アカウントでサインインする

### 毎回の手順（TestFlight）

1. Actions → **release** → **Run workflow** → Use workflow from: **develop**、mode: **testflight** → Run workflow
2. アップロードまで 15〜30 分。run の Summary に版とビルド番号が出る。そのあと App Store Connect の処理に 10 分〜1 時間
   （輸出コンプライアンスの質問は、Info.plist の `ITSAppUsesNonExemptEncryption = NO` で答えてあるので出ない）
3. TestFlight アプリに届いたビルドを入れる。自動配信をオフにしたときは、App Store Connect の TestFlight → 内部テストの
   グループにビルドを足す
4. ホームの帯の右上の小さなアイコン（聴診器。VoiceOver では「診断」）で診断画面を開く。「まとめてコピー」で、記録の中身
   （金額・メモなど）を含まない文として写せる

### 診断画面で見るもの

| 項目 | 見ること |
|---|---|
| 保存先（`default.store`・`-wal`・`-shm`）の保護クラス | 3 つとも `NSFileProtectionComplete`（データ保護が効いている。`docs/design.md` §5-4）。`default.store` は保存先を開いた時点（ホームが出る前）に作られるので、これが `missing` なら異常（診断画面の見ている場所と実際の保存先が食い違っているなど。記録を入れても直らない）。`-wal` / `-shm` は保存先を開いている間はふつうある（SQLite の WAL）。`missing` なら記録を 1 件入れてから再読み込みし、それでも `missing` なら報告に添える |
| 保護されたデータを読めるか | 画面を見ている間は `true` |
| 端末内 AI（Foundation Models） | `available` か、使えない理由（`deviceNotEligible`・`appleIntelligenceNotEnabled`・`modelNotReady`）。日本語に対応しているか。iOS 27 なら画像を入力できるか |
| 音声の書き起こし（SpeechTranscriber） | 使えるか、日本語のモデルが入っているか、声の入力が使っている経路（`speechTranscriber` / `dictationTranscriber` / `none`）とそのモデルの状態（`installed` / `needsReservation` / `needsDownload` / `downloading`）。`checking` は端末への問い合わせがまだ返っていないところ（ほかの行はそれを待たずに出る）。再読み込みしても `checking` のままなら、問い合わせが返らない端末として報告に添える |
| 版・ビルド番号・OS・機種 | 不具合を報告するときに添える |
| 記録の件数・予算の行数 | 中身ではなく数だけ |
| iCloud | アカウントの状態（`available` / `noAccount` / `restricted` / `temporarilyUnavailable` / `couldNotDetermine`。`checking` は問い合わせがまだ返っていないところ）、いま開いている保存先の同期（`none` か `private(iCloud.com.iam74k4.SaifuLog)`）、設定の「iCloud で同期」（`true` / `false`）。設定が `true` なのに `none` なら、iCloud と同期する保存先を開けずに端末の中だけへ戻したところ（そのときは理由のアラートが出ている）。同期を試すときの手順は `docs/design.md` §15 |

### 知っておくこと

- ビルド番号は、main へのマージと同じ release.yml の実行番号から付く（「[ビルド番号の決め方](#ビルド番号の決め方)」）。
  testflight の実行の分だけ番号が飛ぶが、同じ版の中で重ならず、いつも前より大きい
- タグ（`v<version>`）があってもスキップしない（同じ版で何度送ってもよい）。ただし配信済みや承認済みの版には、Apple が
  TestFlight 用のビルドも受け付けない。そのときはアーカイブの前に止まるので、作業ブランチで `MARKETING_VERSION` と
  CHANGELOG の先頭の見出しを次の版に上げて develop へ入れてから走らせる
- 社内テスト専用のビルドは、あとから審査や外部テストに回せない。審査に出すビルドは、これまでどおり main へのマージで作る
- TestFlight のビルドは 90 日で期限が切れる
- TestFlight のビルドの iCloud 同期は、CloudKit の Production の環境を使う。スキーマを Production に出す前は同期できない
  （「[CloudKit のスキーマ](#cloudkit-のスキーマ所有者の作業)」）
- 診断画面と家族・パートナーとの家計の共有は、社内テスト用のビルドと DEBUG のビルド（手元の Xcode から入れたもの）にだけある。
  App Store へ出すビルドには入らず（家計の共有はコードは入るが無効）、入っていれば release.mk が止める（「[`release.mk`](#releasemk)」）。
  家計の共有を試すときは `docs/design.md` §15 の 15 の手順で、先に家計の記録の型を CloudKit のスキーマに出す。どちらのビルドでもホームの帯に診断のボタンが
  出るので、App Store 用のスクリーンショットはこれらのビルドの画面では撮らず、`./scripts/app-store-screenshots.sh`（撮影用のデモ。診断のボタンを出さない）で撮る（「一度だけの準備」の 5）
- アーカイブは main のリリースと同じく開発用の証明書で署名する（エンタイトルメントが載る）。エンタイトルメントの照合はまだ
  警告だけ（「[照合を止める扱いに戻す](#照合を止める扱いに戻す所有者が確かめてから)」）なので、警告が出たビルドでは保護クラスが
  Complete にならない。診断画面の保護クラスで、そのビルドに効いているかを確かめられる

---

## 中身

### `release.mk`

`Makefile` の末尾で読み込む、提出用のターゲット。手元でも CI でも同じものを使う。

| ターゲット | 何をするか |
|---|---|
| `make version` | いまの `MARKETING_VERSION` を表示する |
| `make check-version` | `MARKETING_VERSION` と CHANGELOG 先頭の見出しの一致を確かめる |
| `make archive` | Release の `.xcarchive` を `build/` に作る。`BUILD_NUMBER=…` でビルド番号を上書き。既定は署名ありで、`ARCHIVE_SIGNING=NO` で署名なし（build.yml と `make ci`）。`ARCHIVE_KEYCHAIN=…` で署名に使うキーチェーンを指定できる（release.yml が一時キーチェーンを渡す）。`INTERNAL_BUILD=YES` で社内テスト用（診断画面入り。release.yml の `mode=testflight` だけが渡す。既定は `NO`）。できたアプリの Info.plist にバージョン・ビルド番号・アイコンが入っているかと、診断画面と家族との家計の共有が `INTERNAL_BUILD` のとおりに入っているか（入っていないか）と、撮影用のデモが入っていないかを確かめる。`BUILD_NUMBER` が `CURRENT_PROJECT_VERSION`（1）と同じ値だと、上書きが届いたかを確かめられないので警告を出す |
| `make export-ipa` | アーカイブから `.ipa` を書き出すだけ。**送信しない。** 署名とエンタイトルメントを表示し、エンタイトルメントのファイル（`RELEASE_ENTITLEMENTS`。いまは自動で見つかる `SaifuLog/SaifuLog.entitlements`）のキーがすべて載っているかと、`RELEASE_ENTITLEMENT_VALUES` の値（データ保護が `NSFileProtectionComplete`、`aps-environment` が `production`、iCloud のサービスが `CloudKit`、コンテナが `iCloud.<Bundle ID>`）になっているかを照合する。抜けや食い違いがあれば止まる（`RELEASE_ENTITLEMENTS_CHECK=warn` なら警告だけ出して続ける）。release.yml はアップロードの前に必ずこれを通す（いまは `warn`）。アーカイブの診断画面の有無が `INTERNAL_BUILD` と合わなければ止まる |
| `make upload` | `Config/ExportOptions.plist` で書き出し、そのまま App Store Connect へ送る。手元の端末では確認を挟む。ビルド番号はアーカイブに焼かれた値で、`BUILD_NUMBER` を渡しても変わらない（アーカイブと違う値なら止まる）。社内テスト用のアーカイブは `INTERNAL_BUILD=YES` で送り、`testFlightInternalTestingOnly` を true にした写し（`build/ExportOptions.upload.plist`）で TestFlight の社内テスト専用になる。アーカイブの診断画面の有無が `INTERNAL_BUILD` と合わなければ、送る前に止まる |

開発用の `make ci`（Makefile）は、build.yml と同じ 8 つ（`make build`・`make check-strings`・`make test`・
`make build-tests`・`make test-app`・`make test-storekit`・`make check-version`・`make archive ARCHIVE_SIGNING=NO BUILD_NUMBER=99999`）を
順に通す。`make check-strings` は、`make build` が書き出した Debug の .stringsdata と String Catalog
（`Localizable.xcstrings`）を突き合わせ、足りないキー・使われていないキー・en の無いキー・ja と en の書式指定子の
不一致があれば止まる（`scripts/check-strings.py`）。

認証は、環境変数 `ASC_API_KEY_ID` / `ASC_API_ISSUER_ID` / `ASC_API_KEY_PATH`（.p8 のパス）が
3 つとも揃っていれば API キー、無ければ Xcode にサインインしているアカウント。
どちらでも `-allowProvisioningUpdates` を付け、プロファイルの用意を Xcode に任せる。

診断画面が入っているかは、アーカイブのアプリの中に `RELEASE_INTERNAL_MARKER`（`SaifuLog/Diagnostics/DiagnosticsReport.swift` の
`buildMarker` と同じ文字列）があるかで見分ける。ビルドの設定だけを見ると、条件をほかの場所で足したときや、診断画面のコードが
`#if DEBUG || INTERNAL_DIAGNOSTICS` の外に出たときに気づけないため。社内テスト用のアーカイブで印が見つからないときも止める
（印を変えて release.mk を直し忘れたときに、「入っていない」の確かめが空振りしないように）。build.yml と `make ci` のアーカイブ
（`INTERNAL_BUILD=NO`）でも、診断画面が入っていないことを毎回確かめている。

家族・パートナーとの家計の共有も同じ仕組みで確かめる（`RELEASE_HOUSEHOLD_CHECK`）。アプリの中に `RELEASE_HOUSEHOLD_MARKER`
（`SaifuLog/Household/HouseholdSharing.swift` の `enabledMarker` と同じ文字列。有効なときに同期を始める処理がログに書くので、最適化で
消えない）があるか、アプリの Info.plist に `CKSharingSupported` があるかを `INTERNAL_BUILD` と照らし合わせ、合わなければ止める。
Info.plist を家計の共有の有無で 2 つに分けたので、どちらのビルドでも `UIBackgroundModes` に remote-notification があるかも見る。

App Store のスクリーンショットを撮るための撮影用のデモ（`SaifuLog/ScreenshotDemo/`。起動引数で架空の記録の画面を開く）も同じ仕組みで
確かめる（`RELEASE_SCREENSHOT_DEMO_CHECK`）。DEBUG のビルドだけのものなので、`INTERNAL_BUILD` によらず、アーカイブのアプリの中に
`RELEASE_SCREENSHOT_DEMO_MARKER`（`SaifuLog/ScreenshotDemo/ScreenshotDemo.swift` の `marker` と同じ文字列。撮る画面を開くときにログに
書くので、Debug のビルドでは消えない）があれば止める。印の値の食い違いで確かめが空振りしないよう、`scripts/app-store-screenshots.sh` が
Debug のアプリに同じ印があることを確かめてから撮る。

build.yml（と `make ci`）はアーカイブを**署名なし**（`ARCHIVE_SIGNING=NO`）で作る。PR ごとに走り、
Environment `release` の Secrets（証明書）を読めないため。組み立ての経路とアーカイブの検査を通すだけなら
署名は要らない。release.yml は**署名あり**で作る（下の「[署名ありのアーカイブ](#署名ありのアーカイブ)」）。
署名なしのアーカイブにはエンタイトルメントが焼かれず、App Store 向けの掛け直し（export の段階で、
クラウド管理の配布証明書で行う）もアーカイブにあるエンタイトルメントしか引き継がないため。
`make export-ipa` の照合で、提出物にエンタイトルメントが載っているかを確かめてから送る
（所有者が main で確かめるまでは、照合は警告だけ）。

### `Config/ExportOptions.plist`

| キー | 値 | 理由 |
|---|---|---|
| `method` | `app-store-connect` | App Store Connect 向け。旧名の `app-store` は非推奨 |
| `destination` | `upload` | 書き出したものをそのまま送る（既定は手元に書き出すだけ） |
| `teamID` | `NL9ZXK2SGR` | |
| `signingStyle` | `automatic` | プロファイルとクラウド管理の配布証明書を Xcode に用意させる |
| `manageAppVersionAndBuildNumber` | `false` | 既定は YES。Xcode がビルド番号を書き換えると、`asc.py wait-build` が番号でビルドを見つけられない |
| `uploadSymbols` | `true` | クラッシュレポートを読めるようにする |
| `testFlightInternalTestingOnly` | `false` | 審査に出すビルドなので、社内テスト専用にしない。`make upload INTERNAL_BUILD=YES`（`mode=testflight`）のときだけ、release.mk が `true` にした写しで送る（診断画面の入ったビルドを審査や外部テストに回さない） |

### 署名ありのアーカイブ

release.yml は、アーカイブを開発用の証明書（Apple Development）で署名して作る（`make archive ARCHIVE_SIGNING=YES`）。
署名なしのアーカイブにはエンタイトルメントが焼かれず、App Store 向けの掛け直し（export の段階のクラウド署名）も
アーカイブにあるエンタイトルメントしか引き継がないため。署名なしのままだと、データ保護
（`default-data-protection`）が提出物から抜ける。

証明書を Secrets に置いて毎回取り込むのは、使い捨てのランナーで自動署名に任せきりにすると、手元に使える
証明書が無いので、実行のたびに Xcode が API キーの権限で開発用の証明書を新しく作り、その秘密鍵がランナーと
一緒に消えるため（証明書が溜まり、次の実行で秘密鍵の無い証明書を掴んで落ちることがある）。

upload ジョブでの流れ:

| ステップ | すること |
|---|---|
| 署名の証明書を一時キーチェーンに取り込む | Secrets の .p12 を base64 から戻し、使い捨てのキーチェーン（`$RUNNER_TEMP/signing.keychain-db`。パスワードは実行ごとの乱数）に取り込んで、キーチェーンの検索リストに足す。取り込んだら .p12 はすぐ消す。Secrets が無い、.p12 を読めない、Apple Development の証明書と秘密鍵が入っていない、チームが `DEVELOPMENT_TEAM` と違う、期限が切れている、のどれかなら止める。期限が 30 日を切ると警告を出す |
| アーカイブを作る | `make archive ARCHIVE_SIGNING=YES ARCHIVE_KEYCHAIN=…`。証明書はそのキーチェーンから使い（codesign に `--keychain` で指定）、開発用のプロファイルは `-allowProvisioningUpdates` と API キーで Xcode が用意する（チームは `Config/Base.xcconfig` の `DEVELOPMENT_TEAM`、自動署名） |
| 送る前に書き出して確かめる／アップロード | これまでどおり。App Store 向けには、クラウド管理の配布証明書で署名し直す |
| 後片付け（鍵を残さない） | 成否や取り消しにかかわらず（`if: always()`）、キーチェーン（検索リストからも外れる）と一時ファイル（.p12・.pem・.p8）を消す |

**Secrets が無いときは止める。** 署名なしに切り替えて続けることはしない。アップロード前の照合がまだ警告だけ
なので、署名なしに落とすと、データ保護の抜けたビルドが警告 1 つで審査まで進むため。`mode=export` でも同じ
（署名ありのアーカイブで照合が通るかを確かめるための実行なので）。版が配信済み（タグあり）などでアップロードを
スキップする実行では、証明書を取り込まないので止まらない。

公開リポジトリの Actions のログは誰でも読める。release.yml は証明書の名前（`Apple Development: 氏名 (…)`）を
自分では出さないが、xcodebuild はアーカイブのログの署名の行にその名前を出す。

#### 証明書（.p12）を用意する

1. チームに端末が 1 台以上登録されているかを確かめる（Certificates, Identifiers & Profiles → Devices）。
   開発用のプロファイルは、登録した端末が無いと作れない（アーカイブが `Your team has no devices from which to
   generate a provisioning profile` で止まる）。手元の Xcode でその iPhone に一度ビルドすれば自動で登録される
2. Mac の Xcode → 設定 → Accounts で、Apple アカウントとチーム（`NL9ZXK2SGR`）を選び、**Manage Certificates…** を開く。
   この Mac に秘密鍵のある Apple Development の証明書が無ければ、左下の **+** → **Apple Development** で作る
   - できれば CI 用の証明書を手元の開発用と分ける。漏れた疑いがあるときに、CI 用だけを失効させられる
3. 一覧の Apple Development の証明書を右クリック → **Export Certificate** で .p12 に書き出す。**パスワードを必ず付ける**
   （空のパスワードは Secret に登録できない）。キーチェーンアクセス（ログイン → 自分の証明書で、秘密鍵の付いた
   `Apple Development: …` を 1 つだけ選び、右クリック → 書き出す → 形式は .p12）で書き出してもよい
   - openssl で作った .p12 は、macOS の `security import` が読めない形式になることがある。Xcode かキーチェーンアクセスで書き出す
4. base64 にしてクリップボードへ写す: `base64 -i AppleDevelopment.p12 | pbcopy`
5. Environment `release` の Secrets に入れる。`APPLE_DEV_CERT_P12_BASE64` に 4 の中身、`APPLE_DEV_CERT_P12_PASSWORD` に 3 のパスワード
6. 手元の .p12 を消す（秘密鍵が入っている）。リポジトリの中には置かない（`.gitignore` で `*.p12` は除外済み）
7. main で Actions → release → Run workflow → `mode=export` を走らせ、取り込みから書き出しまで通ることを確かめる

#### 年に一度の更新

Apple Development の証明書の期限は 1 年。期限は「署名の証明書を一時キーチェーンに取り込む」のログ
（`署名の証明書を取り込みました（期限: …）`）に出る。30 日を切ると警告（run の Annotations）が出て、切れると
アーカイブの前に止まる。警告は release.yml が走ったときにしか出ないので、期限の日はカレンダーにも入れておく。

1. 上の「証明書（.p12）を用意する」の 2〜6 で新しい証明書を作って書き出し、Secrets の 2 つを差し替える
2. `mode=export` で、取り込みから書き出しまで通ることを確かめる
3. 古い証明書は、期限切れを待つか、Certificates, Identifiers & Profiles → Certificates で失効させる。開発用の証明書を
   失効させても、配信済みのアプリには影響しない（App Store のアプリは配布証明書で署名し直されている）

#### 照合を止める扱いに戻す（所有者が確かめてから）

アップロード前の照合（「送る前に書き出して確かめる」）は、まだ `RELEASE_ENTITLEMENTS_CHECK=warn` のまま。
署名ありのアーカイブの経路をまだ一度も通していないため（経路のどこかが食い違っていたときに、マージのたびに
リリースが止まらないように）。初回リリースでは、審査に出す前に済ませる（「[初回リリース（0.1.0）の進め方](#初回リリース010の進め方)」の 6）。

1. 証明書の Secrets を入れ、main で Actions → release → Run workflow → `mode=export` を走らせる
2. 「書き出すだけ（送信しない）」が緑で、`OK: SaifuLog/SaifuLog.entitlements のキーはすべて載っています` と出ることを確かめる
3. release.yml の「送る前に書き出して確かめる」から `RELEASE_ENTITLEMENTS_CHECK=warn` を外す PR を develop へ出す。
   あわせて release.mk と release.yml のコメント、この文書、`CLAUDE.md`、`docs/design.md`（§5-4・§14・§15）の
   「警告だけ」の記述も直す

### アプリアイコン（`AppIcon.appiconset`）

`SaifuLog/Resources/Assets.xcassets/AppIcon.appiconset` に 1024 × 1024 の PNG を置き（ライトは必須、
ダーク・色付きは任意。いまは 3 枚とも入っている）、`Contents.json` の `filename` で参照する。
ホーム画面などの小さい大きさは Xcode（actool）が作る。

- **アイコンが無いと、App Store Connect がアップロードを弾く。** AppIcon が空でもビルドと
  アーカイブは通ってしまうので、`make archive` の最後でアプリの Info.plist に `CFBundleIcons` が
  あるかを見て、無ければ止める。build.yml も `make archive` を通すので、main へのマージ前
  （PR の段階）で気づける
- 透過（アルファチャンネル）を入れない。透過があってもアップロードで弾かれる。角は丸めない
  （iOS が丸める）
- アイコンは「カードがのぞく財布」。ライト（真っ白の地に黒い財布）・ダーク（真っ黒の地に白い財布（ライトの反転））・
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

`mode=testflight` の実行も同じ式で番号を付ける。TestFlight 用に別のワークフローを作らないのは、社内テスト用の
ビルドも App Store へ出すビルドと同じ版の中で番号の重複を許されず、別のワークフローにすると `run_number` が 1 から
別々に数えられて番号がぶつかるため。同じ release.yml の実行番号を分け合えば、mode にかかわらず番号は実行ごとに
必ず増える。

tag-release.yml は、この式を逆にたどって、配信されたビルドを作った release.yml の実行（とその
コミット）を見つける。式を変えるときは tag-release.yml も一緒に直す。配信待ちの版があるうちに
`BUILD_NUMBER_OFFSET` を変えると逆算がずれる（tag-release は版が合わずに止まるので、手動実行の
`sha` でコミットを指定する）。

`Config/Base.xcconfig` の `CURRENT_PROJECT_VERSION`（1）は手元のビルド用で、CI では使わない。
手元から送るときは、`make archive BUILD_NUMBER=<CI より大きい番号>` でアーカイブを作り直してから
`make upload` する。`make upload` は `BUILD_NUMBER` を読まない（アーカイブに焼かれた番号で送る。
違う値を渡すと止まる）。手元から送ったビルドは release.yml の実行と結びつかないので、それが配信
されたときは、tag-release を `sha` を指定して手動実行する。

### `tag-release.yml`

配信が始まった版に、タグ `v<version>` と GitHub Release で印を付ける。3 時間おきの cron と
手動実行（Actions → tag-release → Run workflow）で動く。

- **見るのは App Store Connect で配信中の版**（`asc.py version-info --live`）。main のバージョン
  ではない。前の版の審査中に次の版を main へ入れても、前の版が配信されればその版に印が付く。
  main のバージョンのタグと Release が既にあれば、App Store Connect を見ずに終わる。
- **タグを打つのは、配信されたビルドを作ったコミット。** main の HEAD ではない。審査中に版を
  上げずに main へ入れた変更（ドキュメントの修正など）は、配信されたビルドに入っていないため。
  配信中の版に紐づいたビルド番号から、release.yml の式（上の「ビルド番号の決め方」）を逆にたどって
  実行番号を出し、その実行の `head_sha` を Actions の API で引く。打つ前に、そのコミットが main の
  履歴にあること、そのコミットの `Config/Base.xcconfig` の版がタグの版と同じことを確かめる。
- 逆算できないとき（手元から送ったビルド、配信待ちの版があるうちに `BUILD_NUMBER_OFFSET` を変えた、
  App Store Connect の版番号が `MARKETING_VERSION` と違う）は、赤で止まってコミットの指定を求める。
- release.yml の `mode=testflight` の実行も同じ実行番号の系列を使うが、逆算に紛れることはない。逆算するのは配信中の版
  （`force` なら指定した版）に紐づいたビルドの番号だけで、社内テスト専用のビルドは版に紐づけられない（審査に出せない）。
  実行番号は mode によらず 1 つの実行に 1 つなので、番号から引いた実行は、配信されたビルドを作った実行そのものになる。
- ジョブは 2 つに分けてある。鍵と書き込みの権限を同じジョブに置くと、そのジョブで動く依存の 1 つが
  乗っ取られただけで、両方を一度に取られるため。

| ジョブ | 持つもの | すること |
|---|---|---|
| `check` | Environment `release`（App Store Connect の鍵）、`contents: read`、`actions: read` | 配信状況を調べ、打つ版とコミットを決める。依存（`scripts/requirements.txt`）はここでだけ入れる |
| `tag` | `contents: write` だけ（鍵も Environment も持たず、pip も実行しない） | タグの push と GitHub Release の作成。本文はタグのコミットの `CHANGELOG.md` の節 |

手動実行の入力:

| 入力 | 効果 |
|---|---|
| `sha` | タグを打つコミット。空なら、配信されたビルドのビルド番号から逆算する。逆算で止まったときに、配信されたビルドを作ったコミットを入れる |
| `force` | App Store の配信状況を見ずに、main のバージョンのタグを打つ。コミットは `sha` が空なら、その版に紐づいたビルドから逆算する |

### `scripts/asc.py`

App Store Connect API を叩く小さな道具。4 つの操作だけを持つ。

| 操作 | 何をするか |
|---|---|
| `wait-build` | アップロードしたビルドの処理（`processingState`）が `VALID` になるのを待つ。輸出コンプライアンスが未回答なら止まる |
| `submit` | バージョンを用意し（無ければ作る。編集中の版があれば番号を書き換えて使う。既にある版の `releaseType` が指定と違えば合わせる）、ビルドを紐づけ、リリースノートを入れ、審査に出す。前の版が審査中・配信待ちなら、新しい版を作らずに案内を出して止まる。審査への追加で 409 が返ったら、Apple の理由（`errors[].detail` と `associatedErrors`）をそのまま出し、この版が本当に提出の入れ物に入っているときだけ先へ進む |
| `state` | いまそのバージョンがどう扱われているかを表示する。`--require-open` は release.yml が使う（承認済み以降でもうビルドを送れなければ終了コード 2、版がまだ無ければ `NOT_FOUND` と出して 0）。`--require-live` は配信中なら 0、配信前なら 2（版がまだ無い提出前も 2。`NOT_FOUND` と表示する）で、配信を待つ判定に使える（いまのワークフローは使っていない） |
| `version-info` | `--live`（配信中の版）か `--version X` の版について、`version=`・`state=`・`build=`（紐づいたビルド番号）の行を出す。版が無ければ終了コード 2。tag-release.yml が、タグを打つ版とコミットを決めるのに使う |

認証は API キーから作る ES256 の JWT（有効期限 15 分。時計のずれに備えて発行時刻を 60 秒前にする）。
GET が 401 で返ったら、トークンを作り直して 1 回だけやり直す（POST・PATCH はやり直さない）。
依存は PyJWT（と cryptography）だけで、HTTP は標準ライブラリ。.p8 は `ASC_API_KEY_P8`（中身）か
`ASC_API_KEY_PATH`（パス）で渡す。後者は release.mk と同じ環境変数なので、手元からも試せる。

依存は `scripts/requirements.txt` に、推移依存まで版とハッシュで固定してある。Admin 権限の鍵を
持つジョブで、PyPI のその日の最新をそのまま実行しないため。CI は
`pip install --require-hashes --only-binary=:all: -r scripts/requirements.txt` で入れる（ソースからの
ビルドも許さない）。手元で試すときも同じファイルから入れる。

```bash
python3 -m pip install --require-hashes -r scripts/requirements.txt
```

依存を変えるときは `scripts/requirements.in` を直し、ファイルの先頭にある手順（使い捨ての venv に
pip-tools を入れて `pip-compile --generate-hashes --strip-extras scripts/requirements.in`）で
`requirements.txt` を作り直す。手で書き換えない。版上げは Dependabot が `requirements.txt` ごと PR にする。

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
| Python | 3.12（`actions/setup-python`） | release.yml / tag-release.yml の `python-version` |
| actions | `actions/checkout`・`actions/setup-python` をコミットの SHA で固定（版はコメント） | 3 つのワークフローの `uses:` |
| `scripts/asc.py` の依存 | PyJWT と推移依存を版とハッシュで固定 | `scripts/requirements.txt`（`scripts/requirements.in` から生成） |

`macos-latest`（macos-26）の Xcode は 26.x 止まりで iOS 27 SDK が無い。iOS 27 の API を
使った時点で CI だけが落ちるので、Xcode 27 の入った `xcode-27` を使っている。
GA でラベルが変わったら、build.yml と release.yml を一緒に直す。ランナー・Xcode・XcodeGen は
Dependabot の対象外なので、上げるときは手で、意図的な PR で上げる。

actions と Python の依存は Dependabot が月に一度 develop 宛てに PR を立てる。actions は SHA と
版のコメントを組で書き換え、pip は `requirements.txt` をハッシュごと作り直す。`uses:` を足すときも
タグではなく SHA で書く（Settings で SHA での固定を必須にしている。「一度だけの準備」の 7）。

### cron の注意

`tag-release.yml` の `schedule` は、**このリポジトリの既定ブランチ（`develop`）に
あるファイル**で動く。ワークフローを直して develop へマージすると、次の cron からその定義で動く
（判定に読む中身は常に main。「既定のブランチ」を参照）。cron の時刻は UTC。

また GitHub は、60 日間まったく動きの無いリポジトリで scheduled workflow を
自動的に止める。長く触っていない状態でリリースしたときは、Actions タブで
有効になっているかを確認する（止まっている間は手動実行もできないので、Enable workflow で有効に戻してから走らせる）。

いまは、最初のリリースまで所有者が tag-release を手で無効にしてある（「[既定のブランチ](#既定のブランチ)」）。
初めて main へマージするときに有効に戻す（「[初回リリース（0.1.0）の進め方](#初回リリース010の進め方)」の 2）。

---

## この先やれること

| やれること | 手段 |
|---|---|
| 英語のリリースノートを分ける | CHANGELOG に英語の節を持たせ、`asc.py` の `set_whats_new` でロケールごとに入れ分ける |
| 審査結果を通知する | `scripts/asc.py state` を cron で回して通知する |
| 審査状態の変化を待たずに拾う | App Store Connect の Webhook（公開 URL の受け口が要る） |
| 説明文とスクリーンショットを App Store Connect へ自動で入れる | 下書きとスクリーンショットは `docs/app-store/` にある（入力はいまは手作業）。自動にするなら fastlane `deliver` に寄せるか、`asc.py` にローカライズとスクリーンショットの登録を足す |
| 段階的リリース（Phased Release） | `appStoreVersionPhasedReleases` を叩く |

### Capability（iCloud など）を足すとき

release.yml はアーカイブを開発用の証明書で署名して作る（上の「[署名ありのアーカイブ](#署名ありのアーカイブ)」）ので、
エンタイトルメントはアーカイブに焼かれ、App Store 向けの掛け直しでも引き継がれる。いまのアプリのエンタイトルメント
（`project.yml` の `entitlements.properties` から `make generate` が `SaifuLog/SaifuLog.entitlements` を書き出す）は次のとおり。

| キー | 値 | 何のため |
|---|---|---|
| `com.apple.developer.default-data-protection` | `NSFileProtectionComplete` | 保存先のデータ保護（`docs/design.md` §5-4） |
| `com.apple.developer.icloud-services` | `CloudKit` | iCloud 同期（`docs/design.md` §5-3） |
| `com.apple.developer.icloud-container-identifiers` | `$(ICLOUD_CONTAINER_ID)`（`Config/Base.xcconfig`。`iCloud.com.iam74k4.SaifuLog`） | 同期に使う CloudKit のコンテナ。署名のときに Xcode が値に置き換える |
| `aps-environment` | `development` | ほかの端末の変更の知らせ（CloudKit のサイレントプッシュ）。App Store 向けの書き出しで、配布用のプロファイルの `production` に替わる |

あわせて Info.plist の `UIBackgroundModes` に `remote-notification`（`SaifuLog/Info.plist`。ビルドの設定で書けないキーだけを置く
ファイル）を入れている。アプリが裏にいる間も、知らせを受けて取り込むため。

iCloud（CloudKit）、App Groups、プッシュ通知などを足すときは、次の順で進める。

1. `project.yml` の `entitlements.properties` に足し、`make generate` で `SaifuLog/SaifuLog.entitlements` を書き出す。
   値も確かめたいもの（書き出しで替わるもの、ビルドの設定から入るもの）は、`release.mk` の `RELEASE_ENTITLEMENT_VALUES` にも足す
2. Bundle ID の設定（Identifiers）でその Capability を有効にする。export はアプリ ID の設定を変えないため
   （iCloud と Push Notifications は所有者がオンにし、コンテナ `iCloud.com.iam74k4.SaifuLog` を割り当て済み）
3. main へ入れたら `mode=export` で走らせ、照合が通る（`OK: …` の 2 行）ことを確かめる。main へ入れる前に、手元で
   `make archive` と `make export-ipa`（Xcode のアカウントで署名する）を通して確かめてもよい

署名なしのビルド（`make build`・`make build-tests`・build.yml と `make ci` の `make archive ARCHIVE_SIGNING=NO`）は、
エンタイトルメントを焼かないので、iCloud や Push のプロファイルが無くても通る。アプリのテストも署名なしで動かすので、
テストのプロセスには iCloud の entitlement が無い（`CKContainer` を作ると落ちるので、テストでは CloudKit に問い合わせない）。

release.yml はアップロードの前に `make export-ipa` で書き出したアプリをエンタイトルメントのファイルと照合する。
いまは `RELEASE_ENTITLEMENTS_CHECK=warn` で警告だけ（上の「[照合を止める扱いに戻す](#照合を止める扱いに戻す所有者が確かめてから)」）。
`mode=export` の照合は、抜けていれば止まる。

#### CloudKit のスキーマ（所有者の作業）

iCloud 同期は、SwiftData が記録と予算を CloudKit のレコード（`CD_Entry`・`CD_Budget`）として置く。レコードの型と項目（スキーマ）は、
開発用の環境（Development）では、アプリが初めて書き込んだときに自動で作られる。Production の環境では自動では作られないので、
所有者が CloudKit Console で出す。TestFlight と App Store のビルドは Production の環境を使う（Xcode から入れた Debug のビルドは
Development）。

記録と予算の項目は、すべて CloudKit の暗号化フィールドにしている（SwiftData の `@Attribute(.allowsCloudEncryption)`。`docs/design.md` §5-3）。
CloudKit は、スキーマに載った項目を後から暗号化フィールドに変えられず、暗号化フィールドをふつうの項目に戻すこともできない。
**Production に出す前に、型が暗号化になっているかを必ず確かめる**（2）。

0. **開発用の環境に、暗号化にする前の形のスキーマが残っていないかを確かめる。** 暗号化フィールドにする前のビルド（iCloud 同期を
   入れてから、記録と予算の項目を暗号化フィールドにする変更が develop に入るまでのビルド）で同期を試したことがあると、Development に
   `CD_Entry`・`CD_Budget` が暗号化でない項目（型が `String`・`Int(64)`・`Date/Time` など）で作られている。そのままでは同じ名前の
   項目を暗号化フィールドにできないので、CloudKit Console → `iCloud.com.iam74k4.SaifuLog` → Development → Reset Environment で
   リセットしてから（開発用の記録とスキーマがすべて消える。家計の共有を試していれば、その型も消えるので 5 で作り直す。Production には
   影響しない）1 に進む。試した実機のアプリは消して入れ直す（前のスキーマで同期した状態が端末の保存先に
   残っているため。消えるのは開発用の記録だけ）。`CD_Entry` が無ければ、そのまま 1 に進む
1. **開発用の環境にスキーマを作る。** 手元の Xcode から、iCloud にサインインした実機（登録済みの端末）へ Debug のビルドを入れ、
   設定の「iCloud で同期」をオンにして、記録を 1 件と月の予算を 1 つ入れる（どの項目にも既定値があるので、1 件で全部の項目が作られる）。
   数分待ってから [CloudKit Console](https://icloud.developer.apple.com/) → `iCloud.com.iam74k4.SaifuLog` → Development →
   Schema → Record Types に `CD_Entry` と `CD_Budget` があり、`CD_amount`・`CD_memo` などの項目が並んでいるかを確かめる
   - 項目の名前と型を間違えて作ったときは、Development の環境をリセットしてから（Console の Reset Environment。開発用の記録も消える）
     作り直す。Production に出した後はリセットできない
2. **暗号化フィールドになっているかを確かめる。** 同じ画面で、`CD_Entry` と `CD_Budget` のアプリの項目の型が、すべて「Encrypted」で
   始まっているかを見る（Console は暗号化フィールドの型を「Encrypted String」「Encrypted Double」「Encrypted Timestamp」のように
   表す。Apple の説明）。確かめる項目は次の 11（名前は Core Data が付ける `CD_` つき）
   - `CD_Entry`: `CD_amount`・`CD_isIncome`・`CD_categoryRawValue`・`CD_memo`・`CD_spentAt`・`CD_createdAt`・`CD_sourceRawValue`・`CD_originalText`
   - `CD_Budget`: `CD_scopeRawValue`・`CD_amount`・`CD_updatedAt`
   - Core Data が足す管理用の項目（`CD_entityName` と、文字の項目ごとの `…_ckAsset`）と、CloudKit のシステムの項目（`recordName`・
     `createdTimestamp` など）は、アプリから暗号化を指定しないので、ここでは見ない（`…_ckAsset` はアセットで、アセットは CloudKit が
     いつも暗号化する）
   - 暗号化でない型の項目が 1 つでもあれば、Production に出さない。アプリのモデルで指定が外れていないか（`make test-app` の
     `ModelContainerFactoryTests` が止めるはず）と、0 のリセットを済ませたかを確かめてから、0 からやり直す
3. **Production に出す。** CloudKit Console → Deploy Schema Changes で、Development のスキーマを Production に反映する。
   初回リリースの審査の前に済ませる（「[初回リリース（0.1.0）の進め方](#初回リリース010の進め方)」の 5）。TestFlight
   （`mode=testflight`）で同期を試すのも、これを済ませてから
4. モデルに項目を足したら（既定値つき・暗号化フィールド。`docs/design.md` §5-2）、1・2・3 をやり直す。Production のスキーマは足すことしか
   できないので、項目の名前や型の変更・削除はしない（アプリのテスト `ModelContainerFactoryTests` で、今の項目が残っていることと、すべての
   項目が暗号化フィールドであることを確かめている）。足した項目も、Production に出す前に 2 で型が暗号化になっているかを確かめる
5. **家族との共有の家計の記録の型（`HouseholdEntry`）**も同じく出す（家計の共有は実機で確かめるまで機能フラグで隠しているので、
   出すのは提供を決めてからでよい。`docs/design.md` §5-5）。家計の共有が有効なビルド（Debug）で、iCloud にサインインした実機から
   設定の「家族と共有」で家計を作り、「家族」で記録を 1 件入れると、持ち主の私用データベースの `household-…` のゾーンに `HouseholdEntry` の
   レコードができ、型と項目（`amount`・`memo` など 8 つ）が作られる。項目はすべて暗号化フィールド（Console で Encrypted と出る）で作る
   （アプリが `encryptedValues` に書く。後から暗号化フィールドに変えることはできない）。共有の画面を一度開くと、共有のレコード（`cloudkit.share`）も使われる

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

- `.github/workflows/release.yml` — main マージでアップロードし、審査に出す（手動実行の `mode=testflight` で、develop のビルドを TestFlight の社内テスト専用に送る）
- `.github/workflows/tag-release.yml` — 配信を検知してタグと GitHub Release を作る
- `.github/workflows/build.yml` — PR と push のビルド確認 CI（必須チェック `build`）
- `.github/dependabot.yml` — GitHub Actions と `scripts/` の pip の版上げ PR（develop 宛て）
- `Makefile` — 開発用のターゲットと `make ci`（build.yml と同じ 8 つ）
- `scripts/check-strings.py` — String Catalog とコードの文字列の整合を確かめる（`make check-strings`）
- `scripts/pick-simulator.sh` — アプリのテストを動かすシミュレータを選ぶ（`make test-app`。版を渡すと `make test-storekit`）
- `scripts/test-storekit.sh` — 購入のテストを動かし、飛ばされたものがあれば失敗にする（`make test-storekit`）
- `scripts/prepare-storekit-simulator.sh` — 購入のテストに使う版のシミュレータを用意する（ランタイムが無ければ入れる。build.yml）
- `release.mk` — `make version` / `check-version` / `archive` / `export-ipa` / `upload`
- `project.yml` — エンタイトルメント（データ保護・iCloud・aps-environment）の正。`SaifuLog/SaifuLog.entitlements` はここから生成する。
  ビルドの設定で書けない Info.plist のキー（`UIBackgroundModes`）は `SaifuLog/Info.plist`
- `Config/ExportOptions.plist` — 書き出しと送信の設定（`mode=testflight` のときは、release.mk が社内テスト専用にした写しを使う）
- `SaifuLog/Diagnostics/` — 社内テスト用のビルド（`mode=testflight`）と DEBUG のビルドにだけ入る診断画面
- `docs/app-store/` — App Store の掲載情報・審査メモ・App のプライバシーと年齢制限の回答の下書きと、スクリーンショット
- `docs/support.md` — サポート URL のページ（問い合わせ先とよくある質問）
- `scripts/app-store-screenshots.sh` — スクリーンショットを撮る（撮影用のデモを 6.9 インチのシミュレータで開いて撮る。透過の層は `scripts/screenshot-image.swift` で外す）
- `SaifuLog/ScreenshotDemo/` — DEBUG のビルドにだけ入る撮影用のデモ（架空の記録で撮る画面を開く）
- `Config/Base.xcconfig` — バージョンの正（`MARKETING_VERSION`）
- `scripts/asc.py` — App Store Connect API を叩く道具
- `scripts/requirements.in` / `scripts/requirements.txt` — `asc.py` の依存（txt は版とハッシュで固定した生成物）
- `scripts/changelog-section.sh` — CHANGELOG から該当バージョンの節を取り出す
- `scripts/check-version.sh` — バージョンを読み、CHANGELOG との一致を確かめる
- `CHANGELOG.md` — 変更履歴（各節がリリースノートになる）
