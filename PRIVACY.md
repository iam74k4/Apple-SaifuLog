# プライバシーポリシー / Privacy Policy

**SaifuLog（サイフログ）**

最終更新日 / Last updated: 2026-10-05

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

### 覚えたカテゴリ（修正の記憶）

記録の返事でカテゴリを選んだとき（「その他」になった記録に出るカテゴリのボタン）と、記録を直す画面でカテゴリを変えたときは、
その記録の品目の言葉（例: 「ユニクロ」）と選んだカテゴリの組を覚え、次から同じ言葉の記録をそのカテゴリで記録します。
覚えた言葉とカテゴリは、上の「入力した家計の記録」と同じ場所（お使いの iPhone の中の本アプリ専用の保存先。「iCloud で同期」を
オンにしているときは、記録と同じく暗号化フィールドとして利用者自身の iCloud にも）に保存し、**開発者や第三者へ送信することは
ありません。** 端末内 AI に渡すこともありません（読み取った後に、本アプリが覚えたカテゴリへ置き換えます）。
覚えたものは、設定の「覚えたカテゴリ」でいつでも確かめ、カテゴリを変えたり、1 つずつ、またはすべて忘れさせたりできます。

### 作ったカテゴリ

設定の「カテゴリ」や記録の返事から作ったカテゴリ（名前・記号・色・並び順・作った日時・直した日時）は、上の「入力した家計の記録」と
同じ場所（お使いの iPhone の中の本アプリ専用の保存先。「iCloud で同期」をオンにしているときは、記録と同じく暗号化フィールドとして
利用者自身の iCloud にも）に保存し、**開発者や第三者へ送信することはありません。** 記録にはカテゴリの名前ではなく、作ったカテゴリを
見分ける番号だけを保存します。週のふりかえりや月のまとめの一言、質問の答えの一言を端末内 AI に書かせるときは、ほかのカテゴリと同じく
作ったカテゴリの名前も渡しますが、この処理もお使いの iPhone の上で行います。CSV に書き出すときは、カテゴリの列に作ったカテゴリの名前を
書きます。カテゴリを削除すると、そのカテゴリの記録は「その他」になります。家族・パートナーとの家計には、作ったカテゴリを持ち込みません
（家計の記録では「その他」になります）。

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

### Apple Pay の支払いの自動記録（任意）

利用者が「ショートカット」App で、Apple Pay で払ったときのオートメーション（「取引」）を作り、本アプリの「支払いを記録」を使うようにした
場合だけ、払った金額と店名（加盟店の名前）が、Apple のショートカットの仕組みを通って本アプリに渡されます。本アプリは、金融機関や
カード会社とはつながらず、ログインの情報も預かりません。

受け取った支払い（金額・店名・受け取った日時）は、次に本アプリを開いて記録にするまで、お使いの iPhone の中の本アプリ専用の小さな
ファイルに置きます。iPhone がロックされたままでも受け取れるよう、このファイルは、iPhone を起動して最初にロックを解いた後から
読み書きできる保護（iOS のデータ保護の「最初のユーザ認証まで保護」）にしています。記録にしたら、このファイルから消します。記録にした後は、上の「入力した家計の記録」と同じく扱います。**受け取った支払いを
開発者や第三者へ送信することはありません。** オートメーションはいつでも「ショートカット」App で消せます。

受信の動作を確かめるため、最後に支払いを受け取った日時だけを端末内に保存します。この状態表示には金額・店名を残さず、外部送信やiCloud同期はしません。アプリを削除すると消えます。

### Siri・ショートカット

Siri・ショートカット・Spotlight・アクションボタンから本アプリの操作（「ひとことで記録」「家計に質問」など）を使うと、話したり入れたりした文が、
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
  文章・入力の方法（文字・レシート・声・くり返しの記録）・記録した日時と、予算の対象・金額・決めた日時と、覚えたカテゴリの言葉・カテゴリ・覚えた日時と、
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

### 家族・パートナーとの家計の共有（提供前の機能）

家族やパートナーと家計を共有する機能は、**App Store で配信する版では提供していません**（開発者が実機で確かめるための、社内テスト用の
版にだけ入っています）。提供するときは、次のように取り扱う予定です。提供を始めるときに、このポリシーを見直します。

