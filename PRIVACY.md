# プライバシーポリシー / Privacy Policy

**SaifuLog（サイフログ）**

最終更新日 / Last updated: 2026-11-13

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
送信することはありません（利用者が設定で「iCloud で同期」をオンにしたときは、記録を利用者自身の iCloud（Apple）に
保存します。開発者はその内容を見られません。下の「iCloud での同期」）。

本アプリには、解析ツール、広告ネットワーク、クラッシュレポートの送信機能、トラッキング、
その他のサードパーティ製 SDK が含まれていません。広告は表示しません。

なお、iPhone の設定で「App デベロッパと共有」を有効にしている場合、Apple が匿名の
診断情報（クラッシュの記録など）を開発者に提供することがあります。これは Apple の
仕組みによるもので、本アプリ自身が送信するものではありません。

### 入力した家計の記録

金額、日付、カテゴリ、メモ、入力した文章といった記録と、利用者が決めた予算の金額は、iOS の
標準的な仕組み（SwiftData）を用いて、お使いの iPhone の中の本アプリ専用の領域に保存されます。設定の「iCloud で同期」が
オフ（既定）のあいだは、この iPhone の中にのみ保存されます。オンにした場合の取り扱いは、下の「iCloud での同期」のとおりです。

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

ひとこと入力の記録のカテゴリは、本アプリが、作ったカテゴリの名前・覚えたカテゴリ・お使いの iPhone の中の過去の記録（品目とカテゴリ）・
店の名前の辞書から決めます。過去の記録はこの判断のためにお使いの iPhone の中で読むだけで、外部へ送信することはありません。
それでもカテゴリが決まらないとき（と、作ったカテゴリがあるとき）は、その記録の品目だけと、カテゴリの名前の一覧（作ったカテゴリの
名前を含む）を端末内 AI に渡して、カテゴリを選ばせます。金額・日付・覚えたカテゴリは AI に渡しません。この処理もお使いの iPhone の
上で行い、AI の答えを覚えることはありません。

チャットの文で直前の記録を直す・消す・月の予算を決めるとき（「さっきのを900に直して」など）は、本アプリが文を読み取ります。
本アプリの決まりで読み取れない文は、Apple Intelligence を使える端末では、送った文だけを端末内 AI に渡し、どの操作を頼んでいるかを
選ばせます（金額やカテゴリは本アプリが送った文から読み取ります）。記録や予算の中身は AI に渡しません。この処理もお使いの iPhone の
上で行い、**送った文を外部へ送信することはありません。**

### 家計への質問

記録と同じ入力欄で家計について質問したとき（「今月カフェいくら?」など）、答えの数字は本アプリがお使いの iPhone の中の
記録から計算します。質問の文の読み取りと、答えに添える一言の作成には、Apple Intelligence を使える端末では Foundation Models を、
使えない端末では端末内のキーワード辞書を用います。**質問の文や記録、計算した答えを外部へ送信することはありません。**

質問と答えは記録として保存せず、アプリを起動している間だけアプリのメモリの中に置きます（アプリを開き直すと消えます）。

### 記録の返事の一言

ひとこと入力で記録した直後に、Apple Intelligence を使える端末では、いま記録した支出（品目・金額・カテゴリ）、そのカテゴリの今月の
合計と件数、今月の支出の合計と件数、予算の残りを本アプリがお使いの iPhone の中で計算して文にし、その文を Foundation Models に渡して
一言を書かせます。この処理もお使いの iPhone の上で行い、**記録や計算した数字、一言を外部へ送信することはありません。** 一言は保存せず、
アプリを起動している間だけアプリのメモリの中に置きます。

### 月のまとめ

月のまとめの数字（使った額・収入・収支・前の月との差・カテゴリ別の内訳・予算の残り）は、本アプリがお使いの iPhone の中の記録から
計算します。Apple Intelligence を使える端末では、計算した数字を並べた文を Foundation Models に渡して一言を書かせますが、この処理もお使いの
iPhone の上で行います。**記録や計算した数字、一言を外部へ送信することはありません。** 一言は保存せず、アプリを起動している
間だけアプリのメモリの中に置きます。

### 覚えたカテゴリ（修正の記憶）

