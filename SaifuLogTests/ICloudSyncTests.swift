import CloudKit
import Combine
import CoreData
import Foundation
import SwiftData
import Testing
@testable import SaifuLog

/// iCloud 同期（設定の「iCloud で同期」。既定はオフ）の切り替え。
///
/// 本物の CloudKit にはつながない（署名なしのテストのプロセスは iCloud の entitlement を持たず、`CKContainer` を作ると
/// 落ちる）。保存先を開く処理と iCloud のアカウントの問い合わせを差し替えて、どの iCloud の扱いで開き直すか、開けなければ
/// 端末の中だけに戻すか、設定に何を書くかを確かめる。実際に 2 台の端末でそろうかは実機で確かめる（docs/design.md §15）。
@MainActor
struct ICloudSyncTests {
    typealias FakeStore = StoreHostTests.FakeStore

    /// 使い捨ての設定の領域（テストの終わりに消す）。
    @MainActor
    final class Settings {
        let suiteName = "ICloudSyncTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
        }

        var syncEnabled: Bool { defaults.bool(for: AppSettings.iCloudSyncEnabled) }
        /// 書いたかどうか（書いていなければ nil）。
        var storedSyncEnabled: Bool? { defaults.object(forKey: AppSettings.iCloudSyncEnabled.key) as? Bool }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// iCloud のアカウントの問い合わせの代わり。答えと、問い合わせた回数を持つ。
    @MainActor
    final class Account {
        var status: ICloudAccountStatus
        private(set) var queries = 0

        init(_ status: ICloudAccountStatus) {
            self.status = status
        }

        func query() -> ICloudAccountStatus {
            queries += 1
            return status
        }
    }

    static func container(of host: StoreHost) -> ModelContainer? {
        if case .ready(let container) = host.state { container } else { nil }
    }

    static func isReopening(_ host: StoreHost) -> Bool {
        if case .reopening = host.state { true } else { false }
    }

    static func isUnavailable(_ host: StoreHost) -> Bool {
        if case .unavailable = host.state { true } else { false }
    }

