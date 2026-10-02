import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 保存先を開けないとき（ロック中・それ以外の失敗）に落ちず、待つか再試行の画面を出すこと。
@MainActor
struct StoreHostTests {
    /// 保存先を開く処理と、ロックの状態の代わり。
    @MainActor
    final class FakeStore {
        /// 保護されたデータが読めるか（false ならロック中）。
        var protectedDataAvailable = true
        /// 次に開くときに投げるエラー（先頭から順に使う）。
        var failures: [any Error] = []
        /// この iCloud の扱いで開こうとしたら、いつも投げるエラー（iCloud と同期する保存先だけ開けない、などに使う）。
        var failuresByDatabase: [ModelContainerFactory.CloudKitDatabase: any Error] = [:]
        /// 次に開くときに、開いている途中でロックされたことにする。
        var locksDuringNextOpen = false
        /// 次にこの iCloud の扱いで開くときに、開いている途中でロックされたことにする（一度だけ）。
        var locksDuringNextOpenOf: ModelContainerFactory.CloudKitDatabase?
        private(set) var openedWith: [ModelContainerFactory.CloudKitDatabase] = []
        /// VoiceOver に読み上げさせた文。
        private(set) var announcements: [String] = []

        func open(_ cloudKitDatabase: ModelContainerFactory.CloudKitDatabase) throws -> ModelContainer {
            openedWith.append(cloudKitDatabase)
            if locksDuringNextOpen || locksDuringNextOpenOf == cloudKitDatabase {
                locksDuringNextOpen = false
                locksDuringNextOpenOf = nil
                protectedDataAvailable = false
                throw TestError()
            }
            if let failure = failuresByDatabase[cloudKitDatabase] { throw failure }
            if !failures.isEmpty { throw failures.removeFirst() }
            // iCloud と同期する保存先も、テストではメモリの上に開く（署名なしのテストのプロセスは iCloud の
            // entitlement を持たず、本物の CloudKit にはつながらない）。
            return try ModelContainerFactory.makeInMemoryContainer()
        }

        /// - Parameters:
        ///   - cloudKitDatabase: 最初に開く保存先の iCloud の扱い。
        ///   - settings: 設定の置き場所（iCloud 同期を読み、切り替えを書く）。渡さなければ、テストごとの新しいファイル。
        func makeHost(
            cloudKitDatabase: ModelContainerFactory.CloudKitDatabase? = ModelContainerFactory.CloudKitDatabase.none,
            settings: LaunchSettingsStore? = nil,
            contentRemovalTimeout: Duration = .seconds(3)
        ) -> StoreHost {
            StoreHost(
                cloudKitDatabase: cloudKitDatabase,
                settings: settings ?? (try! TestSupport.makeLaunchSettings()),
                openContainer: { try self.open($0) },
                isProtectedDataAvailable: { self.protectedDataAvailable },
                announce: { self.announcements.append($0) },
                contentRemovalTimeout: contentRemovalTimeout
            )
        }
    }

    static func container(of host: StoreHost) -> ModelContainer? {
        if case .ready(let container) = host.state { container } else { nil }
    }

    static func isLoading(_ host: StoreHost) -> Bool {
        if case .loading = host.state { true } else { false }
    }

    static func isReopening(_ host: StoreHost) -> Bool {
        if case .reopening = host.state { true } else { false }
    }

