import CloudKit
import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 家計の共有の受け持ち（HouseholdHost）。機能フラグ・家計を作る・招待を受け入れる・抜ける・消す・家計の記録の書き込み。
/// CKSyncEngine と共有（CKShare）は代わりに替える。
@MainActor
struct HouseholdHostTests {
    // MARK: - 機能フラグ

    /// 機能フラグが false なら、保存先も開かず、同期もせず、招待も受け入れない（入口を出さない）。
    @Test func disabledFlagDoesNothing() async throws {
        let fixture = try HouseholdFixture(isEnabled: false)

        #expect(fixture.host.container == nil)
        #expect(!fixture.host.isAvailable)
        #expect(!fixture.host.hasHousehold)

        await fixture.host.accept(TestSupport.invitation())
        #expect(fixture.cloud.state.withLock { $0.accepted.isEmpty })
        #expect(fixture.host.notice == nil)
        #expect(fixture.engines[.shared] == nil)
    }

    /// 機能フラグは、DEBUG と社内テスト用のビルドでだけ true（テストは DEBUG のビルドで動く）。
    @Test func flagIsOnInDebugBuilds() {
        #expect(HouseholdSharing.isEnabled)
        #expect(HouseholdSharing.enabledMarker == "SaifuLog-HouseholdSharing-v1")
        // release.mk が 15 バイトまでの文字列を見落とさないよう、16 バイト以上にしている。
        #expect((HouseholdSharing.enabledMarker?.utf8.count ?? 0) >= 16)
    }

