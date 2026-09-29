# プライバシーポリシー / Privacy Policy

**SaifuLog（サイフログ）**

最終更新日 / Last updated: 2026-09-29

施行日 / Effective date: 初回リリース時に確定します / To be set at the first release

> **草案 / Draft** — 本ポリシーは開発中のアプリについての草案です。初回リリースまでに実装に
> 合わせて見直し、施行日を確定します。
> This is a draft for an app still in development. It will be reviewed against the
> implementation and given an effective date before the first release.

---

## 日本語

### 収集する情報

**SaifuLog の開発者は、利用者の個人情報や家計の記録を収集しません。**

本アプリは、開発者が運営するサーバーを使いません。入力した記録を開発者や第三者へ
送信することはありません。

本アプリには、解析ツール、広告ネットワーク、クラッシュレポートの送信機能、トラッキング、
その他のサードパーティ製 SDK が含まれていません。広告は表示しません。

なお、iPhone の設定で「App デベロッパと共有」を有効にしている場合、Apple が匿名の
診断情報（クラッシュの記録など）を開発者に提供することがあります。これは Apple の
仕組みによるもので、本アプリ自身が送信するものではありません。

### 入力した家計の記録

金額、日付、カテゴリ、メモ、入力した文章といった記録と、利用者が決めた予算の金額は、iOS の
標準的な仕組み（SwiftData）を用いて、お使いの iPhone の中の本アプリ専用の領域にのみ保存されます。

iPhone のバックアップ（iCloud バックアップや、Mac・PC へのバックアップ）を有効にしている
場合、記録はバックアップの一部として保存されることがあります。これは Apple が提供する
iOS の機能で、開発者はその内容を見られません。

記録は 1 件ずつ、アプリの中で直したり削除したりできます（タイムラインの記録か、月のまとめのカテゴリ別の記録の一覧の
記録を押して開く画面で直すか「この記録を削除」、またはタイムラインの記録を長押しして「削除」）。直した金額・品目・支出か収入か・カテゴリ・日付は、元の記録に
上書きして保存します。入力した文章は直しても元のまま残り、直す画面に見比べるために表示します。入力した文章を消すには、
その記録を削除してください（1 回の入力から複数の記録ができたときは、そのすべてを削除すると消えます）。
予算は、予算を決める画面の「予算をなくす」で、確認のうえ設定なしに戻せます。

### 端末内 AI の取り扱い

入力した文章から日付・金額・カテゴリを読み取る処理には、Apple の Foundation Models
フレームワークを用います。この処理はお使いの iPhone の上で行われ、**入力した文章や記録を、
解析のために外部へ送信することはありません。**

Apple Intelligence を使えない端末では、端末内のキーワード辞書で読み取ります。この場合も
外部へ送信することはありません。

### 家計への質問

記録と同じ入力欄で家計について質問したとき（「今月カフェいくら?」など）、答えの数字は本アプリがお使いの iPhone の中の
記録から計算します。質問の文の読み取りと、答えに添える一言の作成には、Apple Intelligence を使える端末では Foundation Models を、
使えない端末では端末内のキーワード辞書を用います。**質問の文や記録、計算した答えを外部へ送信することはありません。**

質問と答えは記録として保存せず、アプリを起動している間だけアプリのメモリの中に置きます（アプリを開き直すと消えます）。
無料で質問した回数（月ごとの回数）だけを、下の「保存される設定」に保存します。

### 週のふりかえりと月のまとめ

週が替わって最初に開いたときにホームに出す「先週のふりかえり」（先週の支出・前の週との差・カテゴリ別の内訳・予算の目安と、
直近の月の支出から出す月の予算の目安）と、月のまとめの数字は、本アプリがお使いの iPhone の中の記録から計算します。
プレミアムと無料体験の間は、計算した数字を並べた文を Foundation Models に渡して一言を書かせますが、この処理もお使いの
iPhone の上で行います。**記録や計算した数字、一言を外部へ送信することはありません。** 一言は保存せず、アプリを起動している
間だけアプリのメモリの中に置きます。予算の目安は表示するだけで、利用者が保存しない限り予算は変わりません。

ふりかえりを最後に表示した日時だけを、下の「保存される設定」に保存します（同じ週にもう一度出さないため）。

### 修正の記憶（予定の機能）

