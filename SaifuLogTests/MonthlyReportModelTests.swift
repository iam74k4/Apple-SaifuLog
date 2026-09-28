import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 月のまとめ（MonthlyReportModel）。メモリの上の保存先と、固定の日時（2026-09-28 12:00、日本時間）で確かめる。
@MainActor
struct MonthlyReportModelTests {
    /// MonthlyReportModel と、その保存先・時計・読み上げ・ホームへの知らせの代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        var now = TestSupport.now
        private(set) var announcements: [String] = []
        private(set) var savedEntries: [Entry] = []
        private(set) var deletedIDs: [PersistentIdentifier] = []

        init() throws {
            context = try TestSupport.makeContext()
        }

        /// 記録を保存先に足す。
        func insert(_ entries: Entry...) throws {
            try EntryStore(context: context).insert(entries)
        }

        func delete(_ entries: Entry...) throws {
            try EntryStore(context: context).delete(entries)
        }

        /// 全体の予算を `date` の日時に決める。
        func setBudget(_ amount: Int, at date: Date) throws {
            try BudgetStore(context: context, now: { date }).setAmount(amount, for: .total)
        }

        /// いまの保存先で、まとめのモデルを作る（今月を開く）。
        func makeModel() -> MonthlyReportModel {
            MonthlyReportModel(
                store: EntryStore(context: context),
                calendar: TestSupport.calendar,
                now: { [unowned self] in now },
                announce: { [unowned self] in announcements.append($0) },
                didSave: { [unowned self] in savedEntries.append($0) },
                didDelete: { [unowned self] in deletedIDs.append($0) }
            )
        }
    }

    static func month(_ year: Int, _ month: Int) -> DateInterval {
        let start = TestSupport.date(year, month, 1)
        let end = TestSupport.calendar.date(byAdding: .month, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    static func income(_ amount: Int, spentAt: Date) -> Entry {
        Entry(
            amount: amount, isIncome: true, category: .other, memo: "給料",
            spentAt: spentAt, createdAt: spentAt, source: .text, originalText: "給料 \(amount)"
        )
    }

    // MARK: - 開いたとき

    @Test("今月を開く。記録が無ければ、前の月にも次の月にも進めない")
    func opensCurrentMonth() throws {
        let fixture = try Fixture()

        let model = fixture.makeModel()

        #expect(model.month == Self.month(2026, 9))
        #expect(!model.loadFailed)
        #expect(model.report?.recordCount == 0)
        #expect(model.report?.timing == .current)
        #expect(model.earliestSpentAt == nil)
        #expect(!model.canShowPreviousMonth)
        #expect(!model.canShowNextMonth)
        #expect(model.monthTitle.contains("2026"))
    }

    @Test("質問の回答カードから開くときは、渡した月を開く（今月より先の月は今月にする）")
    func opensGivenMonth() throws {
        let fixture = try Fixture()
        try fixture.insert(TestSupport.entry(amount: 700, spentAt: TestSupport.date(2026, 8, 10)))

        let lastMonth = MonthlyReportModel(
            store: EntryStore(context: fixture.context), calendar: TestSupport.calendar,
            month: TestSupport.date(2026, 8, 1), now: { TestSupport.now }, announce: { _ in }
        )
        #expect(lastMonth.month == Self.month(2026, 8))
        #expect(lastMonth.report?.expense == 700)
        #expect(lastMonth.canShowNextMonth)

        let future = MonthlyReportModel(
            store: EntryStore(context: fixture.context), calendar: TestSupport.calendar,
            month: TestSupport.date(2026, 11, 1), now: { TestSupport.now }, announce: { _ in }
        )
        #expect(future.month == Self.month(2026, 9))
    }

    @Test("今月の数字は、その月の記録から出す（前の月との差も）")
    func reportOfCurrentMonth() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 3_000, category: .food, spentAt: TestSupport.date(2026, 8, 20)),
            TestSupport.entry(amount: 850, category: .food, spentAt: TestSupport.date(2026, 9, 3)),
            TestSupport.entry(amount: 400, category: .cafe, memo: "コーヒー", spentAt: TestSupport.date(2026, 9, 10)),
            Self.income(250_000, spentAt: TestSupport.date(2026, 9, 25))
        )

        let report = try #require(fixture.makeModel().report)

        #expect(report.expense == 1_250)
        #expect(report.income == 250_000)
        #expect(report.breakdown.items.map(\.category) == [.food, .cafe])
        #expect(report.expenseChange == -1_750)
    }

    // MARK: - 月送り

    @Test("前の月へは記録のある最初の月まで、次の月へは今月までしか進めない")
    func monthNavigationStopsAtEdges() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 1_200, spentAt: TestSupport.date(2026, 7, 10)),
            TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 9, 5))
        )
        let model = fixture.makeModel()
        #expect(model.canShowPreviousMonth)
        #expect(!model.canShowNextMonth)

        // 今月より先へは進まない（押せないボタンを押したことにしても変わらない）。
        model.showNextMonth()
        #expect(model.month == Self.month(2026, 9))
        #expect(fixture.announcements.isEmpty)

        // 記録の無い月も通れる。
        model.showPreviousMonth()
        #expect(model.month == Self.month(2026, 8))
        #expect(model.report?.recordCount == 0)
        #expect(model.report?.timing == .past)
        #expect(model.canShowPreviousMonth)
        #expect(model.canShowNextMonth)

        model.showPreviousMonth()
        #expect(model.month == Self.month(2026, 7))
        #expect(model.report?.expense == 1_200)
        #expect(!model.canShowPreviousMonth)

        // 記録のある最初の月より前には戻らない。
        model.showPreviousMonth()
        #expect(model.month == Self.month(2026, 7))

        model.showNextMonth()
        model.showNextMonth()
        #expect(model.month == Self.month(2026, 9))
        #expect(model.report?.expense == 850)
        #expect(!model.canShowNextMonth)

        // 月を替えるたびに、どの月になったかを読み上げる（押せなかったときは読まない）。
        #expect(fixture.announcements.count == 4)
        #expect(fixture.announcements.last == model.monthTitle)
    }

    /// 先の日付の記録（払う予定の家賃など）があっても、今月より先へは進まない。
    @Test("先の日付の記録があっても、今月より先へは進めない")
    func futureRecordsDoNotAllowGoingForward() throws {
        let fixture = try Fixture()
        try fixture.insert(TestSupport.entry(amount: 80_000, category: .other, memo: "家賃", spentAt: TestSupport.date(2026, 10, 5)))

        let model = fixture.makeModel()

        #expect(!model.canShowNextMonth)
        #expect(!model.canShowPreviousMonth)
        #expect(model.report?.recordCount == 0)
    }

    @Test("記録のある最初の月が今月なら、前の月へは戻れない")
    func earliestRecordInCurrentMonth() throws {
        let fixture = try Fixture()
        try fixture.insert(TestSupport.entry(spentAt: TestSupport.date(2026, 9, 1)))

        let model = fixture.makeModel()

        #expect(model.earliestSpentAt == TestSupport.date(2026, 9, 1))
        #expect(!model.canShowPreviousMonth)
    }

    /// 前面に置いたまま月をまたいでも、見ている月は黙って替えない。次の月（新しい今月）へ進めるようになる。
    @Test("今日が次の月になっても、見ている月はそのままで、次の月へ進めるようになる")
    func refreshTodayAcrossMonthEnd() throws {
        let fixture = try Fixture()
        fixture.now = TestSupport.date(2026, 9, 30, hour: 23)
        try fixture.insert(TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 9, 30, hour: 12)))
        let model = fixture.makeModel()
        #expect(model.report?.timing == .current)
        #expect(!model.canShowNextMonth)

        fixture.now = TestSupport.date(2026, 10, 1, hour: 9)
        model.refreshToday()

        #expect(model.month == Self.month(2026, 9))
        #expect(model.report?.timing == .past)
        #expect(model.report?.averagingDays == 30)
        #expect(model.canShowNextMonth)
        model.showNextMonth()
        #expect(model.month == Self.month(2026, 10))
        #expect(model.report?.timing == .current)
    }

    @Test("月を替えると、開いていたカテゴリの一覧は閉じる")
    func changingMonthClosesCategoryList() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(spentAt: TestSupport.date(2026, 8, 10)),
            TestSupport.entry(spentAt: TestSupport.date(2026, 9, 10))
        )
        let model = fixture.makeModel()
        model.showEntries(in: .food)
        #expect(model.selectedCategory == .food)

        model.showPreviousMonth()

        #expect(model.selectedCategory == nil)
    }

    // MARK: - 記録の変化

    /// 保存先に書き込まれたら、画面が `ModelContext.didSave` を受けて読み直す。
    @Test("記録を足したり消したりしたら、読み直すと数字と月送りの端が変わる")
    func reloadReflectsAddedAndDeletedRecords() throws {
        let fixture = try Fixture()
        let lunch = TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 9, 3))
        try fixture.insert(lunch)
        let model = fixture.makeModel()
        #expect(model.report?.expense == 850)
        #expect(!model.canShowPreviousMonth)

        let coffee = TestSupport.entry(amount: 400, category: .cafe, memo: "コーヒー", spentAt: TestSupport.date(2026, 9, 28, hour: 9))
        let old = TestSupport.entry(amount: 1_200, spentAt: TestSupport.date(2026, 7, 10))
        try fixture.insert(coffee, old)
        model.reload()

        #expect(model.report?.expense == 1_250)
        #expect(model.report?.breakdown.items.map(\.category) == [.food, .cafe])
        #expect(model.canShowPreviousMonth)

        try fixture.delete(lunch, old)
        model.reload()

        #expect(model.report?.expense == 400)
        #expect(model.report?.breakdown.items.map(\.category) == [.cafe])
        #expect(!model.canShowPreviousMonth)

        try fixture.delete(coffee)
        model.reload()

        #expect(model.report?.recordCount == 0)
        #expect(model.earliestSpentAt == nil)
    }

    // MARK: - カテゴリの記録

    @Test("カテゴリの記録は、その月のそのカテゴリの支出だけを、使った日時の新しい順に並べる")
    func entriesInCategory() throws {
        let fixture = try Fixture()
        let early = TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 9, 3))
        let late = TestSupport.entry(amount: 1_200, memo: "弁当", spentAt: TestSupport.date(2026, 9, 20))
        // 同じ日時なら、あとで記録したほうを上にする。
        let sameTimeFirst = TestSupport.entry(amount: 300, memo: "パン", spentAt: TestSupport.date(2026, 9, 10), createdAt: TestSupport.date(2026, 9, 10, hour: 8))
        let sameTimeSecond = TestSupport.entry(amount: 150, memo: "牛乳", spentAt: TestSupport.date(2026, 9, 10), createdAt: TestSupport.date(2026, 9, 10, hour: 9))
        let refund = Entry(
            amount: 500, isIncome: true, category: .food, memo: "返金", spentAt: TestSupport.date(2026, 9, 12),
            createdAt: TestSupport.date(2026, 9, 12), source: .text, originalText: "返金 -500"
        )
        try fixture.insert(
            early, late, sameTimeFirst, sameTimeSecond, refund,
            TestSupport.entry(amount: 3_000, spentAt: TestSupport.date(2026, 8, 31, hour: 23)),
            TestSupport.entry(amount: 400, category: .cafe, memo: "コーヒー", spentAt: TestSupport.date(2026, 9, 5))
        )
        let model = fixture.makeModel()

        #expect(model.entries(in: .food).map(\.amount) == [1_200, 150, 300, 850])
        #expect(model.entries(in: .cafe).map(\.amount) == [400])
        #expect(model.entries(in: .transport).isEmpty)
        // 一覧の合計は、内訳の行の金額と同じ。
        #expect(model.entries(in: .food).reduce(0) { $0 + $1.amount } == model.report?.breakdown.item(for: .food)?.amount)
    }

    @Test("一覧から直してカテゴリを変えたら、数字と一覧を読み直し、ホームに知らせる")
    func editFromCategoryListReloads() throws {
        let fixture = try Fixture()
        let drug = TestSupport.entry(amount: 1_200, category: .daily, memo: "ドラッグ", spentAt: TestSupport.date(2026, 9, 3))
        try fixture.insert(drug, TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 9, 4)))
        let model = fixture.makeModel()
        model.showEntries(in: .daily)

        model.presentEdit(drug)
        let editing = try #require(model.editing)
        editing.category = .medical
        #expect(editing.save())

        #expect(model.entries(in: .daily).isEmpty)
        #expect(model.entries(in: .medical).map(\.amount) == [1_200])
        #expect(model.report?.breakdown.item(for: .daily) == nil)
        #expect(model.report?.breakdown.item(for: .medical)?.amount == 1_200)
        #expect(fixture.savedEntries.count == 1)
    }

    @Test("一覧から直して日付を別の月にしたら、その月の数字から外れる")
    func editMovingEntryToAnotherMonth() throws {
        let fixture = try Fixture()
        let lunch = TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 9, 3, hour: 12))
        try fixture.insert(lunch, TestSupport.entry(amount: 400, category: .cafe, spentAt: TestSupport.date(2026, 9, 4)))
        let model = fixture.makeModel()

        model.presentEdit(lunch)
        let editing = try #require(model.editing)
        editing.day = TestSupport.date(2026, 8, 31)
        #expect(editing.save())

        #expect(model.report?.expense == 400)
        #expect(model.entries(in: .food).isEmpty)
        #expect(model.canShowPreviousMonth)
    }

    @Test("一覧から消したら、数字と一覧を読み直し、ホームに知らせる")
    func deleteFromCategoryListReloads() throws {
        let fixture = try Fixture()
        let lunch = TestSupport.entry(amount: 850, spentAt: TestSupport.date(2026, 9, 3))
        try fixture.insert(lunch, TestSupport.entry(amount: 400, category: .cafe, spentAt: TestSupport.date(2026, 9, 4)))
        let model = fixture.makeModel()
        let id = lunch.persistentModelID

        model.presentEdit(lunch)
        #expect(try #require(model.editing).delete())

        #expect(model.report?.expense == 400)
        #expect(model.entries(in: .food).isEmpty)
        #expect(fixture.deletedIDs == [id])
    }

    // MARK: - 予算

    @Test("予算を決めていなければ、予算の進みを出さない")
    func noBudget() throws {
        let fixture = try Fixture()
        try fixture.insert(TestSupport.entry(spentAt: TestSupport.date(2026, 9, 3)))

        let model = fixture.makeModel()

        #expect(model.report?.budget == nil)
        #expect(model.report?.budgetPace == nil)
    }

    /// 予算は月ごとに持たないので、いまの額に決める前の月には出さない（§6-1、docs/design.md の ⑦ の決め事）。
    @Test("今月には予算の進みを出し、いまの予算に決めた月より前の月には出さない")
    func budgetOnlyFromDecidedMonth() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 120_000, spentAt: TestSupport.date(2026, 8, 20)),
            TestSupport.entry(amount: 57_000, spentAt: TestSupport.date(2026, 9, 3))
        )
        try fixture.setBudget(150_000, at: TestSupport.date(2026, 9, 1, hour: 9))
        let model = fixture.makeModel()

        let budget = try #require(model.report?.budget)
        #expect(budget.spent == 57_000)
        #expect(budget.remaining == 93_000)
        #expect(model.report?.budgetPace == 140_000)

        model.showPreviousMonth()
        #expect(model.report?.budget == nil)
    }

    @Test("予算を前の月より前に決めていれば、前の月にも予算の進みを出す（日割りの目安は今月だけ）")
    func budgetInPastMonth() throws {
        let fixture = try Fixture()
        try fixture.insert(TestSupport.entry(amount: 162_000, spentAt: TestSupport.date(2026, 8, 20)))
        try fixture.setBudget(150_000, at: TestSupport.date(2026, 7, 1))
        let model = fixture.makeModel()

        model.showPreviousMonth()

        let budget = try #require(model.report?.budget)
        #expect(budget.isOver)
        #expect(budget.overspent == 12_000)
        #expect(model.report?.budgetPace == nil)
    }

    /// 払う予定の家賃のように、今月の先の日付で付けた記録（§4-4）。月の支出と予算の使った額には数え（ホームの帯と同じ）、
    /// 1 日あたりの平均と今日までの目安との比べには数えない。56,000 ÷ 28 = 2,000、56,000 − 140,000 = −84,000。
    @Test("今月の先の日付の記録は、平均と今日までの目安との比べに数えない")
    func futureDatedRecordInCurrentMonth() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 56_000, spentAt: TestSupport.date(2026, 9, 3)),
            TestSupport.entry(amount: 80_000, category: .other, memo: "家賃", spentAt: TestSupport.date(2026, 9, 30))
        )
        try fixture.setBudget(150_000, at: TestSupport.date(2026, 9, 1))

        let report = try #require(fixture.makeModel().report)

        #expect(report.expense == 136_000)
        #expect(report.budget?.spent == 136_000)
        #expect(report.expenseThroughToday == 56_000)
        #expect(report.dailyAverage == 2_000)
        #expect(report.budgetPace == 140_000)
        #expect(report.spentBeyondPace == -84_000)
    }

    @Test("予算を変えたら、変えた月から後にだけ出す（変える前の月には出さない）")
    func changingBudgetHidesEarlierMonths() throws {
        let fixture = try Fixture()
        try fixture.insert(
            TestSupport.entry(amount: 100_000, spentAt: TestSupport.date(2026, 8, 20)),
            TestSupport.entry(amount: 50_000, spentAt: TestSupport.date(2026, 9, 3))
        )
        try fixture.setBudget(150_000, at: TestSupport.date(2026, 7, 1))
        try fixture.setBudget(120_000, at: TestSupport.date(2026, 9, 15))
        let model = fixture.makeModel()

        #expect(model.report?.budget?.budget == 120_000)
        model.showPreviousMonth()
        #expect(model.report?.budget == nil)
    }
}
