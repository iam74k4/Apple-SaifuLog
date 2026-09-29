import CloudKit
import Foundation
import Observation
import OSLog
import SaifuLogCore
import SwiftData

/// 家計の共有（家族・パートナー）を受け持つ。家計の保存先を開き、同期（`HouseholdSync`）を始め、家計を作る・招待する・
/// 共有をやめる・抜ける・消す、招待を受け入れる、家計の記録を書く・直す・消す。アプリで 1 つ（`SaifuLogApp` が作る）。
///
/// 機能フラグ（`HouseholdSharing.isEnabled`）が false なら何もしない（保存先も開かず、同期もせず、招待も受け入れない）。
/// 画面は `isAvailable` が true のときだけ入口を出す。
///
/// 家計の保存先は、自分の記録の保存先を開き直しても（iCloud 同期の切り替え）開き直さない。家計の同期は自分の記録の
/// iCloud 同期とは別のもので、開き直すと CKSyncEngine を作り直すことになるため。
@MainActor
@Observable
final class HouseholdHost {
    /// 家計の共有が有効か（機能フラグ。テストでは false も渡す）。
    let isEnabled: Bool
    /// このプロセスが CloudKit を使えるか（署名の無いビルドでは false。`HouseholdSharing.canUseCloudKit`）。
    let canUseCloudKit: Bool
    /// 家計の保存先。開くまでは nil（開けなかったときも nil のままで、家計の入口を出さない）。
    private(set) var container: ModelContainer?
    /// いまの家計（v1 では 1 つだけ）。入っていなければ nil。
    private(set) var currentHousehold: Household?
    /// 利用者への知らせ（作った・入った・消えたなど）。画面がアラートで出し、閉じたら nil に戻す。
    var notice: HouseholdNotice?
    /// サーバーに頼んでいる途中（ボタンを押せなくし、進行中の印を出す）。
    private(set) var isWorking = false

    @ObservationIgnored private(set) var store: HouseholdStore?
    @ObservationIgnored private(set) var sync: HouseholdSync?
    @ObservationIgnored private let openContainer: @MainActor () throws -> ModelContainer
    @ObservationIgnored private let makeEngine: HouseholdSync.EngineFactory
    @ObservationIgnored private let cloud: any HouseholdCloudService
    @ObservationIgnored private let inbox: HouseholdInvitationInbox
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.iam74k4.SaifuLog", category: "household")

