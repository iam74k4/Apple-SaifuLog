#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// 端末内 AI（Foundation Models）で、ふりかえりの一言を書く。
///
/// モデルには数字の文（`RecapFacts`）だけを渡し、ツールは渡さない（数字はもう計算してあり、モデルに選ばせるものが無いため）。
/// 一言は呼び出し側が数字の文と突き合わせる（`RecapRemark.checked`）。
struct FoundationModelsRecapRemarkWriter: RecapRemarkWriting {
    func remark(from facts: String) async throws -> String {
        // 書くたびに新しいセッションにする（前の週や月の文脈を引きずらせないため）。
        let session = LanguageModelSession(instructions: Self.instructions)
        return try await session.respond(to: facts).content
    }

    /// 指示文には、具体的な数字や単位の例を書かない（モデルが入力に無くても写して返すため。CLAUDE.md の決まり）。
    /// 責めたり指図したりしないように書かせるのは、家計簿は続けることがいちばん大事で、使い過ぎを責める一言は続ける気を削ぐため。
    static let instructions = """
        あなたは家計簿アプリの中で、利用者の支出のふりかえりに、ひとこと添えるアシスタントです。
        渡された内容だけを使って、励ましか気づきを、日本語の一文か二文で短く書いてください。
        渡された内容に無い数字は書かないでください。計算・換算・四捨五入もしないでください。金額は渡されたとおりの表記で書いてください。
        利用者を責めたり、お金の使い方を指図したりしないでください。渡された内容に無いこと（貯金や来月の予定など）は書かないでください。
        """
}
#endif
