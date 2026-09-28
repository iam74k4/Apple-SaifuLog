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

    @Test("読めない表記や存在しない日付、年まで書いた未来の日付は nil", arguments: [
        "", "ランチ", "2/30", "9/31", "13/1", "400日前", "2026/2/30", "2026/10/1",
    ])
    func unreadable(expression: String) {
        #expect(DateExpression.daysAgo(in: expression, now: Fixture.now, calendar: Fixture.calendar) == nil)
    }

    @Test("今年のその日がまだ来ていなければ去年とみなす")
    func futureDateMeansLastYear() {
        let days = DateExpression.daysAgo(month: 10, day: 1, now: Fixture.now, calendar: Fixture.calendar)
        #expect(days == 362)
    }

    @Test("今日は基準の日時そのもの、過去は同じ時刻のその日")
    func dateFromDaysAgo() {
        #expect(DateExpression.date(daysAgo: 0, now: Fixture.now, calendar: Fixture.calendar) == Fixture.now)
        #expect(
            DateExpression.date(daysAgo: 1, now: Fixture.now, calendar: Fixture.calendar)
                == Fixture.date(2026, 9, 27, hour: 12)
        )
    }
}
