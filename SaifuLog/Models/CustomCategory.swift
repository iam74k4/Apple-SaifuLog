import Foundation
import SaifuLogCore
import SwiftData

/// 利用者が作ったカテゴリの 1 行（名前・記号・色・並び）。docs/design.md §8 の作ったカテゴリの決め事。
///
/// 記録は ID だけを持つ（`EntryCategory.custom`。rawValue は「custom:」と ID）ので、名前や記号を変えても記録は書き換えない。
/// 記録（`Entry`）・予算（`Budget`）と同じく、最初から iCloud 同期（SwiftData + CloudKit）の制約に合わせる。すべてのプロパティに
/// 既定値を持たせ、一意制約も関係も持たせない。ID は作った端末で UUID から決めるので、iCloud で同じ ID の行が重なるのは同期の
/// 行き違いのときだけで、そのときは書き込んだ日時の新しい行を採る（`CustomCategoryStore.catalog()`）。
///
/// **項目はすべて CloudKit の暗号化フィールドにする**（`.allowsCloudEncryption`。理由は `Entry`）。名前は利用者が決めた家計の分け方で、
/// 家計の中身にあたるため。
@Model
final class CustomCategory {
    /// ID（UUID の小文字の文字列）。記録のカテゴリ（`EntryCategory.custom`）が指す。SwiftData の `id` と重ならない名前にする。
    @Attribute(.allowsCloudEncryption) var categoryID: String = ""
    /// 名前（`CategoryCatalog.validateName` で確かめた形）。
    @Attribute(.allowsCloudEncryption) var name: String = ""
    /// SF Symbols の名前（`CategoryCatalog.symbolChoices` から選ぶ）。
    @Attribute(.allowsCloudEncryption) var symbolName: String = "tag"
    /// 色の番号（`Palette.customCategoryChoices` の位置）。
    @Attribute(.allowsCloudEncryption) var colorIndex: Int = 0
    /// 並び（小さいほど前）。
    @Attribute(.allowsCloudEncryption) var sortOrder: Int = 0
    /// 作った日時。並びが同じときに前にする。
    @Attribute(.allowsCloudEncryption) var createdAt: Date = Date.now
    /// 最後に書いた日時。同じ ID の行が重なったときに、新しいほうを採る。
    @Attribute(.allowsCloudEncryption) var updatedAt: Date = Date.now

    init(categoryID: String, name: String, symbolName: String, colorIndex: Int, sortOrder: Int, createdAt: Date) {
        self.categoryID = categoryID
        self.name = name
        self.symbolName = symbolName
        self.colorIndex = colorIndex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var info: CustomCategoryInfo {
        CustomCategoryInfo(id: categoryID, name: name, symbolName: symbolName, colorIndex: colorIndex)
    }

    /// 並びの順に並べ、同じ ID の行が重なっていれば書き込んだ日時の新しい行を採る（iCloud の行き違い）。ID の空の行は除く。
    ///
    /// メインスレッドの外（CSV の書き出し）からも使えるよう、保存先の読み書き（`CustomCategoryStore`）とは分けて置く。
    static func resolved(_ rows: [CustomCategory]) -> [CustomCategory] {
        var latest: [String: CustomCategory] = [:]
        for row in rows where !row.categoryID.isEmpty {
            if let current = latest[row.categoryID], current.updatedAt >= row.updatedAt { continue }
            latest[row.categoryID] = row
        }
        return latest.values.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.categoryID < rhs.categoryID
        }
    }
}

extension CategoryCatalog {
    /// 保存した作ったカテゴリの行から一覧を作る（`CustomCategory.resolved` の順）。
    init(rows: [CustomCategory]) {
        self.init(customs: CustomCategory.resolved(rows).map(\.info))
    }
}

/// 作ったカテゴリの読み書き。保存に失敗したら変更を巻き戻し、呼び出し側に知らせる（`EntryStore`・`BudgetStore` と同じ）。
@MainActor
struct CustomCategoryStore {
    let context: ModelContext
    /// 変更を書き込む処理。テストで失敗させるために差し替えられるようにしている。
    var save: (ModelContext) throws -> Void = { try $0.save() }
    /// 作った日時・書いた日時の基準。テストで固定の日時にする。
    var now: () -> Date = { .now }
    /// 新しいカテゴリの ID を作る。テストで決めた ID にする。
    var makeID: () -> String = { UUID().uuidString.lowercased() }

    /// いまのカテゴリの一覧（作ったカテゴリは並びの順。同じ ID の行が重なっていれば、書き込んだ日時の新しい行を採る）。
    func catalog() throws -> CategoryCatalog {
        CategoryCatalog(rows: try context.fetch(FetchDescriptor<CustomCategory>()))
    }

    /// 作ったカテゴリの行（並びの順、重なりを除いたもの）。
    private func resolvedRows() throws -> [CustomCategory] {
        CustomCategory.resolved(try context.fetch(FetchDescriptor<CustomCategory>()))
    }

