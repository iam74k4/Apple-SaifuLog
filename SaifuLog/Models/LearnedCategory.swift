import Foundation
import SaifuLogCore
import SwiftData

/// 覚えたカテゴリの 1 行（修正の記憶。「この言葉はこのカテゴリ」）。docs/design.md §3-2・§5-2 の「覚えた修正」。
///
/// ⑥ でカテゴリを直したときと、「その他」になった記録の返事でカテゴリを選んだとき（聞き返し）に書き、次から同じ言葉の記録を
/// そのカテゴリにする（当て方はコアの `CategoryMemory`）。
///
/// 記録（`Entry`）・予算（`Budget`）と同じく、最初から iCloud 同期（SwiftData + CloudKit）の制約に合わせる。すべてのプロパティに
/// 既定値を持たせ、一意制約も関係も持たせない。一意制約が無いので、iCloud で同じ言葉の行が重なることがある。どの行を採るかは
/// `CategoryMemory.resolve`（書いた日時の新しいもの）が決め、書くとき（`LearnedCategoryStore`）は同じ言葉の行を 1 つに片づける。
///
/// **項目はすべて CloudKit の暗号化フィールドにする**（`.allowsCloudEncryption`。理由は `Entry`）。言葉は利用者が記録した品目や
/// 店名そのもので、家計の中身にあたるため。
@Model
final class LearnedCategory {
    /// 覚えた言葉（`CategoryMemory.key(for:)` でそろえた品目）。
    @Attribute(.allowsCloudEncryption) var phrase: String = ""
    /// カテゴリの rawValue（`EntryCategory`）。記録のカテゴリと同じく文字列で持つ。
    @Attribute(.allowsCloudEncryption) var categoryRawValue: String = EntryCategory.other.rawValue
    /// 最後に書いた日時。同じ言葉の行が複数あるときは、これが新しいものを採る。
    @Attribute(.allowsCloudEncryption) var updatedAt: Date = Date.now

    init(phrase: String, category: EntryCategory, updatedAt: Date) {
        self.phrase = phrase
        self.categoryRawValue = category.rawValue
        self.updatedAt = updatedAt
    }

    /// カテゴリ。知らない値（新しい版で足したカテゴリが iCloud で届いたときなど）は nil。
    var category: EntryCategory? {
        EntryCategory(rawValue: categoryRawValue)
    }
}

/// 覚えの決め方（SaifuLogCore の CategoryMemory.resolve）にそのまま渡せるようにする。
extension LearnedCategory: LearnedCategoryRecord {}

/// 覚えたカテゴリの読み書き。保存に失敗したら変更を巻き戻し、呼び出し側に知らせる（`EntryStore`・`BudgetStore` と同じ）。
@MainActor
struct LearnedCategoryStore {
    let context: ModelContext
    /// 変更を書き込む処理。テストで失敗させるために差し替えられるようにしている。
    var save: (ModelContext) throws -> Void = { try $0.save() }
    /// 書いた日時（`LearnedCategory.updatedAt`）の基準。テストで固定の日時にする。
    var now: () -> Date = { .now }

    /// いま使う覚え。
    func memory() throws -> CategoryMemory {
        CategoryMemory.resolve(try context.fetch(FetchDescriptor<LearnedCategory>()))
    }

    /// 覚えた言葉の一覧（設定の「覚えたカテゴリ」）。同じ言葉は 1 つにまとめ（`CategoryMemory.resolve` と同じ行を採る）、
    /// 新しく覚えた順に並べる。知らないカテゴリの行は出さない。
    func rules() throws -> [Rule] {
        let rows = try context.fetch(FetchDescriptor<LearnedCategory>())
        let groups = Dictionary(grouping: rows) { CategoryMemory.key(for: $0.phrase) ?? "" }
        return groups.compactMap { key, rows -> Rule? in
            guard !key.isEmpty, let row = CategoryMemory.preferred(rows), let category = row.category else { return nil }
            return Rule(phrase: key, category: category, updatedAt: row.updatedAt)
        }
        .sorted { lhs, rhs in
            lhs.updatedAt != rhs.updatedAt ? lhs.updatedAt > rhs.updatedAt : lhs.phrase < rhs.phrase
        }
    }

    /// 品目とカテゴリの組を覚える。品目を覚えの言葉の形にそろえられなければ（空・長すぎる）何もしない（false を返す）。
    ///
    /// 同じ言葉の行は 1 つだけを残して書き換え（無ければ足し）、ほかを片づける（`BudgetStore.setAmounts` と同じ）。残す行の
    /// カテゴリがすでに同じなら、書いた日時だけを新しくする（別の端末で同じころに覚えた別のカテゴリより、いま選んだものを勝たせる）。
    @discardableResult
    func remember(item: String, category: EntryCategory) throws -> Bool {
        guard let key = CategoryMemory.key(for: item) else { return false }
        let rows = try context.fetch(FetchDescriptor<LearnedCategory>())
            .filter { CategoryMemory.key(for: $0.phrase) == key }
        let timestamp = now()
        if let kept = CategoryMemory.preferred(rows) {
            if kept.phrase != key { kept.phrase = key }
            if kept.categoryRawValue != category.rawValue { kept.categoryRawValue = category.rawValue }
            kept.updatedAt = timestamp
            for duplicate in rows where duplicate !== kept {
                context.delete(duplicate)
            }
        } else {
            context.insert(LearnedCategory(phrase: key, category: category, updatedAt: timestamp))
        }
        try commit()
        return true
    }

    /// 直す（⑥）で変えたカテゴリを覚える。支出のカテゴリを変えたとき（収入を支出に直してカテゴリを選んだときも）だけ覚える。
    /// 覚えたら true。書き込めなければ throw する（呼び出し側は、直した記録の保存を失敗にはしない。`EditEntryModel`）。
    @discardableResult
    func rememberCorrection(from original: EntryEdits, to edits: EntryEdits) throws -> Bool {
        guard !edits.isIncome, original.isIncome || edits.category != original.category else { return false }
        let item = CategoryMemory.item(ofMemo: edits.memo, amount: edits.amount, isIncome: false)
        return try remember(item: item, category: edits.category)
    }

    /// 覚えた言葉を忘れる（同じ言葉の行をすべて消す）。
    func forget(phrase: String) throws {
        guard let key = CategoryMemory.key(for: phrase) else { return }
        for row in try context.fetch(FetchDescriptor<LearnedCategory>()) where CategoryMemory.key(for: row.phrase) == key {
            context.delete(row)
        }
        try commit()
    }

    /// 覚えたものをすべて忘れる。
    func forgetAll() throws {
        for row in try context.fetch(FetchDescriptor<LearnedCategory>()) {
            context.delete(row)
        }
        try commit()
    }

    /// 書き込めなかった変更は取り消す（EntryStore と同じ理由。画面と保存先を食い違わせないため）。
    private func commit() throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// 設定の一覧の 1 行。
    struct Rule: Identifiable, Hashable {
        /// 覚えた言葉（そろえた形）。
        let phrase: String
        let category: EntryCategory
        let updatedAt: Date

        var id: String { phrase }
    }
}
