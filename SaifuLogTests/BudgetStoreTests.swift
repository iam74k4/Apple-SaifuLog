import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 予算の保存（BudgetStore）。同じ対象の行を 1 つにまとめ、保存の失敗で画面と保存先を食い違わせないこと。
@MainActor
struct BudgetStoreTests {
    static let earlier = TestSupport.date(2026, 9, 1, hour: 9)

    static func makeStore(context: ModelContext, now: Date = TestSupport.now) -> BudgetStore {
        var store = BudgetStore(context: context)
        store.now = { now }
        return store
    }

    static func rows(_ context: ModelContext) throws -> [Budget] {
        try context.fetch(FetchDescriptor<Budget>(sortBy: [SortDescriptor(\.scopeRawValue)]))
    }

    @Test func setAmountInsertsTotalBudget() throws {
        let context = try TestSupport.makeContext()
        let store = Self.makeStore(context: context)

        try store.setAmount(150_000, for: .total)

        #expect(try store.plan() == BudgetPlan(total: 150_000))
        let rows = try Self.rows(context)
        #expect(rows.map(\.scopeRawValue) == ["total"])
        #expect(rows.map(\.updatedAt) == [TestSupport.now])
        #expect(rows.first?.scope == .total)
        #expect(!context.hasChanges)
    }

    /// 決め直しても行は増やさず、同じ行を書き換える（書き込んだ日時も新しくする）。
    @Test func setAmountUpdatesExistingRow() throws {
        let context = try TestSupport.makeContext()
        try Self.makeStore(context: context, now: Self.earlier).setAmount(150_000, for: .total)

        try Self.makeStore(context: context).setAmount(200_000, for: .total)

        let rows = try Self.rows(context)
        #expect(rows.map(\.amount) == [200_000])
        #expect(rows.map(\.updatedAt) == [TestSupport.now])
    }

    /// 額が同じなら行を書き換えない（書き込んだ日時を動かさない）。その日時は、月のまとめが予算の進みを出す月の基準
    /// （BudgetPlan.decidedAt）なので、同じ額で書き直して動かすと、前の月の予算の進みが消えるため。重なった行の片づけはする。
    @Test func sameAmountKeepsRowAndDate() throws {
        let context = try TestSupport.makeContext()
        try Self.makeStore(context: context, now: Self.earlier).setAmounts([.total: 150_000, .category(.food): 0])
        context.insert(Budget(scope: .total, amount: 100_000, updatedAt: TestSupport.date(2026, 8, 1)))
        try context.save()

        try Self.makeStore(context: context).setAmounts([.total: 150_000, .category(.food): 0, .category(.cafe): 5_000])

        let rows = try Self.rows(context)
        #expect(rows.map(\.scopeRawValue) == ["cafe", "food", "total"])
        #expect(rows.map(\.amount) == [5_000, 0, 150_000])
        #expect(rows.map(\.updatedAt) == [TestSupport.now, Self.earlier, Self.earlier])
        #expect(BudgetPlan.decidedAt(.total, in: rows) == Self.earlier)
        #expect(!context.hasChanges)
    }

    /// iCloud で別々の端末の行が届いて重なったときは、書き込むときに 1 行へ片づける。ほかの対象の行には触れない。
    @Test func setAmountRemovesDuplicatesOfSameScope() throws {
        let context = try TestSupport.makeContext()
        for (amount, day) in [(120_000, 2), (180_000, 5), (150_000, 3)] {
            context.insert(Budget(scope: .total, amount: amount, updatedAt: TestSupport.date(2026, 9, day)))
        }
        context.insert(Budget(scope: .category(.food), amount: 40_000, updatedAt: Self.earlier))
        try context.save()
        #expect(try Self.makeStore(context: context).plan().total == 180_000)

        try Self.makeStore(context: context).setAmount(160_000, for: .total)

        let rows = try Self.rows(context)
        #expect(rows.map(\.scopeRawValue) == ["food", "total"])
        #expect(rows.map(\.amount) == [40_000, 160_000])
        #expect(try Self.makeStore(context: context).plan() == BudgetPlan(total: 160_000, byCategory: [.food: 40_000]))
    }

    /// 予算をなくすときは行を消さずに 0 を書く（CloudKit で削除が伝わるのが遅れても、あとの「設定なし」が勝つように）。
    @Test func zeroMarksUnsetWithoutDeletingRow() throws {
        let context = try TestSupport.makeContext()
        let store = Self.makeStore(context: context)
        try store.setAmount(150_000, for: .total)

        try store.setAmount(0, for: .total)

        #expect(try store.plan().total == nil)
        #expect(try Self.rows(context).map(\.amount) == [0])
    }

    @Test func clampsAmountToValidRange() throws {
        let context = try TestSupport.makeContext()
        let store = Self.makeStore(context: context)

        try store.setAmounts([.total: 1_000_000_000, .category(.cafe): -500])

        #expect(try store.plan() == BudgetPlan(total: BudgetPlan.maximumAmount))
        #expect(try Self.rows(context).first { $0.scopeRawValue == "cafe" }?.amount == 0)
    }

    @Test func setAmountsWritesTotalAndCategoriesTogether() throws {
        let context = try TestSupport.makeContext()
        let store = Self.makeStore(context: context)

        try store.setAmounts([.total: 150_000, .category(.food): 40_000, .category(.cafe): 5_000])

        #expect(try store.plan() == BudgetPlan(total: 150_000, byCategory: [.food: 40_000, .cafe: 5_000]))
    }

