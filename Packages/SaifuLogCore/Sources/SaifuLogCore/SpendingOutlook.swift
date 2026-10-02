import Foundation

/// 今月の見通し（カレンダーのページの「今日あと」の欄）。数字はコードで計算する（AI には計算させない）。
///
/// 決め事（docs/design.md §9 の ⑩ カレンダーの決め事）:
/// - 支出だけを数える。収入は予算の支出を減らさない（`BudgetStatus` と同じ）。
/// - 固定費は、くり返しの記録の支出のうち、今月まだ記録していないもの（`RecurringSchedule.plannedOccurrences`）。記録したら
///   支出として数えるので、二重に数えない。先の日付で記録した支出（「27日 家賃」）も、まだ使っていないが使う予定の額として
///   同じく先に引く。
/// - 今日あと = （予算 − 昨日までの支出 − 先の日付の支出 − まだ記録していない固定費）÷ 今日を含む残りの日数（切り捨て）
///   − 今日の支出。今日の支出を割る前に引かないのは、今日使った分だけ「今日あと」がそのまま減るようにするため（ホームの
///   「1日あたり」は今日の支出も月の残りに含めて割るので、今日使っても少ししか動かない）。
/// - 月末の見込み = くり返し以外の支出の、今日までの 1 日あたりのペース × 月の日数 ＋ 先の日付の支出 ＋ 固定費（記録したものと
///   まだのもの）。月の初めは数日の支出で大きく振れるので、今日が `projectionMinimumDay` 日目より前なら出さない。
public struct SpendingOutlook: Sendable, Hashable {
    /// 月末の見込みを出し始める日（月の何日目か）。
    public static let projectionMinimumDay = 7

    /// 見通しに使う記録の値（記録のモデルに依存しないように、値だけを渡す）。
    public struct Record: Sendable, Hashable {
        public var amount: Int
        public var isIncome: Bool
        public var spentAt: Date
        /// くり返しの記録から記録したものか（固定費として、ペースの計算から外す）。
        public var isRecurring: Bool

        public init(amount: Int, isIncome: Bool, spentAt: Date, isRecurring: Bool) {
            self.amount = amount
            self.isIncome = isIncome
            self.spentAt = spentAt
            self.isRecurring = isRecurring
        }
    }

    /// 月の全体の予算。決めていなければ nil。
    public let budget: Int?
    /// 月の初めから昨日までの支出。
    public let spentBeforeToday: Int
    /// 今日の支出。
    public let spentToday: Int
    /// 明日より後の日付で記録した、今月の支出（使う予定の額）。
    public let spentLater: Int
    /// まだ記録していない、今月のくり返しの記録の支出（日の順）。
    public let plannedFixed: [PlannedOccurrence]
    /// 今日を含む、月の終わりまでの日数。
    public let remainingDays: Int
    /// 月末の見込み。月の初め（`projectionMinimumDay` 日目より前）は nil。
    public let projection: Int?

    /// - Parameters:
    ///   - budget: 月の全体の予算。nil か 0 以下なら決めていないとみなす。
    ///   - records: 記録（月の外のものは数えない）。
    ///   - rules: くり返しの記録の決まり（収入の決まりは数えない）。
    ///   - now: 今の日時。`month` に入っていなければ nil を返す（見通しは今月だけ）。
    ///   - month: 今月（`ReportPeriod.thisMonth`）。
    ///   - calendar: 日を区切る暦（画面の暦）。
    public init?(
        budget: Int?, records: [Record], rules: [RecurringRule], now: Date, month: DateInterval, calendar: Calendar
    ) {
        guard month.start <= now, now < month.end else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else { return nil }
        self.budget = budget.flatMap { $0 > 0 ? $0 : nil }

        var spentBeforeToday = 0
        var spentToday = 0
        var spentLater = 0
        var variableThroughToday = 0
        var recurringRecorded = 0
        for record in records where !record.isIncome && month.start <= record.spentAt && record.spentAt < month.end {
            if record.spentAt < startOfToday {
                spentBeforeToday += record.amount
            } else if record.spentAt < startOfTomorrow {
                spentToday += record.amount
            } else {
                spentLater += record.amount
            }
            if record.isRecurring {
                recurringRecorded += record.amount
            } else if record.spentAt < startOfTomorrow {
                variableThroughToday += record.amount
            }
        }
        self.spentBeforeToday = spentBeforeToday
        self.spentToday = spentToday
        self.spentLater = spentLater
        let plannedFixed = RecurringSchedule.plannedOccurrences(
            for: rules.filter { !$0.isIncome }, in: month, now: now, timeZone: calendar.timeZone
        )
        self.plannedFixed = plannedFixed
        self.remainingDays = BudgetStatus.remainingDays(from: now, in: month, calendar: calendar)

        let dayOfMonth = LedgerSummary.dayCount(of: DateInterval(start: month.start, end: startOfTomorrow), calendar: calendar)
        let daysInMonth = LedgerSummary.dayCount(of: month, calendar: calendar)
        if dayOfMonth >= Self.projectionMinimumDay, dayOfMonth > 0 {
            let plannedTotal = plannedFixed.reduce(0) { $0 + $1.amount }
            // くり返しの記録で記録した先の日付の支出は、固定費としてすでに数えたので、先の日付の支出から外して足す。
            let laterVariable = records.filter {
                !$0.isIncome && !$0.isRecurring && startOfTomorrow <= $0.spentAt && $0.spentAt < month.end
            }.reduce(0) { $0 + $1.amount }
            projection = variableThroughToday * daysInMonth / dayOfMonth + laterVariable + recurringRecorded + plannedTotal
        } else {
            projection = nil
        }
    }

    /// まだ記録していない固定費の合計。
    public var plannedFixedTotal: Int {
        plannedFixed.reduce(0) { $0 + $1.amount }
    }

    /// 今月の支出（昨日まで・今日・先の日付の合計）。
    public var spent: Int {
        spentBeforeToday + spentToday + spentLater
    }

    /// 固定費を引いた今月あと（予算 − 今月の支出 − まだ記録していない固定費）。超えていれば負。予算が無ければ nil。
    public var freeToSpend: Int? {
        budget.map { $0 - spent - plannedFixedTotal }
    }

    /// 今日使える額（今日の支出を引く前）。残りが無ければ 0。予算が無ければ nil。
    public var todayAllowance: Int? {
        budget.map { max(0, $0 - spentBeforeToday - spentLater - plannedFixedTotal) / remainingDays }
    }

    /// 今日あと（今日使える額 − 今日の支出）。負なら、今日の目安を超えた額。予算が無ければ nil。
    public var todayLeft: Int? {
        todayAllowance.map { $0 - spentToday }
    }

    /// 月末の見込みと予算の差（見込み − 予算。正なら超える見込み）。見込みか予算が無ければ nil。
    public var projectedOverBudget: Int? {
        guard let projection, let budget else { return nil }
        return projection - budget
    }
}
