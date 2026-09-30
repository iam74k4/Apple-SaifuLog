import Foundation

/// 月のまとめ（⑦）の数字。ある月の支出・収入・収支、1 日あたりの平均、前の月との差、カテゴリ別の内訳、予算の進み。
///
/// 数字はすべてコードで計算する（AI には計算させない）。月の区切りは `ReportPeriod`（ホームの今月と同じ、利用者が
/// 選んだ暦の月）、集計は `LedgerSummary`、予算の進みは `BudgetStatus` を使い、ホームの帯の数字と食い違わせない。
///
/// 決め事:
/// - 1 日あたりの平均は、支出を日数で割って四捨五入する。割る日数は、終わった月はその月の日数、今月は 1 日から
///   今日まで（今日を含む）。今月を月の日数で割ると、月の半ばでは平均が実際の半分ほどに見えるため。予算の 1 日あたりの
///   額（切り捨て）と違って使える上限ではなく、過ぎた日のようすを表す値なので、いちばん近い整数にする。
/// - 平均と日割りの目安との比べに数える支出は、今日の終わりまでの日時の記録だけ（`expenseThroughToday`）。今月には
///   先の日付の記録（払う予定の家賃など）を付けられるので、月の支出まるごとを今日までの日数で割ると、まだ過ぎていない
///   日の支出で平均が上がり、今日までの目安を超えたように見えるため。月の支出と予算の使った額は、ホームの帯と同じく
///   先の日付の記録も含めた月まるごとのまま出す。
/// - 前の月との差は、この月の支出 − 前の月の支出。前の月に支出の記録が 1 件も無ければ出さない（nil）。使い始めた月の
///   翌月に「前月より ¥（その月の支出まるごと）多い」と出ても、比べたことにならないため。収入の記録だけの月も、支出を
///   つけていなかった月とみなす。
/// - 予算の進みは、いまの予算をその額に決めた日時（`BudgetPlan.decidedAt`）を含む月と、それより後の月にだけ出す。
///   予算は月ごとに持たないので、それより前の月の予算がいくらだったかは分からない（いまの額で比べると、違う予算で
///   「超えた」「余った」と出してしまう）。決めた日時が分からなければ今月だけに出す。先の月には出さない。
/// - カテゴリ別の予算の進み（`categoryBudgets`）も、全体の予算と同じ決まりで、カテゴリごとにその予算を決めた日時から
///   当てはめる月を決める。使った額はその月のそのカテゴリの支出（先の日付の記録も含めた月まるごと。全体の予算の使った額と
///   同じ）。支出の無いカテゴリにも、予算があれば ¥0 の進みを出す（予算を決めたカテゴリが行ごと消えると、予算が効いて
///   いないように見えるため）。日割りの目安は全体の予算だけに出す。
/// - 日割りの目安（今日までに使う額の目安）は、今月だけ出す。予算 × 1 日から今日までの日数 ÷ 月の日数（切り捨て）。
///   今日を含めるのは、予算の残りの日数（`BudgetStatus.remainingDays`）が今日を含めているのと合わせるため。
public struct MonthlyReport: Sendable, Hashable {
    /// 月が今日から見て、過ぎた月か・今月か・先の月か。
    public enum Timing: Sendable, Hashable {
        case past
        case current
        case future
    }