- 共有は、利用者が「家計」を作り、招待した相手とだけ行います。招待は Apple の iCloud の共有の仕組み（CloudKit の共有）で送り、
  相手は自分の Apple アカウントで受け入れます。開発者のサーバーは通りません。
- 共有するのは、家計に記録したもの（金額・収入か支出か・カテゴリ・メモ・使った日時・記録した人の名前・記録した日時と直した日時）と、
  家計の名前だけです。**自分の記録（「自分」に記録したもの）は共有しません。**
- 記録した人の名前は、家計の参加者に見える表示名です。家計を作った人は、作るときに自分で決めます。招待を受け入れた人は、はじめは
  その人の Apple アカウントの名前が入り（分からなければ空欄）、設定の「家族と共有」でいつでも確かめて変えられます。変える前に記録した
  ものは、そのときの名前のままです。
- 家計の名前（作った人が決めるもの。空欄なら「家族の家計」）は、招待の画面と招待を開いた人に表示するため、Apple の iCloud の共有の
  情報（CloudKit の共有の題名）として保存します。家計の記録と違って暗号化フィールドには入りません（通信中と Apple のサーバー上では
  暗号化されます）。家計の名前に、知られたくない内容を入れないでください。招待を受け入れた人の端末では、受け入れたときの家計の名前を
  その端末の中に写し、その人が変えても家族には見えません。
- 共有の画面（iOS の標準の画面）では、Apple の共有の仕組みにより、家計に参加している人の名前などが参加者に表示されます。
- 家計の記録は、家計を作った人の iCloud の領域（CloudKit の非公開データベースの家計ごとのゾーン）に保存され、参加者の端末とのあいだで
  Apple の iCloud を通じてそろえます。家計の参加者は全員、家計の記録を見て、足し、直し、削除できます。
- **開発者は、家計の記録と家計の名前を見られません。** 家計の記録の項目は、CloudKit の暗号化フィールドとして、端末の中で暗号化してから iCloud に
  保存します。通信中と Apple のサーバー上で暗号化されます。Apple の「高度なデータ保護」をオンにしている場合は、エンドツーエンドで
  暗号化され、鍵は家計の持ち主と参加者だけが持ちます（オフのときは、鍵は Apple が管理します）。
- 家計の記録は、お使いの iPhone の中でも、自分の記録とは別の本アプリ専用の保存先に置き、同期の状態（どこまで同期したか）も
  そこに保存します。開発者へは送りません。
- 家計を作った人が共有をやめるか家計を削除すると、参加者の端末から家計の記録が消えます。参加者が家計から抜けると、その参加者の端末から
  家計の記録が消えます（ほかの人の家計の記録は残ります）。iCloud からサインアウトしたり、アカウントを替えたりしたときも、その端末から
  家計の記録を消します。同じ Apple アカウントでサインインし直したときや、同じ Apple アカウントでサインインしているほかの端末（本アプリの
  家計の共有を使える版で、家計に入っていない端末）では、そのアカウントの iCloud にある家計と記録を取り込んで表示します。

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

### アプリのロック（任意）

設定の「Face ID でロック」（Face ID の無い端末では Touch ID かパスコード）は、既定ではオフです。オンにすると、本アプリを開くときに
ロックの解除を求め、アプリの切り替えの画面でも記録を隠します。認証は iOS の仕組み（LocalAuthentication）が行い、本アプリが
受け取るのは認証できたかどうかだけです。**顔や指紋のデータ、パスコードを本アプリが受け取ったり保存したりすることはありません。**
オンかオフかだけを、下の「保存される設定」に保存します。

### 保存される設定

