import Foundation
import Testing
@testable import SaifuLogCore

/// 質問の答えの数字（LedgerQuestionAnswerer）。固定の日時 2026-09-28 12:00（日本時間、月曜日）で確かめる。
@Suite("質問の答えの数字")
struct LedgerQuestionAnswererTests {
    static let sundayFirst = Fixture.calendar(firstWeekday: 1)
    static let mondayFirst = Fixture.calendar(firstWeekday: 2)

    /// 期間の境目をまたぐ記録。
    static let records: [TestRecord] = [
        TestRecord(amount: 850, category: .food, spentAt: Fixture.date(2026, 9, 28, hour: 12)),        // 今日
        TestRecord(amount: 400, category: .cafe, spentAt: Fixture.date(2026, 9, 28, hour: 15)),        // 今日（いまより後の時刻）
        TestRecord(amount: 1_200, category: .cafe, spentAt: Fixture.date(2026, 9, 27, hour: 10)),      // 昨日（日曜）
        TestRecord(amount: 3_000, category: .transport, spentAt: Fixture.date(2026, 9, 22)),           // 直近 7 日の始まり
        TestRecord(amount: 999, category: .food, spentAt: Fixture.date(2026, 9, 21, hour: 23, minute: 59)), // 直近 7 日の外
        TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25)),              // 収入
        TestRecord(amount: 5_000, category: .food, spentAt: Fixture.date(2026, 8, 31, hour: 23, minute: 59)), // 先月の終わり
        TestRecord(amount: 700, category: .cafe, spentAt: Fixture.date(2026, 8, 1)),                   // 先月の始まり
        TestRecord(amount: 80_000, category: .other, spentAt: Fixture.date(2026, 9, 30)),              // 今月の先の日付
        TestRecord(amount: 2_000, category: .food, spentAt: Fixture.date(2026, 10, 1)),                // 来月の始まり（今月の外）
        TestRecord(amount: 10_000, category: .entertainment, spentAt: Fixture.date(2025, 12, 31, hour: 23)), // 去年
    ]

    static func answer(
        _ period: QuestionPeriod,
        _ metric: QuestionMetric,
        category: EntryCategory? = nil,
        records: [TestRecord] = records,
        budget: BudgetPlan = BudgetPlan(),
        decidedAt: Date? = nil,
        calendar: Calendar = Fixture.calendar
    ) -> LedgerAnswer? {
        LedgerQuestionAnswerer.answer(
            LedgerQuestion(period: period, metric: metric, category: category),
            records: records, budget: budget, budgetDecidedAt: decidedAt, now: Fixture.now, calendar: calendar
        )
    }

    // MARK: - 支出・収入・収支

    @Test("支出の合計と件数（期間ごと）", arguments: [
        (QuestionPeriod.today, 1_250, 2),
        (.yesterday, 1_200, 1),
        (.thisMonth, 86_449, 6),
        (.lastMonth, 5_700, 2),
        (.recentDays(7), 5_450, 4),
        (.recentDays(1), 1_250, 2),
        (.thisYear, 94_149, 9),
    ])
    func expenseTotal(period: QuestionPeriod, amount: Int, count: Int) throws {
        let answer = try #require(Self.answer(period, .expenseTotal))

        #expect(answer.value == .amount(amount))
        #expect(answer.recordCount == count)
        #expect(answer.period == period)
    }

    @Test("今週・先週は週の始まりの設定に従う", arguments: [
        (QuestionPeriod.thisWeek, 1, 84_450),
        (.thisWeek, 2, 83_250),
        (.lastWeek, 1, 3_999),
        (.lastWeek, 2, 5_199),
    ])
    func weeksFollowWeekStart(period: QuestionPeriod, firstWeekday: Int, amount: Int) throws {
        let calendar = firstWeekday == 1 ? Self.sundayFirst : Self.mondayFirst

        let answer = try #require(Self.answer(period, .expenseTotal, calendar: calendar))

        #expect(answer.value == .amount(amount))
        #expect(answer.interval == period.interval(now: Fixture.now, calendar: calendar))
    }

    @Test("カテゴリの支出と件数")
    func categoryExpense() throws {
        let thisMonth = try #require(Self.answer(.thisMonth, .categoryExpense, category: .cafe))
        #expect(thisMonth.value == .amount(1_600))
        #expect(thisMonth.recordCount == 2)

        let lastMonth = try #require(Self.answer(.lastMonth, .expenseTotal, category: .cafe))
        #expect(lastMonth.question.metric == .categoryExpense)
        #expect(lastMonth.value == .amount(700))

        let none = try #require(Self.answer(.thisMonth, .categoryExpense, category: .medical))
        #expect(none.value == .amount(0))
        #expect(none.recordCount == 0)
    }

    @Test("収入の合計と収支")
    func incomeAndBalance() throws {
        let income = try #require(Self.answer(.thisMonth, .incomeTotal))
        #expect(income.value == .amount(250_000))
        #expect(income.recordCount == 1)

        let balance = try #require(Self.answer(.thisMonth, .balance))
        #expect(balance.value == .balance(163_551))
        #expect(balance.recordCount == 7)

        let lastMonthBalance = try #require(Self.answer(.lastMonth, .balance))
        #expect(lastMonthBalance.value == .balance(-5_700))
    }

    @Test("収入だけの期間は、支出が 0 で収入が出る")
    func incomeOnly() throws {
        let records = [TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25))]

        let expense = try #require(Self.answer(.thisMonth, .expenseTotal, records: records))
        #expect(expense.value == .amount(0))
        #expect(expense.recordCount == 0)
        #expect(try #require(Self.answer(.thisMonth, .incomeTotal, records: records)).value == .amount(250_000))
        #expect(try #require(Self.answer(.thisMonth, .topCategory, records: records)).value == .topCategory(nil))
        #expect(try #require(Self.answer(.thisMonth, .entryCount, records: records)).value == .count(1))
    }

    // MARK: - 内訳・件数

    @Test("カテゴリ別の内訳といちばん多いカテゴリ")
    func breakdownAndTop() throws {
        let breakdown = try #require(Self.answer(.thisMonth, .expenseByCategory))
        guard case .breakdown(let value) = breakdown.value else {
            Issue.record("内訳にならなかった")
            return
        }
        #expect(value.items.map(\.category) == [.other, .transport, .food, .cafe])
        #expect(value.total == 86_449)
        #expect(value.items.map(\.percent).reduce(0, +) == 100)
        #expect(breakdown.recordCount == 6)

        let top = try #require(Self.answer(.thisMonth, .topCategory))
        #expect(top.value == .topCategory(value.items.first))
    }

    @Test("件数は、カテゴリがあればその支出の件数、無ければすべての記録の件数")
    func entryCount() throws {
        #expect(try #require(Self.answer(.thisMonth, .entryCount)).value == .count(7))
        #expect(try #require(Self.answer(.thisMonth, .entryCount, category: .cafe)).value == .count(2))
        #expect(try #require(Self.answer(.today, .entryCount)).value == .count(2))
    }

    @Test("記録が 0 件でも答える（0 円・0 件）")
    func noRecords() throws {
        let empty: [TestRecord] = []
        let expense = try #require(Self.answer(.thisMonth, .expenseTotal, records: empty))
        #expect(expense.value == .amount(0))
        #expect(expense.recordCount == 0)
        #expect(try #require(Self.answer(.thisMonth, .expenseByCategory, records: empty)).value == .breakdown(CategoryBreakdown(expenseByCategory: [:])))
        #expect(try #require(Self.answer(.thisMonth, .topCategory, records: empty)).value == .topCategory(nil))
        #expect(try #require(Self.answer(.thisMonth, .balance, records: empty)).value == .balance(0))
    }

    @Test("期間の境目: 始まりの時刻は含み、終わりの時刻（翌月 1 日 0 時）は含まない")
    func boundaries() throws {
        let records = [
            TestRecord(amount: 100, spentAt: Fixture.date(2026, 9, 1)),
            TestRecord(amount: 200, spentAt: Fixture.date(2026, 9, 30, hour: 23, minute: 59)),
            TestRecord(amount: 400, spentAt: Fixture.date(2026, 10, 1)),
            TestRecord(amount: 800, spentAt: Fixture.date(2026, 8, 31, hour: 23, minute: 59)),
        ]

        #expect(try #require(Self.answer(.thisMonth, .expenseTotal, records: records)).value == .amount(300))
        #expect(try #require(Self.answer(.lastMonth, .expenseTotal, records: records)).value == .amount(800))
    }

    // MARK: - 予算

    @Test("予算の残りと 1 日あたりに使える額（今月。残りの日数は今日を含める）")
    func budget() throws {
        let plan = BudgetPlan(total: 150_000)

        let remaining = try #require(Self.answer(.thisMonth, .remainingBudget, budget: plan))
        guard case .budget(let status) = remaining.value else {
            Issue.record("予算の答えにならなかった")
            return
        }
        #expect(status.remaining == 63_551)
        #expect(status.remainingDays == 3)
        #expect(remaining.recordCount == 6)

        let daily = try #require(Self.answer(.thisMonth, .dailyAllowance, budget: plan))
        guard case .dailyAllowance(let dailyStatus) = daily.value else {
            Issue.record("1 日あたりの答えにならなかった")
            return
        }
        #expect(dailyStatus.dailyAllowance == 21_183)
    }

    @Test("予算を超えたら、超えた額")
    func overBudget() throws {
        let answer = try #require(Self.answer(.thisMonth, .dailyAllowance, budget: BudgetPlan(total: 50_000)))
        guard case .dailyAllowance(let status) = answer.value else {
            Issue.record("1 日あたりの答えにならなかった")
            return
        }
        #expect(status.isOver)
        #expect(status.overspent == 36_449)
        #expect(status.dailyAllowance == 0)
    }

    @Test("予算を決めていなければ、予算なし")
    func noBudget() throws {
        #expect(try #require(Self.answer(.thisMonth, .remainingBudget)).value == .noBudget)
        #expect(try #require(Self.answer(.thisMonth, .dailyAllowance)).value == .noBudget)
        #expect(try #require(Self.answer(.lastMonth, .remainingBudget)).value == .noBudget)
    }

    @Test("予算は月で数える。今週や今年を聞かれても今月、1 日あたりはいつも今月")
    func budgetUsesMonth() throws {
        let plan = BudgetPlan(total: 150_000)

        let year = try #require(Self.answer(.thisYear, .remainingBudget, budget: plan))
        #expect(year.period == .thisMonth)
        #expect(year.question.period == .thisYear)
        #expect(year.interval == ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: Fixture.calendar))

        let daily = try #require(Self.answer(.lastMonth, .dailyAllowance, budget: plan))
        #expect(daily.period == .thisMonth)
    }

    @Test("先月の予算の残りは、いまの予算を先月の終わりより前に決めていたときだけ")
    func lastMonthBudget() throws {
        let plan = BudgetPlan(total: 150_000)

        let applies = try #require(Self.answer(.lastMonth, .remainingBudget, budget: plan, decidedAt: Fixture.date(2026, 8, 15)))
        guard case .budget(let status) = applies.value else {
            Issue.record("予算の答えにならなかった")
            return
        }
        #expect(applies.period == .lastMonth)
        #expect(status.remaining == 144_300)

        let decidedThisMonth = try #require(
            Self.answer(.lastMonth, .remainingBudget, budget: plan, decidedAt: Fixture.date(2026, 9, 10))
        )
        #expect(decidedThisMonth.value == .budgetNotApplicable)
        #expect(try #require(Self.answer(.lastMonth, .remainingBudget, budget: plan)).value == .budgetNotApplicable)
    }

    @Test("カテゴリ別の予算は数えない（全体の予算だけ）")
    func categoryBudgetIgnored() throws {
        let plan = BudgetPlan(byCategory: [.cafe: 5_000])

        #expect(try #require(Self.answer(.thisMonth, .remainingBudget, category: .cafe, budget: plan)).value == .noBudget)
    }

    // MARK: - 期間

    @Test("直近 N 日は、今日を含めて N 日（今日の終わりまで）。範囲の外は答えない")
    func recentDaysInterval() throws {
        #expect(QuestionPeriod.recentDays(7).interval(now: Fixture.now, calendar: Fixture.calendar)
            == DateInterval(start: Fixture.date(2026, 9, 22), end: Fixture.date(2026, 9, 29)))
        #expect(QuestionPeriod.recentDays(0).interval(now: Fixture.now, calendar: Fixture.calendar) == nil)
        #expect(QuestionPeriod.recentDays(367).interval(now: Fixture.now, calendar: Fixture.calendar) == nil)
        #expect(Self.answer(.recentDays(0), .expenseTotal) == nil)
    }

    /// 夏時間が始まる日（2026-03-08 はニューヨークで 23 時間）をまたいでも、日の境目で区切る。
    @Test("直近 N 日は夏時間の日も暦で数える")
    func recentDaysAcrossDaylightSaving() throws {
        let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")
        let now = try #require(newYork.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)))

        let interval = try #require(QuestionPeriod.recentDays(3).interval(now: now, calendar: newYork))

        #expect(interval.start == newYork.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        #expect(interval.end == newYork.date(from: DateComponents(year: 2026, month: 3, day: 11)))
    }

    @Test("読み込む範囲は、答えうる期間をすべて覆う")
    func window() throws {
        let window = try #require(QuestionLedger.window(now: Fixture.now, calendar: Fixture.calendar))

        #expect(window.start == Fixture.date(2025, 9, 28))
        #expect(window.end == Fixture.date(2027, 1, 1))
    }

    @Test("質問の組み合わせをそろえる")
    func normalization() {
        #expect(LedgerQuestion(period: .today, metric: .expenseTotal, category: .cafe).metric == .categoryExpense)
        #expect(LedgerQuestion(period: .today, metric: .categoryExpense).metric == .expenseTotal)
        #expect(LedgerQuestion(period: .today, metric: .incomeTotal, category: .cafe).category == nil)
        #expect(LedgerQuestion(period: .today, metric: .topCategory, category: .cafe).category == nil)
        #expect(LedgerQuestion(period: .today, metric: .entryCount, category: .cafe).category == .cafe)
    }

    @Test("値だけの写しで答えても同じ")
    func snapshot() throws {
        let ledger = QuestionLedger(records: Self.records.map(LedgerRecordValue.init), budget: BudgetPlan(total: 150_000))
        let question = LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe)

        let answer = try #require(LedgerQuestionAnswerer.answer(question, ledger: ledger, now: Fixture.now, calendar: Fixture.calendar))

        #expect(answer.value == .amount(1_600))
    }
}
