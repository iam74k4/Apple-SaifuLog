import Foundation

/// 記録の日付を直すときの日時の決め方。
///
/// 直すシートでは日付だけを選ばせ、時刻は元の記録のものを残す。日付の選択が返す時刻は、選んだときの時刻や
/// 0 時になることがあり、そのまま使うと、同じ日のうちの並びや「今日」の読み上げが、直していない時刻の分だけ変わるため。
public enum EntryDateEdit {
    /// `day` の日で、時刻は `original` のままの日時。同じ日を選んだときは `original` をそのまま返す（直していない日付を
    /// 変えたことにしないため）。
    ///
    /// 日は暦で数えて足す（秒数で足さない）。夏時間の切り替わる日をまたいでも、時刻が 1 時間ずれないようにするため
    /// （ひとこと入力の「昨日」と同じ数え方。`DateExpression.date(daysAgo:now:calendar:)`）。
    public static func date(on day: Date, keepingTimeOf original: Date, calendar: Calendar) -> Date {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: original), to: calendar.startOfDay(for: day)
        ).day ?? 0
        guard days != 0 else { return original }
        return DateExpression.date(daysAgo: -days, now: original, calendar: calendar)
    }

    /// 今日より後の日か。直すシートで、先の日付を選んだときに注意を出すかに使う（保存は止めない。
    /// 払う予定の家賃のように、先の日付で記録することがあるため。docs/design.md §4-4 のひとこと入力と同じ）。
    public static func isAfterToday(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        calendar.compare(date, to: now, toGranularity: .day) == .orderedDescending
    }
}
