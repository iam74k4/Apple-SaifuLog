# サポート / Support

**SaifuLog（サイフログ）** — ひとことで記録できる iPhone の家計簿 / A budget book you keep in one line

[日本語](#日本語) · [English](#english)

---

## 日本語

### お問い合わせ

- **ご質問・不具合のご報告・ご要望:** GitHub の Issues にお寄せください。
  https://github.com/iam74k4/Apple-SaifuLog/issues
  **Issues は公開されます。** 個人情報や家計の記録（金額・メモ・スクリーンショットに写った記録など）は書き込まないでください。
  お使いの iPhone の機種と iOS のバージョン、アプリのバージョン（設定の画面のいちばん下）を添えていただけると助かります。
- **セキュリティやプライバシーに関わる問題、公開の場に書けないご相談:** Issues ではなく、GitHub の非公開の報告窓口
  （リポジトリの Security タブの「Report a vulnerability」）からお知らせください。内容は開発者とご本人だけが見られます。
  https://github.com/iam74k4/Apple-SaifuLog/security/advisories/new

### よくある質問

**端末内の AI は、どの iPhone で使えますか？**
端末内の AI（文章の読み取りなど）は、Apple Intelligence に対応した iPhone で、設定で Apple Intelligence がオンになっていて、
モデルのダウンロードが済んでいるときに使えます。使えない iPhone でも、キーワード辞書で読み取るので、「ランチ 850」のような
書き方なら記録も質問もできます。

**声で記録できますか？**
キーボードの音声入力（キーボードのマイクのキー）で話した文を入力欄に入れて、送信してください。

**記録を直したいです。**
記録を押すと、金額・品目・カテゴリ・日付を直す画面が開きます。送った直後の記録なら、入力欄にそのまま「それ日用品」
「さっきのを900に直して」と送っても直せます。送った直後の返事の「取り消す」を押すと、記録をなかったことにして、送った文を
入力欄に戻します。

**日ごとにいくら使ったかを見たいです。**
ホームの会話を左へスワイプすると、カレンダーが出ます。日を押すと、その日の記録が出ます。

**ウィジェットで今月の額を見たいです。**
ホーム画面かロック画面を長押しして「編集」（ロック画面は「カスタマイズ」）から、サイフログの「今月使った額」を足してください。
今月使った額と、予算を決めていれば残りの額が出ます。ロック画面では、iPhone のロック中は金額を隠します。アプリのロック
（設定の「Face ID でロック」）をオンにしている間は、どのウィジェットにも金額を出しません。数字は、サイフログを開いて記録したり
予算を変えたりしたときに新しくなります。ウィジェットを押すと、記録の入力欄が開きます。

**カメラを許可しなかったので、レシートを撮れません。**
iPhone の「設定」→「サイフログ」で、カメラの許可を変えられます。写真から選ぶときは、写真のライブラリの許可は要りません。

**料金はかかりますか？**
かかりません。すべての機能を無料で、回数の制限なく使えます。広告とアプリ内課金もありません。

**記録をほかの iPhone でも見たいです。**
設定の「iCloud で同期」をオンにすると、同じ Apple アカウントの iPhone どうしで記録と予算をそろえます（既定はオフ）。
記録を CSV ファイルに書き出して、ほかのアプリやファイルに保存することもできます（設定の「CSV ファイルを書き出す」）。

**機種変更のとき、記録を新しい iPhone に移したいです。**
どちらかの方法で移せます。
- 「iCloud で同期」: 前の iPhone でオンにして同期が済んでから、新しい iPhone でも同じ Apple アカウントでオンにします。
- CSV ファイル: 前の iPhone で、設定の「記録を書き出す」から「すべて」を書き出して「ファイル」などに保存し、新しい iPhone の
  設定の「CSV から読み込む」でそのファイルを選びます。同じ記録がすでにあれば、重ねて入れません。

iPhone 全体のバックアップ（iCloud バックアップやパソコンへのバックアップ）から戻したときも、記録は戻ります。

**記録を消したいです。**
記録を長押しして「削除」を選ぶか、記録を押して開く画面の「この記録を削除」から消せます。送った直後の記録なら、「さっきの消して」と
送っても消せます。消した記録は元に戻せません。アプリを削除すると、iPhone の中の記録も消えます（「iCloud で同期」をオンに
していたときは、iCloud に保存した記録は残ります）。

**入力した記録は、どこかへ送られますか？**
開発者へは送りません。開発者のサーバーはありません。詳しくはプライバシーポリシーをご覧ください。
https://github.com/iam74k4/Apple-SaifuLog/blob/main/PRIVACY.md

---

## English

### Contact

- **Questions, bug reports, and requests:** Please open an issue on GitHub.
  https://github.com/iam74k4/Apple-SaifuLog/issues
  **Issues are public.** Please don't include personal information or your records (amounts, notes, or screenshots that show your
  records). It helps to include your iPhone model, iOS version, and the app version (at the bottom of Settings).
