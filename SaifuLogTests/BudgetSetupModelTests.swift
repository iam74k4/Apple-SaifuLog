import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 「予算を決める」の状態と操作（BudgetSetupModel）。メモリの上の保存先で確かめる。
@MainActor
struct BudgetSetupModelTests {
    /// BudgetSetupModel と、その保存先・読み上げの代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        /// true の間は保存（書き込み）が失敗する。
        var failsSave = false
        var now = TestSupport.now
        private(set) var announcements: [String] = []

        init() throws {
            context = try TestSupport.makeContext()
        }

        var store: BudgetStore {
            var store = BudgetStore(context: context)
            store.save = { [unowned self] context in
                if failsSave { throw TestError() }
                try context.save()
            }
            store.now = { [unowned self] in now }
            return store
        }

        func makeModel(showsCategoryBudgets: Bool = false) -> BudgetSetupModel {
            BudgetSetupModel(store: store, showsCategoryBudgets: showsCategoryBudgets, announce: { [unowned self] in
                announcements.append($0)
            })
        }

        func plan() throws -> BudgetPlan {
            try store.plan()
        }

        func rows() throws -> [Budget] {
            try context.fetch(FetchDescriptor<Budget>())
        }
    }

    @Test func startsEmptyWithoutBudget() throws {
        let fixture = try Fixture()

        let model = fixture.makeModel()

        #expect(model.totalText.isEmpty)
        #expect(model.totalAmount == 0)
        #expect(!model.canSave)
        #expect(!model.hadTotalBudget)
        #expect(!model.showsCategoryBudgets)
    }

    /// 予算を変えるときも同じ画面を使う。いまの予算を入力欄に入れて開く。
    @Test func startsWithCurrentBudget() throws {
        let fixture = try Fixture()
        try fixture.store.setAmounts([.total: 150_000, .category(.food): 40_000])

        let model = fixture.makeModel()

        #expect(model.totalText == "150,000")
        #expect(model.hadTotalBudget)
        #expect(model.canSave)
        #expect(model.categoryTexts[.food] == "40,000")
        #expect(model.categoryTexts[.cafe] == "")
    }

    /// 入力欄は 3 桁ごとにカンマを入れて見せ、8 桁を超えた数字は捨てる。
    @Test func normalizesTypedText() throws {
        let model = try Fixture().makeModel()

        model.totalText = "150000"
        model.normalizeTotalText()
        #expect(model.totalText == "150,000")
        #expect(model.totalAmount == 150_000)

        model.totalText = "12,345,6789"
        model.normalizeTotalText()
        #expect(model.totalText == "12,345,678")

        model.categoryTexts[.food] = "４００００"
        model.normalizeCategoryText(.food)
        #expect(model.categoryTexts[.food] == "40,000")
    }

    @Test func quickAmountFillsField() throws {
        let model = try Fixture().makeModel()

        model.selectQuickAmount(150_000)

        #expect(model.totalText == "150,000")
        #expect(model.isSelected(quickAmount: 150_000))
        #expect(!model.isSelected(quickAmount: 100_000))
        #expect(model.canSave)
    }

    @Test func saveWritesTotalBudget() throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        model.totalText = "180,000"

        #expect(model.save())

        #expect(try fixture.plan() == BudgetPlan(total: 180_000))
        #expect(!model.showsSaveFailure)
        // 決めた額を VoiceOver に読み上げる。
        #expect(fixture.announcements.count == 1)
        #expect(fixture.announcements.first?.contains("¥180,000") == true)
    }

    /// 0 円の予算は決められない（何も書き込まない）。
    @Test func cannotSaveZero() throws {
        let fixture = try Fixture()
        let model = fixture.makeModel()
        model.totalText = "0"

        #expect(!model.canSave)
        #expect(!model.save())

        #expect(try fixture.rows().isEmpty)
        #expect(fixture.announcements.isEmpty)
    }

    /// 保存に失敗したら閉じずに知らせる（決めたつもりにさせない）。前の予算はそのまま。
    @Test func saveFailureKeepsPreviousBudget() throws {
        let fixture = try Fixture()
        try fixture.store.setAmount(150_000, for: .total)
        let model = fixture.makeModel()
        fixture.failsSave = true
        model.totalText = "200,000"

        #expect(!model.save())

        #expect(model.showsSaveFailure)
        #expect(!fixture.context.hasChanges)
        #expect(try fixture.plan().total == 150_000)
        #expect(fixture.announcements.isEmpty)
        // 入力は残し、もう一度保存できるようにする。
        #expect(model.totalText == "200,000")
    }

    /// 変えていない対象は書き込まない（iCloud で別の端末が決めた額を、書き込んだ日時で上書きしないように）。
    @Test func saveWritesOnlyChangedScopes() throws {
        let fixture = try Fixture()
        fixture.now = TestSupport.date(2026, 9, 1)
        try fixture.store.setAmounts([.total: 150_000, .category(.food): 40_000])
        fixture.now = TestSupport.now
        let model = fixture.makeModel(showsCategoryBudgets: true)
        model.categoryTexts[.cafe] = "5,000"

        #expect(model.save())

        let rows = try fixture.rows()
        #expect(rows.first { $0.scopeRawValue == "total" }?.updatedAt == TestSupport.date(2026, 9, 1))
        #expect(rows.first { $0.scopeRawValue == "food" }?.updatedAt == TestSupport.date(2026, 9, 1))
        #expect(rows.first { $0.scopeRawValue == "cafe" }?.updatedAt == TestSupport.now)
        #expect(try fixture.plan() == BudgetPlan(total: 150_000, byCategory: [.food: 40_000, .cafe: 5_000]))
    }

    /// カテゴリ別の予算はプレミアム。欄を出していなければ、入力があっても書き込まない。
    @Test func categoryBudgetsIgnoredWhenHidden() throws {
        let fixture = try Fixture()
        let model = fixture.makeModel(showsCategoryBudgets: false)
        model.totalText = "150,000"
        model.categoryTexts[.food] = "40,000"

        #expect(model.save())

        #expect(try fixture.plan() == BudgetPlan(total: 150_000))
    }

    /// カテゴリの欄を空けると、そのカテゴリは設定なし（0 を書く）。
    @Test func clearingCategoryUnsetsIt() throws {
        let fixture = try Fixture()
        try fixture.store.setAmounts([.total: 150_000, .category(.food): 40_000])
        let model = fixture.makeModel(showsCategoryBudgets: true)
        model.categoryTexts[.food] = ""

        #expect(model.save())

        #expect(try fixture.plan() == BudgetPlan(total: 150_000))
        #expect(try fixture.rows().first { $0.scopeRawValue == "food" }?.amount == 0)
    }

    /// 予算をなくすと、全体の予算を設定なし（0）にする。カテゴリ別の予算は残す。
    @Test func removeTotalBudget() throws {
        let fixture = try Fixture()
        try fixture.store.setAmounts([.total: 150_000, .category(.food): 40_000])
        let model = fixture.makeModel()

        #expect(model.removeTotalBudget())

        #expect(try fixture.plan() == BudgetPlan(byCategory: [.food: 40_000]))
        #expect(model.totalText.isEmpty)
        #expect(fixture.announcements.last == String(localized: "予算をなくしました"))
    }

    @Test func removeFailureKeepsBudget() throws {
        let fixture = try Fixture()
        try fixture.store.setAmount(150_000, for: .total)
        let model = fixture.makeModel()
        fixture.failsSave = true

        #expect(!model.removeTotalBudget())

        #expect(model.showsSaveFailure)
        #expect(model.totalText == "150,000")
        #expect(try fixture.plan().total == 150_000)
    }
}
