import Foundation
import SaifuLogCore
import SwiftData

/// 家計の保存先（household.store）の読み書き。書き込めなければ変更を巻き戻して throw する（自分の記録の `EntryStore` と同じ）。
///
/// CloudKit には触れない。同期（`HouseholdSync`）に何を送るかを知らせるのは、呼び出し側（`HouseholdHost`）が受け持つ。
@MainActor
struct HouseholdStore {
    let context: ModelContext
    /// 変更を書き込む処理。テストで失敗させるために差し替えられるようにしている。
    var save: (ModelContext) throws -> Void = { try $0.save() }

    // MARK: - 家計

    /// この端末の家計（作った日時の古い順）。v1 では 1 つだけ（`currentHousehold`）。
    func households() throws -> [Household] {
        try context.fetch(FetchDescriptor<Household>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    /// いまの家計。v1 では端末が入る家計は 1 つだけなので、いちばん古いもの。無ければ nil。
    func currentHousehold() throws -> Household? {
        try households().first
    }

    func household(zoneName: String) throws -> Household? {
        var descriptor = FetchDescriptor<Household>(predicate: #Predicate { $0.zoneName == zoneName })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func insert(_ household: Household) throws {
        context.insert(household)
        try commit()
    }

    /// 家計の名前や表示名を直したあとに書き込む。
    func saveChanges() throws {
        try commit()
    }

    /// 家計とその記録を端末から消す（ゾーンが消えた・共有をやめた・抜けた・家計を消した）。同期の状態は残す
    /// （データベースごとのもので、ほかの家計の送っていない変更も入っているため）。
    func removeHousehold(zoneName: String) throws {
        for household in try context.fetch(FetchDescriptor<Household>(predicate: #Predicate { $0.zoneName == zoneName })) {
            context.delete(household)
        }
        for entry in try context.fetch(FetchDescriptor<HouseholdEntry>(predicate: #Predicate { $0.zoneName == zoneName })) {
            context.delete(entry)
        }
        try commit()
    }

    /// 家計の保存先を空にする（iCloud からサインアウトした・アカウントを替えたとき）。同期の状態も消す
    /// （前のアカウントの状態で、新しいアカウントと同期しないため）。
    func removeAll() throws {
        try context.delete(model: HouseholdEntry.self)
        try context.delete(model: Household.self)
        try context.delete(model: HouseholdSyncState.self)
        try commit()
    }

    // MARK: - 記録

    func entries(zoneName: String) throws -> [HouseholdEntry] {
        try context.fetch(FetchDescriptor<HouseholdEntry>(
            predicate: #Predicate { $0.zoneName == zoneName }, sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func entry(id: UUID) throws -> HouseholdEntry? {
        var descriptor = FetchDescriptor<HouseholdEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func insert(_ entries: [HouseholdEntry]) throws {
        for entry in entries {
            context.insert(entry)
        }
        try commit()
    }

    /// 記録を直す。直した日時（`modifiedAt`）も書く（衝突の解決で、新しいほうを採るのに使う）。書き込めなければ直す前の値に戻す。
    func update(_ entry: HouseholdEntry, with edits: EntryEdits, at now: Date) throws {
        if entry.amount != edits.amount { entry.amount = edits.amount }
        if entry.isIncome != edits.isIncome { entry.isIncome = edits.isIncome }
        if entry.category != edits.category { entry.category = edits.category }
        if entry.memo != edits.memo { entry.memo = edits.memo }
        if entry.spentAt != edits.spentAt { entry.spentAt = edits.spentAt }
        entry.modifiedAt = now
        do {
            try commit()
        } catch {
            // 読み込み済みの記録は直した値のまま残るので、保存先から読み直す（自分の記録の `EntryStore.update` と同じ）。
            let id = entry.persistentModelID
            _ = try? context.fetch(FetchDescriptor<HouseholdEntry>(predicate: #Predicate { $0.persistentModelID == id }))
            throw error
        }
    }

    func delete(_ entries: [HouseholdEntry]) throws {
        for entry in entries {
            context.delete(entry)
        }
        try commit()
    }

    // MARK: - 同期の状態

    /// データベースごとの CKSyncEngine の状態（JSON）。まだ無ければ nil。
    func syncState(scope: HouseholdDatabaseScope) throws -> Data? {
        try syncStateRow(scope: scope)?.serialization
    }

    func setSyncState(_ data: Data?, scope: HouseholdDatabaseScope) throws {
        if let row = try syncStateRow(scope: scope) {
            row.serialization = data
        } else {
            context.insert(HouseholdSyncState(scopeRawValue: scope.rawValue, serialization: data))
        }
        try commit()
    }

    private func syncStateRow(scope: HouseholdDatabaseScope) throws -> HouseholdSyncState? {
        let rawValue = scope.rawValue
        var descriptor = FetchDescriptor<HouseholdSyncState>(predicate: #Predicate { $0.scopeRawValue == rawValue })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// 書き込めなかった変更は取り消す（画面と保存先を食い違わせないため）。
    private func commit() throws {
        do {
            try save(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

/// 家計のゾーンを置くデータベース。
enum HouseholdDatabaseScope: String, CaseIterable, Sendable {
    /// 持ち主の私用データベース（自分で作った家計のゾーン）。
    case `private`
    /// 共有データベース（招待を受け入れた家計のゾーン）。
    case shared

    init(role: HouseholdRole) {
        self = role == .owner ? .private : .shared
    }

    /// このデータベースの家計での立場。
    var role: HouseholdRole {
        self == .private ? .owner : .participant
    }
}