記録の返事でカテゴリを選んだとき（「その他」になった記録に出るカテゴリのボタン）と、記録の直後に「それ日用品」の
ような文を送ってカテゴリを直したときと、記録を直す画面でカテゴリを変えたときは、その記録の品目の言葉（例: 「ユニクロ」）と選んだカテゴリの組を覚え、次から同じ言葉の記録をそのカテゴリで記録します。
覚えた言葉とカテゴリは、上の「入力した家計の記録」と同じ場所（お使いの iPhone の中の本アプリ専用の保存先。「iCloud で同期」を
オンにしているときは、記録と同じく暗号化フィールドとして利用者自身の iCloud にも）に保存し、**開発者や第三者へ送信することは
ありません。** 端末内 AI に渡すこともありません（読み取った後に、本アプリが覚えたカテゴリへ置き換えます）。
覚えたものは、設定の「覚えたカテゴリ」でいつでも確かめ、カテゴリを変えたり、1 つずつ、またはすべて忘れさせたりできます。

カテゴリを選ぶ必要がある記録には、カテゴリを聞き返している印を記録と一緒に保存します（「iCloud で同期」をオンにしているときは、記録と一緒に
同期します）。カテゴリを選ぶか、記録を削除すると消えます。

### 作ったカテゴリ

設定の「カテゴリ」や記録の返事から作ったカテゴリ（名前・記号・色・並び順・作った日時・直した日時）は、上の「入力した家計の記録」と
同じ場所（お使いの iPhone の中の本アプリ専用の保存先。「iCloud で同期」をオンにしているときは、記録と同じく暗号化フィールドとして
利用者自身の iCloud にも）に保存し、**開発者や第三者へ送信することはありません。** 記録にはカテゴリの名前ではなく、作ったカテゴリを
見分ける番号だけを保存します。記録のカテゴリを端末内 AI に選ばせるときと、記録の返事の一言、月のまとめの一言、質問の答えの一言を
端末内 AI に書かせるときは、ほかのカテゴリと同じく作ったカテゴリの名前も渡しますが、この処理もお使いの iPhone の上で行います。CSV に書き出すときは、カテゴリの列に作ったカテゴリの名前を
書きます。カテゴリを削除すると、そのカテゴリの記録は「その他」になります。

### くり返しの記録

設定の「くり返しの記録」や記録の長押しから作った、毎月同じ記録の決まり（金額・品目・支出か収入か・カテゴリ・毎月の日・最初の月・記録を
済ませた月・作った日時・直した日時）は、上の「入力した家計の記録」と同じ場所（お使いの iPhone の中の本アプリ専用の保存先。「iCloud で同期」を
オンにしているときは、記録と同じく暗号化フィールドとして利用者自身の iCloud にも）に保存し、**開発者や第三者へ送信することはありません。**
決めた日を過ぎてアプリを開いたときに、本アプリがお使いの iPhone の中で記録を作ります（サーバーは使いません）。作った記録は、ほかの記録と
同じく保存し、どの決まりのどの月の分かを見分ける印を付けます（iCloud で同期している端末どうしで同じ月を二重に記録したときに、1 件にまとめるため）。
決まりをやめても、作った記録は残ります。

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

### Siri・ショートカット

Siri・ショートカット・Spotlight・アクションボタンから本アプリの操作（「ひとことで記録」「家計に質問」）を使うと、話したり入れたりした文が、
Siri とショートカットの仕組み（Apple）を通って本アプリに渡されます。Siri で話した声の扱いは、Apple のプライバシーポリシーと Siri の設定に従います。
本アプリは、渡された文を入力欄に打った文と同じく扱い（記録や質問になった文は、上の「入力した家計の記録」と同じく保存します）、開発者や第三者へ
送信することはありません。操作はどれも本アプリを開いてから行い、記録した内容はアプリの中の返事で確かめられます。

### CSV 書き出し

設定の画面で利用者が「CSV ファイルを書き出す」を押したときだけ、選んだ期間（今月・先月・今年・すべて）の
記録（日付・時刻・支出か収入か・カテゴリ（作ったカテゴリはその名前）・品目・金額・入力した文章）を CSV ファイルにします。ファイルは
iOS の共有の画面に渡され、**利用者が選んだ共有先（アプリ、「ファイル」の保存先、AirDrop など）にだけ渡ります。**
本アプリが自動で書き出したり、外部へ送信したりすることはありません。開発者へ送信することもありません。