    /// その月の集計（期間はその月）。
    public let summary: LedgerSummary
    /// 前の月の集計。
    public let previousSummary: LedgerSummary
    /// 支出のカテゴリ別の内訳。
    public let breakdown: CategoryBreakdown
    /// その月の記録の件数（支出と収入）。0 なら画面は空の状態の案内を出す。
    public let recordCount: Int
    /// 前の月の支出の記録の件数。0 なら前の月との差を出さない。
    public let previousExpenseCount: Int
    public let timing: Timing
    /// この月の支出のうち、今日の終わりまでの日時の記録の合計。1 日あたりの平均と、日割りの目安との比べに使う。
    /// 終わった月は月の支出と同じ、先の月は 0。今月は今日より先の日付の記録を数えない。
    public let expenseThroughToday: Int
    /// 1 日あたりの平均を出すときに割る日数（終わった月はその月の日数、今月は今日まで、先の月は 0）。
    public let averagingDays: Int
    /// 予算の進み。予算が無いか、この月には当てはめない（上の決め事）なら nil。
    public let budget: BudgetStatus?
    /// 今日までの日割りの予算の目安。今月で、予算の進みを出すときだけ。
    public let budgetPace: Int?
    /// カテゴリ別の予算の進み。予算を決めてあり、この月に当てはめる（上の決め事）カテゴリだけ。支出の無いカテゴリも入る。
    ///
    /// カテゴリ別の予算はプレミアムの機能だが、出すかどうか（無料に戻った人に出さない）はアプリが決める（ここでは数えるだけ）。
    public let categoryBudgets: [EntryCategory: BudgetStatus]

    /// `anchor` を含む月のまとめを作る。
    ///
    /// - Parameters:
    ///   - records: その月と前の月の記録（ほかの月の記録が混じっていても数えない）。
    ///   - anchor: まとめる月に入る日時（月の最初の日時など）。
    ///   - now: 今日の日時。今月かどうか、平均の日数、予算の残りの日数の基準。
    ///   - budget: いまの月の全体の予算。nil か 0 以下なら予算なし。
    ///   - budgetDecidedAt: その予算を決めた日時（`BudgetPlan.decidedAt`）。この日時を含む月から後にだけ当てはめる。
    ///   - categoryBudgets: カテゴリ別の予算と、それぞれを決めた日時（`BudgetPlan.categoryDecisions`）。全体の予算と同じく、
    ///     決めた日時を含む月から後にだけ当てはめる。
    ///   - calendar: 月の区切りの暦（ホームと同じ、利用者が選んだ暦）。
    /// - Returns: 暦で月を区切れなければ nil。
    public init?<Records: Sequence>(
        records: Records,
        month anchor: Date,
        now: Date,
        budget: Int? = nil,
        budgetDecidedAt: Date? = nil,
        categoryBudgets: [EntryCategory: BudgetDecision] = [:],
        calendar: Calendar
    ) where Records.Element: LedgerRecord {
        guard let month = ReportPeriod.thisMonth.interval(now: anchor, calendar: calendar),
              let previous = ReportPeriod.lastMonth.interval(now: anchor, calendar: calendar)
        else { return nil }
        // 同じ記録を何度か数えるので、1 度だけ読む（Sequence は 2 度読めるとは限らない）。
        let records = Array(records)
        let summary = LedgerSummary(records: records, interval: month, calendar: calendar)
        let timing: Timing = if now < month.start {
            .future
        } else if now >= month.end {
            .past
        } else {
            .current
        }

        self.summary = summary
        self.previousSummary = LedgerSummary(records: records, interval: previous, calendar: calendar)
        self.breakdown = CategoryBreakdown(summary)
        // 区切りは LedgerSummary と同じ（始まりは含み、終わりは含まない）。
        self.recordCount = records.count(where: { $0.spentAt >= month.start && $0.spentAt < month.end })
        self.previousExpenseCount = records.count(where: {
            !$0.isIncome && $0.spentAt >= previous.start && $0.spentAt < previous.end
        })
        self.timing = timing
        // 月のうち今日の終わり（翌日の 0 時）まで。終わった月は月まるごと、先の月は長さ 0 になる。今日の終わりは暦で
        // 決め、秒数を足さない（夏時間の日があるため）。
        let endOfToday = calendar.dateInterval(of: .day, for: now)?.end ?? now
        let throughToday = DateInterval(start: month.start, end: min(max(endOfToday, month.start), month.end))
        self.expenseThroughToday = LedgerSummary(records: records, interval: throughToday, calendar: calendar).expense
        self.averagingDays = Self.averagingDays(summary: summary, throughToday: throughToday, timing: timing, calendar: calendar)

        let status = Self.applies(decidedAt: budgetDecidedAt, to: month, timing: timing)
            ? BudgetStatus(budget: budget, summary: summary, now: now, calendar: calendar) : nil
        self.budget = status
        self.budgetPace = if let status, timing == .current, summary.dayCount > 0 {
            status.budget * averagingDays / summary.dayCount
        } else {
            nil
        }
        var categoryStatuses: [EntryCategory: BudgetStatus] = [:]
        for (category, decision) in categoryBudgets
        where Self.applies(decidedAt: decision.decidedAt, to: month, timing: timing) {
            // 額が 0 以下なら BudgetStatus が nil を返し、入れない（設定なし）。
            categoryStatuses[category] = BudgetStatus(
                budget: decision.amount, scope: .category(category), summary: summary, now: now, calendar: calendar
            )
        }
        self.categoryBudgets = categoryStatuses
    }

