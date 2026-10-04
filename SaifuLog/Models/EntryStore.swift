import Foundation
import SaifuLogCore
import SwiftData

/// 記録の保存・直し・削除。保存に失敗したら変更を巻き戻し、呼び出し側に知らせる。
///
/// 失敗を捨てると、保存できていないのに「記録しました」と読み上げたり、消したはずの記録が
/// 次の起動で戻ってきたりする。呼び出し側は throw を受けて利用者に知らせる。
@MainActor
struct EntryStore {
    let context: ModelContext
    /// 変更を書き込む処理。テストで失敗させるために差し替えられるようにしている。
    var save: (ModelContext) throws -> Void = { try $0.save() }

    func insert(_ entries: [Entry]) throws {
        for entry in entries {
            context.insert(entry)
        }
        try commit()
    }

    /// 記録を直す（直すシートの保存）。書き込めなければ直す前の値に戻して throw する。
    ///
    /// 戻さないと、画面には直した値が出たまま、次の自動保存で黙って書き込まれたり、次の起動で直す前に戻ったりする。
    /// ほかの端末（iCloud）で消された記録なら、値に触れずに `EntryDeletedElsewhere` を throw する（消えた記録の値を読み書き
    /// すると、アプリが落ちうるため。直したつもりで何も残らないことも避ける）。
    func update(_ entry: Entry, with edits: EntryEdits, resolvesCategory: Bool = true) throws {
        guard exists(entry.persistentModelID) else { throw EntryDeletedElsewhere() }
        edits.apply(to: entry)
        if resolvesCategory {
            entry.needsCategoryReview = false
            entry.needsPaymentClassification = false
        }
        do {
            try commit()
        } catch {
            // SwiftData の rollback は書き込む前の変更を捨てるが、読み込み済みの記録の値は直した値のまま残る
            // （吹き出しに保存していない値が出続ける）。読み直すと保存されている値に戻るので、読み直しておく。
            reload(entry)
            throw error
        }
    }

    /// 記録を消す。ほかの端末（iCloud）で消された記録は飛ばす（もう無いので、消したのと同じ）。
    func delete(_ entries: [Entry]) throws {
        let existing = entries.filter { exists($0.persistentModelID) }
        let keys = Set(existing.map(\.reviewID).filter { !$0.isEmpty })
        // 相手の記録を消したら、確認用に控えた金額や品目も同じ保存処理で片づける。
        if !keys.isEmpty {
            let pending = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.paymentReviewJSON != "" }))
            for anchor in pending {
                guard let evidence = PaymentReviewEvidence(json: anchor.paymentReviewJSON),
                      keys.contains(evidence.payment.key) || evidence.records.contains(where: { keys.contains($0.key) }) else { continue }
                anchor.paymentReviewJSON = ""
            }
        }
        for entry in existing {
            context.delete(entry)
        }
        try commit()
    }

    /// 記録がまだ保存先にあるか（ほかの端末で消されていないか）。ID だけで確かめ、記録の値には触れない。
    ///
    /// iCloud で届いた削除は、SwiftData が読み込み済みの記録の値を空にするので、値を読むとアプリが落ちうる（Apple の開発者
    /// フォーラム thread 762022）。確かめられなければ、あるものとして扱う（消えていない記録を、取り消しや聞き返しから外さない
    /// ため）。
    func exists(_ id: PersistentIdentifier) -> Bool {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id })
        guard let count = try? context.fetchCount(descriptor) else { return true }
        return count > 0
    }

    /// 記録を保存先から読み直す（読み込み済みの記録の値を、保存されている値にそろえる）。読めなければそのまま。
    private func reload(_ entry: Entry) {
        let id = entry.persistentModelID
        _ = try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.persistentModelID == id }))
    }

    /// 書き込めなかった変更は取り消す。残しておくと、画面には出たまま次の自動保存で
    /// 黙って書き込まれたり、書き込まれずに消えたりして、画面と保存先が食い違うため。
    func commit() throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// 直そうとした記録が、ほかの端末（iCloud）で消されていた。
struct EntryDeletedElsewhere: Error {}

/// 直すシートで変えられる、記録の値。保存する前の形で持ち、変えたかどうかの比べと書き換えに使う。
///
/// 元の入力文・入力元・記録した日時は直さない（元の入力文は、読み違いの見直しに元のまま残す。
/// 記録した日時を変えると、タイムラインの並び（送った順）が変わるため）。
struct EntryEdits: Equatable {
    var amount: Int
    var isIncome: Bool
    var category: EntryCategory
    var memo: String
    var spentAt: Date

    init(amount: Int, isIncome: Bool, category: EntryCategory, memo: String, spentAt: Date) {
        self.amount = amount
        self.isIncome = isIncome
        self.category = category
        self.memo = memo
        self.spentAt = spentAt
    }

    /// 記録のいまの値。
    init(_ entry: Entry) {
        self.init(
            amount: entry.amount, isIncome: entry.isIncome, category: entry.category,
            memo: entry.memo, spentAt: entry.spentAt
        )
    }

    /// 違う値の項目だけを書き換える。
    ///
    /// 同じ値でも代入すると変更として扱われうるので、直した項目に限って書き込む（直していない項目まで書き換えたことに
    /// しない。予算の保存で、変えた対象だけを書き込むのと同じ考え方）。
    func apply(to entry: Entry) {
        if entry.amount != amount { entry.amount = amount }
        if entry.isIncome != isIncome { entry.isIncome = isIncome }
        if entry.category != category { entry.category = category }
        if entry.memo != memo { entry.memo = memo }
        if entry.spentAt != spentAt { entry.spentAt = spentAt }
    }
}
