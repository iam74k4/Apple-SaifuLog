import CloudKit
import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 家計の同期（HouseholdSync）。CKSyncEngine を代わりに替え、CKSyncEngine から届く値（取れた変更・送った結果）を直接渡して、
/// 取り込み・衝突の解決・ゾーンが消えたときの片づけを確かめる。CKSyncEngine と CKShare の実際の動きは実機で確かめる
/// （docs/design.md §15）。
@MainActor
struct HouseholdSyncTests {
    /// 家計の保存先と、代わりの CKSyncEngine を使う同期。
    @MainActor
    final class Fixture {
        let context: ModelContext
        let store: HouseholdStore
        let engines = FakeHouseholdEngines()
        let sync: HouseholdSync
        private(set) var removals: [HouseholdRemoval] = []
        private(set) var changeCount = 0

        init() throws {
            context = try TestSupport.makeHouseholdContext()
            store = HouseholdStore(context: context)
            sync = HouseholdSync(store: store, makeEngine: engines.factory)
            sync.householdRemoved = { [unowned self] in removals.append($0) }
            sync.didChange = { [unowned self] in changeCount += 1 }
        }

        @discardableResult
        func insertHousehold(role: HouseholdRole, zoneName: String = TestSupport.householdZoneName) throws -> Household {
            let household = TestSupport.household(role: role, zoneName: zoneName)
            try store.insert(household)
            return household
        }

        func entries() throws -> [HouseholdEntry] {
            try context.fetch(FetchDescriptor<HouseholdEntry>(sortBy: [SortDescriptor(\.createdAt)]))
        }

        /// サーバーから届いたことにする記録。
        func serverRecord(
            id: UUID, role: HouseholdRole, amount: Int, memo: String = "ランチ", recorderName: String = "たろう", modifiedAt: Date?
        ) -> CKRecord {
            let record = CKRecord(
                recordType: HouseholdRecord.recordType,
                recordID: HouseholdRecord.recordID(for: id, zoneID: TestSupport.householdZoneID(role: role))
            )
            record.encryptedValues[HouseholdRecord.Field.amount] = amount
            record.encryptedValues[HouseholdRecord.Field.memo] = memo
            record.encryptedValues[HouseholdRecord.Field.category] = EntryCategory.food.rawValue
            record.encryptedValues[HouseholdRecord.Field.spentAt] = TestSupport.now
            record.encryptedValues[HouseholdRecord.Field.createdAt] = TestSupport.now
            record.encryptedValues[HouseholdRecord.Field.recorderName] = recorderName
            if let modifiedAt { record.encryptedValues[HouseholdRecord.Field.modifiedAt] = modifiedAt }
            return record
        }
    }

    let earlier = TestSupport.date(2026, 9, 28, hour: 9)
    let later = TestSupport.date(2026, 9, 28, hour: 11)

    // MARK: - 端末の変更を送る

