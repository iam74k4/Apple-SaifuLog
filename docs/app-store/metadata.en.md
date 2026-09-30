# App Store の掲載情報（英語）の下書き

App Store Connect の「英語（米国）」のローカライズに入れる文の下書き。**入力は所有者が内容を確かめてから行う。**
決まり（出していない機能を書かない・名前とサブタイトルとスクリーンショットに価格を入れない・キーワードの決まり）は
[`metadata.ja.md`](metadata.ja.md) と同じ。

**英語の掲載で必ず伝えること: 入力の読み取りは日本語の文が前提で、金額は円。** 英語の画面は、英語を優先する端末で日本語の入力を
する人のためのもの（`docs/design.md` §10）。キーワード辞書・日付の言い回し・AI への指示は日本語の文を前提にしていて、英語の文の
読み取りは作っていないので、英語の文を読めるように書かない。説明の最初の段落と「REQUIREMENTS」に書いている。

## 文字数

| 項目 | 上限 | いまの長さ |
|---|---|---|
| アプリ名 | 30 文字 | 8 文字 |
| サブタイトル | 30 文字 | 18 文字 |
| プロモーション用テキスト | 170 文字 | 169 文字 |
| 説明 | 4,000 文字 | 3,979 文字（改行を含む） |
| キーワード | 100 バイト | 90 バイト |
| 著作権 | — | 14 文字 |

## アプリ名（提案）

日本語の名前は「サイフログ」で登録済み。英語のローカライズの名前は **「SaifuLog」** を提案する（ホーム画面の英語の表示名
`CFBundleDisplayName` の en と同じ。カタカナを読めない人にも読め、財布（サイフ）の記録（ログ）の由来もそのまま）。

```text
SaifuLog
```

App Store の名前はストア全体で重ならないものしか登録できない。「SaifuLog」が使われていたら、説明の語を足した
「SaifuLog: One-Line Budget」（25 文字）を次の案にする（ホーム画面の表示名は「SaifuLog」のまま）。

## サブタイトル

```text
Budget in one line
```

`docs/design.md` §10 の案のまま。別の案: 「One-line expense log」（20 文字）。

## プロモーション用テキスト

```text
Log spending by sending one line like “ランチ 850,” or just by paying with Apple Pay. Text, receipts, and voice are read on your iPhone. No developer server, no bank login.
```

## 説明

```text
Send one line like “ランチ 850” and it’s logged, the way you send a chat message. Paying with Apple Pay can log spending for you.

SaifuLog reads entries written in Japanese and records amounts in yen. The interface is also available in English.

Text, receipts, and voice are read on your iPhone. There is no developer server, records are never sent to the developer, and no bank or card login is needed.

LOG BY PAYING (APPLE PAY)
• Set up a Shortcuts automation once. When you pay with Apple Pay, SaifuLog receives the amount and merchant and records it the next time you open the app. Settings shows how.
• The category comes from the merchant name. For unknown merchants SaifuLog asks once and remembers. Undo right away if something’s wrong.

ONE-LINE ENTRY
• Send “ランチ 850,” “昨日 焼肉12000 4人で割り勘” (yesterday, yakiniku ¥12,000 split four ways), or “給料 25万,” and SaifuLog records the date, category, and amount. Several entries in one line, dates, and discounts work too.
• On iPhone models that support Apple Intelligence, on-device AI reads your text; otherwise a keyword dictionary does, so you can always record.
• Splits, totals, and what’s left are calculated by the app, not by the AI.
• Edit or Undo right after each entry, or touch and hold an entry to delete it.
• When a category isn’t clear, the reply asks and remembers your choice. Create your own categories such as rent or clothing.
• Items you log often appear as buttons above the entry field.

AUTOMATIC MONTHLY ENTRIES
• Rent, subscriptions, or salary can be recorded automatically each month.

SIRI AND SHORTCUTS
• Say “Record in SaifuLog” to Siri. Questions, receipts, and voice input also work from Siri, Shortcuts, and the Action button.

RECEIPTS AND VOICE
• Photograph a receipt or pick a screenshot. SaifuLog reads the store, date, items, and total, sorts items into categories, and checks them against the total. Images are never saved or sent.
• Speak into the microphone and your words are transcribed on your iPhone into the entry field. You send it yourself.

QUESTIONS ABOUT YOUR SPENDING
• Ask in the same field, like “今月カフェいくら?” (how much on cafés this month?). The app calculates the answer, compares it with the previous period, shows a six-month trend, and suggests follow-up questions.

BUDGET AND REVIEWS
• A monthly budget shows what’s left, a daily allowance, and whether you’re above or below today’s target.
• The monthly summary shows spending, income, balance, daily average, and spending by category.
• Each new week, Last Week in Review sums up last week’s spending.

EXPORT, SYNC, AND PRIVACY
• Export your records as a CSV file.
• Sync with iCloud keeps records and budgets the same on your devices (off by default). The developer can’t see your iCloud data.
• Lock the app with Face ID, Touch ID, or your passcode.
• No analytics, no ads, no tracking. The developer receives no data from the app.

PRICING
• Free to download, with no ads. One-line entry (including AI reading), Apple Pay logging, recurring entries, voice input, budgets, summaries, CSV export, and iCloud sync are free with no limits.
• Free includes 5 receipt scans a month (only scans you record count) and 10 questions a month.
• Premium is a one-time purchase of ¥1,800 in Japan, not a subscription. It removes the limits on receipts and questions, adds a short on-device AI note to your reviews (on iPhone models that support Apple Intelligence), and adds budgets by category. Family Sharing is supported.
• Try Premium free for 14 days (once per Apple Account). You won’t be charged when the trial ends.

REQUIREMENTS
• iPhone with iOS 26 or later.
• On-device AI features need an iPhone that supports Apple Intelligence, with Apple Intelligence turned on and its model downloaded.
• Apple Pay logging needs a Shortcuts automation and records payments in yen only.
• Entries are read as Japanese text, and amounts are in yen.

Privacy Policy: https://github.com/iam74k4/SaifuLog-Apple/blob/main/PRIVACY.md
```