共有先に渡したファイルの取り扱いは、その共有先（アプリやサービス）に従います。家計の記録を含むため、
渡す先はご注意ください。書き出しのためにアプリの中に一時的に作ったファイルは、共有の画面を閉じると削除します
（共有の途中でアプリが終了したときは、次に設定の画面を開いたときに削除します）。

### iCloud での同期（任意）

設定の「iCloud で同期」は、既定ではオフです。利用者がオンにしたときだけ、記録（金額・日付・カテゴリ・メモ・入力した文章など、
上の「入力した家計の記録」と同じもの）と予算の金額と覚えたカテゴリと作ったカテゴリとくり返しの記録を、Apple の iCloud の利用者自身の領域（CloudKit の非公開データベース）に
保存し、同じ Apple アカウントでサインインしている端末どうしでそろえます。オンにした時点でお使いの端末にある記録も、iCloud に
保存されます。上に書いた iPhone 自体のバックアップとは別の機能です。

- **開発者は、利用者の iCloud に保存された内容を見られません。** 記録は開発者のサーバーを経由せず、Apple の iCloud と
  利用者の端末のあいだでだけやり取りされます。iCloud での保存には、Apple のプライバシーポリシーと iCloud の利用規約が
  適用されます。
- **暗号化について。** 記録と予算の中身（本アプリが保存する項目のすべて。金額・収入か支出か・日付・カテゴリ・メモ・入力した
  文章・入力の方法（文字・レシート・くり返しの記録など）・記録した日時と、予算の対象・金額・決めた日時と、覚えたカテゴリの言葉・カテゴリ・覚えた日時と、
  作ったカテゴリの名前・記号・色・並び順・作った日時・直した日時と、くり返しの記録の決まりのすべての項目と記録に付けた印）は、
  CloudKit の暗号化フィールドとして、お使いの端末の中で暗号化してから iCloud に保存します。Apple の「高度なデータ保護」をオンにしている場合は、エンドツーエンドで
  暗号化され、暗号の鍵は利用者の信頼できるデバイスだけが持ちます。オフの場合（標準のデータ保護）は、通信中と Apple のサーバー上で
  暗号化され、暗号の鍵は Apple が管理します。記録の件数や、iCloud に保存・変更した日時などの管理用の情報は、暗号化フィールドに
  入らず、高度なデータ保護をオンにしていても標準のデータ保護で扱われます（通信中と Apple のサーバー上では暗号化されます）。
- 同期のために、iOS の仕組み（Core Data と CloudKit）が、同期の状態（どこまで同期したか、どの iCloud のアカウントと
  同期しているかを見分けるための情報など）をお使いの端末の中に保存します。これらも開発者へは送信しません。
- **オフにすると**、以後はお使いの端末の中にだけ保存します。端末の中の記録は残ります。すでに iCloud に保存した記録は iCloud に
  残り、その端末とはそろわなくなります。iCloud の記録を消すには、オンのまま本アプリで記録を削除してください（削除は iCloud と、
  同期しているほかの端末にも反映されます）。
- 同期をオンのまま iCloud からサインアウトすると、同期した記録がその端末から見えなくなることがあります（iCloud には残ります）。
  サインアウトする前に、本アプリの設定で同期をオフにしてください。

### アプリのロック（任意）

設定の「Face ID でロック」（Face ID の無い端末では Touch ID かパスコード）は、既定ではオフです。オンにすると、本アプリを開くときに
ロックの解除を求め、アプリの切り替えの画面でも記録を隠します。認証は iOS の仕組み（LocalAuthentication）が行い、本アプリが
受け取るのは認証できたかどうかだけです。**顔や指紋のデータ、パスコードを本アプリが受け取ったり保存したりすることはありません。**
オンかオフかだけを、下の「保存される設定」に保存します。

### 保存される設定

初回の案内を終えたかどうか、iCloud で同期するかどうか、アプリのロックをオンにしているかどうかといったアプリの設定は、
iOS の標準的な仕組み（UserDefaults）を用いて、お使いの iPhone の中の本アプリ専用の領域にのみ保存します。ただし、iCloud で同期するか
どうかとアプリのロックをオンにしているかどうかの 2 つは、本アプリが iPhone のロック中に裏で動くとき（iCloud の変更の知らせを受けたときなど）にも
正しく読めるよう、同じ領域の小さな設定のファイルに、iPhone を起動して最初にロックを解いた後から読める保護で保存します。
これらを外部に送信することはありません。予算の金額は設定ではなく、上の家計の記録と同じ場所に保存します。

