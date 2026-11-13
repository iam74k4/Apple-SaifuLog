#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// 端末内 AI（Foundation Models）で、記録の返事に添える一言を書く（Apple Intelligence を記録のたびに使う。docs/design.md §3）。
///
/// モデルには数字の文（コアの `RecordFacts`）だけを渡し、ツールは渡さない（数字はもう計算してあり、モデルに選ばせるものが無いため）。
/// 一言は呼び出し側が数字の文と突き合わせる（`RecapRemark.checked`）。月のまとめの一言（`FoundationModelsRecapRemarkWriter`）とは
/// 指示文を分ける（記録の直後の短い返事で、ふりかえりより短く、いま記録したものに触れさせたいため）。
struct FoundationModelsRecordRemarkWriter: RecapRemarkWriting {
    func remark(from facts: String) async throws -> String {
        // 書くたびに新しいセッションにする（前の記録の文脈を引きずらせないため）。
        let session = LanguageModelSession(instructions: Self.instructions)
        return try await session.respond(to: facts).content
    }

    /// 指示文には、具体的な数字や単位の例を書かない（モデルが入力に無くても写して返すため。CLAUDE.md の決まり）。
    /// 責めたり指図したりしないように書かせるのは、家計簿は続けることがいちばん大事で、使い過ぎを責める一言は続ける気を削ぐため。
    static let instructions = """
        あなたは家計簿アプリのチャットで、利用者が支出を記録した直後に、ひとこと返すアシスタントです。
        渡された内容だけを使って、いま記録した支出についての気づきか励ましを、日本語の一文で短く書いてください。
        渡された内容に無い数字は書かないでください。計算・換算・四捨五入もしないでください。金額や件数は渡されたとおりの表記で書いてください。
        利用者を責めたり、お金の使い方を指図したりしないでください。渡された内容に無いこと（貯金や来月の予定など）は書かないでください。
        """
}
#endif