    /// 家計を作ったらゾーンを作る変更、記録を書いたら書き込みの変更を、家計のデータベース（持ち主は私用）に登録する。
    @Test func localChangesBecomePendingChanges() throws {
        let fixture = try Fixture()
        let household = try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry()
        try fixture.store.insert([entry])

        fixture.sync.householdCreated(household)
        fixture.sync.entriesSaved([entry], in: household)

        let engine = try #require(fixture.engines[.private])
        #expect(engine.pendingDatabaseChanges == [.saveZone(CKRecordZone(zoneID: TestSupport.householdZoneID(role: .owner)))])
        #expect(engine.pendingRecordZoneChanges == [
            .saveRecord(HouseholdRecord.recordID(for: entry.id, zoneID: TestSupport.householdZoneID(role: .owner))),
        ])
        #expect(fixture.engines[.shared] == nil)
    }

    /// 参加者の記録は共有データベースへ送る（ゾーンの持ち主は家計を作った人）。消したら、送っていない書き込みを取り消して削除を登録する。
    @Test func participantChangesGoToSharedDatabase() throws {
        let fixture = try Fixture()
        let household = try fixture.insertHousehold(role: .participant)
        let entry = TestSupport.householdEntry()
        try fixture.store.insert([entry])

        fixture.sync.entriesSaved([entry], in: household)
        fixture.sync.entriesDeleted(ids: [entry.id], in: household)

        let engine = try #require(fixture.engines[.shared])
        let recordID = HouseholdRecord.recordID(for: entry.id, zoneID: TestSupport.householdZoneID(role: .participant))
        #expect(recordID.zoneID.ownerName == TestSupport.householdOwnerName)
        #expect(engine.pendingRecordZoneChanges == [.deleteRecord(recordID)])
    }

    /// 送る直前に記録を作る。端末に無い記録（送る前に消した）は送る変更から外す。
    @Test func recordToSaveBuildsEncryptedRecordOrDropsMissing() throws {
        let fixture = try Fixture()
        let household = try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry(amount: 1_500)
        try fixture.store.insert([entry])
        fixture.sync.entriesSaved([entry], in: household)
        let zoneID = TestSupport.householdZoneID(role: .owner)

        let record = try #require(fixture.sync.recordToSave(HouseholdRecord.recordID(for: entry.id, zoneID: zoneID), scope: .private))
        #expect(record.encryptedValues[HouseholdRecord.Field.amount] as Int? == 1_500)

        let missing = HouseholdRecord.recordID(for: UUID(), zoneID: zoneID)
        fixture.sync.engine(for: .private).add(pendingRecordZoneChanges: [.saveRecord(missing)])
        #expect(fixture.sync.recordToSave(missing, scope: .private) == nil)
        #expect(fixture.engines[.private]?.pendingRecordZoneChanges.contains(.saveRecord(missing)) == false)
    }

    /// 取りにいくゾーンは、そのデータベースの家計のゾーンだけ（iCloud 同期のゾーンを取らない）。
    @Test func fetchesOnlyHouseholdZonesOfTheScope() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .participant)

        #expect(fixture.sync.zoneIDsToFetch(scope: .shared) == [TestSupport.householdZoneID(role: .participant)])
        #expect(fixture.sync.zoneIDsToFetch(scope: .private).isEmpty)
    }

    /// 起動のときは、家計が端末に無くても私用・共有の両方の CKSyncEngine を作る（サーバーにある家計のゾーンを見つけるため）。
    /// 家計が無ければ、取りにいく記録のゾーンは無い（ゾーンの増減だけを知る）。保存してあった状態はデータベースごとに渡す。
    @Test func startsBothEnginesEvenWithoutHousehold() throws {
        let empty = try Fixture()
        empty.sync.startEngines()
        #expect(empty.engines[.private] != nil && empty.engines[.shared] != nil)
        #expect(empty.sync.zoneIDsToFetch(scope: .private).isEmpty)
        #expect(empty.sync.zoneIDsToFetch(scope: .shared).isEmpty)
        #expect(empty.engines[.private]?.pendingDatabaseChanges.isEmpty == true)

        let joined = try Fixture()
        try joined.insertHousehold(role: .participant)
        let state = try JSONEncoder().encode(try Self.emptySerialization())
        try joined.store.setSyncState(state, scope: .shared)
        joined.sync.startEngines()
        #expect(joined.engines[.shared]?.serialization != nil)
        #expect(joined.engines[.private]?.serialization == nil)
        // 2 回目は作り直さない。
        let shared = try #require(joined.engines[.shared])
        joined.sync.startEngines()
        #expect(joined.engines[.shared] === shared)
    }

    /// CKSyncEngine の状態は、データベースごとに保存して次の起動で渡す（ここでは保存の置き場所を確かめる）。
    @Test func syncStateIsStoredPerScope() throws {
        let fixture = try Fixture()
        try fixture.store.setSyncState(Data([1, 2, 3]), scope: .private)
        try fixture.store.setSyncState(Data([4]), scope: .shared)
        try fixture.store.setSyncState(Data([5]), scope: .private)

        #expect(try fixture.store.syncState(scope: .private) == Data([5]))
        #expect(try fixture.store.syncState(scope: .shared) == Data([4]))
        #expect(try fixture.context.fetchCount(FetchDescriptor<HouseholdSyncState>()) == 2)
    }

    // MARK: - 取れた変更

    /// 端末に無い記録は取り込み、サーバーの版（システムフィールド）も残す。
    @Test func fetchedNewRecordIsInserted() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .participant)
        let id = UUID()

        fixture.sync.applyFetchedRecordChanges(
            modified: [fixture.serverRecord(id: id, role: .participant, amount: 3_000, recorderName: "たろう", modifiedAt: later)],
            deleted: [], scope: .shared
        )

        let entry = try #require(try fixture.entries().first)
        #expect(entry.id == id)
        #expect(entry.amount == 3_000)
        #expect(entry.recorderName == "たろう")
        #expect(entry.zoneName == TestSupport.householdZoneName)
        #expect(entry.modifiedAt == later)
        #expect(entry.systemFields != nil)
        #expect(fixture.changeCount == 1)
    }

    /// 同じ記録なら、直した日時の新しいほうを採る。サーバーが新しければサーバーの値にする。
    @Test func fetchedNewerServerValueWins() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry(amount: 850, modifiedAt: earlier)
        try fixture.store.insert([entry])

        fixture.sync.applyFetchedRecordChanges(
            modified: [fixture.serverRecord(id: entry.id, role: .owner, amount: 900, modifiedAt: later)], deleted: [], scope: .private
        )

        #expect(entry.amount == 900)
        #expect(entry.modifiedAt == later)
        #expect(fixture.engines[.private]?.pendingRecordZoneChanges.isEmpty ?? true)
    }

    /// 端末が新しければ端末の値を残し、送り直す（送る変更が無ければ登録する）。
    @Test func fetchedOlderServerValueKeepsLocalAndResends() throws {
        let fixture = try Fixture()
        let household = try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry(amount: 850, modifiedAt: later)
        try fixture.store.insert([entry])
        fixture.sync.startEngines()
        _ = household

        fixture.sync.applyFetchedRecordChanges(
            modified: [fixture.serverRecord(id: entry.id, role: .owner, amount: 900, modifiedAt: earlier)], deleted: [], scope: .private
        )

        #expect(entry.amount == 850)
        #expect(entry.systemFields != nil)
        let recordID = HouseholdRecord.recordID(for: entry.id, zoneID: TestSupport.householdZoneID(role: .owner))
        #expect(fixture.engines[.private]?.pendingRecordZoneChanges == [.saveRecord(recordID)])
    }

    /// サーバーで消えた記録は、端末で直している途中でも消す（削除が勝つ）。送る変更からも外す。
    @Test func fetchedDeletionWinsOverLocalEdit() throws {
        let fixture = try Fixture()
        let household = try fixture.insertHousehold(role: .participant)
        let entry = TestSupport.householdEntry(modifiedAt: later)
        try fixture.store.insert([entry])
        fixture.sync.entriesSaved([entry], in: household)
        let recordID = HouseholdRecord.recordID(for: entry.id, zoneID: TestSupport.householdZoneID(role: .participant))

        fixture.sync.applyFetchedRecordChanges(modified: [], deleted: [recordID], scope: .shared)

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.engines[.shared]?.pendingRecordZoneChanges.isEmpty == true)
    }

    /// 家計のゾーンでない記録（iCloud 同期のゾーン）や、ほかのデータベースの家計の記録は取り込まない。
    @Test func ignoresRecordsOutsideHouseholdZones() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        let foreignZone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        let foreign = CKRecord(recordType: HouseholdRecord.recordType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: foreignZone))
        foreign.encryptedValues[HouseholdRecord.Field.amount] = 500
        foreign.encryptedValues[HouseholdRecord.Field.spentAt] = TestSupport.now

        fixture.sync.applyFetchedRecordChanges(modified: [foreign], deleted: [], scope: .private)
        // 持ち主の家計のゾーンの記録でも、共有データベースから届いたことにはしない（立場が合わない）。
        fixture.sync.applyFetchedRecordChanges(
            modified: [fixture.serverRecord(id: UUID(), role: .owner, amount: 700, modifiedAt: later)], deleted: [], scope: .shared
        )

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.changeCount == 0)
    }

    // MARK: - 送った結果

    /// 送れた記録は、サーバーの版を残す（次に送るときに衝突しないため）。
    @Test func savedRecordKeepsSystemFields() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry()
        try fixture.store.insert([entry])
        let record = HouseholdRecord.record(for: entry, zoneID: TestSupport.householdZoneID(role: .owner))

        fixture.sync.applySentRecordChanges(saved: [record], failed: [], failedDeletes: [:], scope: .private)

        let restored = try #require(entry.systemFields.flatMap(HouseholdRecord.decodeSystemFields))
        #expect(restored.recordID == record.recordID)
    }

    /// 衝突（serverRecordChanged）: サーバーが新しければサーバーの値にして送り直さない。どちらでもサーバーの版の上に載せる。
    @Test func conflictTakesNewerServerValue() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry(amount: 850, modifiedAt: earlier)
        try fixture.store.insert([entry])
        let server = fixture.serverRecord(id: entry.id, role: .owner, amount: 1_000, memo: "ディナー", modifiedAt: later)
        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])

        fixture.sync.applySentRecordChanges(
            saved: [], failed: [(record: HouseholdRecord.record(for: entry, zoneID: server.recordID.zoneID), error: error)],
            failedDeletes: [:], scope: .private
        )

        #expect(entry.amount == 1_000)
        #expect(entry.memo == "ディナー")
        #expect(entry.systemFields != nil)
        #expect(fixture.engines[.private]?.pendingRecordZoneChanges.isEmpty ?? true)
    }

    /// 衝突: 端末が新しければ端末の値を残し、サーバーの版の上に載せて送り直す。
    @Test func conflictKeepsNewerLocalValueAndResends() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        fixture.sync.startEngines()
        let entry = TestSupport.householdEntry(amount: 850, modifiedAt: later)
        try fixture.store.insert([entry])
        let server = fixture.serverRecord(id: entry.id, role: .owner, amount: 1_000, modifiedAt: earlier)
        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])

        fixture.sync.applySentRecordChanges(
            saved: [], failed: [(record: HouseholdRecord.record(for: entry, zoneID: server.recordID.zoneID), error: error)],
            failedDeletes: [:], scope: .private
        )

        #expect(entry.amount == 850)
        #expect(fixture.engines[.private]?.pendingRecordZoneChanges == [.saveRecord(server.recordID)])
        let restored = try #require(entry.systemFields.flatMap(HouseholdRecord.decodeSystemFields))
        #expect(restored.recordID == server.recordID)
    }

    /// 送った版の記録がサーバーに無い（ほかの人が消した）なら、端末からも消す（削除が勝つ）。
    @Test func unknownItemDeletesLocalEntry() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .participant)
        let entry = TestSupport.householdEntry()
        try fixture.store.insert([entry])
        let record = HouseholdRecord.record(for: entry, zoneID: TestSupport.householdZoneID(role: .participant))

        fixture.sync.applySentRecordChanges(
            saved: [], failed: [(record: record, error: CKError(.unknownItem))], failedDeletes: [:], scope: .shared
        )

        #expect(try fixture.entries().isEmpty)
    }

    /// 送ったらゾーンが無かった（共有が消えた）なら、家計を片づけて知らせる。ゾーンは作り直さない。
    @Test func zoneNotFoundRemovesHousehold() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .participant)
        let entry = TestSupport.householdEntry()
        try fixture.store.insert([entry])
        let record = HouseholdRecord.record(for: entry, zoneID: TestSupport.householdZoneID(role: .participant))

        fixture.sync.applySentRecordChanges(
            saved: [], failed: [(record: record, error: CKError(.zoneNotFound))], failedDeletes: [:], scope: .shared
        )

        #expect(try fixture.store.households().isEmpty)
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.removals == [.zoneRemoved(role: .participant)])
        #expect(fixture.engines[.shared]?.pendingDatabaseChanges.isEmpty ?? true)
    }

    /// 通信の失敗などは CKSyncEngine が送り直すので、端末の記録には触れない。
    @Test func transientFailureLeavesEntryAlone() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry()
        try fixture.store.insert([entry])
        let record = HouseholdRecord.record(for: entry, zoneID: TestSupport.householdZoneID(role: .owner))

        fixture.sync.applySentRecordChanges(
            saved: [], failed: [(record: record, error: CKError(.networkFailure))], failedDeletes: [:], scope: .private
        )

        #expect(try fixture.entries().count == 1)
        #expect(fixture.removals.isEmpty)
    }

    // MARK: - ゾーンが消えたとき

    /// 参加者から見て共有が消えた（持ち主が共有をやめた・家計を消した）ら、端末の家計の記録を消して知らせる。
    @Test func deletedSharedZoneCleansUpParticipant() throws {
        let fixture = try Fixture()
        let household = try fixture.insertHousehold(role: .participant)
        try fixture.store.insert([TestSupport.householdEntry(), TestSupport.householdEntry(amount: 500)])
        fixture.sync.entriesSaved(try fixture.entries(), in: household)

        fixture.sync.applyFetchedZoneChanges(
            modified: [], deleted: [(zoneID: TestSupport.householdZoneID(role: .participant), reason: .deleted)], scope: .shared
        )

        #expect(try fixture.store.households().isEmpty)
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.removals == [.zoneRemoved(role: .participant)])
        // 消えた家計の送っていない変更も捨てる。
        #expect(fixture.engines[.shared]?.pendingRecordZoneChanges.isEmpty == true)
    }

    /// 持ち主の家計のゾーンがほかの端末で消された（iCloud の容量の画面で消したなど）ときも、端末の記録を消す。
    @Test func purgedOwnerZoneCleansUpOwner() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        try fixture.store.insert([TestSupport.householdEntry()])

        fixture.sync.applyFetchedZoneChanges(
            modified: [], deleted: [(zoneID: TestSupport.householdZoneID(role: .owner), reason: .purged)], scope: .private
        )

        #expect(try fixture.store.households().isEmpty)
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.removals == [.zoneRemoved(role: .owner)])
    }

    /// 持ち主の暗号化したデータのリセットでは、記録を残し、ゾーンを作り直して新しい記録として送り直す。
    @Test func encryptedDataResetReuploadsForOwner() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry()
        entry.systemFields = Data([1])
        try fixture.store.insert([entry])
        let zoneID = TestSupport.householdZoneID(role: .owner)

        fixture.sync.applyFetchedZoneChanges(modified: [], deleted: [(zoneID: zoneID, reason: .encryptedDataReset)], scope: .private)

        #expect(try fixture.entries().count == 1)
        #expect(entry.systemFields == nil)
        let engine = try #require(fixture.engines[.private])
        #expect(engine.pendingDatabaseChanges == [.saveZone(CKRecordZone(zoneID: zoneID))])
        #expect(engine.pendingRecordZoneChanges == [.saveRecord(HouseholdRecord.recordID(for: entry.id, zoneID: zoneID))])
        #expect(fixture.removals == [.reuploadedAfterEncryptionReset])
    }

    /// 端末に無い家計のゾーンが消えても何もしない。
    @Test func unknownZoneDeletionIsIgnored() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        let other = CKRecordZone.ID(zoneName: HouseholdZoneName.make(householdID: UUID()), ownerName: CKCurrentUserDefaultName)

        fixture.sync.applyFetchedZoneChanges(modified: [], deleted: [(zoneID: other, reason: .deleted)], scope: .private)

        #expect(try fixture.store.households().count == 1)
        #expect(fixture.removals.isEmpty)
    }

    // MARK: - 増えたゾーン

    /// 家計の無い端末で家計のゾーンが増えたら取り込む（同じ Apple アカウントのほかの端末で受け入れた家計）。表示名は空のまま。
    /// 起動のときに作った CKSyncEngine（`startEngines`）に届いたことにし、手で CKSyncEngine を作らない。取り込んだら、その家計の
    /// 記録を取りにいく（増えたゾーンは、その回の取りにいく範囲に入っていなかったため）。
    @Test func newHouseholdZoneIsAdopted() async throws {
        let fixture = try Fixture()
        fixture.sync.startEngines()
        let engine = try #require(fixture.engines[.shared])

        fixture.sync.applyFetchedZoneChanges(
            modified: [TestSupport.householdZoneID(role: .participant)], deleted: [], scope: .shared
        )

        let household = try #require(try fixture.store.currentHousehold())
        #expect(household.role == .participant)
        #expect(household.zoneOwnerName == TestSupport.householdOwnerName)
        #expect(household.memberName.isEmpty)
        #expect(fixture.changeCount == 1)
        #expect(fixture.sync.zoneIDsToFetch(scope: .shared) == [TestSupport.householdZoneID(role: .participant)])
        #expect(await HouseholdHostTests.eventually { engine.fetchCount == 1 })
    }

    /// 持ち主の家計のゾーンも、家計の無い端末（同じ Apple アカウントのほかの端末）では持ち主として取り込む。
    @Test func ownerZoneIsAdoptedAsOwner() throws {
        let fixture = try Fixture()
        fixture.sync.startEngines()

        fixture.sync.applyFetchedZoneChanges(modified: [TestSupport.householdZoneID(role: .owner)], deleted: [], scope: .private)

        let household = try #require(try fixture.store.currentHousehold())
        #expect(household.role == .owner)
        #expect(household.zoneOwnerName == CKCurrentUserDefaultName)
        #expect(household.name.isEmpty)
    }

    /// 家計がすでにある端末・家計のゾーンでないゾーン・消している途中のゾーンは取り込まない。
    @Test func zonesAreNotAdoptedWhenNotEligible() throws {
        let fixture = try Fixture()
        let household = try fixture.insertHousehold(role: .owner)
        let another = CKRecordZone.ID(zoneName: HouseholdZoneName.make(householdID: UUID()), ownerName: "_someone")
        fixture.sync.applyFetchedZoneChanges(modified: [another], deleted: [], scope: .shared)
        #expect(try fixture.store.households().count == 1)

        let fresh = try Fixture()
        fresh.sync.applyFetchedZoneChanges(
            modified: [CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)],
            deleted: [], scope: .private
        )
        #expect(try fresh.store.households().isEmpty)

        // 消した家計のゾーンは、サーバーが片づけ終える前に届いても取り込み直さない。
        fixture.sync.householdDeleted(household)
        try fixture.store.removeHousehold(zoneName: household.zoneName)
        fixture.sync.applyFetchedZoneChanges(modified: [TestSupport.householdZoneID(role: .owner)], deleted: [], scope: .private)
        #expect(try fixture.store.households().isEmpty)
        #expect(fixture.engines[.private]?.pendingDatabaseChanges == [.deleteZone(TestSupport.householdZoneID(role: .owner))])
    }

    // MARK: - アカウント

    /// iCloud からサインアウトした・アカウントを替えたら、前のアカウントの家計と同期の状態を端末から消して知らせ、状態を持たない
    /// CKSyncEngine を私用・共有の両方に作り直す（Apple のサンプルと同じ）。前の CKSyncEngine は、いま使っているものではなくなる
    /// （遅れて届いた出来事を捨てるため）。
    @Test func accountChangeWipesHouseholdDataAndRecreatesEngines() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .participant)
        try fixture.store.insert([TestSupport.householdEntry()])
        try fixture.store.setSyncState(JSONEncoder().encode(try Self.emptySerialization()), scope: .shared)
        fixture.sync.startEngines()
        let oldShared = try #require(fixture.engines[.shared])
        let oldPrivate = try #require(fixture.engines[.private])
        #expect(oldShared.serialization != nil)
        #expect(fixture.sync.isCurrent(oldShared, scope: .shared))

        fixture.sync.accountDidChange()

        #expect(try fixture.store.households().isEmpty)
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.removals == [.accountChanged])
        let newShared = try #require(fixture.engines[.shared])
        let newPrivate = try #require(fixture.engines[.private])
        #expect(newShared !== oldShared && newPrivate !== oldPrivate)
        #expect(newShared.serialization == nil && newPrivate.serialization == nil)
        #expect(!fixture.sync.isCurrent(oldShared, scope: .shared) && !fixture.sync.isCurrent(oldPrivate, scope: .private))
        #expect(fixture.sync.isCurrent(newShared, scope: .shared) && fixture.sync.isCurrent(newPrivate, scope: .private))
    }

    /// サインアウトして同じアカウントで入り直すと、作り直した CKSyncEngine が家計のゾーンを見つけて、家計を取り込み直す
    /// （サーバーには家計と共有が残っていて、家族も使い続けている）。
    @Test func householdComesBackAfterSigningInAgain() throws {
        let fixture = try Fixture()
        try fixture.insertHousehold(role: .owner)
        fixture.sync.startEngines()

        fixture.sync.accountDidChange()
        #expect(try fixture.store.currentHousehold() == nil)
        fixture.sync.applyFetchedZoneChanges(modified: [TestSupport.householdZoneID(role: .owner)], deleted: [], scope: .private)

        let household = try #require(try fixture.store.currentHousehold())
        #expect(household.zoneName == TestSupport.householdZoneName)
        #expect(household.role == .owner)
    }

    /// 家計の無い端末では、サインアウトしても知らせない。
    @Test func accountChangeWithoutHouseholdIsSilent() throws {
        let fixture = try Fixture()
        fixture.sync.accountDidChange()
        #expect(fixture.removals.isEmpty)
    }

    /// 保存してあったことにする、CKSyncEngine の状態（中身の無いもの）。
    ///
    /// `CKSyncEngine.State.Serialization` は作り方が公開されていないので、Codable の形から読んで作る。形（`data` のキーに Base64 の
    /// バイト列）は公開されていないが、ここで読めなくなったら（形が変わったら）このテストが落ちて気づける。
    static func emptySerialization() throws -> CKSyncEngine.State.Serialization {
        try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: Data(#"{"data":""}"#.utf8))
    }
}
