import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// カレンダーのページ（今月を開く・日を選ぶ・月を替える・予算の日割りの印・くり返しの予定・見通し・ほかの端末で消えた記録・
/// 日付の変わり目）。
@MainActor
struct LedgerCalendarModelTests {
    /// カレンダーのモデルと、その保存先・時計・読み上げの代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        /// 今日（既定は 2026-09-28 12:00 の月曜）。
        var now = TestSupport.now
        private(set) var announcements: [String] = []
        private(set) var model: LedgerCalendarModel!

        init() throws {
            context = try TestSupport.makeContext()
            model = LedgerCalendarModel(
                store: EntryStore(context: context),
                budgetStore: BudgetStore(context: context),
                recurring: RecurringEntryStore(context: context, now: { TestSupport.now }),
                now: { [unowned self] in now },
                announce: { [unowned self] in announcements.append($0) }
            )
        }

        func insert(_ entries: Entry...) throws {
            try EntryStore(context: context).insert(entries)
        }

        /// 画面の暦を渡して開く（ホームが出たとき）。
        func open() {
            model.configure(calendar: TestSupport.calendar)
        }
    }

    /// 開くと今月を見せて今日を選び、今日の記録を使った日時の順に出す。日ごとの集計は月の記録だけを数える。
    @Test func opensThisMonthAndSelectsToday() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 850, memo: "ランチ", spentAt: TestSupport.date(2026, 9, 28, hour: 12)),
            TestSupport.entry(amount: 300, memo: "パン", spentAt: TestSupport.date(2026, 9, 28, hour: 8)),
            TestSupport.entry(amount: 1_200, memo: "本", spentAt: TestSupport.date(2026, 9, 27, hour: 10)),
            TestSupport.entry(amount: 3_000, memo: "先月", spentAt: TestSupport.date(2026, 8, 31, hour: 10))
        )

        fixture.open()

        let model = try #require(fixture.model)
        #expect(model.month == ReportPeriod.thisMonth.interval(now: TestSupport.now, calendar: TestSupport.calendar))
        #expect(model.isCurrentMonth)
        #expect(model.isShowingToday)
        #expect(model.selectedDay == TestSupport.date(2026, 9, 28))
        #expect(model.selectedRecords.map(\.memo) == ["パン", "ランチ"])
        #expect(model.selectedSummary?.expense == 1_150)
        let days = try #require(model.days)
        #expect(days.days.count == 30)
        #expect(days.expense == 2_350)
        // 2026-09-01 は火曜。週の始まり（日曜）から 2 日空ける。
        #expect(days.leadingBlankCount == 2)
        #expect(model.outlook?.spentToday == 1_150)
        #expect(model.isToday(days.days[27]))
        #expect(model.isFuture(days.days[28]))
        #expect(!model.isFuture(days.days[26]))
    }

    /// 日を選ぶと、その日の記録を出す。
    @Test func selectsDay() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 1_200, memo: "本", spentAt: TestSupport.date(2026, 9, 27, hour: 10)),
            TestSupport.entry(amount: 850, memo: "ランチ", spentAt: TestSupport.date(2026, 9, 28, hour: 12))
        )
        fixture.open()

        fixture.model.select(try #require(fixture.model.days?.days[26]))

        #expect(fixture.model.selectedDay == TestSupport.date(2026, 9, 27))
        #expect(fixture.model.selectedRecords.map(\.memo) == ["本"])
        #expect(!fixture.model.isShowingToday)
    }

    /// 前後の月へ替えると選んだ日を外し、見通しは出さない（今月だけ）。替えた月を読み上げる。「今日」で今月の今日に戻る。
    @Test func switchesMonths() throws {
        let fixture = try Fixture()
        fixture.open()

        fixture.model.showMonth(offset: -1)

        #expect(fixture.model.month?.start == TestSupport.date(2026, 8, 1))
        #expect(fixture.model.selectedDay == nil)
        #expect(fixture.model.selectedRecords.isEmpty)
        #expect(fixture.model.outlook == nil)
        #expect(!fixture.model.isCurrentMonth)
        #expect(fixture.announcements == [fixture.model.monthTitle])

        #expect(!fixture.model.isFutureMonth)
        fixture.model.showMonth(offset: 2)
        #expect(fixture.model.isFutureMonth)

        fixture.model.showThisMonth()

        #expect(fixture.model.month?.start == TestSupport.date(2026, 9, 1))
        #expect(!fixture.model.isFutureMonth)
        #expect(fixture.model.selectedDay == TestSupport.date(2026, 9, 28))
        #expect(fixture.model.outlook != nil)
        #expect(fixture.announcements.count == 3)

        // 今月を見ているときの「今日」は、月を読み上げない（月は替わらないため）。
        fixture.model.select(try #require(fixture.model.days?.days.first))
        fixture.model.showThisMonth()
        #expect(fixture.model.isShowingToday)
        #expect(fixture.announcements.count == 3)
    }

    /// 予算の日割り（予算 ÷ 月の日数）より多く使った日に印を付ける。予算を決めていなければ付けない。
    @Test func marksDaysOverDailyPace() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 3_001, spentAt: TestSupport.date(2026, 9, 2, hour: 12)),
            TestSupport.entry(amount: 3_000, spentAt: TestSupport.date(2026, 9, 3, hour: 12))
        )
        fixture.open()
        #expect(fixture.model.exceedsPace(try #require(fixture.model.days?.days[1])) == false)

        // 90,000 ÷ 30 日 = 3,000。
        try BudgetStore(context: fixture.context).setAmount(90_000, for: .total)
        fixture.model.reload()

        let days = try #require(fixture.model.days)
        #expect(fixture.model.budget == 90_000)
        #expect(fixture.model.exceedsPace(days.days[1]))
        #expect(!fixture.model.exceedsPace(days.days[2]))
    }

    /// まだ記録していないくり返しの記録を、その日の予定として出し、今月の見通しの固定費に数える。先の月にも予定を出す。
    @Test func showsPlannedRecurringEntries() throws {
        let fixture = try Fixture()
        try RecurringEntryStore(context: fixture.context, now: { TestSupport.now }).create(
            RecurringDraft(amount: 1_490, memo: "動画", isIncome: false, category: .entertainment, dayOfMonth: 30),
            startMonth: RecurringMonth(year: 2026, month: 9)
        )
        try BudgetStore(context: fixture.context).setAmount(100_000, for: .total)
        fixture.open()

        #expect(fixture.model.planned(on: TestSupport.date(2026, 9, 30)).map(\.memo) == ["動画"])
        #expect(fixture.model.planned(on: TestSupport.date(2026, 9, 29)).isEmpty)
        #expect(fixture.model.outlook?.plannedFixedTotal == 1_490)
        // 予算 − 今月の支出（0）− まだ記録していない固定費。
        #expect(fixture.model.outlook?.freeToSpend == 98_510)

        fixture.model.showMonth(offset: 1)
        #expect(fixture.model.planned.map(\.memo) == ["動画"])
        #expect(fixture.model.outlook == nil)
    }

    /// 保存先に足した記録は、読み直すと出る（ホームは保存の知らせで読み直す）。
    @Test func reloadPicksUpNewRecords() throws {
        let fixture = try Fixture()
        fixture.open()
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
        fixture.open()
        let record = try #require(fixture.model.selectedRecords.first)
        #expect(fixture.model.entry(for: record)?.persistentModelID == record.id)

        let other = ModelContext(fixture.context.container)
        let id = record.id
        try other.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id })).forEach(other.delete)
        try other.save()

        #expect(fixture.model.entry(for: record) == nil)
        #expect(fixture.model.selectedRecords.isEmpty)
    }

    /// 日付が変わったら、今日を見ていれば今日を選び直し、今月を見ていて月が替われば新しい月を見せる。ほかの日・ほかの月を
    /// 見ていたら、そのまま。
    @Test func followsTodayAcrossDays() throws {
        let fixture = try Fixture()
        fixture.now = TestSupport.date(2026, 9, 30, hour: 23)
        fixture.open()
        #expect(fixture.model.selectedDay == TestSupport.date(2026, 9, 30))

        fixture.now = TestSupport.date(2026, 10, 1, hour: 7)
        fixture.model.refreshToday()
        #expect(fixture.model.month?.start == TestSupport.date(2026, 10, 1))
        #expect(fixture.model.selectedDay == TestSupport.date(2026, 10, 1))
        #expect(fixture.model.outlook != nil)

        fixture.now = TestSupport.date(2026, 10, 2, hour: 7)
        fixture.model.refreshToday()
        #expect(fixture.model.selectedDay == TestSupport.date(2026, 10, 2))

        fixture.model.select(try #require(fixture.model.days?.days.first))
        fixture.now = TestSupport.date(2026, 10, 3, hour: 7)
        fixture.model.refreshToday()
        #expect(fixture.model.selectedDay == TestSupport.date(2026, 10, 1))

        fixture.model.showMonth(offset: -1)
        fixture.now = TestSupport.date(2026, 11, 1, hour: 7)
        fixture.model.refreshToday()
        #expect(fixture.model.month?.start == TestSupport.date(2026, 9, 1))
    }

    /// 週の始まりの設定を変えると、1 日の前の空きを数え直す。
    @Test func followsWeekStart() throws {
        let fixture = try Fixture()
        fixture.open()
        #expect(fixture.model.days?.leadingBlankCount == 2)

        var monday = TestSupport.calendar
        monday.firstWeekday = 2
        fixture.model.configure(calendar: monday)

        // 2026-09-01（火）は、月曜から 1 日空ける。見ていた月と選んだ日はそのまま。
        #expect(fixture.model.days?.leadingBlankCount == 1)
        #expect(fixture.model.month?.start == TestSupport.date(2026, 9, 1))
        #expect(fixture.model.selectedDay == TestSupport.date(2026, 9, 28))
    }
}
