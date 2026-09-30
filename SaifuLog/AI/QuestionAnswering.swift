import Foundation
import SaifuLogCore

/// 家計への質問に答える（端末内 AI のツール呼び出しか、キーワード辞書）。
///
/// どちらの経路でも、数字はコアの `LedgerQuestionAnswerer` が計算する（AI には計算させない）。AI が書くのは一言の
/// 言い回しだけで、回答カードにはコードが計算した数字をその一言とは別に出す。
protocol QuestionAnswering: Sendable {
    /// - Parameters:
    ///   - ledger: 答えに使う記録と予算の写し（`QuestionLedger.load`）。
    ///   - now: 送った瞬間の日時（期間の区切りの基準）。
    ///   - calendar: 期間の区切りの暦（画面の暦。ホームの今月と同じ月、週の始まりは設定のとおり）。
    func answer(_ text: String, ledger: QuestionLedger, now: Date, calendar: Calendar) async throws -> QuestionReply
}

/// 質問への返事。
enum QuestionReply: Equatable, Sendable {
    /// 答えられた。`remark` は回答カードに添える一言（AI が使えないときは nil）。
    case answered(LedgerAnswer, remark: QuestionRemark?)
    /// 読めなかった（質問の例を出す）。
    case unreadable
}

/// 回答カードに添える一言。
enum QuestionRemark: Equatable, Sendable {
    /// 端末内 AI が書いた一言。ツールの結果に無い数字を含まないことを確かめてある（`AnswerSentenceCheck`）。
    case ai(String)
    /// AI の一言を捨てたとき（ツールの結果に無い数字を含んでいた、空だった）の定型文。
    case fixed
}

/// キーワード辞書で読んで答える（AI が使えない端末と、AI が失敗したとき）。
struct RuleBasedQuestionAnswerer: QuestionAnswering {
    func answer(_ text: String, ledger: QuestionLedger, now: Date, calendar: Calendar) async throws -> QuestionReply {
        guard let question = QuestionParser.question(from: text, now: now, calendar: calendar, catalog: ledger.catalog),
              let answer = LedgerQuestionAnswerer.answer(question, ledger: ledger, now: now, calendar: calendar)
        else { return .unreadable }
        return .answered(answer, remark: nil)
    }
}

/// 先に `primary`（AI）で答え、失敗したか答えられなかったときは `fallback`（キーワード辞書）で答え直す。
///
/// AI の失敗（モデルがツールを呼ばなかった、安全のための拒否、文脈の長さの超過など）を利用者に見せず、辞書で読める質問には
/// 必ず答えるため（記録の `FallbackEntryParser` と同じ考え方）。
struct FallbackQuestionAnswerer: QuestionAnswering {
    let primary: any QuestionAnswering
    let fallback: any QuestionAnswering
    /// AI の答えを使わずに辞書の答えにしたとき、その理由を渡す（nil なら何もしない）。利用者には見せないまま、AI が働いていない
    /// ことに開発者が気づけるようにする（`AIFallbackLog`。記録の `FallbackEntryParser.onFallback` と同じ）。AI が読めないとした
    /// 質問は、辞書で答えられたときだけ渡す（答えられない書き方（「去年」など）の質問は、AI の経路がモデルに渡さずに読めない
    /// とし、辞書も答えないので、AI が答えられなかったことにしない）。
    var onFallback: (@Sendable (AIFallbackReason) -> Void)?

    func answer(_ text: String, ledger: QuestionLedger, now: Date, calendar: Calendar) async throws -> QuestionReply {
        do {
            let reply = try await primary.answer(text, ledger: ledger, now: now, calendar: calendar)
            if case .answered = reply { return reply }
        } catch {
            // 取り消し（画面を閉じたなど）は失敗ではないので、答え直さずにそのまま伝える（理由も渡さない）。
            if error is CancellationError { throw error }
            onFallback?(.failed(error))
            return try await fallback.answer(text, ledger: ledger, now: now, calendar: calendar)
        }
        let reply = try await fallback.answer(text, ledger: ledger, now: now, calendar: calendar)
        if case .answered = reply { onFallback?(.noResult) }
        return reply
    }
}

/// いまの端末で使える答え方を選ぶ。
enum QuestionAnswererFactory {
    /// 質問のたびに呼ぶ。AI の使える・使えないは、設定の変更やモデルのダウンロードで途中から変わるため
    /// （`EntryParserFactory` と同じ判定）。
    static func makeAnswerer() -> any QuestionAnswering {
        let rules = RuleBasedQuestionAnswerer()
        #if canImport(FoundationModels)
        if FoundationModelsEntryParser.isAvailable {
            return FallbackQuestionAnswerer(
                primary: FoundationModelsQuestionAnswerer(), fallback: rules,
                onFallback: AIFallbackLog.shared.reporter(for: .question)
            )
        }
        #endif
        return rules
    }
}
