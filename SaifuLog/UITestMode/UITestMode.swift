// UI テスト（SaifuLogUITests）が起動したときの決まった状態。DEBUG のビルドにだけ入れる（撮影用のデモと同じ）。
// App Store へ出すビルドと TestFlight のビルド（どちらも Release）には入らない。撮影用のデモの記録とレシートを使い回すので、
// DEBUG の外に出れば撮影用のデモの印も入り、release.mk のアーカイブの検査（RELEASE_SCREENSHOT_DEMO_MARKER）で止まる。
#if DEBUG
import Foundation
import SaifuLogCore
import SwiftData

/// UI テスト（SaifuLogUITests）が起動したときの状態（DEBUG のビルドだけ）。
///
/// UI テストは起動引数 `-SaifuLogUITest YES` を付けてアプリを開く。引数が無ければ何もしない（ふだんの Xcode の Run には効かない）。
/// UI テストの間は:
/// - 保存先はメモリの上だけにし、起動のたびに空から始める（利用者の記録のファイル default.store を開かない）。
///   `-SaifuLogUITestSeed demo` なら、撮影用のデモと同じ架空の記録と予算を入れる（月のまとめ・カレンダー・書き出しを中身のある
///   状態で確かめるため）。
/// - 設定（UserDefaults）は専用の領域を毎回空にして使う（利用者の設定に触れない）。初回の案内は終えたことにする
///   （`-SaifuLogUITestFirstRun YES` なら出す）。
/// - ロックと iCloud 同期はオフ（シミュレータでは認証も iCloud のアカウントの確かめもできないため）。
/// - 端末内 AI を使わない（読み取り・カテゴリの聞き直し・チャットの操作・質問・一言）。キーワード辞書とコアの計算だけにして、
///   端末によって読み方や答えが変わらないようにする（AI が無くても記録できるアプリであることの確かめにもなる）。
/// - 「いま」は撮影用のデモと同じく、その月の 15 日の 20:30 に置く（月の初めや終わりに走らせても、同じ日付の画面にする）。
/// - 診断画面のボタンを出さない（App Store へ出すビルドと同じ画面を確かめる）。
/// - `-SaifuLogUITestReceipt YES` なら、ホームが出た後に、決まったレシートの文字（撮影用のデモと同じ）を読み取った ⑤ を開く
///   （書類カメラと写真の選択はアプリの外の画面で、UI テストからは操作できないため）。
@MainActor
final class UITestMode {
    /// 始めの記録。
    enum Seed: String, Sendable {
        /// 記録も予算も無い。
        case empty
        /// 撮影用のデモと同じ架空の記録と予算（`ScreenshotDemoLedger`）。
        case demo
    }

    /// 起動引数から読んだ設定。
    struct Configuration: Equatable, Sendable {
        var seed: Seed = .empty
        /// 初回の案内（① ようこそ）を出すか。
        var showsOnboarding = false
        /// ホームが出た後に、決まったレシートの読み取り結果（⑤）を開くか。
        var opensReceipt = false
    }

    /// UI テストで起動したことを示す起動引数。
    nonisolated static let argument = "-SaifuLogUITest"
    /// 始めの記録（`Seed` の rawValue）を渡す起動引数。
    nonisolated static let seedArgument = "-SaifuLogUITestSeed"
    /// 初回の案内を出すか（YES）を渡す起動引数。
    nonisolated static let firstRunArgument = "-SaifuLogUITestFirstRun"
    /// レシートの読み取り結果を開くか（YES）を渡す起動引数。
    nonisolated static let receiptArgument = "-SaifuLogUITestReceipt"
    /// UI テストの設定を置く UserDefaults の領域。利用者の設定（`UserDefaults.standard`）とは別にし、起動のたびに空にする。
    nonisolated static let defaultsSuiteName = "com.iam74k4.SaifuLog.UITest"

    /// このプロセスの UI テストの状態。起動引数が無ければ nil（ふだんの起動）。
    static let current: UITestMode? = parse(arguments: ProcessInfo.processInfo.arguments).map {
        UITestMode(configuration: $0, launchedAt: .now, calendar: .current)
    }

    let configuration: Configuration
    /// UI テストの「いま」（起動した月の 15 日の 20:30）。
    let now: Date
    let calendar: Calendar
    /// UI テストの設定の置き場所（`defaultsSuiteName` の領域）。
    let defaults: UserDefaults
    /// 設定の領域の名前（テストの後片づけで領域ごと消す）。
    let defaultsDomain: String
    /// UI テストのアプリのロックと iCloud 同期の設定（一時フォルダのファイル。毎回どちらもオフで始める）。
    let launchSettings: LaunchSettingsStore

    /// 作った瞬間。時計（`makeClock`）は、ここからの経過を「いま」に足して進める（続けて送った文が送った順に並ぶように）。
    private let startedAt = ContinuousClock.now

