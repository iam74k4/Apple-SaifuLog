import Foundation
import Testing
@testable import SaifuLogCore

@Suite("日付の言い回し")
struct DateExpressionTests {
    @Test("何日前かに直す（基準は 2026-09-28）", arguments: [
        ("今日", 0),
        ("本日", 0),
        ("昨日", 1),
        ("きのう", 1),
        ("一昨日", 2),
        ("おととい", 2),
        ("3日前", 3),
        ("３日前", 3),
        ("9/26", 2),
        ("９／２６", 2),
        ("9月26日", 2),
        ("9/28", 0),
        ("9/1", 27),
        ("12/31", 271),
        ("2026/9/26", 2),
        ("2025/9/28", 365),
    ])
    func daysAgo(expression: String, expected: Int) {
        #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: Fixture.calendar) == expected)
    }

    @Test("読めない表記や存在しない日付は nil", arguments: [
        "", "ランチ", "2/30", "9/31", "13/1", "400日前", "2026/2/30", "31日",
    ])
    func unreadable(expression: String) {
        #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: Fixture.calendar) == nil)
    }

    // 以前は「今年のその日がまだ来ていなければ去年」としていたため、明日の日付（払う予定の家賃）が
    // 364 日前として保存され、今月の合計から消えていた。60 日先までは未来の日付として読むよう改めた。
    @Test("年を省いた月日は、60 日先までは未来の日付、それより先は去年とみなす", arguments: [
        ("9/29", -1),
        ("10/1", -3),
        ("11/27", -60),
        ("11/28", 304),
    ])
    func monthDayWindow(expression: String, expected: Int) {
        #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: Fixture.calendar) == expected)
    }

    @Test("年末に書いた年明けの月日は来年の日付にする")
    func monthDayAcrossYearEnd() {
        let now = Fixture.date(2026, 12, 20, hour: 12)
        #expect(DateExpression.daysAgo(month: 1, day: 5, now: now, calendar: Fixture.calendar) == -16)
    }

    // 以前は年まで書いた未来の日付を nil にしていたため、「2026/10/1」が今日の記録になっていた。
    @Test("年を書いた日付は、未来でも常にその年")
    func yearDateInFuture() {
        #expect(DateExpression.daysAgo(in: "2026/10/1", now: Fixture.now, calendar: Fixture.calendar) == -3)
        #expect(DateExpression.daysAgo(year: 2027, month: 1, day: 1, now: Fixture.now, calendar: Fixture.calendar) == -95)
    }

    @Test("月や年を語で指した日付は、その月・その年の日付（基準は 2026-10-28）", arguments: [
        ("先月25日", 33), ("先月の25日", 33), ("今月25日", 3), ("来月1日", -4), ("再来月1日", -34),
        ("去年10/1", 392), ("昨年10月1日", 392), ("今年10月1日", 27), ("来年1/5", -69),
    ])
    func relativeMonthAndYear(expression: String, expected: Int) {
        let now = Fixture.date(2026, 10, 28, hour: 12)
        #expect(DateExpression.daysAgo(in: expression, now: now, calendar: Fixture.calendar) == expected)
    }

    @Test("語と組にならない日付と、その月に無い日は読まない", arguments: [
        "去年25日", "先月10/1", "先月9月25日", "先月31日", "去年2025/10/1",
    ])
    func unsupportedRelativeDates(expression: String) {
        let now = Fixture.date(2026, 10, 28, hour: 12)
        #expect(DateExpression.daysAgo(in: expression, now: now, calendar: Fixture.calendar) == nil)
    }

    @Test("1 月の「先月」は去年の 12 月、12 月の「来月」は来年の 1 月")
    func relativeMonthAcrossYearEnd() {
        let january = Fixture.date(2027, 1, 10, hour: 12)
        let december = Fixture.date(2026, 12, 20, hour: 12)
        #expect(DateExpression.daysAgo(monthOffset: -1, day: 25, now: january, calendar: Fixture.calendar) == 16)
        #expect(DateExpression.daysAgo(monthOffset: 1, day: 5, now: december, calendar: Fixture.calendar) == -16)
    }

    @Test("日だけの表記は今月のその日", arguments: [
        ("26日", 2),
        ("30日", -2),
        ("1日", 27),
    ])
    func dayOnly(expression: String, expected: Int) {
        #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: Fixture.calendar) == expected)
    }

    @Test("型番・版・小数・人数の幅の「.」「-」は日付にしない", arguments: ["ver1.2", "1.5", "10.5", "PS5-2", "3-4人", "2-3個"])
    func dottedNumbersAreNotDates(expression: String) {
        #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: Fixture.calendar) == nil)
    }

    @Test("期間・順番・割合の「N日」は日付にしない", arguments: ["3日間", "1日分", "2日目", "3日後", "2泊3日", "1日1回", "1日あたり"])
    func dayCountIsNotDate(expression: String) {
        #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: Fixture.calendar) == nil)
    }

    @Test("年まで書いた漢字の日付・2 桁の年・和暦の略記・「-」「.」でつないだ日付", arguments: [
        ("2025年9月26日", 367),
        ("2026年9月26日", 2),
        ("2024年12月1日", 666),
        ("2025年 9月 26日", 367),
        ("12月 25日", 277),
        ("令和7年9月26日", 367),
        ("25/9/26", 367),
        ("R7/9/26", 367),
        ("2026-09-26", 2),
        ("2026.9.26", 2),
        ("9-26", 2),
        ("9.26", 2),
        ("10.05", -7),
    ])
    func writtenDates(expression: String, expected: Int) {
        #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: Fixture.calendar) == expected)
    }

    @Test("和暦・仏暦の設定でも、年は西暦として読む", arguments: [
        Calendar.Identifier.japanese, .buddhist,
    ])
    func nonGregorianCalendars(identifier: Calendar.Identifier) {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = Fixture.calendar.timeZone
        for (expression, expected) in [("2026/9/26", 2), ("9/26", 2), ("昨日", 1), ("2025年9月26日", 367), ("26日", 2)] {
            #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: calendar) == expected)
        }
    }

    // チリ（America/Santiago）は 2026-09-06 の 0 時に夏時間へ切り替わり、その日の 0 時が存在しない。
    // 0 時で組み立てて差を数えると 1 日ずれる。
    @Test("深夜 0 時に夏時間へ切り替わる日も 1 日ずれない")
    func daylightSavingAtMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12)))
        #expect(DateExpression.daysAgo(in: "9/6", now: now, calendar: calendar) == 1)
        #expect(DateExpression.daysAgo(in: "9/7", now: now, calendar: calendar) == 0)
        #expect(DateExpression.daysAgo(in: "2026/9/5", now: now, calendar: calendar) == 2)
    }

    @Test("今日は基準の日時そのもの、ほかの日は同じ時刻のその日")
    func dateFromDaysAgo() {
        #expect(DateExpression.date(daysAgo: 0, now: Fixture.now, calendar: Fixture.calendar) == Fixture.now)
        #expect(
            DateExpression.date(daysAgo: 1, now: Fixture.now, calendar: Fixture.calendar)
                == Fixture.date(2026, 9, 27, hour: 12)
        )
        #expect(
            DateExpression.date(daysAgo: -2, now: Fixture.now, calendar: Fixture.calendar)
                == Fixture.date(2026, 9, 30, hour: 12)
        )
    }
}
