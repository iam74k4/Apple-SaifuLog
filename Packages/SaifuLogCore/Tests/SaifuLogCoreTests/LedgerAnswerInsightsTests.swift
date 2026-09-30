import Foundation
import Testing
@testable import SaifuLogCore

@Suite("答えの比べ・推移・続けて聞く質問")
struct LedgerAnswerInsightsTests {
    /// 2026-09-28 12:00（月曜日。週の始まりは日曜）。
    static let now = Fixture.now
    static let calendar = Fixture.calendar(firstWeekday: 1)

    static func record(_ amount: Int, _ year: Int, _ month: Int, _ day: Int, category: EntryCategory = .cafe, isIncome: Bool = false) -> LedgerRecordValue {
        LedgerRecordValue(amount: amount, isIncome: isIncome, category: category, spentAt: Fixture.date(year, month, day, hour: 10))
    }

    static func answer(_ question: LedgerQuestion, _ records: [LedgerRecordValue], budget: BudgetPlan = BudgetPlan()) -> LedgerAnswer? {
        LedgerQuestionAnswerer.answer(
            question, ledger: QuestionLedger(records: records, budget: budget), now: now, calendar: calendar
        )
    }

    // MARK: - 比べる期間

    @Test("途中の期間は、前の期間の同じところまでと比べる")
    func toDateIntervals() throws {
        let month = try #require(QuestionPeriod.thisMonth.comparison(now: Self.now, calendar: Self.calendar))
        #expect(month.baseline == .lastMonthToDate)
        #expect(month.interval == DateInterval(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 28, hour: 12)))

        let week = try #require(QuestionPeriod.thisWeek.comparison(now: Self.now, calendar: Self.calendar))
        #expect(week.baseline == .lastWeekToDate)
        #expect(week.interval == DateInterval(start: Fixture.date(2026, 9, 20), end: Fixture.date(2026, 9, 21, hour: 12)))

        let today = try #require(QuestionPeriod.today.comparison(now: Self.now, calendar: Self.calendar))
        #expect(today.interval == DateInterval(start: Fixture.date(2026, 9, 27), end: Fixture.date(2026, 9, 27, hour: 12)))

        let year = try #require(QuestionPeriod.thisYear.comparison(now: Self.now, calendar: Self.calendar))
        #expect(year.baseline == .lastYearToDate)
        #expect(year.interval == DateInterval(start: Fixture.date(2025, 1, 1), end: Fixture.date(2025, 9, 28, hour: 12)))
    }

    @Test("終わった期間は、その前の期間まるごとと比べる。3 月 31 日の先月の同じ日は 2 月の終わりまで")
    func wholeIntervals() throws {
        let lastMonth = try #require(QuestionPeriod.lastMonth.comparison(now: Self.now, calendar: Self.calendar))
        #expect(lastMonth.baseline == .monthBeforeLast)
        #expect(lastMonth.interval == DateInterval(start: Fixture.date(2026, 7, 1), end: Fixture.date(2026, 8, 1)))

        let recent = try #require(QuestionPeriod.recentDays(7).comparison(now: Self.now, calendar: Self.calendar))
        #expect(recent.baseline == .previousDays(7))
        #expect(recent.interval == DateInterval(start: Fixture.date(2026, 9, 15), end: Fixture.date(2026, 9, 22)))
        #expect(QuestionPeriod.recentDays(LedgerComparison.maximumComparedDays + 1).comparison(now: Self.now, calendar: Self.calendar) == nil)

        let endOfMarch = Fixture.date(2026, 3, 31, hour: 20)
        let march = try #require(QuestionPeriod.thisMonth.comparison(now: endOfMarch, calendar: Self.calendar))
        #expect(march.interval == DateInterval(start: Fixture.date(2026, 2, 1), end: Fixture.date(2026, 2, 28, hour: 20)))
    }

    // MARK: - 比べ

