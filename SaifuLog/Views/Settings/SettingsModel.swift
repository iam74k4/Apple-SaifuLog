import Foundation
import Observation
import SaifuLogCore
import SwiftData

/// 「設定」（⑧）の状態と操作。月の予算を開く、カテゴリ、くり返しの記録、iCloud で同期、記録の CSV 書き出し、このアプリについて。
///
/// 画面（`SettingsView`）から切り離し、保存先・時計・書き出し先を差し替えて SaifuLogTests で確かめられるようにしている。
/// CSV の中身はコア（`LedgerCSVWriter`）、ファイルの作成は `LedgerExporter` が受け持つ。
///
/// iCloud 同期は、オンにする前に iCloud のアカウントを確かめ（使えなければ案内だけ）、説明を読んでもらってから
/// `StoreHost.setICloudSyncEnabled(_:)` に頼む（保存先を開き直すので、この画面ごと作り直される）。オフにするときも説明を出す。
@MainActor
@Observable
final class SettingsModel {
    /// プライバシーポリシー（リポジトリの main の PRIVACY.md。Safari で開く）。
    static let privacyPolicyURL = URL(string: "https://github.com/iam74k4/Apple-SaifuLog/blob/main/PRIVACY.md")!
    /// ヘルプ・お問い合わせ（リポジトリの main の docs/support.md。App Store Connect のサポート URL と同じページ。Safari で開く）。
    static let supportURL = URL(string: "https://github.com/iam74k4/Apple-SaifuLog/blob/main/docs/support.md")!

    /// 書き出しの途中（ボタンを押せなくし、進行中の印を出す）。
    private(set) var isExporting = false
    /// 共有に出しているファイル。共有のシートを閉じると `finishSharing()` で消して nil に戻す。
    private(set) var sharedFile: ExportedFile?
    /// 書き出せなかった・書き出す記録が無かった（アラートを出す）。
    var exportAlert: ExportAlert?
    /// 「予算を決める」のシートの状態と操作。シートを出していなければ nil（シートを閉じると画面が nil に戻す）。
    var budgetSetup: BudgetSetupModel?
    /// いまの月の予算。決めていないか、読めなければ nil。
    private(set) var totalBudget: Int?
    /// このアプリについての版とビルド番号（「0.1.0 (12)」）。
    let versionText: String

    // MARK: iCloud 同期の状態

    /// iCloud 同期の節を出すか（保存先を開いたもの（`StoreHost`）を渡されたときだけ。テストとプレビューでは出さない）。
    var showsICloudSync: Bool { storeHost != nil }
    /// いま iCloud と同期する保存先を開いているか。切り替えると保存先を開き直してこの画面ごと作り直すので、開いたときの
    /// 値のまま変わらない。トグルはこれを出し、押されたら確かめと説明に進む（押しただけでは変わらない）。
    let isICloudSyncEnabled: Bool
    /// iCloud のアカウントを確かめている途中（トグルを押せなくし、進行中の印を出す）。
    private(set) var isCheckingICloudAccount = false
    /// 同期がオンのときに確かめた iCloud のアカウントの状態（使えなければ、同期していないことを案内する）。まだなら nil。
    private(set) var iCloudAccountStatus: ICloudAccountStatus?
    /// オンにする・オフにする前の説明（確かめのダイアログ）。出していなければ nil。
    var iCloudSyncConfirmation: ICloudSyncChange?
    /// オンにしようとしたら iCloud を使えなかった（案内のアラートを出す）。
    var iCloudAccountAlert: ICloudAccountStatus?
    /// 切り替えようとしたら設定を書けなかった（切り替えていない。アラートを出す）。
    var showsICloudSyncSaveFailure = false

    /// 「覚えたカテゴリ」（修正の記憶の一覧）の状態と操作。「カテゴリ」の画面から進み、行には覚えた言葉の数を出す。
    let learnedCategories: LearnedCategoriesModel

    /// 「カテゴリ」（組み込みと作ったカテゴリの一覧。作る・直す・並べ替える・削除する）の状態と操作。
    let categoryList: CategoryListModel

