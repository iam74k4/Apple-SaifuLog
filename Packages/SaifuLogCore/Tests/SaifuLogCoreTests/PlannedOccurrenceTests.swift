import Foundation
import Testing
@testable import SaifuLogCore

/// くり返しの記録の、まだ記録していない予定（`RecurringSchedule.plannedOccurrences`）。
struct PlannedOccurrenceTests {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    static func rule(
        _ id: String, day: Int, amount: Int = 80_000, isIncome: Bool = false,
        start: RecurringMonth = RecurringMonth(year: 2026, month: 1), last: RecurringMonth? = nil
    ) -> RecurringRule {
        RecurringRule(
            id: id, memo: id, amount: amount, isIncome: isIncome, category: .other, dayOfMonth: day,
            startMonth: start, lastRecordedMonth: last
        )
    }

    static func month(_ year: Int, _ month: Int) -> DateInterval {
        ReportPeriod.month(year: year, month: month).interval(now: Fixture.now, calendar: Fixture.calendar)!
    }

    /// 今月（2026 年 9 月。今日は 28 日）: まだ記録していない決まりは、記録する日を過ぎていても数える。記録した月は数えない。
    @Test func countsRulesNotYetRecordedThisMonth() {
        let rules = [
            Self.rule("家賃", day: 27),
            Self.rule("サブスク", day: 30, amount: 1_200),
            Self.rule("済み", day: 29, last: RecurringMonth(year: 2026, month: 9)),
            Self.rule("来月から", day: 29, start: RecurringMonth(year: 2026, month: 10)),
        ]

        let planned = RecurringSchedule.plannedOccurrences(
            for: rules, in: Self.month(2026, 9), now: Fixture.now, timeZone: Self.tokyo
        )

        #expect(planned.map(\.ruleID) == ["家賃", "サブスク"])
        #expect(planned.map(\.date) == [Fixture.date(2026, 9, 27, hour: 12), Fixture.date(2026, 9, 30, hour: 12)])
    }

    /// 先の月は、始まっている決まりをすべて数える。31 日の決まりは、その月の最後の日にする。
    @Test func countsEveryStartedRuleInFutureMonths() {
        let rules = [Self.rule("家賃", day: 31), Self.rule("来月から", day: 5, start: RecurringMonth(year: 2026, month: 11))]

        let october = RecurringSchedule.plannedOccurrences(
            for: rules, in: Self.month(2026, 10), now: Fixture.now, timeZone: Self.tokyo
        )
        let november = RecurringSchedule.plannedOccurrences(
            for: rules, in: Self.month(2026, 11), now: Fixture.now, timeZone: Self.tokyo
        )

        #expect(october.map(\.ruleID) == ["家賃"])
        #expect(october.first?.date == Fixture.date(2026, 10, 31, hour: 12))
        #expect(november.map(\.ruleID) == ["来月から", "家賃"])
        #expect(november.last?.date == Fixture.date(2026, 11, 30, hour: 12))
    }

    /// 過ぎた月は数えない（記録したものは記録として残り、記録しなかった月は開けばさかのぼって記録する）。
    @Test func ignoresPastMonths() {
        let planned = RecurringSchedule.plannedOccurrences(
            for: [Self.rule("家賃", day: 27)], in: Self.month(2026, 8), now: Fixture.now, timeZone: Self.tokyo
        )

        #expect(planned.isEmpty)
    }

    /// 収入の決まりも予定として返す（見通しでは支出だけを使う）。
    @Test func includesIncomeRules() {
        let planned = RecurringSchedule.plannedOccurrences(
            for: [Self.rule("給料", day: 25, amount: 250_000, isIncome: true)], in: Self.month(2026, 10),
            now: Fixture.now, timeZone: Self.tokyo
        )

        #expect(planned.map(\.isIncome) == [true])
    }
}
