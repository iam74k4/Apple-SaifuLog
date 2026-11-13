# SaifuLog-Apple

ひとことで記録できる iPhone の家計簿アプリ「SaifuLog（サイフログ）」。文章の理解は
端末内の AI（Apple の Foundation Models）で行い、家計のデータを端末の外に出さない。

## 現在の到達点
- 初期構成の段階。プロジェクトの骨組み・CI/CD・ドキュメントと、**ひとこと入力・記録の直し・チャットで頼む操作（直す・消す・予算）・記録の返事の AI の一言・カテゴリの振り分けと聞き返しと修正の記憶・家計への質問・レシートの読み取り・月の予算・カレンダー・月のまとめ・設定と CSV 書き出し・iCloud 同期（自分の端末どうし）・アプリのロック・初回の案内の試作**まで。すべての機能を無料で、回数の制限なく使える（プレミアムと課金はやめた）。
  - 試作済み: 一行の読み取り（端末内 AI、使えない端末ではキーワード辞書）、タイムライン（会話の形。1 回の送信で記録したものを
    送信にまとめ（コアの `TimelineSend`。送信は保存せず、元の文・入力元が同じで記録した日時が 0.1 秒以内に続く記録をまとめる）、送った文を
    右寄せの自分の吹き出し（灰色。レシートは印つき。前の版で声で入れた記録はマイクの印）に、記録をアプリの返事のカード（「記録しました」・記録ごとの行。
    行を押すと ⑥。割り勘の説明は行の下の文、直前の返事の最後に今月の状況の一行（予算を決めていて、AI の一言が無いときだけ。今月使った額は帯にあるのでくり返さない））に出し、暦の日が替わるところに日付だけの見出し（コアの `TimelineDay`）。質問の吹き出しと回答カードも
    同じ見た目。部品は `Views/TimelineConversation.swift`、送信は `EntrySend`。下端から開く。行は LazyVStack ではなく
    すべて測る並べ方（`TimelineStack`。VStack と同じ位置で、揃えを行の中まで問い合わせない）に並べ、読み込みは 50 件ずつ・300 件まで
    （記録の件数で数える。上限に届いたら月のまとめと CSV の書き出しを案内）。行の中も HStack・ViewThatFits・VStack の測り直しを
    避けて同じ形に置く Layout で組む（`ReplyRowLayout`・`SplitRowLayout`・`LeadingStack`）。LazyVStack の高さの見積もりの揺れで、
    大きな文字で開くと空に見えたため。`HomeView` の `TimelineScrollView`、確かめは `HomeTimelineLayoutTests`。帯の文字の大きさの
    上限は AX1）、記録の直後の「取り消す」（直前の送信の返事の見出し。時間では引っ込めず、次の送信・取り消し・その記録を直す・
    開き直しまで。入力欄の VoiceOver の操作にも）、長押しでの記録の削除（確認つき）、今月の支出と収入の合計。
    画面は縦向きのみ。見た目は iOS 26 の Liquid Glass に合わせ、ガラスは操作の層（帯のボタン・入力欄・月送り・主ボタン）にだけ使う。ホームの帯と入力欄は `safeAreaBar` に置き、上は `.scrollEdgeEffectStyle(.hard)`（`docs/design.md` §7）。
    ⑥ 直す（返事の行を押す・長押しのメニュー・VoiceOver の操作（行と入力欄の「直す: …」）・⑦ の記録の一覧から開くシート。金額・品目・
    支出か収入か・カテゴリ・日付を直し、そこから削除もできる。`EditEntryModel` と `EntryStore.update`。割り勘の人数は記録に持たないので直せない）。
    ホームの帯（`SummaryHeader`。「今月使った」額を大きく、予算を決めていれば細いバーと「あと ¥…」か「¥… オーバー」だけ。1 日あたり・のこりの日数・
    今日までの目安・収入・予算のボタンは出さない（帯は会話の上に常に出ているので、数字を増やすほど会話の場所が減り、使った額が埋もれるため。細かい数字は
    月のまとめと会話の質問にある）。見出しと数字から ⑦、右上の歯車から ⑧、VoiceOver では数字の要素の操作「カレンダー」）。
    月の全体の予算（② 予算を決める・⑧・会話の「今月の予算を5万にして」で決める。帯の数字は月のまとめと同じ `MonthlyReport` の数字）。予算は全体の 1 つだけ（カテゴリ別の予算はやめた。
    前の版で決めたカテゴリ別の行は `BudgetPlan.resolve` が読んで無視する。`BudgetScope.category` は古い行を読むために残す））。⑦ 月のまとめ（ホームの帯の見出しと数字から横に進む。月送り・使った額（大きく）・収入があれば収入と収支を
    小さく 1 行・前の月との差（終わった月だけ。月の途中で前の月のまる 1 か月と比べない）・予算の残り（終わった月は「余った額」、今月で超えていなければ
    1 日あたりに使える額。いまの予算に決めた月から後だけ）・カテゴリ別の割合の帯（`BreakdownCompositionBar`）と行・行からその月の記録の一覧と ⑥・
    使った額のカードの下に AI の一言（AI が使える端末だけ。無料。数字の文（コアの `RecapFacts`）だけを端末内 AI に渡して書かせ
    （`SaifuLog/AI/FoundationModelsRecapRemarkWriter`）、`AnswerSentenceCheck` で照合して合わなければ捨てる（`RecapRemarkModel`）。
    実機でのモデルの一言の確認はまだ）。
    1 日あたりの平均・今日までの目安・目安との比べは出さない（使った額と予算の残りが埋もれるため）。
    `MonthlyReportView` と `MonthlyReportModel`、数字はコアの `MonthlyReport` と `CategoryBreakdown`）。
    ⑩ カレンダー（ホームを左へスワイプした 2 枚目のページ。`HomeView` の TabView のページの形で、カレンダーからは会話のボタンでも
    戻れる。帯にカレンダーのボタンは置かず（スワイプで出るページと入口が重なるため）、VoiceOver では帯の数字の要素の操作「カレンダー」で
    開く（ページは `HomeModel.page`。開いたときと Siri の頼みを受けたときは会話）。「いくら使ったか」だけが分かるページにする:
    上にその月に使った額（大きく）と、収入があれば小さく 1 行と月のまとめへの入口、月のカレンダー（日ごとに使った額だけ。今日と選んだ日の印）、
    選んだ日の使った額の合計と記録（返事の行 `RecordedReplyRow` を記録の値の控え `DayRecord` で使い回す。押すと ⑥、長押しで削除と「毎月くり返す」）。
    見通し（今日あと・固定費・ペース）・予算の日割りの印・くり返しの予定の印・凡例・予算のボタン・「この日に記録」は出さない（数字と印が
    多いと、いちばん知りたい使った額が埋もれるため。記録の入口は会話の入力欄の 1 つにする）。アクセシビリティサイズの文字では日の一覧。
    `Views/Calendar/` の `LedgerCalendarView`・`LedgerCalendarModel`（記録の保存先だけを受け取る）、数字はコアの `LedgerCalendarMonth`。撮影用のデモの画面
    `calendar` がある（ストアの画像にはまだ入れていない）。実機でのスワイプと VoiceOver の確認はまだ）。
    初回の案内（① ようこそ →「はじめる」でホーム。予算の画面は挟まない（予算は会話の「今月の予算を5万にして」か ⑧ で決める。
    記録の無いホームの案内にその例を出し、押すと入力欄に入る）。記録がある端末には出さない。`AppRootView` と `OnboardingModel`）。
    ⑧ 設定（ホームの帯の右上の歯車から横に進む。上から「予算」（月の予算。② のシート）・「カテゴリ」（作ったカテゴリと、その画面の中の
    覚えたカテゴリ）・「毎月の記録」（くり返しの記録）・「同期」（「iCloud で同期」）・「セキュリティ」（アプリのロック）・「記録を書き出す」
    （CSV。1 行のメニューで今月・先月・今年・すべてを選んだらすぐ書き出す。中身はコアの `LedgerCSVWriter`、ファイルは `LedgerExporter` が
    メインスレッドの外で作り、共有の画面を閉じたら消す。書き出しとアカウントの確かめは設定を閉じたときだけやめる）・「このアプリについて」
    （ヘルプ・お問い合わせ・プライバシーポリシー・バージョン）。週の始まりの設定（端末の暦のまま）とライセンスの行はやめた。
    `SettingsView` と `SettingsModel`。行の頭に色の付いた印（`SettingsRowIcon`））。
    プレミアム（StoreKit の買い切りと 14 日間の体験）・無料の回数の制限（家計への質問とレシートの読み取り）・体験が終わった後の案内は
    やめ、すべての機能を無料で使える（2026-11-13。中身が薄く、無料の AI の一言と紛らわしく、仕組みが重いため。収益化は未決。
    `docs/design.md` §6）。配色は白 × 墨（モノクロ。地はライトが白に近い灰色・ダークが黒、
    操作の色は墨と白で外観で入れ替わる。色はカテゴリ・収入・注意と、設定の行の印だけ。トグルはシステムの緑のまま（主の塗りの tint を
    掛けない）。`Theme`・`Palette`、`docs/design.md` §7）。
    家計への質問（ひとこと入力と同じ入力欄。記録か質問かはコアの `InputIntentClassifier` が決め、誤って記録しないことを優先し、
    決められない文は記録せずに書き直しを案内する。端末内 AI は `SaifuLog/AI/FoundationModelsQuestionAnswerer` のツール呼び出しで期間・知りたいこと・
    カテゴリを選択肢から選ぶだけで、数字はコアの `LedgerQuestionAnswerer` が計算し、AI の一言の数字はコアの `AnswerSentenceCheck` で照合する。
    AI が使えないときはコアの `QuestionParser`。答えはホームのタイムラインの回答カード（`SaifuLog/Views/Question/`）で、保存しない。
    金額と件数の答えには前の期間との比べ（途中の期間は前の期間の同じところまで。コアの `LedgerComparison`。AI に渡す文にも書く）、今月・先月の
    金額には 6 か月の推移（`LedgerTrend`、`AnswerTrendChart`）、いちばん新しい答えには続けて聞ける質問のボタン（`QuestionFollowUp`。質問の読み取りが
    同じ質問に読める日本語の文を送る。`HomeModel.askFollowUp`）。回数の制限は無い。
    答えのカードに、元になった記録の件数と定型の注記は出さない。実機でのモデルの答え方の確認はまだ）。
    レシートの読み取り（④⑤。入力欄の左のカメラのボタン →「撮る」（VisionKit の書類カメラ）か「写真から選ぶ」（PhotosPicker）→ ⑤ の読み取り結果の
    シート。文字は `SaifuLog/Receipt/ReceiptTextRecognizer` が Vision で端末内で読み（iOS 26 の `RecognizeDocumentsRequest`、日本語に対応しないか読めなければ
    `VNRecognizeTextRequest`）、店名・日付・品目・値引き・税・合計などの見分けはコアの `ReceiptLineScanner`、照合と記録の下書きは `ReceiptReconciler`
    （外税は「税・その他」の 1 行。合わなければ ⑤ で確かめてから記録）。AI は品名とカテゴリだけを整え（iOS 27 で画像に対応したモデルは画像も、iOS 26 は
    文字だけ。`SaifuLog/AI/FoundationModelsReceiptItemRefiner`）、AI の金額は使わない（コアの `ReceiptItemRefinement`）。画像も OCR の全文も保存せず、
    記録の元の文は「レシート: 店名 合計 ¥…」の要約（`ReceiptSummary`。店名の「TEL」「電話」は後ろに番号が続くときだけ切る）。回数の制限は無い。
    ⑤ で直した内容があれば閉じる前に確かめ（⑥ と同じ）、書類カメラは 4 ページまで読んで、超えたら ⑤ に知らせる。
    状態は `SaifuLog/Views/Receipt/ReceiptResultModel`、出し入れと記録は `HomeModel`。実機でのカメラ・実際のレシートの読み取りの
    精度・モデルの整え方の確認はまだ）。
    iCloud 同期（⑧ の「iCloud で同期」。既定はオフ。自分の iCloud の私用データベース `iCloud.com.iam74k4.SaifuLog` で、同じ Apple
    アカウントの端末どうしの記録と予算をそろえる。ほかの人との共有はしない）。設定はアプリのロックと同じ専用のファイル（`LaunchSettingsStore`。
    UserDefaults ではない）に置き、`StoreHost` が最初に開く直前に読んで `ModelContainerFactory.CloudKitDatabase`（`.none` / `.private`。
    `.automatic` は置いていない）を決める。
    オンとオフで同じファイル（default.store）を開き、`cloudKitDatabase` だけを替える。切り替えは `StoreHost.setICloudSyncEnabled`
    （設定に書いて `reopen`。前の保存先の画面が消え（`StoreRootView` の onDisappear）、書き込み中の処理が終わるのを待ってから開き、
    設定の画面を開いた状態のホームに戻す。ホームのモデルは `AppRootView` が 1 回だけ作り、`HomeModel.restoreSettingsAfterStoreSwitch`
    で設定を開く）。iCloud と同期する保存先だけを開けなければ（同じファイルを `.none` でなら開けたときだけ）`.none` に戻して設定もオフに
    し、アラートで知らせる（原因に近いエラーのドメインと番号（`ICloudSyncFailure`）はアラートに出さず、ログに残す。設定を書けなければ
    それも知らせる。`.none` でも開けなければ戻さず、設定も変えずに
    再試行の画面。SwiftData は CloudKit の制約違反を中身の分からない `loadIssueModelContainer` で投げるので、エラーの種類では見分けない）。オンにする前に `CKContainer.accountStatus`（`ICloudAccountStatus`）を確かめ、
    使えなければ案内だけ。設定の状態と操作は `SettingsModel`（アカウントの問い合わせは差し替えられる。テストのプロセスは iCloud の
    entitlement を持たないので `CKContainer` を作らない）。最後に同期した時刻は出さない。ほかの端末の変更は `StoreChanges.remote`
    （`NSPersistentStoreRemoteChange`）で、月のまとめ・設定の予算を読み直す。エンタイトルメントに iCloud（CloudKit・
    コンテナ）と `aps-environment`、`SaifuLog/Info.plist` に `UIBackgroundModes` の remote-notification を足し、`make export-ipa` が値
    （`aps-environment` が production など。`release.mk` の `RELEASE_ENTITLEMENT_VALUES`）も照合する。モデルが CloudKit の制約を
    満たすことは `ModelContainerFactoryTests` で確かめている（制約のためにモデルを変えることは無かった）。記録と予算の項目はすべて CloudKit の
    暗号化フィールド（`@Attribute(.allowsCloudEncryption)`。高度なデータ保護をオンにした利用者ではエンドツーエンド）で、すべての項目に付いて
    いること（外したモデルを見逃さないことも）と、付ける前のモデルで作った保存先が移行なしで開けて記録と予算が残ることも
    `ModelContainerFactoryTests` で確かめている。項目を足すときも最初から付ける（CloudKit は後から暗号化フィールドに変えられない）。
    診断画面にアカウントの状態・いまの保存先の同期・設定の値。CloudKit のスキーマを Production に出すこと（所有者の作業。その前に
    CloudKit Console で項目の型が Encrypted になっているかを確かめる）と、実機 2 台での同期の確認はまだ（`docs/design.md` §5-3・§15、
    `docs/release-flow.md` の「Capability（iCloud など）を足すとき」の「CloudKit のスキーマ」）。
    App Store の掲載情報の下書き（`docs/app-store/`。日本語と英語の名前・サブタイトル・説明・キーワードと文字数、審査メモ、App のプライバシー
    （データの収集なし）と年齢制限（4+）の回答。App Store Connect への入力は所有者が確かめてから）と、サポート URL のページ（`docs/support.md`）。
    スクリーンショットは撮影用のデモ（`SaifuLog/ScreenshotDemo/`。**DEBUG のビルドだけ**で、`#if DEBUG` の中。起動引数
    `-SaifuLogScreenshotDemo <画面>` で、メモリの上の架空の記録・専用の UserDefaults の領域・
    決まった AI の一言とレシートで撮る画面を開き、初回の案内と診断のボタンを出さない）を
    `scripts/app-store-screenshots.sh` が 6.9 インチのシミュレータで日本語と英語で撮る（`docs/app-store/screenshots/`。透過の層は
    `scripts/screenshot-image.swift` で外す）。Release のアーカイブに入っていないことは `make archive` が印 `SaifuLog-ScreenshotDemo-v1`
    （`release.mk` の `RELEASE_SCREENSHOT_DEMO_MARKER`）で確かめる。組み立ては `ScreenshotDemoTests`。
    カテゴリの振り分け・聞き返し・修正の記憶（ひとこと入力の記録だけ。読み取った後、コアの `CategoryResolver` が次の順で決める:
    品目に作ったカテゴリの名前 → 品目に組み込みのカテゴリの名前があれば読み取ったまま → 覚えたカテゴリ（`CategoryMemory`）→ 過去の記録の
    いつものカテゴリ（コアの `CategoryHistory`。同じ品目の記録が 2 件以上で、半分を超えるカテゴリ。「その他」と聞き返し中の記録は数えない。
    読むのは新しい支出 1000 件まで、`Entry.categoryHistoryDescriptor`）→ 読み取ったカテゴリ（AI かキーワード辞書）→ 店の名前の辞書
    （レシートと同じ `ReceiptStoreDictionary`）→ 「その他」。AI が使える端末では、決まらない品目と、作ったカテゴリがあるときは読み取りや
    店の名前の辞書で決めた品目も、品目だけを端末内 AI に渡し、組み込みの表示名と作ったカテゴリの名前から選ばせる（決まらない品目を先に聞く。
    読み取りで決めた品目には作ったカテゴリの答えだけを使う。`AI/CategoryRefiner`・`FoundationModelsCategoryClassifier`（選択肢は
    `DynamicGenerationSchema`）、決め事はコアの `CategoryRefinement`。上限は全体で 3 秒。答えは覚えない）。それでも「その他」で、品目が辞書の
    「その他」の語にも当たらない支出だけ、直前の返事の行の下にカテゴリのボタン（`CategoryQuestionView`）を出して聞き返す（`Entry.needsCategoryReview` に持ち、
    開き直しても `HomeModel.refreshCategoryQuestions` で読み直す。確認待ちの一覧はやめた）。記録は止めない。直前の記録はチャットの文
    （「それ日用品」「さっきのは交際費にして」。コアの `CategoryCorrection`。数字の無い文で、カテゴリの名前のほかは前の記録を指す語・直す語・
    語尾だけ）でも直せ、`HomeModel.submit` が記録か質問かを見分ける前に読み、直前の送信の支出が 1 件か聞き返し中が 1 件のときだけ直して、
    返事のカード（`QuestionExchange.State.recategorized`）を出す（「取り消す」は残す）。返事・チャットで選んだカテゴリと ⑥ で変えたカテゴリを
    品目の言葉とともに覚える（AI への手がかりには渡さない）。保存は `LearnedCategory`（暗号化フィールド）と `LearnedCategoryStore`、状態は
    `HomeModel.categoryQuestionIDs`・`chooseCategory`。⑧ の「カテゴリ」の画面の「覚えたカテゴリ」（`LearnedCategoriesView`・
    `LearnedCategoriesModel`）で一覧・変える・忘れる（忘れても過去の記録のいつものカテゴリは使う）。実機でのモデルの選び方の確認はまだ）。
    チャットで頼む操作（記録にも質問にもしない文。コアの `ChatCommand`・`ChatCommandReader`。`HomeModel.submit` が記録か質問かを
    見分ける前に読む。誤って記録を書き換えないことを優先し、読めなければふつうの送信として読む。相手は文を送った時点の直前の送信の
    記録（`HomeModel.commandTargets`。くり返しの記録は相手にしない）で、カテゴリと金額を直すのはそのうちの支出が 1 件のときか、
    聞き返し中が 1 件のときだけ（収入は直さない）。消すときは直前の送信の記録をすべて消す。相手が無ければ（質問の後・取り消した後・
    くり返しの記録の後）「直せる直前の記録がありません」と案内して文を入力欄に戻す）。決まりで読むのは、カテゴリを変える
    （`CategoryCorrection`）・消す（数字の無い文で、消す語（「消して」「削除」「取り消して」「なかったことに」「キャンセル」など）のほかは
    前の記録を指す語・語尾だけ。「なし」「いらない」「やめて」は前の記録を指す語があるときだけで、「カテゴリなし」では消さない。
    「取り消す」と同じだが、文は入力欄に戻さない）・月の全体の予算を決める（「予算」と金額がちょうど 1 つ、カテゴリの名前が無く、
    ほかの期間（「来月」「年間」「週」「日」「12月」）や残り・超えた額の語（「残り」「超え」「オーバー」）が無く、残りが「今月」「にして」
    「に設定」などだけ。`BudgetStore.setAmount(.total)`）・金額を直す（`InputIntentClassifier` の直す語があり、直した先の金額（値引き・
    合計・おつり・ポイントは数えない）がちょうど 1 つで、金額のほかは前の記録を指す語・直す語・語尾だけ。「名前の変更 2500」
    「前のタイヤ変えて 20000」のように品目や店の名前が残る文は記録にする。「AじゃなくてB」は後ろの金額で、A が金額か前の記録を指す語
    だけのときに限る（「スタバじゃなくてドトール 400」は記録）。メモは品目だけにし（割り勘の説明は前の金額のため）、カテゴリの聞き返しと
    チャットの相手は残し、「取り消す」だけを引っ込める（⑥ と同じ理由）。割り勘の記録は 1 人分の額を記録しているので、書いた金額が
    1 人分か合計か決められず、直さずに ⑥ で直すよう案内する）。決まりで読んだ操作はすぐ行う。
    決まりで読めず、記録か質問か決められない文・前の記録を直そうとする文・金額の無い記録の文になったときだけ、AI が使える端末では
    文だけを端末内 AI に渡して操作の種類（5 つの選択肢から 1 つ。いちばん確かな選択肢を毎回選ぶ）を選ばせ（`AI/ChatCommandInterpreter`・
    `FoundationModelsChatCommandInterpreter`。上限は `AITimeouts.chatCommand` の 3 秒、失敗と時間切れは `AIFallbackLog` の
    `chatCommand`）、値は `ChatCommandReader.command(kind:in:…)` が文から読む（文に無い値と、種類に合う語の無い文では行わない）。
    AI が選んだ操作は、どれも確認のアラート（`HomeModel.pendingCommand`。返事のカードは `.commandAsked`）で選んでもらってから行い、
    キャンセルなら何も変えずに文を入力欄に戻す（`.commandCancelled`。確認の間に相手が消えていれば行わない）。返事はタイムラインの案内の
    カード（`QuestionExchange.State` の `.recategorized`・`.amountChanged`・`.removed`・`.budgetSet`・`.noTarget`・`.splitNotChanged`）、
    書き込めなければ文を入力欄に戻して `StoreFailure`（`.amountChange`・`.budgetChange` で見出しを分ける）。読めなければこれまでどおりの
    案内（書き直し・直し方・金額が見つからない）。金額の無い文などで何も記録しなかったときは、直前の送信の「取り消す」と聞き返しを
    戻す。実機でのモデルの選び方の確認はまだ）。
    記録の返事の AI の一言（Apple Intelligence を返事に使う。無料。ひとこと入力で記録した直後に、いま記録した支出（3 件まで）・その
    「その他」でない最初のカテゴリの今月の合計と件数・今月の支出の合計と件数・予算の残り（超えた額）を数字の文にし（コアの `RecordFacts`。
    収入は書かない）、その文だけを端末内 AI に渡して一言を書かせる（`AI/FoundationModelsRecordRemarkWriter`。記録の返事向けの指示文で、
    数字の例を書かず、責めない・指図しない・利用者の文の中の指示に従わない。一文に足りる長さまで。`RecordRemarkWriterFactory`）。上限は `AITimeouts.recordRemark` の 3 秒で、待つ間も入力できる。
    `RecapRemark.checked`（`AnswerSentenceCheck`）で照合して、文に無い数字と、予算の残りと超えた額・前より多いか少ないかの向きが文と
    食い違えば捨てる。直前の送信の返事にだけ、今月の状況の一行の代わりに出す（同じ数字から書くので 2 度言わない。`HomeModel.requestReplyRemark`・
    `replyRemark`、画面は `ReplyRemarkLine`。保存せず、次の送信・記録を消す・直す・カテゴリを選ぶ・予算を変える・ほかの端末の変更で消える。
    届いたときは読み上げを遮らずに読む）。AI の使えない端末と、照合に通らなかったときは定型の一行だけ（予算を決めていなければ何も出さない）。失敗と時間切れは `AIFallbackLog` の `recordRemark`。撮影用のデモは
    決まった一言を返す writer で、ホームの画面に写す。実機でのモデルの一言の確認はまだ）。
    作ったカテゴリ（利用者が 20 個まで作る。記録は ID だけを持つ `EntryCategory.custom`（rawValue は「custom:」と ID）で、名前・記号・色・
    並びは `CustomCategory`（暗号化フィールド）と `CustomCategoryStore`。一覧はコアの `CategoryCatalog` で、ホームが `CategoryCatalogModel` を
    1 つ持ち、画面へは環境の `categoryCatalog` で渡す（名前・色・記号は `CategoryCatalog` の拡張から引き、`EntryCategory.displayName` を
    直接出さない）。作ったカテゴリは文の中の名前（「衣服 3000」）・覚えたカテゴリ・過去の記録・AI の聞き直し（選択肢に作ったカテゴリの
    名前を入れる）・返事の聞き返しの「カテゴリを作る」・チャットの直し・⑥・⑤ で付く（ひとこと入力の読み取りの選択肢は組み込みの 8 種のまま）。削除すると記録は「その他」にし、覚えたカテゴリからも外す。⑧ の「カテゴリ」（`Views/Categories/` の `CategoryListView`・`CategoryListModel`、作る・直すシートは
    `CategoryEditorSheet`・`CategoryEditorModel`）。`docs/design.md` §8）。
    くり返しの記録（家賃・サブスク・給料のように毎月同じ記録。決めた日（1〜31。無い日は月末）を過ぎて最初に開いたとき（ホームが出た・前面に戻った・
    日付が変わった・足したり直したりした）に `HomeModel.recordDueRecurringEntries` が記録し、返事のカード（「くり返しの記録」。自分の吹き出しは出さない。
    元の文は空・入力元 `.recurring`）と「取り消す」で知らせる。開かなかった月も 12 か月までさかのぼる。記録した月は決まりに覚え（取り消した月も）、
    記録には印 `Entry.recurrenceKey`（「決まりの ID/202610」）を付けて、iCloud で 2 台が同じ月を記録したら記録した日時の古い 1 件を残す
    （`RecurringDuplicates`。ほかの端末の変更が届いたときと記録する前）。決まりは `RecurringEntry`（暗号化フィールド）と `RecurringEntryStore`、日付は
    コアの `RecurringSchedule`・`RecurringMonth`（西暦で数える）。⑧ の「毎月の記録」の「くり返しの記録」（`Views/Recurring/` の `RecurringListView`・
    `RecurringListModel`、足す・直すシートは `RecurringEditorSheet`・`RecurringEditorModel`）と、返事の行の長押しの「毎月くり返す」（その記録の月の次の
    月から）。自分の記録だけ。無料。`docs/design.md` §9）。
    Siri・ショートカット（`SaifuLog/Intents/`。App Intents の 2 つの操作（ひとことで記録・家計に質問。レシート・声・入力欄を開く操作は
    やめた）と App Shortcuts（言い方の英語は `Resources/AppShortcuts.xcstrings`）。どれもアプリを開いてから行う（`openAppWhenRun`）。頼みは
    `QuickActionInbox` に置き、ホームが出たら `HomeModel.performPendingQuickAction` が行う（読み取りの間・ロック中は待つ）。
    署名の無いビルドではショートカットから実行できないので、シミュレータでは ad hoc 署名で確かめる。操作の題名と説明に「Apple」の語を
    書かない（「Apple Pay」も。App Store Connect が ITMS-90626 でアップロードを弾く。`AppIntentMetadataTests`）。ウィジェットは未決（§13））。
    アプリのロック（⑧ の「セキュリティ」の「Face ID でロック」。既定はオフ。起動と裏から戻ったときに `deviceOwnerAuthentication` を求め、
    前面を離れたら隠す。オンにするときもオフにするときも認証する。状態は `AppLock`（`SaifuLogApp` で 1 つ、環境で設定へ渡す）、ロックの画面は
    シートやアラートより上の別の窓（`AppLockOverlay` の `AppLockWindow`。VoiceOver もその窓の中だけにとどめる）。設定は UserDefaults では
    なく専用のファイル（`LaunchSettingsStore`。最初のロック解除の後は読める保護。ロック中に裏で起こされると UserDefaults は空の内容を
    覚えてしまうため）。起動したときに読めなければ、読めるまで画面を隠す。家計の画面を隠している間は、くり返しの記録・
    Siri の頼みを待たせる（`HomeView`）。Face ID の利用目的は project.yml と InfoPlist.xcstrings。実機の Face ID と VoiceOver の
    確認はまだ）。⑧ に「ヘルプ・お問い合わせ」（`docs/support.md`）。
    保存先を開けないときは落とさず、ロック中なら解除を待って開き直し、それ以外は再試行の画面を出す（`StoreHost`）。
    保存先のデータ保護は NSFileProtectionComplete（ロック中は読めないようにする。SwiftData は SQLite のファイルに自分で保護を付け
    （既定は最初のロック解除の後は読める）、エンタイトルメントの既定は効かないので、開いた直後に本体と -wal とフォルダへ Complete を
    当てる（`StoreFileProtection`。-shm は記録の中身を含まず、落ちるおそれがあるので当てない）。実機での確認はまだ。
    release.yml は開発用の証明書で署名したアーカイブから提出物を作るようにしたが、証明書の Secrets の登録と、
    main で `mode=export` の照合が通るかの確認はまだ。`docs/design.md` §5-4）。
  - **未実装:** 金額が読めないときの聞き返し・CSV の読み込み・ウィジェット（未決。`docs/design.md` §13）。
  - **やめたもの（2026-11-13）:** Apple Pay の支払いの自動記録・買う前チェック・家族との家計の共有（試作）・確認待ちの一覧・
    よく使うひとこと・独自の声の入力（キーボードの音声入力で足りる）・週のふりかえり・カテゴリ別の予算・プレミアムと課金と無料の回数の制限（すべて無料にした）・週の始まりの設定・
    ライセンスの行・初回の案内の予算の画面・月のまとめの 1 日あたりの平均と今日までの目安。Siri の操作は 2 つにした
    （チャットと端末内 AI に絞るため。`docs/design.md` §15）。
  - 実機での確認の手段: release.yml の手動実行 `mode=testflight` で、develop のビルドを診断画面入りで TestFlight の
    社内テスト専用に送れるようにした（審査には出ない。Environment `release` の配備ブランチは `main` と `develop`）。
    実際に TestFlight で入れての確認はまだ（`docs/release-flow.md` の「TestFlight で実機に入れる（社内テスト）」）。
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
ただし、タグを作る tag-release.yml は最初のリリースまで Actions で無効にしてある（2026-09-30、所有者の判断）。初めて main へ
マージするときに有効に戻す（`docs/release-flow.md` の「既定のブランチ」と「初回リリース（0.1.0）の進め方」の 2）。
既定のブランチは `develop`（手動実行の workflow_dispatch に、既定のブランチにワークフローがあることが要るため）。
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
  `-only-testing:SaifuLogTests`）。SwiftData の保存・読み込みの条件や保存の失敗の扱い、保存先の開き方、
  画面のモデル（`HomeModel`）の操作など、コアに置けない部分。
  機種は `scripts/pick-simulator.sh` が、いちばん新しい iOS の iPhone を選ぶ（`TEST_DESTINATION=…` で上書きできる）