利用者が記録を直した内容（例: ある言葉をどのカテゴリに分けるか）を以後の読み取りに
役立てる機能を提供する場合、その内容は端末内にのみ保存します。

### レシート・スクリーンショットの取り扱い

利用者がレシートを撮影したり、写真（スクリーンショットを含む）を選んだりしたときは、明細を読み取るために、その画像の文字を
iOS の文字認識（Vision）でお使いの iPhone の上で読みます。Apple Intelligence を使える端末では、読み取った品目の一覧（品名と金額）と
店名を Foundation Models に渡して品名とカテゴリを整えさせ、iOS 27 以降で画像の入力に対応した端末では画像も渡しますが、この処理も
お使いの iPhone の上で行います。**画像や読み取った文字を外部へ送信することはありません。**

**画像は読み取りの間だけアプリのメモリの中に置き、ファイルにも写真のアルバムにも保存しません。読み取った文字の全体も保存しません。**
保存するのは、利用者が読み取り結果を確かめて「記録する」を押したときの記録（品名・金額・カテゴリ・日付）だけで、記録の「入力した文章」には、
レシートの文字の全体ではなく「レシート: 店名 合計 ¥…」という短い要約だけを入れます（店名からも電話番号やカード番号のような数字の並びを除きます）。
レシートに印字された電話番号・住所・カード番号の一部・担当者の名前などは保存しません。

カメラへのアクセスは、利用者が「撮る」を選んだときにだけ iOS が許可を求めます。写真から選ぶときは、iOS の写真の選択の画面（アプリの外で動きます）を
使うため、写真のライブラリへのアクセスの許可は求めず、本アプリは利用者が選んだ 1 枚だけを受け取ります。

### 声での入力

入力欄のマイクのボタンを押して話すと、話した内容を iOS の音声の書き起こし（Speech フレームワークの SpeechAnalyzer）で
お使いの iPhone の上で文字にし、入力欄に入れます。**声を録音してファイルに残すことはなく、声や書き起こした文を開発者へも
Apple のサーバーへも送信しません**（この書き起こしは端末の中で行われ、声を Apple のサーバーへ送りません）。声は書き起こしの
間だけアプリのメモリの中で扱います。書き起こした文は入力欄に入れるだけで、利用者が送信ボタンを押したときだけ、ほかの入力と
同じく記録や質問として扱います（記録になった文は、上の「入力した家計の記録」と同じく保存します）。

マイクへのアクセスは、利用者がマイクのボタンを初めて押したときにだけ iOS が許可を求めます。許可はいつでも iPhone の設定で
変えられます。

書き起こしに使う日本語のモデルがお使いの iPhone に無いときは、確認のうえで Apple のサーバーからダウンロードします（モデルは
iOS が管理し、ほかのアプリと共有されます）。このダウンロードに声や記録は含まれません。モバイル回線かどうかの確認のために
回線の種類をアプリの中で調べますが、その結果を保存したり送信したりはしません。

### CSV 書き出し

設定の画面で利用者が「CSV ファイルを書き出す」を押したときだけ、選んだ期間（今月・先月・今年・すべて）の
記録（日付・時刻・支出か収入か・カテゴリ・品目・金額・入力した文章）を CSV ファイルにします。ファイルは
iOS の共有の画面に渡され、**利用者が選んだ共有先（アプリ、「ファイル」の保存先、AirDrop など）にだけ渡ります。**
本アプリが自動で書き出したり、外部へ送信したりすることはありません。開発者へ送信することもありません。

共有先に渡したファイルの取り扱いは、その共有先（アプリやサービス）に従います。家計の記録を含むため、
渡す先はご注意ください。書き出しのためにアプリの中に一時的に作ったファイルは、共有の画面を閉じると削除します
（共有の途中でアプリが終了したときは、次に設定の画面を開いたときに削除します）。

### アプリの iCloud バックアップ・同期と家族との共有（将来の任意の機能）

現在は提供していません。上に書いた iPhone 自体のバックアップとは別に、アプリの機能として
iCloud へのバックアップや同期を提供する場合の取り扱いです。

提供する場合は、利用者が有効にしたときだけ、記録は利用者自身の iCloud（Apple）の領域に
保存されます。家族やパートナーとの共有も、利用者が招待した相手とだけ、Apple の iCloud の
仕組みを通じて行います。いずれも開発者は内容を見られません。

