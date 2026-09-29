# SaifuLog-Apple

ひとことで記録できる iPhone の家計簿アプリ「SaifuLog（サイフログ）」。文章の理解は
端末内の AI（Apple の Foundation Models）で行い、家計のデータを端末の外に出さない。

## 現在の到達点
- 初期構成の段階。プロジェクトの骨組み・CI/CD・ドキュメントと、**ひとこと入力・記録の直し・家計への質問・レシートの読み取り・声の入力・月の予算・月のまとめ・週のふりかえり・設定と CSV 書き出し・iCloud 同期（自分の端末どうし）・初回の案内・プレミアム（StoreKit）の試作**まで。
  - 試作済み: 一行の読み取り（端末内 AI、使えない端末ではキーワード辞書）、タイムライン、記録直後の
    「直す」「取り消す」、長押しでの記録の削除（確認つき）、今月の支出と収入の合計。画面は縦向きのみ。
    ⑥ 直す（吹き出しを押す・長押しのメニュー・記録直後のバナー・VoiceOver の操作・⑦ の記録の一覧から開くシート。金額・品目・支出か収入か・
    カテゴリ・日付を直し、そこから削除もできる。`EditEntryModel` と `EntryStore.update`。割り勘の人数は記録に持たないので直せない）。
    月の全体の予算（② 予算を決める、ホームの帯の「今月あと ¥…／1日あたり ¥…」。カテゴリ別の予算の欄は、ホームと ⑧ から開いたときに
    プレミアムと体験中だけ出す。進み（使った額との比べ）はまだどこにも出さない）。⑦ 月のまとめ（ホームの帯の見出しと数字から横に進む。月送り・支出と収入と収支・1 日あたりの
    平均・前の月との差・予算の進み（いまの予算に決めた月から後だけ）・カテゴリ別の横棒グラフと行・行からその月の記録の一覧と ⑥。
    `MonthlyReportView` と `MonthlyReportModel`、数字はコアの `MonthlyReport` と `CategoryBreakdown`）。
    初回の案内（① ようこそ → ② → ホーム。記録がある端末には出さない。`AppRootView` と `OnboardingModel`）。
    ⑧ 設定（ホームの帯の右上の歯車から横に進む。月の予算（② のシート）・週の始まり（`AppSettings.weekStart`。`AppRootView` が画面の
    暦に当てはめる）・記録の CSV 書き出し（今月・先月・今年・すべて。中身はコアの `LedgerCSVWriter`、ファイルは `LedgerExporter` が
    メインスレッドの外で作り、共有の画面を閉じたら消す）・プライバシーポリシー・ライセンス・版。`SettingsView` と `SettingsModel`。
    いちばん上に「プレミアム」（状態）と「購入の復元」の行。週の始まりの下に「同期」の節（「iCloud で同期」））。
    ⑨ プレミアム（StoreKit 2。⑧ の「プレミアム」と、体験が終わった後の最初の起動に一度だけ出すシート。買い切り
    `com.iam74k4.SaifuLog.premium`（ファミリー共有）と、価格 0 の非消耗型の 14 日間の体験 `com.iam74k4.SaifuLog.trial14`（購入日時から
    経過時間で 14 日）。価格は App Store の表示のまま。まだ出していない機能は「近日」。`PremiumSheet` と `PremiumSheetModel`、購入・復元・
    Transaction.updates の購読は `SaifuLog/Purchases/PurchaseManager`（`SaifuLogApp` で 1 つ作り、起動したらすぐ購読）、状態はコアの
    `PremiumStatus`・`TrialPeriod`。無料の回数の数え方はコアの `UsageQuota` と `QuotaStore`（家計への質問とレシートの読み取りで使う）。
    Xcode の Run では `Config/SaifuLog.storekit` で購入を試せる。購入のテストは SKTestSession で、iOS 26.3・26.4 のシミュレータでは
    Apple の不具合で動かないので、`make test-app` から除き、`make test-storekit` が iOS 26.2 のシミュレータで動かす（飛ばされたら失敗。
    CI のランナーで iOS 26.2 のランタイムを入れて通るかはまだ走らせていない）。実機（Sandbox）での購入・復元・返金・ファミリー共有の
    確認はまだ。カテゴリ別の予算の進みを出すまで App 内課金は審査に出さない。家計への質問を出したので、この決め事を続けるかは見直し中で、
    所有者が決めるまでは出さない。`docs/release-flow.md` の「App 内課金を審査に出す」）。配色は墨 × 山吹。
    家計への質問（ひとこと入力と同じ入力欄。記録か質問かはコアの `InputIntentClassifier` が決め、誤って記録しないことを優先し、
    決められない文は記録せずに書き直しを案内する。端末内 AI は `SaifuLog/AI/FoundationModelsQuestionAnswerer` のツール呼び出しで期間・知りたいこと・
    カテゴリを選択肢から選ぶだけで、数字はコアの `LedgerQuestionAnswerer` が計算し、AI の一言の数字はコアの `AnswerSentenceCheck` で照合する。
    AI が使えないときはコアの `QuestionParser`。答えはホームのタイムラインの回答カード（`SaifuLog/Views/Question/`）で、保存しない。無料は月 10 回で、
    答えを出せたときだけ数え、使い切ったら ⑨ への案内。実機でのモデルの答え方の確認はまだ）。
    週のふりかえり（週が替わって最初に開いたときだけ、ホームのタイムラインの出した日時の位置に「先週のふりかえり」のカードを出し、出した日時を
    `AppSettings.weeklyRecapShownAt` に書いて同じ週にはもう出さない（閉じても開き直しても）。記録を始める前の週には出さない。定型文（先週の支出と
    前の週との差）・上位 3 カテゴリ・月の予算を日割りした週の目安との比べ・予算の目安の提案（予算が無ければ「予算を決める」、あれば差が 2 割以上の
    ときだけ。表示だけで予算は変えない）。押すと先週の内訳（⑦ と同じ部品。カテゴリの記録の一覧は `CategoryEntriesView` を共有）。数字と出す条件は
    コアの `WeeklyRecap`、予算の目安は `BudgetSuggestion`。`SaifuLog/Views/Recap/` の `WeeklyRecapModel`（カードと内訳で同じもの）・`WeeklyRecapCard`・
    `WeeklyRecapView`。プレミアムと体験中で AI が使える端末では、数字の文（コアの `RecapFacts`）だけを端末内 AI に渡して一言を書かせ
    （`SaifuLog/AI/FoundationModelsRecapRemarkWriter`）、`AnswerSentenceCheck` で照合して合わなければ捨てる（`RecapRemarkModel`）。月のまとめの先頭にも
    同じ一言。無料と AI の使えない端末は定型文だけ。週の始まりの朝の通知は出さない（未決）。実機でのモデルの一言の確認はまだ）。
    レシートの読み取り（④⑤。入力欄の左のカメラのボタン →「撮る」（VisionKit の書類カメラ）か「写真から選ぶ」（PhotosPicker）→ ⑤ の読み取り結果の
    シート。文字は `SaifuLog/Receipt/ReceiptTextRecognizer` が Vision で端末内で読み（iOS 26 の `RecognizeDocumentsRequest`、日本語に対応しないか読めなければ
    `VNRecognizeTextRequest`）、店名・日付・品目・値引き・税・合計などの見分けはコアの `ReceiptLineScanner`、照合と記録の下書きは `ReceiptReconciler`
    （外税は「税・その他」の 1 行。合わなければ ⑤ で確かめてから記録）。AI は品名とカテゴリだけを整え（iOS 27 で画像に対応したモデルは画像も、iOS 26 は
    文字だけ。`SaifuLog/AI/FoundationModelsReceiptItemRefiner`）、AI の金額は使わない（コアの `ReceiptItemRefinement`）。画像も OCR の全文も保存せず、
    記録の元の文は「レシート: 店名 合計 ¥…」の要約（`ReceiptSummary`）。無料は月 5 回で、記録したときだけ数え、直後の取り消しで戻す。使い切ったら
    カメラのボタンから ⑨。⑤ で直した内容があれば閉じる前に確かめ（⑥ と同じ）、書類カメラは 4 ページまで読んで、超えたら ⑤ に知らせる。
    状態は `SaifuLog/Views/Receipt/ReceiptResultModel`、出し入れと記録は `HomeModel`。実機でのカメラ・実際のレシートの読み取りの
    精度・モデルの整え方の確認はまだ）。
    声の入力（入力欄の右のマイクのボタン。入力欄が空なら送信の位置。話した内容を iOS 26 の SpeechAnalyzer で端末の中で書き起こし、入力欄に
    入れるだけで送信はしない（送信は利用者が押したときだけ）。SpeechTranscriber（ja_JP）を先に、日本語に対応しなければ DictationTranscriber、
    どちらも無ければマイクを出さない。書き起こしは `SaifuLog/Voice/`（`SpeechModules`・`SpeechAnalysisSession`・`SpeechAnalyzerTranscriber`。
    マイクは AVAudioEngine で取り、`bestAvailableAudioFormat` の形式に AVAudioConverter で変えて渡す）、状態は `SaifuLog/Views/Voice/VoiceInputModel`
    （許可・モデルのダウンロードの確認と進み・途中の文・止めるボタン・話し終えて 2 秒・話し始めずに 6 秒・30 秒・割り込み・裏へ）、まとめ方と
    止める決まりはコアの `VoiceTranscript`・`VoiceListeningLimit`。マイクの許可だけを求め、音声認識の許可は求めない（Apple の説明）。声は保存も
    送信もしない。無料で回数を数えない。声で入れた文の記録は入力元 `.voice`。実機での実際の声の書き起こし・許可・ダウンロード・割り込みの確認はまだ。
    シミュレータの iOS 26.4 では SpeechTranscriber が使えず、DictationTranscriber の日本語のモデルも無い）。
    iCloud 同期（⑧ の「iCloud で同期」。既定はオフ。自分の iCloud の私用データベース `iCloud.com.iam74k4.SaifuLog` で、同じ Apple
    アカウントの端末どうしの記録と予算をそろえる。家族との共有は含まない）。設定のキーは `AppSettings.iCloudSyncEnabled`、起動のときに
    `SaifuLogApp` が読んで `ModelContainerFactory.CloudKitDatabase`（`.none` / `.private`。`.automatic` は置いていない）を決める。
    オンとオフで同じファイル（default.store）を開き、`cloudKitDatabase` だけを替える。切り替えは `StoreHost.setICloudSyncEnabled`
    （設定に書いて `reopen`。前の保存先の画面が消え（`StoreRootView` の onDisappear）、書き込み中の処理が終わるのを待ってから開き、
    設定の画面を開いた状態のホームに戻す。ホームのモデルは `AppRootView` が 1 回だけ作り、`HomeModel.restoreSettingsAfterStoreSwitch`
    で設定を開く）。iCloud と同期する保存先だけを開けなければ（同じファイルを `.none` でなら開けたときだけ）`.none` に戻して設定もオフに
    し、理由（原因に近いエラーのドメインと番号）をアラートで出す（`ICloudSyncFailure`。`.none` でも開けなければ戻さず、設定も変えずに
    再試行の画面。SwiftData は CloudKit の制約違反を中身の分からない `loadIssueModelContainer` で投げるので、エラーの種類では見分けない）。オンにする前に `CKContainer.accountStatus`（`ICloudAccountStatus`）を確かめ、
    使えなければ案内だけ。設定の状態と操作は `SettingsModel`（アカウントの問い合わせは差し替えられる。テストのプロセスは iCloud の
    entitlement を持たないので `CKContainer` を作らない）。最後に同期した時刻は出さない。ほかの端末の変更は `StoreChanges.remote`
    （`NSPersistentStoreRemoteChange`）で、月のまとめ・ふりかえり・設定の予算を読み直す。エンタイトルメントに iCloud（CloudKit・
    コンテナ）と `aps-environment`、`SaifuLog/Info.plist` に `UIBackgroundModes` の remote-notification を足し、`make export-ipa` が値
    （`aps-environment` が production など。`release.mk` の `RELEASE_ENTITLEMENT_VALUES`）も照合する。モデルが CloudKit の制約を
    満たすことは `ModelContainerFactoryTests` で確かめている（制約のためにモデルを変えることは無かった）。記録と予算の項目はすべて CloudKit の
    暗号化フィールド（`@Attribute(.allowsCloudEncryption)`。高度なデータ保護をオンにした利用者ではエンドツーエンド）で、すべての項目に付いて
    いること（外したモデルを見逃さないことも）と、付ける前のモデルで作った保存先が移行なしで開けて記録と予算が残ることも
    `ModelContainerFactoryTests` で確かめている。項目を足すときも最初から付ける（CloudKit は後から暗号化フィールドに変えられない）。
    診断画面にアカウントの状態・いまの保存先の同期・設定の値。CloudKit のスキーマを Production に出すこと（所有者の作業。その前に
    CloudKit Console で項目の型が Encrypted になっているかを確かめる）と、実機 2 台での同期の確認はまだ（`docs/design.md` §5-3・§15、
    `docs/release-flow.md` の「Capability（iCloud など）を足すとき」の「CloudKit のスキーマ」）。
    家族・パートナーとの家計の共有（**機能フラグで隠している**。`HouseholdSharing.isEnabled` は DEBUG と社内テスト用のビルド（INTERNAL_DIAGNOSTICS）
    でだけ true で、App Store へ出すビルドでは画面・同期・招待の受け入れを出さない。`make archive` が、INTERNAL_BUILD=NO のアーカイブに印の文字列
    `SaifuLog-HouseholdSharing-v1` と Info.plist の `CKSharingSupported` が無いこと（と remote-notification があること）を確かめる。Info.plist は
    `SaifuLog/Info.plist` と `SaifuLog/Info-HouseholdSharing.plist` の 2 つで、`project.yml` の `SAIFULOG_HOUSEHOLD_SHARING` で選ぶ）。家計は自分の記録とは別の
    保存先（household.store。`ModelContainerFactory.makeHouseholdContainer`、`cloudKitDatabase` は `.none`）に置き、`SaifuLog/Household/` の `HouseholdSync` が
    CKSyncEngine を 2 つ（私用・共有のデータベース。状態は household.store に保存して次の起動で渡す。家計の無い端末でも作り、サーバーにある家計（同じ
    Apple アカウントのほかの端末・サインアウトの前）を取り込む。サインアウトしたら作り直し、前の CKSyncEngine から遅れて届いた出来事は捨てる）持って
    家計ごとのゾーン（`household-<UUID>`）と同期し、ゾーンごと CKShare で共有する。署名の無いビルド（`make build`・`make test-app`）は iCloud の entitlement が
    無く CKContainer で止まるので、家計の共有を始めない（`HouseholdSharing.canUseCloudKit`）。記録の中身はすべて暗号化フィールド（`HouseholdRecord`）。衝突は直した日時の新しいほう、削除が勝つ、ゾーンが消えたら
    端末の家計を消して知らせる（決め事はコアの `HouseholdConflict`・`HouseholdZoneRemoval`）。全体は `HouseholdHost`（`SaifuLogApp` で 1 つ、`AppRootView` が
    自分の記録の保存先を開けた後に `start()`）、共有の作成・削除・受け入れは `HouseholdCloudService`、招待は `HouseholdAppDelegate`・`HouseholdSceneDelegate`
    （DEBUG と社内テスト用のビルドだけ）から `HouseholdInvitationInbox` へ。設定の「家族と共有」の節（`Views/Household/`。家計を作る・UICloudSharingController で
    招待・共有をやめる・抜ける・削除）、ホームの帯の「自分／家族」（`HomeModel.ledgerScope`。「家族」では家計に記録し、家計の記録（記録した人の名前つき）と
    家族の今月の合計を出す。予算・まとめ・質問・ふりかえり・レシート・声は「自分」だけ）、⑥ は `EditEntryModel.Target` で家計の記録も直す。v1 は家計を 1 つ
    だけ。購入の状態で入口を絞っていない。CKSyncEngine と共有は差し替えてテストし、実機 2 台・2 アカウントでの確かめはまだ（`docs/design.md` §5-5・§15 の 15）。
    CHANGELOG の利用者向けの「追加」には、隠している間は書かない）。
    App Store の掲載情報の下書き（`docs/app-store/`。日本語と英語の名前・サブタイトル・説明・キーワードと文字数、審査メモ、App のプライバシー
    （データの収集なし）と年齢制限（4+）の回答。App Store Connect への入力は所有者が確かめてから）と、サポート URL のページ（`docs/support.md`）。
    スクリーンショットは撮影用のデモ（`SaifuLog/ScreenshotDemo/`。**DEBUG のビルドだけ**で、`#if DEBUG` の中。起動引数
    `-SaifuLogScreenshotDemo <画面>` と `-SaifuLogScreenshotPremium purchased|free` で、メモリの上の架空の記録・専用の UserDefaults の領域・
    決まった AI の一言とレシートと書き起こしと価格の表示で撮る画面を開き、初回の案内と診断のボタンと家計の共有を出さない）を
    `scripts/app-store-screenshots.sh` が 6.9 インチのシミュレータで日本語と英語で撮る（`docs/app-store/screenshots/`。透過の層は
    `scripts/screenshot-image.swift` で外す）。Release のアーカイブに入っていないことは `make archive` が印 `SaifuLog-ScreenshotDemo-v1`
    （`release.mk` の `RELEASE_SCREENSHOT_DEMO_MARKER`）で確かめる。組み立ては `ScreenshotDemoTests`。
    保存先を開けないときは落とさず、ロック中なら解除を待って開き直し、それ以外は再試行の画面を出す（`StoreHost`）。
    保存先のデータ保護は NSFileProtectionComplete（ロック中は読めないようにする。実機での確認はまだ。
    release.yml は開発用の証明書で署名したアーカイブから提出物を作るようにしたが、証明書の Secrets の登録と、
    main で `mode=export` の照合が通るかの確認はまだ。`docs/design.md` §5-4）。
  - **未実装:** カテゴリ別の予算の進みの表示・週のふりかえりの通知・家族との共有の提供（試作は機能フラグで隠している）・修正の記憶・CSV の読み込み。
  - 実機での確認の手段: release.yml の手動実行 `mode=testflight` で、develop のビルドを診断画面入りで TestFlight の
    社内テスト専用に送れるようにした（審査には出ない）。Environment `release` の配備ブランチへの develop の追加
    （所有者の作業）と、実際に TestFlight で入れての確認はまだ（`docs/release-flow.md` の「TestFlight で実機に入れる（社内テスト）」）。
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
リリースするつもりのない変更を main へ入れない。main へ入れる前に実機で確かめるときは、release.yml を
develop から `mode=testflight` で手動実行する（TestFlight の社内テスト専用。審査には出ない）。

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
  `-only-testing:SaifuLogTests`。購入のテスト `StoreKitPurchaseTests` は除く）。SwiftData の保存・読み込みの条件や保存の失敗の扱い、保存先の開き方、
  画面のモデル（`HomeModel`）の操作など、コアに置けない部分。
  機種は `scripts/pick-simulator.sh` が、いちばん新しい iOS の iPhone を選ぶ（`TEST_DESTINATION=…` で上書きできる）