初回の案内を終えたかどうか、週の始まり（日曜か月曜か）、iCloud で同期するかどうか、アプリのロックをオンにしているかどうか、無料体験が終わったときの案内を出したかどうか、家計への質問を
無料で使った回数（月ごとの回数。質問の文や答えは含みません）、先週のふりかえりを最後に表示した日時（ふりかえりの中身は
含みません）、レシートの読み取りを無料で使った回数（月ごとの回数。画像や読み取った内容は含みません）といったアプリの設定は、
iOS の標準的な仕組み（UserDefaults）を用いて、お使いの iPhone の中の本アプリ専用の領域にのみ保存します。ただし、iCloud で同期するか
どうかとアプリのロックをオンにしているかどうかの 2 つは、本アプリが iPhone のロック中に動くとき（Apple Pay の支払いの受け取りなど）にも
正しく読めるよう、同じ領域の小さな設定のファイルに、iPhone を起動して最初にロックを解いた後から読める保護で保存します。
これらを外部に送信することはありません。予算の金額は設定ではなく、上の家計の記録と同じ場所に保存します。
購入したかどうかは設定には保存しません（上の「購入の取り扱い」）。

### 設定の画面から開くページ

設定の画面の「ヘルプ・お問い合わせ」「プライバシーポリシー」「ライセンス」は、Safari で GitHub のページ（サポートのページ、
このポリシー、ライセンスの文書）を開きます。開いたページの閲覧には、GitHub のプライバシーポリシーが適用されます。
プレミアムの画面の「利用規約（Apple の標準 EULA）」は、Safari で Apple のページを開き、その閲覧には Apple の
プライバシーポリシーが適用されます。本アプリが記録や設定をそれらのページへ送ることはありません。

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

### Learned Categories (Remembered Corrections)

When you choose a category in a reply (the category buttons shown for an entry that was recorded as Other) or change the
category of an entry on the edit screen, the app remembers the pair of the entry's item words (for example, "UNIQLO") and the
category you chose, and records entries with the same words in that category from then on. Learned words and categories are stored
in the same place as your records described above (in an area reserved for this app on your iPhone, and, when Sync with iCloud is
on, also in your own iCloud as encrypted fields, like your records). **They are never sent to the developer or to any third party.**
They are not passed to the on-device AI either (the app replaces the category with the learned one after reading).
You can review them at any time in Learned Categories in Settings, change their categories, and forget them one by one or all at once.

### Categories You Create

Categories you create in Categories in Settings or from a reply (their names, symbols, colors, order, and when they were created and
last edited) are stored in the same place as your records described above (in an area reserved for this app on your iPhone, and, when
Sync with iCloud is on, also in your own iCloud as encrypted fields, like your records). **They are never sent to the developer or to
any third party.** Each record stores only an identifier of the category you created, not its name. When the app asks the on-device AI
to write a remark for Last Week in Review or the monthly summary, or for an answer to a question, the names of categories you created
are passed along with the other categories, and this also happens on your iPhone. When you export a CSV file, the category column
contains the name of the category you created. If you delete a category, its records move to Other. Categories you create are not
brought into a household shared with family or a partner (such records use Other there).

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

### Automatic Recording of Apple Pay Payments (Optional)

Only if you create an automation in the Shortcuts app that runs when you pay with Apple Pay (a Transaction automation) and uses the app's
Record Payment action, the amount and merchant name are passed to the app through Apple's Shortcuts. The app does not connect to banks or
card companies and never holds your login information.

Received payments (amount, merchant, and when they were received) are kept in a small file reserved for the app on your iPhone until you
next open the app and they are recorded. So payments can be received while your iPhone is locked, this file uses the iOS data
protection class that makes it readable after you first unlock your iPhone following a restart. The payments are removed from this file
once recorded, after which they are handled as
described in Your Records above. **Received payments are never sent to the developer or to any third party.** You can delete the automation
in the Shortcuts app at any time.

To help you check reception, only the date of the last received payment is retained locally. This status contains no amount or merchant, is not transmitted or synced with iCloud, and is removed when the app is deleted.

### Siri and Shortcuts

When you use the app's actions (such as "Record in SaifuLog" or "Ask SaifuLog") from Siri, Shortcuts, Spotlight, or the Action button, the text you
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
  expense, dates, categories, notes, the text you entered, how it was entered (text, receipt, voice, or a recurring entry), when it was recorded,
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

### Sharing a Household with Family or a Partner (Not Yet Offered)

Sharing a household with family members or a partner is **not offered in the version distributed on the App Store** (it is
included only in internal test builds the developer uses to verify it on devices). When it is offered, it is planned to work
as follows, and this policy will be reviewed when it starts.

