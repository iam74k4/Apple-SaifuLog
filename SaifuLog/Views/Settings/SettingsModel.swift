import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 「設定」（⑧）の状態と操作。プレミアム（⑨ を開く・購入の復元）、月の予算を開く、週の始まり、記録の CSV 書き出し、
/// このアプリについて。
///
/// 画面（`SettingsView`）から切り離し、保存先・設定の置き場所・時計・書き出し先を差し替えて SaifuLogTests で
/// 確かめられるようにしている。CSV の中身はコア（`LedgerCSVWriter`）、ファイルの作成は `LedgerExporter` が受け持つ。
/// 購入と復元そのものは、アプリで 1 つの `PurchaseManager` が受け持つ。
///
/// iCloud 同期の行は、その仕組みを作るまで出さない（まだできないことを設定に並べない）。
@MainActor
@Observable
final class SettingsModel {
    /// プライバシーポリシー（リポジトリの main の PRIVACY.md。Safari で開く）。
    static let privacyPolicyURL = URL(string: "https://github.com/iam74k4/SaifuLog-Apple/blob/main/PRIVACY.md")!
    /// ライセンス（リポジトリの main の LICENSE。Safari で開く）。
    static let licenseURL = URL(string: "https://github.com/iam74k4/SaifuLog-Apple/blob/main/LICENSE")!

    /// 書き出す期間。開くたびに今月から始める（前に選んだ期間を覚えておくほどの設定ではないため）。
    var exportPeriod: LedgerExportPeriod = .thisMonth
    /// 書き出しの途中（ボタンを押せなくし、進行中の印を出す）。
    private(set) var isExporting = false
    /// 共有に出しているファイル。共有のシートを閉じると `finishSharing()` で消して nil に戻す。
    private(set) var sharedFile: ExportedFile?
    /// 書き出せなかった・書き出す記録が無かった（アラートを出す）。
    var exportAlert: ExportAlert?
    /// 「予算を決める」のシートの状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var budgetSetup: BudgetSetupModel?
    /// 「プレミアム」のシートの状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var premiumSheet: PremiumSheetModel?
    /// 購入の復元の結果（アラートを出す）。
    var purchaseAlert: PurchaseAlert?
    /// プレミアムの購入と状態（アプリで 1 つ）。
    let purchases: PurchaseManager
    /// いまの月の予算。決めていないか、読めなければ nil。
    private(set) var totalBudget: Int?
    /// 端末の設定（地域と iOS の設定）の週の始まり（1 = 日曜）。「端末の設定に合わせる」の選択肢に曜日を添える。
    let systemFirstWeekday: Int
    /// このアプリについての版とビルド番号（「0.1.0 (12)」）。
    let versionText: String

    /// 週の始まり。変えるとすぐ設定に書く（画面の根元が `@AppStorage` で読み、画面の暦に当てはめる）。
    var weekStart: WeekStart {
        get { storedWeekStart }
        set {
            storedWeekStart = newValue
            defaults.set(newValue, for: AppSettings.weekStart)
        }
    }

    private var storedWeekStart: WeekStart
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private let budgetStore: BudgetStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let exporter: LedgerExporter
    @ObservationIgnored private let csvLanguage: LedgerCSVWriter.Language
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// - Parameters:
    ///   - budgetStore: 予算の読み書き。渡さなければ `context` を使う。
    ///   - purchases: プレミアムの購入と状態。アプリはホームから同じもの（`SaifuLogApp` の 1 つ）を渡す。渡さなければ
    ///     購入の無い状態（テストとプレビュー用）。
    ///   - defaults: 設定の置き場所。アプリは `UserDefaults.standard`（`AppSettings` の決まり）、テストは使い捨ての領域。
    ///   - exporter: 記録をファイルに書き出す。渡さなければ `context` と同じ保存先から、アプリの一時ディレクトリへ書き出す。
    ///     テストで書き出し先を使い捨ての場所にし、書き出しがメインスレッドの外で進むかを確かめる。
    ///   - csvLanguage: CSV の見出しと値の言語。アプリの表示の言語に合わせる。
    ///   - systemFirstWeekday: 端末の設定の週の始まり。テストで決める。
    ///   - bundleInfo: 版とビルド番号を読む Info.plist の中身。テストで決める。
    ///   - now: 書き出す期間の基準とファイル名の日付。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる（予算を決める画面に渡す）。
    init(
        context: ModelContext,
        budgetStore: BudgetStore? = nil,
        purchases: PurchaseManager? = nil,
        defaults: UserDefaults = .standard,
        exporter: LedgerExporter? = nil,
        csvLanguage: LedgerCSVWriter.Language = LedgerCSVWriter.Language(localization: Bundle.main.preferredLocalizations.first),
        systemFirstWeekday: Int = Calendar.autoupdatingCurrent.firstWeekday,
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.budgetStore = budgetStore ?? BudgetStore(context: context)
        self.purchases = purchases ?? PurchaseManager(loadPurchases: { [] })
        self.defaults = defaults
        self.exporter = exporter ?? LedgerExporter(container: context.container)
        self.csvLanguage = csvLanguage
        self.systemFirstWeekday = systemFirstWeekday
        self.versionText = Self.versionText(info: bundleInfo)
        self.now = now
        self.announce = announce
        self.storedWeekStart = defaults.value(for: AppSettings.weekStart)
        // 前に書き出して残ったファイル（共有の途中でアプリが終了したときなど）を片づける。設定を開いた時点では、
        // 共有のシートは出ていない（共有のシートは設定の画面の上にしか出ない）ので、消しても共有を妨げない。
        self.exporter.removeAll()
        reloadBudget()
    }

