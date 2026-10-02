import Foundation

/// くり返しの記録の、まだ記録していない予定（カレンダーの予定の印と、固定費を先に引く「今日あと」に使う）。
public struct PlannedOccurrence: Hashable, Sendable, Identifiable {
    public let ruleID: String
    public let memo: String
    public let amount: Int
    public let isIncome: Bool
    public let category: EntryCategory
    /// 記録する日時（その日の正午。`RecurringSchedule.date`）。
    public let date: Date
    /// どの月の分か。
    public let month: RecurringMonth

    public var id: String { RecurringSchedule.occurrenceKey(ruleID: ruleID, month: month) }
}

extension RecurringSchedule {
    /// `interval` に入る予定（まだ記録していない決まりの、その月の日）。日の順。
    ///
    /// - 今月より前の月は数えない（過ぎた月は、記録したものが記録として残る。記録しなかった月は、開けばさかのぼって記録する）。
    /// - 記録した月（取り消した月も）は数えない（`RecurringRule.lastRecordedMonth`）。記録したら支出として数えるので、二重に
    ///   数えないため。
    /// - 今月の分は、記録する日を過ぎていてもまだ記録していなければ数える（開いたときに記録するまでの間）。
    /// - 月は西暦で数え（`RecurringMonth`）、画面の暦の月とずれても `interval` に入る日だけを返す。
    public static func plannedOccurrences(
        for rules: [RecurringRule], in interval: DateInterval, now: Date, timeZone: TimeZone
    ) -> [PlannedOccurrence] {
        guard interval.end > interval.start else { return [] }
        let current = RecurringMonth(containing: now, timeZone: timeZone)
        var month = max(RecurringMonth(containing: interval.start, timeZone: timeZone), current)
        let last = RecurringMonth(containing: interval.end.addingTimeInterval(-1), timeZone: timeZone)
        var occurrences: [PlannedOccurrence] = []
        while month <= last {
            for rule in rules where rule.startMonth <= month && (rule.lastRecordedMonth.map { $0 < month } ?? true) {
                guard let date = date(in: month, dayOfMonth: rule.dayOfMonth, timeZone: timeZone),
                      interval.start <= date, date < interval.end
                else { continue }
                occurrences.append(PlannedOccurrence(
                    ruleID: rule.id, memo: rule.memo, amount: rule.amount, isIncome: rule.isIncome,
                    category: rule.category, date: date, month: month
                ))
            }
            month = month.adding(months: 1)
        }
        return occurrences.sorted { ($0.date, $0.ruleID) < ($1.date, $1.ruleID) }
    }
}