    /// 保存に失敗したら throw し、書き換えかけた額を残さない（画面に出ている予算と保存先が食い違わないように）。
    @Test func rollsBackUpdateWhenSaveFails() throws {
        let context = try TestSupport.makeContext()
        try Self.makeStore(context: context, now: Self.earlier).setAmount(150_000, for: .total)
        context.insert(Budget(scope: .total, amount: 100_000, updatedAt: TestSupport.date(2026, 8, 1)))
        try context.save()
        var store = Self.makeStore(context: context)
        store.save = { _ in throw TestError() }

        #expect(throws: TestError.self) {
            try store.setAmount(200_000, for: .total)
        }

        #expect(!context.hasChanges)
        #expect(try store.plan().total == 150_000)
        // 片づけかけた重複の行も戻る。
        #expect(try Self.rows(context).count == 2)
        #expect(try Self.rows(context).map(\.updatedAt).contains(Self.earlier))
    }

    @Test func rollsBackInsertWhenSaveFails() throws {
        let context = try TestSupport.makeContext()
        var store = Self.makeStore(context: context)
        store.save = { _ in throw TestError() }

        #expect(throws: TestError.self) {
            try store.setAmounts([.total: 150_000, .category(.food): 40_000])
        }

        #expect(!context.hasChanges)
        #expect(try Self.rows(context).isEmpty)
    }

    @Test func emptyChangesDoNothing() throws {
        let context = try TestSupport.makeContext()
        var store = Self.makeStore(context: context)
        var saveCount = 0
        store.save = { saveCount += 1; try $0.save() }

        try store.setAmounts([:])

        #expect(saveCount == 0)
    }
}

/// ホームの帯に出す数字（今月の合計と予算の進み）。保存先から読んだ記録と予算で確かめる。
@MainActor
struct MonthSummaryFiguresTests {
    static func figures(
        context: ModelContext, today: Date
    ) throws -> (summary: MonthlySummary, budget: BudgetStatus?, pace: SummaryHeader.Pace?) {
        let records = try context.fetch(Entry.monthDescriptor(containing: today, calendar: TestSupport.calendar))
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        return MonthSummaryHeader.figures(records: records, budgets: budgets, today: today, calendar: TestSupport.calendar)
    }

    /// 9/28 は月末まで今日を含めて 3 日。収入（返金）は予算の支出を減らさない。
    @Test func showsRemainingBudgetForThisMonth() throws {
        let context = try TestSupport.makeContext()
        context.insert(TestSupport.entry(amount: 50_000, spentAt: TestSupport.date(2026, 9, 3)))
        context.insert(TestSupport.entry(amount: 7_000, category: .cafe, memo: "カフェ", spentAt: TestSupport.date(2026, 9, 28, hour: 9)))
        context.insert(TestSupport.entry(amount: 9_999, spentAt: TestSupport.date(2026, 8, 31, hour: 23)))
        context.insert(Entry(
            amount: 500, isIncome: true, category: .other, memo: "返金", spentAt: TestSupport.date(2026, 9, 10),
            source: .text, originalText: "返金 -500"
        ))
        // 重なった予算の行は、最後に書いたものを採る。
        context.insert(Budget(scope: .total, amount: 100_000, updatedAt: TestSupport.date(2026, 9, 1)))
        context.insert(Budget(scope: .total, amount: 150_000, updatedAt: TestSupport.date(2026, 9, 2)))
        try context.save()

        let figures = try Self.figures(context: context, today: TestSupport.now)

        #expect(figures.summary == MonthlySummary(expense: 57_000, income: 500))
        let budget = try #require(figures.budget)
        #expect(budget.spent == 57_000)
        #expect(budget.remaining == 93_000)
        #expect(budget.remainingDays == 3)
        #expect(budget.dailyAllowance == 31_000)
        // 今日までの目安は月のまとめと同じ（予算を 30 日で日割りした 28 日分）。今日までに使った額はそれより 83,000 円少ない。
        #expect(figures.pace == SummaryHeader.Pace(amount: 140_000, beyond: -83_000))
    }

    @Test func noBudgetShowsOnlyTotals() throws {
        let context = try TestSupport.makeContext()
        context.insert(TestSupport.entry(amount: 850))
        context.insert(Budget(scope: .total, amount: 0, updatedAt: TestSupport.now))
        try context.save()

        let figures = try Self.figures(context: context, today: TestSupport.now)

        #expect(figures.summary.expense == 850)
        #expect(figures.budget == nil)
        #expect(figures.pace == nil)
    }

    /// 月が変わったら、前の月の支出を持ち越さない（残りの日数も新しい月で数える）。
    @Test func switchesToNewMonth() throws {
        let context = try TestSupport.makeContext()
        context.insert(TestSupport.entry(amount: 160_000, spentAt: TestSupport.date(2026, 9, 20)))
        context.insert(Budget(scope: .total, amount: 150_000, updatedAt: TestSupport.date(2026, 9, 1)))
        try context.save()

        let september = try #require(try Self.figures(context: context, today: TestSupport.date(2026, 9, 30, hour: 23, minute: 59)).budget)
        #expect(september.isOver)
        #expect(september.overspent == 10_000)

        let october = try #require(try Self.figures(context: context, today: TestSupport.date(2026, 10, 1)).budget)
        #expect(!october.isOver)
        #expect(october.spent == 0)
        #expect(october.remainingDays == 31)
    }
}