    /// - Parameters:
    ///   - isEnabled: 家計の共有が有効か。アプリは機能フラグ、テストは true と false の両方を渡す。
    ///   - canUseCloudKit: CloudKit を使えるか。アプリは署名の有無から決め、テストは true（CKSyncEngine も共有も偽物なので）。
    ///   - openContainer: 家計の保存先を開く。テストはメモリの上の保存先。
    ///   - makeEngine: CKSyncEngine を作る。テストは送る変更を記録するだけの偽物。
    ///   - cloud: 共有の作成・削除・受け入れと、アカウントの確かめ。テストは偽物。
    ///   - inbox: 招待の受け皿。テストは使い捨てのもの。
    ///   - now: 記録を直した日時の基準。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    init(
        isEnabled: Bool = HouseholdSharing.isEnabled,
        canUseCloudKit: Bool = HouseholdSharing.canUseCloudKit,
        openContainer: @escaping @MainActor () throws -> ModelContainer = { try ModelContainerFactory.makeHouseholdContainer() },
        makeEngine: @escaping HouseholdSync.EngineFactory = LiveHouseholdSyncEngine.factory,
        cloud: any HouseholdCloudService = LiveHouseholdCloudService(),
        inbox: HouseholdInvitationInbox = .shared,
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.isEnabled = isEnabled
        self.canUseCloudKit = canUseCloudKit
        self.openContainer = openContainer
        self.makeEngine = makeEngine
        self.cloud = cloud
        self.inbox = inbox
        self.now = now
        self.announce = announce
    }

    /// 家計の入口（設定の「家族と共有」）を出すか。有効で、保存先を開けたときだけ。
    var isAvailable: Bool {
        isEnabled && store != nil
    }

    /// ホームで「自分／家族」を切り替えられるか（家計に入っているときだけ）。
    var hasHousehold: Bool {
        isAvailable && currentHousehold != nil
    }

    // MARK: - 始める

    /// 家計の保存先を開いて同期を始める。自分の記録の保存先を開けた後（ロックが解けた後）に呼ぶ（2 回目からは何もしない）。
    ///
    /// 開けなければ家計の入口を出さないだけにする（自分の記録は使える）。CKSyncEngine は、家計が端末に無くても私用・共有の両方を
    /// 作る（サーバーにある家計を見つけて取り込むため。`HouseholdSync.startEngines`）。
    func start() {
        guard isEnabled, !hasStarted, let marker = HouseholdSharing.enabledMarker else { return }
        hasStarted = true
        // 有効なビルドの印（release.mk が App Store へ出すビルドに無いことを確かめる）。
        logger.notice("\(marker, privacy: .public): start")
        guard canUseCloudKit else {
            // 署名の無いビルド（make build・make test-app）。CKContainer を作るとプロセスが止まるので、保存先も開かず入口も出さない
            // （出しても、家計を作る・招待を受け入れるところで止まるため）。
            logger.notice("署名の無いビルドなので、家計の共有を始めません")
            return
        }
        let container: ModelContainer
        do {
            container = try openContainer()
        } catch {
            logger.error("家計の保存先を開けませんでした: \(String(describing: error), privacy: .public)")
            // 招待のリンクで起動したときの招待が受け皿に残り続けないよう、受け取って「受け入れられなかった」と知らせる
            // （記録を置けないので受け入れない。`accept` が保存先の無いことを見て知らせる）。
            receiveInvitations()
            return
        }
        let store = HouseholdStore(context: container.mainContext)
        let sync = HouseholdSync(store: store, makeEngine: makeEngine)
        sync.householdRemoved = { [weak self] removal in self?.didRemoveHousehold(removal) }
        sync.didChange = { [weak self] in self?.reload() }
        self.container = container
        self.store = store
        self.sync = sync
        reload()
        sync.startEngines()
        receiveInvitations()
    }

    /// 招待の受け皿から招待を受け取り始める（溜まっていた招待もここで受け取る）。
    private func receiveInvitations() {
        inbox.setHandler { [weak self] invitation in
            guard let self else { return }
            Task { await self.accept(invitation) }
        }
    }

    /// いまの家計を読み直す。
    func reload() {
        currentHousehold = try? store?.currentHousehold()
    }

    // MARK: - 家計を作る・招待する（持ち主）

    /// 家計を作る。iCloud のアカウントを確かめてから（使えなければ招待を送れないので作らない）、家計のゾーンを作る変更を登録する。
    /// 作れたら nil、作れなければその理由（家計を作るシートがその場で知らせる。シートの下の画面ではアラートを出せないため）。
    func createHousehold(name: String, memberName: String) async -> HouseholdNotice? {
        guard isAvailable, let store, let sync, currentHousehold == nil, !isWorking else { return .saveFailed }
        isWorking = true
        defer { isWorking = false }
        let status = await cloud.accountStatus()
        guard status.isAvailable else {
            return .accountUnavailable(status)
        }
        let household = Household(
            zoneName: HouseholdZoneName.make(householdID: UUID()),
            zoneOwnerName: CKCurrentUserDefaultName,
            role: .owner,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            memberName: memberName.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now()
        )
        do {
            try store.insert(household)
        } catch {
            return .saveFailed
        }
        sync.householdCreated(household)
        reload()
        announce(String(localized: "家計を作りました"))
        return nil
    }

    /// 共有の画面（招待・参加している人・自分を外す）に渡す共有を用意する。持ち主なら共有を作り（まだ無ければ）、参加者なら
    /// 読む。用意できなければ知らせて nil。
    func prepareSharing() async -> HouseholdSharingPresentation? {
        guard let household = currentHousehold, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let zoneID = HouseholdSync.zoneID(for: household)
        do {
            let share = switch household.role {
            case .owner: try await cloud.ownerShare(zoneID: zoneID, title: householdTitle(household))
            case .participant: try await cloud.participantShare(zoneID: zoneID)
            }
            let cloud = cloud
            return HouseholdSharingPresentation(share: share, title: householdTitle(household), makeContainer: { cloud.makeContainer() })
        } catch {
            logger.error("共有を用意できませんでした: \(String(describing: error), privacy: .public)")
            notice = .sharingFailed
            return nil
        }
    }

    /// 共有の画面で共有をやめた・自分を外した（画面の委任先から）。参加者なら端末の家計を片づける。
    func sharingControllerDidStopSharing() {
        guard let household = currentHousehold else { return }
        switch household.role {
        case .owner:
            notice = .sharingStopped
        case .participant:
            removeLocally(household, notice: .left)
        }
    }

    /// 共有をやめる（持ち主）。家族は家計を見られなくなり、家族の端末からも家計の記録が消える。持ち主の家計と記録は残る
    /// （もう一度招待できる）。
    func stopSharing() async {
        guard let household = currentHousehold, household.role == .owner, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await cloud.deleteShare(zoneID: HouseholdSync.zoneID(for: household), scope: .private)
        } catch {
            logger.error("共有をやめられませんでした: \(String(describing: error), privacy: .public)")
            // 共有は続いている（家族はまだ家計を見られる）ことを、共有の画面を開けなかったときとは別の知らせで伝える。
            notice = .stopSharingFailed
            return
        }
        notice = .sharingStopped
        announce(String(localized: "家族との共有をやめました"))
    }

    /// 家計から抜ける（参加者）。自分を共有から外してから、端末の家計の記録を消す。
    func leaveHousehold() async {
        guard let household = currentHousehold, household.role == .participant, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await cloud.deleteShare(zoneID: HouseholdSync.zoneID(for: household), scope: .shared)
        } catch {
            // 抜けられなかった（通信できないなど）。端末の記録は消さない（抜けたつもりで家計に残るのを避ける）。
            notice = .leaveFailed
            return
        }
        removeLocally(household, notice: .left)
        announce(String(localized: "家計から抜けました"))
    }

    /// 家計を消す（持ち主）。ゾーンごと消すので、共有も消え、家族の端末からも消える。この端末の家計の記録も消す。
    func deleteHousehold() async {
        guard let household = currentHousehold, household.role == .owner, let sync, !isWorking else { return }
        sync.householdDeleted(household)
        removeLocally(household, notice: .deleted)
        announce(String(localized: "家計を削除しました"))
        // ゾーンの削除はすぐに送る（CKSyncEngine の都合の時まで待つと、その間は家族の端末に家計が残るため）。送れなければ
        // CKSyncEngine が後で送る。
        let engine = sync.engine(for: .private)
        isWorking = true
        defer { isWorking = false }
        try? await engine.sendChanges()
    }

    /// 家計の名前と自分の表示名を直す（端末の中だけ。表示名はこれから書く記録の「記録した人」に使う）。直せたら nil、
    /// 直せなければその理由（名前を直すシートがその場で知らせる）。
    ///
    /// 持ち主が直した家計の名前は、次に共有の画面を開いたとき（`prepareSharing`）に共有の題名にも書く（招待の画面と、これから
    /// 招待を開く人に出る）。すでに入っている家族の端末の家計の名前は変わらない（参加者の家計の名前はその端末の中だけのもの）。
    func updateNames(householdName: String, memberName: String) -> HouseholdNotice? {
        guard let household = currentHousehold, let store else { return .saveFailed }
        household.name = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        household.memberName = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try store.saveChanges()
        } catch {
            reload()
            return .saveFailed
        }
        reload()
        return nil
    }

    // MARK: - 招待を受け入れる（参加者）

    /// 招待を受け入れる。このアプリのゾーンごとの家計の共有だけを受け入れ、すでに家計に入っていれば受け入れない（v1 は 1 つだけ）。
    func accept(_ invitation: HouseholdInvitation) async {
        guard isEnabled else { return }
        guard let store, let sync else {
            // 保存先を開けていない（開けなかった）。受け入れても記録を置けないので知らせるだけ。
            notice = .acceptFailed
            return
        }
        guard invitation.containerIdentifier == ModelContainerFactory.iCloudContainerIdentifier,
              invitation.isZoneWideShare,
              HouseholdZoneName.isHouseholdZone(invitation.zoneID.zoneName)
        else {
            notice = .invitationInvalid
            return
        }
        if let current = currentHousehold {
            notice = current.zoneName == invitation.zoneID.zoneName ? .alreadyJoined : .anotherHousehold
            return
        }
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await cloud.accept(invitation)
        } catch {
            logger.error("招待を受け入れられませんでした: \(String(describing: error), privacy: .public)")
            notice = .acceptFailed
            return
        }
        // 受け入れている間に、同期（共有のデータベースに増えたゾーン）や同じ Apple アカウントのほかの端末から同じ家計が
        // 取り込まれていれば、それを使う。取り込んだ家計は名前が空なので、招待の題名と名前の候補で埋める。
        reload()
        if let adopted = currentHousehold, adopted.zoneName == invitation.zoneID.zoneName,
           adopted.name.isEmpty || adopted.memberName.isEmpty {
            if adopted.name.isEmpty { adopted.name = invitation.title }
            if adopted.memberName.isEmpty { adopted.memberName = invitation.suggestedMemberName }
            do {
                try store.saveChanges()
            } catch {
                // 名前を書けなくても家計には入れている（名前は設定で決められる）。
                logger.error("取り込んだ家計に名前を書けませんでした: \(String(describing: error), privacy: .public)")
            }
            reload()
        }
        if currentHousehold == nil {
            let household = Household(
                zoneName: invitation.zoneID.zoneName,
                zoneOwnerName: invitation.zoneID.ownerName,
                role: .participant,
                name: invitation.title,
                memberName: invitation.suggestedMemberName,
                createdAt: now()
            )
            do {
                try store.insert(household)
            } catch {
                notice = .saveFailed
                return
            }
            reload()
        }
        if let household = currentHousehold { sync.householdJoined(household) }
        notice = .joined
        announce(String(localized: "家計に入りました"))
    }

    // MARK: - 家計の記録

    /// 送った文の解析結果から、いまの家計の記録を作って保存し、送る変更として登録する。保存したものを返す。
    ///
    /// 記録した人は、いまの家計の自分の表示名。家計に入っていなければ throw する。
    func record(_ parsed: [ParsedEntry], sentAt: Date, calendar: Calendar) throws -> [HouseholdEntry] {
        guard let household = currentHousehold, let store, let sync else { throw HouseholdError.noHousehold }
        let entries = HouseholdEntry.records(
            from: parsed, zoneName: household.zoneName, recorderName: household.memberName, now: sentAt, calendar: calendar
        )
        try store.insert(entries)
        sync.entriesSaved(entries, in: household)
        return entries
    }

    /// 家計の記録を消し、消す変更として登録する。
    func delete(_ entries: [HouseholdEntry]) throws {
        guard let household = currentHousehold, let store, let sync else { throw HouseholdError.noHousehold }
        let ids = entries.map(\.id)
        try store.delete(entries)
        sync.entriesDeleted(ids: ids, in: household)
    }

    /// 家計の記録を直し、送る変更として登録する（直した日時も書く）。
    func update(_ entry: HouseholdEntry, with edits: EntryEdits) throws {
        guard let household = currentHousehold, let store, let sync else { throw HouseholdError.noHousehold }
        try store.update(entry, with: edits, at: now())
        sync.entriesSaved([entry], in: household)
    }

    /// 家計の記録を「直す」のシート（⑥）で直すための対象。ほかの参加者の記録も直せる（参加者は全員が読み書きできる共有のため）。
    func editTarget(
        for entry: HouseholdEntry, didSave: @escaping @MainActor () -> Void, didDelete: @escaping @MainActor () -> Void
    ) -> EditEntryModel.Target {
        EditEntryModel.Target(
            original: EntryEdits(
                amount: entry.amount, isIncome: entry.isIncome, category: entry.category, memo: entry.memo, spentAt: entry.spentAt
            ),
            originalText: "",
            source: .text,
            deletionSummary: entry.summaryText,
            // 削除の確認に、家族の端末からも消えることを添える（長押しの削除と同じ）。
            isShared: true,
            update: { [weak self] edits in
                guard let self else { throw HouseholdError.noHousehold }
                try self.update(entry, with: edits)
            },
            delete: { [weak self] in
                guard let self else { throw HouseholdError.noHousehold }
                try self.delete([entry])
            },
            didSave: didSave,
            didDelete: didDelete
        )
    }

    // MARK: - 内部

    /// 共有の題名（家計の名前。空なら「家族の家計」）。
    private func householdTitle(_ household: Household) -> String {
        household.name.isEmpty ? String(localized: "家族の家計") : household.name
    }

    /// 端末の家計の記録を消して知らせる（抜けた・消した・共有の画面で自分を外した）。
    private func removeLocally(_ household: Household, notice: HouseholdNotice) {
        if household.role == .participant { sync?.householdLeft(household) }
        do {
            try store?.removeHousehold(zoneName: household.zoneName)
        } catch {
            self.notice = .saveFailed
            return
        }
        reload()
        self.notice = notice
    }

    /// 同期で家計が端末から消えた（ゾーンが消えた・サインアウトした）。
    private func didRemoveHousehold(_ removal: HouseholdRemoval) {
        reload()
        notice = .removed(removal)
    }
}