### 設定の画面から開くページ

設定の画面の「ヘルプ・お問い合わせ」「プライバシーポリシー」は、Safari で GitHub のページ（サポートのページと
このポリシー）を開きます。開いたページの閲覧には、GitHub のプライバシーポリシーが適用されます。
本アプリが記録や設定をそれらのページへ送ることはありません。

### アプリの削除

SaifuLog を削除すると、端末内の記録と設定も併せて削除されます。ただし、削除より前に
作られた iPhone のバックアップには残ることがあります。「iCloud で同期」をオンにしていた場合、iCloud に保存した記録は、
アプリを削除しても iCloud に残ります（同じ Apple アカウントの端末でアプリを入れ直して同期をオンにすると、また使えます）。

### ポリシーの変更

内容を変更する場合は、このページを更新し、最終更新日を改めます。変更の履歴は GitHub
リポジトリで確認できます。

### お問い合わせ

本ポリシーに関するご質問は、GitHub リポジトリの Issues までお寄せください。Issues は
公開されるため、個人情報や家計の記録は書き込まないでください。

https://github.com/iam74k4/Apple-SaifuLog/issues

セキュリティやプライバシーに関わる問題（記録が端末の外へ送られている疑いなど）や、公開の
場に書けないご相談は、Issues ではなく GitHub の非公開の報告窓口（リポジトリの Security
タブの「Report a vulnerability」）からお知らせください。内容は開発者とご本人だけが
見られます。詳しくは [`SECURITY.md`](SECURITY.md) を参照してください。

https://github.com/iam74k4/Apple-SaifuLog/security/advisories/new

---

## English

### Information We Collect

**The developer of SaifuLog does not collect your personal information or your household
finance records.**

The app does not use any server operated by the developer. Your records are never sent to
the developer or to any third party (if you turn on Sync with iCloud in Settings, your records are
saved in your own iCloud (Apple) space, which the developer cannot see; see Sync with iCloud below).

The app contains no analytics tools, no advertising networks, no crash reporting, no
tracking, and no third-party SDKs of any kind. It shows no advertisements.

If you have turned on "Share with App Developers" in your iPhone's settings, Apple may
provide the developer with anonymous diagnostic information such as crash logs. This is
done by Apple's own system, not by the app itself.

### Your Records

Your records, such as amounts, dates, categories, notes, and the text you entered, and the
budget amount you set are stored on your own iPhone, in an area reserved for this app, using the
standard iOS mechanism (SwiftData). While Sync with iCloud in Settings is off (the default), they are
stored only on this iPhone. When it is on, they are handled as described in Sync with iCloud below.

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

The app decides the category of a one-line entry from the names of categories you created, your learned categories, your past
records on your iPhone (their items and categories), and a dictionary of store names. Past records are only read on your iPhone for
this and are never sent anywhere. When the category is still undecided (or when you have created categories), only the entry's item
and the list of category names (including the names of categories you created) are passed to the on-device AI to choose a category.
Amounts, dates, and learned categories are not passed to the AI. This also happens on your iPhone, and the AI's answers are not
remembered.

When you send a chat message to fix or remove your latest entry or to set your monthly budget (for example, "さっきのを900に直して"),
the app reads the message. If the app's own rules can't read it, on devices where Apple Intelligence is available only the message
is passed to the on-device AI to choose which operation you asked for (the app itself reads the amount or category from your
message). Your records and budgets are not passed to the AI. This also happens on your iPhone, and **your message is never sent
anywhere.**

### Questions About Your Spending

When you ask about your spending in the same field you use for records (for example, "今月カフェいくら?"), the app
calculates the numbers in the answer from the records on your own iPhone. Reading your question and writing the short note
added to the answer are done with Apple's Foundation Models framework on devices where Apple Intelligence is available, and
with an on-device keyword dictionary otherwise. **Your question, your records, and the calculated answer are never sent
anywhere.**

Questions and answers are not saved as records. They are kept only in the app's memory while the app is running and disappear
when you reopen the app.

### The Note in a Reply to an Entry

Right after you record something with a one-line entry, on devices that can use Apple Intelligence, the app calculates on your own
iPhone the spending you just recorded (item, amount, category), this month's total and count for that category, this month's total
spending and count, and what is left of your budget, puts them into a text, and passes that text to Apple's Foundation Models framework
to write a short note; this also happens on your own iPhone. **Your records, the calculated numbers, and the note are never sent
anywhere.** The note is not saved; it is kept only in the app's memory while the app is running.