- `make test-storekit` — 購入のテスト（SKTestSession）を、それが動く版（`STOREKIT_TEST_OS`、いまは iOS 26.2）のシミュレータで
  動かし、1 つでも飛ばされたら失敗にする（`scripts/test-storekit.sh`。シミュレータが無ければ `scripts/prepare-storekit-simulator.sh`）
- `make check-strings` — `make build` が書き出した Debug の .stringsdata と `Localizable.xcstrings` を突き合わせ、
  足りないキー・使われていないキー・en の無いキー・ja と en の書式指定子の不一致があれば止まる（`scripts/check-strings.py`）
- `make ci` — 必須チェック `build`（build.yml）と同じ 8 つ（`make build`・`make check-strings`・`make test`・`make build-tests`・
  `make test-app`・`make test-storekit`・`make check-version`・`make archive ARCHIVE_SIGNING=NO BUILD_NUMBER=99999`）を順に通す。
  **`make build` が通るだけでは CI が通るとは限らない。** PR の前はこれを通す
- `make clean` / `make open` — 生成物の削除 / Xcode で開く
- `release.mk`（Makefile の末尾で読み込む）:
  - `make version` — いまの `MARKETING_VERSION` を表示する
  - `make check-version` — `MARKETING_VERSION` と CHANGELOG 先頭の見出しの一致を確かめる
  - `make archive` — Release の .xcarchive を `build/` に作る。`BUILD_NUMBER=…` でビルド番号を上書きできる。
    既定は署名あり。`ARCHIVE_SIGNING=NO` で署名なし（build.yml と `make ci`）、`ARCHIVE_KEYCHAIN=…` で署名に使う
    キーチェーンを指定する（release.yml が、証明書を取り込んだ使い捨てのキーチェーンを渡す）。
    `INTERNAL_BUILD=YES` で社内テスト用（診断画面入り。release.yml の `mode=testflight` だけが渡す。既定は `NO`）。
    できたアプリの Info.plist にバージョン・ビルド番号・アイコンが入っているかと、診断画面が `INTERNAL_BUILD` の
    とおりに入っているか（`NO` なら入っていないか）も確かめる（CI の build でも走る）
  - `make export-ipa` — アーカイブから .ipa を書き出すだけ（送信しない）。署名とエンタイトルメントを表示し、
    エンタイトルメントのファイル（`SaifuLog/SaifuLog.entitlements`）のキーが載っていなければ止まる
    （`RELEASE_ENTITLEMENTS_CHECK=warn` なら警告だけ）。release.yml はアップロードの前に必ずこれを通す。
    release.yml のアーカイブは署名あり（Apple Development の証明書を一時キーチェーンに取り込む）にしたが、
    その経路はまだ一度も通していないので、所有者が main で `mode=export` の照合が通るのを確かめるまでは `warn` を渡している
  - `make upload` — `Config/ExportOptions.plist` で App Store Connect へ送る。ビルド番号はアーカイブに
    焼かれた値で、`make upload BUILD_NUMBER=…` では変わらない（違う値を渡すと止まる）。番号を変えるときは
    `make archive BUILD_NUMBER=…` から。認証は App Store Connect API キー
    （環境変数 `ASC_API_KEY_ID` / `ASC_API_ISSUER_ID` / `ASC_API_KEY_PATH`）。社内テスト用のアーカイブは
    `INTERNAL_BUILD=YES` で送り、TestFlight の社内テスト専用（`testFlightInternalTestingOnly`）になる
    （`make export-ipa` も同じ。アーカイブの診断画面の有無と `INTERNAL_BUILD` が合わなければ止まる）
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
- `SaifuLog/` — アプリ本体。起動と保存先を開く部分・設定のキー（`App/`）、SwiftUI の画面と画面ごとの
  `@Observable` のモデル（`Views/`）、SwiftData のモデルと保存先の作り方（`Models/`）、
  Foundation Models を使う部分（`AI/`）、`Resources/`（Assets、String Catalog など）、
  実機での確認に使う診断画面（`Diagnostics/`）。
