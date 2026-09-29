import Foundation

/// 月の予算の目安の提案（先週のふりかえりのカードに出す）。直近の月の支出の中央値を 1,000 円単位に丸めた額。
///
/// 表示するだけで、予算は変えない（決めるのは利用者が「予算を決める」の画面で保存したときだけ）。数字はコードで計算する
/// （AI には計算させない）。月の区切りは `ReportPeriod`（ホームの今月と同じ、利用者が選んだ暦の月）、集計は `LedgerSummary`。
///
/// 決め事:
/// - 元にするのは、今月の前の 3 か月（先月・2 か月前・3 か月前）のうち、支出の記録がある月だけ。今月は途中なので使わない。
///   記録の無い月（つけ忘れた月）を 0 円の月として数えると、目安が実際より低く出るため。
/// - 記録を始めた月（いちばん古い記録の月）は、その月の 1 日から記録していなければ使わない。途中から付け始めた月の支出は、
///   1 か月分より少なく出るため。使える月が 1 つも無い（記録が 1 か月分に満たない）ときは提案しない。
/// - 中央値にするのは、旅行や家電のように 1 か月だけ大きい月があっても、目安が引っ張られないようにするため。月が 2 つなら
///   2 つの平均。1,000 円単位に四捨五入する（予算は細かい額で決めるものではないため）。0 円になれば提案しない。
/// - いま予算がある人には、目安といまの予算の差が大きいとき（予算の 2 割以上）だけ出す（`differsNotably(from:)`）。
///   わずかな差で毎週「予算を変えては」と出すと、うるさいため。
public struct BudgetSuggestion: Sendable, Hashable {
    /// 丸める単位（円）。
    public static let roundingUnit = 1_000
    /// さかのぼる月の数（今月を除く）。
    public static let monthsToLookBack = 3

    /// 提案する月の予算（円。1,000 円単位）。
    public let amount: Int
    /// 元にした月の支出（新しい月から）。
    public let monthlyExpenses: [Int]

    /// 元にした月の数（1〜3）。
    public var monthCount: Int {
        monthlyExpenses.count
    }

    /// - Parameters:
    ///   - records: 今月の前の 3 か月の記録（ほかの期間の記録が混じっていても数えない）。
    ///   - recordingStartedAt: 使った日時のいちばん古い記録の日時（`records` の外の記録も含めて）。nil なら `records` の中で
    ///     いちばん古いもの。
    ///   - now: 今日の日時。今月とその前の月の基準。
    ///   - calendar: 月の区切りの暦。
    /// - Returns: 使える月が無いか、目安が 0 円なら nil。
    public init?<Records: Sequence>(
        records: Records, recordingStartedAt: Date? = nil, now: Date, calendar: Calendar
    ) where Records.Element: LedgerRecord {
        let records = Array(records)
        guard let startedAt = recordingStartedAt ?? records.map(\.spentAt).min(),
              var month = ReportPeriod.thisMonth.interval(now: now, calendar: calendar)
        else { return nil }

        var expenses: [Int] = []
        for _ in 0..<Self.monthsToLookBack {
            guard let previous = ReportPeriod.lastMonth.interval(now: month.start, calendar: calendar) else { break }
            month = previous
            // 月の 1 日の終わりより後に記録を始めた月は、途中からなので使わない（それより前の月も記録が無いので、ここで終える）。
            guard let firstDay = calendar.dateInterval(of: .day, for: month.start), startedAt < firstDay.end else { break }
            let summary = LedgerSummary(records: records, interval: month, calendar: calendar)
            if summary.expenseCount > 0 {
                expenses.append(summary.expense)
            }
        }
        guard let amount = Self.roundedMedian(of: expenses), amount > 0 else { return nil }
        self.amount = amount
        self.monthlyExpenses = expenses
    }

    /// いまの予算との差が大きい（予算の 2 割以上）か。いま予算がある人には、このときだけ提案を出す。
    public func differsNotably(from budget: Int) -> Bool {
        guard budget > 0 else { return true }
        return abs(amount - budget) * 5 >= budget
    }

    /// 中央値を 1,000 円単位に四捨五入した額。値が無ければ nil。
    ///
    /// 中央値の 2 倍（奇数個なら真ん中の 2 倍、偶数個なら真ん中の 2 つの和）で丸め、平均の端数の切り捨てで 500 円の境目が
    /// ずれないようにする。予算の上限（`BudgetPlan.maximumAmount`）を超えるなら、上限以下の 1,000 円単位にする。
    static func roundedMedian(of values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        let twice = sorted.count.isMultiple(of: 2) ? sorted[middle - 1] + sorted[middle] : sorted[middle] * 2
        let unit = roundingUnit
        let rounded = (twice + unit) / (2 * unit) * unit
        return min(rounded, BudgetPlan.maximumAmount / unit * unit)
    }
}
