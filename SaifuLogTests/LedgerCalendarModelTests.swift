import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 月の画面のカレンダー（月に合わせる・今日を選ぶ・日を選ぶ・ほかの端末で消えた記録・週の始まり）。
@MainActor
struct LedgerCalendarModelTests {
    /// カレンダーのモデルと、その保存先・時計の代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        /// 今日（既定は 2026-09-28 12:00 の月曜）。
        var now = TestSupport.now
        private(set) var model: LedgerCalendarModel!

        init() throws {
            context = try TestSupport.makeContext()
            model = LedgerCalendarModel(store: EntryStore(context: context), now: { [unowned self] in now })
        }

        func insert(_ entries: Entry...) throws {
            try EntryStore(context: context).insert(entries)
        }

        /// 月の画面が見せている月に合わせて読む（月の画面を開いたとき・月を替えたとき）。
        func show(_ date: Date = TestSupport.now, calendar: Calendar = TestSupport.calendar) {
            model.follow(monthContaining: date, calendar: calendar)
            model.reload()
        }
    }

    /// 今月なら今日を選び、今日の記録を使った日時の順に出す。日ごとの集計は月の記録だけを数える。
    @Test func showsThisMonthAndSelectsToday() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 850, memo: "ランチ", spentAt: TestSupport.date(2026, 9, 28, hour: 12)),
            TestSupport.entry(amount: 300, memo: "パン", spentAt: TestSupport.date(2026, 9, 28, hour: 8)),
            TestSupport.entry(amount: 1_200, memo: "本", spentAt: TestSupport.date(2026, 9, 27, hour: 10)),
            TestSupport.entry(amount: 3_000, memo: "先月", spentAt: TestSupport.date(2026, 8, 31, hour: 10))
        )

        fixture.show()

        let model = try #require(fixture.model)
        #expect(model.month == ReportPeriod.thisMonth.interval(now: TestSupport.now, calendar: TestSupport.calendar))
        #expect(model.selectedDay == TestSupport.date(2026, 9, 28))
        #expect(model.selectedRecords.map(\.memo) == ["パン", "ランチ"])
        #expect(model.selectedSummary?.expense == 1_150)
        let days = try #require(model.days)
        #expect(days.days.count == 30)
        #expect(days.expense == 2_350)
        // 2026-09-01 は火曜。週の始まり（日曜）から 2 日空ける。
        #expect(days.leadingBlankCount == 2)
        #expect(model.isToday(days.days[27]))
        #expect(model.isFuture(days.days[28]))
        #expect(!model.isFuture(days.days[26]))
    }

    /// ほかの月に合わせると、選んだ日を外し（日を押すまで選ばない）、その月の記録だけを数える。
    @Test func followsOtherMonthWithoutSelection() throws {
        let fixture = try Fixture()
        try fixture.insert(TestSupport.entry(amount: 3_000, memo: "先月", spentAt: TestSupport.date(2026, 8, 31, hour: 10)))
        fixture.show()

        fixture.show(TestSupport.date(2026, 8, 10))

        #expect(fixture.model.month?.start == TestSupport.date(2026, 8, 1))
        #expect(fixture.model.selectedDay == nil)
        #expect(fixture.model.selectedRecords.isEmpty)
        #expect(fixture.model.days?.expense == 3_000)
    }

    /// 日を選ぶと、その日の記録を出す。
    @Test func selectsDay() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 1_200, memo: "本", spentAt: TestSupport.date(2026, 9, 27, hour: 10)),
            TestSupport.entry(amount: 850, memo: "ランチ", spentAt: TestSupport.date(2026, 9, 28, hour: 12))
        )
        fixture.show()

        fixture.model.select(try #require(fixture.model.days?.days[26]))

        #expect(fixture.model.selectedDay == TestSupport.date(2026, 9, 27))
        #expect(fixture.model.selectedRecords.map(\.memo) == ["本"])
    }

    /// 保存先に足した記録は、読み直すと出る（月の画面は保存の知らせで読み直す）。
    @Test func reloadPicksUpNewRecords() throws {
        let fixture = try Fixture()
        fixture.show()
        #expect(fixture.model.selectedRecords.isEmpty)

        try fixture.insert(TestSupport.entry(amount: 850, memo: "ランチ", spentAt: TestSupport.date(2026, 9, 28, hour: 12)))
        fixture.model.reload()

        #expect(fixture.model.selectedRecords.map(\.memo) == ["ランチ"])
        #expect(fixture.model.days?.expense == 850)
    }

    /// ほかの端末（iCloud）で消された記録は、直す・消すの前に確かめて引かず、一覧から外す（消えた記録の値に触れないため）。
    @Test func recordDeletedElsewhereIsNotReturned() throws {
        let fixture = try Fixture()
        try fixture.insert(TestSupport.entry(spentAt: TestSupport.date(2026, 9, 28, hour: 9)))
        fixture.show()
        let record = try #require(fixture.model.selectedRecords.first)
        #expect(fixture.model.entry(for: record)?.persistentModelID == record.id)

        let other = ModelContext(fixture.context.container)
        let id = record.id
        try other.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id })).forEach(other.delete)
        try other.save()

        #expect(fixture.model.entry(for: record) == nil)
        #expect(fixture.model.selectedRecords.isEmpty)
    }

    /// 暦の週の始まりに合わせて、1 日の前の空きを数える。
    @Test func followsWeekStart() throws {
        let fixture = try Fixture()
        var monday = TestSupport.calendar
        monday.firstWeekday = 2

        fixture.show(calendar: monday)

        // 2026-09-01（火）は、月曜から 1 日空ける。
        #expect(fixture.model.days?.leadingBlankCount == 1)
    }
}
