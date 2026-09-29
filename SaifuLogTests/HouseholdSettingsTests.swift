import CloudKit
import Foundation
import SwiftData
import Testing
@testable import SaifuLog

/// 設定の「家族と共有」の節（HouseholdSettingsModel）と、家計の保存先の作り方・診断画面の家計の行。
@MainActor
struct HouseholdSettingsTests {
    // MARK: - 設定の節

    /// 家計を作るシートは、自分の表示名が空なら作らせない（家族の記録が混ざるので、だれの記録かの印が要る）。
    @Test func draftRequiresMemberName() async throws {
        let fixture = try HouseholdFixture()
        let model = HouseholdSettingsModel(host: fixture.host)

        model.presentCreation()
        var draft = try #require(model.draft)
        #expect(draft.kind == .create)
        draft.householdName = "わが家"
        draft.memberName = "  "
        #expect(!draft.canSubmit)
        #expect(await model.submit(draft) == .saveFailed)
        #expect(fixture.host.currentHousehold == nil)

        draft.memberName = "はなこ"
        #expect(await model.submit(draft) == nil)
        #expect(model.draft == nil)
        #expect(fixture.host.currentHousehold?.memberName == "はなこ")
    }

    /// 作れなかったら（iCloud を使えない）シートを閉じずに理由を返す（シートの中で知らせる）。
    @Test func creationFailureKeepsSheet() async throws {
        let fixture = try HouseholdFixture()
        fixture.cloud.state.withLock { $0.accountStatus = .restricted }
        let model = HouseholdSettingsModel(host: fixture.host)
        model.presentCreation()
        var draft = try #require(model.draft)
        draft.memberName = "はなこ"

        #expect(await model.submit(draft) == .accountUnavailable(.restricted))
        #expect(model.draft != nil)
        // 設定の画面のアラートには出さない（シートの下では出せないため）。
        #expect(fixture.host.notice == nil)
    }

