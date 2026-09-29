import CloudKit
import Foundation
import OSLog
import SaifuLogCore

/// CKSyncEngine のうち、家計の同期が使う部分（送る変更の登録と、すぐに送る・取る）。
///
/// CKSyncEngine と CKShare の実際の動きは CI で確かめられない（iCloud のアカウントも 2 台目の端末も無い）ので、ここを差し替え
/// られる形にし、アプリのテストでは送る変更を記録するだけの偽物を渡す。CKSyncEngine から届く出来事（取れた変更・送った結果）は、
/// `HouseholdSync` の `apply…` に CloudKit の値のまま渡し、同じテストで確かめる。
@MainActor
protocol HouseholdSyncEngine: AnyObject {
    var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] { get }
    var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] { get }
    func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
    func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
    /// すぐにサーバーの変更を取る（招待を受け入れた直後など。ふだんは CKSyncEngine が自分で決めた時に取る）。
    func fetchChanges() async throws
    /// すぐに送る（家計を消したときなど。ふだんは CKSyncEngine が自分で決めた時に送る）。
    func sendChanges() async throws
}

/// 家計がこの端末から消えたこと（利用者への知らせに使う）。
enum HouseholdRemoval: Equatable, Sendable {
    /// サーバーでゾーンが消えた（持ち主が家計を消した・共有をやめた・iCloud の容量の画面で消したなど）。
    case zoneRemoved(role: HouseholdRole)
    /// 持ち主の暗号化したデータのリセットで、共有が消えた（記録は送り直した。家族はもう一度招待する）。
    case reuploadedAfterEncryptionReset
    /// iCloud からサインアウトした・アカウントを替えた（前のアカウントの家計を端末から消した）。
    case accountChanged
}

/// 家計の保存先と CKSyncEngine のあいだを受け持つ。端末の変更を送る変更として登録し、CKSyncEngine から届いた変更を保存先に
/// 取り込み、送った結果（衝突・ゾーンが無い・記録が無い）を片づける。
///
/// CKSyncEngine は 2 つ持つ。私用データベース（自分で作った家計のゾーン）と、共有データベース（招待を受け入れた家計のゾーン）。
/// 家計が端末に無くても、起動したら両方を作る（`startEngines`）。サーバーにある家計のゾーン（同じ Apple アカウントのほかの端末で
/// 作った・受け入れた家計や、サインアウトする前にこの端末にあった家計）を見つけて取り込むため。CKSyncEngine は作った
/// データベースのすべてのゾーンの変更を知らせてくるが、家計のゾーン（`HouseholdZoneName`）以外は取り込まない（私用データベース
/// には iCloud 同期のゾーンもあるため）。
///
/// 決め事（docs/design.md §5-5）:
/// - 衝突（`serverRecordChanged`）は、利用者が直した日時の新しいほうを採る（`HouseholdConflict`）。端末の値を採ったら、
///   サーバーの版の上に載せて送り直す。
/// - 削除が勝つ。サーバーで消えた記録は、端末で直している途中でも消す。送ったら記録が無かった（`unknownItem`）ときも消す。
/// - ゾーンが消えたら、端末の家計の記録も消して知らせる（持ち主の暗号化したデータのリセットだけは送り直す。`HouseholdZoneRemoval`）。
@MainActor
final class HouseholdSync {
    typealias EngineFactory = @MainActor (HouseholdDatabaseScope, CKSyncEngine.State.Serialization?, HouseholdSync) -> any HouseholdSyncEngine

    /// 家計が端末から消えたときに呼ぶ（`HouseholdHost` が知らせを出す）。
    var householdRemoved: @MainActor (HouseholdRemoval) -> Void = { _ in }
    /// 家計や記録が変わったとき（取り込んだ・消えた）に呼ぶ（`HouseholdHost` がいまの家計を読み直す）。
    var didChange: @MainActor () -> Void = {}

    private let store: HouseholdStore
    private let makeEngine: EngineFactory
    private var engines: [HouseholdDatabaseScope: any HouseholdSyncEngine] = [:]
    /// この起動の間に抜けた・消した家計のゾーン。サーバーが片づけ終える前に届いた変更で、家計を取り込み直さないため。
    private var forgottenZoneNames: Set<String> = []
    private let logger = Logger(subsystem: "com.iam74k4.SaifuLog", category: "household.sync")