    /// 「くり返しの記録」（毎月同じ記録の一覧。足す・直す・やめる）の状態と操作。
    let recurringList: RecurringListModel

    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private let budgetStore: BudgetStore
    @ObservationIgnored private let exporter: LedgerExporter
    @ObservationIgnored private let csvLanguage: LedgerCSVWriter.Language
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let storeHost: StoreHost?
    @ObservationIgnored private let accountStatus: @MainActor () async -> ICloudAccountStatus
    @ObservationIgnored private var accountCheckTask: Task<Void, Never>?

    /// - Parameters:
    ///   - budgetStore: 予算の読み書き。渡さなければ `context` を使う。
    ///   - categories: いまのカテゴリの一覧。アプリはホームと同じもの（作ったカテゴリをホームにもすぐ出すため）を渡す。
    ///     渡さなければ `context` から読む。
    ///   - storeHost: 保存先を開いたもの。「iCloud で同期」の切り替えを頼む。渡さなければ iCloud の節を出さない。
    ///   - accountStatus: iCloud のアカウントの状態の問い合わせ。テストでは CloudKit に問い合わせない値に差し替える
    ///     （iCloud の entitlement の無いテストのプロセスで `CKContainer` を作ると落ちるため）。
    ///   - exporter: 記録をファイルに書き出す。渡さなければ `context` と同じ保存先から、アプリの一時ディレクトリへ書き出す。
    ///     テストで書き出し先を使い捨ての場所にし、書き出しがメインスレッドの外で進むかを確かめる。
    ///   - csvLanguage: CSV の見出しと値の言語。アプリの表示の言語に合わせる。
    ///   - bundleInfo: 版とビルド番号を読む Info.plist の中身。テストで決める。
    ///   - now: 書き出す期間の基準とファイル名の日付。テストで固定の日時にする。
    ///   - announce: VoiceOver に読み上げさせる（予算を決める画面に渡す）。
    ///   - recurringDidChange: くり返しの記録を足した・直した・やめたあとに呼ぶ（ホームが、記録する日を過ぎた分をすぐ記録する）。
    init(
        context: ModelContext,
        budgetStore: BudgetStore? = nil,
        categories: CategoryCatalogModel? = nil,
        storeHost: StoreHost? = nil,
        accountStatus: @escaping @MainActor () async -> ICloudAccountStatus = { await ICloudAccountStatus.current() },
        exporter: LedgerExporter? = nil,
        csvLanguage: LedgerCSVWriter.Language = LedgerCSVWriter.Language(localization: Bundle.main.preferredLocalizations.first),
        bundleInfo: [String: Any] = Bundle.main.infoDictionary ?? [:],
        now: @escaping () -> Date = { .now },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        recurringDidChange: @escaping @MainActor () -> Void = {}
    ) {
        self.budgetStore = budgetStore ?? BudgetStore(context: context)
        self.storeHost = storeHost
        self.learnedCategories = LearnedCategoriesModel(store: LearnedCategoryStore(context: context, now: now), announce: announce)
        let categoryStore = CustomCategoryStore(context: context, now: now)
        self.categoryList = CategoryListModel(
            store: categoryStore, categories: categories ?? CategoryCatalogModel(store: categoryStore), announce: announce
        )
        self.recurringList = RecurringListModel(
            store: RecurringEntryStore(context: context, now: now), now: now, announce: announce, didChange: recurringDidChange
        )
        self.accountStatus = accountStatus
        self.isICloudSyncEnabled = storeHost?.cloudKitDatabase.isSyncEnabled ?? false
        self.exporter = exporter ?? LedgerExporter(container: context.container)
        self.csvLanguage = csvLanguage
        self.versionText = Self.versionText(info: bundleInfo)
        self.now = now
        self.announce = announce
        // 前に書き出して残ったファイル（共有の途中でアプリが終了したときなど）を片づける。設定を開いた時点では、
        // 共有のシートは出ていない（共有のシートは設定の画面の上にしか出ない）ので、消しても共有を妨げない。
        self.exporter.removeAll()
        reloadBudget()
    }

    // MARK: - iCloud 同期

