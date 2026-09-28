import Foundation
import Testing
@testable import SaifuLogCore

@Suite("記録の日付を直す")
struct EntryDateEditTests {
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        Fixture.date(year, month, day, hour: hour, minute: minute)
    }

    /// 直していない日付を、変えたことにしない（日付の選択は、同じ日でも時刻の違う日時を返すことがある）。
    @Test("同じ日を選んだら、元の日時のまま")
    func sameDayKeepsOriginal() {
        let original = Self.date(2026, 9, 28, hour: 12, minute: 34)

        #expect(EntryDateEdit.date(on: Self.date(2026, 9, 28), keepingTimeOf: original, calendar: Fixture.calendar) == original)
        #expect(EntryDateEdit.date(on: Self.date(2026, 9, 28, hour: 23, minute: 59), keepingTimeOf: original, calendar: Fixture.calendar)
            == original)
    }

    @Test("別の日を選んだら、時刻は元の記録のまま", arguments: [
        (date(2026, 9, 27), date(2026, 9, 27, hour: 12, minute: 34)),
        (date(2026, 9, 1, hour: 18), date(2026, 9, 1, hour: 12, minute: 34)),
        (date(2026, 8, 31, hour: 23, minute: 59), date(2026, 8, 31, hour: 12, minute: 34)),
        (date(2025, 12, 31), date(2025, 12, 31, hour: 12, minute: 34)),
        (date(2026, 10, 3), date(2026, 10, 3, hour: 12, minute: 34)),
    ])
    func otherDayKeepsTime(day: Date, expected: Date) {
        let original = Self.date(2026, 9, 28, hour: 12, minute: 34)

        #expect(EntryDateEdit.date(on: day, keepingTimeOf: original, calendar: Fixture.calendar) == expected)
    }

    /// 秒数で足すと、夏時間に切り替わる日をまたいだときに時刻が 1 時間ずれる。
    @Test("夏時間の切り替わる日をまたいでも、時刻がずれない")
    func acrossDaylightSavingTime() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ month: Int, _ day: Int, hour: Int) -> Date {
            newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        // 2026-03-08 に夏時間が始まる。
        let original = date(3, 7, hour: 12)

        let moved = EntryDateEdit.date(on: date(3, 9, hour: 0), keepingTimeOf: original, calendar: newYork)

        #expect(moved == date(3, 9, hour: 12))
        #expect(newYork.component(.hour, from: moved) == 12)
    }

    @Test("今日より後の日か（時刻は見ない）", arguments: [
        (date(2026, 9, 28, hour: 23, minute: 59), false),
        (date(2026, 9, 28), false),
        (date(2026, 9, 27, hour: 23, minute: 59), false),
        (date(2026, 9, 29), true),
        (date(2027, 1, 1), true),
    ])
    func afterToday(date: Date, expected: Bool) {
        #expect(EntryDateEdit.isAfterToday(date, now: Fixture.now, calendar: Fixture.calendar) == expected)
    }
}