### The Monthly Summary

The numbers in the monthly summary (spending, income, net, the difference from the month before, spending by category, and the
remaining budget) are calculated by the app from the records on your own iPhone. On devices where Apple Intelligence is available, the app passes a
text listing the calculated numbers to Apple's Foundation Models framework to write a short note; this also happens on your own
iPhone. **Your records, the calculated numbers, and the note are never sent anywhere.** The note is not saved; it is kept only in
the app's memory while the app is running.

### Learned Categories (Remembered Corrections)

When you choose a category in a reply (the category buttons shown for an entry that was recorded as Other), correct the category right after recording by sending a message such as "それ日用品", or change the category of an entry on
the edit screen, the app remembers the pair of the entry's item words (for example, "UNIQLO") and the
category you chose, and records entries with the same words in that category from then on. Learned words and categories are stored
in the same place as your records described above (in an area reserved for this app on your iPhone, and, when Sync with iCloud is
on, also in your own iCloud as encrypted fields, like your records). **They are never sent to the developer or to any third party.**
They are not passed to the on-device AI either (the app replaces the category with the learned one after reading).
You can review them at any time in Learned Categories in Settings, change their categories, and forget them one by one or all at once.

An entry that needs a category is saved with a mark showing that the app is asking for its category alongside the record (synced with the record when Sync with iCloud is
on). The mark is removed when you choose a category or delete the entry.

### Categories You Create

Categories you create in Categories in Settings or from a reply (their names, symbols, colors, order, and when they were created and
last edited) are stored in the same place as your records described above (in an area reserved for this app on your iPhone, and, when
Sync with iCloud is on, also in your own iCloud as encrypted fields, like your records). **They are never sent to the developer or to
any third party.** Each record stores only an identifier of the category you created, not its name. When the app asks the on-device AI
to choose the category of an entry, or to write a remark for a reply to an entry, for the monthly summary or for an answer to a question,
the names of categories you created are passed along with the other categories, and this also happens on your iPhone. When you export a CSV file, the category column
contains the name of the category you created. If you delete a category, its records move to Other.

### Recurring Entries

The rules for entries that repeat every month, which you create in Recurring Entries in Settings or from a record's menu (the amount,
item, whether it is income or an expense, category, day of the month, first month, the latest month already recorded, and when the rule
was created and last edited), are stored in the same place as your records described above (in an area reserved for this app on your
iPhone, and, when Sync with iCloud is on, also in your own iCloud as encrypted fields, like your records). **They are never sent to the
developer or to any third party.** When you open the app on or after the chosen day, the app creates the record on your iPhone (no server
is involved). The created records are stored like your other records, with a marker that tells which rule and month each one is for (so
that if two of your devices synced with iCloud both record the same month, they can be merged into one). Stopping a rule keeps the records
already created.

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

### Siri and Shortcuts

When you use the app's actions ("Record in SaifuLog" and "Ask SaifuLog") from Siri, Shortcuts, Spotlight, or the Action button, the text you
speak or enter is passed to the app through Siri and Shortcuts (Apple). How your voice is handled when you speak to Siri is governed by Apple's
privacy policy and your Siri settings. The app treats the text it receives the same way as text typed in the input field (text that becomes a record
or a question is handled as described in Your Records above), and never sends it to the developer or to any third party. Every action opens the app
first, so you can check what was recorded in the app's reply.

### CSV Export

Only when you tap Export CSV File in Settings, the records in the period you choose (this
month, last month, this year, or all) are written to a CSV file, including the date, time,
expense or income, category (for a category you created, its name), item, amount, and the text you entered. The file is handed to the
iOS share sheet and **goes only to the destination you choose there (an app, a location in
Files, AirDrop, and so on).** The app never exports or sends your records on its own, and
nothing is sent to the developer.

Once you hand the file to a destination, it is handled according to that app or service. The
file contains your financial records, so please choose the destination with care. The
temporary file the app creates for the export is deleted when the share sheet closes (if the app
quits while the share sheet is open, it is deleted the next time you open Settings).

### Sync with iCloud (Optional)