- Sharing happens only after you create a "household" and only with the people you invite. Invitations are sent with Apple's
  iCloud sharing (CloudKit sharing), and the people you invite accept them with their own Apple Account. Nothing passes through
  a server of the developer.
- Only what you record to the household (amount, income or expense, category, memo, date spent, the name of who recorded it,
  and when it was recorded and edited) and the household name are shared. **Your own records (recorded to "Me") are not
  shared.**
- The name of who recorded an entry is a display name that the members of the household can see. The person who creates the
  household chooses it when creating the household. For a person who accepts an invitation, it starts as the name on their
  Apple Account (blank if it isn't available), and they can check and change it at any time in Settings under "Share with
  Family." Entries recorded before a change keep the name used at the time.
- The household name (chosen by the person who creates the household; "Family Household" if left blank) is saved as part of
  Apple's iCloud sharing information (the title of the CloudKit share) so that it can be shown on the invitation screen and to
  people who open the invitation. Unlike household entries, it is not stored in encrypted fields (it is still encrypted in
  transit and on Apple's servers). Please don't put anything in the household name that you want to keep private. On the
  device of a person who accepts an invitation, the household name at the time of accepting is copied onto that device, and
  changes they make there aren't visible to the family.
- On the sharing screen (the standard iOS screen), Apple's sharing system shows the names and similar details of the people
  in the household to its members.
- Household entries are saved in the iCloud space of the person who created the household (a zone per household in the
  CloudKit private database) and kept in sync with the members' devices through Apple's iCloud. Every member of the household
  can see, add, edit, and delete household entries.
- **The developer cannot see household entries or the household name.** The fields of household entries are saved to iCloud
  as CloudKit encrypted fields, encrypted on the device first. They are encrypted in transit and on Apple's servers. If Advanced Data Protection is
  on, they are end-to-end encrypted, and only the owner and the members of the household have the keys (when it is off, Apple
  manages the keys).
- On your iPhone, household entries are kept in a storage area of the app that is separate from your own records, together
  with the sync state (how far it has synced). This is not sent to the developer.
- If the person who created the household stops sharing or deletes the household, the household entries disappear from the
  members' devices. If a member leaves the household, the household entries disappear from that member's devices (the other
  members' household entries stay). Household entries are also removed from a device when you sign out of iCloud or switch
  accounts on it. When you sign back in with the same Apple Account, and on your other devices signed in with the same Apple
  Account (with a version of the app that includes household sharing, on a device that isn't in a household), the household
  and its entries in that account's iCloud are brought in and shown.

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

### App Lock (Optional)

Lock with Face ID in Settings (Touch ID or your passcode on devices without Face ID) is off by default. When it is on, the app
asks you to unlock it when you open it and hides your records in the app switcher. Authentication is performed by iOS
(LocalAuthentication), and the app only receives whether you were authenticated. **The app never receives or stores your face or
fingerprint data or your passcode.** Only whether app lock is on is stored, as described in Settings We Store below.

### Settings We Store

App settings, such as whether you have finished the first-launch introduction, which day your
week starts on, whether to sync with iCloud, whether app lock is on, whether the notice at the end of the free trial has been shown, and the number of free
questions about your spending you have used (counted per month; your questions and answers are not
included), the date and time Last Week in Review was last shown (not its contents), and the number of free receipt scans you have used
(counted per month; no images or scanned contents), are stored only on your own iPhone, in an area reserved for this app, using the
standard iOS mechanism (UserDefaults). The two settings for iCloud sync and app lock are instead kept in a small settings file in the same
area, using protection that makes it readable after you first unlock your iPhone following a restart, so they are read correctly even when
the app runs while your iPhone is locked (for example, when receiving an Apple Pay payment). They are never transmitted
anywhere. Your budget amount is not a setting; it is stored in the same place as your records,
described above. Whether you have purchased Premium is not stored as a setting (see Purchases above).

### Pages Opened from Settings

Help & Contact, Privacy Policy, and License in Settings open pages on GitHub (the support page, this policy, and the license
document) in Safari. Your visit to those pages is covered by GitHub's privacy policy. Terms of Use
(Apple's Standard EULA) on the Premium screen opens a page on Apple's website in Safari, covered by
Apple's privacy policy. The app does not send your records or settings to those pages.

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
