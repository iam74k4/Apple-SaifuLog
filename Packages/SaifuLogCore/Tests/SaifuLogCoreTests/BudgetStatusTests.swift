import Foundation
import Testing
@testable import SaifuLogCore

@Suite("予算の進み")
struct BudgetStatusTests {
    static let plan = BudgetPlan(total: 150_000)

    static func status(
        plan: BudgetPlan = plan, scope: BudgetScope = .total, records: [TestRecord], now: Date = Fixture.now,
        calendar: Calendar = Fixture.calendar
    ) -> BudgetStatus? {
        BudgetStatus(plan: plan, scope: scope, records: records, now: now, calendar: calendar)
    }

    /// Fixture の今日は 2026-09-28（月）。9 月の残りは 28・29・30 日の 3 日。
    @Test("9/28 なら残りは今日を含めて 3 日。残りを 3 日で割った額が 1 日あたり")
    func remainingOnSeptember28() throws {
        let records = [
            TestRecord(amount: 50_000, category: .food, spentAt: Fixture.date(2026, 9, 3)),
            TestRecord(amount: 7_000, category: .cafe, spentAt: Fixture.date(2026, 9, 28, hour: 9)),
        ]

        let status = try #require(Self.status(records: records))

        #expect(status.budget == 150_000)
        #expect(status.spent == 57_000)
        #expect(status.remaining == 93_000)
        #expect(status.remainingDays == 3)
        #expect(status.dailyAllowance == 31_000)
        #expect(!status.isOver)
        #expect(status.overspent == 0)
        #expect(abs(status.spentFraction - 0.38) < 0.000_1)
    }