導入する際には、このポリシーを更新します。

### 購入の取り扱い

プレミアムの購入、14日間の無料体験（価格 0 円の App 内課金）、購入の復元は、Apple の App Store の仕組み
（StoreKit）が扱います。支払いの方法やお支払いの情報を、開発者が受け取ることはありません。

本アプリは、プレミアムを使えるかを決めるために、Apple の仕組みがお使いの iPhone に持っている購入の記録
（どの商品を買ったか、買った日時、ファミリー共有によるものか、返金などで取り消されたか）を端末上で読みます。
無料体験の残りの日数も、この記録（体験を始めた日時）から端末上で計算します。**これらの購入の情報を、本アプリが
開発者や第三者へ送信することはなく、本アプリの中にも保存しません**（使えるかどうかは、そのつど Apple の仕組みから読み直します）。
購入の記録そのものは Apple が管理し、その取り扱いには Apple のプライバシーポリシーが適用されます。

「購入の復元」を押したときは、Apple の App Store と購入の記録を同期します。このとき、Apple アカウントの
確認を求められることがあります。なお、Apple は開発者に売上の集計を提供しますが、購入者の氏名や連絡先、
支払いの情報は含まれません。

### 保存される設定

初回の案内を終えたかどうか、週の始まり（日曜か月曜か）、無料体験が終わったときの案内を出したかどうか、家計への質問を
無料で使った回数（月ごとの回数。質問の文や答えは含みません）、先週のふりかえりを最後に表示した日時（ふりかえりの中身は
含みません）、レシートの読み取りを無料で使った回数（月ごとの回数。画像や読み取った内容は含みません）といったアプリの設定は、
iOS の標準的な仕組み（UserDefaults）を用いて、お使いの iPhone の中の本アプリ専用の領域にのみ保存します。
これらを外部に送信することはありません。予算の金額は設定ではなく、上の家計の記録と同じ場所に保存します。
購入したかどうかは設定には保存しません（上の「購入の取り扱い」）。

### 設定の画面から開くページ

設定の画面の「プライバシーポリシー」と「ライセンス」は、Safari で GitHub のページ（このポリシーと
ライセンスの文書）を開きます。開いたページの閲覧には、GitHub のプライバシーポリシーが適用されます。
プレミアムの画面の「利用規約（Apple の標準 EULA）」は、Safari で Apple のページを開き、その閲覧には Apple の
プライバシーポリシーが適用されます。本アプリが記録や設定をそれらのページへ送ることはありません。

### アプリの削除

SaifuLog を削除すると、端末内の記録と設定も併せて削除されます。ただし、削除より前に
作られた iPhone のバックアップには残ることがあります。

### ポリシーの変更

内容を変更する場合は、このページを更新し、最終更新日を改めます。変更の履歴は GitHub
リポジトリで確認できます。

### お問い合わせ

本ポリシーに関するご質問は、GitHub リポジトリの Issues までお寄せください。Issues は
公開されるため、個人情報や家計の記録は書き込まないでください。

https://github.com/iam74k4/SaifuLog-Apple/issues

セキュリティやプライバシーに関わる問題（記録が端末の外へ送られている疑いなど）や、公開の
場に書けないご相談は、Issues ではなく GitHub の非公開の報告窓口（リポジトリの Security
タブの「Report a vulnerability」）からお知らせください。内容は開発者とご本人だけが
見られます。詳しくは [`SECURITY.md`](SECURITY.md) を参照してください。

https://github.com/iam74k4/SaifuLog-Apple/security/advisories/new

---

## English

### Information We Collect

**The developer of SaifuLog does not collect your personal information or your household
finance records.**

The app does not use any server operated by the developer. Your records are never sent to
the developer or to any third party.

The app contains no analytics tools, no advertising networks, no crash reporting, no
tracking, and no third-party SDKs of any kind. It shows no advertisements.

If you have turned on "Share with App Developers" in your iPhone's settings, Apple may
provide the developer with anonymous diagnostic information such as crash logs. This is
done by Apple's own system, not by the app itself.

### Your Records

Your records, such as amounts, dates, categories, notes, and the text you entered, and the
budget amount you set are stored only on your own iPhone, in an area reserved for this app,
using the standard iOS mechanism (SwiftData).

