import Foundation
import SaifuLogCore
import SwiftData
import Synchronization
import Testing
@testable import SaifuLog

/// 設定（SettingsModel）。メモリの上の保存先、使い捨ての設定の領域と書き出し先、固定の日時（2026-09-28 12:00、日本時間）で確かめる。
@MainActor
struct SettingsModelTests {
    /// SettingsModel と、その保存先・設定の領域・書き出し先の代わり。
    @MainActor
    final class Fixture {
        let context: ModelContext
        let suiteName = "SettingsModelTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        /// 書き出したファイルを置く使い捨てのディレクトリ。
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SettingsModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        var now = TestSupport.now
        /// 書き出しが保存先から読み始める直前に、書き出しを進めているところで呼ぶ（`LedgerExporter.willRead`）。
        var willRead: (@Sendable () -> Void)?

        init() throws {
            context = try TestSupport.makeContext()
            defaults = try #require(UserDefaults(suiteName: suiteName))
        }

        /// テストの後に、設定の領域と書き出し先を片づける。
        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        func makeModel(language: LedgerCSVWriter.Language = .japanese, systemFirstWeekday: Int = 1) -> SettingsModel {
            SettingsModel(
                context: context,
                defaults: defaults,
                exporter: LedgerExporter(container: context.container, directory: directory, willRead: willRead),
                csvLanguage: language,
                systemFirstWeekday: systemFirstWeekday,
                bundleInfo: ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "12"],
                now: { [unowned self] in now },
                announce: { _ in }
            )
        }

        func insert(_ entries: Entry...) throws {
            try EntryStore(context: context).insert(entries)
        }