- 診断画面（`SaifuLog/Diagnostics/`）は、社内テスト用のビルド（Swift の条件 `INTERNAL_DIAGNOSTICS`。
  `make archive INTERNAL_BUILD=YES`）と DEBUG のビルドにだけ入れる。コードは必ず `#if DEBUG || INTERNAL_DIAGNOSTICS` で
  囲い（入口のボタンや `HomeView` のシートも）、App Store へ出すビルドに入れない（`make archive` がアプリの中の印
  `DiagnosticsReport.buildMarker` を探し、入っていれば止まる）。コピーする文に家計の中身（金額・メモ・入力した文・
  予算の額）や端末の名前を入れない（テストで確かめている）。プライバシーマニフェストで理由の申告が要る API
  （ファイルの日時・空き容量・起動からの時間など）は使わない（社内テスト用のビルドもアップロードで検査される）。
  DEBUG のビルド（Xcode の Run の既定）でもホームの帯に診断のボタンが出るので、App Store 用のスクリーンショットは
  診断のボタンを出さない撮影用のデモ（`SaifuLog/ScreenshotDemo/`）で `./scripts/app-store-screenshots.sh` が撮る
  （`docs/app-store/README.md`、`docs/release-flow.md` の「一度だけの準備」の 5）。
- `Packages/SaifuLogCore/` — 純粋なロジック（金額・日付の読み取り、キーワード辞書による解析、
  割り勘や合計・残りの計算など）とそのテスト。**FoundationModels / SwiftData / SwiftUI を入れない。**
  CI の macOS ランナー上で `swift test` を回すため、platforms は `.iOS(.v26), .macOS(.v14)` に保つ。
