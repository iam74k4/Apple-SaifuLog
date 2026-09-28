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

記録は 1 件ずつ、アプリの中で直したり削除したりできます（タイムラインの記録を押して開く画面で直すか
「この記録を削除」、または記録を長押しして「削除」）。直した金額・品目・支出か収入か・カテゴリ・日付は、元の記録に
上書きして保存します。入力した文章は直しても元のまま残り、直す画面に見比べるために表示します。入力した文章を消すには、
その記録を削除してください（1 回の入力から複数の記録ができたときは、そのすべてを削除すると消えます）。
予算は、予算を決める画面の「予算をなくす」で設定なしに戻せます。

### 端末内 AI の取り扱い

入力した文章から日付・金額・カテゴリを読み取る処理には、Apple の Foundation Models
フレームワークを用います。この処理はお使いの iPhone の上で行われ、**入力した文章や記録を、
解析のために外部へ送信することはありません。**

Apple Intelligence を使えない端末では、端末内のキーワード辞書で読み取ります。この場合も
外部へ送信することはありません。

### 家計への質問・ふりかえり・修正の記憶（予定の機能）

家計についての質問への回答や、ふりかえりのメッセージの作成を提供する場合も、同じく
Foundation Models を用いてお使いの iPhone の上で行い、外部へ送信することはありません。

利用者が記録を直した内容（例: ある言葉をどのカテゴリに分けるか）を以後の読み取りに
役立てる機能を提供する場合、その内容は端末内にのみ保存します。

### レシート・スクリーンショットの取り扱い（予定の機能）

利用者がレシートを撮影したり、スクリーンショットを選んだりしたときは、明細を読み取るために
その画像を端末内で処理します。**画像を外部へ送信することはありません。**

カメラや写真へのアクセスは、利用者がこの機能を使うときにだけ求める予定です。読み取りが
終わった画像そのものを保存するかどうかは、実装時に決めてこのポリシーに記載します。

### 声での記録（予定の機能）

声で記録する機能を提供する場合は、iOS の端末内の音声認識を用いる予定です。音声を
録音して保存したり、開発者へ送信したりはしません。マイクへのアクセスは、利用者が
この機能を使うときにだけ求めます。

### CSV 書き出し（予定の機能）

利用者が書き出しを選んだときだけ、記録を CSV ファイルにして、利用者が選んだ保存先や
共有先へ渡します。開発者へ送信することはありません。

### アプリの iCloud バックアップ・同期と家族との共有（将来の任意の機能）

現在は提供していません。上に書いた iPhone 自体のバックアップとは別に、アプリの機能として
iCloud へのバックアップや同期を提供する場合の取り扱いです。

提供する場合は、利用者が有効にしたときだけ、記録は利用者自身の iCloud（Apple）の領域に
保存されます。家族やパートナーとの共有も、利用者が招待した相手とだけ、Apple の iCloud の
仕組みを通じて行います。いずれも開発者は内容を見られません。

導入する際には、このポリシーを更新します。

### 購入の取り扱い（予定の機能）

プレミアムの購入と復元は、Apple の App Store が扱う予定です。支払いの情報を開発者が受け取る
ことはありません。購入済みかどうかの確認は、Apple の仕組みを通じて端末上で行います。

### 保存される設定

初回の案内を終えたかどうかといったアプリの設定は、iOS の標準的な仕組み（UserDefaults）を用いて、
お使いの iPhone の中の本アプリ専用の領域にのみ保存します。無料で使える回数の数え方に必要な情報などの
設定を今後提供する場合も、同じ場所に保存します。これらを外部に送信することはありません。
予算の金額は設定ではなく、上の家計の記録と同じ場所に保存します。

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

You can edit or delete your records one by one in the app (tap a record in the timeline to
edit it or choose Delete This Record, or long-press a record and choose Delete). When you edit
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

### Questions, Weekly Reviews, and Remembered Corrections (Planned Features)

If answering your questions about your spending and writing review messages are offered,
they will also be done with Apple's Foundation Models framework on your own iPhone, and
nothing will be sent anywhere.

If the app offers to remember your corrections (for example, which category a certain word
belongs to) so that later entries can be read more accurately, those corrections will be
stored only on your device.

### Receipts and Screenshots (Planned Feature)

When you photograph a receipt or choose a screenshot, the image is processed on your device
to read its line items. **The image is never sent anywhere.**

The app is planned to ask for access to the camera or photos only when you use this
feature. Whether the image itself is kept after reading will be decided during
implementation and stated in this policy.

### Voice Entry (Planned Feature)

If voice entry is offered, it is planned to use the on-device speech recognition of iOS.
Your voice is never recorded for storage and never sent to the developer. Access to the
microphone will be requested only when you use this feature.

### CSV Export (Planned Feature)

Only when you choose to export, your records are written to a CSV file and handed to the
destination or app you choose. Nothing is sent to the developer.

### In-App iCloud Backup, Sync, and Sharing with Family (Future, Optional)

These features are not currently offered. This section covers iCloud backup or sync offered
as a feature of the app itself, which is separate from the iPhone backup described above.

If they are offered, your records will be stored in your own iCloud (Apple) space only when
you turn the feature on. Sharing with family members or a partner will take place only with
the people you invite, through Apple's iCloud. In either case, the developer cannot see the
contents.

This policy will be updated when these features are introduced.

### Purchases (Planned Feature)

Purchases and restores of Premium are planned to be handled by Apple's App Store. The
developer never receives your payment information. Whether you have purchased Premium is
checked on your device through Apple's system.

### Settings We Store

App settings, such as whether you have finished the first-launch introduction, are stored only
on your own iPhone, in an area reserved for this app, using the standard iOS mechanism
(UserDefaults). Settings offered in the future, such as the information needed to count
free-tier usage, will be stored in the same place. They are never transmitted anywhere. Your
budget amount is not a setting; it is stored in the same place as your records, described above.

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
