import Foundation
@testable import SaifuLogCore

/// テストで使う固定の日時と暦。「昨日」「9/26」の解釈を実行日に左右されないようにする。
enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 2026-09-28 12:00（日本時間）。
    static let now: Date = date(2026, 9, 28, hour: 12)

    static let parser = RuleBasedParser(calendar: calendar, now: { Fixture.now })

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
