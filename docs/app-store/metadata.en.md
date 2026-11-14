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
| プロモーション用テキスト | 170 文字 | 152 文字 |
| 説明 | 4,000 文字 | 3,564 文字（改行を含む） |
| キーワード | 100 バイト | 89 バイト |
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
Log spending by sending one line like “ランチ 850.” Categories are sorted for you, and you can fix them by chat. Text and receipts are read on your iPhone.
```

## 説明

```text
Send one line like “ランチ 850” and it’s logged, the way you send a chat message. Categories are sorted for you, and fixes are just another message.

SaifuLog reads entries written in Japanese and records amounts in yen. The interface is also available in English.

Text and receipts are read on your iPhone. No developer server, nothing sent to the developer, and no bank or card login.

ONE-LINE ENTRY
• Send “ランチ 850,” “昨日 焼肉12000 4人で割り勘” (yesterday, yakiniku ¥12,000 split four ways), or “給料 25万,” and SaifuLog records the date, category, and amount. Multiple entries, dates, and discounts work too.
• On iPhone models that support Apple Intelligence, on-device AI reads your text; otherwise a keyword dictionary does, so you can always record.
• Splits, totals, and what’s left are calculated by the app, not by the AI.
• Undo right after each entry; tap any entry to edit it, or touch and hold to delete.
• If a category is unclear, the reply asks and remembers. Housing and clothing categories are built in, and you can create your own.
• Replies show how many times and how much you spent in that category this month. With Apple Intelligence, on-device AI writes a short note from the same numbers.

CATEGORIES AND CHAT FIXES
• Categories come from what you wrote, chose, or logged before, and store names like “ローソン.”
• On iPhone models that support Apple Intelligence, on-device AI sorts unknown items, including into categories you created.
• After an entry, send “それ日用品” (that’s daily goods), “さっきのを900に直して” (make it 900), or “さっきの消して” (delete it). “今月の予算を5万にして” sets the budget. When on-device AI reads a fix worded another way, SaifuLog asks before changing anything.

AUTOMATIC MONTHLY ENTRIES
• Rent, subscriptions, or salary can be recorded automatically each month.

SIRI AND SHORTCUTS
• Say “Record in SaifuLog” or “Ask SaifuLog” to Siri. Both also work from Shortcuts and the Action button.

RECEIPTS
• Photograph a receipt or pick a screenshot. SaifuLog reads the store, date, items, and total, sorts items into categories, and checks the total. Images are never saved or sent.

QUESTIONS ABOUT YOUR SPENDING
• Ask in the same field, like “今月カフェいくら?” (how much on cafés this month?). The app calculates the answer, compares it with the previous period, shows a six-month trend, and suggests follow-up questions.

BUDGET, CALENDAR, AND SUMMARY
• The top of the home screen shows what you’ve spent this month and, with a monthly budget, what’s left.
• Swipe left for a calendar of what you spent each day. Tap a day to see and edit its entries.
• The monthly summary shows what you spent, what’s left of your budget, spending by category, and, for past months, the change from the month before. With Apple Intelligence, it adds a short AI note.

EXPORT, SYNC, AND PRIVACY
• Export your records as a CSV file, and import it again, for example on a new iPhone.
• Sync with iCloud keeps records and budgets the same on your devices (off by default). The developer can’t see your iCloud data.
• Lock the app with Face ID, Touch ID, or your passcode.
• No analytics, no ads, no tracking. The developer receives no data from the app.

PRICING
• Free, with no ads and no in-app purchases. Every feature above works with no usage limits.

REQUIREMENTS
• iPhone with iOS 26 or later.
• On-device AI features need an iPhone that supports Apple Intelligence, with Apple Intelligence turned on and its model downloaded.
• Entries are read as Japanese text, and amounts are in yen.

Privacy Policy: https://github.com/iam74k4/Apple-SaifuLog/blob/main/PRIVACY.md
```

- **予算は月の全体の 1 つだけ:** カテゴリ別の予算はやめた（2026-11-13）。カテゴリごとに予算を決められるようには書かない（日本語と同じ）。
- **字数:** 機能を足したときに上限を超えたので、各節を短くまとめた（2026-10-01。カレンダーを足した 2026-10-02 と、チャットでの直しを足した 2026-11-13 にも詰めた。同じ日に声の入力・週のふりかえり・プレミアムなどを外した）。足すときは、ほかの節を詰めて 4,000 文字に収める。
- **料金:** すべて無料で、App 内課金は無い（2026-11-13 にプレミアムと 14 日間の体験をやめた。`docs/design.md` §6）。配信は日本だけ
  （`../release-flow.md` の「一度だけの準備」の 5。アプリは円だけを扱う。円以外の通貨は `docs/design.md` §13 で未決）。
- **例文:** 入力の例は日本語のまま書き、意味を英語で括弧に添える（アプリの画面の例も日本語のまま出している）。

## キーワード

名前（SaifuLog）・サブタイトル（budget・line）・カテゴリ（Finance）と重なる語、他社のアプリ名、価格の語（free など）は入れない。

```text
expense,spending,tracker,receipt,money,yen,japanese,chat,private,cash,diary,split,bill,ai
```

## カテゴリ・著作権・URL

日本語と同じ（[`metadata.ja.md`](metadata.ja.md) の「カテゴリ」「著作権」「URL」）。サポートのページとプライバシーポリシーは、
日本語と英語を 1 つのページに並べている。

## スクリーンショット

`docs/app-store/screenshots/en/` の 6.9 インチ（1320 × 2868）の画像。順と使い道は日本語と同じ（`01`〜`04` をストアに。
`05-calendar.png` はまだ入れない）。日本語と同じく、前の画像はやめた機能が写っていたので消し、いまはフォルダが空。撮って確かめてから
App Store Connect に入れる（[`metadata.ja.md`](metadata.ja.md) の「スクリーンショット」）。

英語の画面でも、記録の品目・質問・レシートの品名は日本語で写る（アプリは日本語の入力を読むため。説明の最初に書いている）。
英語の画面では、記録の返事・質問の答え・月のまとめの **AI の一言を写していない**（端末内 AI は一言を日本語で書くので、英語の画面に
日本語の文が混ざる。AI の使えない端末と同じく一言の無い形にした）。
