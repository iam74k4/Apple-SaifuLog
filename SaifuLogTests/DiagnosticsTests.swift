// 診断画面は社内テスト用のビルドと DEBUG のビルドにだけ入る（アプリのテストは DEBUG で動く）。
#if DEBUG || INTERNAL_DIAGNOSTICS
import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 診断画面の値の集め方と、まとめてコピーする文。
@MainActor
struct DiagnosticsTests {
    /// 音声の書き起こしの問い合わせの代わり（テストでは OS に問い合わせない。資産の問い合わせは環境で時間がかかりうるため）。
    nonisolated static let speech = DiagnosticsReport.SpeechStatus(
        isAvailable: true, japaneseLocale: "ja_JP", isJapaneseInstalled: false, route: "speechTranscriber", model: "needsDownload"
    )

    /// クリップボードと読み上げの代わり。
    @MainActor
    final class Sink {
        private(set) var copied: [String] = []
        private(set) var announcements: [String] = []

        func copy(_ text: String) { copied.append(text) }
        func announce(_ text: String) { announcements.append(text) }
    }

    /// 音声の書き起こしの問い合わせを、テストが答えを渡すまで返さない代わり（遅い・返らない問い合わせを再現する）。
    actor SpeechGate {
        private var waiting: [CheckedContinuation<DiagnosticsReport.SpeechStatus, Never>] = []

        /// 答えを待っている問い合わせの数（答えを渡した後も減らない。何番目の問い合わせかを数えるため）。
        var count: Int { waiting.count }

        func wait() async -> DiagnosticsReport.SpeechStatus {
            await withCheckedContinuation { waiting.append($0) }
        }

        /// `index` 番目（0 から）の問い合わせに答える。
        func answer(_ index: Int, with status: DiagnosticsReport.SpeechStatus) {
            waiting[index].resume(returning: status)
        }
    }

