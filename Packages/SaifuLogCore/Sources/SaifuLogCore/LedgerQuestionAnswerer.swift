import Foundation

/// 質問に答えるための記録と予算（読み込んだ時点の写し）。
///
/// AI のツールはメインスレッドの外で呼ばれるので、保存用のモデル（SwiftData）を渡さずに、値だけの写しを渡す。
/// 読み込む範囲は `window(now:calendar:)`（答えうる期間をすべて覆う範囲）。
public struct QuestionLedger: Sendable, Hashable {
    public var records: [LedgerRecordValue]
    /// いま有効な予算。
    public var budget: BudgetPlan
    /// いまの全体の予算をその額に決めた日時（`BudgetPlan.decidedAt`）。先月の予算の残りを出してよいかに使う。
    public var budgetDecidedAt: Date?

    public init(records: [LedgerRecordValue] = [], budget: BudgetPlan = BudgetPlan(), budgetDecidedAt: Date? = nil) {
        self.records = records
        self.budget = budget
        self.budgetDecidedAt = budgetDecidedAt
    }

    /// 質問で答えうる期間（今日〜今年と、直近 N 日のいちばん長いもの）をすべて覆う範囲。終わりの時刻は含まない。
    ///
    /// AI のツールは、どの期間を聞かれるかを読み込む前には知らないので、どれを聞かれても足りる範囲を先に読む。
    public static func window(now: Date, calendar: Calendar) -> DateInterval? {
        let periods: [QuestionPeriod] = [
            .today, .yesterday, .thisWeek, .lastWeek, .thisMonth, .lastMonth, .thisYear,
            .recentDays(QuestionPeriod.recentDaysRange.upperBound),
        ]
        let intervals = periods.compactMap { $0.interval(now: now, calendar: calendar) }
        guard let start = intervals.map(\.start).min(), let end = intervals.map(\.end).max() else { return nil }
        return DateInterval(start: start, end: end)
    }
}

/// 集計に使う記録の値だけの形（`LedgerRecord` の写し）。スレッドをまたいで渡せる。
public struct LedgerRecordValue: LedgerRecord, Sendable, Hashable {
    public var amount: Int
    public var isIncome: Bool
    public var category: EntryCategory
    public var spentAt: Date

    public init(amount: Int, isIncome: Bool = false, category: EntryCategory = .other, spentAt: Date) {
        self.amount = amount
        self.isIncome = isIncome
        self.category = category
        self.spentAt = spentAt
    }

    public init(_ record: some LedgerRecord) {
        self.init(amount: record.amount, isIncome: record.isIncome, category: record.category, spentAt: record.spentAt)
    }
}

/// 構造化した質問（`LedgerQuestion`）から、答えの数字（`LedgerAnswer`）を計算する。
///
/// 数字はすべてここで計算する（AI には計算させない）。期間は `QuestionPeriod`（`ReportPeriod`）、集計は `LedgerSummary`、
/// 内訳は `CategoryBreakdown`、予算の進みは `BudgetStatus` を使い、ホームの帯と月のまとめの数字と食い違わせない。
///
/// 決め事:
/// - 元になった件数は、数えた記録の件数。支出の合計・内訳・いちばん多いカテゴリ・予算は支出の件数、収入は収入の件数、
///   収支と（カテゴリを聞かれていない）件数は支出と収入の件数、カテゴリの支出はそのカテゴリの支出の件数。
/// - 予算は月の全体の予算だけで数える。カテゴリ別の予算の進みは月のまとめにだけ出す決め事（docs/design.md §6-1）のため。
/// - 予算の残りは、先月を聞かれたら先月、それ以外は今月で数える（予算は月ごとのものなので、今週や今年の予算は無い）。
///   先月は、いまの予算を決めた日時が先月の終わりより前のときだけ出す（月のまとめと同じ。それより前の月の予算は
///   残していない）。1 日あたりに使える額は今月だけ（先の日数があるのは今月だけのため）。数えた期間は答えに入れて、
///   回答カードに出す（聞かれた期間と違うことが分かるように）。
public enum LedgerQuestionAnswerer {
    /// 質問に答える。期間を暦で区切れなければ nil。
    public static func answer(_ question: LedgerQuestion, ledger: QuestionLedger, now: Date, calendar: Calendar) -> LedgerAnswer? {
        answer(
            question, records: ledger.records, budget: ledger.budget, budgetDecidedAt: ledger.budgetDecidedAt,
            now: now, calendar: calendar
        )
    }

