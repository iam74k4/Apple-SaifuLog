import Foundation

/// 週の始まり（設定の「週の始まり」）。`ReportPeriod` の今週・先週の区切りに効く。
///
/// 既定は「端末の設定に合わせる」（地域と iOS の設定の週の始まり）。日曜・月曜を選んだときだけ、
/// 暦の `firstWeekday` を置き換える。既定で日曜か月曜のどちらかに決め打ちすると、地域の設定が土曜始まりの
/// 利用者や、iOS の設定で週の始まりを変えた利用者の暦と食い違うため。
///
/// rawValue は設定の保存に使うので変えないこと（変えると、利用者の選んだ週の始まりが既定に戻る）。
public enum WeekStart: String, CaseIterable, Sendable, Identifiable {
    /// 端末の設定（地域と iOS の設定）に合わせる。
    case system
    case sunday
    case monday

    public var id: String { rawValue }

    /// 置き換える `firstWeekday`（1 = 日曜、2 = 月曜）。端末の設定に合わせるなら nil。
    public var firstWeekday: Int? {
        switch self {
        case .system: nil
        case .sunday: 1
        case .monday: 2
        }
    }

    /// `calendar` の週の始まりをこの設定にした暦。端末の設定に合わせるなら、そのまま返す。
    ///
    /// 週の始まりのほか（暦の種類・時間帯・地域・年の最初の週の日数）は変えない。月や年の区切りは週の始まりに
    /// よらないので、ホームやまとめの「今月」は変わらない。
    public func applied(to calendar: Calendar) -> Calendar {
        guard let firstWeekday else { return calendar }
        var calendar = calendar
        calendar.firstWeekday = firstWeekday
        return calendar
    }
}