    /// その日時に決めた予算を、この月に当てはめるか（上の決め事）。今月はいつも、過ぎた月は決めた日時がその月の終わりより
    /// 前なら（決めた月も含む）、先の月は当てはめない。決めた日時が分からなければ今月だけ。
    static func applies(decidedAt: Date?, to month: DateInterval, timing: Timing) -> Bool {
        switch timing {
        case .current: true
        case .past: decidedAt.map { $0 < month.end } ?? false
        case .future: false
        }
    }

    /// まとめた月（終わりの時刻は含まない）。
    public var month: DateInterval {
        summary.interval
    }

    public var expense: Int {
        summary.expense
    }

    public var income: Int {
        summary.income
    }

    /// 収入から支出を引いた額。
    public var balance: Int {
        summary.balance
    }

    /// 1 日あたりの平均の支出（四捨五入）。今日の終わりまでの支出を、今日までの日数で割る。割る日数が 0（先の月）なら 0。
    public var dailyAverage: Int {
        guard averagingDays > 0 else { return 0 }
        // 四捨五入の割り算（支出は 0 以上）。
        return (expenseThroughToday * 2 + averagingDays) / (averagingDays * 2)
    }

    /// 前の月の支出との差（この月 − 前の月）。多ければ正、少なければ負。前の月に支出の記録が無ければ nil。
    public var expenseChange: Int? {
        previousExpenseCount > 0 ? expense - previousSummary.expense : nil
    }

    /// 今日までに使った額が、日割りの目安より多い額（目安より少なければ負）。目安を出さないときは nil。
    ///
    /// 予算の使った額（`budget.spent`、月まるごと）ではなく、今日の終わりまでの支出で比べる。今日の目安と、まだ来て
    /// いない日の支出（払う予定の家賃など）を比べないため。予算は全体の予算だけなので、支出の合計で比べてよい。
    public var spentBeyondPace: Int? {
        budgetPace.map { expenseThroughToday - $0 }
    }

    /// カテゴリ別の予算の進みを出すカテゴリのうち、この月に支出の無いもの（カテゴリの定義順。`EntryCategory.areInStandardOrder`）。
    ///
    /// 内訳（`breakdown`）は支出のあるカテゴリだけの行なので、画面はこれを内訳の行の後ろに ¥0 の行として足す。並びを定義順に
    /// 決めておくのは、辞書の並びに任せると開くたびに行の順が入れ替わるため（内訳と同じ理由）。
    public var budgetedCategoriesWithoutExpense: [EntryCategory] {
        categoryBudgets.keys
            .filter { breakdown.item(for: $0) == nil }
            .sorted(by: EntryCategory.areInStandardOrder)
    }

    /// 目安の日数: 終わった月はその月の日数、今月は 1 日から今日まで（今日を含む）、先の月は 0。
    static func averagingDays(summary: LedgerSummary, throughToday: DateInterval, timing: Timing, calendar: Calendar) -> Int {
        switch timing {
        case .past:
            return summary.dayCount
        case .future:
            return 0
        case .current:
            // 暦で数え、秒数で割らない（夏時間の日があるため）。
            return max(1, LedgerSummary.dayCount(of: throughToday, calendar: calendar))
        }
    }
}
