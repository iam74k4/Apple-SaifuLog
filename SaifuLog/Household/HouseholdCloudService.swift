import CloudKit
import Foundation

/// 家計の共有のうち、CloudKit のサーバーに直接頼むもの（アカウントの確かめ・共有の作成と削除・招待の受け入れ）。
///
/// 記録の同期は CKSyncEngine（`HouseholdSync`）に任せ、ここでは共有（CKShare）の出し入れだけをする。iCloud の entitlement の
/// 無いテストのプロセスで `CKContainer` を作ると落ちるので、テストでは偽物に差し替える。
protocol HouseholdCloudService: Sendable {
    /// iCloud のアカウントの状態（家計を作る前に確かめる。使えなければ招待を送れないため）。
    func accountStatus() async -> ICloudAccountStatus
    /// 持ち主の家計のゾーンの共有を読む（まだ無ければ作る）。ゾーンがまだサーバーに無ければ先に作る。題名（家計の名前）が
    /// 変わっていれば、共有の題名も書き直す。
    func ownerShare(zoneID: CKRecordZone.ID, title: String) async throws -> CKShare
    /// 参加者として入っている家計のゾーンの共有を読む（参加している人を見る・自分を外す画面に使う）。
    func participantShare(zoneID: CKRecordZone.ID) async throws -> CKShare
    /// 共有を消す。持ち主なら共有をやめる（参加者は家計を見られなくなる）。参加者なら自分を外す（CloudKit は、参加者が共有を
    /// 消そうとするとその人を外す。Apple の CKShare の説明）。
    func deleteShare(zoneID: CKRecordZone.ID, scope: HouseholdDatabaseScope) async throws
    /// 招待を受け入れる（CKAcceptSharesOperation）。
    func accept(_ invitation: HouseholdInvitation) async throws
    /// 共有の画面（UICloudSharingController）に渡すコンテナを作る。画面を出すときだけ呼ぶ。
    func makeContainer() -> CKContainer
}

/// 家計の共有への招待（CloudKit が渡す共有のメタデータから、決め事に要るものを取り出したもの）。
struct HouseholdInvitation: Sendable {
    /// 招待のコンテナ（このアプリのコンテナでなければ受け入れない）。
    let containerIdentifier: String
    /// 共有したゾーン。
    let zoneID: CKRecordZone.ID
    /// ゾーンごとの共有か（記録の階層の共有は、このアプリでは作らないので受け入れない）。
    let isZoneWideShare: Bool
    /// 家計の名前（共有の題名）。
    let title: String
    /// 自分の表示名の候補（招待した人が付けた名前など。無ければ空）。
    let suggestedMemberName: String
    /// CloudKit が渡したメタデータ（受け入れに使う）。テストでは nil。
    let metadata: CKShare.Metadata?

    init(
        containerIdentifier: String, zoneID: CKRecordZone.ID, isZoneWideShare: Bool, title: String,
        suggestedMemberName: String, metadata: CKShare.Metadata? = nil
    ) {
        self.containerIdentifier = containerIdentifier
        self.zoneID = zoneID
        self.isZoneWideShare = isZoneWideShare
        self.title = title
        self.suggestedMemberName = suggestedMemberName
        self.metadata = metadata
    }

    /// CloudKit が渡した共有のメタデータから作る。
    init(metadata: CKShare.Metadata) {
        let share = metadata.share
        let nameComponents = share.currentUserParticipant?.userIdentity.nameComponents
        self.init(
            containerIdentifier: metadata.containerIdentifier,
            zoneID: share.recordID.zoneID,
            isZoneWideShare: share.recordID.recordName == CKRecordNameZoneWideShare,
            title: share[CKShare.SystemFieldKey.title] as? String ?? "",
            suggestedMemberName: nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } ?? "",
            metadata: metadata
        )
    }
}

/// 本物の CloudKit に頼む（アプリだけが使う）。
struct LiveHouseholdCloudService: HouseholdCloudService {
    let containerIdentifier: String

    init(containerIdentifier: String = ModelContainerFactory.iCloudContainerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    func makeContainer() -> CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    func accountStatus() async -> ICloudAccountStatus {
        await ICloudAccountStatus.current(containerIdentifier: containerIdentifier)
    }

    func ownerShare(zoneID: CKRecordZone.ID, title: String) async throws -> CKShare {
        let database = makeContainer().privateCloudDatabase
        // ゾーンの共有は、ゾーンがサーバーにあるときだけ作れる。CKSyncEngine がまだ送っていないことがあるので、ここでも作る
        // （同じゾーンを作り直しても中身は消えない）。
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            if let share = try await database.record(for: shareID) as? CKShare {
                return await retitled(share, to: title, in: database)
            }
        } catch let error as CKError where error.code == .unknownItem {
            // まだ共有していない。下で作る。
        }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = title
        // 招待した人だけが入れるようにする（リンクを知っているだけでは入れない）。参加者の権限は共有の画面で読み書きにする。
        share.publicPermission = .none
        let (saveResults, _) = try await database.modifyRecords(saving: [share], deleting: [])
        guard let saved = try saveResults[share.recordID]?.get() as? CKShare else { return share }
        return saved
    }

    /// 共有の題名が家計の名前と違えば書き直して保存する（持ち主が家計の名前を直した後）。
    ///
    /// 共有の画面は、すでにある共有の題名を共有そのものから読む（`UICloudSharingControllerDelegate.itemTitle(for:)` は新しい共有を
    /// 作るときにしか呼ばれない。Apple の説明）ので、書き直さないと、招待の画面とこれから招待を開く人に前の名前が出続けるため。
    /// 書き直せなくても（通信できないなど）共有の画面は開けるので、前の題名のまま返す。
    private func retitled(_ share: CKShare, to title: String, in database: CKDatabase) async -> CKShare {
        let previous = share[CKShare.SystemFieldKey.title] as? String
        guard previous != title else { return share }
        share[CKShare.SystemFieldKey.title] = title
        do {
            let (saveResults, _) = try await database.modifyRecords(saving: [share], deleting: [])
            return try saveResults[share.recordID]?.get() as? CKShare ?? share
        } catch {
            share[CKShare.SystemFieldKey.title] = previous
            return share
        }
    }

    func participantShare(zoneID: CKRecordZone.ID) async throws -> CKShare {
        let database = makeContainer().sharedCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        guard let share = try await database.record(for: shareID) as? CKShare else { throw CKError(.unknownItem) }
        return share
    }

    func deleteShare(zoneID: CKRecordZone.ID, scope: HouseholdDatabaseScope) async throws {
        let container = makeContainer()
        let database = scope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            _ = try await database.modifyRecords(saving: [], deleting: [shareID])
        } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
            // もう共有が無い（ほかの端末でやめた・持ち主が消した）。やめたのと同じなので失敗にしない。
        }
    }

    func accept(_ invitation: HouseholdInvitation) async throws {
        guard let metadata = invitation.metadata else { throw CKError(.invalidArguments) }
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        operation.qualityOfService = .userInitiated
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // 共有ごとの結果は、1 つだけ渡しているので、全体の結果で決める（失敗は acceptSharesResultBlock にも来る）。
            operation.acceptSharesResultBlock = { result in
                continuation.resume(with: result)
            }
            makeContainer().add(operation)
        }
    }
}