        /// 書き出し先に残っているファイル（使い捨てのディレクトリの中も含む）。
        func exportedFiles() -> [URL] {
            let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "csv" }
        }
    }

    static func entry(_ amount: Int, _ spentAt: Date, memo: String = "ランチ", isIncome: Bool = false) -> Entry {
        Entry(
            amount: amount, isIncome: isIncome, category: isIncome ? .other : .food, memo: memo,
            spentAt: spentAt, createdAt: spentAt, source: .text, originalText: "\(memo) \(amount)"
        )
    }

    /// 書き出したファイルの行（BOM を除き、CRLF で分けたもの）。
    static func lines(of url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let text = try #require(String(data: data.dropFirst(3), encoding: .utf8))
        var lines = text.components(separatedBy: "\r\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    // MARK: - 週の始まり

    @Test func weekStartDefaultsToSystem() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let saturdayFirst = { () -> Calendar in
            var calendar = TestSupport.calendar
            calendar.firstWeekday = 7
            return calendar
        }()

        let model = fixture.makeModel()

        #expect(model.weekStart == .system)
        #expect(model.calendar(applyingTo: saturdayFirst) == saturdayFirst)
    }

    /// 選んだ週の始まりは設定に書き、次に開いたときも同じにする。画面の根元（`AppRootView` の `@AppStorage`）と同じキーで読む。
    @Test func weekStartIsSavedAndAppliedToReportPeriod() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        var saturdayFirst = TestSupport.calendar
        saturdayFirst.firstWeekday = 7
        let model = fixture.makeModel()

        model.weekStart = .monday

        #expect(fixture.defaults.string(forKey: AppSettings.weekStart.key) == "monday")
        #expect(fixture.defaults.value(for: AppSettings.weekStart) == .monday)
        #expect(fixture.makeModel().weekStart == .monday)
        // 2026-09-28 は月曜日。
        #expect(ReportPeriod.thisWeek.interval(now: TestSupport.now, calendar: model.calendar(applyingTo: saturdayFirst))
            == DateInterval(start: TestSupport.date(2026, 9, 28), end: TestSupport.date(2026, 10, 5)))

        model.weekStart = .sunday

        #expect(ReportPeriod.thisWeek.interval(now: TestSupport.now, calendar: model.calendar(applyingTo: saturdayFirst))?.start
            == TestSupport.date(2026, 9, 27))

        // 端末の設定に戻すと、端末の暦の週の始まり（ここでは土曜）になる。
        model.weekStart = .system

        #expect(fixture.defaults.string(forKey: AppSettings.weekStart.key) == "system")
        #expect(ReportPeriod.thisWeek.interval(now: TestSupport.now, calendar: model.calendar(applyingTo: saturdayFirst))?.start
            == TestSupport.date(2026, 9, 26))
    }

    /// 知らない値（新しい版で足した選択肢を古い版で読んだときなど）は、端末の設定に合わせる。
    @Test func unknownWeekStartFallsBackToSystem() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set("saturday", forKey: AppSettings.weekStart.key)

        #expect(fixture.makeModel().weekStart == .system)
    }

    @Test func weekdayNamesFollowDisplayLanguage() {
        #expect(SettingsModel.weekdayName(1, localization: "ja") == "日曜日")
        #expect(SettingsModel.weekdayName(2, localization: "ja") == "月曜日")
        #expect(SettingsModel.weekdayName(7, localization: "ja") == "土曜日")
        #expect(SettingsModel.weekdayName(2, localization: "en") == "Monday")
        #expect(SettingsModel.weekdayName(0, localization: "en") == "")
    }

    // MARK: - 書き出し

    /// 期間の境目の前後の記録（日本時間）。
    static let periodEntries: [(amount: Int, spentAt: Date)] = [
        (1, TestSupport.date(2025, 12, 31, hour: 23, minute: 59)),
        (2, TestSupport.date(2026, 8, 31, hour: 23, minute: 59)),
        (3, TestSupport.date(2026, 9, 1)),
        (4, TestSupport.date(2026, 9, 28, hour: 9)),
        (5, TestSupport.date(2026, 10, 1)),
    ]

    @Test(arguments: [
        (LedgerExportPeriod.thisMonth, [3, 4]),
        (.lastMonth, [2]),
        (.thisYear, [2, 3, 4, 5]),
        (.all, [1, 2, 3, 4, 5]),
    ])
    func exportWritesSelectedPeriod(period: LedgerExportPeriod, amounts: [Int]) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        for record in Self.periodEntries.reversed() {
            try fixture.insert(Self.entry(record.amount, record.spentAt))
        }
        let model = fixture.makeModel()
        model.exportPeriod = period

        await model.export(calendar: TestSupport.calendar)?.value

        let file = try #require(model.sharedFile)
        #expect(file.recordCount == amounts.count)
        let lines = try Self.lines(of: file.url)
        #expect(lines.first == "日付,時刻,種類,カテゴリ,品目,金額,送った文")
        // 金額の欄（6 列目）。使った日時の古い順に並ぶ。
        #expect(lines.dropFirst().map { String($0.split(separator: ",", omittingEmptySubsequences: false)[5]) }
            == amounts.map(String.init))
        #expect(model.isExporting == false)
        #expect(model.exportAlert == nil)
    }

    @Test func exportUsesFileNameAndRemovesFileAfterSharing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.insert(Self.entry(850, TestSupport.now))
        let model = fixture.makeModel()

        await model.export(calendar: TestSupport.calendar)?.value

        let url = try #require(model.sharedFile?.url)
        #expect(url.lastPathComponent == "saifulog-20260928.csv")
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
            == fixture.directory.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        model.finishSharing()

        #expect(model.sharedFile == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path(percentEncoded: false)))
        #expect(fixture.exportedFiles().isEmpty)
    }

    @Test func exportInEnglishWritesEnglishHeader() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.insert(Self.entry(250_000, TestSupport.now, memo: "給料", isIncome: true))
        let model = fixture.makeModel(language: .english)

        await model.export(calendar: TestSupport.calendar)?.value

        let lines = try Self.lines(of: try #require(model.sharedFile?.url))
        #expect(lines == [
            "Date,Time,Type,Category,Item,Amount,What you sent",
            "2026-09-28,12:00,Income,,給料,250000,給料 250000",
        ])
    }

    /// 書き出しの側から、メインスレッドにいるかと、メインアクターが動けるかを確かめる。
    final class MainActorProbe: Sendable {
        struct Observation: Equatable {
            /// 書き出しがメインスレッドの上で進んでいたか。
            var onMainThread: Bool
            /// 書き出しの途中に、メインアクターに積んだ処理が書き出しの終わりを待たずに動いたか。
            var mainActorRan: Bool
        }

        private let observation = Mutex<Observation?>(nil)

        var result: Observation? {
            observation.withLock { $0 }
        }

        /// 書き出しを止めたまま、メインアクターに積んだ処理が動くのを待つ。書き出しがメインアクターの上で進んでいると、
        /// 積んだ処理は書き出しが終わるまで動けないので、待ちが時間切れになる（止まったままにはならない）。
        func check() {
            let onMainThread = Thread.isMainThread
            let ran = DispatchSemaphore(value: 0)
            Task { @MainActor in ran.signal() }
            let mainActorRan = ran.wait(timeout: .now() + 5) == .success
            observation.withLock { $0 = Observation(onMainThread: onMainThread, mainActorRan: mainActorRan) }
        }
    }

    /// 1 万件でも書き出せ、書き出しの間もメインアクター（画面）は止まらない。書き出しは呼んだ時点では終わらず、その間は進行中になる。
    ///
    /// メインスレッドの外で進むことは、書き出しの側（`LedgerExporter.willRead`）で確かめる。書き出しが
    /// メインアクターの上で進む形に戻ると（`export` を `@MainActor` にしたときや、`@concurrent` を外して
    /// NonisolatedNonsendingByDefault を入れたときなど）、画面が止まるので、ここで落ちる。
    @Test func exportOfManyRecordsKeepsMainActorFree() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let start = TestSupport.date(2026, 9, 1)
        let entries = (0..<10_000).map { Self.entry($0 + 1, start.addingTimeInterval(TimeInterval($0 * 60))) }
        try EntryStore(context: fixture.context).insert(entries)
        let probe = MainActorProbe()
        fixture.willRead = { probe.check() }
        let model = fixture.makeModel()

        let task = model.export(calendar: TestSupport.calendar)
        #expect(model.isExporting)
        #expect(model.sharedFile == nil)
        await task?.value

        #expect(probe.result == MainActorProbe.Observation(onMainThread: false, mainActorRan: true))

        let file = try #require(model.sharedFile)
        #expect(file.recordCount == 10_000)
        let lines = try Self.lines(of: file.url)
        #expect(lines.count == 10_001)
        #expect(lines.last?.hasPrefix("2026-09-07,22:39,支出,食費,ランチ,10000,") == true)
    }

    /// 共有のシートを出せなかったときは、ファイルを消し、ほかの失敗と同じく「書き出せませんでした」と知らせる。
    @Test func sheetThatCouldNotBeShownShowsFailureAlert() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.insert(Self.entry(850, TestSupport.now))
        let model = fixture.makeModel()
        await model.export(calendar: TestSupport.calendar)?.value
        #expect(model.sharedFile != nil)

        model.finishSharing(sheetWasShown: false)

        #expect(model.sharedFile == nil)
        #expect(model.exportAlert == .failed)
        #expect(fixture.exportedFiles().isEmpty)
    }

    /// 共有のシートを閉じた（渡し終えたか、やめた）ときは、知らせることは無い。
    @Test func closingSheetShowsNoAlert() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.insert(Self.entry(850, TestSupport.now))
        let model = fixture.makeModel()
        await model.export(calendar: TestSupport.calendar)?.value

        model.finishSharing(sheetWasShown: true)

        #expect(model.sharedFile == nil)
        #expect(model.exportAlert == nil)
    }

    /// 見出しだけのファイルを渡しても使えないので、渡さずに知らせる。
    @Test func exportOfEmptyPeriodShowsAlertWithoutFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.insert(Self.entry(850, TestSupport.date(2026, 8, 10)))
        let model = fixture.makeModel()
        model.exportPeriod = .thisMonth

        await model.export(calendar: TestSupport.calendar)?.value

        #expect(model.sharedFile == nil)
        #expect(model.exportAlert == .empty)
        #expect(fixture.exportedFiles().isEmpty)
    }

    /// 共有のシートを出している間は、次の書き出しを受け付けない（同じシートの上に重ねて出さないように）。
    @Test func exportIsIgnoredWhileSharing() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.insert(Self.entry(850, TestSupport.now))
        let model = fixture.makeModel()
        await model.export(calendar: TestSupport.calendar)?.value
        let first = try #require(model.sharedFile)

        #expect(model.export(calendar: TestSupport.calendar) == nil)
        #expect(model.sharedFile == first)
        #expect(fixture.exportedFiles().count == 1)
    }

    /// 書き出しの途中で画面を離れたら、ファイルを残さず、アラートも出さない。
    @Test func cancellingExportLeavesNoFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try fixture.insert(Self.entry(850, TestSupport.now))
        let model = fixture.makeModel()

        let task = model.export(calendar: TestSupport.calendar)
        #expect(model.isExporting)
        model.cancelExport()
        await task?.value

        #expect(model.sharedFile == nil)
        #expect(model.exportAlert == nil)
        #expect(model.isExporting == false)
        #expect(fixture.exportedFiles().isEmpty)
    }

    /// 共有の途中でアプリが終了したときなどに残ったファイルは、次に設定を開いたときに片づける。
    @Test func openingSettingsRemovesLeftoverFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let leftover = fixture.directory.appending(path: "old/saifulog-20260901.csv")
        try FileManager.default.createDirectory(at: leftover.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: leftover)

        _ = fixture.makeModel()

        #expect(!FileManager.default.fileExists(atPath: leftover.path(percentEncoded: false)))
    }

    // MARK: - 予算

    @Test func budgetRowShowsCurrentBudgetAndReloads() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        #expect(model.totalBudget == nil)

        model.presentBudgetSetup()
        let budgetSetup = try #require(model.budgetSetup)
        budgetSetup.selectQuickAmount(150_000)
        #expect(budgetSetup.save())
        model.budgetSetup = nil
        model.reloadBudget()

        #expect(model.totalBudget == 150_000)
    }

    // MARK: - このアプリについて

    @Test func versionTextShowsVersionAndBuild() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        #expect(fixture.makeModel().versionText == "0.1.0 (12)")
        #expect(SettingsModel.versionText(info: [:]) == "- (-)")
    }

    /// プライバシーポリシーとライセンスは、公開リポジトリの main のファイルを開く。
    @Test func linksPointToRepositoryDocuments() {
        #expect(SettingsModel.privacyPolicyURL.absoluteString == "https://github.com/iam74k4/SaifuLog-Apple/blob/main/PRIVACY.md")
        #expect(SettingsModel.licenseURL.absoluteString == "https://github.com/iam74k4/SaifuLog-Apple/blob/main/LICENSE")
    }
}
