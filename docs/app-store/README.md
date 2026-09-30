# App Store の掲載情報

App Store に出す前の掲載情報・審査用の資料・スクリーンショットの下書き。**App Store Connect への入力は、所有者が中身を
確かめてから行う**（ここを書き換えても App Store Connect には反映されない）。入力する場所と順は
[`../release-flow.md`](../release-flow.md) の「一度だけの準備」の 5 と 8。

| ファイル | 中身 |
|---|---|
| [`metadata.ja.md`](metadata.ja.md) | 日本語の名前・サブタイトル・プロモーション用テキスト・説明・キーワード・カテゴリ・著作権・URL と、それぞれの文字数 |
| [`metadata.en.md`](metadata.en.md) | 英語の同じ項目（英語の名前の提案を含む） |
| [`review-notes.md`](review-notes.md) | 審査メモ（アプリと課金アイテムごと。英語と日本語の対訳） |
| [`privacy-answers.md`](privacy-answers.md) | App のプライバシーの回答（「データの収集なし」）と、機能ごとの根拠 |
| [`age-rating.md`](age-rating.md) | 年齢制限の質問への回答と、その結果の区分（4+） |
| `screenshots/ja/`・`screenshots/en/` | 6.9 インチ（1320 × 2868）のスクリーンショット |
| [`../support.md`](../support.md) | サポート URL のページ（問い合わせ先とよくある質問） |

**書くのは、App Store へ出すビルドで使える機能だけ。** 予定の機能や、App Store へ出すビルドで無効にしている機能は、
掲載情報にも審査メモにもスクリーンショットにも入れない。機能を足したり料金を変えたりしたら、README・`docs/design.md`・
`PRIVACY.md` と一緒にここも直す。

## App Store Connect で所有者がすること

ここのファイルを直しても App Store Connect は変わらない。リポジトリの側で変えたもののうち、App Store Connect の側でも
所有者が直すものを並べる（済んだら行を消す）。

| いつ | どこで | すること |
|---|---|---|
| 課金アイテムを審査に出す前 | 収益化 → App 内課金 → 14日間の無料体験（`com.iam74k4.SaifuLog.trial14`）→ App Store のローカライズ → 英語（米国） | 表示名を「14-Day Free Trial」から **「14-day Trial」** に替える（ガイドライン 3.1.1 の「XX-day Trial」の形。`Config/SaifuLog.storekit` の en と同じ）。説明は `Config/SaifuLog.storekit` の en のまま（「Try every Premium feature free for 14 days. You won't be charged when it ends.」）。日本語の表示名「14日間の無料体験」は替えない。英語のローカライズがまだ無ければ、この表示名と説明で足す |

## スクリーンショット

| ファイル | 写っているもの | 使い道 |
|---|---|---|
| `01-home.png` | 記録のタイムラインと今月の帯 | ストア |
| `02-ask.png` | 家計への質問と回答カード | ストア |
| `03-receipt.png` | レシートの読み取り結果 | ストア |
| `04-voice.png` | 声の入力（聞いている表示） | ストア |
| `05-report.png` | 月のまとめ（予算の進みと、カテゴリ別のグラフと金額の行。下の端まで送って写す） | ストア |
| `06-recap.png` | 先週のふりかえりのカード | ストア |
| `07-premium.png` | プレミアムのシート（価格と購入のボタン） | 課金アイテム（プレミアム）の審査用。価格が写るのでストアには載せない（ガイドライン 2.3.7） |
| `08-trial.png` | プレミアムのシート（14 日間の無料体験） | 課金アイテム（14 日間の体験）の審査用。ストアには載せない |

写っているのは撮影用のデモの架空の記録（実在の人・店・記録ではない）。App Store Connect の iPhone のスクリーンショットは
6.9 インチの分だけあれば、小さい画面の分は自動で縮小される。

### 作り方

```bash
./scripts/app-store-screenshots.sh
```

- Debug のビルド（`make build`）を、撮影用の iPhone 17 Pro Max のシミュレータ（`SaifuLog App Store (iPhone 17 Pro Max)`。
  無ければ作る）に入れ、状態バーを 9:41・電波と Wi‑Fi と電池を満タンにし、ライトの外観で、日本語と英語の画面ごとに撮る。
  撮った画像は透過の層を外し（`scripts/screenshot-image.swift`。App Store Connect は透過のある画像を受け付けない。Dynamic Island が写り込んだら撮り直す）、大きさ（1320 × 2868）を
  確かめる。
- 言語や画面を絞るときは `SCREENSHOT_LANGUAGES=ja`・`SCREENSHOT_SCREENS="home ask"`。
- 撮ったら **1 枚ずつ目で確かめる**（表示崩れ・開発用の表示・iOS の知らせの写り込み・英語の画面の訳し忘れ）。リポジトリは公開なので、
  個人の情報や本物の記録が写った画像をコミットしない（撮影用のデモは架空の記録しか持たない）。
- 撮影用のデモは「いま」を**撮影の月の 15 日の 20:30** に置き、記録の日付はそこから相対で作る。月のどの日に撮っても同じ数字の
  画面になる（撮った日のままだと、月の最後の日には帯の「1日あたり」が「残り」と同じ額に、月のまとめの「今日までの目安」が予算と
  同じ額になり、月の初めには今月の記録が少ないため）。画面の日付（タイムラインの日付・レシートの日付）はその 15 日になる。

### 撮影用のデモ（`SaifuLog/ScreenshotDemo/`）

スクリプトは、アプリを起動引数 `-SaifuLogScreenshotDemo <画面>`（`home`・`ask`・`receipt`・`voice`・`report`・`recap`・`premium`・
`trial`）で開く。購入の状態は `-SaifuLogScreenshotPremium purchased|free` で選べる（省けば、`premium` と `trial` は無料、ほかは購入済み）。
Xcode の Run の Arguments に同じ引数を足しても開ける。

- **DEBUG のビルドだけに入る**（コードは `#if DEBUG` の中）。App Store へ出すビルドにも TestFlight のビルドにも入っていないことは、
  `make archive`（CI の `build` でも走る）がアーカイブの中の印の文字列（`release.mk` の `RELEASE_SCREENSHOT_DEMO_MARKER`）で確かめ、
  入っていれば止まる。スクリプトは、Debug のアプリに同じ印があることを確かめてから撮る（印の値の食い違いで、確かめが空振りしないように）。
- 保存先はメモリの上だけで、架空の記録（先月の 1 日からデモの「いま」（撮影の月の 15 日）まで、毎日。食費・カフェ・日用品・交通・娯楽・光熱・通信・医療と給料）と
  月の予算を入れる。利用者の記録のファイルは開かない。設定は専用の UserDefaults の領域を起動のたびに空にして使う。
- 初回の案内・診断画面のボタン（帯の聴診器）・App Store へ出すビルドで無効にしている機能は出さない。
- 端末によって変わるものは決まった中身にする。質問の答えとふりかえり・月のまとめの AI の一言は、端末内 AI が出しうる形の文で、
  数字の照合（`AnswerSentenceCheck`）を通るもの（英語の画面では、一言は日本語で書かれるので付けない）。レシートは架空の店の文字認識の
  結果、声は途中までの書き起こし、プレミアムの価格は日本の App Store の表示（`xcrun simctl` で起動したアプリは Xcode の StoreKit の
  設定ファイルを使えず、価格を読めないため）。
- 組み立て（件数・日付の範囲・カテゴリ）と、保存先と設定が使い捨てであることは、`SaifuLogTests/ScreenshotDemoTests.swift` で確かめている。
