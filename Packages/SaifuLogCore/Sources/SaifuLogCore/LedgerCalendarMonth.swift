import Foundation

/// 月のカレンダー（ホームの 2 枚目のページ）の、日ごとの支出と収入。
///
/// 日の区切りは渡された暦のまま（ホームの今月と同じ画面の暦。週の始まりはその `firstWeekday`）。支出と収入を分けて数えるのは
/// `LedgerSummary` と同じで、収入は支出を減らさない。画面ごとに数え直さず、ここで数える。
public struct LedgerCalendarMonth: Sendable, Hashable {
    /// 1 日分。
    public struct Day: Sendable, Hashable, Identifiable {
        /// その日の始まり。
        public let start: Date
        /// 月の何日か（画面の暦）。
        public let dayOfMonth: Int
        /// 支出の合計。
        public let expense: Int
        /// 収入の合計。
        public let income: Int
        /// 記録の件数（支出と収入）。
        public let recordCount: Int

        public var id: Date { start }
    }

    /// 月（始まりは含み、終わりは含まない）。
    public let month: DateInterval
    /// 月の日（1 日から順に）。
    public let days: [Day]
    /// 1 日の前に置く空きの数。週の始まりの曜日から 1 日の曜日までの日数。
    public let leadingBlankCount: Int

    /// - Parameters:
    ///   - records: 記録。月の外のものは数えない（月より広く渡してよい）。
    ///   - month: 月（`ReportPeriod.month` などで区切ったもの）。
    ///   - calendar: 日を区切る暦（画面の暦）。
    public init<Records: Sequence>(records: Records, month: DateInterval, calendar: Calendar) where Records.Element: LedgerRecord {
        self.month = month
        var totals: [Date: (expense: Int, income: Int, count: Int)] = [:]
        for record in records where month.start <= record.spentAt && record.spentAt < month.end {
            let day = calendar.startOfDay(for: record.spentAt)
            var total = totals[day] ?? (0, 0, 0)
            if record.isIncome {
                total.income += record.amount
            } else {
                total.expense += record.amount
            }
            total.count += 1
            totals[day] = total
        }
        var days: [Day] = []
        var start = calendar.startOfDay(for: month.start)
        while start < month.end {
            let total = totals[start] ?? (0, 0, 0)
            days.append(Day(
                start: start, dayOfMonth: calendar.component(.day, from: start),
                expense: total.expense, income: total.income, recordCount: total.count
            ))
            // 日を足して次の日へ進む（秒数で足さない。夏時間の切り替わる日は 23 時間や 25 時間になるため）。
            guard let next = calendar.date(byAdding: .day, value: 1, to: start), next > start else { break }
            start = calendar.startOfDay(for: next)
        }
        self.days = days
        let firstWeekday = calendar.component(.weekday, from: calendar.startOfDay(for: month.start))
        self.leadingBlankCount = (firstWeekday - calendar.firstWeekday + 7) % 7
    }

    /// 予算の日割り（予算 ÷ 月の日数、切り捨て）。日の印（日割りの目安より多い）に使う。予算を決めていなければ nil。
    public func dailyPace(budget: Int?) -> Int? {
        guard let budget, budget > 0, !days.isEmpty else { return nil }
        return budget / days.count
    }

    /// `date` を含む日。月の外なら nil。
    public func day(containing date: Date, calendar: Calendar) -> Day? {
        let start = calendar.startOfDay(for: date)
        return days.first { $0.start == start }
    }

    /// 月の支出の合計。
    public var expense: Int {
        days.reduce(0) { $0 + $1.expense }
    }

    /// 月の収入の合計。
    public var income: Int {
        days.reduce(0) { $0 + $1.income }
    }
}