    /// `condition` が成り立つまで、ほかの Task に順番を譲りながら待つ。回数を使い切っても成り立たなければ false
    /// （返らないまま止まらないように、上限を付ける）。
    static func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }

    /// アプリの本物の保存先には触れないよう、一時フォルダを使う（テストの終わりに消す）。
    static func makeFolder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// 設定の「iCloud で同期」を読む領域（テストでは何も書かないので、既定値のオフが読める）。
    static let isolatedDefaults = UserDefaults(suiteName: "DiagnosticsTests.\(UUID().uuidString)")!

    static func makeModel(
        context: ModelContext, storeURL: URL, protectedDataAvailable: Bool = true, sink: Sink = Sink(),
        defaults: UserDefaults = isolatedDefaults
    ) -> DiagnosticsModel {
        DiagnosticsModel(
            context: context,
            storeURL: storeURL,
            isProtectedDataAvailable: { protectedDataAvailable },
            speech: { speech },
            iCloudAccount: { .noAccount },
            defaults: defaults,
            copy: { sink.copy($0) },
            announce: { sink.announce($0) }
        )
    }

    // MARK: - 保護クラス

    @Test("ファイルが無ければ missing（まだ作られていない保存先や、片づいた -wal / -shm）")
    func protectionOfMissingFile() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        #expect(DiagnosticsProbe.protection(at: url) == .missing)
        // フォルダごと無いときも同じ。
        let nowhere = folder.appending(path: "nowhere/default.store", directoryHint: .notDirectory)
        #expect(DiagnosticsProbe.protection(at: nowhere) == .missing)
    }

    @Test("ファイルがあれば、missing にも読めない（error）にもならない")
    func protectionOfExistingFile() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)
        try Data().write(to: url)

        let status = DiagnosticsProbe.protection(at: url)

        // 保護クラスの値そのものは、シミュレータではデータ保護が効かないので確かめられない（実機で見る）。
        #expect(status != .missing)
        if case .failed = status {
            Issue.record("保護クラスを読めませんでした: \(status.description)")
        }
    }

    /// 診断画面の保護クラスを、エンタイトルメント（project.yml の default-data-protection）の値と見比べられること。
    @Test("保護クラスはエンタイトルメントと同じ名前で出す")
    func protectionNamesMatchEntitlementValues() {
        #expect(DiagnosticsProbe.protectionName(.complete) == "NSFileProtectionComplete")
        #expect(DiagnosticsProbe.protectionName(.completeUnlessOpen) == "NSFileProtectionCompleteUnlessOpen")
        #expect(
            DiagnosticsProbe.protectionName(.completeUntilFirstUserAuthentication)
                == "NSFileProtectionCompleteUntilFirstUserAuthentication"
        )
        #expect(DiagnosticsProbe.protectionName(.none) == "NSFileProtectionNone")
    }

    @Test("見るファイルは、SwiftData の保存先が実際に作るもの（本体・-wal・-shm）")
    func storeFilesMatchWhatSwiftDataCreates() throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "default.store", directoryHint: .notDirectory)

        let before = DiagnosticsProbe.storeFiles(storeURL: url)
        #expect(before.map(\.name) == ["default.store", "default.store-wal", "default.store-shm"])
        #expect(before.map(\.protection) == [.missing, .missing, .missing])

        let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        container.mainContext.insert(TestSupport.entry())
        try container.mainContext.save()

        // 開いている間は 3 つともある（名前の付け方が SwiftData と食い違っていれば missing になる）。
        let after = DiagnosticsProbe.storeFiles(storeURL: url)
        #expect(after.allSatisfy { $0.protection != .missing }, "\(after)")
        withExtendedLifetime(container) {}
    }

    // MARK: - 件数

    @Test("記録と予算の行を数える")
    func countsRecordsAndBudgetRows() throws {
        let context = try TestSupport.makeContext()
        #expect(DiagnosticsProbe.counts(context: context) == .init(entries: 0, budgetRows: 0))

        context.insert(TestSupport.entry(amount: 850))
        context.insert(TestSupport.entry(amount: 1_200))
        try BudgetStore(context: context).setAmount(150_000, for: .total)
        try context.save()

        #expect(DiagnosticsProbe.counts(context: context) == .init(entries: 2, budgetRows: 1))
    }

    // MARK: - 読み込み

    /// 音声の資産の問い合わせが遅い・返らない端末でも、実機で見たい値（保存先の保護クラス・端末内 AI）を隠さない。
    @Test("音声の書き起こしの問い合わせを待たずにほかの値を出し、返ったら音声の行を埋める")
    func loadShowsReportBeforeSpeechAnswers() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gate = SpeechGate()
        let model = DiagnosticsModel(
            context: context,
            storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            isProtectedDataAvailable: { true },
            speech: { await gate.wait() },
            iCloudAccount: { .available },
            defaults: Self.isolatedDefaults,
            copy: { _ in },
            announce: { _ in }
        )

        let loading = Task { await model.load() }
        try #require(await Self.eventually { await gate.count == 1 })

        let pending = try #require(model.report)
        #expect(pending.value(for: "speech.available") == DiagnosticsReport.checking)
        #expect(pending.value(for: "speech.japaneseLocale") == DiagnosticsReport.checking)
        #expect(pending.value(for: "speech.japaneseInstalled") == DiagnosticsReport.checking)
        #expect(pending.value(for: "speech.route") == DiagnosticsReport.checking)
        #expect(pending.value(for: "speech.model") == DiagnosticsReport.checking)
        #expect(pending.value(for: "store.default.store") == "missing")
        #expect(pending.value(for: "store.protectedDataAvailable") == "true")
        #expect(pending.value(for: "fm.availability") != nil)
        #expect(pending.value(for: "records.entries") == "0")
        // iCloud のアカウントの問い合わせも待たずに出す（返るまでは checking）。いまの保存先の同期は待たずに読める。
        #expect(pending.value(for: "icloud.account") == DiagnosticsReport.checking)
        #expect(pending.value(for: "icloud.database") == "none")

        await gate.answer(0, with: Self.speech)
        await loading.value

        let answered = try #require(model.report)
        #expect(answered.value(for: "speech.available") == "true")
        #expect(answered.value(for: "speech.japaneseLocale") == "ja_JP")
        #expect(answered.value(for: "speech.japaneseInstalled") == "false")
        #expect(answered.value(for: "speech.route") == "speechTranscriber")
        #expect(answered.value(for: "speech.model") == "needsDownload")
        #expect(answered.value(for: "icloud.account") == "available")
    }

    @Test("iCloud の行に、アカウントの状態・いまの保存先の同期・設定の値を出す")
    func iCloudRows() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suiteName = "DiagnosticsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // 設定はオンなのに、開いた保存先は端末の中だけ（開けずに戻したときの食い違いを見分けられる）。
        defaults.set(true, for: AppSettings.iCloudSyncEnabled)
        let model = DiagnosticsModel(
            context: context,
            storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            isProtectedDataAvailable: { true },
            speech: { Self.speech },
            iCloudAccount: { .failed(domain: "CKErrorDomain", code: 4) },
            defaults: defaults,
            copy: { _ in },
            announce: { _ in }
        )

        await model.load()
        let report = try #require(model.report)

        #expect(report.value(for: "icloud.account") == "error(CKErrorDomain 4)")
        #expect(report.value(for: "icloud.database") == "none")
        #expect(report.value(for: "icloud.syncSetting") == "true")
    }

    @Test("iCloud と同期する保存先の設定なら、コンテナの ID を添えて private と出す")
    func iCloudDatabaseNameForPrivateConfiguration() throws {
        // CloudKit にはつながないよう、保存先は開かずに設定だけを作って読み方を確かめる。
        let configuration = ModelContainerFactory.configuration(
            url: URL.temporaryDirectory.appending(path: "unused.store"), cloudKitDatabase: .private
        )

        #expect(DiagnosticsProbe.cloudKitDatabaseName(configurations: [configuration]) == "private(\(ModelContainerFactory.iCloudContainerIdentifier))")
        #expect(DiagnosticsProbe.cloudKitDatabaseName(configurations: []) == "unknown")
    }

    @Test("読み直しの後に前の問い合わせの答えが返っても、新しい答えを上書きしない")
    func staleSpeechAnswerDoesNotOverwriteNewerLoad() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let gate = SpeechGate()
        let model = DiagnosticsModel(
            context: context,
            storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            isProtectedDataAvailable: { true },
            speech: { await gate.wait() },
            iCloudAccount: { .available },
            defaults: Self.isolatedDefaults,
            copy: { _ in },
            announce: { _ in }
        )
        let stale = DiagnosticsReport.SpeechStatus(
            isAvailable: false, japaneseLocale: nil, isJapaneseInstalled: false, route: "none", model: "none"
        )

        let first = Task { await model.load() }
        try #require(await Self.eventually { await gate.count == 1 })
        let second = Task { await model.load() }
        try #require(await Self.eventually { await gate.count == 2 })

        // 後から始めた読み直しが先に返り、そのあとで前の問い合わせが返る。
        await gate.answer(1, with: Self.speech)
        await second.value
        await gate.answer(0, with: stale)
        await first.value

        let report = try #require(model.report)
        #expect(report.value(for: "speech.available") == "true")
        #expect(report.value(for: "speech.japaneseLocale") == "ja_JP")
        #expect(report.value(for: "speech.route") == "speechTranscriber")
    }

    // MARK: - コピーする文

    @Test("コピーする文に、記録の中身（金額・メモ・入力した文・予算の額）と保存先のパスが入らない")
    func textExcludesPersonalData() async throws {
        let context = try TestSupport.makeContext()
        context.insert(TestSupport.entry(amount: 98_765, memo: "内緒の焼肉"))
        context.insert(TestSupport.entry(amount: 87_654, category: .cafe, memo: "秘密の喫茶"))
        try BudgetStore(context: context).setAmount(123_456, for: .total)
        try context.save()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = Self.makeModel(context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory))

        await model.load()
        let report = try #require(model.report)

        let secrets = [
            "98765", "98,765", "87654", "87,654", "123456", "123,456", "¥", "円",
            "内緒", "焼肉", "秘密", "喫茶", folder.path(percentEncoded: false), URL.applicationSupportDirectory.path(percentEncoded: false),
        ]
        for secret in secrets {
            #expect(!report.text.contains(secret), "コピーする文に「\(secret)」が入っています")
        }
        // 件数は入る（中身ではない）。
        #expect(report.value(for: "records.entries") == "2")
        #expect(report.value(for: "records.budgetRows") == "1")
    }

    @Test("コピーする文は印の行から始まり、1 行に 1 項目で、キーが重ならない")
    func textFormat() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            protectedDataAvailable: false
        )

        await model.load()
        let report = try #require(model.report)
        let lines = report.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        #expect(lines.first == DiagnosticsReport.buildMarker)
        let keys = lines.dropFirst().map { $0.components(separatedBy: ": ").first ?? "" }
        #expect(Set(keys).count == keys.count)
        #expect(keys == report.sections.flatMap(\.rows).map(\.key))
        #expect(report.value(for: "store.default.store") == "missing")
        #expect(report.value(for: "store.default.store-wal") == "missing")
        #expect(report.value(for: "store.default.store-shm") == "missing")
        #expect(report.value(for: "store.protectedDataAvailable") == "false")
        #expect(report.value(for: "speech.japaneseLocale") == "ja_JP")
        #expect(report.value(for: "speech.japaneseInstalled") == "false")
        #expect(report.value(for: "icloud.account") == "noAccount")
        // テストの保存先はメモリの上で、iCloud と同期しない。
        #expect(report.value(for: "icloud.database") == "none")
        #expect(report.value(for: "icloud.syncSetting") == "false")
        #expect(report.value(for: "app.buildKind") == DiagnosticsProbe.buildKind)
    }

    @Test("まとめてコピーは、読み終えた後だけ文をクリップボードへ写し、読み上げる")
    func copyReport() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = Sink()
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory), sink: sink
        )

        model.copyReport()
        #expect(sink.copied.isEmpty)
        #expect(model.copyCount == 0)

        await model.load()
        model.copyReport()

        #expect(sink.copied == [try #require(model.report).text])
        #expect(model.copyCount == 1)
        #expect(sink.announcements.count == 1)
    }

    /// 15 バイトまでの文字列は、Swift がバイナリに文字列として置かないことがある。そうなると release.mk が
    /// アーカイブの中から印を見つけられず、社内テスト用のアーカイブが止まる。
    @Test("診断画面の印は 16 バイト以上")
    func markerIsLongEnoughToBeFoundInBinary() {
        #expect(DiagnosticsReport.buildMarker.utf8.count >= 16)
    }
}
#endif