If you back up your iPhone (for example with iCloud Backup, or to a Mac or PC), your
records may be included in that backup. This is an iOS feature provided by Apple, and the
developer cannot see its contents.

You can edit or delete your records one by one in the app (tap a record in the timeline, or
in a category's list in the monthly summary, to edit it or choose Delete This Record, or
long-press a record in the timeline and choose Delete). When you edit
a record, the amount, item, expense or income, category, and date you set overwrite the
original values. The text you entered stays as it was, and the edit screen shows it (as What
you sent) so you can compare. To remove that text, delete the record (if one entry created
several records, it is removed once you delete all of them). You can clear your budget with
Remove Budget on the budget screen.

### How On-Device AI Is Used

Reading the date, amount, and category from the text you enter is done with Apple's
Foundation Models framework. This processing happens on your own iPhone. **The text you
enter and your records are never sent anywhere for analysis.**

On devices where Apple Intelligence is not available, the app reads your entries with an
on-device keyword dictionary. Nothing is sent anywhere in that case either.

### Questions About Your Spending

When you ask about your spending in the same field you use for records (for example, "今月カフェいくら?"), the app
calculates the numbers in the answer from the records on your own iPhone. Reading your question and writing the short note
added to the answer are done with Apple's Foundation Models framework on devices where Apple Intelligence is available, and
with an on-device keyword dictionary otherwise. **Your question, your records, and the calculated answer are never sent
anywhere.**

Questions and answers are not saved as records. They are kept only in the app's memory while the app is running and disappear
when you reopen the app. Only the number of free questions you have used (counted per month) is stored, as described in
Settings We Store below.

### Last Week in Review and the Monthly Summary

The numbers in Last Week in Review, which appears on the home screen the first time you open the app in a new week (last week's
spending, the difference from the week before, spending by category, a weekly guide based on your budget, and a suggested monthly
budget based on your recent spending), and the numbers in the monthly summary are calculated by the app from the records on your
own iPhone. While you have Premium or the free trial, the app passes a text listing the calculated numbers to Apple's Foundation
Models framework to write a short note; this also happens on your own iPhone. **Your records, the calculated numbers, and the note
are never sent anywhere.** The note is not saved; it is kept only in the app's memory while the app is running. The suggested
budget is only displayed; your budget does not change unless you save it yourself.

Only the date and time Last Week in Review was last shown is stored, as described in Settings We Store below (so that it does not
appear again in the same week).

### Remembered Corrections (Planned Feature)

If the app offers to remember your corrections (for example, which category a certain word
belongs to) so that later entries can be read more accurately, those corrections will be
stored only on your device.

### Receipts and Screenshots

When you photograph a receipt or choose a photo (including a screenshot), the app reads the text in the image with the
iOS text recognition (Vision) on your iPhone to find its line items. On devices where Apple Intelligence is available, the list of
items read (names and amounts) and the store name are passed to Foundation Models to tidy up item names and categories, and on
iOS 27 or later with a model that accepts images, the image is passed as well; this processing also takes place on your iPhone.
**Neither the image nor the text read from it is ever sent anywhere.**

**The image is kept in the app's memory only while it is being read, and is never saved to a file or to your photo library. The full
text read from the receipt is not saved either.** Only the entries you record, after checking the result and tapping Record (item,
amount, category, and date), are saved, and their "text you entered" contains only a short summary such as "Receipt: store total
¥…", not the full text of the receipt (numbers such as phone or card numbers are removed from the store name as well). Phone
numbers, addresses, partial card numbers, staff names, and other details printed on the receipt are not saved.

iOS asks for access to the camera only when you choose Take Photo. When you choose from Photos, the app uses the iOS photo picker
(which runs outside the app), so it does not ask for access to your photo library and receives only the one photo you choose.

### Voice Input

When you tap the microphone button in the input field and speak, the app transcribes what you say on your iPhone using the
iOS speech transcription (SpeechAnalyzer in the Speech framework) and puts the text in the input field. **Your voice is never
recorded to a file, and neither your voice nor the transcribed text is ever sent to the developer or to Apple's servers** (this
transcription runs on the device and does not send your voice to Apple's servers). Your voice is handled only in the app's
memory while it is being transcribed. The transcribed text only goes into the input field; it is treated as a record or a
question, like any other entry, only when you tap Send (text that becomes a record is stored as described in Your Records
above).

