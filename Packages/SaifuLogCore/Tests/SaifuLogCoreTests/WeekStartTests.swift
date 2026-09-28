import Foundation
import Testing
@testable import SaifuLogCore

@Suite("週の始まり")
struct WeekStartTests {
    // 2026-09-28 は月曜日。
    @Test("日曜・月曜を選ぶと、暦の週の始まりを置き換え、今週の区切りが変わる")
    func overridesFirstWeekday() {
        let saturdayFirst = Fixture.calendar(firstWeekday: 7)

        let sunday = WeekStart.sunday.applied(to: saturdayFirst)
        let monday = WeekStart.monday.applied(to: saturdayFirst)

        #expect(sunday.firstWeekday == 1)
        #expect(monday.firstWeekday == 2)
        #expect(ReportPeriod.thisWeek.interval(now: Fixture.now, calendar: sunday)?.start == Fixture.date(2026, 9, 27))
        #expect(ReportPeriod.thisWeek.interval(now: Fixture.now, calendar: monday)?.start == Fixture.date(2026, 9, 28))
    }

    @Test("端末の設定に合わせるときは、渡された暦の週の始まりのまま（土曜始まりの地域でも）")
    func systemKeepsCalendar() {
        let saturdayFirst = Fixture.calendar(firstWeekday: 7)

        let applied = WeekStart.system.applied(to: saturdayFirst)

        #expect(applied == saturdayFirst)
        #expect(ReportPeriod.thisWeek.interval(now: Fixture.now, calendar: applied)?.start == Fixture.date(2026, 9, 26))
    }

    @Test("週の始まりのほかは変えない（時間帯・暦の種類・月の区切り）")
    func keepsOtherProperties() {
        let japanese = Fixture.calendar(firstWeekday: 1, identifier: .japanese)

        let applied = WeekStart.monday.applied(to: japanese)

        #expect(applied.identifier == .japanese)
        #expect(applied.timeZone == japanese.timeZone)
        #expect(applied.minimumDaysInFirstWeek == japanese.minimumDaysInFirstWeek)
        #expect(ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: applied)
            == ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: japanese))
    }

    /// rawValue は設定の保存に使う。変えると、利用者の選んだ週の始まりが既定に戻る。
    @Test("保存に使う値は変えない")
    func rawValuesAreStable() {
        #expect(WeekStart.allCases.map(\.rawValue) == ["system", "sunday", "monday"])
        #expect(WeekStart.allCases.map(\.firstWeekday) == [nil, 1, 2])
    }
}
