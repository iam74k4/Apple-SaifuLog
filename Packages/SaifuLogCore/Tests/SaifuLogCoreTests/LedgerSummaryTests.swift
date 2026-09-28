import Foundation
import Testing
@testable import SaifuLogCore

@Suite("期間の集計")
struct LedgerSummaryTests {
    /// 2026-09-28（月）から 1 週間。
    static let week = DateInterval(start: Fixture.date(2026, 9, 28), end: Fixture.date(2026, 10, 5))

    @Test("期間の支出・収入・差額を出す（始まりの時刻は含み、終わりの時刻は含まない）")
    func sumsWithinInterval() {
        let records = [
            TestRecord(amount: 100, spentAt: Fixture.date(2026, 9, 27, hour: 23, minute: 59)),
            TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 28)),
            TestRecord(amount: 3_000, spentAt: Fixture.date(2026, 10, 4, hour: 23, minute: 59)),
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 10, 1, hour: 9)),
            TestRecord(amount: 500, spentAt: Fixture.date(2026, 10, 5)),
        ]

        let summary = LedgerSummary(records: records, interval: Self.week, calendar: Fixture.calendar)

        #expect(summary.interval == Self.week)
        #expect(summary.expense == 3_850)
        #expect(summary.income == 250_000)
        #expect(summary.balance == 246_150)
    }

    @Test("支出のカテゴリ別の合計を出す（収入と期間の外の記録は数えない）")
    func sumsByCategory() {
        let records = [
            TestRecord(amount: 850, category: .food, spentAt: Fixture.date(2026, 9, 28, hour: 12)),
            TestRecord(amount: 2_480, category: .food, spentAt: Fixture.date(2026, 9, 29, hour: 19)),
            TestRecord(amount: 400, category: .cafe, spentAt: Fixture.date(2026, 9, 30, hour: 15)),
            // 収入は支出とは別の種別なので、カテゴリ（ここでは食費）を持っていてもカテゴリ別には数えない。
            TestRecord(amount: 3_000, isIncome: true, category: .food, spentAt: Fixture.date(2026, 10, 1)),
            TestRecord(amount: 9_999, category: .cafe, spentAt: Fixture.date(2026, 10, 5)),
        ]

        let summary = LedgerSummary(records: records, interval: Self.week, calendar: Fixture.calendar)

        #expect(summary.expenseByCategory == [.food: 3_330, .cafe: 400])
        #expect(summary.expense(in: .food) == 3_330)
        #expect(summary.expense(in: .transport) == 0)
        // カテゴリ別の合計を足すと、支出の合計になる。
        #expect(summary.expenseByCategory.values.reduce(0, +) == summary.expense)
    }

    @Test("記録が無ければ 0")
    func empty() {
        let summary = LedgerSummary(records: [TestRecord](), interval: Self.week, calendar: Fixture.calendar)

        #expect(summary.expense == 0)
        #expect(summary.income == 0)
        #expect(summary.balance == 0)
        #expect(summary.expenseByCategory.isEmpty)
    }

    @Test("期間がかかる日数を暦で数える（日の途中までの日も 1 日と数える）", arguments: [
        (Fixture.date(2026, 9, 1), Fixture.date(2026, 10, 1), 30),
        (Fixture.date(2026, 2, 1), Fixture.date(2026, 3, 1), 28),
        (Fixture.date(2026, 9, 28), Fixture.date(2026, 10, 5), 7),
        (Fixture.date(2026, 9, 28), Fixture.date(2026, 9, 29), 1),
        (Fixture.date(2026, 9, 28, hour: 12), Fixture.date(2026, 9, 29, hour: 12), 2),
        (Fixture.date(2026, 9, 28), Fixture.date(2026, 9, 28, hour: 12), 1),
        (Fixture.date(2026, 9, 28), Fixture.date(2026, 9, 28), 0),
    ])
    func dayCount(start: Date, end: Date, expected: Int) {
        let summary = LedgerSummary(
            records: [TestRecord](), interval: DateInterval(start: start, end: end), calendar: Fixture.calendar
        )
        #expect(summary.dayCount == expected)
    }

    /// 夏時間が終わる週（2026-11-01 はニューヨークで 1 時間長い）。秒で割ると 7 日にならない。
    @Test("夏時間の切り替わる週も 7 日と数える")
    func dayCountAcrossDaylightSaving() throws {
        let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")
        let sunday = try #require(newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let week = try #require(ReportPeriod.thisWeek.interval(now: sunday, calendar: newYork))

        let summary = LedgerSummary(records: [TestRecord](), interval: week, calendar: newYork)

        #expect(week.duration == 7 * 86_400 + 3_600)
        #expect(summary.dayCount == 7)
    }

    @Test("ReportPeriod の期間でそのまま集計できる")
    func summarizesReportPeriod() throws {
        let calendar = Fixture.calendar(firstWeekday: 2)
        let records = [
            TestRecord(amount: 1_000, category: .food, spentAt: Fixture.date(2026, 9, 27, hour: 20)),
            TestRecord(amount: 850, category: .food, spentAt: Fixture.date(2026, 9, 28, hour: 12)),
        ]
        let thisWeek = try #require(ReportPeriod.thisWeek.interval(now: Fixture.now, calendar: calendar))
        let lastWeek = try #require(ReportPeriod.lastWeek.interval(now: Fixture.now, calendar: calendar))

        // 月曜始まりなので、日曜（9/27）の記録は先週に入る。
        #expect(LedgerSummary(records: records, interval: thisWeek, calendar: calendar).expense == 850)
        #expect(LedgerSummary(records: records, interval: lastWeek, calendar: calendar).expense == 1_000)
    }
}
