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
        /// 直前の記録のカテゴリを、チャットの文（「それ日用品」）で直した。`item` は品目、`category` は直した先のカテゴリの名前、
        /// `remembered` は次から同じ品目をそのカテゴリにするか（品目を覚えられたか）。
        case recategorized(item: String, category: String, remembered: Bool)
        /// 直前の記録の金額を、チャットの文（「さっきのを900に直して」）で直した。
        case amountChanged(item: String, from: Int, to: Int)
        /// 直前の記録を、チャットの文（「さっきの消して」）で消した。`summary` は消した記録の要約。
        case removed(summary: String)
        /// 端末内 AI が選んだ操作を行う前に、確認を出した（行えば結果の状態に、やめれば `commandCancelled` に替わる）。
        case commandAsked(CommandQuestion)
        /// 端末内 AI が選んだ操作を、確認で「キャンセル」にした。何も変えていない。
        case commandCancelled
        /// 月の全体の予算を、チャットの文（「今月の予算を5万にして」）で決めた。
        case budgetSet(amount: Int)
        /// チャットの文で直す・消す操作を頼まれたが、相手にできる直前の記録が無かった（質問の後・取り消した後・くり返しの記録の後）。
        case noTarget
        /// 割り勘の記録の金額を、チャットの文で直そうとした。1 人分の額を記録しているので、書いた金額が 1 人分か合計か決められず、
        /// 直していない（⑥ で直してもらう）。
        case splitNotChanged
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
            switch self {
            case .unclear, .correction, .noAmount, .recategorized, .amountChanged, .removed, .commandAsked, .commandCancelled,
                 .budgetSet, .noTarget, .splitNotChanged:
                false
            case .answering, .answered, .unreadable, .limitReached, .loadFailed: true
            }
        }
    }
}

/// 端末内 AI が選んだチャットの操作の確認（何をするか）。確認のアラートと、タイムラインの返事のカードに同じ内容を出す。
///
/// 端末内のモデルは小さく、文の読み違いがある。AI が選んだ操作は、決まりで読んだ操作と違い、すぐには行わずに確かめる
/// （黙って記録や予算を書き換えないため）。
enum CommandQuestion: Equatable {
    /// 直前の記録（`summary`。「ランチ ¥850」）のカテゴリを `category`（名前）にする。
    case recategorize(summary: String, category: String)
    /// 直前の記録の金額を `amount` にする。
    case changeAmount(summary: String, amount: Int)
    /// 直前の送信の記録（`summary`。複数ならまとめた要約）を消す。
    case remove(summary: String)
    /// 月の全体の予算を `amount` にする。
    case setMonthlyBudget(amount: Int)

    /// 消す確認か（確認のボタンを、取り消せない操作の見た目にする）。
    var isDestructive: Bool {
        if case .remove = self { true } else { false }
    }
}