    init(store: HouseholdStore, makeEngine: @escaping EngineFactory) {
        self.store = store
        self.makeEngine = makeEngine
    }

    // MARK: - CKSyncEngine

    /// そのデータベースの CKSyncEngine（まだ無ければ、保存した状態から作る）。
    func engine(for scope: HouseholdDatabaseScope) -> any HouseholdSyncEngine {
        if let engine = engines[scope] { return engine }
        let serialization = (try? store.syncState(scope: scope)).flatMap { data in
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let engine = makeEngine(scope, serialization, self)
        engines[scope] = engine
        return engine
    }

    /// そのデータベースの CKSyncEngine を作ってあるか（テストで使う）。
    func hasEngine(for scope: HouseholdDatabaseScope) -> Bool {
        engines[scope] != nil
    }

    /// 私用・共有の両方のデータベースの同期を始める（起動したとき・サインアウトやアカウントの切り替えの後）。
    ///
    /// 家計が端末に無くても作る。無い端末で作らないと、サーバーにある家計のゾーン（同じ Apple アカウントのほかの端末で作った・
    /// 受け入れた家計や、サインアウトする前にこの端末にあった家計）が増えたことを知る手段が無く、取り込めない
    /// （`applyFetchedZoneChanges`）。取りにいく記録は端末にある家計のゾーンに絞るので（`zoneIDsToFetch`）、家計が無い間に
    /// 取るのはゾーンの増減だけ。iCloud にサインインしていない間は、CKSyncEngine は何もせずに待つ（Apple の CKSyncEngine の説明）。
    func startEngines() {
        for scope in HouseholdDatabaseScope.allCases {
            _ = engine(for: scope)
        }
    }

    /// その CKSyncEngine が、いまそのデータベースに使っているものか。
    ///
    /// サインアウトやアカウントの切り替えで作り直した後に、前の CKSyncEngine から遅れて届いた出来事（状態の保存・取れた変更・
    /// もう 1 つのデータベースからの同じアカウントの変更の知らせ）を捨てるために使う（`HouseholdSyncEngineDelegate`）。捨てないと、
    /// 前のアカウントの状態で新しい状態を上書きしたり、前のアカウントの家計を取り込み直したりするため。
    func isCurrent(_ engine: any HouseholdSyncEngine, scope: HouseholdDatabaseScope) -> Bool {
        engines[scope] === engine
    }

    /// 家計のゾーンの ID。
    static func zoneID(for household: Household) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: household.zoneName,
            ownerName: household.zoneOwnerName.isEmpty ? CKCurrentUserDefaultName : household.zoneOwnerName
        )
    }

    // MARK: - 端末の変更を送る

    /// 家計を作った（持ち主）。ゾーンを作る変更を登録する。
    func householdCreated(_ household: Household) {
        forgottenZoneNames.remove(household.zoneName)
        engine(for: .private).add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID(for: household)))])
    }

    /// 招待を受け入れた（参加者）。共有データベースの同期を始め、すぐに取りにいく。
    func householdJoined(_ household: Household) {
        forgottenZoneNames.remove(household.zoneName)
        let engine = engine(for: .shared)
        Task { try? await engine.fetchChanges() }
    }

    /// 記録を書いた・直した。送る変更として登録する。
    func entriesSaved(_ entries: [HouseholdEntry], in household: Household) {
        let zoneID = Self.zoneID(for: household)
        engine(for: HouseholdDatabaseScope(role: household.role)).add(
            pendingRecordZoneChanges: entries.map { .saveRecord(HouseholdRecord.recordID(for: $0.id, zoneID: zoneID)) }
        )
    }

    /// 記録を消した。消す変更として登録する（まだ送っていない書き込みの変更は取り消す）。
    func entriesDeleted(ids: [UUID], in household: Household) {
        let zoneID = Self.zoneID(for: household)
        let recordIDs = ids.map { HouseholdRecord.recordID(for: $0, zoneID: zoneID) }
        let engine = engine(for: HouseholdDatabaseScope(role: household.role))
        engine.remove(pendingRecordZoneChanges: recordIDs.map { .saveRecord($0) })
        engine.add(pendingRecordZoneChanges: recordIDs.map { .deleteRecord($0) })
    }

    /// 家計を消した（持ち主）。ゾーンごと消す変更を登録する（共有も消え、家族の端末からも消える）。
    func householdDeleted(_ household: Household) {
        let zoneID = Self.zoneID(for: household)
        forget(zoneName: household.zoneName, in: .private)
        let engine = engine(for: .private)
        engine.remove(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        engine.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
    }

    /// 家計から抜けた（参加者）。送っていない変更を捨てる（抜けた家計へは送れない）。
    func householdLeft(_ household: Household) {
        forget(zoneName: household.zoneName, in: .shared)
    }

    /// 家計のゾーンの送っていない変更を捨て、この起動の間は取り込み直さないようにする。
    private func forget(zoneName: String, in scope: HouseholdDatabaseScope) {
        forgottenZoneNames.insert(zoneName)
        guard let engine = engines[scope] else { return }
        let stale = engine.pendingRecordZoneChanges.filter { $0.recordID?.zoneID.zoneName == zoneName }
        engine.remove(pendingRecordZoneChanges: stale)
    }

    // MARK: - CKSyncEngine から届いたもの

    /// CKSyncEngine の状態を保存する（次の起動で渡す）。
    func saveState(_ serialization: CKSyncEngine.State.Serialization, scope: HouseholdDatabaseScope) {
        do {
            try store.setSyncState(JSONEncoder().encode(serialization), scope: scope)
        } catch {
            // 保存できなくても同期は続ける（次の起動で取り直しになるだけ）。
            logger.error("同期の状態を保存できませんでした: \(String(describing: error), privacy: .public)")
        }
    }

    /// 送る記録を作る（CKSyncEngine が送る直前に呼ぶ）。端末に無い記録（送る前に消した・家計ごと消えた）は送る変更から外す。
    func recordToSave(_ recordID: CKRecord.ID, scope: HouseholdDatabaseScope) -> CKRecord? {
        guard let household = household(for: recordID.zoneID, scope: scope),
              let id = UUID(uuidString: recordID.recordName),
              let entry = try? store.entry(id: id), entry.zoneName == household.zoneName
        else {
            engines[scope]?.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
        return HouseholdRecord.record(for: entry, zoneID: recordID.zoneID)
    }

    /// 取りにいく家計のゾーン（そのデータベースの、端末にある家計だけ）。
    ///
    /// CKSyncEngine は既定でデータベースのすべてのゾーンを取りにいく。私用データベースには iCloud 同期（SwiftData）のゾーンも
    /// あり、家計の同期がそれを丸ごと取らないよう、家計のゾーンに絞る（`nextFetchChangesOptions`）。
    func zoneIDsToFetch(scope: HouseholdDatabaseScope) -> [CKRecordZone.ID] {
        ((try? store.households()) ?? [])
            .filter { HouseholdDatabaseScope(role: $0.role) == scope }
            .map(Self.zoneID(for:))
    }

    /// 取れた記録の変更を取り込む。
    ///
    /// 端末に同じ記録があれば、直した日時の新しいほうを採る（`HouseholdConflict`）。端末の値が新しければ残して送り直す
    /// （送る変更が無ければ登録する）。サーバーで消えた記録は、端末で直している途中でも消す（削除が勝つ）。
    func applyFetchedRecordChanges(modified: [CKRecord], deleted: [CKRecord.ID], scope: HouseholdDatabaseScope) {
        var resend: [CKSyncEngine.PendingRecordZoneChange] = []
        var changed = false
        for record in modified {
            guard let household = household(for: record.recordID.zoneID, scope: scope),
                  let id = UUID(uuidString: record.recordID.recordName),
                  let values = HouseholdRecord.values(from: record)
            else { continue }
            if let entry = try? store.entry(id: id) {
                switch HouseholdConflict.winner(localModifiedAt: entry.modifiedAt, serverModifiedAt: values.modifiedAt) {
                case .server:
                    HouseholdRecord.apply(values, to: entry)
                case .local:
                    let change = CKSyncEngine.PendingRecordZoneChange.saveRecord(record.recordID)
                    if engines[scope]?.pendingRecordZoneChanges.contains(change) != true { resend.append(change) }
                }
                HouseholdRecord.keepSystemFieldsIfNewer(record, in: entry)
            } else {
                store.context.insert(HouseholdEntry(
                    id: id,
                    zoneName: household.zoneName,
                    amount: values.amount,
                    isIncome: values.isIncome,
                    category: values.category,
                    memo: values.memo,
                    spentAt: values.spentAt,
                    recorderName: values.recorderName,
                    createdAt: values.createdAt,
                    modifiedAt: values.modifiedAt ?? values.createdAt,
                    systemFields: HouseholdRecord.encodeSystemFields(of: record)
                ))
            }
            changed = true
        }
        for recordID in deleted {
            guard household(for: recordID.zoneID, scope: scope) != nil,
                  let id = UUID(uuidString: recordID.recordName),
                  let entry = try? store.entry(id: id)
            else { continue }
            store.context.delete(entry)
            engines[scope]?.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            changed = true
        }
        guard changed else { return }
        saveFetchedChanges()
        if !resend.isEmpty { engines[scope]?.add(pendingRecordZoneChanges: resend) }
        didChange()
    }

    /// 取れたゾーンの変更を取り込む。
    ///
    /// 消えたゾーン: 端末の家計の記録を消して知らせる（`HouseholdZoneRemoval`）。
    /// 増えたゾーン: 家計が無い端末で、家計のゾーンが増えたら取り込む（同じ Apple アカウントのほかの端末で作った・受け入れた
    /// 家計や、サインアウトする前にこの端末にあった家計。家計の名前と表示名はこの端末で決めてもらう）。家計がすでにある端末では
    /// 取り込まない（v1 は 1 つだけ）。家計の無い端末でも CKSyncEngine を作っておくので（`startEngines`）届く。
    func applyFetchedZoneChanges(
        modified: [CKRecordZone.ID], deleted: [(zoneID: CKRecordZone.ID, reason: HouseholdZoneRemoval.Reason)],
        scope: HouseholdDatabaseScope
    ) {
        for deletion in deleted {
            removeHousehold(zoneID: deletion.zoneID, reason: deletion.reason, scope: scope)
        }
        var adopted = false
        for zoneID in modified where HouseholdZoneName.isHouseholdZone(zoneID.zoneName) {
            guard !forgottenZoneNames.contains(zoneID.zoneName),
                  engines[scope]?.pendingDatabaseChanges.contains(.deleteZone(zoneID)) != true,
                  (try? store.household(zoneName: zoneID.zoneName)) == nil,
                  (try? store.currentHousehold()) == nil
            else { continue }
            let household = Household(
                zoneName: zoneID.zoneName,
                zoneOwnerName: scope == .private ? CKCurrentUserDefaultName : zoneID.ownerName,
                role: scope.role,
                name: "",
                memberName: "",
                createdAt: .now
            )
            do {
                try store.insert(household)
                adopted = true
            } catch {
                logger.error("家計のゾーンを取り込めませんでした: \(String(describing: error), privacy: .public)")
            }
        }
        guard adopted else { return }
        didChange()
        // 増えたゾーンは、この取り込みの範囲（`zoneIDsToFetch`）に入っていなかったので、もう一度取りにいく。
        if let engine = engines[scope] {
            Task { try? await engine.fetchChanges() }
        }
    }

    /// 送った記録の結果を片づける。
    ///
    /// 送れた記録は、サーバーの版（システムフィールド）を残す。衝突は直した日時の新しいほうを採り、端末の値ならサーバーの版の上に
    /// 載せて送り直す。ゾーンが無ければ家計を片づける。記録が無ければ（ほかの人が消した）端末からも消す。通信の失敗などは
    /// CKSyncEngine が自分で送り直すので何もしない。
    func applySentRecordChanges(
        saved: [CKRecord], failed: [(record: CKRecord, error: CKError)], failedDeletes: [CKRecord.ID: CKError],
        scope: HouseholdDatabaseScope
    ) {
        var resend: [CKSyncEngine.PendingRecordZoneChange] = []
        var removedZones: [CKRecordZone.ID] = []
        var changed = false
        for record in saved {
            guard let id = UUID(uuidString: record.recordID.recordName), let entry = try? store.entry(id: id) else { continue }
            HouseholdRecord.keepSystemFieldsIfNewer(record, in: entry)
            changed = true
        }
        for failure in failed {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                guard let serverRecord = failure.error.serverRecord,
                      let id = UUID(uuidString: recordID.recordName),
                      let entry = try? store.entry(id: id)
                else { continue }
                let values = HouseholdRecord.values(from: serverRecord)
                switch HouseholdConflict.winner(localModifiedAt: entry.modifiedAt, serverModifiedAt: values?.modifiedAt) {
                case .server:
                    if let values { HouseholdRecord.apply(values, to: entry) }
                case .local:
                    resend.append(.saveRecord(recordID))
                }
                // どちらを採っても、次に送るときはサーバーの版の上に載せる。
                entry.systemFields = HouseholdRecord.encodeSystemFields(of: serverRecord)
                changed = true
            case .zoneNotFound, .userDeletedZone:
                if !removedZones.contains(recordID.zoneID) { removedZones.append(recordID.zoneID) }
            case .unknownItem:
                // 送った版の記録がサーバーに無い（ほかの人が消した）。削除が勝つので、端末からも消す。
                if let id = UUID(uuidString: recordID.recordName), let entry = try? store.entry(id: id) {
                    store.context.delete(entry)
                    changed = true
                }
            default:
                // 通信の失敗・込み合い・サインインしていないなどは、CKSyncEngine が状態がよくなってから送り直す。
                logger.info("家計の記録を送れませんでした（送り直しは CKSyncEngine に任せる）: \(failure.error.code.rawValue, privacy: .public)")
            }
        }
        for (recordID, error) in failedDeletes where error.code != .zoneNotFound && error.code != .unknownItem {
            logger.info("家計の記録を消せませんでした（送り直しは CKSyncEngine に任せる）: \(recordID.recordName, privacy: .private) \(error.code.rawValue, privacy: .public)")
        }
        if changed { saveFetchedChanges() }
        if !resend.isEmpty { engines[scope]?.add(pendingRecordZoneChanges: resend) }
        for zoneID in removedZones {
            removeHousehold(zoneID: zoneID, reason: .notFound, scope: scope)
        }
        if changed { didChange() }
    }

    /// 送ったゾーンの結果を片づける。ゾーンを作れなかった（すでに消えた・制限）ときは、通信の失敗などを除いて家計を片づける。
    func applySentZoneChanges(failed: [(zoneID: CKRecordZone.ID, error: CKError)], scope: HouseholdDatabaseScope) {
        for failure in failed {
            switch failure.error.code {
            case .zoneNotFound, .userDeletedZone:
                removeHousehold(zoneID: failure.zoneID, reason: .notFound, scope: scope)
            default:
                logger.info("家計のゾーンを作れませんでした（送り直しは CKSyncEngine に任せる）: \(failure.error.code.rawValue, privacy: .public)")
            }
        }
    }

    /// iCloud からサインアウトした・アカウントを替えた。前のアカウントの家計と同期の状態を端末から消し、CKSyncEngine を作り直す。
    ///
    /// 残すと、別のアカウントの端末に前の人の家計の記録が見え続け、新しいアカウントへ送ってしまうため（Apple の CKSyncEngine の
    /// サンプルと同じく、端末のデータを消して、状態を持たない CKSyncEngine を作り直す）。作り直した CKSyncEngine は、サインイン
    /// するまで待ち、サインインしたらそのアカウントの家計のゾーンを見つけて取り込む（同じアカウントで入り直せば家計が戻る）。
    /// 私用・共有の両方の CKSyncEngine から届くので、2 つ目（作り直す前のもの）は `isCurrent` で捨てる。
    func accountDidChange() {
        let hadHousehold = ((try? store.households()) ?? []).isEmpty == false
        do {
            try store.removeAll()
        } catch {
            logger.error("サインアウトの後に家計を片づけられませんでした: \(String(describing: error), privacy: .public)")
        }
        engines.removeAll()
        forgottenZoneNames.removeAll()
        startEngines()
        didChange()
        if hadHousehold { householdRemoved(.accountChanged) }
    }

    // MARK: - 内部

    /// そのデータベースの、そのゾーンの家計（家計のゾーンでない・端末に無い・立場が合わなければ nil）。
    private func household(for zoneID: CKRecordZone.ID, scope: HouseholdDatabaseScope) -> Household? {
        guard HouseholdZoneName.isHouseholdZone(zoneID.zoneName),
              let household = try? store.household(zoneName: zoneID.zoneName),
              HouseholdDatabaseScope(role: household.role) == scope
        else { return nil }
        return household
    }

    /// ゾーンが消えた家計を片づける（`HouseholdZoneRemoval` の決め事）。
    private func removeHousehold(zoneID: CKRecordZone.ID, reason: HouseholdZoneRemoval.Reason, scope: HouseholdDatabaseScope) {
        guard let household = household(for: zoneID, scope: scope) else { return }
        let role = household.role
        switch HouseholdZoneRemoval.action(for: reason, role: role == .owner ? .owner : .participant) {
        case .removeLocalData:
            forget(zoneName: household.zoneName, in: scope)
            do {
                try store.removeHousehold(zoneName: household.zoneName)
            } catch {
                logger.error("消えた家計を片づけられませんでした: \(String(describing: error), privacy: .public)")
                return
            }
            didChange()
            householdRemoved(.zoneRemoved(role: role))
        case .reuploadLocalData:
            let entries = (try? store.entries(zoneName: household.zoneName)) ?? []
            // 前の版はもう無いので、新しい記録として送る。
            for entry in entries { entry.systemFields = nil }
            saveFetchedChanges()
            let engine = engine(for: scope)
            engine.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            engine.add(pendingRecordZoneChanges: entries.map { .saveRecord(HouseholdRecord.recordID(for: $0.id, zoneID: zoneID)) })
            householdRemoved(.reuploadedAfterEncryptionReset)
        }
    }

    /// 取り込んだ変更を書き込む。書き込めなければ巻き戻す（CKSyncEngine の状態は進んでいるので、取り込めなかった変更は次の
    /// 起動の取り直しまで端末に届かない。ログに残す）。
    private func saveFetchedChanges() {
        do {
            try store.saveChanges()
        } catch {
            logger.error("取れた家計の変更を保存できませんでした: \(String(describing: error), privacy: .public)")
        }
    }
}