    /// 切り上げると、毎日その額を使ったときに月末に予算を超える。
    @Test("1 日あたりの額は切り捨て")
    func dailyAllowanceRoundsDown() throws {
        let status = try #require(Self.status(
            records: [TestRecord(amount: 50_000, spentAt: Fixture.date(2026, 9, 10))]
        ))

        #expect(status.remaining == 100_000)
        #expect(status.dailyAllowance == 33_333)
        #expect(status.dailyAllowance * status.remainingDays <= status.remaining)
    }

    @Test("月の最初の日は、その月の日数がまるごと残り", arguments: [
        (Fixture.date(2026, 9, 1), 30),
        (Fixture.date(2026, 10, 1), 31),
        (Fixture.date(2026, 2, 1, hour: 23, minute: 59), 28),
    ])
    func firstDayOfMonth(now: Date, expected: Int) throws {
        let status = try #require(Self.status(records: [], now: now))

        #expect(status.remainingDays == expected)
        #expect(status.dailyAllowance == 150_000 / expected)
    }

    @Test("月末の日は残り 1 日で、残りをまるごと使える")
    func lastDayOfMonth() throws {
        let now = Fixture.date(2026, 9, 30, hour: 23, minute: 59)
        let status = try #require(Self.status(
            records: [TestRecord(amount: 120_000, spentAt: Fixture.date(2026, 9, 15))], now: now
        ))

        #expect(status.remainingDays == 1)
        #expect(status.dailyAllowance == 30_000)
    }

    @Test("うるう年の 2 月は 29 日まで数える", arguments: [
        (Fixture.date(2028, 2, 28, hour: 12), 2),
        (Fixture.date(2028, 2, 29, hour: 12), 1),
        (Fixture.date(2026, 2, 28, hour: 12), 1),
        (Fixture.date(2028, 2, 1), 29),
    ])
    func leapYear(now: Date, expected: Int) throws {
        #expect(try #require(Self.status(records: [], now: now)).remainingDays == expected)
    }

    /// 月が変わったら、支出も残りの日数も新しい月で数え直す（前の月の支出を持ち越さない）。
    @Test("月の切り替わり: 月末の 23:59 はその月、翌月 1 日の 0:00 は翌月で数える")
    func monthRollover() throws {
        let records = [
            TestRecord(amount: 140_000, spentAt: Fixture.date(2026, 9, 30, hour: 23, minute: 58)),
            TestRecord(amount: 850, spentAt: Fixture.date(2026, 10, 1)),
        ]

        let september = try #require(Self.status(records: records, now: Fixture.date(2026, 9, 30, hour: 23, minute: 59)))
        #expect(september.spent == 140_000)
        #expect(september.remainingDays == 1)
        #expect(september.dailyAllowance == 10_000)

        let october = try #require(Self.status(records: records, now: Fixture.date(2026, 10, 1)))
        #expect(october.spent == 850)
        #expect(october.remainingDays == 31)
        #expect(october.remaining == 149_150)
    }

    @Test("予算を決めていない（0 か未設定）なら、進みは出さない")
    func noBudget() {
        let records = [TestRecord(amount: 850, spentAt: Fixture.now)]

        #expect(Self.status(plan: BudgetPlan(), records: records) == nil)
        #expect(Self.status(plan: BudgetPlan(total: 0), records: records) == nil)
        #expect(BudgetStatus(budget: 0, spent: 0, now: Fixture.now, month: DateInterval(start: Fixture.now, duration: 1), calendar: Fixture.calendar) == nil)
        #expect(BudgetStatus(budget: -1, spent: 0, now: Fixture.now, month: DateInterval(start: Fixture.now, duration: 1), calendar: Fixture.calendar) == nil)
    }

    @Test("予算を超えたら、超えた額を出し、1 日あたりの額は 0")
    func overBudget() throws {
        let status = try #require(Self.status(
            records: [TestRecord(amount: 162_000, spentAt: Fixture.date(2026, 9, 20))]
        ))

        #expect(status.isOver)
        #expect(status.overspent == 12_000)
        #expect(status.remaining == -12_000)
        #expect(status.dailyAllowance == 0)
        #expect(status.spentFraction == 1)
    }

    @Test("ちょうど使い切ったときは、超えていない（残り 0、1 日あたり 0）")
    func exactlySpent() throws {
        let status = try #require(Self.status(
            records: [TestRecord(amount: 150_000, spentAt: Fixture.date(2026, 9, 20))]
        ))

        #expect(!status.isOver)
        #expect(status.overspent == 0)
        #expect(status.remaining == 0)
        #expect(status.dailyAllowance == 0)
        #expect(status.spentFraction == 1)
    }

    /// v1 の決め事: 収入（返金を含む）は予算の支出を減らさない。
    @Test("収入と返金は、予算の支出を減らさない")
    func incomeDoesNotReduceSpending() throws {
        let records = [
            TestRecord(amount: 60_000, category: .food, spentAt: Fixture.date(2026, 9, 5)),
            // 返金（「返金 -500」はカテゴリがその他の収入として記録される）。
            TestRecord(amount: 500, isIncome: true, category: .other, spentAt: Fixture.date(2026, 9, 6)),
            TestRecord(amount: 250_000, isIncome: true, category: .other, spentAt: Fixture.date(2026, 9, 25)),
        ]

        let status = try #require(Self.status(records: records))

        #expect(status.spent == 60_000)
        #expect(status.remaining == 90_000)
    }

    @Test("カテゴリの予算は、そのカテゴリの支出だけで数える")
    func categoryScope() throws {
        let plan = BudgetPlan(total: 150_000, byCategory: [.cafe: 6_000])
        let records = [
            TestRecord(amount: 4_500, category: .cafe, spentAt: Fixture.date(2026, 9, 10)),
            TestRecord(amount: 30_000, category: .food, spentAt: Fixture.date(2026, 9, 10)),
        ]

        let cafe = try #require(Self.status(plan: plan, scope: .category(.cafe), records: records))
        #expect(cafe.budget == 6_000)
        #expect(cafe.spent == 4_500)
        #expect(cafe.dailyAllowance == 500)

        // 予算を決めていないカテゴリは出さない。
        #expect(Self.status(plan: plan, scope: .category(.food), records: records) == nil)
    }

    /// ホームの今月（ReportPeriod.thisMonth）と同じ区切り。イスラム暦では 2026-09-28 を含む月は 9/12〜10/12。
    @Test("月の区切りが西暦と違う暦では、その暦の月末まで数える")
    func nonGregorianCalendar() throws {
        let islamic = Fixture.calendar(firstWeekday: 1, identifier: .islamicUmmAlQura)
        let records = [
            TestRecord(amount: 1_000, spentAt: Fixture.date(2026, 9, 5)),
            TestRecord(amount: 2_000, spentAt: Fixture.date(2026, 10, 5)),
        ]

        let status = try #require(Self.status(records: records, calendar: islamic))

        // 9/28〜10/11 の 14 日。9/5 は前の月。
        #expect(status.remainingDays == 14)
        #expect(status.spent == 2_000)
    }

    /// ニューヨークでは 2026-11-01 の 2:00 に 1 時間戻り（25 時間の日）、2026-03-08 の 2:00 に 1 時間進む
    /// （23 時間の日）。どちらも月末までの秒数が 1 日の秒数の倍数からずれるので、秒で割ると日数がずれる。
    ///
    /// 日時は、秒で割る書き方が実際に外れる時刻を選ぶ（切り替わりの後の昼などでは、たまたま同じ答えになり
    /// ずれを捕まえられない）。
    /// - 11/1 0:30（戻る前）: 月末まで 30 日と 30 分。今の時刻から割って切り上げると 31 になる。
    /// - 3/8 12:00（進んだ日）: その日の 0:00 から月末まで 23 日と 23 時間。切り捨てると 23 になる。
    @Test("夏時間の切り替わる月も、暦で日数を数える", arguments: [
        (DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30), 30),
        (DateComponents(year: 2026, month: 3, day: 8, hour: 12), 24),
    ])
    func daylightSaving(components: DateComponents, expected: Int) throws {
        let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")
        let now = try #require(newYork.date(from: components))

        let status = try #require(Self.status(records: [], now: now, calendar: newYork))

        #expect(status.remainingDays == expected)
    }

    @Test("期間の集計から出しても、記録から出したものと同じ")
    func fromLedgerSummary() throws {
        let records = [
            TestRecord(amount: 50_000, category: .food, spentAt: Fixture.date(2026, 9, 3)),
            TestRecord(amount: 800, category: .food, spentAt: Fixture.date(2026, 8, 31)),
        ]
        let month = try #require(ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: Fixture.calendar))
        let summary = LedgerSummary(records: records, interval: month, calendar: Fixture.calendar)

        let fromSummary = BudgetStatus(budget: 150_000, summary: summary, now: Fixture.now, calendar: Fixture.calendar)

        #expect(fromSummary == Self.status(records: records))
        #expect(fromSummary?.spent == 50_000)
    }

    /// 月の外の日時を渡されても、1 日あたりの額の割る数が 0 にならない。
    @Test("月の外の日時でも、残りの日数は 1 以上")
    func remainingDaysOutsideMonth() {
        let september = DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1))

        #expect(BudgetStatus.remainingDays(from: Fixture.date(2026, 10, 3), in: september, calendar: Fixture.calendar) == 1)
        #expect(BudgetStatus.remainingDays(from: Fixture.date(2026, 8, 20), in: september, calendar: Fixture.calendar) == 30)
    }
}