- 集計はコアの `LedgerSummary`（期間の支出・収入・差額・支出のカテゴリ別の合計）に、期間の区切りは `ReportPeriod`
  （区切りは渡された暦のまま、週の始まりはその `firstWeekday`。西暦で読むのは `month(year:month:)` の年月だけ）に
  集める。ホームの「今月」（`MonthlySummary`・`Entry.monthDescriptor`）も `ReportPeriod.thisMonth` で区切る。
  画面ごとに合計や期間を計算し直さない（画面の数字と AI に渡す数字が食い違うため）。
- 文字列は String Catalog（`.xcstrings`）で、開発言語 ja に en を足す。開発言語を ja にしているのは
  意図どおり（日本語と英語のどちらも優先言語に無い端末では日本語で出る。理由は `docs/design.md` §10）。
  ホーム画面の表示名は
  `SaifuLog/Resources/InfoPlist.xcstrings` の `CFBundleDisplayName`（ja「サイフログ」/ en「SaifuLog」）。
- アプリアイコンは `Resources/Assets.xcassets/AppIcon.appiconset/` の 3 枚（1024 × 1024・透過なし）。
  `AppIcon.png`（ライト: 真っ白の地に黒い財布）、`AppIcon-Dark.png`（ダーク: 真っ黒の地に白い財布（ライトの反転））、`AppIcon-Tinted.png`（色付き）。
  元の SVG は `design/icon/`。**AppIcon を空にしない。** 空でもビルドは通るが、App Store Connect が
  アップロードを弾く（`make archive` の検査で止まる）。