/// 共有の画面（UICloudSharingController）に渡すもの。
struct HouseholdSharingPresentation: Identifiable {
    let id = UUID()
    let share: CKShare
    /// 共有の画面の題名（家計の名前）。
    let title: String
    /// コンテナは画面を出すときに作る（テストのプロセスで CKContainer を作ると落ちるため）。
    let makeContainer: @MainActor () -> CKContainer
}

/// 家計の記録を書けなかった理由。
enum HouseholdError: Error {
    /// 家計に入っていない（抜けた・消えた後に書こうとした）。
    case noHousehold
}

/// 家計の共有の知らせ（画面がアラートで出す）。
enum HouseholdNotice: Equatable, Identifiable {
    /// 招待を受け入れて家計に入った。
    case joined
    /// 受け入れようとした家計に、もう入っている。
    case alreadyJoined
    /// ほかの家計に入っているので受け入れなかった（v1 は 1 つだけ）。
    case anotherHousehold
    /// このアプリの家計の招待ではない。
    case invitationInvalid
    /// 招待を受け入れられなかった（通信・アカウント・招待が取り消されたなど）。
    case acceptFailed
    /// iCloud を使えないので家計を作らなかった。
    case accountUnavailable(ICloudAccountStatus)
    /// 共有の画面に渡す共有を用意できなかった・共有の画面で保存できなかった。
    case sharingFailed
    /// 共有をやめられなかった（持ち主。共有は続いていて、家族はまだ家計を見られる）。
    case stopSharingFailed
    /// 共有をやめた（持ち主）。
    case sharingStopped
    /// 家計から抜けられなかった。
    case leaveFailed
    /// 家計から抜けた（参加者）。
    case left
    /// 家計を削除した（持ち主）。
    case deleted
    /// 同期で家計が端末から消えた。
    case removed(HouseholdRemoval)
    /// 端末に保存できなかった。
    case saveFailed

    var id: String {
        switch self {
        case .joined: "joined"
        case .alreadyJoined: "alreadyJoined"
        case .anotherHousehold: "anotherHousehold"
        case .invitationInvalid: "invitationInvalid"
        case .acceptFailed: "acceptFailed"
        case .accountUnavailable: "accountUnavailable"
        case .sharingFailed: "sharingFailed"
        case .stopSharingFailed: "stopSharingFailed"
        case .sharingStopped: "sharingStopped"
        case .leaveFailed: "leaveFailed"
        case .left: "left"
        case .deleted: "deleted"
        case .removed: "removed"
        case .saveFailed: "saveFailed"
        }
    }
}