    /// トグルを押した。オンにするなら iCloud のアカウントを確かめ、使えれば説明を出し、使えなければ案内を出す。
    /// オフにするなら説明を出す。確かめ終えるのを待つ Task を返す（テストで使う）。確かめている途中や、いまと同じ値なら
    /// 何もしない（nil を返す）。
    @discardableResult
    func requestICloudSync(_ enabled: Bool) -> Task<Void, Never>? {
        guard storeHost != nil, enabled != isICloudSyncEnabled, !isCheckingICloudAccount else { return nil }
        guard enabled else {
            iCloudSyncConfirmation = .disable
            return nil
        }
        isCheckingICloudAccount = true
        let task = Task {
            let status = await accountStatus()
            // やめた確かめ（画面を離れた）は、後から始めた確かめの印を消さないよう、何も触らない。
            guard !Task.isCancelled else { return }
            isCheckingICloudAccount = false
            if status.isAvailable {
                iCloudSyncConfirmation = .enable
            } else {
                iCloudAccountAlert = status
            }
        }
        accountCheckTask = task
        return task
    }

    /// 説明を読んで「オンにする」「オフにする」を押した。保存先を開き直す（この画面は畳まれ、開き直したら設定に戻る）。
    ///
    /// 何に切り替えるかは、ダイアログに出していた値を受け取る（ボタンを押すとダイアログを閉じる側が先に
    /// `iCloudSyncConfirmation` を nil にすることがあるため）。
    func confirmICloudSync(_ change: ICloudSyncChange) {
        iCloudSyncConfirmation = nil
        // 設定を書けなければ切り替わらない（トグルは元のまま）。黙っていると押しても何も起きないように見えるので知らせる。
        if storeHost?.setICloudSyncEnabled(change == .enable) == false {
            showsICloudSyncSaveFailure = true
        }
    }

    /// 同期がオンのとき、iCloud のアカウントがいまも使えるかを確かめる（設定の画面を開いたとき）。
    ///
    /// サインアウトなどで使えなくなっても保存先は開けて、同期だけが止まる。気づかないまま別の端末とそろっていると
    /// 思わないよう、使えないことを節の中に出す。オフのときは問い合わせない。
    func refreshICloudAccountStatus() async {
        guard isICloudSyncEnabled else { return }
        iCloudAccountStatus = await accountStatus()
    }

    /// 設定の画面を閉じたら、途中のアカウントの確かめをやめる（閉じた後で説明やアラートを出さない）。
    func cancelICloudAccountCheck() {
        accountCheckTask?.cancel()
        accountCheckTask = nil
        isCheckingICloudAccount = false
    }

    // MARK: - 予算

    /// 「予算を決める」のシートを出す（ホームの帯のボタンと同じ画面）。
    func presentBudgetSetup() {
        budgetSetup = BudgetSetupModel(store: budgetStore, announce: announce)
    }

    /// いまの予算を読み直す（予算を決める画面を閉じたとき）。
    func reloadBudget() {
        totalBudget = (try? budgetStore.plan())?.total
    }

    // MARK: - 書き出し

    /// 選んだ期間の記録を CSV ファイルにし、共有のシートに渡す（`sharedFile`）。書き終えるのを待つ Task を返す（テストで使う）。
    ///
    /// 利用者が期間を選んだときだけ書き出す。どこへ渡すかは利用者が共有のシートで選び、アプリからは送らない。
    /// 書き出しの途中や、共有のシートを出している間は受け付けない（nil を返す）。
    /// - Parameters:
    ///   - period: 書き出す期間（書き出しのメニューで選んだもの）。
    ///   - calendar: 期間を区切る暦（画面の暦。ホームの今月と同じ月で区切るため）。
    @discardableResult
    func export(period: LedgerExportPeriod = .thisMonth, calendar: Calendar) -> Task<Void, Never>? {
        guard !isExporting, sharedFile == nil else { return nil }
        isExporting = true
        let exporter = exporter
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

    /// 設定の画面を閉じた（ホームが `settings` を nil に戻した・作り直した）。途中の書き出しとアカウントの確かめをやめる。
    ///
    /// 画面の onDisappear でやめると、設定から「カテゴリ」などへ進んだだけでも書き出しが止まり、戻ると何も起きていない
    /// ように見えるため、閉じたときだけにする。
    func close() {
        cancelExport()
        cancelICloudAccountCheck()
    }

    /// 途中の書き出しをやめる（書き終えていたファイルは、書き出しの Task が消す）。
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

    // MARK: - 型

    /// iCloud 同期をどちらへ切り替えるか（確かめのダイアログの中身）。
    enum ICloudSyncChange: Identifiable, Equatable {
        case enable
        case disable

        var id: Self { self }
    }

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
