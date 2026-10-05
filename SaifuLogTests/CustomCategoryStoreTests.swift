import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 作ったカテゴリの読み書き（`CustomCategoryStore`）。作る・直す・並べ替える・削除する（記録は「その他」に、予算は 0 に、
/// 覚えたカテゴリからも外す）と、iCloud の行き違いで同じ ID の行が重なったときの採り方。
@MainActor
struct CustomCategoryStoreTests {
    /// 保存先と、決めた ID・固定の日時で作る読み書き。
    @MainActor
    final class Fixture {
        let context: ModelContext
        var now = TestSupport.now
        var failsSave = false
        private var nextID = 0
        private(set) var store: CustomCategoryStore!

        init(context: ModelContext? = nil) throws {
            self.context = try context ?? TestSupport.makeContext()
            var store = CustomCategoryStore(context: self.context)
            store.now = { [unowned self] in now }
            store.makeID = { [unowned self] in
                nextID += 1
                return "id-\(nextID)"
            }
            store.save = { [unowned self] context in
                if failsSave { throw TestError() }
                try context.save()
            }
            self.store = store
        }
    }

    // MARK: - 作る

    /// 作ったカテゴリは ID を指すカテゴリで返り、作った順に一覧の後ろ（「その他」の前）に並ぶ。名前の前後の空白は落とす。
    @Test func createAppendsInOrder() throws {
        let fixture = try Fixture()

        let clothes = try fixture.store.create(name: " 衣服 ", symbolName: "tshirt", colorIndex: 2)
        let housing = try fixture.store.create(name: "住居", symbolName: "house", colorIndex: 0)

        #expect(clothes == .custom("id-1"))
        #expect(housing == .custom("id-2"))
        let catalog = try fixture.store.catalog()
        #expect(catalog.customs == [
            CustomCategoryInfo(id: "id-1", name: "衣服", symbolName: "tshirt", colorIndex: 2),
            CustomCategoryInfo(id: "id-2", name: "住居", symbolName: "house", colorIndex: 0),
        ])
        #expect(catalog.all.suffix(3) == [clothes, housing, .other])
    }

    /// 空の名前・長すぎる名前・同じ名前（作ったカテゴリも組み込みのカテゴリも。大文字小文字と全角半角は同じとみなす）は作らない。
    @Test func createRejectsInvalidNames() throws {
        let fixture = try Fixture()
        _ = try fixture.store.create(name: "Gym", symbolName: "dumbbell", colorIndex: 0)

        #expect(throws: CategoryNameIssue.empty) { try fixture.store.create(name: "  ", symbolName: "tag", colorIndex: 0) }
        #expect(throws: CategoryNameIssue.tooLong) {
            try fixture.store.create(name: String(repeating: "あ", count: CategoryCatalog.maximumNameLength + 1), symbolName: "tag", colorIndex: 0)
        }
        #expect(throws: CategoryNameIssue.duplicate) { try fixture.store.create(name: "ｇｙｍ", symbolName: "tag", colorIndex: 0) }
        #expect(throws: CategoryNameIssue.duplicate) { try fixture.store.create(name: "食費", symbolName: "tag", colorIndex: 0) }
        #expect(try fixture.store.catalog().customs.count == 1)
    }

    /// 作れる数を超えては作らない。
    @Test func createStopsAtMaximum() throws {
        let fixture = try Fixture()
        for index in 0..<CategoryCatalog.maximumCustomCount {
            _ = try fixture.store.create(name: "分類\(index)", symbolName: "tag", colorIndex: 0)
        }

        #expect(throws: CustomCategoryError.tooMany) { try fixture.store.create(name: "もう一つ", symbolName: "tag", colorIndex: 0) }
        #expect(try fixture.store.catalog().customs.count == CategoryCatalog.maximumCustomCount)
    }

    /// 書き込めなければ巻き戻す（一覧に残らない）。
    @Test func createFailureRollsBack() throws {
        let fixture = try Fixture()
        fixture.failsSave = true

        #expect(throws: TestError.self) { try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0) }
        #expect(try fixture.store.catalog().customs.isEmpty)
    }

    // MARK: - 直す

    /// 名前・記号・色を変えても、記録は ID を指したまま（書き換えない）で、新しい名前で読める。自分の名前のままでも保存できる。
    @Test func updateKeepsEntriesPointingToCategory() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let entry = TestSupport.entry(amount: 3000, category: clothes)
        fixture.context.insert(entry)
        try fixture.context.save()
        fixture.now = TestSupport.now.addingTimeInterval(60)

        try fixture.store.update(clothes, name: "服", symbolName: "bag", colorIndex: 4)
        try fixture.store.update(clothes, name: "服", symbolName: "bag", colorIndex: 5)

        let catalog = try fixture.store.catalog()
        #expect(catalog.info(for: clothes) == CustomCategoryInfo(id: "id-1", name: "服", symbolName: "bag", colorIndex: 5))
        #expect(entry.category == clothes)
        #expect(catalog.name(of: entry.category) == "服")
        let row = try #require(try fixture.context.fetch(FetchDescriptor<CustomCategory>()).first)
        #expect(row.updatedAt == fixture.now)
    }

    /// ほかのカテゴリと同じ名前には直さない。消えたカテゴリは直せない。
    @Test func updateRejectsDuplicateAndMissing() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        _ = try fixture.store.create(name: "住居", symbolName: "house", colorIndex: 0)

        #expect(throws: CategoryNameIssue.duplicate) { try fixture.store.update(clothes, name: "住居", symbolName: "tag", colorIndex: 0) }
        #expect(throws: CustomCategoryError.notFound) { try fixture.store.update(.custom("gone"), name: "旅行", symbolName: "tag", colorIndex: 0) }
        #expect(try fixture.store.catalog().name(of: clothes) == "衣服")
    }

    /// 一覧を読み直す前でも、保存できなかった名前・記号・色が画面に残らない。
    @Test func updateFailureRestoresLoadedRows() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let row = try #require(try fixture.context.fetch(FetchDescriptor<CustomCategory>()).first)
        fixture.now = TestSupport.now.addingTimeInterval(60)
        fixture.failsSave = true

        #expect(throws: TestError.self) {
            try fixture.store.update(clothes, name: "服", symbolName: "bag", colorIndex: 4)
        }

        #expect(row.info == CustomCategoryInfo(id: "id-1", name: "衣服", symbolName: "tshirt", colorIndex: 0))
        #expect(row.updatedAt == TestSupport.now)
        #expect(!fixture.context.hasChanges)
    }

    // MARK: - 並べ替える

    @Test func reorderChangesOrder() throws {
        let fixture = try Fixture()
        let first = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let second = try fixture.store.create(name: "住居", symbolName: "house", colorIndex: 0)
        let third = try fixture.store.create(name: "美容", symbolName: "scissors", colorIndex: 0)

        try fixture.store.reorder([third, first, second])

        #expect(try fixture.store.catalog().customs.map(\.category) == [third, first, second])
        // 並べ替えた後に作ったカテゴリも後ろに並ぶ。
        let fourth = try fixture.store.create(name: "旅行", symbolName: "airplane", colorIndex: 0)
        #expect(try fixture.store.catalog().customs.map(\.category) == [third, first, second, fourth])
    }

    @Test func reorderFailureRestoresLoadedRows() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let housing = try fixture.store.create(name: "住居", symbolName: "house", colorIndex: 0)
        let rows = try fixture.context.fetch(FetchDescriptor<CustomCategory>(sortBy: [SortDescriptor(\.sortOrder)]))
        fixture.now = TestSupport.now.addingTimeInterval(60)
        fixture.failsSave = true

        #expect(throws: TestError.self) { try fixture.store.reorder([housing, clothes]) }

        #expect(rows.map(\.sortOrder) == [0, 1])
        #expect(rows.allSatisfy { $0.updatedAt == TestSupport.now })
        #expect(!fixture.context.hasChanges)
    }

    // MARK: - 削除する

    /// 削除すると、そのカテゴリの記録は「その他」になり、カテゴリ別の予算は 0（設定なし）に、覚えたカテゴリからも外れる。
    /// ほかのカテゴリの記録・予算・覚えには触れない。
    @Test func deleteMovesEntriesToOtherAndClearsBudgetsAndMemory() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let housing = try fixture.store.create(name: "住居", symbolName: "house", colorIndex: 0)
        let clothesEntry = TestSupport.entry(amount: 3000, category: clothes)
        let housingEntry = TestSupport.entry(amount: 80000, category: housing)
        let foodEntry = TestSupport.entry(amount: 850, category: .food)
        fixture.context.insert(clothesEntry)
        fixture.context.insert(housingEntry)
        fixture.context.insert(foodEntry)
        try fixture.context.save()
        let budgets = BudgetStore(context: fixture.context, now: { TestSupport.now })
        try budgets.setAmounts([.category(clothes): 10_000, .category(housing): 80_000, .category(.food): 30_000])
        let learned = LearnedCategoryStore(context: fixture.context, now: { TestSupport.now })
        try learned.remember(item: "ユニクロ", category: clothes)
        try learned.remember(item: "家賃", category: housing)
        #expect(try fixture.store.entryCount(of: clothes) == 1)
        fixture.now = TestSupport.now.addingTimeInterval(60)

        try fixture.store.delete(clothes)

        #expect(clothesEntry.category == .other)
        #expect(housingEntry.category == housing)
        #expect(foodEntry.category == .food)
        #expect(try fixture.store.entryCount(of: clothes) == 0)
        let plan = try budgets.plan()
        #expect(plan.byCategory[clothes] == nil)
        #expect(plan.byCategory[housing] == 80_000)
        #expect(plan.byCategory[.food] == 30_000)
        #expect(try learned.memory().rules == ["家賃": housing])
        #expect(try fixture.store.catalog().customs.map(\.category) == [housing])
    }

    /// 書き込めなければ、記録もカテゴリも元のまま（一部だけ消えて、消したカテゴリを指す記録が残らないように）。
    @Test(arguments: [false, true])
    func deleteFailureRollsBackEverything(usesFileStore: Bool) throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)
        let container = try usesFileStore
            ? ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
            : ModelContainerFactory.makeInMemoryContainer()
        let fixture = try Fixture(context: container.mainContext)
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let entry = TestSupport.entry(amount: 3000, category: clothes)
        let budget = Budget(scope: .category(clothes), amount: 10_000, updatedAt: TestSupport.now)
        let learned = LearnedCategory(phrase: "ユニクロ", category: clothes, updatedAt: TestSupport.now)
        let recurring = RecurringEntry(
            recurrenceID: "clothes", draft: RecurringDraft(amount: 3000, memo: "衣服", isIncome: false, category: clothes, dayOfMonth: 1),
            startMonth: RecurringMonth(year: 2026, month: 10), createdAt: TestSupport.now
        )
        fixture.context.insert(entry)
        fixture.context.insert(budget)
        fixture.context.insert(learned)
        fixture.context.insert(recurring)
        try fixture.context.save()
        fixture.now = TestSupport.now.addingTimeInterval(60)
        fixture.failsSave = true

        #expect(throws: TestError.self) { try fixture.store.delete(clothes) }

        // fetch で偶然直る前に、画面が持っている行そのものを確かめる。
        #expect(entry.category == clothes)
        #expect(budget.amount == 10_000)
        #expect(budget.updatedAt == TestSupport.now)
        #expect(recurring.category == clothes)
        #expect(recurring.updatedAt == TestSupport.now)
        #expect(!fixture.context.hasChanges)
        #expect(try LearnedCategoryStore(context: fixture.context).memory().rules == ["ユニクロ": clothes])
        #expect(try fixture.store.catalog().customs.map(\.category) == [clothes])

        // 別の操作による次の保存でも、失敗した削除が紛れ込まない。ファイルを開き直しても全項目が残る。
        fixture.context.insert(TestSupport.entry(amount: 850, category: .food))
        try fixture.context.save()
        let reopened = try usesFileStore
            ? ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
            : container
        let saved = ModelContext(reopened)
        #expect(try saved.fetch(FetchDescriptor<Entry>()).filter { $0.category == clothes }.count == 1)
        #expect(try BudgetStore(context: saved).plan().byCategory[clothes] == 10_000)
        #expect(try LearnedCategoryStore(context: saved).memory().rules == ["ユニクロ": clothes])
        #expect(try RecurringEntryStore(context: saved).rules().first?.category == clothes)
        #expect(try CustomCategoryStore(context: saved).catalog().customs.map(\.category) == [clothes])
    }

    // MARK: - iCloud の行き違い

    /// 同じ ID の行が重なったら（ほかの端末で同時に直したなど）、書き込んだ日時の新しい行を採る。ID の空の行は無視する。
    @Test func catalogResolvesDuplicateRowsByLatestUpdate() throws {
        let fixture = try Fixture()
        let older = CustomCategory(categoryID: "same", name: "服", symbolName: "tag", colorIndex: 0, sortOrder: 0, createdAt: TestSupport.now)
        let newer = CustomCategory(categoryID: "same", name: "衣服", symbolName: "tshirt", colorIndex: 3, sortOrder: 0, createdAt: TestSupport.now)
        newer.updatedAt = TestSupport.now.addingTimeInterval(60)
        let empty = CustomCategory(categoryID: "", name: "空", symbolName: "tag", colorIndex: 0, sortOrder: 0, createdAt: TestSupport.now)
        fixture.context.insert(older)
        fixture.context.insert(newer)
        fixture.context.insert(empty)
        try fixture.context.save()

        #expect(try fixture.store.catalog().customs == [CustomCategoryInfo(id: "same", name: "衣服", symbolName: "tshirt", colorIndex: 3)])

        // 直すと重なった行の両方を書き換える（どちらを読んでも同じ名前になるように）。
        try fixture.store.update(.custom("same"), name: "洋服", symbolName: "tshirt", colorIndex: 3)
        #expect(older.name == "洋服")
        #expect(newer.name == "洋服")
    }

    /// 一覧に無い（ほかの端末で消した）カテゴリを指す記録は、名前を「その他」として読む。
    @Test func unknownCustomCategoryReadsAsOther() throws {
        let fixture = try Fixture()

        let catalog = try fixture.store.catalog()

        #expect(catalog.name(of: .custom("gone")) == EntryCategory.other.displayName)
        #expect(!catalog.contains(.custom("gone")))
    }
}