    /// 招待のリンクでアプリを開かせるキー（CKSharingSupported）は、家計の共有が有効なビルドだけにある。ほかの端末の変更の
    /// 知らせを受け取るための remote-notification は、Info.plist を分けてもどちらのビルドにも入っている。
    @Test func infoPlistMatchesFlag() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CKSharingSupported") as? Bool == HouseholdSharing.isEnabled)
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        #expect(modes.contains("remote-notification"))
    }

    /// 始めると保存先を開き、2 回目からは何もしない。家計が無くても私用・共有の両方の CKSyncEngine を作る（サーバーにある家計を
    /// 見つけるため）が、送る変更は何も登録しない。
    @Test func startOpensStoreOnce() throws {
        let fixture = try HouseholdFixture()

        #expect(fixture.host.isAvailable)
        #expect(!fixture.host.hasHousehold)
        let privateEngine = try #require(fixture.engines[.private])
        let sharedEngine = try #require(fixture.engines[.shared])
        #expect(privateEngine.pendingDatabaseChanges.isEmpty && privateEngine.pendingRecordZoneChanges.isEmpty)
        #expect(sharedEngine.pendingDatabaseChanges.isEmpty && sharedEngine.pendingRecordZoneChanges.isEmpty)
        let container = fixture.host.container
        fixture.host.start()
        #expect(fixture.host.container === container)
        #expect(fixture.engines[.private] === privateEngine)
    }

    /// CloudKit を使えないビルド（署名が無い）では、保存先も開かず、CKSyncEngine も作らず、入口を出さない
    /// （CKContainer を作るとプロセスが止まるため）。
    @Test func unsignedBuildDoesNotStart() throws {
        let engines = FakeHouseholdEngines()
        let context = try TestSupport.makeHouseholdContext()
        let host = HouseholdHost(
            isEnabled: true, canUseCloudKit: false, openContainer: { context.container }, makeEngine: engines.factory,
            cloud: FakeHouseholdCloud(), inbox: HouseholdInvitationInbox()
        )
        host.start()
        #expect(host.container == nil)
        #expect(!host.isAvailable)
        #expect(engines[.private] == nil && engines[.shared] == nil)
    }

    /// 開けなければ入口を出さない（自分の記録は使える）。
    @Test func unavailableStoreHidesEntryPoints() throws {
        let host = HouseholdHost(
            isEnabled: true, canUseCloudKit: true, openContainer: { throw TestError() }, makeEngine: FakeHouseholdEngines().factory,
            cloud: FakeHouseholdCloud(), inbox: HouseholdInvitationInbox()
        )
        host.start()
        #expect(!host.isAvailable)
    }

    /// 保存先を開けなかったときに、招待のリンクで届いていた招待は、受け入れずに「受け入れられなかった」と知らせる
    /// （受け皿に残り続けて、何も起きないままにしない）。
    @Test func invitationIsNoticedWhenStoreFailsToOpen() async throws {
        let cloud = FakeHouseholdCloud()
        let inbox = HouseholdInvitationInbox()
        inbox.deliver(TestSupport.invitation())
        let host = HouseholdHost(
            isEnabled: true, canUseCloudKit: true, openContainer: { throw TestError() }, makeEngine: FakeHouseholdEngines().factory,
            cloud: cloud, inbox: inbox
        )

        host.start()

        #expect(await Self.eventually { host.notice == .acceptFailed })
        #expect(cloud.state.withLock { $0.accepted.isEmpty })
        // 後から届いた招待も同じ。
        host.notice = nil
        inbox.deliver(TestSupport.invitation())
        #expect(await Self.eventually { host.notice == .acceptFailed })
    }

    // MARK: - 家計を作る（持ち主）

    /// iCloud を使えれば家計を作り、ゾーンを作る変更を私用データベースに登録する。
    @Test func createHouseholdRegistersZone() async throws {
        let fixture = try HouseholdFixture()

        let failure = await fixture.host.createHousehold(name: " わが家 ", memberName: " はなこ ")

        #expect(failure == nil)
        let household = try #require(fixture.host.currentHousehold)
        #expect(household.role == .owner)
        #expect(household.name == "わが家")
        #expect(household.memberName == "はなこ")
        #expect(HouseholdZoneName.isHouseholdZone(household.zoneName))
        #expect(household.zoneOwnerName == CKCurrentUserDefaultName)
        let zoneID = HouseholdSync.zoneID(for: household)
        #expect(fixture.engines[.private]?.pendingDatabaseChanges == [.saveZone(CKRecordZone(zoneID: zoneID))])
        #expect(fixture.host.hasHousehold)
        #expect(fixture.announcements == ["家計を作りました"])
    }

    /// iCloud を使えなければ作らず、理由を返す（招待を送れないため）。
    @Test func createHouseholdNeedsICloud() async throws {
        let fixture = try HouseholdFixture()
        fixture.cloud.state.withLock { $0.accountStatus = .noAccount }

        let failure = await fixture.host.createHousehold(name: "わが家", memberName: "はなこ")

        #expect(failure == .accountUnavailable(.noAccount))
        #expect(fixture.host.currentHousehold == nil)
        #expect(fixture.engines[.private]?.pendingDatabaseChanges.isEmpty == true)
    }

    /// 持ち主は共有を作って共有の画面に渡す（題名は家計の名前、空なら「家族の家計」）。
    @Test func ownerPreparesShareWithTitle() async throws {
        let fixture = try HouseholdFixture()
        let household = try fixture.insertHousehold(role: .owner)
        household.name = ""

        let presentation = await fixture.host.prepareSharing()

        #expect(presentation != nil)
        let requests = fixture.cloud.state.withLock { $0.ownerShareRequests }
        #expect(requests.map(\.title) == ["家族の家計"])
        #expect(requests.map(\.zoneID) == [TestSupport.householdZoneID(role: .owner)])
    }

    /// 持ち主が家計の名前を直したら、次に共有の画面を開くときに新しい名前を共有の題名として渡す（すでにある共有の題名も書き直す）。
    @Test func renamedHouseholdTitleGoesToShare() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)
        _ = await fixture.host.prepareSharing()

        #expect(fixture.host.updateNames(householdName: "実家", memberName: "はなこ") == nil)
        _ = await fixture.host.prepareSharing()

        #expect(fixture.cloud.state.withLock { $0.ownerShareRequests.map(\.title) } == ["わが家", "実家"])
    }

    /// 共有を用意できなければ知らせる。
    @Test func sharingFailureIsNoticed() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)
        fixture.cloud.state.withLock { $0.failsShare = true }

        #expect(await fixture.host.prepareSharing() == nil)
        #expect(fixture.host.notice == .sharingFailed)
    }

    /// 共有をやめる（持ち主）: 私用データベースの共有を消す。持ち主の家計と記録は残る。
    @Test func ownerStopsSharingButKeepsHousehold() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)
        try fixture.store.insert([TestSupport.householdEntry()])

        await fixture.host.stopSharing()

        let deleted = fixture.cloud.state.withLock { $0.deletedShares }
        #expect(deleted.map(\.scope) == [.private])
        #expect(fixture.host.currentHousehold != nil)
        #expect(try fixture.entries().count == 1)
        #expect(fixture.host.notice == .sharingStopped)
    }

    /// 共有をやめられなければ（通信できないなど）、共有の画面を開けなかったときとは別の知らせで、共有が続いていることを伝える。
    /// 家計と記録はそのまま。
    @Test func stopSharingFailureIsNoticedSeparately() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)
        try fixture.store.insert([TestSupport.householdEntry()])
        fixture.cloud.state.withLock { $0.failsDelete = true }

        await fixture.host.stopSharing()

        #expect(fixture.host.notice == .stopSharingFailed)
        #expect(fixture.host.notice != .sharingFailed)
        #expect(fixture.host.currentHousehold != nil)
        #expect(try fixture.entries().count == 1)
        #expect(fixture.announcements.isEmpty)
    }

    /// 家計を消す（持ち主）: ゾーンごと消す変更を登録してすぐ送り、この端末の家計の記録も消す。
    @Test func ownerDeletesHousehold() async throws {
        let fixture = try HouseholdFixture()
        let household = try fixture.insertHousehold(role: .owner)
        let zoneID = HouseholdSync.zoneID(for: household)
        try fixture.store.insert([TestSupport.householdEntry()])

        await fixture.host.deleteHousehold()

        #expect(fixture.host.currentHousehold == nil)
        #expect(try fixture.entries().isEmpty)
        let engine = try #require(fixture.engines[.private])
        #expect(engine.pendingDatabaseChanges == [.deleteZone(zoneID)])
        #expect(engine.sendCount == 1)
        #expect(fixture.host.notice == .deleted)
    }

    // MARK: - 招待を受け入れる（参加者）

    /// このアプリのゾーンごとの家計の共有なら受け入れ、参加者として家計を作り、共有データベースの同期を始める。
    @Test func acceptsValidInvitation() async throws {
        let fixture = try HouseholdFixture()

        await fixture.host.accept(TestSupport.invitation())

        let household = try #require(fixture.host.currentHousehold)
        #expect(household.role == .participant)
        #expect(household.zoneName == TestSupport.householdZoneName)
        #expect(household.zoneOwnerName == TestSupport.householdOwnerName)
        #expect(household.name == "わが家")
        #expect(household.memberName == "たろう")
        #expect(fixture.cloud.state.withLock { $0.accepted } == [TestSupport.householdZoneID(role: .participant)])
        #expect(fixture.engines[.shared] != nil)
        #expect(fixture.host.notice == .joined)
    }

    /// ほかのアプリのコンテナ・記録の階層の共有・家計でないゾーンの招待は受け入れない。
    @Test(arguments: [
        TestSupport.invitation(containerIdentifier: "iCloud.com.example.Other"),
        TestSupport.invitation(isZoneWideShare: false),
        TestSupport.invitation(zoneName: "Contacts"),
    ])
    func rejectsInvalidInvitation(invitation: HouseholdInvitation) async throws {
        let fixture = try HouseholdFixture()

        await fixture.host.accept(invitation)

        #expect(fixture.host.currentHousehold == nil)
        #expect(fixture.cloud.state.withLock { $0.accepted.isEmpty })
        #expect(fixture.host.notice == .invitationInvalid)
    }

    /// すでに家計に入っていれば受け入れない（v1 は 1 つだけ）。同じ家計なら「もう入っている」。
    @Test func rejectsSecondHousehold() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)

        await fixture.host.accept(TestSupport.invitation(zoneName: HouseholdZoneName.make(householdID: UUID())))
        #expect(fixture.host.notice == .anotherHousehold)

        fixture.host.notice = nil
        await fixture.host.accept(TestSupport.invitation())
        #expect(fixture.host.notice == .alreadyJoined)
        #expect(fixture.cloud.state.withLock { $0.accepted.isEmpty })
    }

    /// 受け入れられなければ知らせ、家計は作らない。
    @Test func acceptFailureIsNoticed() async throws {
        let fixture = try HouseholdFixture()
        fixture.cloud.state.withLock { $0.failsAccept = true }

        await fixture.host.accept(TestSupport.invitation())

        #expect(fixture.host.currentHousehold == nil)
        #expect(fixture.host.notice == .acceptFailed)
    }

    /// 受け入れている間に、同期が同じ家計を先に取り込んでいた（共有のデータベースにゾーンが増えた）ら、その家計を使い、空の名前を
    /// 招待の題名と名前の候補で埋める（家計を 2 つ作らない）。
    @Test func acceptFillsNamesOfHouseholdAdoptedMeanwhile() async throws {
        let fixture = try HouseholdFixture()
        let sync = try #require(fixture.host.sync)
        fixture.cloud.state.withLock { state in
            state.duringAccept = {
                sync.applyFetchedZoneChanges(
                    modified: [TestSupport.householdZoneID(role: .participant)], deleted: [], scope: .shared
                )
            }
        }

        await fixture.host.accept(TestSupport.invitation())

        #expect(try fixture.store.households().count == 1)
        let household = try #require(fixture.host.currentHousehold)
        #expect(household.name == "わが家")
        #expect(household.memberName == "たろう")
        #expect(household.role == .participant)
        #expect(fixture.host.notice == .joined)
    }

    /// サーバーにある家計（同じ Apple アカウントのほかの端末で受け入れた家計）は、起動のときに作った CKSyncEngine に届けば
    /// 取り込み、「自分／家族」を出せるようになる（手で CKSyncEngine を作らない）。
    @Test func serverHouseholdIsAdoptedAfterStart() async throws {
        let fixture = try HouseholdFixture()
        let sync = try #require(fixture.host.sync)
        #expect(sync.isCurrent(try #require(fixture.engines[.shared]), scope: .shared))

        sync.applyFetchedZoneChanges(modified: [TestSupport.householdZoneID(role: .participant)], deleted: [], scope: .shared)

        #expect(fixture.host.hasHousehold)
        #expect(fixture.host.currentHousehold?.role == .participant)
        #expect(await Self.eventually { fixture.engines[.shared]?.fetchCount == 1 })
    }

    /// iCloud からサインアウトしたら家計を消して知らせ、同じアカウントで入り直したら（作り直した CKSyncEngine に家計のゾーンが
    /// 届いたら）家計が戻る。
    @Test func householdComesBackAfterSigningInAgain() throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)
        let sync = try #require(fixture.host.sync)
        let oldPrivate = try #require(fixture.engines[.private])

        sync.accountDidChange()
        #expect(fixture.host.currentHousehold == nil)
        #expect(fixture.host.notice == .removed(.accountChanged))
        let newPrivate = try #require(fixture.engines[.private])
        #expect(newPrivate !== oldPrivate)

        sync.applyFetchedZoneChanges(modified: [TestSupport.householdZoneID(role: .owner)], deleted: [], scope: .private)
        #expect(fixture.host.currentHousehold?.role == .owner)
        #expect(fixture.host.hasHousehold)
    }

    /// 家計の保存先を開く前に届いた招待（招待のリンクで起動したとき）は、始めたときに受け入れる。
    @Test func invitationDeliveredBeforeStartIsProcessedAfterStart() async throws {
        let fixture = try HouseholdFixture(start: false)
        fixture.inbox.deliver(TestSupport.invitation())
        #expect(fixture.cloud.state.withLock { $0.accepted.isEmpty })

        fixture.host.start()
        #expect(await Self.eventually { fixture.host.currentHousehold != nil })
        #expect(fixture.host.notice == .joined)
    }

    /// 家計から抜ける（参加者）: 共有データベースの共有を消して自分を外し、端末の家計の記録を消す。
    @Test func participantLeaves() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .participant)
        try fixture.store.insert([TestSupport.householdEntry()])

        await fixture.host.leaveHousehold()

        #expect(fixture.cloud.state.withLock { $0.deletedShares.map(\.scope) } == [.shared])
        #expect(fixture.host.currentHousehold == nil)
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.host.notice == .left)
    }

    /// 抜けられなければ（通信できないなど）、端末の家計の記録は消さずに知らせる。
    @Test func leaveFailureKeepsHousehold() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .participant)
        fixture.cloud.state.withLock { $0.failsDelete = true }

        await fixture.host.leaveHousehold()

        #expect(fixture.host.currentHousehold != nil)
        #expect(fixture.host.notice == .leaveFailed)
    }

    /// 参加者が共有の画面で自分を外したら、端末の家計の記録を消す。
    @Test func sharingControllerStopForParticipantRemovesHousehold() throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .participant)

        fixture.host.sharingControllerDidStopSharing()

        #expect(fixture.host.currentHousehold == nil)
        #expect(fixture.host.notice == .left)
    }

    /// 同期で家計が消えたら（持ち主が共有をやめた）、いまの家計を読み直して知らせる。
    @Test func syncRemovalIsNoticed() throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .participant)
        let sync = try #require(fixture.host.sync)

        sync.applyFetchedZoneChanges(
            modified: [], deleted: [(zoneID: TestSupport.householdZoneID(role: .participant), reason: .deleted)], scope: .shared
        )

        #expect(fixture.host.currentHousehold == nil)
        #expect(fixture.host.notice == .removed(.zoneRemoved(role: .participant)))
    }

    // MARK: - 家計の記録

    /// 記録すると、記録した人（自分の表示名）つきで家計の保存先に入り、送る変更に登録される。
    @Test func recordSavesAndRegistersChanges() throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .participant, memberName: "たろう")

        let recorded = try fixture.host.record(
            [ParsedEntry(amount: 850, category: .food, memo: "ランチ")], sentAt: TestSupport.now, calendar: TestSupport.calendar
        )

        #expect(recorded.map(\.recorderName) == ["たろう"])
        #expect(try fixture.entries().map(\.amount) == [850])
        #expect(fixture.engines[.shared]?.savedRecordNames == recorded.map(\.id.uuidString))
    }

    /// 直すと直した日時を書き（衝突の解決に使う）、送る変更に登録する。消すと削除を登録する。
    @Test func updateAndDeleteRegisterChanges() throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry(amount: 850, modifiedAt: TestSupport.date(2026, 9, 28, hour: 9))
        try fixture.store.insert([entry])
        fixture.now = TestSupport.date(2026, 9, 28, hour: 13)

        try fixture.host.update(entry, with: EntryEdits(
            amount: 900, isIncome: false, category: .food, memo: "ランチ", spentAt: entry.spentAt
        ))
        #expect(entry.amount == 900)
        #expect(entry.modifiedAt == TestSupport.date(2026, 9, 28, hour: 13))
        #expect(fixture.engines[.private]?.savedRecordNames == [entry.id.uuidString])

        let id = entry.id
        try fixture.host.delete([entry])
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.engines[.private]?.deletedRecordNames == [id.uuidString])
        #expect(fixture.engines[.private]?.savedRecordNames.isEmpty == true)
    }

    /// 家計の記録を ⑥ で直す対象は、共有している記録として作る（削除の確認に「家族の端末からも消えます」を添える）。
    /// 自分の記録は共有していない。
    @Test func editTargetIsMarkedShared() throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)
        let entry = TestSupport.householdEntry()
        try fixture.store.insert([entry])

        let target = fixture.host.editTarget(for: entry, didSave: {}, didDelete: {})
        #expect(target.isShared)
        #expect(EditEntryModel(target: target, calendar: TestSupport.calendar).isShared)

        let context = try TestSupport.makeContext()
        let store = EntryStore(context: context)
        let personal = TestSupport.entry()
        try store.insert([personal])
        #expect(!EditEntryModel(entry: personal, store: store, calendar: TestSupport.calendar).isShared)
    }

    /// 家計に入っていなければ書けない。
    @Test func recordWithoutHouseholdThrows() throws {
        let fixture = try HouseholdFixture()
        #expect(throws: HouseholdError.self) {
            try fixture.host.record([ParsedEntry(amount: 850, category: .food, memo: "ランチ")], sentAt: TestSupport.now, calendar: TestSupport.calendar)
        }
    }

    /// 名前を直すと、端末の家計に書く（これから書く記録の「記録した人」に使う）。
    @Test func updateNames() throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .owner)

        #expect(fixture.host.updateNames(householdName: " 実家 ", memberName: " じろう ") == nil)
        #expect(fixture.host.currentHousehold?.name == "実家")
        #expect(fixture.host.currentHousehold?.memberName == "じろう")
    }

    /// 条件がそろうまで待つ（Task の中で進む受け入れを待つ）。
    static func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
