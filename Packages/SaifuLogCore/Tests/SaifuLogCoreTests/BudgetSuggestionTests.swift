import Foundation
import Testing
@testable import SaifuLogCore

/// Fixture の今日は 2026-09-28。元にするのは 6・7・8 月（今月の 9 月は使わない）。
@Suite("月の予算の目安の提案")
struct BudgetSuggestionTests {
    static func suggestion(
        _ records: [TestRecord], recordingStartedAt: Date? = nil, now: Date = Fixture.now
    ) -> BudgetSuggestion? {
        BudgetSuggestion(records: records, recordingStartedAt: recordingStartedAt, now: now, calendar: Fixture.calendar)
    }

    static func spend(_ amount: Int, _ year: Int, _ month: Int, _ day: Int = 15) -> TestRecord {
        TestRecord(amount: amount, spentAt: Fixture.date(year, month, day, hour: 12))
    }

    @Test("直近 3 か月の支出の中央値を 1,000 円単位に丸める")
    func medianOfThreeMonths() throws {
        let records = [
            Self.spend(120_400, 2026, 6, 1),
            Self.spend(98_700, 2026, 7),
            Self.spend(100_000, 2026, 8),
            Self.spend(51_000, 2026, 8, 31),
        ]

        let suggestion = try #require(Self.suggestion(records))

        // 6 月 120,400・7 月 98,700・8 月 151,000 の中央値は 120,400。
        #expect(suggestion.monthlyExpenses == [151_000, 98_700, 120_400])
        #expect(suggestion.monthCount == 3)
        #expect(suggestion.amount == 120_000)
    }

    @Test("記録の無い月は使わない（2 か月なら 2 つの平均）")
    func skipsMonthsWithoutRecords() throws {
        let records = [Self.spend(120_400, 2026, 6, 1), Self.spend(151_000, 2026, 8)]

        let suggestion = try #require(Self.suggestion(records))

        #expect(suggestion.monthlyExpenses == [151_000, 120_400])
        // (151,000 + 120,400) ÷ 2 = 135,700 → 136,000。
        #expect(suggestion.amount == 136_000)
    }

    @Test("収入だけの月は、支出の記録が無い月として使わない")
    func skipsIncomeOnlyMonths() throws {
        let records = [
            Self.spend(80_000, 2026, 7, 1),
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 8, 25)),
        ]

        let suggestion = try #require(Self.suggestion(records))

        #expect(suggestion.monthlyExpenses == [80_000])
        #expect(suggestion.amount == 80_000)
    }

    @Test("1,000 円単位の四捨五入（500 円は切り上げ。平均の端数で境目をずらさない）", arguments: [
        ([12_499], 12_000),
        ([12_500], 13_000),
        ([12_000, 12_999], 12_000), // 平均 12,499.5 → 12,000
        ([12_000, 13_000], 13_000), // 平均 12,500 → 13,000
        ([1_000, 5_000, 900_000], 5_000),
    ])
    func rounding(values: [Int], expected: Int) {
        #expect(BudgetSuggestion.roundedMedian(of: values) == expected)
    }

    @Test("予算の上限を超える目安は、上限以下の 1,000 円単位にする")
    func capsAtMaximumBudget() {
        #expect(BudgetSuggestion.roundedMedian(of: [150_000_000]) == 99_999_000)
    }

    @Test("今月の記録だけ・記録が無いときは提案しない")
    func noSuggestionWithoutCompletedMonth() {
        #expect(Self.suggestion([Self.spend(50_000, 2026, 9, 1)]) == nil)
        #expect(Self.suggestion([]) == nil)
    }

    @Test("4 か月以上前の記録は使わない")
    func ignoresOlderMonths() {
        #expect(Self.suggestion([Self.spend(50_000, 2026, 5, 1)]) == nil)
    }

    @Test("途中から記録を始めた月は使わない（記録が 1 か月分に満たなければ提案しない）")
    func skipsPartialFirstMonth() throws {
        // 8 月 10 日から記録を始めた。8 月は途中からなので、まだ 1 か月分の記録が無い。
        #expect(Self.suggestion([Self.spend(30_000, 2026, 8, 20)], recordingStartedAt: Fixture.date(2026, 8, 10)) == nil)

        // 7 月 10 日から始めたなら、7 月は使わず、8 月だけで出す。
        let suggestion = try #require(Self.suggestion(
            [Self.spend(30_000, 2026, 7, 20), Self.spend(90_000, 2026, 8)],
            recordingStartedAt: Fixture.date(2026, 7, 10)
        ))
        #expect(suggestion.monthlyExpenses == [90_000])
        #expect(suggestion.amount == 90_000)
    }

    @Test("記録を始めた日が月の 1 日なら、その月も使う")
    func usesFirstMonthStartedOnFirstDay() throws {
        let records = [
            TestRecord(amount: 70_000, spentAt: Fixture.date(2026, 8, 1, hour: 23, minute: 59)),
            Self.spend(10_000, 2026, 9, 2),
        ]

        let suggestion = try #require(Self.suggestion(records))

        #expect(suggestion.monthlyExpenses == [70_000])
    }

    @Test("目安が 0 円なら提案しない")
    func noSuggestionForZero() {
        #expect(Self.suggestion([Self.spend(499, 2026, 8, 1)]) == nil)
    }

    @Test("月をまたいでも、年の初めは前の年の月を使う")
    func acrossYears() throws {
        let now = Fixture.date(2027, 1, 10)
        let records = [
            Self.spend(60_000, 2026, 10, 1), Self.spend(70_000, 2026, 11), Self.spend(80_000, 2026, 12),
            Self.spend(5_000, 2027, 1, 2),
        ]

        let suggestion = try #require(Self.suggestion(records, now: now))

        #expect(suggestion.monthlyExpenses == [80_000, 70_000, 60_000])
        #expect(suggestion.amount == 70_000)
    }

    @Test("いまの予算との差が 2 割以上のときだけ、大きい差とする", arguments: [
        (120_000, 100_000, true),
        (119_000, 100_000, false),
        (80_000, 100_000, true),
        (81_000, 100_000, false),
        (100_000, 100_000, false),
    ])
    func differsNotably(amount: Int, budget: Int, expected: Bool) throws {
        let suggestion = try #require(Self.suggestion([Self.spend(amount, 2026, 8, 1)]))

        #expect(suggestion.amount == amount)
        #expect(suggestion.differsNotably(from: budget) == expected)
    }
}
