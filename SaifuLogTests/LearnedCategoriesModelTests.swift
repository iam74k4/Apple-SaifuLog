import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 設定の「覚えたカテゴリ」（`LearnedCategoriesModel`）。一覧・カテゴリを変える・忘れる・すべて忘れる・書き込みの失敗を確かめる。
@MainActor
struct LearnedCategoriesModelTests {
    private func makeModel(
        _ context: ModelContext, failsSave: @escaping () -> Bool = { false }
    ) -> (model: LearnedCategoriesModel, announcements: () -> [String]) {
        var announcements: [String] = []
        var store = LearnedCategoryStore(context: context, now: { TestSupport.now })
        store.save = { context in
            if failsSave() { throw TestError() }
            try context.save()
        }
        let model = LearnedCategoriesModel(store: store, announce: { announcements.append($0) })
        return (model, { announcements })
    }

    @Test func listsRulesAndChangesCategory() throws {
        let context = try TestSupport.makeContext()
        try LearnedCategoryStore(context: context, now: { TestSupport.now }).remember(item: "ユニクロ", category: .other)
        let (model, announcements) = makeModel(context)

        #expect(model.rules.map(\.phrase) == ["ユニクロ"])

        model.change(try #require(model.rules.first), to: .daily)

        #expect(model.rules.map(\.category) == [.daily])
        #expect(try LearnedCategoryStore(context: context).memory().rules == ["ユニクロ": .daily])
        #expect(announcements().last?.contains("ユニクロ") == true)
    }

    @Test func forgetsOneAndAll() throws {
        let context = try TestSupport.makeContext()
        let store = LearnedCategoryStore(context: context, now: { TestSupport.now })
        try store.remember(item: "ユニクロ", category: .other)
        try store.remember(item: "ジム", category: .entertainment)
        let (model, _) = makeModel(context)

        model.forget(try #require(model.rules.first { $0.phrase == "ジム" }))
        #expect(model.rules.map(\.phrase) == ["ユニクロ"])

        model.forgetAll()
        #expect(model.rules.isEmpty)
        #expect(try store.memory().rules.isEmpty)
    }

    /// 書き込めなければ知らせ、一覧は変えない（変更は巻き戻してある）。
    @Test func reportsSaveFailure() throws {
        let context = try TestSupport.makeContext()
        try LearnedCategoryStore(context: context, now: { TestSupport.now }).remember(item: "ユニクロ", category: .other)
        var fails = false
        let (model, _) = makeModel(context, failsSave: { fails })
        fails = true

        model.change(try #require(model.rules.first), to: .daily)

        #expect(model.failure == .save)
        #expect(model.rules.map(\.category) == [.other])
    }
}
