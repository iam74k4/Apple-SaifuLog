import Foundation

/// 今月の予算の進み（ホームの「今月あと ¥…」「1日あたり ¥…」）。
///
/// 残り・1 日あたりの額・残りの日数はコードで計算する（AI には計算させない）。ホーム・月のまとめ・質問への答えが
/// 同じ計算を使い、画面の数字と AI に渡す数字を食い違わせないため、ここに集める。
///
/// v1 の決め事:
/// - 予算に数えるのは支出だけ。収入（返金を含む）は予算の支出を減らさない（残りを増やさない）。
///   返金を差し引くと、給料などの収入の記録まで「使える額」に見えてしまい、どの収入を差し引くかを
///   利用者に選ばせる仕組みが v1 には無いため。
/// - 月の区切りは `ReportPeriod.thisMonth`（ホームの今月の合計と同じ、利用者が選んだ暦の月）。
/// - 残りの日数は今日を含めて数える。1 日あたりの額は、残りを残りの日数で割って切り捨てる
///   （切り上げると、毎日その額を使ったときに月末に予算を超えるため）。
public struct BudgetStatus: Sendable, Hashable {
    /// 予算（円）。
    public let budget: Int
    /// 予算の対象の、その月の支出（円）。
    public let spent: Int
    /// 月の終わりまでの日数。今日を含める（月末の日は 1）。
    public let remainingDays: Int

    /// - Parameters:
    ///   - budget: 予算。nil か 0 以下なら「設定なし」として nil を返す。
    ///   - spent: 予算の対象の、その月の支出。
    ///   - now: 今日の日時。残りの日数の基準。
    ///   - month: 予算を数える月（終わりの時刻は含まない）。
    public init?(budget: Int?, spent: Int, now: Date, month: DateInterval, calendar: Calendar) {
        guard let budget, budget > 0 else { return nil }
        self.budget = budget
        self.spent = spent
        self.remainingDays = Self.remainingDays(from: now, in: month, calendar: calendar)
    }

    /// 期間の集計（`LedgerSummary`）から、その対象の予算の進みを出す。期間は `summary.interval` を予算の月とみなす。
    public init?(budget: Int?, scope: BudgetScope = .total, summary: LedgerSummary, now: Date, calendar: Calendar) {
        let spent = switch scope {
        case .total: summary.expense
        case .category(let category): summary.expense(in: category)
        }
        self.init(budget: budget, spent: spent, now: now, month: summary.interval, calendar: calendar)
    }

    /// `now` を含む月（`ReportPeriod.thisMonth`）の記録から、予算の進みを出す。予算を決めていなければ nil。
    public init?<Records: Sequence>(
        plan: BudgetPlan, scope: BudgetScope = .total, records: Records, now: Date, calendar: Calendar
    ) where Records.Element: LedgerRecord {
        guard let month = ReportPeriod.thisMonth.interval(now: now, calendar: calendar) else { return nil }
        let summary = LedgerSummary(records: records, interval: month, calendar: calendar)
        self.init(budget: plan.amount(for: scope), scope: scope, summary: summary, now: now, calendar: calendar)
    }

    /// 予算の残り。予算を超えたら負の数。
    public var remaining: Int {
        budget - spent
    }

    /// 予算を超えたか（ちょうど使い切ったときは超えていない）。
    public var isOver: Bool {
        spent > budget
    }

    /// 予算を超えた額。超えていなければ 0。
    public var overspent: Int {
        max(0, spent - budget)
    }

    /// 今日から月末まで、1 日あたりに使える額（切り捨て）。残りが無ければ 0。
    public var dailyAllowance: Int {
        remaining > 0 ? remaining / remainingDays : 0
    }

    /// 予算のうち使った割合（0〜1）。進捗のバーに使う。超えたら 1 のまま。
    public var spentFraction: Double {
        min(max(Double(spent) / Double(budget), 0), 1)
    }

    /// `now` の日から `month` の終わりまでの日数（`now` の日を含む）。
    ///
    /// 秒数を 1 日の秒数で割らずに暦で数える（夏時間の切り替わる日は 23 時間や 25 時間になるため）。
    /// 月の外の日時を渡されても 1 以上にする（1 日あたりの額の割る数にするため）。
    static func remainingDays(from now: Date, in month: DateInterval, calendar: Calendar) -> Int {
        let start = max(now, month.start)
        guard start < month.end else { return 1 }
        return max(1, LedgerSummary.dayCount(of: DateInterval(start: start, end: month.end), calendar: calendar))
    }
}