iOS asks for access to the microphone only the first time you tap the microphone button. You can change this at any time in
your iPhone's Settings.

If the Japanese model used for transcription is not on your iPhone, the app downloads it from Apple's servers after asking you
(the model is managed by iOS and shared with other apps). This download does not include your voice or your records. To tell
whether you are on cellular data, the app checks the type of network connection on the device; the result is neither stored nor
sent.

### CSV Export

Only when you tap Export CSV File in Settings, the records in the period you choose (this
month, last month, this year, or all) are written to a CSV file, including the date, time,
expense or income, category, item, amount, and the text you entered. The file is handed to the
iOS share sheet and **goes only to the destination you choose there (an app, a location in
Files, AirDrop, and so on).** The app never exports or sends your records on its own, and
nothing is sent to the developer.

Once you hand the file to a destination, it is handled according to that app or service. The
file contains your financial records, so please choose the destination with care. The
temporary file the app creates for the export is deleted when the share sheet closes (if the app
quits while the share sheet is open, it is deleted the next time you open Settings).

### In-App iCloud Backup, Sync, and Sharing with Family (Future, Optional)

These features are not currently offered. This section covers iCloud backup or sync offered
as a feature of the app itself, which is separate from the iPhone backup described above.

If they are offered, your records will be stored in your own iCloud (Apple) space only when
you turn the feature on. Sharing with family members or a partner will take place only with
the people you invite, through Apple's iCloud. In either case, the developer cannot see the
contents.

This policy will be updated when these features are introduced.

### Purchases

Purchases of Premium, the 14-day free trial (an in-app purchase priced at 0 yen), and Restore
Purchases are handled by Apple's App Store system (StoreKit). The developer never receives your
payment method or payment information.

To decide whether you can use Premium, the app reads, on your device, the purchase records that
Apple's system keeps on your iPhone (which item was bought, when, whether it comes through Family
Sharing, and whether it was revoked, for example by a refund). The days left in the free trial are
also calculated on your device from these records (the date and time you started the trial). **The
app never sends this purchase information to the developer or any third party, and does not store
it in the app** (it reads it again from Apple's system each time). The purchase records themselves
are managed by Apple and covered by Apple's privacy policy.

When you tap Restore Purchases, the app syncs your purchase records with Apple's App Store, which may
ask you to confirm your Apple Account. Apple provides the developer with aggregated sales reports,
which do not include buyers' names, contact details, or payment information.

### Settings We Store

App settings, such as whether you have finished the first-launch introduction, which day your
week starts on, whether the notice at the end of the free trial has been shown, and the number of free
questions about your spending you have used (counted per month; your questions and answers are not
included), the date and time Last Week in Review was last shown (not its contents), and the number of free receipt scans you have used
(counted per month; no images or scanned contents), are stored only on your own iPhone, in an area reserved for this app, using the
standard iOS mechanism (UserDefaults). They are never transmitted
anywhere. Your budget amount is not a setting; it is stored in the same place as your records,
described above. Whether you have purchased Premium is not stored as a setting (see Purchases above).

### Pages Opened from Settings

Privacy Policy and License in Settings open pages on GitHub (this policy and the license
document) in Safari. Your visit to those pages is covered by GitHub's privacy policy. Terms of Use
(Apple's Standard EULA) on the Premium screen opens a page on Apple's website in Safari, covered by
Apple's privacy policy. The app does not send your records or settings to those pages.

### Deleting the App

Removing SaifuLog also removes the records and settings stored on your device. However, they
may remain in iPhone backups made before the app was removed.

### Changes to This Policy

If this policy changes, this page will be updated along with its "Last updated" date. The
history of changes can be viewed in the GitHub repository.

### Contact

Questions about this policy may be raised via Issues on the GitHub repository. Issues are
public, so please do not include personal information or your financial records.

https://github.com/iam74k4/SaifuLog-Apple/issues

For security or privacy problems (for example, a sign that records leave the device), or for
anything you cannot write in public, please use GitHub's private reporting channel instead of
Issues ("Report a vulnerability" on the repository's Security tab). Only the developer and you
can see the report. See [`SECURITY.md`](SECURITY.md) for details.

https://github.com/iam74k4/SaifuLog-Apple/security/advisories/new