    @Test func startOpensContainerOnce() {
        let store = FakeStore()
        let host = store.makeHost()
        #expect(Self.isLoading(host))

        host.start()
        host.start()

        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith == [.none])
    }

    /// ロック中は開こうとせずに待ち、ロックが解けたら開く（以前は開けずに fatalError で落ちていた）。
    @Test func waitsWhileLockedAndOpensAfterUnlock() {
        let store = FakeStore()
        store.protectedDataAvailable = false
        let host = store.makeHost()

        host.start()
        #expect(Self.isLoading(host))
        #expect(host.isWaitingForProtectedData)
        #expect(store.openedWith.isEmpty)

        // まだロック中なら、通知が来ても開かない。
        host.protectedDataMayBeAvailable()
        #expect(Self.isLoading(host))
        #expect(store.openedWith.isEmpty)

        store.protectedDataAvailable = true
        host.protectedDataMayBeAvailable()
        #expect(Self.container(of: host) != nil)
        #expect(!host.isWaitingForProtectedData)
        #expect(store.openedWith == [.none])
    }

    /// 開いている途中でロックされて失敗したときは、再試行の画面を出さずにロックの解除を待つ。
    @Test func waitsWhenLockedDuringOpen() {
        let store = FakeStore()
        store.locksDuringNextOpen = true
        let host = store.makeHost()

        host.start()
        #expect(Self.isLoading(host))
        #expect(host.isWaitingForProtectedData)

        store.protectedDataAvailable = true
        host.protectedDataMayBeAvailable()
        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith.count == 2)
    }

    /// ロック中でないのに開けなければ、再試行の画面を出す。再試行で開ければホームへ進む。
    @Test func showsUnavailableAndRetries() {
        let store = FakeStore()
        store.failures = [TestError()]
        let host = store.makeHost()

        host.start()
        guard case .unavailable(let error) = host.state else {
            Issue.record("再試行の画面になっていない: \(host.state)")
            return
        }
        #expect(error is TestError)
        #expect(!host.isWaitingForProtectedData)

        // ロックを待っているわけではないので、前面に戻っただけでは開き直さない（再試行のボタンで開く）。
        host.protectedDataMayBeAvailable()
        #expect(store.openedWith.count == 1)

        host.retry()
        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith.count == 2)
        // 開けたときは「開けなかった」とは知らせない。
        #expect(host.failedRetryCount == 0)
        #expect(store.announcements.isEmpty)
    }

    /// 開けない原因が続いていると、再試行してもすぐに同じ画面に戻る（読み込み中の画面も一瞬も出ない）。
    /// 押したことが伝わるよう、回数を数えて画面に出し、VoiceOver にも読み上げる。開けたら数え直す。
    @Test func retryThatFailsAgainTellsUser() {
        let store = FakeStore()
        store.failures = [TestError(), TestError(), TestError()]
        let host = store.makeHost()

        host.start()
        // 最初に開けなかったときは、再試行の画面そのものが知らせになるので数えない。
        #expect(host.failedRetryCount == 0)
        #expect(store.announcements.isEmpty)

        host.retry()
        guard case .unavailable = host.state else {
            Issue.record("再試行の画面に戻っていない: \(host.state)")
            return
        }
        #expect(host.failedRetryCount == 1)
        #expect(store.announcements.count == 1)
        #expect(store.announcements.first?.isEmpty == false)

        host.retry()
        #expect(host.failedRetryCount == 2)
        #expect(store.announcements.count == 2)

        host.retry()
        #expect(Self.container(of: host) != nil)
        #expect(host.failedRetryCount == 0)
        #expect(store.announcements.count == 2)
        #expect(store.openedWith.count == 4)
    }

    /// 再試行でロック中だと分かったときは、開けなかったとは知らせない（ロックの解除を待つ）。
    @Test func retryWhileLockedDoesNotReportFailure() {
        let store = FakeStore()
        store.failures = [TestError()]
        let host = store.makeHost()
        host.start()

        store.protectedDataAvailable = false
        host.retry()

        #expect(Self.isLoading(host))
        #expect(host.isWaitingForProtectedData)
        #expect(host.failedRetryCount == 0)
        #expect(store.announcements.isEmpty)
    }

    /// 開けているときの再試行は何もしない（同じファイルを 2 つの保存先で開かない）。
    @Test func retryDoesNothingWhenReady() throws {
        let store = FakeStore()
        let host = store.makeHost()
        host.start()
        let container = try #require(Self.container(of: host))

        host.retry()

        #expect(Self.container(of: host) === container)
        #expect(store.openedWith.count == 1)
    }

    /// 開き直すときは、先に画面のツリーを畳む（前の保存先を手放す）。畳み終えてから新しく開く。
    @Test func reopenReleasesContainerBeforeOpeningNewOne() async throws {
        let store = FakeStore()
        let host = store.makeHost()
        host.start()
        let first = try #require(Self.container(of: host))

        host.reopen(cloudKitDatabase: .none)
        #expect(Self.isReopening(host))
        #expect(Self.container(of: host) == nil)
        #expect(store.openedWith.count == 1)

        await host.finishReopening()
        let second = try #require(Self.container(of: host))
        #expect(second !== first)
        #expect(store.openedWith == [.none, .none])
        #expect(host.cloudKitDatabase == .none)
    }

    /// 開き直す途中でロックされていたら、ロックの解除を待ってから開く。
    @Test func reopenWaitsWhileLocked() async {
        let store = FakeStore()
        let host = store.makeHost()
        host.start()
        host.reopen(cloudKitDatabase: .none)
        store.protectedDataAvailable = false

        await host.finishReopening()
        #expect(Self.isReopening(host))
        #expect(host.isWaitingForProtectedData)

        store.protectedDataAvailable = true
        host.protectedDataMayBeAvailable()
        #expect(Self.container(of: host) != nil)
    }

    /// 開く前（読み込み中）には開き直さない。開き直すのは、開けたか開けなかったかが決まってから。
    @Test func reopenIsIgnoredWhileLoading() {
        let store = FakeStore()
        store.protectedDataAvailable = false
        let host = store.makeHost()
        host.start()

        host.reopen(cloudKitDatabase: .none)

        #expect(Self.isLoading(host))
    }

    /// 開けなかったあとでも開き直せる（iCloud をやめて端末の中だけに戻す、などに使う）。
    @Test func reopenFromUnavailable() async {
        let store = FakeStore()
        store.failures = [TestError()]
        let host = store.makeHost()
        host.start()

        host.reopen(cloudKitDatabase: .none)
        await host.finishReopening()

        #expect(Self.container(of: host) != nil)
    }

    /// 送信の解析を待っている間に開き直しても、記録し終えるまで新しい保存先を開かない。
    ///
    /// 解析を待つ Task は、画面のツリーを畳んだ後も前の保存先の ModelContext を持ったまま動き続ける。待たずに
    /// 開くと、新しい保存先を開いた後で前の保存先に書き込み、同じファイルを 2 つの保存先で開くことになる。
    @Test func reopenWaitsForPendingWrites() async throws {
        let store = FakeStore()
        let host = store.makeHost()
        host.start()
        let first = try #require(Self.container(of: host))

        // 解析を止めておき、開き直しの途中で終わらせる。
        let (gate, openGate) = AsyncStream<Void>.makeStream()
        let parser = RuleBasedParser(calendar: TestSupport.calendar, now: { TestSupport.now })
        let model = HomeModel(
            store: EntryStore(context: first.mainContext),
            pendingWrites: host.pendingWrites,
            makeParser: { _, _ in
                StubParser { text in
                    for await _ in gate { break }
                    return try await parser.parse(text)
                }
            },
            makeCategoryRefiner: { nil },
            now: { TestSupport.now },
            announce: { _ in }
        )
        model.draft = "ランチ 850"
        let sending = try #require(model.send(calendar: TestSupport.calendar))
        #expect(host.pendingWrites.count == 1)

        host.reopen(cloudKitDatabase: .none)
        let reopening = Task { await host.finishReopening() }
        for _ in 0..<10 { await Task.yield() }

        // 解析が終わるまでは、新しい保存先を開かない。
        #expect(Self.isReopening(host))
        #expect(store.openedWith.count == 1)

        openGate.yield()
        openGate.finish()
        await sending.value
        await reopening.value

        // 記録は前の保存先に書き込み終えてから、新しい保存先を開いた。
        #expect(try first.mainContext.fetch(FetchDescriptor<Entry>()).map(\.amount) == [850])
        #expect(model.justRecorded.map(\.amount) == [850])
        #expect(host.pendingWrites.count == 0)
        let second = try #require(Self.container(of: host))
        #expect(second !== first)
        #expect(store.openedWith.count == 2)
    }

    /// 書き込み中の処理が無ければ、待たずに開く。
    @Test func reopenWithoutPendingWritesOpensImmediately() async throws {
        let store = FakeStore()
        let host = store.makeHost()
        host.start()

        host.reopen(cloudKitDatabase: .none)
        await host.finishReopening()

        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith.count == 2)
    }

    /// 開き直しの画面が出ても、前の保存先の画面がまだ消えていなければ（アラートを閉じる動きの途中など）、消えるまで
    /// 新しい保存先を開かない（前の画面のモデルが前の保存先を使ったまま、同じファイルを開かないように）。
    @Test func reopenWaitsForPreviousContentToDisappear() async throws {
        let store = FakeStore()
        let host = store.makeHost()
        host.start()
        host.contentDidAppear()

        host.reopen(cloudKitDatabase: .none)
        let reopening = Task { await host.finishReopening() }
        for _ in 0..<20 { await Task.yield() }
        #expect(Self.isReopening(host))
        #expect(store.openedWith.count == 1)

        host.contentDidDisappear()
        await reopening.value

        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith.count == 2)
    }

    /// 前の画面が消えた知らせが来なくても、上限を過ぎたら開く（読み込み中の画面で止まり続けない）。
    @Test func reopenStopsWaitingForContentAfterTimeout() async throws {
        let store = FakeStore()
        let host = store.makeHost(contentRemovalTimeout: .milliseconds(50))
        host.start()
        host.contentDidAppear()

        host.reopen(cloudKitDatabase: .none)
        await host.finishReopening()

        #expect(Self.container(of: host) != nil)
        #expect(store.openedWith.count == 2)
    }

    /// 前の画面がもう消えていれば待たない。新しい保存先の画面が出たら、次の開き直しでまた待つ。
    @Test func reopenDoesNotWaitWhenContentIsAlreadyGone() async throws {
        let store = FakeStore()
        let host = store.makeHost(contentRemovalTimeout: .seconds(60))
        host.start()
        host.contentDidAppear()
        host.contentDidDisappear()

        host.reopen(cloudKitDatabase: .none)
        await host.finishReopening()
        #expect(store.openedWith.count == 2)

        host.contentDidAppear()
        host.reopen(cloudKitDatabase: .none)
        let reopening = Task { await host.finishReopening() }
        for _ in 0..<20 { await Task.yield() }
        #expect(store.openedWith.count == 2)
        host.contentDidDisappear()
        await reopening.value
        #expect(store.openedWith.count == 3)
    }
}
