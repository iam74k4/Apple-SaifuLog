// App Store のスクリーンショットを撮るための「撮影用のデモ」。DEBUG のビルドにだけ入れる。
// App Store へ出すビルドと TestFlight のビルド（どちらも Release）に入っていないことは、release.mk がアーカイブの中身
// （下の marker）で確かめる。
#if DEBUG
import Foundation
import OSLog
import SaifuLogCore
import SwiftData

/// App Store のスクリーンショットを撮るための撮影用のデモ（DEBUG のビルドだけ）。
///
/// `scripts/app-store-screenshots.sh` が起動引数 `-SaifuLogScreenshotDemo <画面>` を付けて起動し、撮る画面を開かせる。
/// 引数が無ければ何もしない（ふだんの Xcode の Run には効かない）。デモの間は:
/// - 保存先はメモリの上だけにし、架空の記録と予算を入れる（利用者の記録のファイル default.store を開かない）。
/// - 設定（UserDefaults）は専用の領域（`defaultsSuiteName`）を毎回空にして使う（利用者の設定に触れない）。
/// - 初回の案内を出さず、診断画面のボタン（帯の聴診器）など開発用の表示を出さない。家族との共有（機能フラグで隠している機能）も
///   出さない。
/// - 端末や AI によって変わるもの（AI の一言・レシートの文字認識・声の書き起こし・App Store の価格）は、決まった中身にする
///   （どれも実際のアプリが出しうる中身にする）。
/// - 「いま」は撮影の月の 15 日の 20:30 に置き、日付はそこから相対で作る（`pinnedNow(on:calendar:)`）。月のどの日に撮っても
///   同じ画面になるようにする。
@MainActor
final class ScreenshotDemo {
    /// 撮る画面。起動引数の値（rawValue）とスクリーンショットのファイル名に使う。
    enum Screen: String, CaseIterable, Sendable {
        /// 記録のタイムラインと今月の帯。
        case home
        /// 家計への質問と回答カード。
        case ask
        /// 月のまとめの予算の進みとカテゴリ別のグラフ・行（カテゴリ別の予算の進みも。下の端まで送って開く）。
        case report
        /// 先週のふりかえりのカード。
        case recap
        /// レシートの読み取り結果のシート。
        case receipt
        /// 声の入力の聞いている表示。
        case voice
        /// プレミアムのシートの上のほう（プレミアムでできることと、下の帯の体験と購入のボタン。プレミアムの課金アイテムの審査用の
        /// スクリーンショット）。
        case premium
        /// プレミアムのシートの下のほう（14 日間の無料体験の説明とボタン。体験の課金アイテムの審査用のスクリーンショット）。
        case trial

        /// 購入の状態を指定しなかったときの状態。プレミアムのシートは購入と体験のボタンを写すので無料、ほかは購入済み
        /// （無料の残りの回数の行などを写さず、ふりかえりと月のまとめの AI の一言を写すため）。
        var defaultPremium: PremiumChoice {
            switch self {
            case .premium, .trial: .free
            case .home, .ask, .report, .recap, .receipt, .voice: .purchased
            }
        }
    }

    /// デモの購入の状態（起動引数 `-SaifuLogScreenshotPremium`）。
    enum PremiumChoice: String, CaseIterable, Sendable {
        case purchased
        case free
    }

    /// 起動引数から読んだ設定。
    struct Configuration: Equatable, Sendable {
        var screen: Screen
        var premium: PremiumChoice
    }

