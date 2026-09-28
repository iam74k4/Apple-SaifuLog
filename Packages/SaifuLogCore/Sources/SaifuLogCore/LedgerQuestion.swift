import Foundation

/// 家計への質問の期間（今日・昨日・今週・先週・今月・先月・今年・直近 N 日）。
///
/// 区切りは `ReportPeriod`（ホームの今月・月のまとめと同じ暦、週の始まりは暦の `firstWeekday`）に任せる。
/// 質問の「今月」がホームの「今月」と別の期間にならないようにするため。
public enum QuestionPeriod: Hashable, Sendable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case thisYear
    /// 今日を含む直近 `days` 日（今日の終わりまで）。`days` は `recentDaysRange` の中。
    case recentDays(Int)

    /// 直近 N 日の N に使える範囲。1 年（うるう年を含む）より長い期間は読み込む記録が増えるだけで、
    /// 「今年」や月のまとめで足りるため、答えない（読めない質問にする）。
    public static let recentDaysRange = 1...366

    /// `now` を基準にした期間。終わりの時刻は含まない（`ReportPeriod` と同じ）。
    ///
    /// 直近 N 日は、今日を含めて N 日前の 0 時から、今日の終わり（翌日の 0 時）まで。暦で数え、秒数で引かない
    /// （夏時間の日は 23 時間や 25 時間になるため）。範囲の外の N は nil。
    public func interval(now: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .today: return ReportPeriod.today.interval(now: now, calendar: calendar)
        case .yesterday: return ReportPeriod.yesterday.interval(now: now, calendar: calendar)
        case .thisWeek: return ReportPeriod.thisWeek.interval(now: now, calendar: calendar)
        case .lastWeek: return ReportPeriod.lastWeek.interval(now: now, calendar: calendar)
        case .thisMonth: return ReportPeriod.thisMonth.interval(now: now, calendar: calendar)
        case .lastMonth: return ReportPeriod.lastMonth.interval(now: now, calendar: calendar)
        case .thisYear: return ReportPeriod.thisYear.interval(now: now, calendar: calendar)
        case .recentDays(let days):
            guard Self.recentDaysRange.contains(days),
                  let today = calendar.dateInterval(of: .day, for: now),
                  let start = calendar.date(byAdding: .day, value: -(days - 1), to: today.start)
            else { return nil }
            return DateInterval(start: calendar.startOfDay(for: start), end: today.end)
        }
    }

    /// 期間が暦の月まるごと（今月・先月）か。回答カードから、その月の月のまとめへ進めるかに使う。
    public var isWholeMonth: Bool {
        self == .thisMonth || self == .lastMonth
    }
}

/// 質問で知りたいこと（指標）。
///
/// rawValue は使わない（保存しない）。AI のツールの選択肢はアプリ側の `@Generable` の型に別に持ち、ここへ写す。
public enum QuestionMetric: Hashable, Sendable, CaseIterable {
    /// 支出の合計。
    case expenseTotal
    /// 収入の合計。
    case incomeTotal
    /// 収支（収入 − 支出）。
    case balance
    /// 支出のカテゴリ別の内訳。
    case expenseByCategory
    /// あるカテゴリの支出の合計。カテゴリが要る。
    case categoryExpense
    /// 記録の件数（カテゴリを聞かれたら、そのカテゴリの支出の件数）。
    case entryCount
    /// 月の予算の残り（超えたら超えた額）。
    case remainingBudget
    /// 今日から月末まで、1 日あたりに使える額。
    case dailyAllowance
    /// いちばん多く使ったカテゴリ。
    case topCategory

    /// 予算の指標か。予算は月の全体の予算だけを数える（カテゴリ別の予算の進みは、まだどこにも出さない決め事のため）。
    public var isBudget: Bool {
        self == .remainingBudget || self == .dailyAllowance
    }
}