    /// iCloud と同期する保存先を開くときに、iCloud のせいで本当に起こる失敗（本物の SwiftData のエラー）。
    ///
    /// CloudKit の制約に合わないモデルを iCloud と同期する保存先として開くと、SwiftData は開くときに失敗する。サインインして
    /// いない・容量が足りないでは開けなくならない（`ICloudSyncFailure`）ので、戻す仕組みのテストにはこれを使う。
    static func cloudKitRejection() throws -> any Error {
        let directory = URL.temporaryDirectory.appending(path: "ICloudSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([CloudKitIncompatibleSample.self])
        let configuration = ModelConfiguration(
            schema: schema,
            url: directory.appending(path: "rejected.store", directoryHint: .notDirectory),
            cloudKitDatabase: .private(ModelContainerFactory.iCloudContainerIdentifier)
        )
        do {
            _ = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            return error
        }
        Issue.record("CloudKit の制約に合わないモデルなのに、iCloud と同期する保存先として開けた（戻す仕組みが働かない）")
        return TestError()
    }

    /// iPhone の空き容量が無いときのエラー（iCloud のせいではない。同じファイルなので、iCloud の扱いを替えても開けない）。
    static let diskFull = NSError(domain: NSPOSIXErrorDomain, code: 28)

    static func makeSettingsModel(host: StoreHost?, account: Account, settings: Settings) throws -> SettingsModel {
        try makeSettingsModel(host: host, accountStatus: { account.query() }, settings: settings)
    }

    static func makeSettingsModel(
        host: StoreHost?, accountStatus: @escaping @MainActor () async -> ICloudAccountStatus, settings: Settings
    ) throws -> SettingsModel {
        SettingsModel(
            context: try TestSupport.makeContext(),
            storeHost: host,
            accountStatus: accountStatus,
            defaults: settings.defaults,
            exporter: LedgerExporter(
                container: try ModelContainerFactory.makeInMemoryContainer(),
                directory: URL.temporaryDirectory.appending(path: "ICloudSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            ),
            announce: { _ in }
        )
    }

    // MARK: - 既定

    /// 既定はオフ。アプリは設定の値で最初の保存先を開くので、何も選んでいなければ端末の中だけに開く。
    @Test func defaultsToLocalStore() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let database = ModelContainerFactory.CloudKitDatabase(syncEnabled: settings.syncEnabled)
        let host = store.makeHost(cloudKitDatabase: database, defaults: settings.defaults)

        host.start()

        #expect(database == .none)
        #expect(store.openedWith == [.none])
        #expect(host.iCloudFallback == nil)
    }

    /// 設定がオンなら、iCloud と同期する保存先で開く。
    @Test func opensICloudStoreWhenSettingIsOn() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        settings.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = FakeStore()
        let host = store.makeHost(
            cloudKitDatabase: .init(syncEnabled: settings.syncEnabled), defaults: settings.defaults
        )

        host.start()

        #expect(store.openedWith == [.private])
        #expect(host.cloudKitDatabase == .private)
        #expect(Self.container(of: host) != nil)
    }

    // MARK: - StoreHost の切り替え

    /// オンにすると、設定に書いてから iCloud と同期する保存先で開き直す。開き直したら設定の画面に戻し、読み上げる。
    @Test func turningOnReopensWithICloudStore() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let host = store.makeHost(defaults: settings.defaults)
        host.start()
        let first = try #require(Self.container(of: host))

        host.setICloudSyncEnabled(true)
        #expect(Self.isReopening(host))
        #expect(settings.syncEnabled)
        #expect(store.openedWith == [.none])

        await host.finishReopening()

        let second = try #require(Self.container(of: host))
        #expect(second !== first)
        #expect(store.openedWith == [.none, .private])
        #expect(host.cloudKitDatabase == .private)
        #expect(host.iCloudFallback == nil)
        #expect(store.announcements == ["iCloud での同期をオンにしました"])
        // 設定の画面に戻すのは、開き直した直後の 1 回だけ。
        #expect(host.consumeSettingsRestoration())
        #expect(!host.consumeSettingsRestoration())
    }

    /// オフにすると、端末の中だけの保存先で開き直す（同じファイルなので、この端末の記録は残る。`ModelContainerFactoryTests`）。
    @Test func turningOffReopensWithLocalStore() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        settings.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = FakeStore()
        let host = store.makeHost(cloudKitDatabase: .private, defaults: settings.defaults)
        host.start()

        host.setICloudSyncEnabled(false)
        await host.finishReopening()