    /// 撮る画面を渡す起動引数。
    nonisolated static let screenArgument = "-SaifuLogScreenshotDemo"
    /// 購入の状態を渡す起動引数（省けば画面ごとの既定。`Screen.defaultPremium`）。
    nonisolated static let premiumArgument = "-SaifuLogScreenshotPremium"
    /// 撮影用のデモが入ったビルドにだけある印。release.mk の `RELEASE_SCREENSHOT_DEMO_MARKER` と同じ値にする（変えるときは両方）。
    ///
    /// release.mk は、アーカイブのアプリの中にこの文字列があれば止める（撮影用のデモは DEBUG のビルドだけのもの）。
    /// `stage(on:calendar:)` がログに書くので最適化で消されず、撮影のスクリプトが Debug のアプリに印があることを確かめる
    /// （印を変えて release.mk を直し忘れたときに、「入っていない」の確かめが空振りしないように）。16 バイト以上にしておく
    /// （15 バイトまでの文字列は、Swift がバイナリに文字列として置かないことがあるため）。
    nonisolated static let marker = "SaifuLog-ScreenshotDemo-v1"
    /// デモの設定を置く UserDefaults の領域。利用者の設定（`UserDefaults.standard`）とは別にし、起動のたびに空にする。
    nonisolated static let defaultsSuiteName = "com.iam74k4.SaifuLog.ScreenshotDemo"
    /// デモの「いま」の日（撮影の月の何日か）。月の半ばにする。撮った日のままだと、月の最後の日には帯と月のまとめの
    /// 「1日あたり」が「残り」と同じ額に、「今日までの目安」が予算と同じ額になり、月の初めには今月の記録が少なく、
    /// ストアの画像に向かない数字になるため。
    nonisolated static let pinnedDay = 15
    /// デモの「いま」の時刻。夕方までの記録がそろい、日付が替わる前の時刻にする。
    nonisolated static let pinnedTime = DateComponents(hour: 20, minute: 30)

    /// このプロセスの撮影用のデモ。起動引数が無ければ nil（ふだんの起動）。
    static let current: ScreenshotDemo? = parse(arguments: ProcessInfo.processInfo.arguments).map {
        ScreenshotDemo(
            configuration: $0, launchedAt: .now, calendar: .current,
            uiLanguage: Bundle.main.preferredLocalizations.first
        )
    }

    let screen: Screen
    let premium: PremiumChoice
    /// デモの「いま」（撮影の月の 15 日の 20:30）。記録と予算はここから相対で作る。
    let now: Date
    let calendar: Calendar
    /// AI の一言を添えるか。一言は端末内 AI が日本語で書く（AI への指示が日本語）ので、日本語の画面だけにする。英語の画面では
    /// AI の使えない端末と同じく一言を添えない（英語の画面に日本語の一言が混ざると、訳し忘れに見えるため）。
    let showsAIRemarks: Bool
    /// デモの設定の置き場所（`defaultsSuiteName` の領域）。
    let defaults: UserDefaults
    /// 設定の領域の名前（テストの後片づけで領域ごと消す）。
    let defaultsDomain: String
    /// デモのアプリのロックと iCloud 同期の設定（一時フォルダのファイル。毎回どちらもオフで始める）。
    let launchSettings: LaunchSettingsStore

    /// 起動した瞬間。デモの時計（`clock`）は、起動してからの経過をデモの「いま」に足して進める。
    private let launchedAt: Date

    private static let logger = Logger(subsystem: "com.iam74k4.SaifuLog", category: "screenshot-demo")

