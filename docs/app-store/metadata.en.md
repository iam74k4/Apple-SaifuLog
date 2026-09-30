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
| プロモーション用テキスト | 170 文字 | 133 文字 |
| 説明 | 4,000 文字 | 3,630 文字（改行を含む） |
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
Log spending by sending one line like “ランチ 850.” Your text, receipts, and voice are read on your iPhone. There’s no developer server.
```

## 説明

```text
Send one line like “ランチ 850” and it’s logged. SaifuLog is a budget book you keep the way you send a chat message.

SaifuLog reads entries written in Japanese and records amounts in yen. The interface is also available in English.

Your text, receipts, and voice are all read on your iPhone. There is no developer server, and your records are never sent to the developer.

ONE-LINE ENTRY
• Send “ランチ 850,” “昨日 焼肉12000 4人で割り勘” (yesterday, yakiniku ¥12,000 split four ways), or “給料 25万,” and SaifuLog records the date, category, and amount.
• It understands several entries in one line, dates like “昨日” (yesterday) or “9/26,” bill splitting, and discounts.
• On iPhone models that support Apple Intelligence, on-device AI reads your text. Otherwise a keyword dictionary reads it, so you can always record without AI.
• Splits, totals, and what’s left are calculated by the app, not by the AI.
• Right after each entry you can Edit or Undo. Tap an entry any time to edit it, or touch and hold to delete it.

RECEIPTS
• Take a photo or choose one (screenshots too). SaifuLog reads the store, date, items, and total, and sorts each item into a category.
• It checks the items against the receipt total so you can confirm before recording.
• Images are read on your iPhone and are never saved or sent.

VOICE INPUT
• Tap the microphone and speak. Your words are transcribed on your iPhone and placed in the entry field, and you send it yourself.
• Your voice is never saved or sent. The Japanese speech model may need to be downloaded the first time. On iPhone models without Japanese transcription, the microphone button doesn’t appear.

QUESTIONS ABOUT YOUR SPENDING
• In the same field, ask things like “今月カフェいくら?” (how much on cafés this month?).
• The app calculates the numbers from your records and shows the period and how many entries the answer is based on.

BUDGET AND REVIEWS
• Set a monthly budget to see what’s left this month and how much you can spend per day.
• The monthly summary shows spending, income, balance, daily average, the change from last month, and a chart by category.
• The first time you open the app in a new week, Last Week in Review sums up last week’s spending and top categories.

EXPORT AND SYNC
• Export your records as a CSV file that spreadsheet apps open correctly.
• Turn on Sync with iCloud in Settings to keep records and budgets the same on your iPhone devices with the same Apple Account (off by default). The developer can’t see your iCloud data.

PRIVACY
• Records are stored on your iPhone (and in your own iCloud if you turn on sync).
• No analytics, no ads, no tracking. The developer receives no data from the app.

PRICING
• Free to download, with no ads. One-line entry (including AI reading), voice input, budgets, summaries, CSV export, and iCloud sync are free with no limits.
• Free includes 5 receipt scans a month (only scans you record count) and 10 questions a month.
• Premium is a one-time purchase of ¥1,800 in Japan, not a subscription. It removes the limits on receipts and questions, adds a short on-device AI note to your reviews (on iPhone models that support Apple Intelligence), and lets you set budgets by category. Family Sharing is supported.
• Try Premium free for 14 days (once per Apple Account). You won’t be charged when the trial ends.

REQUIREMENTS
• iPhone with iOS 26 or later.
• On-device AI features need an iPhone that supports Apple Intelligence, with Apple Intelligence turned on and its model downloaded.
• Entries are read as Japanese text, and amounts are in yen.

Privacy Policy: https://github.com/iam74k4/SaifuLog-Apple/blob/main/PRIVACY.md
```

- **カテゴリ別の予算:** 「lets you set budgets by category」とだけ書き、使った額と比べられるようには書かない（日本語と同じ）。
- **価格:** 「¥1,800 in Japan」と国を添える。ほかの国や地域で配信するなら、価格はその国の App Store の表示になる。配信する国を
  決めたら、この行を見直す（アプリは円だけを扱う。円以外の通貨は `docs/design.md` §13 で未決）。
- **例文:** 入力の例は日本語のまま書き、意味を英語で括弧に添える（アプリの画面の例も日本語のまま出している）。
- **体験の名前:** 説明の文では「Try Premium free for 14 days」と書く。課金アイテムそのものの英語の表示名（App Store の購入の確認に
  出る名前）は、ガイドライン 3.1.1 の形の「14-day Trial」で、説明とは別に App Store Connect の課金アイテムの英語のローカライズに入れる
  （`Config/SaifuLog.storekit` と同じ。[`review-notes.md`](review-notes.md) の「課金アイテムの審査メモ」。入力は所有者の作業で、
  [`README.md`](README.md) の「App Store Connect で所有者がすること」）。

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
