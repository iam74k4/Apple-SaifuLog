import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// カテゴリを作る・直す画面（`CategoryEditorModel`）と、設定の「カテゴリ」の一覧（`CategoryListModel`）。
@MainActor
struct CategoryEditorModelTests {
    /// 保存先と、読み上げ・保存できたカテゴリを集める。
    @MainActor
    final class Fixture {
        let context: ModelContext
        var failsSave = false
        private(set) var announcements: [String] = []
        private(set) var saved: [EntryCategory] = []
        private(set) var store: CustomCategoryStore!

        init() throws {
            context = try TestSupport.makeContext()
            var store = CustomCategoryStore(context: context, now: { TestSupport.now })
            store.save = { [unowned self] context in
                if failsSave { throw TestError() }
                try context.save()
            }
            self.store = store
        }

        func editor(_ mode: CategoryEditorModel.Mode) throws -> CategoryEditorModel {
            CategoryEditorModel(
                mode: mode, store: store, catalog: try store.catalog(),
                announce: { [unowned self] in announcements.append($0) },
                didSave: { [unowned self] in saved.append($0) }
            )
        }

        func list() -> CategoryListModel {
            CategoryListModel(
                store: store, categories: CategoryCatalogModel(store: store),
                announce: { [unowned self] in announcements.append($0) }
            )
        }
    }

    // MARK: - 作る

    /// 名前を入れて保存すると作り、作ったカテゴリを渡して読み上げる。
    @Test func createSavesAndAnnounces() throws {
        let fixture = try Fixture()
        let editor = try fixture.editor(.create)
        #expect(!editor.canSave)

        editor.name = "衣服"
        editor.symbolName = "tshirt"
        editor.colorIndex = 4
        #expect(editor.canSave)
        #expect(editor.save())

        let category = try #require(fixture.saved.first)
        #expect(try fixture.store.catalog().info(for: category)?.name == "衣服")
        #expect(try fixture.store.catalog().info(for: category)?.symbolName == "tshirt")
        #expect(try fixture.store.catalog().info(for: category)?.colorIndex == 4)
        #expect(fixture.announcements == ["カテゴリ「衣服」を作りました"])
    }

    /// 使えない名前は保存せず、理由を出す。直し始めたら理由を消す。
    @Test func createShowsNameIssue() throws {
        let fixture = try Fixture()
        let editor = try fixture.editor(.create)

        editor.name = "食費"
        #expect(!editor.save())
        #expect(editor.issue == .duplicate)
        #expect(fixture.saved.isEmpty)

        editor.name = "衣服"
        #expect(editor.issue == nil)
    }

    /// 書き込めなければアラートを出し、閉じない。
    @Test func createFailureShowsAlert() throws {
        let fixture = try Fixture()
        let editor = try fixture.editor(.create)
        fixture.failsSave = true

        editor.name = "衣服"
        #expect(!editor.save())
        #expect(editor.showsSaveFailure)
        #expect(fixture.saved.isEmpty)
        #expect(fixture.announcements.isEmpty)
    }

    /// 候補は、まだ無い名前だけを出す。選ぶと名前と記号を入れる。色は作った数の次の色から始める。
    @Test func presetsSkipExistingNames() throws {
        let fixture = try Fixture()
        _ = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let editor = try fixture.editor(.create)

        #expect(!editor.availablePresets.map(\.name).contains("衣服"))
        #expect(editor.availablePresets.map(\.name).contains("住居"))
        #expect(editor.colorIndex == 1)

        editor.choosePreset(name: "住居", symbolName: "house")
        #expect(editor.name == "住居")
        #expect(editor.symbolName == "house")
    }

    // MARK: - 直す

