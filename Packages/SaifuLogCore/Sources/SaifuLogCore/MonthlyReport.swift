import Foundation

/// 月のまとめ（⑦）の数字。ある月の支出・収入・収支、前の月との差、カテゴリ別の内訳、予算の進み。
///
/// 数字はすべてコードで計算する（AI には計算させない）。月の区切りは `ReportPeriod`（ホームの今月と同じ、利用者が
/// 選んだ暦の月）、集計は `LedgerSummary`、予算の進みは `BudgetStatus` を使い、ホームの帯の数字と食い違わせない。
///
/// 決め事:
/// - 前の月との差は、この月の支出 − 前の月の支出。終わった月だけに出す（今月は途中までの支出を前の月まるごとと比べる
///   ことになり、月の初めはいつも「少ない」と出るため。今月の比べは、前の月の同じ日までと比べる家計への質問にまかせる）。
///   前の月に支出の記録が 1 件も無ければ出さない（nil）。使い始めた月の翌月に「前月より ¥（その月の支出まるごと）多い」と
///   出ても、比べたことにならないため。収入の記録だけの月も、支出をつけていなかった月とみなす。
/// - 予算の進みは、いまの予算をその額に決めた日時（`BudgetPlan.decidedAt`）を含む月と、それより後の月にだけ出す。
///   予算は月ごとに持たないので、それより前の月の予算がいくらだったかは分からない（いまの額で比べると、違う予算で
///   「超えた」「余った」と出してしまう）。決めた日時が分からなければ今月だけに出す。先の月には出さない。
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
    /// 予算の進み。予算が無いか、この月には当てはめない（上の決め事）なら nil。
    public let budget: BudgetStatus?

    /// `anchor` を含む月のまとめを作る。
    ///
    /// - Parameters:
    ///   - records: その月と前の月の記録（ほかの月の記録が混じっていても数えない）。
    ///   - anchor: まとめる月に入る日時（月の最初の日時など）。
    ///   - now: 今日の日時。今月かどうかと、予算の残りの日数の基準。
    ///   - budget: いまの月の全体の予算。nil か 0 以下なら予算なし。
    ///   - budgetDecidedAt: その予算を決めた日時（`BudgetPlan.decidedAt`）。この日時を含む月から後にだけ当てはめる。
    ///   - calendar: 月の区切りの暦（ホームと同じ、利用者が選んだ暦）。
    /// - Returns: 暦で月を区切れなければ nil。
    public init?<Records: Sequence>(
        records: Records,
        month anchor: Date,
        now: Date,
        budget: Int? = nil,
        budgetDecidedAt: Date? = nil,
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
        self.budget = Self.applies(decidedAt: budgetDecidedAt, to: month, timing: timing)
            ? BudgetStatus(budget: budget, summary: summary, now: now, calendar: calendar) : nil
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

    /// 前の月の支出との差（この月 − 前の月）。多ければ正、少なければ負。終わった月でないか、前の月に支出の記録が無ければ nil。
    public var expenseChange: Int? {
        timing == .past && previousExpenseCount > 0 ? expense - previousSummary.expense : nil
    }
}