    /// カテゴリを作る。名前を確かめ（`CategoryCatalog.validateName`）、いちばん後ろに並べる。作ったカテゴリを返す。
    func create(name: String, symbolName: String, colorIndex: Int) throws -> EntryCategory {
        let catalog = try catalog()
        guard catalog.customs.count < CategoryCatalog.maximumCustomCount else { throw CustomCategoryError.tooMany }
        let validated = try catalog.validateName(name).get()
        let order = (try resolvedRows().map(\.sortOrder).max() ?? -1) + 1
        let row = CustomCategory(
            categoryID: makeID(), name: validated, symbolName: symbolName, colorIndex: colorIndex, sortOrder: order, createdAt: now()
        )
        context.insert(row)
        try commit()
        return .custom(row.categoryID)
    }

    /// 名前・記号・色を変える（記録は ID を指しているので書き換えない）。
    func update(_ category: EntryCategory, name: String, symbolName: String, colorIndex: Int) throws {
        guard let id = category.customID else { return }
        let validated = try catalog().validateName(name, editing: id).get()
        let rows = try context.fetch(FetchDescriptor<CustomCategory>()).filter { $0.categoryID == id }
        guard !rows.isEmpty else { throw CustomCategoryError.notFound }
        for row in rows {
            row.name = validated
            row.symbolName = symbolName
            row.colorIndex = colorIndex
            row.updatedAt = now()
        }
        try commit()
    }

    /// 並びを変える（`categories` の順に並べ直す）。
    func reorder(_ categories: [EntryCategory]) throws {
        let ids = categories.compactMap(\.customID)
        let rows = try context.fetch(FetchDescriptor<CustomCategory>())
        for row in rows {
            guard let index = ids.firstIndex(of: row.categoryID), row.sortOrder != index else { continue }
            row.sortOrder = index
            row.updatedAt = now()
        }
        try commit()
    }

    /// そのカテゴリの記録の件数（削除の確認に出す）。
    func entryCount(of category: EntryCategory) throws -> Int {
        let rawValue = category.rawValue
        return try context.fetchCount(FetchDescriptor<Entry>(predicate: #Predicate { $0.categoryRawValue == rawValue }))
    }

    /// カテゴリを消す。そのカテゴリの記録とくり返しの記録は「その他」にし、予算と覚えたカテゴリからも外してから、1 回で書き込む
    /// （一部だけ書かれて、消したカテゴリを指す記録が残らないように）。
    ///
    /// 記録を先に書き換えるのは、行を消しただけだと、記録が一覧に無いカテゴリ（名前は「その他」）を指したまま残り、月のまとめで
    /// 「その他」が 2 行に分かれるため。iCloud では書き換えた記録もほかの端末に届く。
    func delete(_ category: EntryCategory) throws {
        guard let id = category.customID else { return }
        let rawValue = category.rawValue
        // 読み込みが途中で失敗しても、書きかけの変更を残さないよう、すべて読めてから書き換える。
        let entries = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.categoryRawValue == rawValue }))
        let budgets = try context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.scopeRawValue == rawValue }))
        let memories = try context.fetch(FetchDescriptor<LearnedCategory>(predicate: #Predicate { $0.categoryRawValue == rawValue }))
        let rules = try context.fetch(FetchDescriptor<RecurringEntry>(predicate: #Predicate { $0.categoryRawValue == rawValue }))
        let categories = try context.fetch(FetchDescriptor<CustomCategory>(predicate: #Predicate { $0.categoryID == id }))
        for entry in entries {
            entry.category = .other
        }
        // 予算は行を消さずに 0（設定なし）を書く（`BudgetStore` と同じ考え方。ほかの端末の古い額が勝たないように）。
        for budget in budgets where budget.amount != 0 {
            budget.amount = 0
            budget.updatedAt = now()
        }
        for learned in memories {
            context.delete(learned)
        }
        // くり返しの記録も「その他」にする（次の月から、消したカテゴリで記録しないように）。
        for recurring in rules {
            recurring.category = .other
            recurring.updatedAt = now()
        }
        for row in categories {
            context.delete(row)
        }
        try commit {
            // rollback の後は保存先のカテゴリで探す。EntryStore.update と同じく、読み込み済みの行も元の値に戻す。
            _ = try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.categoryRawValue == rawValue }))
            _ = try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.scopeRawValue == rawValue }))
            _ = try? context.fetch(FetchDescriptor<LearnedCategory>(predicate: #Predicate { $0.categoryRawValue == rawValue }))
            _ = try? context.fetch(FetchDescriptor<RecurringEntry>(predicate: #Predicate { $0.categoryRawValue == rawValue }))
        }
    }

    /// 書き込めなかった変更は取り消す（EntryStore と同じ理由。画面と保存先を食い違わせないため）。
    private func commit(afterRollback: () -> Void = {}) throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            // iOS 26 では rollback だけだと、画面が持つ名前や並びが変更後のまま残る。保存済みの値を読み直す。
            _ = try? context.fetch(FetchDescriptor<CustomCategory>())
            afterRollback()
            throw error
        }
    }
}

/// 作ったカテゴリの読み書きの失敗（名前の確かめは `CategoryNameIssue`）。
enum CustomCategoryError: Error, Equatable {
    /// 作れる数（`CategoryCatalog.maximumCustomCount`）に届いている。
    case tooMany
    /// 変えようとしたカテゴリが無い（ほかの端末で消した）。
    case notFound
}