/// 構造化した質問（期間 × 指標 × 任意のカテゴリ）。
///
/// 質問の文をどう読んでも（AI のツールの選択・キーワード辞書）、ここに直してから `LedgerQuestionAnswerer` が数字を
/// 計算する。AI には数字を計算させない（CLAUDE.md の決まり）。
public struct LedgerQuestion: Hashable, Sendable {
    public let period: QuestionPeriod
    public let metric: QuestionMetric
    /// 聞かれたカテゴリ。カテゴリを使わない指標では nil にそろえる。
    public let category: EntryCategory?

    /// 指標とカテゴリの組み合わせをそろえる。
    ///
    /// - 支出の合計にカテゴリが付いていれば、そのカテゴリの支出（`categoryExpense`）にする。カテゴリの支出なのに
    ///   カテゴリが無ければ、支出の合計にする（どちらで読んでも同じ答えにするため）。
    /// - 件数は、カテゴリがあればそのカテゴリの支出の件数、無ければすべての記録の件数。
    /// - 収入・収支・内訳・いちばん多いカテゴリ・予算は、カテゴリを使わない（収入はカテゴリで分けておらず、内訳と
    ///   いちばん多いカテゴリはすべてのカテゴリを比べるもの、予算は全体の予算だけを数えるため）。
    public init(period: QuestionPeriod, metric: QuestionMetric, category: EntryCategory? = nil) {
        self.period = period
        switch metric {
        case .expenseTotal, .categoryExpense:
            self.metric = category == nil ? .expenseTotal : .categoryExpense
            self.category = category
        case .entryCount:
            self.metric = .entryCount
            self.category = category
        case .incomeTotal, .balance, .expenseByCategory, .remainingBudget, .dailyAllowance, .topCategory:
            self.metric = metric
            self.category = nil
        }
    }
}

/// 質問への答え。数字はすべてコードで計算したもの（`LedgerQuestionAnswerer`）。
///
/// 画面の回答カードは、この値をそのまま出す（AI の一言とは別に）。AI が言い回しの中で数字を書き換えても、
/// 正しい値が見えるようにするため（docs/design.md §3-4）。
public struct LedgerAnswer: Hashable, Sendable {
    /// 答えの中身。
    public enum Value: Hashable, Sendable {
        /// 支出の合計・収入の合計・あるカテゴリの支出（円）。
        case amount(Int)
        /// 収支（収入 − 支出。負の数は支出が多い）。
        case balance(Int)
        /// 件数。
        case count(Int)
        /// 支出のカテゴリ別の内訳。
        case breakdown(CategoryBreakdown)
        /// いちばん多く使ったカテゴリ。支出が無ければ nil。
        case topCategory(CategoryBreakdown.Item?)
        /// 月の予算の進み（残りか超えた額）。
        case budget(BudgetStatus)
        /// 今日から月末まで 1 日あたりに使える額（予算を超えていれば超えた額）。
        case dailyAllowance(BudgetStatus)
        /// 月の予算を決めていない。
        case noBudget
        /// その月には、いまの予算を当てはめられない（いまの予算を決める前の月。月のまとめと同じ決め事）。
        case budgetNotApplicable
    }

    /// 聞かれた質問（指標とカテゴリをそろえたもの）。
    public let question: LedgerQuestion
    /// 実際に数えた期間。予算の指標は月で数えるので、聞かれた期間と違うことがある（`LedgerQuestionAnswerer`）。
    public let period: QuestionPeriod
    /// 数えた期間の区切り（終わりの時刻は含まない）。
    public let interval: DateInterval
    /// 答えの元になった記録の件数（何を数えたかは指標による。`LedgerQuestionAnswerer`）。
    public let recordCount: Int
    public let value: Value

    public init(question: LedgerQuestion, period: QuestionPeriod, interval: DateInterval, recordCount: Int, value: Value) {
        self.question = question
        self.period = period
        self.interval = interval
        self.recordCount = recordCount
        self.value = value
    }
}
