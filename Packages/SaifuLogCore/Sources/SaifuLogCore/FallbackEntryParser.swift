import Foundation

/// 先に `primary`（AI）で読み、失敗したか何も読めなかったときは `fallback`（ルールベース）で読み直す。
///
/// AI の失敗（安全のための拒否、文脈の長さの超過、モデルの準備中など）を利用者に見せず、
/// 記録そのものは必ずできるようにするため。
public struct FallbackEntryParser: EntryParsing {
    public let primary: any EntryParsing
    public let fallback: any EntryParsing

    public init(primary: any EntryParsing, fallback: any EntryParsing) {
        self.primary = primary
        self.fallback = fallback
    }

    public func parse(_ text: String) async throws -> [ParsedEntry] {
        do {
            let entries = try await primary.parse(text)
            if !entries.isEmpty { return entries }
        } catch {
            // 取り消し（画面を閉じたなど）は失敗ではないので、読み直さずにそのまま伝える。
            if error is CancellationError { throw error }
        }
        return try await fallback.parse(text)
    }
}
