# 審査メモの下書き（App Review に関する情報）

App Store Connect の「App Review に関する情報」の「メモ」に入れる文の下書き。
**入力は所有者が内容を確かめてから行う。** 審査は英語で読まれることが多いので、英語の文を入れる（日本語は内容を確かめるための
対訳）。連絡先（名前・電話番号・メールアドレス）は App Store Connect にだけ入れ、このリポジトリには書かない（公開のため）。

書き方の決まり:

- App Store へ出すビルドで使える機能だけを書く（無効にしている機能は書かない）。
- 審査の端末は Apple Intelligence に対応していないことがある。AI が無くても一通り試せる手順にする。
- アプリはすべて無料で、App 内課金は無い（2026-11-13 にプレミアムと 14 日間の体験をやめた。`docs/design.md` §6）。前に App Store
  Connect に登録した課金アイテムは審査に出さない（`docs/release-flow.md` の「一度だけの準備」の 8）。

## アプリの審査メモ

App Store Connect → アプリ → バージョン → 「App Review に関する情報」→ メモ。「サインインが必要」はオフにする。
メモの上限は 4,000 文字（英語の文はいま 2,986 文字）。書き足すときは、ほかの行を詰めて収める。

### 英語（入れる文）

```text
No sign-in is required. The app has no accounts and no developer server.

HOW TO TRY IT
- Type one line in the field at the bottom of the home screen and send it, for example "ランチ 850" (lunch 850 yen) or "昨日 焼肉12000 4人で割り勘" (yesterday, dinner 12,000 yen split four ways). The app records it and replies in the timeline with what it recorded; the latest reply has an Undo button. Tap a recorded item in a reply to edit it; touch and hold to delete it. Right after recording, sending "さっきのを900に直して" (change that to 900 yen), "それ日用品" (that is daily goods), or "さっきの消して" (delete that) edits or deletes the latest entry instead of recording a new one, and "今月の予算を5万にして" (set this month's budget to 50,000 yen) sets the monthly budget. When the on-device AI reads a fix worded differently from these examples, the app asks for confirmation before changing anything.
- Ask a question in the same field, for example "今月カフェいくら?" (how much on cafes this month?). The answer is calculated by the app from the records.
- Receipts: tap the camera button on the left of the field, then "Take Photo" or "Choose from Photos". Any photo or screenshot of a receipt works.
- The gear at the top right opens Settings (monthly budget, categories and learned categories, recurring entries, Sync with iCloud, Face ID lock, CSV export, help, privacy policy). Tapping the numbers at the top of the home screen opens the Monthly Summary. Swiping the home screen to the left shows the calendar.
- Siri and Shortcuts: the app provides two App Shortcuts, "Record in SaifuLog" and "Ask SaifuLog"; each opens the app.

APPLE INTELLIGENCE
AI features use Apple's on-device Foundation Models and work only on devices that support Apple Intelligence, with it turned on and its model downloaded. On other devices (including many review devices), the app reads entries and questions with a built-in keyword dictionary, so all of the examples above work without AI. Only these extras need AI: sorting items the dictionary does not know, reading chat fixes written in other ways than the examples, the short notes added to replies, answers, and the Monthly Summary, and tidying receipt item names and categories.

PERMISSIONS
- Camera: requested only when the user chooses "Take Photo" for a receipt. Images are read on the device with Vision and are never saved or sent. Choosing a photo uses the system photo picker, so no photo library permission is requested.
- Face ID: used only when the user turns on the app lock in Settings (off by default). The system performs the authentication; the app receives only the result.

DATA
Records are stored on the device. Sync with iCloud is optional and off by default; when turned on, records are stored in the user's own iCloud private database, which the developer cannot read. The app sends no data to the developer and contains no analytics, advertising, or tracking.

PRICE
The app is free. Every feature works without usage limits, and there are no in-app purchases or ads.
```

### 日本語（対訳）

```text
サインインは要りません。アカウントも開発者のサーバーもありません。

試し方
- ホーム画面の下の入力欄に一行を入れて送ります。例: 「ランチ 850」「昨日 焼肉12000 4人で割り勘」。記録すると、アプリがタイムラインの返事で記録した内容を見せ、いちばん新しい返事に「取り消す」が出ます。返事の記録を押すと直せ、長押しで削除できます。記録した直後に「さっきのを900に直して」「それ日用品」「さっきの消して」と送ると、新しい記録にせずに直前の記録を直す・消すことができ、「今月の予算を5万にして」と送ると月の予算を決められます。例と違う書き方の直しを端末内の AI が読んだときは、変える前に確かめます。
- 同じ入力欄で質問できます。例: 「今月カフェいくら?」。答えの数字はアプリが記録から計算します。
- レシート: 入力欄の左のカメラのボタン →「撮る」か「写真から選ぶ」。レシートの写真やスクリーンショットなら、どれでも試せます。
- 右上の歯車で設定（月の予算・カテゴリと覚えたカテゴリ・くり返しの記録・iCloud で同期・Face ID でロック・CSV 書き出し・ヘルプ・プライバシーポリシー）。ホーム画面の上の数字を押すと月のまとめが開きます。ホーム画面を左へスワイプするとカレンダーが出ます。
- Siri・ショートカット: 「サイフログで記録」「サイフログに質問」の 2 つの App Shortcuts があり、どちらもアプリを開きます。

Apple Intelligence
AI の機能は Apple の端末内の Foundation Models を使い、Apple Intelligence に対応した端末で、Apple Intelligence がオンでモデルのダウンロードが済んでいるときだけ動きます。それ以外の端末（審査の端末の多く）では、内蔵のキーワード辞書で記録と質問を読むので、上の例はどれも AI なしで動きます。AI が要るのは、辞書に無い品目のカテゴリの振り分け、例と違う書き方のチャットでの直しの読み取り、記録の返事・質問の答え・月のまとめに添える一言、レシートの品名とカテゴリの整えだけです。

許可
- カメラ: レシートで「撮る」を選んだときだけ求めます。画像は端末の中の Vision で読み、保存も送信もしません。写真から選ぶときは iOS の写真の選択の画面を使うので、写真のライブラリの許可は求めません。
- Face ID: 設定でアプリのロックをオンにしたときだけ使います（既定はオフ）。認証は iOS が行い、アプリは結果だけを受け取ります。

データ
記録は端末に保存します。iCloud で同期は任意で、既定はオフです。オンにすると、利用者自身の iCloud の非公開データベースに保存し、開発者は読めません。アプリは開発者にデータを送らず、解析・広告・トラッキングは入っていません。

料金
アプリは無料です。どの機能も回数の制限なく使え、App 内課金と広告はありません。
```

## 審査に出す前に確かめること

- 審査は iPad で行われることもある（iPhone 専用のアプリも iPad で iPhone 版が拡大して動く）。iPad のシミュレータでも一通り動くこと。
- Apple Intelligence に対応しない端末（とシミュレータ）で、上の「試し方」がどれも AI なしで動くこと。
- 審査メモに書いた画面の名前（「Take Photo」「Choose from Photos」「Sync with iCloud」など）が、英語の画面の表示と合っていること
  （`SaifuLog/Resources/Localizable.xcstrings` の en）。
- バージョンの「App 内課金とサブスクリプション」で、前に登録した課金アイテムを選んでいないこと。
