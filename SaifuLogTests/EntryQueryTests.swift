import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 今月の合計とタイムラインの読み込みの条件。
@MainActor
struct EntryQueryTests {
    private let calendar = TestSupport.calendar

    /// 今月の合計は、渡した日を含む月の記録だけから出す。月をまたいで日付を渡し直せば、合計も新しい月に切り替わる。
    @Test func monthDescriptorReadsOnlyThatMonth() throws {
        let context = try TestSupport.makeContext()
        let september = TestSupport.entry(amount: 12_000, spentAt: TestSupport.date(2026, 9, 30, hour: 23, minute: 59))
        let october = TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 10, 1))
        let lastYear = TestSupport.entry(amount: 80_000, spentAt: TestSupport.date(2025, 10, 15))
        for entry in [september, october, lastYear] {
            context.insert(entry)
        }
        try context.save()

        let onSeptember30 = try context.fetch(
            Entry.monthDescriptor(containing: TestSupport.date(2026, 9, 30, hour: 12), calendar: calendar)
        )
        #expect(onSeptember30.map(\.amount) == [12_000])

        let onOctober1 = try context.fetch(
            Entry.monthDescriptor(containing: TestSupport.date(2026, 10, 1, hour: 0, minute: 1), calendar: calendar)
        )
        #expect(onOctober1.map(\.amount) == [850])
        #expect(MonthlySummary(records: onOctober1, month: TestSupport.date(2026, 10, 1), calendar: calendar).expense == 850)
    }

    /// タイムラインは全期間を読まず、記録した日時の新しいものから件数で区切って読む。
    @Test func timelineDescriptorReadsNewestEntriesUpToLimit() throws {
        let context = try TestSupport.makeContext()
        for minute in 0..<5 {
            context.insert(TestSupport.entry(amount: 100 + minute, createdAt: TestSupport.date(2026, 9, 28, hour: 12, minute: minute)))
        }
        try context.save()

        let recent = try context.fetch(Entry.timelineDescriptor(limit: 3))
        #expect(recent.map(\.amount) == [104, 103, 102])
    }
}
