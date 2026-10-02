import Foundation

/// 「昨日」「3日前」「9/26」のような日付の言い回しを、何日前かに直す。
///
/// AI には日付の表記を抜き出させるだけにして、日付の計算はここで行う。
/// 端末内のモデルに日数の差を数えさせると間違えることがあるため。
///
/// 何日前かは負の数にもなる（-1 = 明日）。払う予定の家賃のように、少し先の日付で記録することがあるため。
/// 暦は、渡されたものではなくグレゴリオ暦で数える（タイムゾーンだけ渡されたものを使う）。
/// 和暦・仏暦の設定でも「2026/9/26」の 2026 を西暦として読むため。
public enum DateExpression {
    /// 年を省いた月日を、今日から何日先まで未来の日付として読むか。
    static let futureWindow = 60

    /// 日付の表記（「今日」「昨日」「一昨日」「おととい」「3日前」「9/26」「9-26」「9.26」「9月26日」「26日」
    /// 「2026/9/26」「25/9/26」「R7/9/26」「2025年9月26日」「先月25日」「来月1日」「去年10/1」）が何日前か。読めなければ nil。
    ///
    /// AI が返した日付の表記の突き合わせ（`ExtractedEntry`）もここを通る。「先月25日」の入力に AI が「9月25日」を返しても、
    /// 「先月25日」を返しても、同じ日として突き合わせられるようにするため。
    public static func daysAgo(in expression: String, now: Date, calendar: Calendar) -> Int? {
        EntryScan(TextNormalizer.normalize(expression), now: now, calendar: calendar).daysAgo
    }

    /// 年を省いた月日が何日前か。存在しない日付（2/30 など）は nil。
    ///
    /// 今日から 60 日先までは未来の日付として読む（年をまたぐなら来年の日付。12/20 に書いた「1/5」は来年の 1/5）。
    /// それより先の月日は去年のこととみなす（9/28 に書いた「12/31」は去年の 12/31）。
    /// 家計簿に書くのはおおむね使ったあとの記録だが、払う予定の家賃のように少し先の日付で書くこともあるため。
    public static func daysAgo(month: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
        let calendar = calendar.gregorianForParsing
        let thisYear = calendar.component(.year, from: now)
        let candidates = [thisYear + 1, thisYear, thisYear - 1].compactMap {
            daysAgo(year: $0, month: month, day: day, now: now, calendar: calendar)
        }
        // 今日の 60 日先から、1 年前までの 365 日の中に入る年を採る。
        let window = -futureWindow...(364 - futureWindow)
        if let days = candidates.first(where: { window.contains($0) }) { return days }
        // 2/29 のように、その 365 日の中に無い日付は、過去のいちばん近い日にする。
        return candidates.filter { $0 >= 0 }.min()
    }

    /// 日だけ（「26日」）が何日前か。今月のその日として読む（まだ来ていない日でも今月）。
    /// 今月に無い日（9 月の 31 日）は nil。
    public static func daysAgo(day: Int, now: Date, calendar: Calendar) -> Int? {
        let calendar = calendar.gregorianForParsing
        let today = calendar.dateComponents([.year, .month], from: now)
        guard let year = today.year, let month = today.month else { return nil }
        return daysAgo(year: year, month: month, day: day, now: now, calendar: calendar)
    }

    /// 月を語で指した日（「先月25日」「来月1日」）が何日前か。`monthOffset` は今月からずらす月の数（先月は -1、来月は 1）。
    ///
    /// 年を省いた月日と違って 60 日の窓は当てない（月は語が決めているので、先の日付でもその月のまま）。その月に無い日
    /// （9 月の「先月31日」）は nil。
    public static func daysAgo(monthOffset: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
        let calendar = calendar.gregorianForParsing
        let today = calendar.dateComponents([.year, .month], from: now)
        guard let year = today.year, let month = today.month else { return nil }
        let months = year * 12 + (month - 1) + monthOffset
        return daysAgo(year: months / 12, month: months % 12 + 1, day: day, now: now, calendar: calendar)
    }

    /// 年を語で指した月日（「去年10/1」「来年1/5」）が何日前か。`yearOffset` は今年からずらす年の数（去年は -1）。
    /// 60 日の窓は当てない（年は語が決めているため）。その年に無い日は nil。
    public static func daysAgo(yearOffset: Int, month: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
        let calendar = calendar.gregorianForParsing
        let year = calendar.component(.year, from: now) + yearOffset
        return daysAgo(year: year, month: month, day: day, now: now, calendar: calendar)
    }

    /// 年まで書かれた日付（「2026/9/26」）が何日前か。未来の日付は負の数。存在しない日付は nil。
    public static func daysAgo(year: Int, month: Int, day: Int, now: Date, calendar: Calendar) -> Int? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let calendar = calendar.gregorianForParsing
        // 正午で組み立てて日数の差を数える。深夜 0 時に夏時間へ切り替わる地域では、その日の 0 時が存在せず、
        // 0 時で組み立てると 1 日ずれるため。
        // 2/30 を 3/2 に繰り上げて返すことがあるので、組み立て直した年月日が一致するかで確かめる。
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day,
              let todayNoon = calendar.date(
                  from: DateComponents(year: today.year, month: today.month, day: today.day, hour: 12)
              )
        else { return nil }
        return calendar.dateComponents([.day], from: date, to: todayNoon).day
    }

    /// 何日前かから日時を作る。今日なら `now` そのもの、ほかの日なら同じ時刻のその日（負の数は未来の日）。
    /// 時刻を残すのは、同じ日の記録を入力した順に並べられるようにするため。
    public static func date(daysAgo: Int, now: Date, calendar: Calendar) -> Date {
        guard daysAgo != 0 else { return now }
        return calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
    }
}

extension Calendar {
    /// 日付の解析に使う暦。グレゴリオ暦で、タイムゾーンだけ `self` のもの。
    ///
    /// 和暦の設定では「2026/9/26」が 2026 年（令和 2026 年）の未来の日になり、仏暦の設定では 1483 年になる。
    /// 利用者が書く年は西暦なので、暦の設定によらずグレゴリオ暦で数える。
    var gregorianForParsing: Calendar {
        guard identifier != .gregorian else { return self }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        return gregorian
    }
}