### 保存先・設定・テストの作り方
- **保存先（`ModelContainer`）は `SaifuLog/Models/ModelContainerFactory.swift` でだけ作る。** アプリは
  `makeContainer(cloudKitDatabase:)`、テストとプレビューは `makeInMemoryContainer()`。`.modelContainer(for:inMemory:)` や
  `ModelConfiguration(isStoredInMemoryOnly:)` を直接使わない（iCloud が既定の `.automatic` になり、iCloud の
  entitlement を足した時点でテストやプレビューまで同期しようとするため）。保存先の場所（`storeURL`、
  Application Support/default.store）は変えない（変えるとそれまでの記録が読めなくなる。テストで確かめている）。
  モデルを足すときは `ModelContainerFactory.modelTypes` に並べる。
- アプリの保存先は `SaifuLog/App/StoreHost.swift` が開く（最初の画面が出るとき）。fatalError で止めない。
  ロック中は解除を待って開き直し、それ以外の失敗は再試行の画面（`StoreRootView`）を出す（再試行でもまた開けなければ、
  回数を出して VoiceOver にも読み上げる）。iCloud の切り替えなどで開き直すときは `reopen(cloudKitDatabase:)`
  （画面のツリーを畳み、書き込み中の処理が終わるのを待ってから開く）を使う。解析を待ってから記録するなど、
  あとで保存先に書き込む処理は、Task を作る前に `StoreHost.pendingWrites` の `begin()` を呼び、終えたら `end()` を呼ぶ
  （数えないと、開き直しが待たずに新しい保存先を開き、前の保存先へ書き込むことになる）。
