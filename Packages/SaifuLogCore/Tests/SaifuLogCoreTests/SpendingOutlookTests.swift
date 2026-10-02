import Foundation
import Testing
@testable import SaifuLogCore

/// 今月の見通し（`SpendingOutlook`。カレンダーのページの「今日あと」の欄）。
struct SpendingOutlookTests {
    typealias Record = SpendingOutlook.Record

    /// 2026 年 10 月（31 日）。今日は 10 月 12 日（12 日目。残りは今日を含めて 20 日）。
    static let month = ReportPeriod.month(year: 2026, month: 10).interval(now: Fixture.now, calendar: Fixture.calendar)!
    static let now = Fixture.date(2026, 10, 12, hour: 15)

    static func expense(_ amount: Int, day: Int, recurring: Bool = false) -> Record {
        Record(amount: amount, isIncome: false, spentAt: Fixture.date(2026, 10, day, hour: 12), isRecurring: recurring)
    }

    static func rent(day: Int = 27, recorded: Bool = false) -> RecurringRule {
        RecurringRule(
            id: "rent", memo: "家賃", amount: 80_000, isIncome: false, category: .other, dayOfMonth: day,
            startMonth: RecurringMonth(year: 2026, month: 1),
            lastRecordedMonth: recorded ? RecurringMonth(year: 2026, month: 10) : RecurringMonth(year: 2026, month: 9)
        )
    }

    static func outlook(budget: Int? = 200_000, records: [Record], rules: [RecurringRule] = [], now: Date = now) -> SpendingOutlook? {
        SpendingOutlook(budget: budget, records: records, rules: rules, now: now, month: month, calendar: Fixture.calendar)
    }

    /// 今日あと = （予算 − 昨日までの支出 − まだ記録していない固定費）÷ 今日を含む残りの日数 − 今日の支出。
    @Test func todayLeftSubtractsPlannedFixedCostsAndTodaysSpending() throws {
        let outlook = try #require(Self.outlook(
            records: [Self.expense(30_000, day: 5), Self.expense(1_200, day: 12)], rules: [Self.rent()]
        ))

        #expect(outlook.remainingDays == 20)
        #expect(outlook.plannedFixedTotal == 80_000)
        // (200,000 − 30,000 − 80,000) ÷ 20 = 4,500
        #expect(outlook.todayAllowance == 4_500)
        #expect(outlook.todayLeft == 3_300)
        #expect(outlook.freeToSpend == 200_000 - 31_200 - 80_000)
    }

    /// 記録した月の固定費は、支出として数えるので二重に引かない。
    @Test func recordedFixedCostIsNotSubtractedTwice() throws {
        let outlook = try #require(Self.outlook(
            records: [Self.expense(80_000, day: 1, recurring: true)], rules: [Self.rent(day: 1, recorded: true)]
        ))

        #expect(outlook.plannedFixed.isEmpty)
        #expect(outlook.todayAllowance == (200_000 - 80_000) / 20)
    }

    /// 先の日付で記録した支出は、使う予定の額として先に引く。収入は数えない。
    @Test func laterExpensesAreCommittedAndIncomeIsIgnored() throws {
        let outlook = try #require(Self.outlook(records: [
            Self.expense(60_000, day: 27),
            Record(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 10, 10), isRecurring: false),
        ]))

        #expect(outlook.spentLater == 60_000)
        #expect(outlook.todayAllowance == (200_000 - 60_000) / 20)
        #expect(outlook.spent == 60_000)
    }

    /// 今日の支出が今日使える額を超えたら、今日あとは負（超えた額）。残りが無ければ今日使える額は 0。
    @Test func todayLeftGoesNegativeWhenOverspent() throws {
        let over = try #require(Self.outlook(records: [Self.expense(10_000, day: 12)]))
        let exhausted = try #require(Self.outlook(records: [Self.expense(250_000, day: 3)]))

        #expect(over.todayLeft == 200_000 / 20 - 10_000)
        #expect(exhausted.todayAllowance == 0)
        #expect(exhausted.freeToSpend == -50_000)
    }

    /// 予算が無ければ、今日あとと固定費を引いた今月あとは出さない（見込みは出す）。
    @Test func withoutBudgetOnlyProjectionIsShown() throws {
        let outlook = try #require(Self.outlook(budget: nil, records: [Self.expense(12_000, day: 6)]))

        #expect(outlook.todayLeft == nil)
        #expect(outlook.freeToSpend == nil)
        #expect(outlook.projection == 12_000 * 31 / 12)
    }

    /// 月末の見込み = くり返し以外の支出のペース × 月の日数 ＋ 先の日付の支出 ＋ 固定費（記録したものとまだのもの）。
    @Test func projectionAddsFixedCostsToVariablePace() throws {
        let outlook = try #require(Self.outlook(
            records: [Self.expense(24_000, day: 4), Self.expense(80_000, day: 1, recurring: true), Self.expense(5_000, day: 20)],
            rules: [
                Self.rent(day: 1, recorded: true),
                RecurringRule(
                    id: "sub", memo: "サブスク", amount: 1_500, isIncome: false, category: .other, dayOfMonth: 28,
                    startMonth: RecurringMonth(year: 2026, month: 1)
                ),
            ]
        ))

        #expect(outlook.projection == 24_000 * 31 / 12 + 5_000 + 80_000 + 1_500)
        #expect(outlook.projectedOverBudget == outlook.projection.map { $0 - 200_000 })
    }

    /// 月の初め（7 日目より前）は、数日の支出で大きく振れるので見込みを出さない。
    @Test func noProjectionEarlyInTheMonth() throws {
        let early = try #require(Self.outlook(records: [Self.expense(3_000, day: 2)], now: Fixture.date(2026, 10, 6, hour: 9)))
        let seventh = try #require(Self.outlook(records: [Self.expense(3_000, day: 2)], now: Fixture.date(2026, 10, 7, hour: 9)))

        #expect(early.projection == nil)
        #expect(seventh.projection == 3_000 * 31 / 7)
    }

    /// 今月の外の日時では出さない（見通しは今月だけ）。
    @Test func onlyForTheCurrentMonth() {
        #expect(Self.outlook(records: [], now: Fixture.date(2026, 11, 1, hour: 9)) == nil)
    }
}