- `make test-app-ios26` — アプリ側のテストを iOS 26 の版（`IOS26_TEST_OS`、いまは iOS 26.2）のシミュレータで動かす（iOS 26 での
  SwiftData などの動作の違いを確かめる）。その版のシミュレータが無ければ止まる（`./scripts/prepare-simulator.sh 26.2` で入れる。
  ランタイムは数 GB。CI は build.yml が `scripts/prepare-simulator.sh` で入れる）
- `make check-strings` — `make build` が書き出した Debug の .stringsdata と `Localizable.xcstrings` を突き合わせ、
  足りないキー・使われていないキー・en の無いキー・ja と en の書式指定子の不一致があれば止まる（`scripts/check-strings.py`）
- `make ci` — 必須チェック `build`（build.yml）と同じ 8 種類（`make build`・`make check-strings`・`make test`・`make build-tests`・
  `make test-app`・`make test-app-ios26`・`make check-version`・`make archive ARCHIVE_SIGNING=NO BUILD_NUMBER=99999`）を順に通す。
  アプリ側のテストは最新 iOS と iOS 26.2 の両方で動かす（SwiftData などの動作の違いも確かめる）。
  **`make build` が通るだけでは CI が通るとは限らない。** PR の前はこれを通す
- `make clean` / `make open` — 生成物の削除 / Xcode で開く
- `release.mk`（Makefile の末尾で読み込む）:
  - `make version` — いまの `MARKETING_VERSION` を表示する
  - `make check-version` — `MARKETING_VERSION` と CHANGELOG 先頭の見出しの一致を確かめる
  - `make archive` — Release の .xcarchive を `build/` に作る。`BUILD_NUMBER=…` でビルド番号を上書きできる。
    既定は署名あり。`ARCHIVE_SIGNING=NO` で署名なし（build.yml と `make ci`）、`ARCHIVE_KEYCHAIN=…` で署名に使う
    キーチェーンを指定する（release.yml が、証明書を取り込んだ使い捨てのキーチェーンを渡す）。
    `INTERNAL_BUILD=YES` で社内テスト用（診断画面入り。release.yml の `mode=testflight` だけが渡す。既定は `NO`）。
    できたアプリの Info.plist にバージョン・ビルド番号・アイコンが入っているかと、診断画面が
    `INTERNAL_BUILD` のとおりに入っているか（`NO` なら入っていないか）、
    `UIBackgroundModes` に remote-notification があるか、撮影用のデモが入っていないかも確かめる（CI の build でも走る）
  - `make export-ipa` — アーカイブから .ipa を書き出すだけ（送信しない）。署名とエンタイトルメントを表示し、
    エンタイトルメントのファイル（`SaifuLog/SaifuLog.entitlements`）のキーが載っていないか、値が `release.mk` の
    `RELEASE_ENTITLEMENT_VALUES`（`aps-environment` が production など）と食い違えば止まる
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
  コミットはする。いまは次の 4 つ: データ保護（`com.apple.developer.default-data-protection = NSFileProtectionComplete`）、
  iCloud（`com.apple.developer.icloud-services = CloudKit` と `com.apple.developer.icloud-container-identifiers =
  $(ICLOUD_CONTAINER_ID)`。`Config/Base.xcconfig` で `iCloud.com.iam74k4.SaifuLog`）、`aps-environment = development`
  （App Store 向けの書き出しで production に替わる）。Info.plist の `UIBackgroundModes` の remote-notification は、ビルドの設定で
  書けないので `SaifuLog/Info.plist` に置く（どのビルドも同じファイル）。
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
  Foundation Models を使う部分（`AI/`）、Siri とショートカット（`Intents/`）、レシートの文字認識（`Receipt/`）、
  `Resources/`（Assets、String Catalog など）、
  実機での確認に使う診断画面（`Diagnostics/`）、App Store のスクリーンショットの撮影用のデモ（`ScreenshotDemo/`。DEBUG だけ）。
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
- **ロック中に裏で起こされうる経路（App を作る時点・App Intents・サイレントプッシュ）から UserDefaults を読まない。** 読めずに空の
  内容が覚えられ、ロックを解いた後も同じプロセスでは空のまま返るため。そうした経路で頼る設定（アプリのロック・iCloud 同期）は
  `LaunchSettingsStore`（保護を決めた専用のファイル）に置く。

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
- Apple Intelligence が使えない端末（非対応機種・オフ・モデル準備中）や、生成が失敗したとき・上限の時間までに
  返らない（時間切れ）ときは、キーワード辞書によるルールベース解析に切り替える。**AI が無くても記録できるアプリであること。**
  上限は `SaifuLog/AI/AITimeouts` の 1 か所に書き、AI を待つときはコアの `withDeadline` を通す（止まったモデルを待たない。
  取り消しは時間切れにしない）。
- 記録の直後に必ずアプリの返事で記録した内容と「取り消す」を出し、返事の行からすぐ直せるようにする。記録は長押しでいつでも
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
- `docs/app-store/` — App Store の掲載情報・審査メモ・App のプライバシーと年齢制限の回答の下書きとスクリーンショット、
  App Store Connect で所有者がすることの一覧（`docs/app-store/README.md`）
- `docs/support.md` — サポート URL のページ（問い合わせ先とよくある質問）
- `PRIVACY.md` — プライバシーポリシー（草案。初回リリースの手順で草案の注記を外し、施行日を入れて
  main へ入れてから審査に出す。`docs/release-flow.md` の「初回リリース（0.1.0）の進め方」）
- `SECURITY.md` — 脆弱性・プライバシーの問題の非公開の報告窓口
- `CHANGELOG.md` — 変更履歴（先頭の見出しがバージョンの検査とリリースノートに使われる）
- `LICENSE` — 権利留保。個人が自分の端末で試すための clone・ビルドだけを許可（再配布・公開・商用は不可）