    @Test("今月のカフェを、先月の同じ日までのカフェと比べる（同じ日より後の先月の記録は数えない）")
    func comparesCategoryToDate() throws {
        let answer = try #require(Self.answer(LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe), [
            Self.record(3_000, 2026, 9, 3), Self.record(4_200, 2026, 9, 20), Self.record(800, 2026, 9, 21, category: .food),
            Self.record(5_400, 2026, 8, 10), Self.record(9_999, 2026, 8, 29),
        ]))

        #expect(answer.value == .amount(7_200))
        let comparison = try #require(answer.comparison)
        #expect(comparison.previous == 5_400)
        #expect(comparison.previousRecordCount == 1)
        #expect(comparison.difference == 1_800)
    }

    @Test("件数も比べる。内訳・予算・収支は比べない")
    func comparedMetrics() throws {
        let records = [Self.record(500, 2026, 9, 3), Self.record(500, 2026, 9, 4), Self.record(500, 2026, 8, 3)]
        let count = try #require(Self.answer(LedgerQuestion(period: .thisMonth, metric: .entryCount), records))
        #expect(count.comparison?.difference == 1)
        #expect(Self.answer(LedgerQuestion(period: .thisMonth, metric: .expenseByCategory), records)?.comparison == nil)
        #expect(Self.answer(LedgerQuestion(period: .thisMonth, metric: .balance), records)?.comparison == nil)
        #expect(Self.answer(
            LedgerQuestion(period: .thisMonth, metric: .remainingBudget), records, budget: BudgetPlan(total: 100_000)
        )?.comparison == nil)
    }

    @Test("前の期間に記録が無ければ、件数 0 として渡す（画面は差を出さない）")
    func noPreviousRecords() throws {
        let answer = try #require(Self.answer(LedgerQuestion(period: .thisWeek, metric: .expenseTotal), [Self.record(500, 2026, 9, 27)]))
        #expect(answer.comparison?.previousRecordCount == 0)
        #expect(answer.comparison?.difference == 500)
    }

    // MARK: - 推移

    @Test("今月・先月の金額の答えには、答えの月までの 6 か月の推移を付ける")
    func trend() throws {
        let records = [
            Self.record(1_000, 2026, 4, 5), Self.record(2_000, 2026, 6, 5), Self.record(3_000, 2026, 9, 5),
            Self.record(99_999, 2026, 3, 31),
        ]
        let answer = try #require(Self.answer(LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe), records))
        let trend = try #require(answer.trend)
        #expect(trend.points.map(\.value) == [1_000, 0, 2_000, 0, 0, 3_000])
        #expect(trend.points.first?.month.start == Fixture.date(2026, 4, 1))
        #expect(trend.points.last?.month.start == Fixture.date(2026, 9, 1))
        #expect(trend.maximum == 3_000)

        let lastMonth = try #require(Self.answer(LedgerQuestion(period: .lastMonth, metric: .expenseTotal), records))
        #expect(lastMonth.trend?.points.last?.month.start == Fixture.date(2026, 8, 1))
    }

    @Test("前の月に値が無いときと、月でない期間・金額でない指標には推移を付けない")
    func noTrend() {
        let onlyThisMonth = [Self.record(3_000, 2026, 9, 5)]
        #expect(Self.answer(LedgerQuestion(period: .thisMonth, metric: .expenseTotal), onlyThisMonth)?.trend == nil)
        let history = [Self.record(1_000, 2026, 7, 5), Self.record(3_000, 2026, 9, 5)]
        #expect(Self.answer(LedgerQuestion(period: .thisWeek, metric: .expenseTotal), history)?.trend == nil)
        #expect(Self.answer(LedgerQuestion(period: .thisMonth, metric: .expenseByCategory), history)?.trend == nil)
    }

    // MARK: - AI に渡す文

    @Test("AI に渡す文に比べを書き、その数字を一言に使ってよい")
    func factsIncludeComparison() throws {
        let answer = try #require(Self.answer(LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe), [
            Self.record(7_200, 2026, 9, 3), Self.record(5_400, 2026, 8, 10),
        ]))
        let facts = LedgerAnswerFacts.text(for: answer, calendar: Self.calendar)

        #expect(facts.contains("前の期間との比べ: 先月の同じ日まで（¥5,400）より ¥1,800 多い"))
        #expect(AnswerSentenceCheck.accepts("今月のカフェは¥7,200で、先月より¥1,800多めです。", facts: facts))
        #expect(!AnswerSentenceCheck.accepts("先月より¥2,000多めです。", facts: facts))
    }

    // MARK: - 続けて聞く質問

    @Test("続けて聞く質問: 途中の期間は前の期間、終わった期間はいまの期間、金額なら内訳、内訳なら予算の残り")
    func followUps() throws {
        let records = [Self.record(500, 2026, 9, 3)]
        let cafe = try #require(Self.answer(LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe), records))
        #expect(cafe.followUps.map(\.text) == ["先月のカフェはいくら?", "今月の内訳は?"])

        let lastWeek = try #require(Self.answer(LedgerQuestion(period: .lastWeek, metric: .expenseTotal), records))
        #expect(lastWeek.followUps.map(\.text) == ["今週の支出はいくら?", "先週の内訳は?"])

        let breakdown = try #require(Self.answer(
            LedgerQuestion(period: .thisMonth, metric: .expenseByCategory), records, budget: BudgetPlan(total: 100_000)
        ))
        #expect(breakdown.followUps.map(\.text) == ["先月の内訳は?", "今月の予算の残りは?"])
        // 予算が無ければ、予算の残りは出さない。
        #expect(Self.answer(LedgerQuestion(period: .thisMonth, metric: .expenseByCategory), records)?.followUps.map(\.text)
            == ["先月の内訳は?"])

        let budget = try #require(Self.answer(
            LedgerQuestion(period: .thisMonth, metric: .dailyAllowance), records, budget: BudgetPlan(total: 100_000)
        ))
        #expect(budget.followUps.map(\.text) == ["今月の内訳は?"])

        // 読めない期間（去年・直近 N 日の前）は出さない。
        let year = try #require(Self.answer(LedgerQuestion(period: .thisYear, metric: .incomeTotal), records))
        #expect(year.followUps.isEmpty)
    }

    /// 送る文を質問の読み取りが同じ質問に読み、記録ではなく質問に分ける（AI が使えない端末でも同じ答えになるように）。
    @Test("続けて聞く質問の文は、質問の読み取りで同じ質問に読める", arguments: [
        QuestionPeriod.today, .yesterday, .thisWeek, .lastWeek, .thisMonth, .lastMonth, .thisYear,
    ])
    func followUpTextsParseBack(period: QuestionPeriod) {
        let catalog = CategoryCatalog(customs: [CustomCategoryInfo(id: "c1", name: "衣服", symbolName: "tshirt", colorIndex: 0)])
        var questions: [LedgerQuestion] = QuestionMetric.allCases.map { LedgerQuestion(period: period, metric: $0) }
        for category in EntryCategory.builtIns + [.custom("c1")] {
            questions.append(LedgerQuestion(period: period, metric: .categoryExpense, category: category))
            questions.append(LedgerQuestion(period: period, metric: .entryCount, category: category))
        }
        for question in questions {
            guard let text = QuestionFollowUp.text(for: question, catalog: catalog) else { continue }
            #expect(QuestionParser.question(from: text, now: Self.now, calendar: Self.calendar, catalog: catalog) == question, "\(text)")
            #expect(InputIntentClassifier.classify(text, now: Self.now, calendar: Self.calendar, catalog: catalog) == .question, "\(text)")
        }
    }
}
