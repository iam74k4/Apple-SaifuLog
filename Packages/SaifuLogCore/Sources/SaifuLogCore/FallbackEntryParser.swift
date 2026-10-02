import Foundation

/// 先に `primary`（AI）で読み、失敗したか、上限の時間までに返らなかったか、何も読めなかったときは `fallback`（ルールベース）で
/// 読み直す。
///
/// AI の失敗（安全のための拒否、文脈の長さの超過、モデルの準備中など）や、返らないまま止まったことを利用者に見せず、
/// 記録そのものは必ずできるようにするため。
public struct FallbackEntryParser: EntryParsing {
    public let primary: any EntryParsing
    public let fallback: any EntryParsing
    /// AI を待つ上限。過ぎたら AI が終わるのを待たずに、ルールベースで読む（nil なら上限なし）。
    ///
    /// 端末内のモデルが返らないまま止まると、読み取りが終わらず、次の文を送れないうえ、保存先の開き直し（iCloud の切り替え）
    /// までが待ち続けるため。値はアプリが決める（`AITimeouts`）。
    public let timeout: Duration?
    /// AI の結果を使わずにルールベースの結果にしたとき、その理由を渡す（nil なら何もしない）。
    ///
    /// 利用者には見せないまま、AI が使える端末で AI が働いていないこと（生成が毎回失敗している・時間切れになっているなど）に開発者が
    /// 気づけるようにするため。どう残すか（ログ・診断画面の記録）はアプリが決める（コアはログの仕組みに依存しない）。
    /// `parse` を呼んだ Task の上で呼ぶ。失敗と時間切れは読み直す前に渡す。AI が何も読めなかったときは、ルールベースでは読めたときだけ
    /// 読み直した後に渡す（どちらも読めない文（金額の無い文など）は、AI の経路がモデルに渡さずに 0 件を返すので、AI が
    /// 読み落としたことにしない）。
    public let onFallback: (@Sendable (AIFallbackReason) -> Void)?

    public init(
        primary: any EntryParsing,
        fallback: any EntryParsing,
        timeout: Duration? = nil,
        onFallback: (@Sendable (AIFallbackReason) -> Void)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.timeout = timeout
        self.onFallback = onFallback
    }

    public func parse(_ text: String) async throws -> [ParsedEntry] {
        do {
            let entries = try await parseWithPrimary(text)
            if !entries.isEmpty { return entries }
        } catch {
            // 取り消し（画面を閉じたなど）は失敗ではないので、読み直さずにそのまま伝える（理由も渡さない）。
            if error is CancellationError { throw error }
            onFallback?(AIFallbackReason(error: error))
            return try await fallback.parse(text)
        }
        let entries = try await fallback.parse(text)
        if !entries.isEmpty { onFallback?(.noResult) }
        return entries
    }

    /// `primary` で読む。上限があれば、過ぎたときに `DeadlineExceeded` を投げる（`primary` が終わるのは待たない）。
    private func parseWithPrimary(_ text: String) async throws -> [ParsedEntry] {
        guard let timeout else { return try await primary.parse(text) }
        let primary = primary
        return try await withDeadline(timeout) { try await primary.parse(text) }
    }
}

/// AI の結果を使わずに、ルールベース（キーワード辞書）で読み直した・答え直した（ふりかえりは定型文だけにした）理由。
///
/// `FallbackEntryParser` と、アプリの家計への質問の切り替え（`FallbackQuestionAnswerer`）が、呼び出し側に渡す。ふりかえりの一言と
/// レシートの品名の整えも、アプリがこの理由で残す（`AIFallbackLog`）。
public enum AIFallbackReason: Sendable {
    /// AI が失敗した（投げた）。取り消し（`CancellationError`）と時間切れは含まない。
    case failed(any Error)
    /// AI が上限の時間（値）までに返らなかった。呼び出した Task の取り消しは含まない（`withDeadline` が取り消しとして投げる）。
    case timedOut(Duration)
    /// AI は投げなかったが使える結果を返さず（記録は 0 件、質問は読めない）、ルールベースでは読めた（答えられた）。
    case noResult

    /// AI を呼んで投げられたエラーの理由。上限を過ぎた（`DeadlineExceeded`）なら時間切れ、ほかは失敗。
    ///
    /// 取り消しかどうかは見分けない（取り消しは理由として渡さないので、呼び出し側が先に除く）。
    public init(error: any Error) {
        if let exceeded = error as? DeadlineExceeded {
            self = .timedOut(exceeded.timeout)
        } else {
            self = .failed(error)
        }
    }
}
