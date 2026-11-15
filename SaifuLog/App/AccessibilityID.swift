/// 画面の要素の名前（accessibilityIdentifier）。UI テスト（SaifuLogUITests）が要素を探すのに使う。
///
/// 利用者には見えず、VoiceOver も読まない（読むのは accessibilityLabel）。表示の文や訳を変えても UI テストが要素を見失わない
/// よう、文ではなくここの名前で探す。UI テストのターゲットにも同じファイルを入れて（project.yml）、名前を 1 か所で決める
/// （アプリとテストで別々に書くと、片方だけ直して食い違うため）。
///
/// 名前は訳さない（String Catalog に入れない。`accessibilityIdentifier` は `String` を受け取るので、カタログには載らない）。
/// 付けるのは VoiceOver の要素になるもの（ボタン・入力欄・文・まとめた要素）だけにする。要素でない入れ物に付けると、中の要素
/// すべてに同じ名前が付き、VoiceOver の要素の分け方を変えずには入れ物を指せないため。
enum AccessibilityID {
    /// ホーム（会話のページ・上の帯・入力欄）。
    enum Home {
        /// 入力欄（記録や質問）。
        static let inputField = "home.inputField"
        /// 送信のボタン。
        static let sendButton = "home.sendButton"
        /// レシートを読み取るボタン（入力欄の左のカメラ）。
        static let receiptButton = "home.receiptButton"
        /// 帯の数字の要素（今月使った額・予算の残り。押すと月のまとめ）。値に読み上げる数字を持つ。
        static let monthFigures = "home.monthFigures"
        /// 帯の右上の設定のボタン。
        static let settingsButton = "home.settingsButton"
        /// 記録が無いときの案内の見出し。
        static let emptyTimeline = "home.emptyTimeline"
    }

    /// タイムラインの返事（記録の返事のカード・質問の答え・チャットの操作の知らせ）。
    enum Reply {
        /// 直前の送信の返事の「取り消す」。
        static let undoButton = "reply.undoButton"
        /// 記録 1 件の行（押すと ⑥ 直す）。カレンダーの選んだ日の記録の行も同じ名前。
        static let row = "reply.row"
        /// 聞き返しのカテゴリのボタン。`id` は `EntryCategory.id`（組み込みは "food"・"daily" など）。
        static func categoryChoice(_ id: String) -> String {
            "reply.category.\(id)"
        }
        /// 聞き返しの「カテゴリを作る」。
        static let createCategory = "reply.createCategory"
        /// 返事の下の、チャットでの直し方のヒント。
        static let correctionHint = "reply.correctionHint"
        /// チャットの操作や読めなかった文への知らせの見出し（「金額を直しました」など）。
        static let noticeTitle = "reply.noticeTitle"
        /// 質問の答えの数字と見出しの要素。
        static let answerSummary = "reply.answerSummary"
    }

    /// 月の画面の「カレンダー」。
    enum CalendarPage {
        /// 日のボタン（その月の何日か）。
        static func day(_ day: Int) -> String {
            "calendar.day.\(day)"
        }
    }

    /// 初回の案内（① ようこそ）。
    enum Onboarding {
        static let startButton = "onboarding.startButton"
    }

    /// 設定（⑧）の行。
    enum Settings {
        static let budget = "settings.budget"
        static let categories = "settings.categories"
        static let cards = "settings.cards"
        static let recurring = "settings.recurring"
        static let iCloudSync = "settings.iCloudSync"
        static let appLock = "settings.appLock"
        static let export = "settings.export"
        static let importCSV = "settings.importCSV"
        static let help = "settings.help"
        static let privacyPolicy = "settings.privacyPolicy"
    }

    /// ② 予算を決める。
    enum Budget {
        static let amountField = "budget.amountField"
        static let saveButton = "budget.saveButton"
    }

    /// ⑥ 直す。
    enum EditEntry {
        static let amountField = "editEntry.amountField"
        static let memoField = "editEntry.memoField"
        static let saveButton = "editEntry.saveButton"
        static let deleteButton = "editEntry.deleteButton"
    }

    /// カテゴリの一覧と、作る・直すシート。
    enum Categories {
        static let createButton = "categories.createButton"
        static let nameField = "categories.nameField"
        static let saveButton = "categories.saveButton"
    }

    /// くり返しの記録の一覧と、足す・直すシート。
    /// 月のまとめ（⑦）。
    enum Report {
        /// 上のバーの「内訳」と「カレンダー」の切り替え。
        static let tabPicker = "report.tabPicker"
        /// 下のバーの「前の月」。
        static let previousMonth = "report.previousMonth"
        /// 下のバーの「次の月」。
        static let nextMonth = "report.nextMonth"
        /// 下のバーの月の題。
        static let monthTitle = "report.monthTitle"
        /// 下のバーの「今月」（今月でないときだけ出す）。
        static let thisMonth = "report.thisMonth"
    }

    /// 設定の「カード」とカードを選ぶ欄。
    enum Cards {
        /// 一覧の「カードを登録」。
        static let addButton = "cards.addButton"
        /// 登録・直すシートの名前の欄。
        static let nameField = "cards.nameField"
        /// 登録・直すシートの保存。
        static let saveButton = "cards.saveButton"
        /// 一覧のカードの行（押すとその締めの記録）。
        static let row = "cards.row"
        /// 直す画面・レシート・くり返しの記録の、払ったカードを選ぶ欄。
        static let picker = "cards.picker"
    }

    enum Recurring {
        static let addButton = "recurring.addButton"
        static let amountField = "recurring.amountField"
        static let memoField = "recurring.memoField"
        static let saveButton = "recurring.saveButton"
    }

    /// ⑤ レシートの読み取り結果。
    enum Receipt {
        static let recordButton = "receipt.recordButton"
    }
}