extension HouseholdZoneRemoval.Reason {
    /// CloudKit のゾーンが消えた理由を写す。
    init(_ reason: CKDatabase.DatabaseChange.Deletion.Reason) {
        switch reason {
        case .deleted: self = .deleted
        case .purged: self = .purged
        case .encryptedDataReset: self = .encryptedDataReset
        @unknown default: self = .deleted
        }
    }
}

extension CKSyncEngine.PendingRecordZoneChange {
    /// 変更の対象の記録の ID（知らない種類の変更なら nil）。
    var recordID: CKRecord.ID? {
        switch self {
        case .saveRecord(let recordID), .deleteRecord(let recordID): recordID
        @unknown default: nil
        }
    }
}

// MARK: - 本物の CKSyncEngine

/// 本物の CKSyncEngine を包む（アプリだけが使う。テストでは偽物を渡す）。
@MainActor
final class LiveHouseholdSyncEngine: HouseholdSyncEngine {
    private let engine: CKSyncEngine
    /// CKSyncEngine に渡した委任先。CKSyncEngine が弱く持つことがあるので、ここで持っておく。
    private let delegate: HouseholdSyncEngineDelegate

    init(scope: HouseholdDatabaseScope, serialization: CKSyncEngine.State.Serialization?, sync: HouseholdSync, containerIdentifier: String) {
        let container = CKContainer(identifier: containerIdentifier)
        let delegate = HouseholdSyncEngineDelegate(scope: scope, sync: sync)
        let database = scope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
        self.engine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: serialization, delegate: delegate))
        self.delegate = delegate
        // 出来事は MainActor で届くので、ここ（同じ MainActor の続き）で持ち主を決めれば、最初の出来事より先に決まる。
        delegate.owner = self
    }

    /// アプリの家計の同期が使う作り方（iCloud 同期と同じコンテナ）。
    static let factory: HouseholdSync.EngineFactory = { scope, serialization, sync in
        LiveHouseholdSyncEngine(
            scope: scope, serialization: serialization, sync: sync,
            containerIdentifier: ModelContainerFactory.iCloudContainerIdentifier
        )
    }

    var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] { engine.state.pendingRecordZoneChanges }
    var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] { engine.state.pendingDatabaseChanges }
    func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) { engine.state.add(pendingRecordZoneChanges: pendingRecordZoneChanges) }
    func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) { engine.state.remove(pendingRecordZoneChanges: pendingRecordZoneChanges) }
    func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) { engine.state.add(pendingDatabaseChanges: pendingDatabaseChanges) }
    func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) { engine.state.remove(pendingDatabaseChanges: pendingDatabaseChanges) }
    func fetchChanges() async throws { try await engine.fetchChanges() }
    func sendChanges() async throws { try await engine.sendChanges() }
}

