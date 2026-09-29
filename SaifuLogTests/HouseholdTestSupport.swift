import CloudKit
import Foundation
import SaifuLogCore
import SwiftData
import Synchronization
@testable import SaifuLog

/// CKSyncEngine の代わり。送る変更を記録するだけで、サーバーには何も送らない（CI では iCloud を使えないため）。
@MainActor
final class FakeHouseholdSyncEngine: HouseholdSyncEngine {
    let scope: HouseholdDatabaseScope
    /// 作ったときに渡された、保存してあった状態。
    let serialization: CKSyncEngine.State.Serialization?
    private(set) var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
    private(set) var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
    private(set) var fetchCount = 0
    private(set) var sendCount = 0

    init(scope: HouseholdDatabaseScope, serialization: CKSyncEngine.State.Serialization?) {
        self.scope = scope
        self.serialization = serialization
    }

    // CKSyncEngine と同じく、同じ変更を重ねて登録しない。
    func add(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
        for change in changes where !pendingRecordZoneChanges.contains(change) { pendingRecordZoneChanges.append(change) }
    }

    func remove(pendingRecordZoneChanges changes: [CKSyncEngine.PendingRecordZoneChange]) {
        pendingRecordZoneChanges.removeAll { changes.contains($0) }
    }

    func add(pendingDatabaseChanges changes: [CKSyncEngine.PendingDatabaseChange]) {
        for change in changes where !pendingDatabaseChanges.contains(change) { pendingDatabaseChanges.append(change) }
    }

    func remove(pendingDatabaseChanges changes: [CKSyncEngine.PendingDatabaseChange]) {
        pendingDatabaseChanges.removeAll { changes.contains($0) }
    }

    func fetchChanges() async throws { fetchCount += 1 }
    func sendChanges() async throws { sendCount += 1 }

    /// 送る変更のうち、書き込みの記録の名前。
    var savedRecordNames: [String] {
        pendingRecordZoneChanges.compactMap { if case .saveRecord(let id) = $0 { id.recordName } else { nil } }
    }

    /// 送る変更のうち、削除の記録の名前。
    var deletedRecordNames: [String] {
        pendingRecordZoneChanges.compactMap { if case .deleteRecord(let id) = $0 { id.recordName } else { nil } }
    }
}

/// CKSyncEngine の代わりを作り、データベースごとに覚えておく。
@MainActor
final class FakeHouseholdEngines {
    private(set) var engines: [HouseholdDatabaseScope: FakeHouseholdSyncEngine] = [:]

    var factory: HouseholdSync.EngineFactory {
        { [unowned self] scope, serialization, _ in
            let engine = FakeHouseholdSyncEngine(scope: scope, serialization: serialization)
            engines[scope] = engine
            return engine
        }
    }

    subscript(scope: HouseholdDatabaseScope) -> FakeHouseholdSyncEngine? {
        engines[scope]
    }
}

/// 共有の作成・削除・受け入れの代わり（CloudKit にはつながない）。
final class FakeHouseholdCloud: HouseholdCloudService {
    struct State {
        var accountStatus: ICloudAccountStatus = .available
        var failsAccept = false
        var failsDelete = false
        var failsShare = false
        var accepted: [CKRecordZone.ID] = []
        var deletedShares: [(zoneID: CKRecordZone.ID, scope: HouseholdDatabaseScope)] = []
        var ownerShareRequests: [(zoneID: CKRecordZone.ID, title: String)] = []
        /// 受け入れている途中（サーバーの返事を待つ間）に動かすこと。同期が同じ家計を先に取り込む場合を作るのに使う。
        var duringAccept: (@MainActor @Sendable () -> Void)?
    }

    let state = Mutex(State())

    func accountStatus() async -> ICloudAccountStatus {
        state.withLock { $0.accountStatus }
    }

    func ownerShare(zoneID: CKRecordZone.ID, title: String) async throws -> CKShare {
        let fails = state.withLock { state in
            state.ownerShareRequests.append((zoneID, title))
            return state.failsShare
        }
        if fails { throw TestError() }
        return CKShare(recordZoneID: zoneID)
    }

    func participantShare(zoneID: CKRecordZone.ID) async throws -> CKShare {
        if state.withLock({ $0.failsShare }) { throw TestError() }
        return CKShare(recordZoneID: zoneID)
    }

    func deleteShare(zoneID: CKRecordZone.ID, scope: HouseholdDatabaseScope) async throws {
        let fails = state.withLock { state in
            if !state.failsDelete { state.deletedShares.append((zoneID, scope)) }
            return state.failsDelete
        }
        if fails { throw TestError() }
    }

