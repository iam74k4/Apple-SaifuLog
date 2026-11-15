import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 月の画面（月のまとめ）の「内訳」と「カレンダー」の切り替えと月送り（カレンダーは画面の月に合わせ、ホームと同じ保存先を読む）。
@MainActor
struct HomeModelCalendarTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 月の画面は内訳から開き、カレンダーに切り替えると、ホームで記録した今日の記録を出す。
    @Test func calendarTabReadsSameStore() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 850")

        fixture.model.presentMonthlyReport(calendar: TestSupport.calendar)
        let report = try #require(fixture.model.monthlyReport)
        #expect(report.tab == .breakdown)
        report.tab = .calendar

        #expect(report.days.month?.start == TestSupport.date(2026, 9, 1))
        #expect(report.days.selectedRecords.map(\.memo) == ["ランチ"])
    }

    /// 月を替えると、カレンダーもその月にし、見方（カレンダー）はそのまま。「今月」で今月に戻る。
    @Test func calendarFollowsMonth() throws {
        let fixture = try Fixture()
        try EntryStore(context: fixture.context).insert([
            TestSupport.entry(amount: 3_000, memo: "先月", spentAt: TestSupport.date(2026, 8, 20, hour: 10)),
        ])
        fixture.model.presentMonthlyReport(calendar: TestSupport.calendar)
        let report = try #require(fixture.model.monthlyReport)
        report.tab = .calendar
        #expect(report.isCurrentMonth)

        report.showPreviousMonth()

        #expect(report.tab == .calendar)
        #expect(!report.isCurrentMonth)
        #expect(report.days.month?.start == TestSupport.date(2026, 8, 1))
        #expect(report.days.days?.expense == 3_000)

        report.showThisMonth()

        #expect(report.isCurrentMonth)
        #expect(report.days.month?.start == TestSupport.date(2026, 9, 1))
    }

    /// カレンダーの記録の長押しの「毎月くり返す」は、ホームのくり返しの記録を作るシートを出す。
    @Test func calendarMakeRecurringOpensEditor() async throws {
        let fixture = try Fixture()
        await fixture.send("家賃 80000")
        fixture.model.presentMonthlyReport(calendar: TestSupport.calendar)
        let report = try #require(fixture.model.monthlyReport)
        let entry = try #require(try fixture.context.fetch(FetchDescriptor<Entry>()).first)

        report.makeRecurring?(entry)

        #expect(fixture.model.recurringEditor != nil)
    }
}
