import Foundation

/// 「昨日」「3日前」「9/26」のような日付の言い回しを、何日前かに直す。
///
/// AI には日付の表記を抜き出させるだけにして、日付の計算はここで行う。
/// 端末内のモデルに日数の差を数えさせると間違えることがあるため。
public enum DateExpression {
    /// 日付の表記（「今日」「昨日」「一昨日」「おととい」「3日前」「9/26」「9月26日」「2026/9/26」）が
    /// 何日前か。読めなければ nil。
    public static func daysAgo(in expression: String, now: Date, calendar: Calendar) -> Int? {
        EntryScan(TextNormalizer.normalize(expression), now: now, calendar: calendar).daysAgo
    }

    /// 年を省いた月日が何日前か。今年のその日がまだ来ていなければ去年のこととみなす。
    /// 家計簿に書くのは使ったあとの記録なので、未来の日付は考えない。
    /// 存在しない日付（2/30 など）は nil。
    public static func daysAgo(month: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
        let thisYear = calendar.component(.year, from: calendar.startOfDay(for: now))
        return daysAgo(year: thisYear, month: month, day: day, now: now, calendar: calendar)
            ?? daysAgo(year: thisYear - 1, month: month, day: day, now: now, calendar: calendar)
    }

    /// 年まで書かれた日付（「2026/9/26」）が何日前か。未来の日付と存在しない日付は nil。
    public static func daysAgo(year: Int, month: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let today = calendar.startOfDay(for: now)
        // 2/30 を 3/2 に繰り上げて返すことがあるので、組み立て直した年月日が一致するかで確かめる。
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day,
              date <= today
        else { return nil }
        return calendar.dateComponents([.day], from: date, to: today).day
    }

    /// 何日前かから日時を作る。今日なら `now` そのもの、過去の日なら同じ時刻のその日。
    /// 時刻を残すのは、同じ日の記録を入力した順に並べられるようにするため。
    public static func date(daysAgo: Int, now: Date, calendar: Calendar) -> Date {
        guard daysAgo > 0 else { return now }
        return calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    }
}
