import Foundation
@testable import SaifuLogCore

/// テストで使う固定の日時と暦。「昨日」「9/26」の解釈を実行日に左右されないようにする。
enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-09-28 12:00（日本時間）。月曜日。
    static let now: Date = date(2026, 9, 28, hour: 12)

    static let parser = RuleBasedParser(calendar: calendar, now: { Fixture.now })

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 週の始まり（1 = 日曜、2 = 月曜）と暦の種類・時間帯を変えた暦。
    /// 週の始まりは地域と iOS の設定で変わるので、実行する Mac の設定に左右されないよう決めて渡す。
    static func calendar(
        firstWeekday: Int, identifier: Calendar.Identifier = .gregorian, timeZone: String = "Asia/Tokyo"
    ) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }
}

/// 集計のテストで使う記録。
struct TestRecord: LedgerRecord {
    var amount: Int
    var isIncome = false
    var category: EntryCategory = .other
    var spentAt: Date
}
