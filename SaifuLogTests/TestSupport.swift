import Foundation
import SaifuLogCore
import SwiftData
@testable import SaifuLog

/// テストで使う固定の日時と暦、メモリの上だけの保存先。
enum TestSupport {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-09-28 12:00（日本時間）。
    static let now = date(2026, 9, 28, hour: 12)

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// テストごとに新しい保存先を作る。前のテストの記録が残らないよう、ファイルには書かない。
    ///
    /// アプリと同じ `ModelContainerFactory` で作る（モデルの一覧と iCloud を切る設定をアプリと食い違わせないため）。
    /// SwiftData の `ModelConfiguration(isStoredInMemoryOnly:)` を直接使うと iCloud が既定の `.automatic` になり、
    /// iCloud の entitlement を足した時点で、テストが iCloud と同期しようとする。
    @MainActor
    static func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        // mainContext はコンテナが生きている間しか使えないので、コンテナごと保持させる。
        let context = container.mainContext
        retained.append(container)
        return context
    }

    @MainActor private static var retained: [ModelContainer] = []

    static func entry(
        amount: Int = 850, category: EntryCategory = .food, memo: String = "ランチ",
        spentAt: Date = now, createdAt: Date = now
    ) -> Entry {
        Entry(
            amount: amount, isIncome: false, category: category, memo: memo,
            spentAt: spentAt, createdAt: createdAt, source: .text, originalText: "\(memo) \(amount)"
        )
    }
}

struct TestError: Error {}

/// 読み方を差し替えられる解析器（FallbackEntryParser に AI の代わりとして渡す、HomeModel に渡す）。
struct StubParser: EntryParsing {
    let body: @Sendable (String) async throws -> [ParsedEntry]

    init(_ body: @escaping @Sendable (String) async throws -> [ParsedEntry]) {
        self.body = body
    }

    func parse(_ text: String) async throws -> [ParsedEntry] {
        try await body(text)
    }
}