- **Security or privacy issues, or anything you can't post publicly:** Please use GitHub's private reporting channel instead of Issues
  ("Report a vulnerability" on the repository's Security tab). Only the developer and you can see it.
  https://github.com/iam74k4/Apple-SaifuLog/security/advisories/new

### Frequently asked questions

**Which iPhone models can use the on-device AI?**
On-device AI (such as reading your text) works on iPhone models that support Apple Intelligence, with Apple Intelligence turned on in
Settings and its model downloaded. On other iPhone models, a keyword dictionary reads your entries, so lines like “ランチ 850” still work
for both entries and questions. Entries are read as Japanese text.

**Can I record by voice?**
Use the keyboard's dictation (the microphone key on the keyboard) to put what you say in the entry field, then send it.

**How do I fix an entry?**
Tap an entry to edit its amount, item, category, and date. Right after sending, you can also type a fix into the entry field, such as
“それ日用品” (make it daily goods) or “さっきのを900に直して” (change it to 900). Undo in the reply right after sending removes the entry
and puts your text back in the entry field.

**How do I see how much I spent each day?**
Swipe left on the home conversation to show the calendar. Tap a day to see its entries.

**I want to see this month's spending in a widget.**
Touch and hold the Home Screen and tap Edit (or touch and hold the Lock Screen and tap Customize), then add SaifuLog's “Spent This
Month” widget. It shows what you've spent this month and, if you've set a budget, what's left. Lock Screen widgets hide the amounts
while your iPhone is locked. While app lock (Lock with Face ID in Settings) is on, no widget shows amounts. The figures update when
you open SaifuLog and record something or change your budget. Tapping the widget opens the entry field.

**I didn't allow the camera, so I can't photograph receipts.**
You can change camera access in the iPhone Settings app under SaifuLog. Choosing a photo doesn't require photo library access.

**Does it cost anything?**
No. Every feature is free, with no usage limits. There are no ads and no in-app purchases.

**I want to see my records on another iPhone.**
Turn on Sync with iCloud in Settings to keep records and budgets the same on iPhone devices signed in to the same Apple Account (off by
default). You can also export your records as a CSV file (Export CSV File in Settings).

**How do I move my records to a new iPhone?**
Use either of these:
- Sync with iCloud: turn it on on your old iPhone and let it finish syncing, then turn it on on the new iPhone with the same Apple
  Account.
- A CSV file: on your old iPhone, export All from Export Entries in Settings and save the file (for example, in Files). On the new
  iPhone, choose the file with Import CSV File in Settings. Entries that are already there aren't added twice.

Restoring a full iPhone backup (iCloud Backup or a backup on your computer) also restores your entries.

**How do I delete records?**
Touch and hold a record and choose Delete, or tap it and use Delete This Record. Right after sending, you can also type “さっきの消して”
(delete the last one). Deleted entries can't be restored. Deleting the app deletes the records on your iPhone (records saved in iCloud
with Sync with iCloud stay in iCloud).

**Are my records sent anywhere?**
Not to the developer; there is no developer server. See the privacy policy for details.
https://github.com/iam74k4/Apple-SaifuLog/blob/main/PRIVACY.md