- 画面の状態と操作は、画面ごとの `@Observable` のモデル（例: `SaifuLog/Views/HomeModel.swift`）に置き、View は
  表示と環境に合わせた出し方だけにする。解析器・時計・VoiceOver の読み上げはモデルの外から渡せるようにする。
- アプリのテストは、`SaifuLogTests/TestSupport.swift` の `makeContext()`（中身は `makeInMemoryContainer()`）で
  テストごとに新しい保存先を作り、固定の日時（`TestSupport.now`）と暦（`TestSupport.calendar`）を使う。
  解析器は `StubParser` か、固定の日時の `RuleBasedParser` を渡す。保存の失敗は `EntryStore.save` を差し替えて起こす。
  コアのテストは Swift Testing と `Fixture` の固定の日時で書く。
- UserDefaults（`@AppStorage`）のキーと既定値は `SaifuLog/App/AppSettings.swift` にだけ書く
  （`@AppStorage(AppSettings.hasCompletedOnboarding)`）。置き場所は `UserDefaults.standard` だけ
  （`PrivacyInfo.xcprivacy` の CA92.1 と合わせる。App Group の共有の領域に置くなら、先にマニフェストへ 1C8F.1 を足し、
  `PRIVACY.md` も直す）。家計の記録そのものは UserDefaults に置かない。

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
- 記録の直後に必ず「直す」「取り消す」を出す。記録は長押しでいつでも
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
- `docs/release-flow.md` — リリースフロー（main マージで App Store Connect へ自動アップロード。develop のビルドを
  TestFlight の社内テストで試す `mode=testflight` も）
- `PRIVACY.md` — プライバシーポリシー（草案。初回リリースの手順で草案の注記を外し、施行日を入れて
  main へ入れてから審査に出す。`docs/release-flow.md` の「初回リリース（0.1.0）の進め方」）
- `SECURITY.md` — 脆弱性・プライバシーの問題の非公開の報告窓口
- `CHANGELOG.md` — 変更履歴（先頭の見出しがバージョンの検査とリリースノートに使われる）
- `LICENSE` — 権利留保。個人が自分の端末で試すための clone・ビルドだけを許可（再配布・公開・商用は不可）
