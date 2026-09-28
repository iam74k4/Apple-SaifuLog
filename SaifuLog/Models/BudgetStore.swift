import Foundation
import SaifuLogCore
import SwiftData

/// 予算の読み書き。保存に失敗したら変更を巻き戻し、呼び出し側に知らせる（`EntryStore` と同じ）。
@MainActor
struct BudgetStore {
    let context: ModelContext
    /// 変更を書き込む処理。テストで失敗させるために差し替えられるようにしている。
    var save: (ModelContext) throws -> Void = { try $0.save() }
    /// 書き込んだ日時（`Budget.updatedAt`）の基準。テストで固定の日時にする。
    var now: () -> Date = { .now }

    /// いま有効な予算。
    func plan() throws -> BudgetPlan {
        BudgetPlan.resolve(try context.fetch(FetchDescriptor<Budget>()))
    }

    /// その対象の予算を決める。0 で「設定なし」にする。
    func setAmount(_ amount: Int, for scope: BudgetScope) throws {
        try setAmounts([scope: amount])
    }

    /// いくつかの対象の予算をまとめて決める（全体とカテゴリ別を一度に保存したとき、一部だけ書かれないように）。
    ///
    /// 対象ごとに 1 行だけを残して書き換え（無ければ足し）、同じ対象のほかの行は片づける。残すのは
    /// `BudgetPlan.preferred` が選ぶ行（読むときに有効とみなす行と同じ）。片づけた行の削除が iCloud で
    /// 他の端末に届く前でも、書き換えた行のほうが新しいので、どの端末でもこの額が有効になる。
    /// 額は 0〜`BudgetPlan.maximumAmount` に収める（負の数は設定なしにする）。
    func setAmounts(_ amounts: [BudgetScope: Int]) throws {
        guard !amounts.isEmpty else { return }
        let rows = try context.fetch(FetchDescriptor<Budget>())
        let timestamp = now()
        for (scope, amount) in amounts {
            let value = min(max(amount, 0), BudgetPlan.maximumAmount)
            let sameScope = rows.filter { $0.scopeRawValue == scope.rawValue }
            guard let kept = BudgetPlan.preferred(sameScope) else {
                context.insert(Budget(scope: scope, amount: value, updatedAt: timestamp))
                continue
            }
            kept.amount = value
            kept.updatedAt = timestamp
            for duplicate in sameScope where duplicate !== kept {
                context.delete(duplicate)
            }
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
}