    /// 質問に答える。期間を暦で区切れなければ nil。
    ///
    /// - Parameters:
    ///   - records: 数える記録（期間の外の記録が混じっていても数えない）。
    ///   - budget: いま有効な予算。
    ///   - budgetDecidedAt: いまの全体の予算をその額に決めた日時。先月の予算の残りを出すかに使う。
    ///   - now: 今日の日時。期間の区切りと、予算の残りの日数の基準。
    ///   - calendar: 期間の区切りの暦（ホームと同じ、利用者が選んだ暦と週の始まり）。
    public static func answer<Records: Sequence>(
        _ question: LedgerQuestion,
        records: Records,
        budget: BudgetPlan,
        budgetDecidedAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> LedgerAnswer? where Records.Element: LedgerRecord {
        let period = countedPeriod(for: question)
        guard let interval = period.interval(now: now, calendar: calendar) else { return nil }
        let summary = LedgerSummary(records: records, interval: interval, calendar: calendar)

        let recordCount: Int
        let value: LedgerAnswer.Value
        switch question.metric {
        case .expenseTotal:
            recordCount = summary.expenseCount
            value = .amount(summary.expense)
        case .categoryExpense:
            let category = question.category ?? .other
            recordCount = summary.expenseCount(in: category)
            value = .amount(summary.expense(in: category))
        case .incomeTotal:
            recordCount = summary.incomeCount
            value = .amount(summary.income)
        case .balance:
            recordCount = summary.recordCount
            value = .balance(summary.balance)
        case .expenseByCategory:
            recordCount = summary.expenseCount
            value = .breakdown(CategoryBreakdown(summary))
        case .topCategory:
            recordCount = summary.expenseCount
            value = .topCategory(CategoryBreakdown(summary).items.first)
        case .entryCount:
            let count = question.category.map { summary.expenseCount(in: $0) } ?? summary.recordCount
            recordCount = count
            value = .count(count)
        case .remainingBudget, .dailyAllowance:
            recordCount = summary.expenseCount
            value = budgetValue(
                for: question.metric, period: period, summary: summary, budget: budget,
                budgetDecidedAt: budgetDecidedAt, now: now, calendar: calendar
            )
        }
        return LedgerAnswer(question: question, period: period, interval: interval, recordCount: recordCount, value: value)
    }

    /// 実際に数える期間。予算の指標だけ、聞かれた期間から月に置き換える（上の決め事）。
    static func countedPeriod(for question: LedgerQuestion) -> QuestionPeriod {
        switch question.metric {
        case .remainingBudget: question.period == .lastMonth ? .lastMonth : .thisMonth
        case .dailyAllowance: .thisMonth
        default: question.period
        }
    }

    private static func budgetValue(
        for metric: QuestionMetric,
        period: QuestionPeriod,
        summary: LedgerSummary,
        budget: BudgetPlan,
        budgetDecidedAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> LedgerAnswer.Value {
        guard budget.total != nil else { return .noBudget }
        if period == .lastMonth {
            // 月のまとめ（`MonthlyReport`）と同じく、いまの予算を決めた月とそれより後の月にだけ当てはめる。
            guard let decidedAt = budgetDecidedAt, decidedAt < summary.interval.end else { return .budgetNotApplicable }
        }
        guard let status = BudgetStatus(budget: budget.total, summary: summary, now: now, calendar: calendar) else {
            return .noBudget
        }
        return metric == .dailyAllowance ? .dailyAllowance(status) : .budget(status)
    }
}