    init(
        configuration: Configuration,
        launchedAt: Date,
        calendar: Calendar,
        defaultsSuiteName: String = UITestMode.defaultsSuiteName
    ) {
        self.configuration = configuration
        self.calendar = calendar
        now = ScreenshotDemo.pinnedNow(on: launchedAt, calendar: calendar)
        // 領域が作れないのは、名前がアプリの Bundle ID か NSGlobalDomain のときだけ（決め打ちの名前なので起きない）。起きたら
        // 止める（standard に書いて利用者の設定を書き換えないため。DEBUG のビルドだけのコード）。
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            preconditionFailure("UI テストの設定の領域を作れません: \(defaultsSuiteName)")
        }
        self.defaults = defaults
        defaultsDomain = defaultsSuiteName
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        if !configuration.showsOnboarding {
            defaults.set(true, for: AppSettings.hasCompletedOnboarding)
        }
        // ロックと iCloud 同期はオフ。ファイルを先に書いておく（無いと、ロックは決めるまで画面を隠すため）。
        let settingsURL = URL.temporaryDirectory.appending(
            path: "\(defaultsSuiteName).LaunchSettings.json", directoryHint: .notDirectory
        )
        try? FileManager.default.removeItem(at: settingsURL)
        launchSettings = LaunchSettingsStore(url: settingsURL, defaults: defaults)
        _ = try? launchSettings.update { _ in }
    }

    /// 起動引数から設定を読む。UI テストの引数が無ければ nil。
    nonisolated static func parse(arguments: [String]) -> Configuration? {
        guard arguments.contains(argument) else { return nil }
        var configuration = Configuration()
        if let seed = value(after: seedArgument, in: arguments).flatMap(Seed.init(rawValue:)) {
            configuration.seed = seed
        }
        configuration.showsOnboarding = isOn(value(after: firstRunArgument, in: arguments))
        configuration.opensReceipt = isOn(value(after: receiptArgument, in: arguments))
        return configuration
    }

    private nonisolated static func value(after name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private nonisolated static func isOn(_ value: String?) -> Bool {
        value == "YES" || value == "1" || value == "true"
    }

    /// UI テストの時計。「いま」から、作ってからの経過だけ進む。
    func makeClock() -> @Sendable () -> Date {
        let pinned = now
        let started = startedAt
        return {
            let elapsed = started.duration(to: .now).components
            return pinned.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
    }

    // MARK: - 差し替えるもの

    /// 保存先。メモリの上だけに作る（`demo` なら撮影用のデモと同じ記録と予算を入れる）。
    func makeContainer() throws -> ModelContainer {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        if configuration.seed == .demo {
            try ScreenshotDemoLedger.insert(into: container.mainContext, now: now, calendar: calendar)
        }
        return container
    }

    /// 保存先を開くもの。iCloud とは同期せず（`.none`）、ロックも待たない（シミュレータで動かすため）。
    func makeStoreHost() -> StoreHost {
        StoreHost(
            cloudKitDatabase: ModelContainerFactory.CloudKitDatabase.none,
            settings: launchSettings,
            openContainer: { [self] _ in try makeContainer() },
            isProtectedDataAvailable: { true }
        )
    }

    /// 初回の案内。出さないなら nil。AI の可否は「使えない」に決める（端末によって案内の文が変わらないように）。
    func makeOnboardingModel() -> OnboardingModel? {
        guard configuration.showsOnboarding else { return nil }
        return OnboardingModel(defaults: defaults, aiStatus: { .unavailable })
    }

    /// ホームのモデル。時計・解析・質問の答え方・レシートの読み取りを、UI テストのものに差し替え、端末内 AI を使わない。
    func makeHomeModel(context: ModelContext, pendingWrites: PendingStoreWrites, storeHost: StoreHost?) -> HomeModel {
        let receiptLines = ScreenshotDemoReceipt.lines(now: now, calendar: calendar)
        return HomeModel(
            store: EntryStore(context: context),
            pendingWrites: pendingWrites,
            storeHost: storeHost,
            makeParser: { now, calendar in RuleBasedParser(calendar: calendar, now: { now }) },
            makeCategoryRefiner: { nil },
            makeCommandInterpreter: { nil },
            makeAnswerer: { RuleBasedQuestionAnswerer() },
            makeRemarkWriter: { nil },
            makeRecordRemarkWriter: { nil },
            receiptReader: ReceiptReader(recognize: { _ in receiptLines }, makeRefiner: { nil }),
            canUseDocumentCamera: false,
            now: makeClock()
        )
    }

    // MARK: - 起動引数で頼まれた画面を開く

    /// ホームが出た後に、起動引数で頼まれた画面を開く（`AppRootView` が呼ぶ）。開き終えるまで待つ。
    func stage(on home: HomeModel, calendar: Calendar) async {
        guard configuration.opensReceipt else { return }
        await home.readReceipt([ScreenshotDemoReceipt.image()], source: .photos, calendar: calendar).value
    }
}

#endif
