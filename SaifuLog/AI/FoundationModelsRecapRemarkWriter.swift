#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// 端末内 AI（Foundation Models）で、月のまとめの一言を書く。
///
/// モデルには数字の文（`RecapFacts`）だけを渡し、ツールは渡さない（数字はもう計算してあり、モデルに選ばせるものが無いため）。
/// 一言は呼び出し側が数字の文と突き合わせる（`RecapRemark.checked`）。
struct FoundationModelsRecapRemarkWriter: RecapRemarkWriting {
    func remark(from facts: String) async throws -> String {
        // 最初の一文で打ち切り、使えなければもう一度だけ書かせる（`RemarkGeneration`。記録の返事の一言と同じ）。
        try await RemarkGeneration.remark(instructions: Self.instructions, facts: facts, options: Self.options)
    }

    /// 長さの上限（トークン）と温度。2026-11-15 に本物のモデルで試したとき、上限が無いと太字の箇条書きを長く書き続け、1 件は
    /// 見張りの 30 秒を過ぎた。温度は記録の返事の一言（`FoundationModelsRecordRemarkWriter.options`）と同じ理由で下げる。
    static let options = GenerationOptions(temperature: 0.5, maximumResponseTokens: 150)

    /// 指示文には、具体的な数字や単位の例を書かない（モデルが入力に無くても写して返すため。CLAUDE.md の決まり）。
    /// 責めたり指図したりしないように書かせるのは、家計簿は続けることがいちばん大事で、使い過ぎを責める一言は続ける気を削ぐため。
    /// 数字の頼み方と、画面に出す前に最初の一文だけにすること（`RecapRemark.checked`）は、記録の返事の一言と同じ。前は「一文か二文」と
    /// 頼んでいたが、モデルは箇条書きで何文も書いたので、一文と頼む。
    static let instructions = """
        あなたは家計簿アプリの中で、利用者のひと月の支出のふりかえりに、ひとこと添えるアシスタントです。
        渡された内容だけを使って、その月の支出についての、やさしい気づきか励ましの短い一文を日本語で書いてください。
        数字を入れるときは、渡された内容の金額・件数・割合から 1 つだけ選び、渡されたとおりの表記で写してください。数字を新しく作ったり、計算したりしないでください。
        利用者を責めたり、お金の使い方を指図したりしないでください。渡された内容に無いこと（貯金や来月の予定など）は書かないでください。
        記号で飾らず、ふつうの文だけで書いてください。
        """
}
#endif
