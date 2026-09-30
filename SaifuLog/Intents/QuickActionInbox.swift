import Foundation
import Observation

/// Siri・ショートカット・Spotlight・アクションボタンからの頼み（`SaifuLogIntents`）。アプリを開いてから、ホームが行う。
enum QuickAction: Equatable, Sendable {
    /// ひとことを送って記録する（ふつうの送信と同じく、記録か質問かはアプリが見分ける）。
    case record(String)
    /// 家計に質問する（質問として答える）。
    case ask(String)
    /// 入力欄に文字を打てるようにする（キーボードを出す）。
    case compose
    /// レシートを読み取る（カメラのボタンを押したときと同じ）。
    case receipt
    /// 声で入力する（マイクのボタンを押したときと同じ。送信は利用者が押したときだけ）。
    case voice
}

/// Siri・ショートカットからの頼みを、ホームが受け取るまで持っておく受け箱（アプリで 1 つ）。
///
/// 頼み（App Intents の `perform()`）はアプリを前面に出してから、アプリの中で動く。そのときホームがまだ出ていない（起動の途中・
/// 保存先を開く前・初回の案内の間・ロックの解除の前）ことがあるので、ここに置いておき、ホームが出たときと、置かれたときに
/// ホームが受け取る（`HomeModel.receive`）。持つのは最後の 1 つだけ（続けて頼まれたら、新しいほうを行う）。
@MainActor
@Observable
final class QuickActionInbox {
    static let shared = QuickActionInbox()

    /// まだホームが受け取っていない頼み。
    private(set) var pending: QuickAction?

    func post(_ action: QuickAction) {
        pending = action
    }

    /// 受け取る（受け取ったら空にする）。
    func take() -> QuickAction? {
        defer { pending = nil }
        return pending
    }
}