/// CKSyncEngine の委任先。届いた出来事を CloudKit の値のまま `HouseholdSync` へ渡すだけにする（決め事はそちらでテストする）。
@MainActor
final class HouseholdSyncEngineDelegate: CKSyncEngineDelegate {
    let scope: HouseholdDatabaseScope
    /// 循環（HouseholdSync → CKSyncEngine → 委任先 → HouseholdSync）を作らないよう弱く持つ。
    weak var sync: HouseholdSync?
    /// この委任先を使う CKSyncEngine の包み。作り直された（サインアウトの後）かを見分けるのに使う。包みがこの委任先を持つので弱く持つ。
    weak var owner: LiveHouseholdSyncEngine?

    init(scope: HouseholdDatabaseScope, sync: HouseholdSync) {
        self.scope = scope
        self.sync = sync
    }

    /// 届いた出来事を渡す先。作り直す前の CKSyncEngine からなら nil（遅れて届いたものは捨てる。`HouseholdSync.isCurrent`）。
    private var currentSync: HouseholdSync? {
        guard let sync, let owner, sync.isCurrent(owner, scope: scope) else { return nil }
        return sync
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard let sync = currentSync else { return }
        switch event {
        case .stateUpdate(let update):
            sync.saveState(update.stateSerialization, scope: scope)
        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                // サインインしただけでは何もしない（家計はサインアウトのときに消している）。
                break
            case .signOut, .switchAccounts:
                sync.accountDidChange()
            @unknown default:
                break
            }
        case .fetchedDatabaseChanges(let changes):
            sync.applyFetchedZoneChanges(
                modified: changes.modifications.map(\.zoneID),
                deleted: changes.deletions.map { (zoneID: $0.zoneID, reason: HouseholdZoneRemoval.Reason($0.reason)) },
                scope: scope
            )
        case .fetchedRecordZoneChanges(let changes):
            sync.applyFetchedRecordChanges(
                modified: changes.modifications.map(\.record), deleted: changes.deletions.map(\.recordID), scope: scope
            )
        case .sentDatabaseChanges(let sent):
            sync.applySentZoneChanges(failed: sent.failedZoneSaves.map { (zoneID: $0.zone.zoneID, error: $0.error) }, scope: scope)
        case .sentRecordZoneChanges(let sent):
            sync.applySentRecordChanges(
                saved: sent.savedRecords,
                failed: sent.failedRecordSaves.map { (record: $0.record, error: $0.error) },
                failedDeletes: sent.failedRecordDeletes,
                scope: scope
            )
        case .willFetchChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .didFetchChanges,
             .willSendChanges, .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // 作り直す前の CKSyncEngine からは送らない（前のアカウントへ送らないため）。
        guard let sync = currentSync else { return nil }
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let databaseScope = self.scope
        // 1 回に送れる数（250 件）を超えないよう、CKSyncEngine の作り方に任せる（入りきらない変更は次の回に残る）。
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            await sync.recordToSave(recordID, scope: databaseScope)
        }
    }

    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        // 作り直す前の CKSyncEngine では、どのゾーンの記録も取らない。
        options.scope = .zoneIDs(currentSync?.zoneIDsToFetch(scope: scope) ?? [])
        return options
    }
}
