import Foundation

/// 先に `primary`（AI）で読み、失敗したか何も読めなかったときは `fallback`（ルールベース）で読み直す。
///
/// AI の失敗（安全のための拒否、文脈の長さの超過、モデルの準備中など）を利用者に見せず、
/// 記録そのものは必ずできるようにするため。
public struct FallbackEntryParser: EntryParsing {
    public let primary: any EntryParsing
    public let fallback: any EntryParsing
    /// AI の結果を使わずにルールベースの結果にしたとき、その理由を渡す（nil なら何もしない）。
    ///
    /// 利用者には見せないまま、AI が使える端末で AI が働いていないこと（生成が毎回失敗しているなど）に開発者が
    /// 気づけるようにするため。どう残すか（ログ・診断画面の記録）はアプリが決める（コアはログの仕組みに依存しない）。
    /// `parse` を呼んだ Task の上で呼ぶ。失敗は読み直す前に渡す。AI が何も読めなかったときは、ルールベースでは読めたときだけ
    /// 読み直した後に渡す（どちらも読めない文（金額の無い文など）は、AI の経路がモデルに渡さずに 0 件を返すので、AI が
    /// 読み落としたことにしない）。
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
        } catch {
            // 取り消し（画面を閉じたなど）は失敗ではないので、読み直さずにそのまま伝える（理由も渡さない）。
            if error is CancellationError { throw error }
            onFallback?(.failed(error))
            return try await fallback.parse(text)
        }
        let entries = try await fallback.parse(text)
        if !entries.isEmpty { onFallback?(.noResult) }
        return entries
    }
}

/// AI の結果を使わずに、ルールベース（キーワード辞書）で読み直した・答え直した理由。
///
/// `FallbackEntryParser` と、アプリの家計への質問の切り替え（`FallbackQuestionAnswerer`）が、呼び出し側に渡す。
public enum AIFallbackReason: Sendable {
    /// AI が失敗した（投げた）。取り消し（`CancellationError`）は含まない。
    case failed(any Error)
    /// AI は投げなかったが使える結果を返さず（記録は 0 件、質問は読めない）、ルールベースでは読めた（答えられた）。
    case noResult
}
