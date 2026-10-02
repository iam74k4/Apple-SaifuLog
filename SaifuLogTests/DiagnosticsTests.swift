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

    /// 設定の「iCloud で同期」を読む置き場所（テストでは何も書かないので、既定値のオフが読める）。
    @MainActor static let isolatedSettings = try! TestSupport.makeLaunchSettings()

    /// 生成の試しで、本物のモデルの代わりを渡し忘れたとき（テストでは本物のモデルを呼ばない）。
    nonisolated static let unexpectedGeneration: @Sendable () async throws -> Void = {
        Issue.record("生成の試しに、本物のモデルの代わりを渡していません")
    }

    /// AI の記録と生成の試しは、テストごとに新しい記録と代わりを渡す（アプリの `AIFallbackLog.shared` には、ほかのテストの失敗も入るため）。
    static func makeModel(
        context: ModelContext, storeURL: URL, protectedDataAvailable: Bool = true, sink: Sink = Sink(),
        settings: LaunchSettingsStore = isolatedSettings, aiFallbackLog: AIFallbackLog = AIFallbackLog(),
        generate: @escaping @Sendable () async throws -> Void = unexpectedGeneration,
        generationTimeout: Duration = .seconds(20)
    ) -> DiagnosticsModel {
        DiagnosticsModel(
            context: context,
            storeURL: storeURL,
            isProtectedDataAvailable: { protectedDataAvailable },
            speech: { speech },
            iCloudAccount: { .noAccount },
            settings: settings,
            copy: { sink.copy($0) },
            announce: { sink.announce($0) },
            aiFallbackLog: aiFallbackLog,
            generate: generate,
            generationTimeout: generationTimeout
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
            settings: Self.isolatedSettings,
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
        // 設定はオンなのに、開いた保存先は端末の中だけ（開けずに戻したときの食い違いを見分けられる）。
        let settings = try TestSupport.makeLaunchSettings(.init(iCloudSyncEnabled: true))
        let model = DiagnosticsModel(
            context: context,
            storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            isProtectedDataAvailable: { true },
            speech: { Self.speech },
            iCloudAccount: { .failed(domain: "CKErrorDomain", code: 4) },
            settings: settings,
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
            settings: Self.isolatedSettings,
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

    // MARK: - 端末内 AI の失敗と生成の試し

    /// モデルの資産が無いシミュレータ（iOS 26.2）で、AI が使えると出るのに生成が返したエラーの形（NSError に包まれ、元のエラーは
    /// NSMultipleUnderlyingErrorsKey に入っていた）。
    nonisolated static func simulatorGenerationError() -> NSError {
        NSError(domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1, userInfo: [
            NSMultipleUnderlyingErrorsKey: [NSError(domain: "ModelManagerServices.ModelManagerError", code: 1026)],
        ])
    }

    static let simulatorGenerationErrorText =
        "NSError error(FoundationModels.LanguageModelSession.GenerationError -1) underlying(ModelManagerServices.ModelManagerError 1026)"

    @Test("起動してから AI の結果を使わなかった回数と時間切れの回数（機能ごと）、最後のエラー・その機能・日時を出す")
    func aiFallbackRows() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = AIFallbackLog(now: { TestSupport.now })
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory), aiFallbackLog: log
        )

        await model.load()
        let before = try #require(model.report)
        #expect(before.value(for: "fm.fallbacks") == "0 (entry 0, question 0, recap 0, receipt 0)")
        #expect(before.value(for: "fm.timeouts") == "0 (entry 0, question 0, recap 0, receipt 0)")
        #expect(before.value(for: "fm.lastError") == "none")
        // 失敗が無ければ、最後のエラーの機能と日時の行は出さない。
        #expect(before.value(for: "fm.lastError.feature") == nil)
        #expect(before.value(for: "fm.lastError.at") == nil)

        log.record(.failed(Self.simulatorGenerationError()), in: .entry)
        log.record(.noResult, in: .question)
        log.record(.failed(TestError()), in: .entry)
        log.record(.failed(Self.simulatorGenerationError()), in: .receipt)
        log.record(.timedOut(.seconds(8)), in: .recap)
        await model.load()
        let after = try #require(model.report)

        #expect(after.value(for: "fm.fallbacks") == "5 (entry 2, question 1, recap 1, receipt 1)")
        // 時間切れは、AI の結果を使わなかった回数にも数え、最後のエラーは変えない。
        #expect(after.value(for: "fm.timeouts") == "1 (entry 0, question 0, recap 1, receipt 0)")
        #expect(after.value(for: "fm.lastError") == Self.simulatorGenerationErrorText)
        #expect(after.value(for: "fm.lastError.feature") == "receipt")
        // 2026-09-28 12:00（日本時間）。タイムゾーンによらない形で出す。
        #expect(after.value(for: "fm.lastError.at") == "2026-09-28T03:00:00Z")
    }

    @Test("生成を試すと、かかった時間を ok として出し、コピーする文にも入れて、終わったことを読み上げる")
    func generationProbeSucceeds() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = Sink()
        let calls = CallCounter()
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory), sink: sink,
            generate: { calls.increment() }
        )

        await model.load()
        #expect(model.report?.value(for: "fm.generation") == "not run")

        await model.runGenerationProbe()

        let value = try #require(model.report?.value(for: "fm.generation"))
        #expect(value.hasPrefix("ok ("), "\(value)")
        #expect(value.hasSuffix(" ms)"), "\(value)")
        #expect(calls.count == 1)
        #expect(sink.announcements.count == 1)
        model.copyReport()
        #expect(try #require(sink.copied.last).contains("fm.generation: \(value)"))
    }

    @Test("生成が失敗したら、エラーの型・ドメイン・番号（と元のエラー）を出す")
    func generationProbeShowsError() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            generate: { throw Self.simulatorGenerationError() }
        )

        await model.load()
        await model.runGenerationProbe()

        #expect(model.report?.value(for: "fm.generation") == Self.simulatorGenerationErrorText)
        // 読み直しても、試した結果は残す（コピーする文に入れるため）。
        await model.load()
        #expect(model.report?.value(for: "fm.generation") == Self.simulatorGenerationErrorText)
    }

    /// モデルが取り消しに応じずに止まっていても、上限の時間で時間切れにして、試している状態のままにしない。
    @Test("生成が上限の時間までに返らなければ、終わるのを待たずに時間切れと出す")
    func generationProbeTimesOut() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // 取り消されても待ち続ける門（取り消しに応じないモデルの代わり）。
        let stuck = Gate()
        defer { stuck.open() }
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            generate: { await stuck.wait() }, generationTimeout: .milliseconds(50)
        )

        await model.load()
        await model.runGenerationProbe()

        #expect(model.generationProbe == .timedOut(.milliseconds(50)))
        #expect(model.report?.value(for: "fm.generation") == "timeout (50 ms)")
    }

    @Test("試している間は running と出し、押し直しても重ねて試さない")
    func generationProbeDoesNotOverlap() async throws {
        let context = try TestSupport.makeContext()
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let started = Gate(), release = Gate()
        let calls = CallCounter()
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            generate: {
                calls.increment()
                started.open()
                await release.wait()
            }
        )
        await model.load()

        let first = Task { await model.runGenerationProbe() }
        await started.wait()
        #expect(model.generationProbe == .running)
        #expect(model.report?.value(for: "fm.generation") == "running")

        await model.runGenerationProbe()
        #expect(calls.count == 1)

        release.open()
        await first.value
        #expect(model.report?.value(for: "fm.generation")?.hasPrefix("ok (") == true)
        #expect(calls.count == 1)
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
        // 端末内 AI のエラーの説明には、モデルに渡した文（入力した文や金額）が入ることがある。説明は写さない。
        let leakyError = NSError(domain: "com.apple.modelmanager", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "内緒の焼肉 98765", NSDebugDescriptionErrorKey: "秘密の喫茶 87654",
        ])
        let log = AIFallbackLog(now: { TestSupport.now })
        log.record(.failed(leakyError), in: .entry)
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            aiFallbackLog: log, generate: { throw leakyError }
        )

        await model.load()
        await model.runGenerationProbe()
        let report = try #require(model.report)
        #expect(report.value(for: "fm.lastError") == "NSError error(com.apple.modelmanager 7)")
        #expect(report.value(for: "fm.generation") == "NSError error(com.apple.modelmanager 7)")

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
        // 失敗があるときだけ出る行（最後のエラーの機能と日時）も含めて、キーが重ならないことを見る。
        let log = AIFallbackLog()
        log.record(.failed(TestError()), in: .question)
        let model = Self.makeModel(
            context: context, storeURL: folder.appending(path: "default.store", directoryHint: .notDirectory),
            protectedDataAvailable: false, aiFallbackLog: log
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
        #expect(report.value(for: "fm.lastError.feature") == "question")
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