        #expect(store.openedWith == [.private, .none])
        #expect(host.cloudKitDatabase == .none)
        #expect(settings.storedSyncEnabled == false)
        #expect(store.announcements == ["iCloud での同期をオフにしました。記録はこの iPhone に残っています"])
        #expect(host.consumeSettingsRestoration())
    }

    /// iCloud と同期する保存先を開けず、端末の中だけの保存先としてなら開けたら、そちらに戻して設定もオフに戻し、理由を残す。
    /// 「オンにしました」とは読み上げない。
    @Test func fallsBackToLocalStoreWhenICloudStoreFails() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let rejection = try Self.cloudKitRejection()
        let store = FakeStore()
        store.failuresByDatabase[.private] = rejection
        let host = store.makeHost(defaults: settings.defaults)
        host.start()

        host.setICloudSyncEnabled(true)
        await host.finishReopening()

        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith == [.none, .private, .none])
        #expect(host.cloudKitDatabase == .none)
        #expect(settings.storedSyncEnabled == false)
        let rejected = rejection as NSError
        #expect(host.iCloudFallback == ICloudSyncFailure(domain: rejected.domain, code: rejected.code))
        #expect(store.announcements.isEmpty)
        // どうなったかを見せるため、戻したときも設定の画面に戻す。
        #expect(host.consumeSettingsRestoration())

        host.acknowledgeICloudFallback()
        #expect(host.iCloudFallback == nil)
    }

    /// 起動したときに iCloud と同期する保存先を開けなくても、再試行の画面で止めずに端末の中だけで開く。
    @Test func fallsBackAtLaunch() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        settings.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = FakeStore()
        store.failuresByDatabase[.private] = try Self.cloudKitRejection()
        let host = store.makeHost(cloudKitDatabase: .private, defaults: settings.defaults)

        host.start()

        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith == [.private, .none])
        #expect(settings.storedSyncEnabled == false)
        #expect(host.iCloudFallback != nil)
        // 起動したときは設定の画面を開いていないので、戻さない（知らせのアラートだけ）。
        #expect(!host.consumeSettingsRestoration())
    }

    /// 端末の中だけの保存先としても開けなければ、iCloud のせいではないので戻さない。ふだんと同じく再試行の画面を出し、
    /// 戻したという知らせは出さず（開けていないのに「この iPhone の中だけに保存しています」と言わない）、設定も変えない。
    /// 再試行はまた iCloud と同期する保存先から開く。
    @Test func fallbackThatAlsoFailsShowsRetry() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        settings.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = FakeStore()
        store.failures = [TestError(), TestError()]
        let host = store.makeHost(cloudKitDatabase: .private, defaults: settings.defaults)

        host.start()

        guard case .unavailable = host.state else {
            Issue.record("再試行の画面になっていない: \(host.state)")
            return
        }
        #expect(store.openedWith == [.private, .none])
        #expect(host.iCloudFallback == nil)
        #expect(host.cloudKitDatabase == .private)
        #expect(settings.storedSyncEnabled == true)

        host.retry()
        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith == [.private, .none, .private])
        #expect(host.cloudKitDatabase == .private)
        #expect(host.iCloudFallback == nil)
        #expect(settings.storedSyncEnabled == true)
    }

    /// iPhone の空き容量が無いなど、iCloud と関係のない理由で開けないときは、同期をオフに戻さない（空けた後も同期が
    /// オフのまま、にしない）。空けた後の再試行で、まだ iCloud と同期する保存先だけを開けなければ、そこで戻す。
    @Test func nonICloudFailureKeepsSyncSetting() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        settings.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = FakeStore()
        store.failures = [Self.diskFull, Self.diskFull]
        let host = store.makeHost(cloudKitDatabase: .private, defaults: settings.defaults)

        host.start()

        #expect(Self.isUnavailable(host))
        #expect(store.openedWith == [.private, .none])
        #expect(host.cloudKitDatabase == .private)
        #expect(settings.storedSyncEnabled == true)
        #expect(host.iCloudFallback == nil)

        // 空き容量を空けたが、iCloud と同期する保存先は（CloudKit の制約に合わず）開けないまま。
        store.failuresByDatabase[.private] = try Self.cloudKitRejection()
        host.retry()

        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith == [.private, .none, .private, .none])
        #expect(host.cloudKitDatabase == .none)
        #expect(settings.storedSyncEnabled == false)
        #expect(host.iCloudFallback != nil)
        #expect(host.failedRetryCount == 0)
    }

    /// 設定でオンにした直後に、どちらの保存先としても開けなければ、再試行の画面にする（戻したという知らせは出さない）。
    /// 設定は利用者が選んだオンのまま。
    @Test func turningOnWhenNeitherStoreOpensShowsRetry() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let host = store.makeHost(defaults: settings.defaults)
        host.start()
        store.failures = [Self.diskFull, Self.diskFull]

        host.setICloudSyncEnabled(true)
        await host.finishReopening()

        #expect(Self.isUnavailable(host))
        #expect(store.openedWith == [.none, .private, .none])
        #expect(host.cloudKitDatabase == .private)
        #expect(settings.storedSyncEnabled == true)
        #expect(host.iCloudFallback == nil)
        #expect(store.announcements.isEmpty)
    }

    /// 端末の中だけの保存先として開き直している途中でロックされたら、戻さずにロックの解除を待つ。解けたら、また iCloud と
    /// 同期する保存先から開く。
    @Test func lockDuringFallbackOpenWaitsWithoutFallback() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        settings.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = FakeStore()
        store.failuresByDatabase[.private] = try Self.cloudKitRejection()
        store.locksDuringNextOpenOf = ModelContainerFactory.CloudKitDatabase.none
        let host = store.makeHost(cloudKitDatabase: .private, defaults: settings.defaults)

        host.start()

        #expect(host.isWaitingForProtectedData)
        #expect(!Self.isUnavailable(host))
        #expect(store.openedWith == [.private, .none])
        #expect(host.cloudKitDatabase == .private)
        #expect(settings.storedSyncEnabled == true)
        #expect(host.iCloudFallback == nil)

        store.protectedDataAvailable = true
        host.protectedDataMayBeAvailable()

        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith == [.private, .none, .private, .none])
        #expect(host.cloudKitDatabase == .none)
        #expect(settings.storedSyncEnabled == false)
        #expect(host.iCloudFallback != nil)
    }

    /// 開いている途中でロックされたのは iCloud のせいではないので、戻さずにロックの解除を待ち、iCloud のまま開く。
    @Test func lockDuringICloudOpenWaitsWithoutFallback() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        settings.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = FakeStore()
        store.locksDuringNextOpen = true
        let host = store.makeHost(cloudKitDatabase: .private, defaults: settings.defaults)

        host.start()
        #expect(host.isWaitingForProtectedData)
        #expect(host.cloudKitDatabase == .private)
        #expect(host.iCloudFallback == nil)
        #expect(settings.syncEnabled)

        store.protectedDataAvailable = true
        host.protectedDataMayBeAvailable()
        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith == [.private, .private])
    }

    /// いまと同じ値や、開く前（読み込み中）の切り替えは受け付けない（設定を書いたのに開き直さない、を避ける）。
    @Test func ignoresSameValueAndSwitchWhileLoading() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        store.protectedDataAvailable = false
        let host = store.makeHost(defaults: settings.defaults)
        host.start()

        host.setICloudSyncEnabled(true)
        #expect(settings.storedSyncEnabled == nil)
        #expect(host.cloudKitDatabase == .none)

        store.protectedDataAvailable = true
        host.protectedDataMayBeAvailable()
        host.setICloudSyncEnabled(false)
        #expect(settings.storedSyncEnabled == nil)
        #expect(store.openedWith == [.none])
        #expect(!host.consumeSettingsRestoration())
    }

    // MARK: - 設定の画面

    /// 保存先を開いたもの（StoreHost）を渡されなければ、iCloud の節を出さない（テストとプレビュー）。
    @Test func settingsHideICloudWithoutStoreHost() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let model = try Self.makeSettingsModel(host: nil, account: Account(.available), settings: settings)

        #expect(!model.showsICloudSync)
        #expect(!model.isICloudSyncEnabled)
        #expect(model.requestICloudSync(true) == nil)
        #expect(model.iCloudSyncConfirmation == nil)
    }

    /// オンにするときは、iCloud のアカウントを確かめてから説明を出す。説明で「オンにする」を押すまで切り替えない。
    @Test func settingsTurnOnAfterAccountCheckAndConfirmation() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let host = store.makeHost(defaults: settings.defaults)
        host.start()
        let account = Account(.available)
        let model = try Self.makeSettingsModel(host: host, account: account, settings: settings)
        #expect(model.showsICloudSync)
        #expect(!model.isICloudSyncEnabled)

        let checking = try #require(model.requestICloudSync(true))
        #expect(model.isCheckingICloudAccount)
        // 確かめている途中は、もう一度押しても受け付けない。
        #expect(model.requestICloudSync(true) == nil)
        await checking.value

        #expect(!model.isCheckingICloudAccount)
        #expect(account.queries == 1)
        #expect(model.iCloudSyncConfirmation == .enable)
        #expect(model.iCloudAccountAlert == nil)
        // まだ切り替えていない（説明を読んでやめられる）。
        #expect(store.openedWith == [.none])
        #expect(settings.storedSyncEnabled == nil)

        model.confirmICloudSync(.enable)
        #expect(model.iCloudSyncConfirmation == nil)
        #expect(Self.isReopening(host))
        await host.finishReopening()
        #expect(store.openedWith == [.none, .private])
        #expect(settings.syncEnabled)
    }

    /// iCloud を使えなければ、切り替えずに案内だけを出す。
    @Test(arguments: [
        ICloudAccountStatus.noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine,
        .failed(domain: CKError.errorDomain, code: CKError.Code.networkUnavailable.rawValue),
    ])
    func settingsShowGuidanceWhenAccountUnavailable(status: ICloudAccountStatus) async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let host = store.makeHost(defaults: settings.defaults)
        host.start()
        let model = try Self.makeSettingsModel(host: host, account: Account(status), settings: settings)

        await model.requestICloudSync(true)?.value

        #expect(model.iCloudAccountAlert == status)
        #expect(status.guidanceText?.isEmpty == false)
        #expect(model.iCloudSyncConfirmation == nil)
        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith == [.none])
        #expect(settings.storedSyncEnabled == nil)
    }

    /// オフにするときは、アカウントを確かめずに説明を出し、「オフにする」を押したら端末の中だけで開き直す。
    @Test func settingsTurnOffAfterConfirmation() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        settings.defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let store = FakeStore()
        let host = store.makeHost(cloudKitDatabase: .private, defaults: settings.defaults)
        host.start()
        let account = Account(.available)
        let model = try Self.makeSettingsModel(host: host, account: account, settings: settings)
        #expect(model.isICloudSyncEnabled)

        #expect(model.requestICloudSync(false) == nil)
        #expect(model.iCloudSyncConfirmation == .disable)
        #expect(account.queries == 0)

        model.confirmICloudSync(.disable)
        await host.finishReopening()
        #expect(store.openedWith == [.private, .none])
        #expect(settings.storedSyncEnabled == false)
    }

    /// いまと同じ値への切り替え（トグルの描き直しなど）は何もしない。
    @Test func settingsIgnoreSameValue() throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let host = store.makeHost(defaults: settings.defaults)
        host.start()
        let account = Account(.available)
        let model = try Self.makeSettingsModel(host: host, account: account, settings: settings)

        #expect(model.requestICloudSync(false) == nil)
        #expect(model.iCloudSyncConfirmation == nil)
        #expect(account.queries == 0)
    }

    /// 同期がオンのときだけ、画面を開いたときにアカウントを確かめ、使えなければ案内を出せるようにする。
    @Test func settingsRefreshAccountOnlyWhenEnabled() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }

        let offStore = FakeStore()
        let offHost = offStore.makeHost(defaults: settings.defaults)
        offHost.start()
        let offAccount = Account(.noAccount)
        let offModel = try Self.makeSettingsModel(host: offHost, account: offAccount, settings: settings)
        await offModel.refreshICloudAccountStatus()
        #expect(offAccount.queries == 0)
        #expect(offModel.iCloudAccountStatus == nil)

        let onStore = FakeStore()
        let onHost = onStore.makeHost(cloudKitDatabase: .private, defaults: settings.defaults)
        onHost.start()
        let onAccount = Account(.noAccount)
        let onModel = try Self.makeSettingsModel(host: onHost, account: onAccount, settings: settings)
        await onModel.refreshICloudAccountStatus()
        #expect(onAccount.queries == 1)
        #expect(onModel.iCloudAccountStatus == .noAccount)
        #expect(onModel.iCloudAccountStatus?.pausedText != nil)

        onAccount.status = .available
        await onModel.refreshICloudAccountStatus()
        #expect(onModel.iCloudAccountStatus?.pausedText == nil)
    }

    /// 確かめている途中で画面を離れたら、戻った後で説明やアラートを出さない。
    @Test func settingsCancelAccountCheckOnDisappear() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let host = store.makeHost(defaults: settings.defaults)
        host.start()
        let (gate, openGate) = AsyncStream<Void>.makeStream()
        let model = try Self.makeSettingsModel(
            host: host,
            accountStatus: {
                for await _ in gate { break }
                return .available
            },
            settings: settings
        )

        let checking = try #require(model.requestICloudSync(true))
        model.cancelICloudAccountCheck()
        #expect(!model.isCheckingICloudAccount)
        openGate.yield()
        openGate.finish()
        await checking.value

        #expect(model.iCloudSyncConfirmation == nil)
        #expect(model.iCloudAccountAlert == nil)
        #expect(store.openedWith == [.none])
    }

    // MARK: - ホームからの配線

    /// 開けた保存先で作るホーム（`AppRootView` と同じく、保存先を開いたものを渡す）。
    static func makeHome(host: StoreHost, settings: Settings) throws -> HomeModel {
        let container = try #require(container(of: host))
        return HomeModel(
            store: EntryStore(context: container.mainContext),
            pendingWrites: host.pendingWrites,
            storeHost: host,
            defaults: settings.defaults,
            makeRemarkWriter: { nil },
            now: { TestSupport.now },
            announce: { _ in }
        )
    }

    /// ホームから開く設定に、保存先を開いたもの（StoreHost）を渡す。渡し忘れると「iCloud で同期」の節が黙って消える。
    @Test(arguments: [ModelContainerFactory.CloudKitDatabase.none, .private])
    func homeSettingsShowICloudSync(database: ModelContainerFactory.CloudKitDatabase) throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let host = store.makeHost(cloudKitDatabase: database, defaults: settings.defaults)
        host.start()
        let home = try Self.makeHome(host: host, settings: settings)

        home.presentSettings()

        let model = try #require(home.settings)
        #expect(model.showsICloudSync)
        #expect(model.isICloudSyncEnabled == host.cloudKitDatabase.isSyncEnabled)
        #expect(model.isICloudSyncEnabled == (database == .private))
    }

    /// 切り替えて開き直したら、新しい保存先で作ったホームは設定の画面を開いた状態から始まり、切り替えた後の状態を見せる。
    /// 切り替えていないとき（起動したとき）と、2 つ目からのホームでは開かない。
    @Test func homeReopensSettingsAfterSwitch() async throws {
        let settings = try Settings()
        defer { settings.cleanUp() }
        let store = FakeStore()
        let host = store.makeHost(defaults: settings.defaults)
        host.start()
        let first = try Self.makeHome(host: host, settings: settings)
        first.restoreSettingsAfterStoreSwitch()
        #expect(first.settings == nil)

        host.setICloudSyncEnabled(true)
        await host.finishReopening()
        let reopened = try Self.makeHome(host: host, settings: settings)
        reopened.restoreSettingsAfterStoreSwitch()

        let model = try #require(reopened.settings)
        #expect(model.showsICloudSync)
        #expect(model.isICloudSyncEnabled)

        let again = try Self.makeHome(host: host, settings: settings)
        again.restoreSettingsAfterStoreSwitch()
        #expect(again.settings == nil)
    }

    // MARK: - ほかの端末の変更

    /// 保存先の「外からの変更」（iCloud から取り込んだ変更）の知らせは、取り込みを受け持つ裏のスレッドから届いても、
    /// メインスレッドで渡す（受けた画面のモデルが読み直す。`StoreChanges`）。
    @Test(.timeLimit(.minutes(1))) func remoteChangesArriveOnMainThread() async {
        let (received, continuation) = AsyncStream<Bool>.makeStream()
        let subscription = StoreChanges.remote.sink { continuation.yield(Thread.isMainThread) }
        defer { subscription.cancel() }

        DispatchQueue.global().async {
            NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        }

        var iterator = received.makeAsyncIterator()
        #expect(await iterator.next() == true)
    }

    // MARK: - 戻した理由

    /// CloudKit の制約に合わないモデルは、iCloud と同期する保存先として開くときに失敗する（戻す仕組みが働く前提。
    /// サインインしていないだけでは開けなくならない）。
    @Test func cloudKitRejectionHappensAtOpen() throws {
        let rejection = try Self.cloudKitRejection()
        #expect(!(rejection is TestError))
    }

    /// 理由は、包まれた元のエラーのいちばん奥（原因に近い）のドメインと番号だけを残す（説明文は残さない）。
    @Test func failureKeepsInnermostDomainAndCode() {
        let inner = NSError(domain: NSPOSIXErrorDomain, code: 28, userInfo: [NSLocalizedDescriptionKey: "/private/var/mobile/…"])
        let middle = NSError(domain: NSCocoaErrorDomain, code: 134_060, userInfo: [NSUnderlyingErrorKey: inner])
        let outer = NSError(domain: "SwiftData.SwiftDataError", code: 1, userInfo: [NSUnderlyingErrorKey: middle])

        #expect(ICloudSyncFailure(error: outer) == ICloudSyncFailure(domain: NSPOSIXErrorDomain, code: 28))
        #expect(
            ICloudSyncFailure(error: NSError(domain: "SwiftData.SwiftDataError", code: 1))
                == ICloudSyncFailure(domain: "SwiftData.SwiftDataError", code: 1)
        )
    }

    /// 理由の番号は桁区切りを入れずに出す（問い合わせや検索に写したときに、本当の番号と食い違わないように）。
    @Test(arguments: [(134_060, "134060"), (-1009, "-1009"), (28, "28")])
    func reasonTextShowsCodeAsIs(code: Int, expected: String) {
        let text = ICloudSyncFailure(domain: NSCocoaErrorDomain, code: code).reasonText
        #expect(text.hasSuffix("\(NSCocoaErrorDomain) \(expected)"))
    }

    /// CloudKit のアカウントの状態の写し替え。オンにしてよいのは使えるときだけ。
    @Test func mapsAccountStatus() {
        #expect(ICloudAccountStatus(CKAccountStatus.available) == .available)
        #expect(ICloudAccountStatus(CKAccountStatus.noAccount) == .noAccount)
        #expect(ICloudAccountStatus(CKAccountStatus.restricted) == .restricted)
        #expect(ICloudAccountStatus(CKAccountStatus.temporarilyUnavailable) == .temporarilyUnavailable)
        #expect(ICloudAccountStatus(CKAccountStatus.couldNotDetermine) == .couldNotDetermine)

        let all: [ICloudAccountStatus] = [
            .available, .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine, .failed(domain: "x", code: 1),
            .missingEntitlement,
        ]
        #expect(all.filter(\.isAvailable) == [.available])
        #expect(all.filter { $0.guidanceText == nil } == [.available])
        #expect(all.filter { $0.pausedText == nil } == [.available])
        #expect(Set(all.map(\.diagnosticName)).count == all.count)
    }

    /// 署名の無いビルド（iCloud の entitlement が無い）では、CloudKit に問い合わせずに `missingEntitlement` を返す。
    /// `CKContainer` を作るとプロセスが止まるため（診断画面を開いたときに落ちていた）。このテストのプロセスも署名が無いので、
    /// 問い合わせていれば止まる。
    @Test func accountStatusWithoutEntitlementDoesNotAskCloudKit() async {
        #expect(await ICloudAccountStatus.current(canUseCloudKit: false) == .missingEntitlement)
        #expect(ICloudAccountStatus.missingEntitlement.isAvailable == false)
    }

    /// サインインしていても、iCloud Drive やこのアプリの iCloud がオフだと「サインインしていない」になることがあるので、
    /// その案内にはどちらも確かめるよう添える（日本語でも英語でも「iCloud Drive」はそのまま出る）。
    @Test func noAccountGuidanceMentionsICloudDrive() {
        #expect(ICloudAccountStatus.noAccount.guidanceText?.contains("iCloud Drive") == true)
        #expect(ICloudAccountStatus.noAccount.pausedText?.contains("iCloud Drive") == true)
    }
}