    /// 名前を直すシートは、いまの名前を入れて開く。
    @Test func namesEditStartsWithCurrentNames() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .participant, memberName: "たろう")
        let model = HouseholdSettingsModel(host: fixture.host)

        model.presentNamesEdit()
        var draft = try #require(model.draft)
        // 参加者の家計の名前はこの端末の中だけのもの（シートの注記を持ち主と替える）。
        #expect(draft.kind == .edit(.participant))
        #expect(draft.householdName == "わが家")
        #expect(draft.memberName == "たろう")

        draft.memberName = "じろう"
        #expect(await model.submit(draft) == nil)
        #expect(fixture.host.currentHousehold?.memberName == "じろう")

        // 持ち主が直すときは、家計の名前が招待の画面にも出ることを注記で伝える。
        let owner = try HouseholdFixture()
        try owner.insertHousehold(role: .owner)
        let ownerModel = HouseholdSettingsModel(host: owner.host)
        ownerModel.presentNamesEdit()
        #expect(ownerModel.draft?.kind == .edit(.owner))
    }

    /// 確認のあとで、抜ける（参加者）・共有をやめる（持ち主）を実行する。
    @Test func confirmationsRunOperations() async throws {
        let participant = try HouseholdFixture()
        try participant.insertHousehold(role: .participant)
        let participantModel = HouseholdSettingsModel(host: participant.host)
        participantModel.requestConfirmation(.leave)
        #expect(!participantModel.canPresentNotice)
        await participantModel.confirm(.leave).value
        #expect(participantModel.confirmation == nil)
        #expect(participant.host.currentHousehold == nil)
        #expect(participantModel.canPresentNotice)

        let owner = try HouseholdFixture()
        try owner.insertHousehold(role: .owner)
        let ownerModel = HouseholdSettingsModel(host: owner.host)
        await ownerModel.confirm(.stopSharing).value
        #expect(owner.cloud.state.withLock { $0.deletedShares.map(\.scope) } == [.private])
        #expect(owner.host.currentHousehold != nil)
    }

    // MARK: - 家計の保存先

    /// 家計の保存先は自分の記録とは別のファイル（Application Support/household.store）で、iCloud との同期は SwiftData に任せない。
    @Test func householdStoreIsSeparateAndLocal() {
        let url = ModelContainerFactory.householdStoreURL
        #expect(url.lastPathComponent == "household.store")
        #expect(url != ModelContainerFactory.storeURL)
        #expect(url.deletingLastPathComponent().standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL)

        let configuration = ModelContainerFactory.householdConfiguration(url: url)
        #expect(configuration.url == url)
        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(configuration.groupAppContainerIdentifier == nil)
    }

    /// 家計の保存先のモデルは家計のものだけ（自分の記録のモデルと混ぜない）。
    @Test func householdSchemaListsHouseholdModels() throws {
        let container = try ModelContainerFactory.makeInMemoryHouseholdContainer()
        #expect(Set(container.schema.entities.map(\.name)) == ["Household", "HouseholdEntry", "HouseholdSyncState"])
        for configuration in container.configurations {
            #expect(configuration.isStoredInMemoryOnly)
            #expect(configuration.cloudKitContainerIdentifier == nil)
        }
    }

    /// ファイルに書いた家計の記録は、開き直しても残る（一時フォルダに開く）。
    @Test func householdFileStorePersists() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "household.store", directoryHint: .notDirectory)

        do {
            let container = try ModelContainerFactory.makeHouseholdContainer(url: url)
            try HouseholdStore(context: container.mainContext).insert([TestSupport.householdEntry(amount: 850)])
        }
        let reopened = try ModelContainerFactory.makeHouseholdContainer(url: url)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<HouseholdEntry>()).map(\.amount) == [850])
    }

    // MARK: - 診断画面

    /// 診断画面の家計の行は、件数と立場と保存先の保護クラスだけ（家族の名前や金額を入れない）。家計の共有が無効なら出さない。
    @Test func diagnosticsHouseholdRowsHaveNoPersonalData() async throws {
        let fixture = try HouseholdFixture()
        try fixture.insertHousehold(role: .participant, memberName: "たろう")
        try fixture.store.insert([TestSupport.householdEntry(amount: 12_345, memo: "焼肉", recorderName: "はなこ")])
        let context = try TestSupport.makeContext()
        let model = DiagnosticsModel(
            context: context, storeURL: URL.temporaryDirectory.appending(path: "none/default.store"),
            isProtectedDataAvailable: { true },
            speech: { DiagnosticsReport.SpeechStatus(isAvailable: false, japaneseLocale: nil, isJapaneseInstalled: false, route: "none", model: "none") },
            iCloudAccount: { .available }, copy: { _ in }, announce: { _ in }, household: fixture.host
        )

        await model.load()
        let report = try #require(model.report)

        #expect(report.value(for: "household.store") == "open")
        #expect(report.value(for: "household.role") == "participant")
        #expect(report.value(for: "household.entries") == "1")
        #expect(report.value(for: "household.memberName") == "true")
        #expect(report.value(for: "household.file.household.store") != nil)
        for secret in ["たろう", "はなこ", "焼肉", "12345", "12,345", "わが家"] {
            #expect(!report.text.contains(secret))
        }

        let disabled = try HouseholdFixture(isEnabled: false)
        let plain = DiagnosticsModel(
            context: context, storeURL: URL.temporaryDirectory.appending(path: "none/default.store"),
            isProtectedDataAvailable: { true },
            speech: { DiagnosticsReport.SpeechStatus(isAvailable: false, japaneseLocale: nil, isJapaneseInstalled: false, route: "none", model: "none") },
            iCloudAccount: { .available }, copy: { _ in }, announce: { _ in }, household: disabled.host
        )
        await plain.load()
        #expect(plain.report?.value(for: "household.store") == nil)
    }
}
