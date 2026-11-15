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
/// 記録した内容と「取り消す」を出す。ショートカット App からも使える。
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
    }
}
