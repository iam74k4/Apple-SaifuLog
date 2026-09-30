# 審査メモの下書き（App Review に関する情報）

App Store Connect の「App Review に関する情報」の「メモ」と、課金アイテムごとの「審査メモ」に入れる文の下書き。
**入力は所有者が内容を確かめてから行う。** 審査は英語で読まれることが多いので、英語の文を入れる（日本語は内容を確かめるための
対訳）。連絡先（名前・電話番号・メールアドレス）は App Store Connect にだけ入れ、このリポジトリには書かない（公開のため）。

書き方の決まり:

- App Store へ出すビルドで使える機能だけを書く（無効にしている機能は書かない）。
- 審査の端末は Apple Intelligence に対応していないことがある。AI が無くても一通り試せる手順にする。
- 課金アイテムを審査に出すか（出すなら、いつ・どの理由で）は `docs/release-flow.md` の「App 内課金を審査に出す」の決め事に従う。
  出さない版では、下の「課金アイテムの審査メモ」は使わず、アプリの審査メモのプレミアムの段落も外す。

## アプリの審査メモ

App Store Connect → アプリ → バージョン → 「App Review に関する情報」→ メモ。「サインインが必要」はオフにする。
メモの上限は 4,000 文字（英語の文はいま 3,976 文字）。書き足すときは、ほかの行を詰めて収める。

### 英語（入れる文）

```text
No sign-in is required. The app has no accounts and no developer server.

HOW TO TRY IT
- Type one line in the field at the bottom of the home screen and send it, for example "ランチ 850" (lunch 850 yen) or "昨日 焼肉12000 4人で割り勘" (yesterday, dinner 12,000 yen split four ways). The app records it and replies in the timeline with what it recorded; the latest reply has an Undo button. Tap a recorded item in a reply to edit it; touch and hold to delete it.
- Ask a question in the same field, for example "今月カフェいくら?" (how much on cafes this month?). The answer is calculated by the app from the records.
- Receipts: tap the camera button on the left of the field, then "Take Photo" or "Choose from Photos". Any photo or screenshot of a receipt works.
- Voice: tap the microphone button on the right of the field and speak Japanese. The transcription is placed in the field; nothing is sent until the user taps Send.
- The gear at the top right opens Settings (Premium, Restore Purchases, monthly budget, categories, learned categories, recurring entries, Apple Pay payments, week start, Sync with iCloud, Face ID lock, CSV export). Tapping the numbers at the top of the home screen opens the Monthly Summary.
- Siri and Shortcuts: the app provides App Shortcuts such as "Record in SaifuLog" and "Ask SaifuLog"; each opens the app. The "Record Payment" action is for a Shortcuts Transaction automation (paying with Apple Pay). It runs without opening the app, keeps the amount and merchant on the device, and records them the next time the app is opened. To try it without paying, run "Record Payment" from a shortcut with any yen amount and a merchant, then open the app.
- "Last Week in Review" appears on the home timeline only the first time the app is opened in a new week, when there are records from before that week, so it may not appear during a short review.

APPLE INTELLIGENCE
AI features use Apple's on-device Foundation Models and work only on devices that support Apple Intelligence, with it turned on and its model downloaded. On other devices (including many review devices), the app reads entries and questions with a built-in keyword dictionary, so all of the examples above work without AI. Only these extras need AI: the short note added to answers, the note in Last Week in Review and the Monthly Summary (Premium), and tidying receipt item names and categories.

PERMISSIONS
- Microphone: requested only when the user first taps the microphone button. Speech is transcribed on the device with SpeechAnalyzer; audio is never recorded to a file or sent anywhere, and speech recognition permission is not requested. The Japanese speech model may need to be downloaded from Apple the first time (the app asks first). On devices without Japanese transcription, the microphone button is hidden.
- Camera: requested only when the user chooses "Take Photo" for a receipt. Images are read on the device with Vision and are never saved or sent. Choosing a photo uses the system photo picker, so no photo library permission is requested.
- Face ID: used only when the user turns on the app lock in Settings (off by default). The system performs the authentication; the app receives only the result.

DATA
Records are stored on the device. Sync with iCloud is optional and off by default; when turned on, records are stored in the user's own iCloud private database, which the developer cannot read. The app sends no data to the developer and contains no analytics, advertising, or tracking.

PREMIUM (IN-APP PURCHASES)
Premium is a one-time non-consumable purchase (not a subscription) and supports Family Sharing. Settings > Premium opens the purchase screen, which also has Restore Purchases (also in Settings). The 14-day free trial ("14-day Trial") is a separate non-consumable at price 0, started from the button on the same screen. Details are in the notes for each in-app purchase. In the sandbox, any Sandbox Apple Account can be used; no special setup is needed.
```

### 日本語（対訳）

