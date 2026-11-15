#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SaifuLogCore

/// 端末内 AI に、数字の文（`RecordFacts`・`RecapFacts`）から一言を書かせる（記録の返事の一言・月のまとめの一言）。
///
/// 2026-11-15 に本物のモデルで試して、次の 2 つにした。
/// - **最初の一文が書き終わったら、続きを待たない。** 画面に出すのは記号を外した最初の一文だけ（`RecapRemark.checked`）なのに、
///   モデルは一文と頼んでも改行して何文も続け、待つ時間の多くが使わない文に掛かっていた（最後まで待つと 1 回で 1 秒ほど、最初の
///   一文で打ち切ると 0.5 秒ほど。打ち切っても、次の生成は遅くならなかった）。
/// - **安全のための拒否か、照合に通らない一言なら、もう一度だけ書かせる。** 家計の数字の文でも安全のための拒否（`guardrailViolation`）が
///   1 割ほど起き、照合（渡していない割合を計算して書いたなど）で捨てる一言も同じくらいあった。温度を下げてあるが揺れは残るので、
///   書き直すと通ることが多い。2 回とも使えなければ、最後に書いた文を返すか（呼び出し側の照合が捨てて定型の一行にする）、拒否を投げる。
enum RemarkGeneration {
    /// 書かせる回数の上限（1 回目を含む）。上限の時間（`AITimeouts.recordRemark` の 3 秒）に 2 回収まるようにする。
    static let attempts = 2

    static func remark(instructions: String, facts: String, options: GenerationOptions) async throws -> String {
        var written: String?
        var refusal: (any Error)?
        for _ in 0..<attempts {
            try Task.checkCancellation()
            do {
                let text = try await firstSentence(instructions: instructions, facts: facts, options: options)
                if RecapRemark.checked(text, facts: facts) != nil { return text }
                written = text
            } catch let error as LanguageModelSession.GenerationError {
                guard case .guardrailViolation = error else { throw error }
                refusal = error
            }
        }
        if let written { return written }
        throw refusal ?? CancellationError()
    }

    /// 書かせるたびに新しいセッションにし（前の一言の文脈を引きずらせないため）、最初の一文の後ろに次の文字が届いたところで受け取るのを
    /// やめる（文の終わりの記号と閉じかっこが続くあいだは待つ。「…ね。」」）。
    private static func firstSentence(instructions: String, facts: String, options: GenerationOptions) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        var text = ""
        for try await snapshot in session.streamResponse(to: facts, options: options) {
            text = snapshot.content
            if let last = text.last, !sentenceTail.contains(last), AnswerSentenceCheck.plainSentence(text) != nil { break }
        }
        return text
    }

    /// 文の終わりの記号と、その後ろに続いてよい閉じかっこ（`AnswerSentenceCheck.plainSentence` と同じ）。
    private static let sentenceTail: Set<Character> = ["。", "！", "？", "!", "?", "」", "』", "）", ")"]
}
#endif
