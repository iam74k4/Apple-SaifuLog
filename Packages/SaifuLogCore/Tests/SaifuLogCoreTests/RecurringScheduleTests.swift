import Foundation
import Testing
@testable import SaifuLogCore

@Suite("くり返しの記録")
struct RecurringScheduleTests {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    static func rule(
        day: Int, start: RecurringMonth = RecurringMonth(year: 2026, month: 9), last: RecurringMonth? = nil
    ) -> RecurringRule {
        RecurringRule(
            id: "rent", memo: "家賃", amount: 80_000, isIncome: false, category: .other, dayOfMonth: day,
            startMonth: start, lastRecordedMonth: last
        )
    }

    // MARK: - 月

    @Test("月は数で保存でき、繰り越して足し引きできる")
    func months() {
        let october = RecurringMonth(year: 2026, month: 10)
        #expect(october.key == 202610)
        #expect(RecurringMonth(key: 202610) == october)
        #expect(RecurringMonth(key: 0) == nil)
        #expect(RecurringMonth(key: 202613) == nil)
        #expect(october.adding(months: 3) == RecurringMonth(year: 2027, month: 1))
        #expect(october.adding(months: -10) == RecurringMonth(year: 2025, month: 12))
        #expect(RecurringMonth(year: 2026, month: 0) == RecurringMonth(year: 2025, month: 12))
        #expect(RecurringMonth(year: 2025, month: 12) < october)
    }

    @Test("月は時間帯で数え、端末の暦（和暦）によらず西暦で数える")
    func monthOfDate() {
        // 日本時間の 10/1 0:30 は、協定世界時ではまだ 9/30。
        let date = Fixture.date(2026, 10, 1, hour: 0, minute: 30)
        #expect(RecurringMonth(containing: date, timeZone: Self.tokyo) == RecurringMonth(year: 2026, month: 10))
        #expect(RecurringMonth(containing: date, timeZone: TimeZone(identifier: "UTC")!) == RecurringMonth(year: 2026, month: 9))
    }

    // MARK: - 記録する日