```text
サインインは要りません。アカウントも開発者のサーバーもありません。

試し方
- ホーム画面の下の入力欄に一行を入れて送ります。例: 「ランチ 850」「昨日 焼肉12000 4人で割り勘」。記録すると、アプリがタイムラインの返事で記録した内容を見せ、いちばん新しい返事に「取り消す」が出ます。返事の記録を押すと直せ、長押しで削除できます。
- 同じ入力欄で質問できます。例: 「今月カフェいくら?」。答えの数字はアプリが記録から計算します。
- レシート: 入力欄の左のカメラのボタン →「撮る」か「写真から選ぶ」。レシートの写真やスクリーンショットなら、どれでも試せます。
- 声: 入力欄の右のマイクのボタンを押して日本語で話します。書き起こしは入力欄に入るだけで、送信を押すまで何も送りません。
- 右上の歯車で設定（プレミアム・購入の復元・月の予算・カテゴリ・覚えたカテゴリ・くり返しの記録・Apple Pay の支払い・週の始まり・iCloud で同期・Face ID でロック・CSV 書き出し）。ホーム画面の上の数字を押すと月のまとめが開きます。
- Siri・ショートカット: 「サイフログで記録」「サイフログに質問」などの App Shortcuts があり、どれもアプリを開きます。「支払いを記録」の操作は、ショートカットの「取引」のオートメーション（Apple Pay で払ったとき）のためのものです。アプリを開かずに動き、金額と店名を端末の中に置いて、次にアプリを開いたときに記録します。払わずに試すには、「ショートカット」App でショートカットに「支払いを記録」を足し、円の金額と店名を入れて実行してから、アプリを開いてください。
- 「先週のふりかえり」は、週が替わって最初に開いたときに、その週より前の記録があるときだけタイムラインに出るので、短い審査の間には出ないことがあります。

Apple Intelligence
AI の機能は Apple の端末内の Foundation Models を使い、Apple Intelligence に対応した端末で、Apple Intelligence がオンでモデルのダウンロードが済んでいるときだけ動きます。それ以外の端末（審査の端末の多く）では、内蔵のキーワード辞書で記録と質問を読むので、上の例はどれも AI なしで動きます。AI が要るのは、質問の答えに添える一言、先週のふりかえりと月のまとめの一言（プレミアム）、レシートの品名とカテゴリの整えだけです。

許可
- マイク: マイクのボタンを初めて押したときだけ求めます。声は端末の中の SpeechAnalyzer で文字にし、録音をファイルに残さず、どこへも送りません。音声認識の許可は求めません。初めて使うときに、日本語の音声モデルを Apple からダウンロードすることがあります（先に確かめます）。日本語の書き起こしに対応しない端末では、マイクのボタンを出しません。
- カメラ: レシートで「撮る」を選んだときだけ求めます。画像は端末の中の Vision で読み、保存も送信もしません。写真から選ぶときは iOS の写真の選択の画面を使うので、写真のライブラリの許可は求めません。
- Face ID: 設定でアプリのロックをオンにしたときだけ使います（既定はオフ）。認証は iOS が行い、アプリは結果だけを受け取ります。

データ
記録は端末に保存します。iCloud で同期は任意で、既定はオフです。オンにすると、利用者自身の iCloud の非公開データベースに保存し、開発者は読めません。アプリは開発者にデータを送らず、解析・広告・トラッキングは入っていません。

プレミアム（App 内課金）
プレミアムは買い切りの非消耗型（サブスクではありません）で、ファミリー共有に対応します。設定 → プレミアムで購入の画面が開き、同じ画面（と設定）に「購入の復元」があります。14 日間の無料体験（「14-day Trial」）は価格 0 の別の非消耗型で、同じ画面のボタンから始めます。詳しくは課金アイテムごとの審査メモに書きました。Sandbox では、どの Sandbox の Apple アカウントでも試せます（特別な準備は要りません）。
```

## 課金アイテムの審査メモ

App Store Connect → 収益化 → App 内課金 → 各アイテム → 「審査に関する情報」。審査用のスクリーンショットは、撮影用のデモの
`screenshots/<言語>/07-premium.png`（プレミアム）と `08-trial.png`（14 日間の体験）を使う（作り方は [`README.md`](README.md)）。

| 製品 ID | 種類 | 価格 | ファミリー共有 | 表示名（ja / en） |
|---|---|---|---|---|
| `com.iam74k4.SaifuLog.premium` | 非消耗型 | ¥1,800（日本基準） | オン | サイフログ プレミアム / SaifuLog Premium |
| `com.iam74k4.SaifuLog.trial14` | 非消耗型 | ¥0 | オフ | 14日間の無料体験 / 14-day Trial |