    func accept(_ invitation: HouseholdInvitation) async throws {
        let (fails, duringAccept) = state.withLock { state in
            if !state.failsAccept { state.accepted.append(invitation.zoneID) }
            return (state.failsAccept, state.duringAccept)
        }
        if let duringAccept { await duringAccept() }
        if fails { throw TestError() }
    }

    func makeContainer() -> CKContainer {
        // テストのプロセスは iCloud の entitlement を持たないので、コンテナを作ると落ちる。共有の画面はテストで出さない。
        fatalError("テストで CKContainer を作らない")
    }
}

extension TestSupport {
    /// 家計のゾーンの名前（決まった UUID）。
    static let householdZoneName = HouseholdZoneName.make(householdID: UUID(uuidString: "5B1F7C1E-3C2A-4F7E-9E1D-2A6B8C0D4E5F")!)
    /// 家計の持ち主（参加者から見たゾーンの ownerName）。
    static let householdOwnerName = "_owner0123456789abcdef"

    /// メモリの上の家計の保存先（テストごとに新しいもの）。
    @MainActor
    static func makeHouseholdContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeInMemoryHouseholdContainer()
        retainedHouseholdContainers.append(container)
        return container.mainContext
    }

    @MainActor private static var retainedHouseholdContainers: [ModelContainer] = []

    /// 家計の記録（テスト用）。
    static func householdEntry(
        id: UUID = UUID(), zoneName: String = householdZoneName, amount: Int = 850, memo: String = "ランチ",
        category: EntryCategory = .food, recorderName: String = "はなこ", spentAt: Date = now, createdAt: Date = now,
        modifiedAt: Date = now
    ) -> HouseholdEntry {
        HouseholdEntry(
            id: id, zoneName: zoneName, amount: amount, isIncome: false, category: category, memo: memo, spentAt: spentAt,
            recorderName: recorderName, createdAt: createdAt, modifiedAt: modifiedAt
        )
    }

    /// 家計（テスト用）。
    static func household(role: HouseholdRole, zoneName: String = householdZoneName, memberName: String = "はなこ") -> Household {
        Household(
            zoneName: zoneName,
            zoneOwnerName: role == .owner ? CKCurrentUserDefaultName : householdOwnerName,
            role: role,
            name: "わが家",
            memberName: memberName,
            createdAt: now
        )
    }

    /// 家計のゾーンの ID（持ち主なら自分、参加者なら持ち主の名前）。
    static func householdZoneID(role: HouseholdRole, zoneName: String = householdZoneName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: role == .owner ? CKCurrentUserDefaultName : householdOwnerName)
    }

    /// 家計への招待（テスト用。メタデータは持たない）。
    static func invitation(
        containerIdentifier: String = ModelContainerFactory.iCloudContainerIdentifier,
        zoneName: String = householdZoneName,
        isZoneWideShare: Bool = true
    ) -> HouseholdInvitation {
        HouseholdInvitation(
            containerIdentifier: containerIdentifier,
            zoneID: householdZoneID(role: .participant, zoneName: zoneName),
            isZoneWideShare: isZoneWideShare,
            title: "わが家",
            suggestedMemberName: "たろう"
        )
    }
}

/// 家計の共有の受け持ち（HouseholdHost）と、その保存先・CKSyncEngine の代わり・共有の代わり。
@MainActor
final class HouseholdFixture {
    let context: ModelContext
    let engines = FakeHouseholdEngines()
    let cloud = FakeHouseholdCloud()
    let inbox = HouseholdInvitationInbox()
    var now = TestSupport.now
    private(set) var announcements: [String] = []
    private(set) var host: HouseholdHost!

    /// - Parameters:
    ///   - isEnabled: 家計の共有が有効か（機能フラグ）。
    ///   - start: 作ったらすぐ始めるか。
    init(isEnabled: Bool = true, start: Bool = true) throws {
        let context = try TestSupport.makeHouseholdContext()
        self.context = context
        host = HouseholdHost(
            isEnabled: isEnabled,
            // テストのプロセスは署名が無く CloudKit を使えないが、CKSyncEngine も共有も偽物なので使えることにする。
            canUseCloudKit: true,
            openContainer: { context.container },
            makeEngine: engines.factory,
            cloud: cloud,
            inbox: inbox,
            now: { [unowned self] in now },
            announce: { [unowned self] in announcements.append($0) }
        )
        if start { host.start() }
    }

    var store: HouseholdStore {
        HouseholdStore(context: context)
    }

    /// 家計を端末に直接置く（同期は始めない）。
    @discardableResult
    func insertHousehold(role: HouseholdRole, memberName: String = "はなこ") throws -> Household {
        let household = TestSupport.household(role: role, memberName: memberName)
        try store.insert(household)
        host.reload()
        return household
    }

    func entries() throws -> [HouseholdEntry] {
        try context.fetch(FetchDescriptor<HouseholdEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    }
}
