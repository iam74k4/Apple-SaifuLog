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
    /// カテゴリの一覧。質問の文から作ったカテゴリの名前を読み、AI に渡す結果の文に名前を書くのに使う。
    public var catalog: CategoryCatalog

    public init(
        records: [LedgerRecordValue] = [], budget: BudgetPlan = BudgetPlan(), budgetDecidedAt: Date? = nil,
        catalog: CategoryCatalog = .builtIn
    ) {
        self.records = records
        self.budget = budget
        self.budgetDecidedAt = budgetDecidedAt
        self.catalog = catalog
    }

    /// 質問で答えうる期間（今日〜今年と、直近 N 日のいちばん長いもの）をすべて覆う範囲。終わりの時刻は含まない。
    ///
    /// AI のツールは、どの期間を聞かれるかを読み込む前には知らないので、どれを聞かれても足りる範囲を先に読む。
    ///
    /// 前の期間との比べ（`QuestionPeriod.comparison`）の期間も覆う（今年と比べる去年の同じ日までの分だけ、前へ広がる）。直近 N 日の
    /// 比べは、N が `LedgerComparison.maximumComparedDays` までなので、直近 366 日の中に収まる。
    public static func window(now: Date, calendar: Calendar) -> DateInterval? {
        let periods: [QuestionPeriod] = [
            .today, .yesterday, .thisWeek, .lastWeek, .thisMonth, .lastMonth, .thisYear,
            .recentDays(QuestionPeriod.recentDaysRange.upperBound),
        ]
        let intervals = periods.compactMap { $0.interval(now: now, calendar: calendar) }
            + periods.compactMap { $0.comparison(now: now, calendar: calendar)?.interval }
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
        guard var answer = answer(
            question, records: ledger.records, budget: ledger.budget, budgetDecidedAt: ledger.budgetDecidedAt,
            now: now, calendar: calendar
        ) else { return nil }
        answer.followUps = QuestionFollowUp.suggestions(for: answer, hasBudget: ledger.budget.total != nil, catalog: ledger.catalog)
        return answer
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
        // 比べと推移で何度も数えるので、1 回で読み切れない列（Sequence）も数えられるよう配列にする。
        let records = Array(records)
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
        return LedgerAnswer(
            question: question, period: period, interval: interval, recordCount: recordCount, value: value,
            comparison: comparison(for: question, period: period, value: value, records: records, now: now, calendar: calendar),
            trend: trend(for: question, period: period, interval: interval, records: records, calendar: calendar)
        )
    }

    /// 比べる値と、その元になった記録の件数（金額と件数の指標だけ。内訳・いちばん多いカテゴリ・予算・収支は比べない）。
    static func comparedValue(of question: LedgerQuestion, in summary: LedgerSummary) -> (value: Int, recordCount: Int)? {
        switch question.metric {
        case .expenseTotal:
            return (summary.expense, summary.expenseCount)
        case .categoryExpense:
            let category = question.category ?? .other
            return (summary.expense(in: category), summary.expenseCount(in: category))
        case .incomeTotal:
            return (summary.income, summary.incomeCount)
        case .entryCount:
            let count = question.category.map { summary.expenseCount(in: $0) } ?? summary.recordCount
            return (count, count)
        case .balance, .expenseByCategory, .topCategory, .remainingBudget, .dailyAllowance:
            return nil
        }
    }

    /// 前の期間との比べ（`QuestionPeriod.comparison` の期間で、同じ指標を数える）。
    static func comparison<Records: Sequence>(
        for question: LedgerQuestion, period: QuestionPeriod, value: LedgerAnswer.Value, records: Records, now: Date,
        calendar: Calendar
    ) -> LedgerComparison? where Records.Element: LedgerRecord {
        let current: Int
        switch value {
        case .amount(let amount): current = amount
        case .count(let count): current = count
        default: return nil
        }
        guard let (baseline, interval) = period.comparison(now: now, calendar: calendar) else { return nil }
        let summary = LedgerSummary(records: records, interval: interval, calendar: calendar)
        guard let previous = comparedValue(of: question, in: summary) else { return nil }
        return LedgerComparison(
            baseline: baseline, interval: interval, previous: previous.value, previousRecordCount: previous.recordCount,
            difference: current - previous.value
        )
    }

    /// 月ごとの推移（今月・先月の支出の合計・カテゴリの支出・収入の合計だけ）。答えの月を最後に `LedgerTrend.monthCount` か月。
    /// 前の月のどれにも値が無ければ出さない（使い始めたばかりの人に、空の棒を並べないため）。
    static func trend<Records: Sequence>(
        for question: LedgerQuestion, period: QuestionPeriod, interval: DateInterval, records: Records, calendar: Calendar
    ) -> LedgerTrend? where Records.Element: LedgerRecord {
        guard period.isWholeMonth,
              [.expenseTotal, .categoryExpense, .incomeTotal].contains(question.metric) else { return nil }
        var points: [LedgerTrend.Point] = []
        for offset in stride(from: LedgerTrend.monthCount - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .month, value: -offset, to: interval.start),
                  let month = calendar.dateInterval(of: .month, for: day),
                  let value = comparedValue(of: question, in: LedgerSummary(records: records, interval: month, calendar: calendar))
            else { return nil }
            points.append(LedgerTrend.Point(month: month, value: value.value))
        }
        guard points.dropLast().contains(where: { $0.value > 0 }) else { return nil }
        return LedgerTrend(points: points)
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
