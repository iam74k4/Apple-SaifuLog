import Foundation
import SaifuLogCore
import SwiftData

/// 書き出した CSV を読み、どの記録を入れるかを決める（設定の「CSV から読み込む」）。読み方はコアの `LedgerCSVReader`、
/// 入れる記録の決め方は `LedgerCSVImport` が受け持つ。
///
/// ファイルを読むのと、保存先の記録と比べるのは、メインスレッドの外で行う（`LedgerExporter` と同じ理由。記録が 1 万件あると、
/// 読んで比べるまでに画面が止まって見えるほどかかるため）。保存先はメインの ModelContext を使わず、同じ保存先（コンテナ）から
/// 読むための ModelContext を作って読む。ここでは読むだけで書き込まない（書き込むのは、利用者が件数を確かめて「読み込む」を
/// 押した後の `SettingsModel.confirmImport`）ので、保存先の開き直しが待つ処理（`StoreHost.pendingWrites`）には数えない。
struct LedgerImporter: Sendable {
    /// 読み込む前に確かめてもらう中身。
    struct Preview: Sendable, Equatable {
        /// 入れる記録の行（ファイルの順）。
        let rows: [LedgerCSVReader.Row]
        /// すでに同じ記録があるので飛ばす行の数。
        let duplicateCount: Int
        /// 読めなかった行の数。
        let unreadableCount: Int

        var importCount: Int { rows.count }
    }

    let container: ModelContainer
    /// 保存先から読み始める直前に、読み込みを進めているところで呼ぶ。アプリでは渡さない（`LedgerExporter.willRead` と同じく、
    /// テストで、読み込みがメインスレッドの外で進むかを確かめるため）。
    let willRead: (@Sendable () -> Void)?

    init(container: ModelContainer, willRead: (@Sendable () -> Void)? = nil) {
        self.container = container
        self.willRead = willRead
    }

    /// ファイルを読み、入れる記録を決める。読めないファイルは `LedgerCSVReader.ReadError` を投げる。
    /// - Parameters:
    ///   - url: 利用者がファイルを選ぶ画面で選んだファイル（アプリの外のファイルなので、読む間だけ使う許可を得る）。
    ///   - timeZone: 日付と時刻を読む時間帯（書き出しと同じく、画面の暦の時間帯）。
    ///   - catalog: 作ったカテゴリの一覧（カテゴリを名前で戻す）。
    @concurrent
    func preview(fileAt url: URL, timeZone: TimeZone, catalog: CategoryCatalog) async throws -> Preview {
        let data = try Self.readFile(at: url)
        try Task.checkCancellation()
        let result = try LedgerCSVReader.read(data, timeZone: timeZone, catalog: catalog)
        try Task.checkCancellation()
        willRead?()
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<Entry>()).map {
            LedgerCSVImport.Key(spentAt: $0.spentAt, amount: $0.amount, isIncome: $0.isIncome, category: $0.category, memo: $0.memo)
        }
        try Task.checkCancellation()
        let plan = LedgerCSVImport.plan(rows: result.rows, existing: existing)
        return Preview(rows: plan.rows, duplicateCount: plan.duplicateCount, unreadableCount: result.issues.count)
    }

    /// ファイルの中身を、上限（`LedgerCSVReader.maximumBytes`）を超えない分だけ読む。超えていれば `tooLarge` を投げる。
    ///
    /// 大きさを先に調べず、上限より 1 バイト多く読んで確かめる（大きなファイルを丸ごとメモリに読まないため。ファイルの属性を
    /// 読む API は、プライバシーマニフェストで理由の申告が要るものがあるので使わない）。
    static func readFile(at url: URL) throws -> Data {
        // ファイルを選ぶ画面で選んだファイルは、アプリの外（ファイル App・iCloud Drive など）にあるので、読む間だけ使う許可を得る。
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: LedgerCSVReader.maximumBytes + 1) ?? Data()
        guard data.count <= LedgerCSVReader.maximumBytes else { throw LedgerCSVReader.ReadError.tooLarge }
        return data
    }

    /// 入れる行から、保存する記録を作る。入力元は CSV からの読み込み（`.imported`）、記録した日時は使った日時
    /// （`LedgerCSVImport.createdAt`）。カテゴリの聞き返し・くり返しの記録の印・覚えたカテゴリは付けない（過去の記録を
    /// 戻すだけで、いま記録したものではないため）。
    static func entries(from rows: [LedgerCSVReader.Row]) -> [Entry] {
        zip(rows, LedgerCSVImport.createdAt(for: rows)).map { row, createdAt in
            Entry(
                amount: row.amount,
                isIncome: row.isIncome,
                category: row.category,
                memo: row.memo,
                spentAt: row.spentAt,
                createdAt: createdAt,
                source: .imported,
                originalText: row.originalText
            )
        }
    }
}