    /// 直すときは今の名前・記号・色を入れて開き、候補は出さない。保存すると直して読み上げる。
    @Test func editPrefillsAndUpdates() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 2)
        let editor = try fixture.editor(.edit(clothes))

        #expect(editor.name == "衣服")
        #expect(editor.symbolName == "tshirt")
        #expect(editor.colorIndex == 2)
        #expect(editor.availablePresets.isEmpty)

        editor.name = "服"
        #expect(editor.save())
        #expect(try fixture.store.catalog().name(of: clothes) == "服")
        #expect(fixture.saved == [clothes])
        #expect(fixture.announcements == ["カテゴリ「服」を直しました"])
    }

    // MARK: - 設定の一覧

    /// 一覧から作ると、同じ一覧（ホームと共有するもの）を読み直す。
    @Test func listCreatesAndReloads() throws {
        let fixture = try Fixture()
        let list = fixture.list()
        #expect(list.customs.isEmpty)
        #expect(list.canCreate)

        list.presentCreation()
        let editor = try #require(list.editor)
        editor.name = "衣服"
        #expect(editor.save())

        #expect(list.customs.map(\.name) == ["衣服"])
    }

    /// 組み込みのカテゴリは直せない（シートを出さない）。作ったカテゴリは直せる。
    @Test func listEditsOnlyCustomCategories() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let list = fixture.list()

        list.presentEditing(.food)
        #expect(list.editor == nil)
        list.presentEditing(clothes)
        #expect(list.editor?.mode == .edit(clothes))
    }

    /// 削除の確認には記録の件数を出し、「削除」で記録を「その他」にして一覧から外し、読み上げる。
    @Test func listDeletesAfterConfirmation() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let entries = [TestSupport.entry(amount: 3000, category: clothes), TestSupport.entry(amount: 5000, category: clothes)]
        entries.forEach(fixture.context.insert)
        try fixture.context.save()
        let list = fixture.list()

        list.requestDeletion(clothes)
        let deletion = try #require(list.pendingDeletion)
        #expect(deletion.name == "衣服")
        #expect(deletion.entryCount == 2)

        list.confirmDeletion(deletion)

        #expect(list.pendingDeletion == nil)
        #expect(list.customs.isEmpty)
        #expect(entries.allSatisfy { $0.category == .other })
        #expect(fixture.announcements.last == "カテゴリ「衣服」を削除しました")
    }

    /// 削除を書き込めなければ知らせ、一覧は元のまま。
    @Test func listDeleteFailureShowsAlert() throws {
        let fixture = try Fixture()
        let clothes = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let list = fixture.list()
        list.requestDeletion(clothes)
        let deletion = try #require(list.pendingDeletion)
        fixture.failsSave = true

        list.confirmDeletion(deletion)

        #expect(list.failure == .save)
        #expect(list.customs.map(\.category) == [clothes])
    }

    /// ドラッグと VoiceOver の操作で並べ替え、VoiceOver には動かした後の位置を読み上げる。端では動かさない。
    @Test func listReorders() throws {
        let fixture = try Fixture()
        let first = try fixture.store.create(name: "衣服", symbolName: "tshirt", colorIndex: 0)
        let second = try fixture.store.create(name: "住居", symbolName: "house", colorIndex: 0)
        let third = try fixture.store.create(name: "美容", symbolName: "scissors", colorIndex: 0)
        let list = fixture.list()

        list.move(fromOffsets: [2], toOffset: 0)
        #expect(list.customs.map(\.category) == [third, first, second])

        list.moveLater(third)
        #expect(list.customs.map(\.category) == [first, third, second])
        #expect(fixture.announcements.last == "2 番目にしました")

        list.moveEarlier(third)
        #expect(list.customs.map(\.category) == [third, first, second])
        #expect(fixture.announcements.last == "1 番目にしました")

        let count = fixture.announcements.count
        list.moveEarlier(third)
        list.moveLater(second)
        #expect(list.customs.map(\.category) == [third, first, second])
        #expect(fixture.announcements.count == count)
    }

    /// 作れる数に届いたら、作るシートを出さない。
    @Test func listStopsCreatingAtMaximum() throws {
        let fixture = try Fixture()
        for index in 0..<CategoryCatalog.maximumCustomCount {
            _ = try fixture.store.create(name: "分類\(index)", symbolName: "tag", colorIndex: 0)
        }
        let list = fixture.list()

        #expect(!list.canCreate)
        list.presentCreation()
        #expect(list.editor == nil)
    }
}
