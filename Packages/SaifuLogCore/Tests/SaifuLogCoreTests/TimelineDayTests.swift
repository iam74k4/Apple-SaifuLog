import Foundation
import Testing
@testable import SaifuLogCore

@Suite("タイムラインの日付の見出し")
struct TimelineDayTests {
    @Test("見出しは最初の行の前と、暦の日が前の行から変わる行の前に置く（同じ日の行は 1 つの見出しの下）")
    func headersWhereTheDayChanges() {
        let dates = [
            Fixture.date(2026, 9, 26, hour: 19, minute: 30),
            Fixture.date(2026, 9, 27, hour: 8, minute: 50),
            Fixture.date(2026, 9, 27, hour: 12, minute: 15),
            Fixture.date(2026, 9, 27, hour: 23, minute: 59),
            Fixture.date(2026, 9, 28),
            Fixture.date(2026, 9, 28, hour: 12),
        ]
        #expect(TimelineDay.headerIndices(for: dates, calendar: Fixture.calendar) == [0, 1, 4])
        #expect(TimelineDay.headerIndices(for: [Fixture.now], calendar: Fixture.calendar) == [0])
        #expect(TimelineDay.headerIndices(for: [], calendar: Fixture.calendar).isEmpty)
    }

    @Test("日の区切りは渡された暦の時間帯で決める")
    func headersFollowTheCalendarTimeZone() {
        // 日本時間の 9/27 23:30 と 9/28 0:30（協定世界時ではどちらも 9/27）。
        let dates = [Fixture.date(2026, 9, 27, hour: 23, minute: 30), Fixture.date(2026, 9, 28, minute: 30)]
        #expect(TimelineDay.headerIndices(for: dates, calendar: Fixture.calendar) == [0, 1])
        let utc = Fixture.calendar(firstWeekday: 1, timeZone: "UTC")
        #expect(TimelineDay.headerIndices(for: dates, calendar: utc) == [0])
    }

    @Test("週の始まりは見出しの位置にも言い方にも効かない", arguments: [1, 2, 7])
    func weekStartIsIrrelevant(firstWeekday: Int) {
        let calendar = Fixture.calendar(firstWeekday: firstWeekday)
        // 土曜・日曜・月曜（どの週の始まりでも、どこかで週が替わる）。
        let dates = [
            Fixture.date(2026, 9, 26, hour: 13), Fixture.date(2026, 9, 27, hour: 11), Fixture.date(2026, 9, 27, hour: 15),
            Fixture.date(2026, 9, 28, hour: 9),
        ]
        #expect(TimelineDay.headerIndices(for: dates, calendar: calendar) == [0, 1, 3])
        #expect(TimelineDay.label(for: dates[3], now: Fixture.now, calendar: calendar) == .today)
        #expect(TimelineDay.label(for: dates[1], now: Fixture.now, calendar: calendar) == .yesterday)
        #expect(TimelineDay.label(for: dates[0], now: Fixture.now, calendar: calendar) == .date(includesYear: false))
    }

    @Test("今日・昨日・それより前（今年なら年なし、去年より前なら年つき）。先の日も日付で言う")
    func labels() {
        let calendar = Fixture.calendar
        #expect(TimelineDay.label(for: Fixture.date(2026, 9, 28), now: Fixture.now, calendar: calendar) == .today)
        #expect(TimelineDay.label(for: Fixture.date(2026, 9, 28, hour: 23, minute: 59), now: Fixture.now, calendar: calendar)
            == .today)
        #expect(TimelineDay.label(for: Fixture.date(2026, 9, 27, hour: 8), now: Fixture.now, calendar: calendar) == .yesterday)
        #expect(TimelineDay.label(for: Fixture.date(2026, 9, 26, hour: 23, minute: 59), now: Fixture.now, calendar: calendar)
            == .date(includesYear: false))
        #expect(TimelineDay.label(for: Fixture.date(2026, 1, 1), now: Fixture.now, calendar: calendar)
            == .date(includesYear: false))
        #expect(TimelineDay.label(for: Fixture.date(2025, 12, 31, hour: 20), now: Fixture.now, calendar: calendar)
            == .date(includesYear: true))
        // 時計を戻したときなど、先の日の行。
        #expect(TimelineDay.label(for: Fixture.date(2026, 9, 29, hour: 9), now: Fixture.now, calendar: calendar)
            == .date(includesYear: false))
    }

    @Test("年が替わった直後は、大みそかを昨日と言い、その前の日は年つきの日付")
    func labelsAcrossNewYear() {
        let calendar = Fixture.calendar
        let newYear = Fixture.date(2027, 1, 1, hour: 0, minute: 10)
        #expect(TimelineDay.label(for: Fixture.date(2026, 12, 31, hour: 23, minute: 50), now: newYear, calendar: calendar)
            == .yesterday)
        #expect(TimelineDay.label(for: Fixture.date(2026, 12, 30, hour: 12), now: newYear, calendar: calendar)
            == .date(includesYear: true))
    }

    @Test("昨日は暦の日で数える（夏時間が始まって 1 日が 23 時間の日の翌日も）")
    func yesterdayUsesCalendarDays() {
        // アメリカ東部では 2026/3/8 に夏時間が始まり、その日は 23 時間しかない。
        let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            newYork.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute))!
        }
        let now = date(9, 0, 30)
        #expect(TimelineDay.label(for: date(8, 1), now: now, calendar: newYork) == .yesterday)
        // 24 時間前（3/7 の 23:30）は一昨日。
        #expect(now.timeIntervalSince(date(7, 23, 30)) == 24 * 60 * 60)
        #expect(TimelineDay.label(for: date(7, 23, 30), now: now, calendar: newYork) == .date(includesYear: false))
    }

    @Test("年を添えるかは、渡された暦の年で決める（和暦では元号が替われば別の年）")
    func yearFollowsTheCalendar() {
        let japanese = Fixture.calendar(firstWeekday: 1, identifier: .japanese)
        // 平成 31 年 4 月 30 日と令和元年 5 月 3 日（西暦ではどちらも 2019 年）。
        let heisei = Fixture.date(2019, 4, 30, hour: 12)
        let reiwa = Fixture.date(2019, 5, 3, hour: 12)
        #expect(TimelineDay.label(for: heisei, now: reiwa, calendar: japanese) == .date(includesYear: true))
        #expect(TimelineDay.label(for: heisei, now: reiwa, calendar: Fixture.calendar) == .date(includesYear: false))
    }
}
