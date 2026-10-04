import Foundation
import SaifuLogCore

/// ホームのタイムラインに出す、質問 1 つとその返事。記録にならなかった送信（記録か質問か決められない文・前の記録を直そうと
/// する文・金額の無い文）と、その案内もこの形で出す。
///
/// 質問は記録ではないので保存しない（アプリを開き直すと消える。docs/design.md §9 の質問の決め事）。タイムラインには、
/// 記録の吹き出しと同じ流れ（送った順）に、質問の吹き出しと回答カードとして出す。
struct QuestionExchange: Identifiable, Equatable {
    let id: UUID
    /// 送った質問の文。
    let text: String
    /// 送った瞬間の日時。タイムラインの並び（記録した日時と同じく送った順）に使う。
    let askedAt: Date
    var state: State

    init(id: UUID = UUID(), text: String, askedAt: Date, state: State = .answering) {
        self.id = id
        self.text = text
        self.askedAt = askedAt
        self.state = state
    }

    enum State: Equatable {
        /// 答えを計算している（AI だと 1 秒以上かかることがある）。
        case answering
        /// 答えた。`freeQuestionsLeft` は、無料の残りの回数が少ないとき（3 回以下）だけ入る（プレミアムと体験中は nil）。
        case answered(LedgerAnswer, remark: QuestionRemark?, freeQuestionsLeft: Int?)
        /// 読めなかった。質問の例を出す。
        case unreadable
        /// 記録か質問か決められなかった（金額と質問の語が両方ある）。記録しない。
        case unclear
        /// 前の記録を直そうとする文だった（「さっきのを900に直して」）。記録を直さず、新しい記録にもしない。
        case correction
        /// 記録として送った文に、金額が見つからなかった（「ランチ」）。記録しない。前はアラートで知らせていたが、閉じるまで
        /// キーボードが下がって流れが止まり、送った文もタイムラインに残らなかったので、ほかの案内と同じくタイムラインに出す。
        case noAmount
        /// 今月の無料の回数を使い切った。答えずに、プレミアムの案内を出す。
        case limitReached
        /// 保存先を読めなかった。
        case loadFailed

        /// 質問として読んだ文か。記録か質問か決められなかった文・記録を直そうとする文・金額の無い文は、質問として扱っていない
        /// ので、VoiceOver でも「質問」と名乗らない（下の案内と食い違うため）。
        var isQuestion: Bool {
            self != .unclear && self != .correction && self != .noAmount
        }
    }
}