    // MARK: - 週の始まり

    /// 週の始まりを当てはめた暦（画面の根元が当てはめるものと同じ）。`ReportPeriod` の今週・先週の区切りに使われる。
    func calendar(applyingTo systemCalendar: Calendar) -> Calendar {
        weekStart.applied(to: systemCalendar)
    }

    // MARK: - 予算

    /// 「予算を決める」のシートを出す（ホームの帯のボタンと同じ画面）。カテゴリ別の予算はプレミアムと体験中だけ出す。
    func presentBudgetSetup() {
        budgetSetup = BudgetSetupModel(
            store: budgetStore, showsCategoryBudgets: purchases.status.unlocksPremium, announce: announce
        )
    }

    // MARK: - プレミアム

    /// 「プレミアム」のシート（⑨）を出す。
    func presentPremium() {
        premiumSheet = PremiumSheetModel(purchases: purchases, announce: announce)
    }

    /// 購入の復元。終わるのを待つ Task を返す（テストで使う）。購入や復元の途中は受け付けない（nil を返す）。
    @discardableResult
    func restorePurchases() -> Task<Void, Never>? {
        guard !purchases.isPurchasing, !purchases.isRestoring else { return nil }
        return Task {
            let outcome = await purchases.restore()
            purchaseAlert = PurchaseAlert(outcome)
        }
    }

    /// いまの予算を読み直す（予算を決める画面を閉じたとき）。
    func reloadBudget() {
        totalBudget = (try? budgetStore.plan())?.total
    }

    // MARK: - 書き出し

    /// 選んだ期間の記録を CSV ファイルにし、共有のシートに渡す（`sharedFile`）。書き終えるのを待つ Task を返す（テストで使う）。
    ///
    /// 利用者がボタンを押したときだけ書き出す。どこへ渡すかは利用者が共有のシートで選び、アプリからは送らない。
    /// 書き出しの途中や、共有のシートを出している間は受け付けない（nil を返す）。
    /// - Parameter calendar: 期間を区切る暦（画面の暦。ホームの今月と同じ月で区切るため）。
    @discardableResult
    func export(calendar: Calendar) -> Task<Void, Never>? {
        guard !isExporting, sharedFile == nil else { return nil }
        isExporting = true
        let exporter = exporter
        let period = exportPeriod
        let exportedAt = now()
        let language = csvLanguage
        let task = Task {
            defer { isExporting = false }
            do {
                let outcome = try await exporter.export(period: period, now: exportedAt, calendar: calendar, language: language)
                switch outcome {
                case .file(let url, let count):
                    // 書き出している間に画面を離れていたら、共有のシートは出せないので消す。
                    guard !Task.isCancelled else {
                        exporter.remove(url)
                        return
                    }
                    sharedFile = ExportedFile(url: url, recordCount: count)
                case .empty:
                    if !Task.isCancelled { exportAlert = .empty }
                }
            } catch is CancellationError {
                // 画面を離れて取り消した。知らせることは無い。
            } catch {
                if !Task.isCancelled { exportAlert = .failed }
            }
        }
        exportTask = task
        return task
    }

    /// 共有のシートを閉じたら（渡し終えたか、やめたか）、書き出したファイルを消す。
    ///
    /// 渡した先はファイルを写し取っているので、ここで消しても渡したものは消えない。残すと、家計の記録の写しが
    /// アプリの一時ディレクトリに残り続けるため。
    /// - Parameter sheetWasShown: 共有のシートを出せたか。出せなかったとき（ほかの画面が出たり閉じたりしている途中
    ///   など）は「書き出せませんでした」と知らせる。ボタンを押して進行中の印が出た後、何も起きずに終わると、
    ///   何があったのか分からないため（ほかの失敗と同じアラートにする）。
    func finishSharing(sheetWasShown: Bool = true) {
        guard let sharedFile else { return }
        exporter.remove(sharedFile.url)
        self.sharedFile = nil
        if !sheetWasShown { exportAlert = .failed }
    }

    /// 設定の画面を離れたら、途中の書き出しをやめる（書き終えていたファイルは、書き出しの Task が消す）。
    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
    }

    // MARK: - このアプリについて

    /// 版とビルド番号（「0.1.0 (12)」）。読めない値は「-」にする。
    static func versionText(info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "-"
        let build = info["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    /// 曜日の名前（1 = 日曜）。アプリの表示の言語（日本語か英語）で書く。
    static func weekdayName(_ weekday: Int, localization: String? = Bundle.main.preferredLocalizations.first) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: localization ?? "ja")
        let symbols = calendar.standaloneWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }

    // MARK: - 型

    /// 共有に出す、書き出したファイル。
    struct ExportedFile: Identifiable, Equatable {
        let url: URL
        let recordCount: Int
        var id: URL { url }
    }

    /// 書き出しのアラート。
    enum ExportAlert: Identifiable, Equatable {
        /// 選んだ期間に記録が無い（見出しだけのファイルを渡しても使えないので、渡さずに知らせる）。
        case empty
        /// 読み込みかファイルの作成に失敗した。共有のシートを出せなかった。
        case failed

        var id: Self { self }
    }
}

/// ホームから横に進む先（`navigationDestination(item:)`）として渡すため、同じインスタンスかどうかで比べる。
extension SettingsModel: Hashable {
    nonisolated static func == (lhs: SettingsModel, rhs: SettingsModel) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
