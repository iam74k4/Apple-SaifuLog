// UI テストの状態（UITestMode）は DEBUG のビルドだけにある（撮影用のデモと同じ）。
#if DEBUG
import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// UI テスト（SaifuLogUITests）が起動したときの状態。起動引数の読み方、保存先と設定が使い捨てであること、端末内 AI を使わず
/// キーワード辞書で記録すること、レシートの読み取り結果の開き方を、メモリの上の保存先と固定の日時で確かめる。
@MainActor
struct UITestModeTests {
    // MARK: - 起動引数

    @Test("起動引数から始めの記録・初回の案内・レシートを読む")
    func parsesArguments() {
        typealias Configuration = UITestMode.Configuration
        let base = ["SaifuLog", "-SaifuLogUITest", "YES", "-AppleLanguages", "(ja)"]
        #expect(UITestMode.parse(arguments: base) == Configuration())
        #expect(UITestMode.parse(arguments: base + ["-SaifuLogUITestSeed", "demo"]) == Configuration(seed: .demo))
        #expect(UITestMode.parse(arguments: base + ["-SaifuLogUITestFirstRun", "YES"]) == Configuration(showsOnboarding: true))
        #expect(UITestMode.parse(arguments: base + ["-SaifuLogUITestReceipt", "YES"]) == Configuration(opensReceipt: true))
        // 知らない値は既定のまま。
        #expect(
            UITestMode.parse(arguments: base + ["-SaifuLogUITestSeed", "full", "-SaifuLogUITestFirstRun", "NO"]) == Configuration()
        )
    }

    @Test("UI テストの引数が無ければ、UI テストにしない（ふだんの起動）。テストのプロセスも引数を持たない")
    func ignoresOrdinaryLaunch() {
        #expect(UITestMode.parse(arguments: ["SaifuLog"]) == nil)
        // ほかの引数の名前の頭が同じでも、UI テストの引数そのものが無ければ UI テストにしない。
        #expect(UITestMode.parse(arguments: ["SaifuLog", "-SaifuLogUITestSeed", "demo"]) == nil)
        #expect(UITestMode.current == nil)
    }

    @Test("「いま」は起動した月の 15 日の 20:30（撮影用のデモと同じ）")
    func pinsNowToMiddleOfMonth() {
        let mode = Self.makeMode(.init())
        defer { Self.removeDefaults(of: mode) }
        #expect(mode.now == TestSupport.date(2026, 9, 15, hour: 20, minute: 30))
    }

    // MARK: - 使い捨ての保存先と設定

    @Test("保存先はメモリの上だけで、既定は空。demo なら撮影用のデモと同じ記録が入る")
    func containerIsInMemoryAndSeeded() throws {
        let empty = Self.makeMode(UITestMode.Configuration())
        defer { Self.removeDefaults(of: empty) }
        let emptyContainer = try empty.makeContainer()
        #expect(emptyContainer.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(emptyContainer.configurations.allSatisfy { $0.url != ModelContainerFactory.storeURL })
        #expect(try emptyContainer.mainContext.fetchCount(FetchDescriptor<Entry>()) == 0)
        #expect(try emptyContainer.mainContext.fetchCount(FetchDescriptor<Budget>()) == 0)

        let demo = Self.makeMode(UITestMode.Configuration(seed: .demo))
        defer { Self.removeDefaults(of: demo) }
        let demoContainer = try demo.makeContainer()
        let expected = ScreenshotDemoLedger.records(now: demo.now, calendar: demo.calendar).count
        #expect(try demoContainer.mainContext.fetchCount(FetchDescriptor<Entry>()) == expected)
    }

    @Test("保存先を開くもの（StoreHost）は、iCloud を使わずにメモリの上の保存先を開く")
    func storeHostOpensInMemoryContainer() {
        let mode = Self.makeMode(.init())
        defer { Self.removeDefaults(of: mode) }
        let host = mode.makeStoreHost()
        host.start()

        guard case .ready(let container) = host.state else {
            Issue.record("保存先を開けていません: \(host.state)")
            return
        }
        #expect(host.cloudKitDatabase == .none)
        #expect(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
    }

    @Test("設定は専用の領域を空にして使い、初回の案内は頼まれたときだけ出す")
    func defaultsAreDisposableAndOnboardingIsOptIn() throws {
        let suiteName = "UITestModeTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let leftover = try #require(UserDefaults(suiteName: suiteName))
        leftover.set(true, forKey: "leftover")

        let mode = UITestMode(
            configuration: .init(), launchedAt: TestSupport.now, calendar: TestSupport.calendar, defaultsSuiteName: suiteName
        )
        #expect(mode.defaults !== UserDefaults.standard)
        #expect(mode.defaults.object(forKey: "leftover") == nil)
        #expect(mode.defaults.bool(for: AppSettings.hasCompletedOnboarding))
        #expect(mode.makeOnboardingModel() == nil)

        let firstRun = UITestMode(
            configuration: .init(showsOnboarding: true), launchedAt: TestSupport.now, calendar: TestSupport.calendar,
            defaultsSuiteName: suiteName
        )
        #expect(!firstRun.defaults.bool(for: AppSettings.hasCompletedOnboarding))
        let onboarding = try #require(firstRun.makeOnboardingModel())
        onboarding.start()
        // 案内を終えたことは UI テストの領域に書く（利用者の設定には書かない）。
        #expect(firstRun.defaults.bool(for: AppSettings.hasCompletedOnboarding))
    }

    // MARK: - ホーム

    @Test("ホームは端末内 AI を使わず、キーワード辞書で記録する（「いま」は 15 日）")
    func homeRecordsWithKeywordDictionary() async throws {
        let (mode, home, container) = try Self.makeHome(.init())
        defer { Self.removeDefaults(of: mode) }

        home.draft = "ランチ 850"
        await home.send(calendar: mode.calendar)?.value

        let entries = try container.mainContext.fetch(FetchDescriptor<Entry>())
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.amount == 850)
        #expect(entry.category == .food)
        let spentOnPinnedDay = mode.calendar.isDate(entry.spentAt, inSameDayAs: mode.now)
        #expect(spentOnPinnedDay)
    }

    @Test("レシートを頼まれたときだけ、決まったレシートの読み取り結果を開く")
    func stageOpensReceiptOnlyWhenAsked() async throws {
        let (plain, plainHome, _) = try Self.makeHome(.init())
        defer { Self.removeDefaults(of: plain) }
        await plain.stage(on: plainHome, calendar: plain.calendar)
        #expect(plainHome.receiptResult == nil)

        let (receipt, receiptHome, _) = try Self.makeHome(.init(opensReceipt: true))
        defer { Self.removeDefaults(of: receipt) }
        await receipt.stage(on: receiptHome, calendar: receipt.calendar)
        let result = try #require(receiptHome.receiptResult)
        #expect(result.state == .ready)
        #expect(result.receiptTotal == ScreenshotDemoReceipt.total)
    }

    // MARK: - 手伝い

    static func makeMode(_ configuration: UITestMode.Configuration) -> UITestMode {
        UITestMode(
            configuration: configuration, launchedAt: TestSupport.now, calendar: TestSupport.calendar,
            defaultsSuiteName: "UITestModeTests.\(UUID().uuidString)"
        )
    }

    static func removeDefaults(of mode: UITestMode) {
        UserDefaults.standard.removePersistentDomain(forName: mode.defaultsDomain)
    }

    /// UI テストのホームのモデル（メモリの上の保存先）。
    static func makeHome(_ configuration: UITestMode.Configuration) throws -> (UITestMode, HomeModel, ModelContainer) {
        let mode = makeMode(configuration)
        let container = try mode.makeContainer()
        retained.append(container)
        let home = mode.makeHomeModel(context: container.mainContext, pendingWrites: PendingStoreWrites(), storeHost: nil)
        return (mode, home, container)
    }

    /// 保存先はコンテナが生きている間しか使えないので、テストの間は持っておく。
    private static var retained: [ModelContainer] = []
}
#endif