体験の名前: ガイドライン 3.1.1 は、価格 0 の体験の非消耗型に「XX-day Trial」の形の名前を求めている。英語の表示名はこの形に
そろえて「14-day Trial」にした（`Config/SaifuLog.storekit`。前は「14-Day Free Trial」で、「Free」が入っていた）。日本語の表示名
「14日間の無料体験」はそのまま。App Store Connect の英語のローカライズにも「14-day Trial」で入れてある。表示名を変えるときは、
App Store Connect と `Config/SaifuLog.storekit` と `SaifuLogTests/StoreKitConfigurationTests.swift` を一緒に直す。

App Store Connect の課金アイテムの説明は **55 文字まで**なので、`Config/SaifuLog.storekit` の説明（アプリの中と Xcode の StoreKit の
テストで使う文。en は 78 文字）より短い文を入れている。説明を変えるときは、この表を直してから App Store Connect に入れる。

| 製品 ID | 説明（ja） | 説明（en） |
|---|---|---|
| `com.iam74k4.SaifuLog.premium` | レシート読み取りと質問が無制限。AIのふりかえりつきの買い切り | Unlimited receipts and questions, one-time purchase. |
| `com.iam74k4.SaifuLog.trial14` | プレミアムの機能を14日間無料で試せます。自動で課金されません | Try Premium free for 14 days. No charge when it ends. |

### プレミアム（`com.iam74k4.SaifuLog.premium`）

英語（入れる文）:

```text
One-time non-consumable purchase, not a subscription. Family Sharing is supported.
What it unlocks: unlimited receipt scans (free: 5 per month, counted only when a scan is recorded) and unlimited questions about spending (free: 10 per month, asked in the home entry field, e.g. "今月カフェいくら?"); a short on-device AI note in Last Week in Review and the Monthly Summary (only on devices that support Apple Intelligence; the numbers are always calculated by the app); and budgets by category, set in Settings > Monthly Budget, with each category's spending against its budget (spent / budget, and the amount left or over) shown in the Monthly Summary.
Where to buy: Settings > Premium. Restore Purchases is on the same screen and in Settings.
```

日本語（対訳）:

```text
買い切りの非消耗型で、サブスクではありません。ファミリー共有に対応します。
できるようになること: レシートの読み取りの回数の制限がなくなる（無料は月 5 回で、記録したときだけ数える）、家計への質問の回数の制限がなくなる（無料は月 10 回。ホームの入力欄で「今月カフェいくら?」のように聞く）、先週のふりかえりと月のまとめに端末内の AI の一言が付く（Apple Intelligence に対応した端末のみ。数字はいつもアプリが計算する）、設定 → 月の予算でカテゴリ別の予算を決められ、月のまとめのカテゴリの行に、使った額と予算、残りか超えた額が出る。
購入: 設定 → プレミアム。同じ画面と設定に「購入の復元」がある。
```

### 14 日間の体験（`com.iam74k4.SaifuLog.trial14`）

英語（入れる文）:

```text
This is a free time-based trial offered as a Non-Consumable in-app purchase at price 0 named "14-day Trial", as allowed for non-subscription apps by App Review Guideline 3.1.1.
For 14 days from the purchase date (from the App Store transaction), all Premium features can be used for free. The trial is available once per Apple Account. It is never charged automatically; when it ends, Premium features simply stop working (records and budgets are kept), and the user can buy Premium if they want to continue.
Before the trial starts, the purchase screen (Settings > Premium) shows the duration, the features that will no longer be available when it ends, and that there is no charge.
```

日本語（対訳）:

```text
審査ガイドライン 3.1.1 が非サブスクのアプリに認める、価格 0 の非消耗型の App 内課金（名前は「14-day Trial」）による期間限定の無料体験です。
購入日時（App Store の記録）から 14 日間、プレミアムの機能をすべて無料で使えます。体験は 1 つの Apple アカウントにつき 1 回です。自動で課金されることはなく、終わるとプレミアムの機能が使えなくなるだけです（記録と予算は残ります）。続けて使うときは、プレミアムを購入できます。
体験を始める前に、購入の画面（設定 → プレミアム）で、期間・終わった後に使えなくなる機能・料金がかからないことを示しています。
```

## 審査に出す前に確かめること

- 審査は iPad で行われることもある（iPhone 専用のアプリも iPad で iPhone 版が拡大して動く）。iPad のシミュレータでも一通り動くこと。
- Apple Intelligence に対応しない端末（とシミュレータ）で、上の「試し方」がどれも AI なしで動くこと。
- 審査メモに書いた画面の名前（「Take Photo」「Choose from Photos」「Settings > Premium」など）が、英語の画面の表示と合っていること
  （`SaifuLog/Resources/Localizable.xcstrings` の en）。
- 課金アイテムを出すときは、Sandbox のテスターで実機に TestFlight のビルドを入れ、購入・体験・復元を一通り試したこと
  （`docs/release-flow.md` の「App 内課金（プレミアム）を審査に出す」）。