    /// - Parameters:
    ///   - launchedAt: 起動した瞬間（この月の 15 日をデモの「いま」にする）。
    ///   - calendar: 日付の区切りの暦（端末の暦）。
    ///   - uiLanguage: 画面の言語（`Bundle.main.preferredLocalizations.first`）。日本語のときだけ AI の一言を添える。
    ///   - defaultsSuiteName: 設定の領域。テストで別の領域にする。
    init(
        configuration: Configuration,
        launchedAt: Date,
        calendar: Calendar,
        uiLanguage: String?,
        defaultsSuiteName: String = ScreenshotDemo.defaultsSuiteName
    ) {
        screen = configuration.screen
        premium = configuration.premium
        self.calendar = calendar
        self.launchedAt = launchedAt
        now = Self.pinnedNow(on: launchedAt, calendar: calendar)
        showsAIRemarks = uiLanguage?.hasPrefix("ja") ?? false
        // 領域が作れないのは、名前がアプリの Bundle ID か NSGlobalDomain のときだけ（決め打ちの名前なので起きない）。起きたら
        // 止める（standard に書いて利用者の設定を書き換えないため。DEBUG のビルドだけのコード）。
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            preconditionFailure("撮影用のデモの設定の領域を作れません: \(defaultsSuiteName)")
        }
        self.defaults = defaults
        defaultsDomain = defaultsSuiteName
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        // 初回の案内を終えたことにする（デモはホームから始める）。
        defaults.set(true, for: AppSettings.hasCompletedOnboarding)
        // ふりかえりのカードは、ふりかえりの画面でだけ出す。ほかの画面では「今週もう出した」ことにする。
        if screen != .recap {
            defaults.set(now, for: AppSettings.weeklyRecapShownAt)
        }
        // ロックと iCloud 同期はオフ。ファイルを先に書いておく（無いと、ロックは決めるまで画面を隠すため）。
        let settingsURL = URL.temporaryDirectory.appending(
            path: "\(defaultsSuiteName).LaunchSettings.json", directoryHint: .notDirectory
        )
        try? FileManager.default.removeItem(at: settingsURL)
        launchSettings = LaunchSettingsStore(url: settingsURL, defaults: defaults)
        _ = try? launchSettings.update { _ in }
    }

    /// 起動引数から撮る画面と購入の状態を読む。撮る画面の引数が無いか、知らない画面なら nil。
    nonisolated static func parse(arguments: [String]) -> Configuration? {
        guard let screenValue = value(after: screenArgument, in: arguments),
              let screen = Screen(rawValue: screenValue)
        else { return nil }
        let premium = value(after: premiumArgument, in: arguments).flatMap(PremiumChoice.init(rawValue:))
        return Configuration(screen: screen, premium: premium ?? screen.defaultPremium)
    }

    private nonisolated static func value(after name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// `date` の月（渡された暦の月）の 15 日の 20:30。暦で日付や時刻を置けなければ（実際には無い）`date` のまま。
    ///
    /// 月の区切りはホームの「今月」と同じ暦で取る（和暦などでも、帯の「今月」の半ばになるように）。
    nonisolated static func pinnedNow(on date: Date, calendar: Calendar) -> Date {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let day = calendar.date(byAdding: .day, value: pinnedDay - 1, to: month.start)
        else { return date }
        return calendar.date(
            bySettingHour: pinnedTime.hour ?? 0, minute: pinnedTime.minute ?? 0, second: 0, of: day
        ) ?? date
    }

    /// デモの時計。デモの「いま」から、起動してからの経過だけ進む（続けて送った質問の順が、送った順に並ぶように）。
    func makeClock() -> @Sendable () -> Date {
        let pinned = now
        let launched = launchedAt
        return { pinned.addingTimeInterval(max(0, Date.now.timeIntervalSince(launched))) }
    }

    // MARK: - 差し替えるもの

    /// 保存先。メモリの上だけに作り、架空の記録と予算を入れる（利用者の記録のファイルは開かない）。
    func makeContainer() throws -> ModelContainer {
        let container = try ModelContainerFactory.makeInMemoryContainer()
        try ScreenshotDemoLedger.insert(into: container.mainContext, now: now, calendar: calendar)
        return container
    }

    /// 保存先を開くもの。iCloud とは同期せず（`.none`）、ロックも待たない（シミュレータで撮るため）。
    func makeStoreHost() -> StoreHost {
        StoreHost(
            cloudKitDatabase: ModelContainerFactory.CloudKitDatabase.none,
            settings: launchSettings,
            openContainer: { [self] _ in try makeContainer() },
            isProtectedDataAvailable: { true }
        )
    }

    /// 購入の状態。購入済みならプレミアムの購入の記録を 1 つ持ち、App Store の価格の代わりに日本の価格の表示を出す
    /// （`PurchaseManager.useScreenshotDisplayPrices`）。App Store の購入の記録（Transaction）は読まない。
    func makePurchases() -> PurchaseManager {
        let purchases: [VerifiedPurchase] = switch premium {
        case .purchased:
            [VerifiedPurchase(
                transactionID: 1,
                purchase: PremiumPurchase(product: .premium, purchaseDate: now.addingTimeInterval(-30 * 24 * 60 * 60))
            )]
        case .free:
            []
        }
        let manager = PurchaseManager(now: makeClock(), loadPurchases: { purchases }, loadProducts: { _ in [] }, sync: {})
        manager.useScreenshotDisplayPrices(Self.displayPrices)
        Task { await manager.refreshPurchases() }
        return manager
    }

    /// 日本の App Store の価格の表示（`Config/SaifuLog.storekit` と App Store Connect の価格）。画面の言語の書き方で書く。
    nonisolated static var displayPrices: [PremiumProduct: String] {
        [
            .premium: 1_800.formatted(.currency(code: "JPY")),
            .trial14: 0.formatted(.currency(code: "JPY")),
        ]
    }

    /// ホームのモデル。設定・時計・解析・質問の答え方・AI の一言・レシートの読み取り・声の入力を、デモのものに差し替える。
    func makeHomeModel(
        context: ModelContext, pendingWrites: PendingStoreWrites, purchases: PurchaseManager, storeHost: StoreHost?,
        household: HouseholdHost?
    ) -> HomeModel {
        let clock = makeClock()
        let writesRemarks = showsAIRemarks
        let receiptLines = ScreenshotDemoReceipt.lines(now: now, calendar: calendar)
        return HomeModel(
            store: EntryStore(context: context),
            pendingWrites: pendingWrites,
            purchases: purchases,
            storeHost: storeHost,
            household: household,
            defaults: defaults,
            // 端末内 AI を使わず、キーワード辞書で読む（端末によって読み方が変わらないように）。
            makeParser: { now, calendar in RuleBasedParser(calendar: calendar, now: { now }) },
            makeAnswerer: { ScreenshotDemoAnswerer(writesRemark: writesRemarks) },
            makeRemarkWriter: { writesRemarks ? ScreenshotDemoRemarkWriter() : nil },
            receiptReader: ReceiptReader(recognize: { _ in receiptLines }, makeRefiner: { nil }),
            canUseDocumentCamera: false,
            voice: VoiceInputModel(
                transcriber: ScreenshotDemoTranscriber(),
                microphone: ScreenshotDemoMicrophone(),
                network: ScreenshotDemoNetwork(),
                // 時計を止めておき、話し終えた・話し始めない・30 秒で止まらないようにする（撮るまで聞いている表示のまま）。
                now: { [pinned = now] in pinned },
                announce: { _ in },
                announceAndWait: { _ in }
            ),
            now: clock,
            announce: { _ in }
        )
    }

    // MARK: - 撮る画面を開く

    /// ホームのモデルを作った直後（ホームが画面に出る前）に、撮る画面の下ごしらえをする（`AppRootView` が呼び、済んでから
    /// ホームを出す）。
    ///
    /// ふりかえりのカードは、AI の一言まで書き終えてからホームを出す。ホームが出た後にカードが出たり伸びたりすると、タイムラインが
    /// 下端まで送られずに途中で止まった（シミュレータの iOS 26.4 で見た。一言の無いカードはタイムラインの途中で止まり、一言が後から
    /// 付いたカードは下の端が入力欄に隠れた）。スクリーンショットには、カードが下端に出そろった形を写す。タイムラインを VStack にして
    /// 途中で止まる不具合を直した後も（`HomeView` の `TimelineScrollView`）、一言を書き終えた形を写すために残す。
    func prepare(_ home: HomeModel, calendar: Calendar) async {
        guard screen == .recap else { return }
        home.showWeeklyRecapIfDue(calendar: calendar)
        await home.weeklyRecap?.remark.currentTask?.value
    }

    /// ホームが出た後に、撮る画面を開く（`AppRootView` が呼ぶ）。開き終えるまで（質問の答え・レシートの読み取りが済むまで）待つ。
    func stage(on home: HomeModel, calendar: Calendar) async {
        Self.logger.notice("\(Self.marker, privacy: .public): \(self.screen.rawValue, privacy: .public)")
        switch screen {
        case .home, .recap:
            // タイムラインと帯はそのまま。ふりかえりのカードは、ホームが出たときに出る（`HomeModel.showWeeklyRecapIfDue`）。
            break
        case .ask:
            for question in Self.questions {
                home.draft = question
                await home.send(calendar: calendar)?.value
            }
        case .report:
            home.presentMonthlyReport(calendar: calendar)
            // AI の一言（日本語の画面）を書き終えてから、下の端へ送らせる。カテゴリ別のグラフと金額の行を写すため（上から
            // 開くと、一言と数字と予算のカードに押されて、グラフが画面の下で切れ、金額の行は写らない）。一言を待つのは、
            // 送った後に上に一言のカードが出て、中身の高さが変わらないようにするため。
            await home.monthlyReport?.remark.currentTask?.value
            home.monthlyReport?.screenshotScrollsToBottom = true
        case .receipt:
            await home.readReceipt([ScreenshotDemoReceipt.image()], source: .photos, calendar: calendar).value
        case .voice:
            await home.voice.toggle()?.value
        case .premium:
            home.presentPremium()
        case .trial:
            home.presentPremium()
            home.premiumSheet?.screenshotScrollsToBottom = true
        }
    }

    /// 質問の画面で送る質問（ようこそとタイムラインの例と同じ書き方）。デモの「いま」は月の半ばなので、今月を聞く。
    nonisolated static let questions = ["今月カフェいくら?", "今月あと何日でいくら使える?"]
}
#endif
