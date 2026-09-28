import Foundation
import Testing
@testable import SaifuLogCore

@Suite("集計の期間")
struct ReportPeriodTests {
    static let sundayFirst = Fixture.calendar(firstWeekday: 1)
    static let mondayFirst = Fixture.calendar(firstWeekday: 2)

    static func span(_ start: Date, _ end: Date) -> DateInterval {
        DateInterval(start: start, end: end)
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        Fixture.date(year, month, day, hour: hour, minute: minute)
    }

    @Test("今日と昨日は、0 時から翌日の 0 時まで")
    func days() {
        #expect(ReportPeriod.today.interval(now: Fixture.now, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 9, 28), Self.date(2026, 9, 29)))
        #expect(ReportPeriod.yesterday.interval(now: Fixture.now, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 9, 27), Self.date(2026, 9, 28)))
    }

    // 2026-09-28 は月曜日。
    @Test("日曜始まりの暦では、週は日曜から")
    func weeksStartingSunday() {
        #expect(ReportPeriod.thisWeek.interval(now: Fixture.now, calendar: Self.sundayFirst)
            == Self.span(Self.date(2026, 9, 27), Self.date(2026, 10, 4)))
        #expect(ReportPeriod.lastWeek.interval(now: Fixture.now, calendar: Self.sundayFirst)
            == Self.span(Self.date(2026, 9, 20), Self.date(2026, 9, 27)))
    }

    @Test("月曜始まりの暦では、週は月曜から")
    func weeksStartingMonday() {
        #expect(ReportPeriod.thisWeek.interval(now: Fixture.now, calendar: Self.mondayFirst)
            == Self.span(Self.date(2026, 9, 28), Self.date(2026, 10, 5)))
        #expect(ReportPeriod.lastWeek.interval(now: Fixture.now, calendar: Self.mondayFirst)
            == Self.span(Self.date(2026, 9, 21), Self.date(2026, 9, 28)))
    }

    @Test("日曜は、日曜始まりなら週の最初の日、月曜始まりなら週の最後の日")
    func sundayBelongsToDifferentWeeks() {
        let sunday = Self.date(2026, 9, 27, hour: 12)

        #expect(ReportPeriod.thisWeek.interval(now: sunday, calendar: Self.sundayFirst)
            == Self.span(Self.date(2026, 9, 27), Self.date(2026, 10, 4)))
        #expect(ReportPeriod.lastWeek.interval(now: sunday, calendar: Self.sundayFirst)
            == Self.span(Self.date(2026, 9, 20), Self.date(2026, 9, 27)))
        #expect(ReportPeriod.thisWeek.interval(now: sunday, calendar: Self.mondayFirst)
            == Self.span(Self.date(2026, 9, 21), Self.date(2026, 9, 28)))
        #expect(ReportPeriod.lastWeek.interval(now: sunday, calendar: Self.mondayFirst)
            == Self.span(Self.date(2026, 9, 14), Self.date(2026, 9, 21)))
    }

    @Test("今月・先月・今年")
    func monthsAndYear() {
        #expect(ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 9, 1), Self.date(2026, 10, 1)))
        #expect(ReportPeriod.lastMonth.interval(now: Fixture.now, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 8, 1), Self.date(2026, 9, 1)))
        #expect(ReportPeriod.thisYear.interval(now: Fixture.now, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 1, 1), Self.date(2027, 1, 1)))
    }

    /// 3 月 31 日の「1 か月前」は 2 月 31 日で、足し引きで求めると丸めが入る。先月は今月の始まりの直前から取る。
    @Test("月末の 23:59 は今月、翌月 1 日の 0:00 は翌月（先月は 2 月の日数どおり）")
    func monthEnd() {
        let march31 = Self.date(2026, 3, 31, hour: 23, minute: 59)
        #expect(ReportPeriod.thisMonth.interval(now: march31, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 3, 1), Self.date(2026, 4, 1)))
        #expect(ReportPeriod.lastMonth.interval(now: march31, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 2, 1), Self.date(2026, 3, 1)))

        let april1 = Self.date(2026, 4, 1)
        #expect(ReportPeriod.thisMonth.interval(now: april1, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 4, 1), Self.date(2026, 5, 1)))
        #expect(ReportPeriod.lastMonth.interval(now: april1, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 3, 1), Self.date(2026, 4, 1)))
        #expect(ReportPeriod.yesterday.interval(now: april1, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 3, 31), Self.date(2026, 4, 1)))

        // うるう年の 2 月は 29 日まで。
        let leapMarch31 = Self.date(2028, 3, 31, hour: 12)
        #expect(ReportPeriod.lastMonth.interval(now: leapMarch31, calendar: Fixture.calendar)
            == Self.span(Self.date(2028, 2, 1), Self.date(2028, 3, 1)))
    }

    @Test("年末の 23:59 は今年、元日の 0:00 は翌年")
    func yearEnd() {
        let newYearsEve = Self.date(2026, 12, 31, hour: 23, minute: 59)
        #expect(ReportPeriod.today.interval(now: newYearsEve, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 12, 31), Self.date(2027, 1, 1)))
        #expect(ReportPeriod.thisMonth.interval(now: newYearsEve, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 12, 1), Self.date(2027, 1, 1)))
        #expect(ReportPeriod.thisYear.interval(now: newYearsEve, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 1, 1), Self.date(2027, 1, 1)))

        let newYearsDay = Self.date(2027, 1, 1)
        #expect(ReportPeriod.yesterday.interval(now: newYearsDay, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 12, 31), Self.date(2027, 1, 1)))
        #expect(ReportPeriod.lastMonth.interval(now: newYearsDay, calendar: Fixture.calendar)
            == Self.span(Self.date(2026, 12, 1), Self.date(2027, 1, 1)))
        #expect(ReportPeriod.thisYear.interval(now: newYearsDay, calendar: Fixture.calendar)
            == Self.span(Self.date(2027, 1, 1), Self.date(2028, 1, 1)))
    }

    /// 2027-01-01 は金曜日。週は年をまたいでも 7 日のまま。
    @Test("年をまたぐ週")
    func weekAcrossYears() {
        let newYearsDay = Self.date(2027, 1, 1, hour: 9)

        #expect(ReportPeriod.thisWeek.interval(now: newYearsDay, calendar: Self.mondayFirst)
            == Self.span(Self.date(2026, 12, 28), Self.date(2027, 1, 4)))
        #expect(ReportPeriod.lastWeek.interval(now: newYearsDay, calendar: Self.mondayFirst)
            == Self.span(Self.date(2026, 12, 21), Self.date(2026, 12, 28)))
        #expect(ReportPeriod.thisWeek.interval(now: newYearsDay, calendar: Self.sundayFirst)
            == Self.span(Self.date(2026, 12, 27), Self.date(2027, 1, 3)))
    }

    @Test("西暦の年と月を指定した月", arguments: [
        (2026, 9, Fixture.date(2026, 9, 1), Fixture.date(2026, 10, 1)),
        (2026, 2, Fixture.date(2026, 2, 1), Fixture.date(2026, 3, 1)),
        (2028, 2, Fixture.date(2028, 2, 1), Fixture.date(2028, 3, 1)),
        (2026, 12, Fixture.date(2026, 12, 1), Fixture.date(2027, 1, 1)),
        (2026, 1, Fixture.date(2026, 1, 1), Fixture.date(2026, 2, 1)),
    ])
    func specificMonth(year: Int, month: Int, start: Date, end: Date) {
        #expect(ReportPeriod.month(year: year, month: month).interval(now: Fixture.now, calendar: Fixture.calendar)
            == Self.span(start, end))
    }

    /// 13 月を翌年の 1 月に読み替えると、違う月の合計を出してしまう。
    @Test("1〜12 の外の月は期間にしない", arguments: [0, 13, -1])
    func invalidMonth(month: Int) {
        #expect(ReportPeriod.month(year: 2026, month: month).interval(now: Fixture.now, calendar: Fixture.calendar) == nil)
    }

    @Test("和暦の設定でも、年月は西暦で数え、週の始まりと時間帯は引き継ぐ")
    func japaneseCalendar() {
        let japanese = Fixture.calendar(firstWeekday: 2, identifier: .japanese)

        #expect(ReportPeriod.month(year: 2026, month: 9).interval(now: Fixture.now, calendar: japanese)
            == Self.span(Self.date(2026, 9, 1), Self.date(2026, 10, 1)))
        #expect(ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: japanese)
            == Self.span(Self.date(2026, 9, 1), Self.date(2026, 10, 1)))
        #expect(ReportPeriod.thisWeek.interval(now: Fixture.now, calendar: japanese)
            == Self.span(Self.date(2026, 9, 28), Self.date(2026, 10, 5)))
    }

    /// 和暦の暦に西暦の年をそのまま渡すと、和暦の年（令和 2026 年 = 西暦 4044 年）として読まれる。
    @Test("和暦の設定でも、指定した年は西暦として読む")
    func japaneseCalendarReadsGregorianYear() throws {
        let japanese = Fixture.calendar(firstWeekday: 1, identifier: .japanese)

        // 和暦の暦のままだと西暦の年にならないことの確かめ（下の期待の裏づけ）。
        let eraYear = try #require(japanese.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        #expect(Fixture.calendar.component(.year, from: eraYear) == 4044)

        #expect(ReportPeriod.month(year: 2026, month: 9).interval(now: Fixture.now, calendar: japanese)
            == Self.span(Self.date(2026, 9, 1), Self.date(2026, 10, 1)))
        #expect(ReportPeriod.thisYear.interval(now: Fixture.now, calendar: japanese)
            == Self.span(Self.date(2026, 1, 1), Self.date(2027, 1, 1)))
    }

    /// 2019 年は 4 月 30 日までが平成、5 月 1 日からが令和。年の区切りは元号で分かれず、西暦の 1 年のまま。
    @Test("和暦で元号が変わった年も、今年は 1 月 1 日から翌年の 1 月 1 日まで")
    func japaneseEraChangeYear() {
        let japanese = Fixture.calendar(firstWeekday: 1, identifier: .japanese)

        #expect(ReportPeriod.thisYear.interval(now: Self.date(2019, 6, 1, hour: 12), calendar: japanese)
            == Self.span(Self.date(2019, 1, 1), Self.date(2020, 1, 1)))
        #expect(ReportPeriod.thisMonth.interval(now: Self.date(2019, 5, 1, hour: 12), calendar: japanese)
            == Self.span(Self.date(2019, 5, 1), Self.date(2019, 6, 1)))
    }

    /// 西暦に置き換えて区切ると、ホームの「今月」（渡された暦で区切る）と別の期間になってしまう。
    @Test("月の区切りが西暦と違う暦では、相対的な期間はその暦のまま区切る", arguments: [
        Calendar.Identifier.islamicUmmAlQura, .hebrew, .persian, .chinese,
    ])
    func nonGregorianCalendar(identifier: Calendar.Identifier) throws {
        let calendar = Fixture.calendar(firstWeekday: 1, identifier: identifier)
        let gregorianSeptember = Self.span(Self.date(2026, 9, 1), Self.date(2026, 10, 1))

        let thisMonth = try #require(ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: calendar))
        #expect(thisMonth == calendar.dateInterval(of: .month, for: Fixture.now))
        #expect(thisMonth != gregorianSeptember)
        #expect(ReportPeriod.lastMonth.interval(now: Fixture.now, calendar: calendar)
            == calendar.dateInterval(of: .month, for: thisMonth.start.addingTimeInterval(-1)))
        #expect(ReportPeriod.thisYear.interval(now: Fixture.now, calendar: calendar)
            == calendar.dateInterval(of: .year, for: Fixture.now))
        // 日と週は西暦と同じ区切り。
        #expect(ReportPeriod.today.interval(now: Fixture.now, calendar: calendar)
            == Self.span(Self.date(2026, 9, 28), Self.date(2026, 9, 29)))
        #expect(ReportPeriod.thisWeek.interval(now: Fixture.now, calendar: calendar)
            == Self.span(Self.date(2026, 9, 27), Self.date(2026, 10, 4)))
        // 西暦の年月を指したものは、西暦の月のまま。
        #expect(ReportPeriod.month(year: 2026, month: 9).interval(now: Fixture.now, calendar: calendar)
            == gregorianSeptember)
    }

    /// イスラム暦（ウンム・アル＝クラー）では、2026-09-28 を含む月は 9/12〜10/12（日本時間）。
    @Test("イスラム暦の今月")
    func islamicThisMonth() {
        let islamic = Fixture.calendar(firstWeekday: 1, identifier: .islamicUmmAlQura)

        #expect(ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: islamic)
            == Self.span(Self.date(2026, 9, 12), Self.date(2026, 10, 12)))
    }

    /// ニューヨークでは 2026-03-08 に 1 時間進み（23 時間の日）、11-01 に 1 時間戻る（25 時間の日）。
    @Test("夏時間の切り替わる日も、0 時から翌日の 0 時まで")
    func daylightSaving() throws {
        let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")
        func date(_ month: Int, _ day: Int, hour: Int = 0) throws -> Date {
            try #require(newYork.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)))
        }

        let shortDay = try #require(ReportPeriod.today.interval(now: try date(3, 8, hour: 12), calendar: newYork))
        #expect(shortDay == Self.span(try date(3, 8), try date(3, 9)))
        #expect(shortDay.duration == 23 * 3_600)

        let longDay = try #require(ReportPeriod.yesterday.interval(now: try date(11, 2, hour: 0), calendar: newYork))
        #expect(longDay == Self.span(try date(11, 1), try date(11, 2)))
        #expect(longDay.duration == 25 * 3_600)

        #expect(ReportPeriod.thisWeek.interval(now: try date(3, 10), calendar: newYork)
            == Self.span(try date(3, 8), try date(3, 15)))
    }
}
