import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 覚えたカテゴリの読み書き（`LearnedCategoryStore`）。同じ言葉の行を 1 つに片づけること・直すで変えたカテゴリだけを覚えること・
/// 忘れること・保存の失敗の巻き戻しを確かめる。
@MainActor
struct LearnedCategoryStoreTests {
    static let earlier = TestSupport.date(2026, 9, 1, hour: 9)

    private func store(_ context: ModelContext, now: Date = TestSupport.now) -> LearnedCategoryStore {
        LearnedCategoryStore(context: context, now: { now })
    }

    private func rows(_ context: ModelContext) throws -> [LearnedCategory] {
        try context.fetch(FetchDescriptor<LearnedCategory>())
    }

    @Test func remembersItemWithFoldedPhrase() throws {
        let context = try TestSupport.makeContext()

        #expect(try store(context).remember(item: "  ゆにくろ ", category: .other))

        let saved = try rows(context)
        #expect(saved.map(\.phrase) == ["ユニクロ"])
        #expect(saved.map(\.category) == [.other])
        #expect(saved.map(\.updatedAt) == [TestSupport.now])
        #expect(try store(context).memory().category(forItem: "ユニクロ 靴下") == .other)
    }

    @Test func doesNotRememberEmptyItem() throws {
        let context = try TestSupport.makeContext()

        #expect(try !store(context).remember(item: " ", category: .food))
        #expect(try rows(context).isEmpty)
    }

    /// iCloud で同じ言葉の行が重なっていても、書くときに 1 つに片づけ、いま選んだカテゴリにする。
    @Test func rewritesOneRowAndRemovesDuplicates() throws {
        let context = try TestSupport.makeContext()
        context.insert(LearnedCategory(phrase: "ユニクロ", category: .daily, updatedAt: Self.earlier))
        context.insert(LearnedCategory(phrase: "ゆにくろ", category: .entertainment, updatedAt: Self.earlier.addingTimeInterval(60)))
        try context.save()

        try store(context).remember(item: "ユニクロ", category: .other)

        let saved = try rows(context)
        #expect(saved.count == 1)
        #expect(saved.first?.phrase == "ユニクロ")
        #expect(saved.first?.category == .other)
        #expect(saved.first?.updatedAt == TestSupport.now)
    }

    /// 同じカテゴリを選び直しても、書いた日時は新しくする（別の端末で同じころに覚えた別のカテゴリに負けないように）。
    @Test func refreshesTimestampForSameCategory() throws {
        let context = try TestSupport.makeContext()
        context.insert(LearnedCategory(phrase: "ユニクロ", category: .other, updatedAt: Self.earlier))
        try context.save()

        try store(context).remember(item: "ユニクロ", category: .other)

        #expect(try rows(context).map(\.updatedAt) == [TestSupport.now])
    }

    @Test func remembersCategoryChangedInEdit() throws {
        let context = try TestSupport.makeContext()
        let original = EntryEdits(amount: 3_990, isIncome: false, category: .other, memo: "ユニクロ", spentAt: TestSupport.now)
        var edits = original
        edits.category = .daily

        #expect(try store(context).rememberCorrection(from: original, to: edits))

        #expect(try store(context).memory().rules == ["ユニクロ": .daily])
    }

    /// 割り勘の記録は、書き足した説明を除いた品目で覚える（次の「焼肉」の記録に当てるため）。
    @Test func remembersItemOfSplitMemo() throws {
        let context = try TestSupport.makeContext()
        let split = ParsedEntry.assemble(total: 12_000, category: .food, isIncome: false, item: "焼肉", daysAgo: 0, splitCount: 4)
        let original = EntryEdits(amount: split.amount, isIncome: false, category: .food, memo: split.memo, spentAt: TestSupport.now)
        var edits = original
        edits.category = .entertainment

        try store(context).rememberCorrection(from: original, to: edits)

        #expect(try store(context).memory().rules == ["焼肉": .entertainment])
    }

    /// カテゴリを変えていない直し（金額やメモだけ）と、収入への直しは覚えない。収入を支出に直してカテゴリを選んだときは覚える。
    @Test func remembersOnlyCategoryChanges() throws {
        let context = try TestSupport.makeContext()
        let original = EntryEdits(amount: 850, isIncome: false, category: .food, memo: "ランチ", spentAt: TestSupport.now)
        var amountOnly = original
        amountOnly.amount = 900
        amountOnly.memo = "ランチ 社食"
        var toIncome = original
        toIncome.isIncome = true
        toIncome.category = .other

        #expect(try !store(context).rememberCorrection(from: original, to: amountOnly))
        #expect(try !store(context).rememberCorrection(from: original, to: toIncome))
        #expect(try rows(context).isEmpty)

        let income = EntryEdits(amount: 500, isIncome: true, category: .other, memo: "メルカリ", spentAt: TestSupport.now)
        var toExpense = income
        toExpense.isIncome = false
        toExpense.category = .other
        #expect(try store(context).rememberCorrection(from: income, to: toExpense))
        #expect(try store(context).memory().rules == ["メルカリ": .other])
    }

    @Test func listsRulesNewestFirstAndForgets() throws {
        let context = try TestSupport.makeContext()
        try store(context, now: Self.earlier).remember(item: "家賃", category: .other)
        try store(context).remember(item: "ユニクロ", category: .daily)
        // 知らないカテゴリの行（新しい版の端末から届いた）は一覧に出さない。
        let unknown = LearnedCategory(phrase: "ジム", category: .other, updatedAt: TestSupport.now)
        unknown.categoryRawValue = "fitness"
        context.insert(unknown)
        try context.save()

        #expect(try store(context).rules().map(\.phrase) == ["ユニクロ", "家賃"])
        #expect(try store(context).rules().map(\.category) == [.daily, .other])

        try store(context).forget(phrase: "ゆにくろ")
        #expect(try store(context).rules().map(\.phrase) == ["家賃"])

        try store(context).forgetAll()
        #expect(try rows(context).isEmpty)
    }

    /// 書き込めなければ巻き戻す（画面と保存先を食い違わせない）。
    @Test func rollsBackWhenSaveFails() throws {
        let context = try TestSupport.makeContext()
        var failing = store(context)
        failing.save = { _ in throw TestError() }

        #expect(throws: TestError.self) { try failing.remember(item: "ユニクロ", category: .other) }

        #expect(try rows(context).isEmpty)
    }
}
