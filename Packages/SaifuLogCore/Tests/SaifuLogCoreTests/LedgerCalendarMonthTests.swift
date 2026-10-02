import Foundation
import Testing
@testable import SaifuLogCore

/// 月のカレンダーの日ごとの集計（`LedgerCalendarMonth`）。
struct LedgerCalendarMonthTests {
    static func month(_ year: Int, _ month: Int, calendar: Calendar = Fixture.calendar) -> DateInterval {
        ReportPeriod.month(year: year, month: month).interval(now: Fixture.now, calendar: calendar)!
    }

    /// 1 日の前の空きは、週の始まりの曜日から数える（2026 年 10 月 1 日は木曜日）。
    @Test(arguments: [(1, 4), (2, 3)])
    func leadingBlanksFollowWeekStart(firstWeekday: Int, blanks: Int) {
        let calendar = Fixture.calendar(firstWeekday: firstWeekday)
        let month = LedgerCalendarMonth(records: [TestRecord](), month: Self.month(2026, 10, calendar: calendar), calendar: calendar)

        #expect(month.leadingBlankCount == blanks)
        #expect(month.days.first?.dayOfMonth == 1)
    }

    @Test(arguments: [(2026, 10, 31), (2028, 2, 29), (2027, 2, 28), (2026, 9, 30)])
    func hasEveryDayOfTheMonth(year: Int, month: Int, count: Int) {
        let days = LedgerCalendarMonth(records: [TestRecord](), month: Self.month(year, month), calendar: Fixture.calendar).days

        #expect(days.count == count)
        #expect(days.map(\.dayOfMonth) == Array(1...count))
    }

    /// 支出と収入を分けて日ごとに数え、月の外の記録は数えない。日の境目は画面の暦の時間帯で区切る。
    @Test func sumsEachDaySeparatingExpenseAndIncome() {
        let records = [
            TestRecord(amount: 780, spentAt: Fixture.date(2026, 10, 2, hour: 12)),
            TestRecord(amount: 230, spentAt: Fixture.date(2026, 10, 2, hour: 18)),
            TestRecord(amount: 500, isIncome: true, spentAt: Fixture.date(2026, 10, 2, hour: 9)),
            TestRecord(amount: 100, spentAt: Fixture.date(2026, 10, 1, hour: 23, minute: 59)),
            TestRecord(amount: 999, spentAt: Fixture.date(2026, 11, 1)),
            TestRecord(amount: 888, spentAt: Fixture.date(2026, 9, 30, hour: 23, minute: 59)),
        ]
        let month = LedgerCalendarMonth(records: records, month: Self.month(2026, 10), calendar: Fixture.calendar)

        let second = month.days[1]
        #expect(second.expense == 1_010)
        #expect(second.income == 500)
        #expect(second.recordCount == 3)
        #expect(month.days[0].expense == 100)
        #expect(month.expense == 1_110)
        #expect(month.income == 500)
        #expect(month.day(containing: Fixture.date(2026, 10, 2, hour: 23), calendar: Fixture.calendar)?.dayOfMonth == 2)
        #expect(month.day(containing: Fixture.date(2026, 11, 2), calendar: Fixture.calendar) == nil)
    }

    /// 予算の日割りは、予算 ÷ 月の日数（切り捨て）。予算が無ければ出さない。
    @Test func dailyPaceDividesBudgetByDaysInMonth() {
        let month = LedgerCalendarMonth(records: [TestRecord](), month: Self.month(2026, 10), calendar: Fixture.calendar)

        #expect(month.dailyPace(budget: 310_000) == 10_000)
        #expect(month.dailyPace(budget: 100_000) == 3_225)
        #expect(month.dailyPace(budget: nil) == nil)
        #expect(month.dailyPace(budget: 0) == nil)
    }
}
