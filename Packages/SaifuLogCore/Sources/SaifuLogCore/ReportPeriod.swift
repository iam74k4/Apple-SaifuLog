import Foundation

/// 集計の期間（今日・今週・先月・ある月など）。月のまとめ・質問・週のふりかえりで同じ区切りを使う。
///
/// 区切りは暦で決め、秒数で数えない。夏時間の切り替わる日は 23 時間や 25 時間になり、
/// 「24 時間前」や「7 日分の秒数」で数えると日の境目がずれるため。
///
/// - 今日・今週・今月・今年などの相対的な期間は、渡された暦（ホームと同じ、利用者が iOS で選んだ暦）のまま区切る。
///   ホームの「今月」（`MonthlySummary`・`Entry.monthDescriptor`）もここの `thisMonth` で区切る。
///   西暦に置き換えてから区切ると、イスラム暦・ヘブライ暦・ペルシア暦・中国暦のように月の区切りが西暦と違う暦では、
///   まとめや質問の「今月」がホームの「今月」と別の期間になり、画面の数字と AI に渡す数字が食い違うため。
/// - 週の始まりは、渡された暦の `firstWeekday`（地域と iOS の設定で日曜か月曜かが変わる）に従う。
/// - 時間帯も、渡された暦の `timeZone` に従う。
/// - 西暦で読むのは `month(year:month:)` の年と月だけ（入力の日付の読み取りと同じ方針）。和暦の暦に西暦の年を
///   そのまま渡すと、令和 2026 年（西暦 4044 年）になってしまうため。区切りも西暦の月にする（西暦の年月を
///   指したものなので）。
public enum ReportPeriod: Hashable, Sendable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case thisYear
    /// 西暦の `year` 年 `month` 月（1〜12）。
    case month(year: Int, month: Int)

    /// `now` を基準にした期間。終わりの時刻は含まない（次の期間の始まり）。
    ///
    /// 成り立たない月（`month(year:month:)` の month が 1〜12 の外）は nil。黙って翌年や前年の月に
    /// 読み替えると、違う月の合計を出してしまうため。
    public func interval(now: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .yesterday:
            return Self.previous(.day, before: now, calendar: calendar)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .lastWeek:
            return Self.previous(.weekOfYear, before: now, calendar: calendar)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .lastMonth:
            return Self.previous(.month, before: now, calendar: calendar)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)
        case .month(let year, let month):
            let gregorian = Self.gregorian(like: calendar)
            guard (1...12).contains(month),
                  let firstDay = gregorian.date(from: DateComponents(year: year, month: month, day: 1))
            else { return nil }
            return gregorian.dateInterval(of: .month, for: firstDay)
        }
    }

    /// `now` を含む期間の 1 つ前の期間。
    ///
    /// 今の期間の始まりの直前（1 秒前）を含む期間を取る。「1 日前」「1 か月前」を足し引きすると、
    /// 夏時間でその時刻が無い日や、3 月 31 日の 1 か月前（2 月 31 日）のような日で丸めが入るため。
    private static func previous(_ component: Calendar.Component, before now: Date, calendar: Calendar) -> DateInterval? {
        guard let current = calendar.dateInterval(of: component, for: now) else { return nil }
        return calendar.dateInterval(of: component, for: current.start.addingTimeInterval(-1))
    }

    /// 渡された暦の時間帯・週の始まり・地域を引き継いだ西暦の暦。
    static func gregorian(like calendar: Calendar) -> Calendar {
        if calendar.identifier == .gregorian { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        // 週の始まりは地域の既定ではなく、渡された暦の値（iOS の設定で変えたものを含む）を写す。
        gregorian.locale = calendar.locale
        gregorian.timeZone = calendar.timeZone
        gregorian.firstWeekday = calendar.firstWeekday
        gregorian.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        return gregorian
    }
}