- **カテゴリ別の予算:** 字数（上限 4,000 文字）のため「adds budgets by category」とだけ書く。ホームの帯や質問の答えに出るようには書かない（日本語と同じ）。
- **字数:** 機能を足したときに上限を超えたので、各節を短くまとめた（2026-10-01）。足すときは、ほかの節を詰めて 4,000 文字に収める。
- **価格:** 「¥1,800 in Japan」と国を添える。配信は日本だけにした（`../release-flow.md` の「一度だけの準備」の 5）。ほかの国や地域にも出すなら、
  価格はその国の App Store の表示になるので、この行を見直す（アプリは円だけを扱う。円以外の通貨は `docs/design.md` §13 で未決）。
- **例文:** 入力の例は日本語のまま書き、意味を英語で括弧に添える（アプリの画面の例も日本語のまま出している）。
- **体験の名前:** 説明の文では「Try Premium free for 14 days」と書く。課金アイテムそのものの英語の表示名（App Store の購入の確認に
  出る名前）は、ガイドライン 3.1.1 の形の「14-day Trial」で、説明とは別に App Store Connect の課金アイテムの英語のローカライズに入れる
  （`Config/SaifuLog.storekit` と同じ。[`review-notes.md`](review-notes.md) の「課金アイテムの審査メモ」。App Store Connect に入力済み）。

## キーワード

名前（SaifuLog）・サブタイトル（budget・line）・カテゴリ（Finance）と重なる語、他社のアプリ名、価格の語（free など）は入れない。

```text
expense,spending,tracker,receipt,money,yen,japanese,voice,private,cash,diary,split,bill,ai
```

## カテゴリ・著作権・URL

日本語と同じ（[`metadata.ja.md`](metadata.ja.md) の「カテゴリ」「著作権」「URL」）。サポートのページとプライバシーポリシーは、
日本語と英語を 1 つのページに並べている。

## スクリーンショット

`docs/app-store/screenshots/en/` の 6.9 インチ（1320 × 2868）の画像。順と使い道は日本語と同じ（`01`〜`06` をストアに、
`07-premium.png` と `08-trial.png` は課金アイテムの審査用）。

英語の画面でも、記録の品目・質問・レシートの品名は日本語で写る（アプリは日本語の入力を読むため。説明の最初に書いている）。
英語の画面では、質問の答えとふりかえり・月のまとめの **AI の一言を写していない**（端末内 AI は一言を日本語で書くので、英語の画面に
日本語の文が混ざる。AI の使えない端末と同じく一言の無い形にした）。
