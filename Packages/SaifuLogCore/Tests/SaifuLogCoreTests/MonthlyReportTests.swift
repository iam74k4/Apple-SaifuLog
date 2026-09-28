import Foundation
import Testing
@testable import SaifuLogCore

/// Fixture の今日は 2026-09-28 12:00（日本時間、月曜）。9 月は 1 日から今日まで 28 日。
@Suite("月のまとめ")
struct MonthlyReportTests {
    static func report(
        _ records: [TestRecord], month anchor: Date = Fixture.date(2026, 9, 1), now: Date = Fixture.now,
        budget: Int? = nil, budgetDecidedAt: Date? = nil, calendar: Calendar = Fixture.calendar
    ) throws -> MonthlyReport {
        try #require(MonthlyReport(
            records: records, month: anchor, now: now, budget: budget, budgetDecidedAt: budgetDecidedAt, calendar: calendar
        ))
    }

    // MARK: - 合計と内訳

    @Test("月の支出・収入・収支とカテゴリ別の内訳（月の始まりは含み、翌月 1 日の 0:00 は含まない）")
    func totalsAndBreakdown() throws {
        let records = [
            TestRecord(amount: 3_000, category: .food, spentAt: Fixture.date(2026, 8, 31, hour: 23, minute: 59)),
            TestRecord(amount: 850, category: .food, spentAt: Fixture.date(2026, 9, 1)),
            TestRecord(amount: 2_480, category: .food, spentAt: Fixture.date(2026, 9, 15, hour: 19)),
            TestRecord(amount: 400, category: .cafe, spentAt: Fixture.date(2026, 9, 28, hour: 9)),
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25, hour: 10)),
            TestRecord(amount: 1_000, category: .food, spentAt: Fixture.date(2026, 9, 30, hour: 23, minute: 59)),
            TestRecord(amount: 500, category: .cafe, spentAt: Fixture.date(2026, 10, 1)),
        ]

        let report = try Self.report(records)

        #expect(report.month == DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)))
        #expect(report.timing == .current)
        #expect(report.expense == 4_730)
        #expect(report.income == 250_000)
        #expect(report.balance == 245_270)
        #expect(report.recordCount == 5)
        #expect(report.breakdown.items.map(\.category) == [.food, .cafe])
        #expect(report.breakdown.items.map(\.amount) == [4_330, 400])
        #expect(report.breakdown.items.map(\.percent) == [92, 8])
        // 9/30 23:59 の先の日付の記録は、月の支出には数え、平均に使う今日までの支出には数えない。
        #expect(report.expenseThroughToday == 3_730)
        // 8/31 23:59 の記録は前の月。
        #expect(report.previousSummary.expense == 3_000)
        #expect(report.expenseChange == 1_730)
    }

    @Test("記録の無い月は、件数 0 で合計も 0")
    func emptyMonth() throws {
        let report = try Self.report([TestRecord(amount: 850, spentAt: Fixture.date(2026, 7, 10))])

        #expect(report.recordCount == 0)
        #expect(report.expense == 0)
        #expect(report.income == 0)
        #expect(report.breakdown.isEmpty)
        #expect(report.dailyAverage == 0)
        #expect(report.expenseChange == nil)
    }

    @Test("収入だけの月は、支出 0・内訳なしで、収支は収入のまま")
    func incomeOnlyMonth() throws {
        let report = try Self.report([
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25, hour: 10)),
        ])

        #expect(report.recordCount == 1)
        #expect(report.expense == 0)
        #expect(report.income == 250_000)
        #expect(report.balance == 250_000)
        #expect(report.breakdown.isEmpty)
        #expect(report.dailyAverage == 0)
    }

    // MARK: - 1 日あたりの平均

    /// 今月は月の日数（30）ではなく今日まで（28）で割る。4,730 ÷ 28 = 168.9 → 169。
    @Test("今月の平均は、1 日から今日までの日数で割って四捨五入")
    func dailyAverageOfCurrentMonth() throws {
        let report = try Self.report([
            TestRecord(amount: 4_730, spentAt: Fixture.date(2026, 9, 10)),
        ])

        #expect(report.averagingDays == 28)
        #expect(report.dailyAverage == 169)
    }

    /// 9/28 に、9/30 に払う家賃を先の日付で記録した（§4-4）。平均と目安との比べは今日までの 57,000 で出す
    /// （57,000 ÷ 28 = 2,035.7 → 2,036）。月の支出と予算の使った額には数える（ホームの帯と同じ）。
    @Test("今月の先の日付の記録は、月の支出と予算の使った額には数え、平均と目安との比べには数えない")
    func futureDatedRecordInCurrentMonth() throws {
        let records = [
            TestRecord(amount: 50_000, category: .food, spentAt: Fixture.date(2026, 9, 3)),
            // 今日の、いまより後の時刻の記録は数える（割る日数に今日を含めているため）。
            TestRecord(amount: 7_000, category: .cafe, spentAt: Fixture.date(2026, 9, 28, hour: 21)),
            // 明日の 0:00 ちょうどからは先の日付。
            TestRecord(amount: 1_000, category: .food, spentAt: Fixture.date(2026, 9, 29)),
            TestRecord(amount: 90_000, category: .other, spentAt: Fixture.date(2026, 9, 30)),
        ]

        let report = try Self.report(records, budget: 150_000, budgetDecidedAt: Fixture.date(2026, 9, 1))
        let budget = try #require(report.budget)

        #expect(report.expense == 148_000)
        #expect(report.breakdown.item(for: .other)?.amount == 90_000)
        #expect(report.expenseThroughToday == 57_000)
        #expect(report.averagingDays == 28)
        #expect(report.dailyAverage == 2_036)
        #expect(budget.spent == 148_000)
        #expect(budget.remaining == 2_000)
        #expect(report.budgetPace == 140_000)
        // 月まるごとの 148,000 で比べると目安より 8,000 多く見えるが、今日までは目安より 83,000 少ない。
        #expect(report.spentBeyondPace == -83_000)
    }

    @Test("今月の最初の日は 1 日、最後の日は月の日数で割る", arguments: [
        (Fixture.date(2026, 9, 1), 1),
        (Fixture.date(2026, 9, 1, hour: 23, minute: 59), 1),
        (Fixture.date(2026, 9, 2), 2),
        (Fixture.date(2026, 9, 30, hour: 23, minute: 59), 30),
    ])
    func averagingDaysInCurrentMonth(now: Date, expected: Int) throws {
        #expect(try Self.report([], now: now).averagingDays == expected)
    }

    /// 9 月は 30 日。45 ÷ 30 = 1.5 → 2、44 ÷ 30 = 1.47 → 1。
    @Test("過ぎた月の平均は、その月の日数で割って四捨五入", arguments: [
        (45, 2), (44, 1), (30_000, 1_000), (0, 0),
    ])
    func dailyAverageOfPastMonth(expense: Int, expected: Int) throws {
        let records = expense > 0 ? [TestRecord(amount: expense, spentAt: Fixture.date(2026, 9, 10))] : []

        let report = try Self.report(records, now: Fixture.date(2026, 10, 5))

        #expect(report.timing == .past)
        #expect(report.averagingDays == 30)
        #expect(report.expenseThroughToday == expense)
        #expect(report.dailyAverage == expected)
    }

    // MARK: - 前の月との差

    @Test("前の月との差は、この月の支出 − 前の月の支出（収入は数えない）", arguments: [
        (10_000, 4_000, -6_000),
        (4_000, 10_000, 6_000),
        (5_000, 5_000, 0),
    ])
    func expenseChange(previous: Int, current: Int, expected: Int) throws {
        let report = try Self.report([
            TestRecord(amount: previous, spentAt: Fixture.date(2026, 8, 20)),
            TestRecord(amount: 300_000, isIncome: true, spentAt: Fixture.date(2026, 8, 25)),
            TestRecord(amount: current, spentAt: Fixture.date(2026, 9, 20)),
        ])

        #expect(report.expenseChange == expected)
    }

    /// 使い始めた月の翌月に「前月より ¥（まるごと）多い」と出さない。収入だけの月も、支出をつけていなかった月とみなす。
    @Test("前の月に支出の記録が無ければ、差を出さない")
    func noChangeWithoutPreviousExpense() throws {
        let current = TestRecord(amount: 4_000, spentAt: Fixture.date(2026, 9, 20))

        let noRecords = try Self.report([current])
        #expect(noRecords.expenseChange == nil)
        #expect(noRecords.previousExpenseCount == 0)

        let incomeOnly = try Self.report([
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 8, 25)),
            current,
        ])
        #expect(incomeOnly.expenseChange == nil)
    }

    @Test("この月に支出が無くても、前の月に支出があれば差を出す")
    func changeWhenCurrentMonthHasNoExpense() throws {
        let report = try Self.report([TestRecord(amount: 8_000, spentAt: Fixture.date(2026, 8, 20))])

        #expect(report.expenseChange == -8_000)
    }

    // MARK: - 予算

    @Test("予算が無ければ、進みも目安も出さない", arguments: [nil, 0, -1] as [Int?])
    func noBudget(budget: Int?) throws {
        let report = try Self.report(
            [TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 10))], budget: budget,
            budgetDecidedAt: Fixture.date(2026, 9, 1)
        )

        #expect(report.budget == nil)
        #expect(report.budgetPace == nil)
        #expect(report.spentBeyondPace == nil)
    }

    /// 9/28 は 30 日のうち 28 日目。目安は 150,000 × 28 ÷ 30 = 140,000。
    @Test("今月は、予算の進みと、今日までの日割りの目安を出す")
    func budgetOfCurrentMonth() throws {
        let records = [
            TestRecord(amount: 50_000, category: .food, spentAt: Fixture.date(2026, 9, 3)),
            TestRecord(amount: 7_000, category: .cafe, spentAt: Fixture.date(2026, 9, 28, hour: 9)),
            // 収入は予算の支出を減らさない（§6-1）。
            TestRecord(amount: 500, isIncome: true, spentAt: Fixture.date(2026, 9, 5)),
        ]

        let report = try Self.report(records, budget: 150_000, budgetDecidedAt: Fixture.date(2026, 9, 1, hour: 9))
        let budget = try #require(report.budget)

        #expect(budget.budget == 150_000)
        #expect(budget.spent == 57_000)
        #expect(budget.remaining == 93_000)
        #expect(budget.remainingDays == 3)
        #expect(budget.dailyAllowance == 31_000)
        #expect(report.budgetPace == 140_000)
        #expect(report.spentBeyondPace == -83_000)
    }

    @Test("目安より多く使っていれば、超えた分が正の数")
    func aheadOfPace() throws {
        let report = try Self.report(
            [TestRecord(amount: 145_000, spentAt: Fixture.date(2026, 9, 20))],
            budget: 150_000, budgetDecidedAt: Fixture.date(2026, 9, 1)
        )

        #expect(report.spentBeyondPace == 5_000)
        #expect(report.budget?.isOver == false)
    }

    /// 決めた日時が分からなければ、今月だけに当てはめる。
    @Test("予算を決めた日時が分からなくても、今月には予算の進みを出す")
    func currentMonthWithoutDecisionDate() throws {
        let report = try Self.report([TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 10))], budget: 150_000)

        #expect(report.budget?.spent == 850)
        #expect(report.budgetPace == 140_000)
    }

    /// 予算は月ごとに持たないので、いまの額に決める前の月の予算は分からない。決めた月（途中で決めても）から後の月にだけ出す。
    @Test("過ぎた月には、いまの予算に決めた月とそれより後の月にだけ予算の進みを出す", arguments: [
        (Fixture.date(2026, 7, 15), true),
        (Fixture.date(2026, 8, 1), true),
        (Fixture.date(2026, 8, 31, hour: 23, minute: 59), true),
        (Fixture.date(2026, 9, 1), false),
        (Fixture.date(2026, 9, 20), false),
    ])
    func budgetOfPastMonth(decidedAt: Date, applies: Bool) throws {
        let records = [TestRecord(amount: 120_000, spentAt: Fixture.date(2026, 8, 20))]

        let report = try Self.report(
            records, month: Fixture.date(2026, 8, 1), budget: 150_000, budgetDecidedAt: decidedAt
        )

        #expect(report.timing == .past)
        #expect((report.budget != nil) == applies)
        if applies {
            #expect(report.budget?.spent == 120_000)
            #expect(report.budget?.remaining == 30_000)
        }
        // 日割りの目安は今月だけ。
        #expect(report.budgetPace == nil)
    }

    @Test("決めた日時が分からなければ、過ぎた月には予算の進みを出さない")
    func pastMonthWithoutDecisionDate() throws {
        let report = try Self.report(
            [TestRecord(amount: 120_000, spentAt: Fixture.date(2026, 8, 20))], month: Fixture.date(2026, 8, 1),
            budget: 150_000
        )

        #expect(report.budget == nil)
    }

    @Test("先の月は、予算も平均も出さない")
    func futureMonth() throws {
        let report = try Self.report(
            [TestRecord(amount: 80_000, spentAt: Fixture.date(2026, 10, 1, hour: 9))], month: Fixture.date(2026, 10, 15),
            budget: 150_000, budgetDecidedAt: Fixture.date(2026, 9, 1)
        )

        #expect(report.timing == .future)
        #expect(report.expense == 80_000)
        #expect(report.averagingDays == 0)
        #expect(report.expenseThroughToday == 0)
        #expect(report.dailyAverage == 0)
        #expect(report.budget == nil)
        #expect(report.budgetPace == nil)
    }

    // MARK: - 暦

    /// 2028 年はうるう年。2/15 は 29 日のうち 15 日目で、目安は 290,000 × 15 ÷ 29 = 150,000。
    @Test("うるう年の 2 月は 29 日で数える")
    func leapYear() throws {
        let records = [
            TestRecord(amount: 1_000, spentAt: Fixture.date(2028, 1, 31, hour: 23, minute: 59)),
            TestRecord(amount: 29_000, spentAt: Fixture.date(2028, 2, 29, hour: 12)),
        ]

        let current = try Self.report(
            records, month: Fixture.date(2028, 2, 1), now: Fixture.date(2028, 2, 15, hour: 12),
            budget: 290_000, budgetDecidedAt: Fixture.date(2028, 1, 1)
        )
        #expect(current.month == DateInterval(start: Fixture.date(2028, 2, 1), end: Fixture.date(2028, 3, 1)))
        #expect(current.summary.dayCount == 29)
        #expect(current.averagingDays == 15)
        #expect(current.budgetPace == 150_000)
        #expect(current.budget?.remainingDays == 15)

        let past = try Self.report(records, month: Fixture.date(2028, 2, 10), now: Fixture.date(2028, 3, 10))
        #expect(past.averagingDays == 29)
        #expect(past.dailyAverage == 1_000)
        #expect(past.expenseChange == 28_000)

        // 3 月の前の月は、29 日まであるうるう年の 2 月。
        let march = try Self.report(records, month: Fixture.date(2028, 3, 1), now: Fixture.date(2028, 3, 10))
        #expect(march.previousSummary.interval == current.month)
        #expect(march.previousSummary.expense == 29_000)

        let february2026 = try Self.report([], month: Fixture.date(2026, 2, 1), now: Fixture.date(2026, 3, 1))
        #expect(february2026.averagingDays == 28)
    }

    /// 月のまとめは月で区切るので、週の始まり（日曜か月曜か）で数字が変わらない。9/27 は日曜。
    @Test("週の始まりが日曜でも月曜でも、同じまとめになる")
    func weekStartDoesNotMatter() throws {
        let records = [
            TestRecord(amount: 500, spentAt: Fixture.date(2026, 8, 31, hour: 12)),
            TestRecord(amount: 1_000, spentAt: Fixture.date(2026, 9, 1, hour: 8)),
            TestRecord(amount: 2_000, spentAt: Fixture.date(2026, 9, 27, hour: 12)),
            TestRecord(amount: 3_000, spentAt: Fixture.date(2026, 9, 30, hour: 20)),
        ]

        let sundayFirst = try Self.report(records, calendar: Fixture.calendar(firstWeekday: 1))
        let mondayFirst = try Self.report(records, calendar: Fixture.calendar(firstWeekday: 2))

        #expect(sundayFirst == mondayFirst)
        #expect(sundayFirst.expense == 6_000)
        #expect(sundayFirst.averagingDays == 28)
        #expect(sundayFirst.previousSummary.expense == 500)
    }

    /// 2026-09-30 15:30（UTC）は、東京では 10/1 0:30、ニューヨークでは 9/30 11:30。
    /// 2026-08-31 20:00（UTC）は、東京では 9/1 5:00、ニューヨークでは 8/31 16:00。
    @Test("月の境目は暦の時間帯で決める")
    func timeZone() throws {
        let utc = Fixture.calendar(firstWeekday: 1, timeZone: "UTC")
        let lateSeptember = try #require(utc.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 15, minute: 30)))
        let lateAugust = try #require(utc.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 20)))
        let records = [
            TestRecord(amount: 1_000, spentAt: lateSeptember),
            TestRecord(amount: 200, spentAt: lateAugust),
            TestRecord(amount: 30, spentAt: Fixture.date(2026, 9, 15)),
        ]
        let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")

        let tokyo = try Self.report(records)
        #expect(tokyo.expense == 230)
        #expect(tokyo.previousSummary.expense == 0)

        // ニューヨークの 9 月は 9/1 0:00（夏時間）から。Fixture の今日（日本時間 9/28 12:00）は、ニューヨークでは 9/27 23:00。
        let september = try #require(newYork.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let october = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let ny = try Self.report(records, month: september, calendar: newYork)
        #expect(ny.month == DateInterval(start: september, end: october))
        #expect(ny.expense == 1_030)
        #expect(ny.previousSummary.expense == 200)
        #expect(ny.averagingDays == 27)
    }

    /// ニューヨークでは 2026-11-01 に 1 時間戻る（25 時間の日）。秒で割らずに暦で数える。
    @Test("夏時間の切り替わる月も、暦で日数を数える")
    func daylightSaving() throws {
        let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")
        func date(_ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) throws -> Date {
            try #require(newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)))
        }

        let past = try Self.report([], month: try date(11, 1), now: try date(12, 5), calendar: newYork)
        #expect(past.averagingDays == 30)

        let firstDay = try Self.report([], month: try date(11, 1), now: try date(11, 1, minute: 30), calendar: newYork)
        #expect(firstDay.averagingDays == 1)

        let secondDay = try Self.report([], month: try date(11, 1), now: try date(11, 2, hour: 12), calendar: newYork)
        #expect(secondDay.averagingDays == 2)
    }

    /// ホームの今月（ReportPeriod.thisMonth）と同じ区切り。イスラム暦では 2026-09-28 を含む月は 9/12〜10/12。
    @Test("月の区切りが西暦と違う暦では、その暦の月でまとめる")
    func nonGregorianCalendar() throws {
        let islamic = Fixture.calendar(firstWeekday: 1, identifier: .islamicUmmAlQura)
        let records = [
            TestRecord(amount: 1_000, spentAt: Fixture.date(2026, 9, 5)),
            TestRecord(amount: 2_000, spentAt: Fixture.date(2026, 9, 20)),
        ]

        let report = try Self.report(records, month: Fixture.now, calendar: islamic)

        #expect(report.month == DateInterval(start: Fixture.date(2026, 9, 12), end: Fixture.date(2026, 10, 12)))
        #expect(report.expense == 2_000)
        #expect(report.previousSummary.expense == 1_000)
        // 9/12 から 9/28 まで 17 日。
        #expect(report.averagingDays == 17)
    }
}
