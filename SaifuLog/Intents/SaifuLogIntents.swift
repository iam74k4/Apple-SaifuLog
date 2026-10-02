import AppIntents
import Foundation
import SaifuLogCore

// Siri・ショートカット・Spotlight・アクションボタンから使える操作（App Intents）。docs/design.md §9 のショートカットの決め事。
//
// どれもアプリを前面に出してから行う（`openAppWhenRun`）。記録や質問をアプリを開かずに済ませないのは、保存先を
// NSFileProtectionComplete で守っていてロック中は読めないのと、記録したものを返事のカードで見せ、読み違いをその場で
// 取り消したり直したりできるようにするため（Siri の聞き違いも、ここで気づける）。頼みは受け箱（`QuickActionInbox`）に置き、
// ホームが出たら行う。

/// ひとことを送って記録する（「ランチ 850」）。ふつうの送信と同じく、記録か質問かはアプリが見分け、返事のカードに
/// 記録した内容と「取り消す」を出す。ショートカットのオートメーション（Apple Pay で払ったときなど）からも使える。
struct RecordEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "ひとことで記録"
    static let description = IntentDescription("「ランチ 850」のようなひとことを送って記録します。アプリを開いて、記録した内容を返事で見せます。")
    static let openAppWhenRun = true

    @Parameter(title: "記録する文", requestValueDialog: IntentDialog("何を記録しますか？"))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionInbox.shared.post(.record(text))
        return .result()
    }
}

/// 家計に質問する（「今月カフェいくら?」）。答えはホームの回答カードに出す。
struct AskQuestionIntent: AppIntent {
    static let title: LocalizedStringResource = "家計に質問"
    static let description = IntentDescription("「今月カフェいくら?」のように家計について聞きます。アプリを開いて、答えをタイムラインに出します。")
    static let openAppWhenRun = true

    @Parameter(title: "質問", requestValueDialog: IntentDialog("何を聞きますか？"))
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionInbox.shared.post(.ask(question))
        return .result()
    }
}

/// アプリを開いて、入力欄に文字を打てるようにする（キーボードを出す）。
struct ComposeEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "入力欄を開く"
    static let description = IntentDescription("アプリを開いて、すぐに打てるよう入力欄にキーボードを出します。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionInbox.shared.post(.compose)
        return .result()
    }
}

/// アプリを開いて、レシートを読み取る（カメラのボタンを押したときと同じ）。
struct ScanReceiptIntent: AppIntent {
    static let title: LocalizedStringResource = "レシートを読み取る"
    static let description = IntentDescription("アプリを開いて、レシートを撮るか写真から選ぶ画面を出します。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionInbox.shared.post(.receipt)
        return .result()
    }
}

/// アプリを開いて、声で入力する（マイクのボタンを押したときと同じ。送信は利用者が押したときだけ）。
struct VoiceEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "声で入力"
    static let description = IntentDescription("アプリを開いて、話した内容を入力欄に入れます。送るのは、あなたが送信を押したときだけです。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionInbox.shared.post(.voice)
        return .result()
    }
}

/// Apple Pay で払ったときのオートメーション（ショートカットの「取引」）から、金額と店名を受け取る。アプリは開かない。
///
/// 払った直後は iPhone がロックされていることが多く、記録の保存先（NSFileProtectionComplete）には書けないので、受け取った
/// 支払いを受け箱（`PaymentInbox`）に置き、次にアプリを開いたときに記録にして返事で見せる（違っていれば取り消せる）。
/// 金額はウォレットの値をそのまま使う（AI にも文の読み取りにも通さない）。円のほかの通貨は記録しない。
struct RecordPaymentIntent: AppIntent {
    static let title: LocalizedStringResource = "支払いを記録"
    // 題名と説明には「Apple」の語を書かない（App Store Connect がアップロードを ITMS-90626 で弾く。「Apple Pay」も同じ）。
    // 文言はテストで確かめる（`AppIntentMetadataTests`）。
    static let description = IntentDescription(
        "ウォレットで払ったときのオートメーション（ショートカットの「取引」）で使います。金額と店名を受け取り、次にサイフログを開いたときに記録します。"
    )
    static let openAppWhenRun = false

    @Parameter(title: "金額")
    var amount: IntentCurrencyAmount

    @Parameter(title: "店名")
    var merchant: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$merchant) の \(\.$amount) を記録")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let yen = PaymentCapture.yenAmount(amount.amount, currencyCode: amount.currencyCode) else {
            throw amount.currencyCode.uppercased() == PaymentCapture.currencyCode ? PaymentCaptureError.invalidAmount : .notYen
        }
        do {
            try PaymentInbox.shared.append(amount: yen, merchant: merchant ?? "", paidAt: .now)
        } catch {
            throw PaymentCaptureError.saveFailed
        }
        let text = YenFormatter.string(from: yen)
        return .result(dialog: IntentDialog("\(text) を受け取りました。サイフログを開くと記録します。"))
    }
}

/// 支払いを受け取れなかった理由（ショートカットに出す）。
enum PaymentCaptureError: Error, CustomLocalizedStringResourceConvertible {
    /// 円のほかの通貨。
    case notYen
    /// 1 円未満か、記録できる上限を超える。
    case invalidAmount
    /// 受け箱に書けなかった。
    case saveFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notYen: "円のほかの通貨の支払いは記録しません。"
        case .invalidAmount: "記録できない金額です。"
        case .saveFailed: "支払いを受け取れませんでした。もう一度お試しください。"
        }
    }
}

/// Siri と Spotlight とアクションボタンに出す操作と、呼び出しの言い方。言い方にはアプリの名前を入れる（App Shortcuts の決まり）。
/// 英語の言い方は `AppShortcuts.xcstrings` に置く。
struct SaifuLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordEntryIntent(),
            phrases: ["\(.applicationName)で記録", "\(.applicationName)に記録", "\(.applicationName)に記録して"],
            shortTitle: "ひとことで記録",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: AskQuestionIntent(),
            phrases: ["\(.applicationName)に質問", "\(.applicationName)で家計を聞く"],
            shortTitle: "家計に質問",
            systemImageName: "questionmark.bubble"
        )
        AppShortcut(
            intent: ScanReceiptIntent(),
            phrases: ["\(.applicationName)でレシートを読み取る", "\(.applicationName)でレシート"],
            shortTitle: "レシートを読み取る",
            systemImageName: "receipt"
        )
        AppShortcut(
            intent: VoiceEntryIntent(),
            phrases: ["\(.applicationName)で声で入力", "\(.applicationName)で声で記録"],
            shortTitle: "声で入力",
            systemImageName: "mic"
        )
        AppShortcut(
            intent: ComposeEntryIntent(),
            phrases: ["\(.applicationName)の入力欄を開く", "\(.applicationName)で入力"],
            shortTitle: "入力欄を開く",
            systemImageName: "keyboard"
        )
    }
}
