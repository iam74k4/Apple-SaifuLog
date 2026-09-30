import Foundation

/// 先に `primary`（AI）で読み、失敗したか何も読めなかったときは `fallback`（ルールベース）で読み直す。
///
/// AI の失敗（安全のための拒否、文脈の長さの超過、モデルの準備中など）を利用者に見せず、
/// 記録そのものは必ずできるようにするため。
public struct FallbackEntryParser: EntryParsing {
    public let primary: any EntryParsing
    public let fallback: any EntryParsing
    /// ルールベースで読み直すたびに、その理由を渡す（nil なら何もしない）。
    ///
    /// 利用者には見せないまま、AI が使える端末で AI が働いていないこと（生成が毎回失敗しているなど）に開発者が
    /// 気づけるようにするため。どう残すか（ログ・診断画面の記録）はアプリが決める（コアはログの仕組みに依存しない）。
    /// 読み直す前に、`parse` を呼んだ Task の上で呼ぶ。
    public let onFallback: (@Sendable (AIFallbackReason) -> Void)?

    public init(
        primary: any EntryParsing,
        fallback: any EntryParsing,
        onFallback: (@Sendable (AIFallbackReason) -> Void)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.onFallback = onFallback
    }

    public func parse(_ text: String) async throws -> [ParsedEntry] {
        do {
            let entries = try await primary.parse(text)
            if !entries.isEmpty { return entries }
            onFallback?(.noResult)
        } catch {
            // 取り消し（画面を閉じたなど）は失敗ではないので、読み直さずにそのまま伝える（理由も渡さない）。
            if error is CancellationError { throw error }
            onFallback?(.failed(error))
        }
        return try await fallback.parse(text)
    }
}

/// AI の結果を使わずに、ルールベース（キーワード辞書）で読み直した・答え直した理由。
///
/// `FallbackEntryParser` と、アプリの家計への質問の切り替え（`FallbackQuestionAnswerer`）が、呼び出し側に渡す。
public enum AIFallbackReason: Sendable {
    /// AI が失敗した（投げた）。取り消し（`CancellationError`）は含まない。
    case failed(any Error)
    /// AI は投げなかったが、使える結果を返さなかった（記録は 0 件、質問は読めない）。
    case noResult
}