    @Test("その月に無い日は月末、記録する日時はその日の正午")
    func dayClampsToMonthEnd() {
        #expect(RecurringSchedule.date(in: RecurringMonth(year: 2026, month: 2), dayOfMonth: 31, timeZone: Self.tokyo)
            == Fixture.date(2026, 2, 28, hour: 12))
        #expect(RecurringSchedule.date(in: RecurringMonth(year: 2028, month: 2), dayOfMonth: 30, timeZone: Self.tokyo)
            == Fixture.date(2028, 2, 29, hour: 12))
        #expect(RecurringSchedule.date(in: RecurringMonth(year: 2026, month: 4), dayOfMonth: 31, timeZone: Self.tokyo)
            == Fixture.date(2026, 4, 30, hour: 12))
        #expect(RecurringSchedule.date(in: RecurringMonth(year: 2026, month: 10), dayOfMonth: 25, timeZone: Self.tokyo)
            == Fixture.date(2026, 10, 25, hour: 12))
    }

    @Test("記録する日になったら、正午より前でも今月の分を記録する。前の日にはまだ記録しない")
    func dueOnTheDay() {
        let rule = Self.rule(day: 25, start: RecurringMonth(year: 2026, month: 10))
        #expect(RecurringSchedule.dueMonths(for: rule, now: Fixture.date(2026, 10, 24, hour: 23, minute: 59), timeZone: Self.tokyo).isEmpty)
        #expect(RecurringSchedule.dueMonths(for: rule, now: Fixture.date(2026, 10, 25, hour: 0, minute: 1), timeZone: Self.tokyo)
            == [RecurringMonth(year: 2026, month: 10)])
    }

    @Test("記録した月の次の月から、今月までの過ぎた月を記録する（開かなかった月の分も）")
    func catchesUpMissedMonths() {
        let rule = Self.rule(day: 25, start: RecurringMonth(year: 2026, month: 6), last: RecurringMonth(year: 2026, month: 7))
        let months = RecurringSchedule.dueMonths(for: rule, now: Fixture.date(2026, 10, 26), timeZone: Self.tokyo)
        #expect(months == [8, 9, 10].map { RecurringMonth(year: 2026, month: $0) })
        // 今月の日がまだなら、今月は含めない。
        let early = RecurringSchedule.dueMonths(for: rule, now: Fixture.date(2026, 10, 3), timeZone: Self.tokyo)
        #expect(early == [8, 9].map { RecurringMonth(year: 2026, month: $0) })
    }

    @Test("記録済みの月と、最初の月より前は記録しない")
    func respectsStartAndLast() {
        let recorded = Self.rule(day: 1, start: RecurringMonth(year: 2026, month: 1), last: RecurringMonth(year: 2026, month: 10))
        #expect(RecurringSchedule.dueMonths(for: recorded, now: Fixture.date(2026, 10, 30), timeZone: Self.tokyo).isEmpty)
        let future = Self.rule(day: 1, start: RecurringMonth(year: 2026, month: 12))
        #expect(RecurringSchedule.dueMonths(for: future, now: Fixture.date(2026, 10, 30), timeZone: Self.tokyo).isEmpty)
    }

    @Test("さかのぼるのは今月を含めて 12 か月まで")
    func catchUpIsLimited() {
        let rule = Self.rule(day: 10, start: RecurringMonth(year: 2024, month: 1))
        let months = RecurringSchedule.dueMonths(for: rule, now: Fixture.date(2026, 10, 30), timeZone: Self.tokyo)
        #expect(months.count == RecurringSchedule.maximumCatchUpMonths)
        #expect(months.first == RecurringMonth(year: 2025, month: 11))
        #expect(months.last == RecurringMonth(year: 2026, month: 10))
    }

    // MARK: - 次に記録する日

    @Test("次に記録する日は、まだ来ていないいちばん早い日")
    func nextDate() {
        let now = Fixture.date(2026, 10, 10)
        // 今月の日がまだ。
        #expect(RecurringSchedule.nextDate(for: Self.rule(day: 25), now: now, timeZone: Self.tokyo) == Fixture.date(2026, 10, 25, hour: 12))
        // 今月の分は記録済み。
        #expect(RecurringSchedule.nextDate(
            for: Self.rule(day: 5, last: RecurringMonth(year: 2026, month: 10)), now: now, timeZone: Self.tokyo
        ) == Fixture.date(2026, 11, 5, hour: 12))
        // 今月の日を過ぎた（開けばすぐ記録する）なら、来月の日。
        #expect(RecurringSchedule.nextDate(for: Self.rule(day: 5), now: now, timeZone: Self.tokyo) == Fixture.date(2026, 11, 5, hour: 12))
        // 最初の月が先なら、その月の日。
        #expect(RecurringSchedule.nextDate(
            for: Self.rule(day: 31, start: RecurringMonth(year: 2027, month: 2)), now: now, timeZone: Self.tokyo
        ) == Fixture.date(2027, 2, 28, hour: 12))
    }

    // MARK: - 最初の月

    @Test("作るときの最初の月: 今月の日がまだなら今月、過ぎていれば来月（今月の分も記録するなら今月）")
    func startMonth() {
        let now = Fixture.date(2026, 10, 10)
        let october = RecurringMonth(year: 2026, month: 10)
        #expect(RecurringSchedule.startMonth(dayOfMonth: 25, now: now, timeZone: Self.tokyo, includesThisMonth: false) == october)
        #expect(RecurringSchedule.startMonth(dayOfMonth: 5, now: now, timeZone: Self.tokyo, includesThisMonth: false)
            == october.adding(months: 1))
        #expect(RecurringSchedule.startMonth(dayOfMonth: 5, now: now, timeZone: Self.tokyo, includesThisMonth: true) == october)
        // 今月の分をもう記録してある（記録から作った）なら、日がまだでも来月から。
        #expect(RecurringSchedule.startMonth(
            dayOfMonth: 25, now: now, timeZone: Self.tokyo, includesThisMonth: false, notBefore: october.adding(months: 1)
        ) == october.adding(months: 1))
        #expect(RecurringSchedule.hasPassedThisMonth(dayOfMonth: 10, now: now, timeZone: Self.tokyo))
        #expect(!RecurringSchedule.hasPassedThisMonth(dayOfMonth: 11, now: now, timeZone: Self.tokyo))
    }

    // MARK: - 二重の記録

    @Test("同じ月の分が 2 件以上あれば、記録した日時のいちばん古い 1 件を残す")
    func duplicates() {
        let key = RecurringSchedule.occurrenceKey(ruleID: "rent", month: RecurringMonth(year: 2026, month: 10))
        #expect(key == "rent/202610")
        let records = [
            RecurringDuplicates.Record(id: 1, key: key, createdAt: Fixture.date(2026, 10, 25, hour: 9)),
            RecurringDuplicates.Record(id: 2, key: key, createdAt: Fixture.date(2026, 10, 25, hour: 8)),
            RecurringDuplicates.Record(id: 3, key: key, createdAt: Fixture.date(2026, 10, 25, hour: 10)),
            RecurringDuplicates.Record(id: 4, key: "rent/202609", createdAt: Fixture.date(2026, 9, 25)),
            // くり返しの記録でない記録（印が空）は数えない。
            RecurringDuplicates.Record(id: 5, key: "", createdAt: Fixture.date(2026, 9, 25)),
            RecurringDuplicates.Record(id: 6, key: "", createdAt: Fixture.date(2026, 9, 25)),
        ]
        #expect(Set(RecurringDuplicates.redundant(in: records)) == [1, 3])
    }
}