Sync with iCloud in Settings is off by default. Only when you turn it on, your records (the same items as in Your Records
above, such as amounts, dates, categories, notes, and the text you entered), budget amounts, learned categories, categories you create, and recurring entries are saved in your own space in
Apple's iCloud (the CloudKit private database) and kept in sync across devices signed in to the same Apple Account. Records
already on your device when you turn it on are saved to iCloud as well. This is separate from the iPhone backup described above.

- **The developer cannot see what is saved in your iCloud.** Your records never pass through a server of the developer; they
  are exchanged only between Apple's iCloud and your devices. Saving in iCloud is covered by Apple's privacy policy and the
  iCloud terms.
- **About encryption.** The contents of your records and budgets (every item the app saves: amounts, whether each is income or an
  expense, dates, categories, notes, the text you entered, how it was entered (text, receipt, a recurring entry, and so on), when it was recorded,
  each budget's target, amount, and when it was set, each learned category's words, category, and when it was learned, and each
  category you create's name, symbol, color, order, and when it was created and last edited, and every item of each recurring entry rule
  and the marker on records created from it) are
  saved to iCloud as CloudKit encrypted fields, encrypted on your
  device first. If Apple's Advanced Data Protection is on, they are end-to-end encrypted, and only your trusted devices have the
  keys. If it is off (standard data protection), they are encrypted in transit and on Apple's servers, and Apple manages the keys.
  Management information, such as the number of records and when they were saved to or changed in iCloud, is not stored in
  encrypted fields and stays under standard data protection even if Advanced Data Protection is on (it is still encrypted in
  transit and on Apple's servers).
- To sync, the iOS system (Core Data and CloudKit) stores the sync state on your device (such as how far it has synced and
  information to tell which iCloud account it syncs with). This is not sent to the developer either.
- **When you turn it off**, records are saved only on your device from then on, and the records on the device stay. Records
  already saved in iCloud stay in iCloud and no longer stay in sync with that device. To remove records from iCloud, delete
  them in the app while sync is on (deletions also reach iCloud and your other synced devices).
- If you sign out of iCloud while sync is on, synced records may disappear from that device (they stay in iCloud). Turn off
  sync in the app's Settings before you sign out.

### App Lock (Optional)

Lock with Face ID in Settings (Touch ID or your passcode on devices without Face ID) is off by default. When it is on, the app
asks you to unlock it when you open it and hides your records in the app switcher. Authentication is performed by iOS
(LocalAuthentication), and the app only receives whether you were authenticated. **The app never receives or stores your face or
fingerprint data or your passcode.** Only whether app lock is on is stored, as described in Settings We Store below.

### Settings We Store

App settings, such as whether you have finished the first-launch introduction, whether to sync with iCloud, and whether app lock
is on, are stored only on your own iPhone, in an area reserved for this app, using the
standard iOS mechanism (UserDefaults). The two settings for iCloud sync and app lock are instead kept in a small settings file in the same
area, using protection that makes it readable after you first unlock your iPhone following a restart, so they are read correctly even when
the app runs in the background while your iPhone is locked (for example, when notified of iCloud changes). They are never transmitted
anywhere. Your budget amount is not a setting; it is stored in the same place as your records,
described above.

### Pages Opened from Settings

Help & Contact and Privacy Policy in Settings open pages on GitHub (the support page and this policy) in Safari. Your visit
to those pages is covered by GitHub's privacy policy. The app does not send your records or settings to those pages.

### Deleting the App

Removing SaifuLog also removes the records and settings stored on your device. However, they
may remain in iPhone backups made before the app was removed. If Sync with iCloud was on, records
saved in iCloud stay in iCloud after you remove the app (you can use them again by reinstalling the
app on a device with the same Apple Account and turning sync on).

### Changes to This Policy

If this policy changes, this page will be updated along with its "Last updated" date. The
history of changes can be viewed in the GitHub repository.

### Contact

Questions about this policy may be raised via Issues on the GitHub repository. Issues are
public, so please do not include personal information or your financial records.

https://github.com/iam74k4/Apple-SaifuLog/issues

For security or privacy problems (for example, a sign that records leave the device), or for
anything you cannot write in public, please use GitHub's private reporting channel instead of
Issues ("Report a vulnerability" on the repository's Security tab). Only the developer and you
can see the report. See [`SECURITY.md`](SECURITY.md) for details.

https://github.com/iam74k4/Apple-SaifuLog/security/advisories/new
