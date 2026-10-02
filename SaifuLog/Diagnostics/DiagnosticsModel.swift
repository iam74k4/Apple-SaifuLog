#if DEBUG || INTERNAL_DIAGNOSTICS
import Foundation
import Observation
import SwiftData
import UIKit

/// 診断画面の状態と操作（値を読む・端末内 AI の生成を試す・まとめてコピーする）。
///
/// 端末に依存する部分（ロックの状態・音声の書き起こしの問い合わせ・端末内 AI の生成・クリップボード）は外から渡せるようにし、
/// SaifuLogTests で確かめられるようにしている（テストでは本物のモデルを呼ばない）。
@MainActor
@Observable
final class DiagnosticsModel {
    /// 読んだ値。最初の読み込みを始めるまでは nil。音声の書き起こしと iCloud のアカウントの行は、問い合わせが返るまで checking。
    private(set) var report: DiagnosticsReport?
    /// まとめてコピーした回数（「コピーしました」の表示と、手ざわりの合図に使う）。
    private(set) var copyCount = 0
    /// 生成の試し（「生成を試す」）の状態と結果。読み直しても消さない（試した結果をコピーする文に残すため）。
    private(set) var generationProbe: DiagnosticsReport.GenerationProbe = .notRun
    /// 読み込みを始めた回数。前の読み込みの音声の答えが、後から始めた読み込みより遅れて返ったときに、
    /// 新しい値を古い値で上書きしないため。
    @ObservationIgnored private var loadGeneration = 0
    /// いちばん新しい読み込みの、音声の書き起こしと iCloud のアカウントの答え（返るまでは nil）。生成の試しが終わって値を
    /// 作り直すときに、問い合わせ直さずに使う。
    @ObservationIgnored private var speechAnswer: DiagnosticsReport.SpeechStatus?
    @ObservationIgnored private var accountAnswer: ICloudAccountStatus?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let storeURL: URL
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let speech: @Sendable () async -> DiagnosticsReport.SpeechStatus
    @ObservationIgnored private let iCloudAccount: @Sendable () async -> ICloudAccountStatus
    @ObservationIgnored private let settings: LaunchSettingsStore
    @ObservationIgnored private let copy: @MainActor (String) -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let household: HouseholdHost?
    @ObservationIgnored private let aiFallbackLog: AIFallbackLog
    @ObservationIgnored private let generate: @Sendable () async throws -> Void
    @ObservationIgnored private let generationTimeout: Duration

    /// - Parameters:
    ///   - context: 件数を数える保存先。
    ///   - storeURL: 保護クラスを見る保存先のファイル。テストで一時フォルダを渡す。
    ///   - isProtectedDataAvailable: 保護されたデータを読めるか（ロック中でないか）。
    ///   - speech: 音声の書き起こしが使えるかの問い合わせ。テストでは OS に問い合わせない値に差し替える。
    ///   - iCloudAccount: iCloud のアカウントの状態の問い合わせ。テストでは CloudKit に問い合わせない値に差し替える
    ///     （iCloud の entitlement の無いテストのプロセスで `CKContainer` を作ると落ちるため）。
    ///   - settings: 設定の「iCloud で同期」を読む置き場所（`LaunchSettingsStore`）。
    ///   - copy: まとめてコピーする先（クリップボード）。テストで文を集める。
    ///   - announce: VoiceOver に読み上げさせる。
    ///   - household: 家計の共有。渡すと（有効なときだけ）家計の行を出す。
    ///   - aiFallbackLog: 起動してから端末内 AI の結果を使わなかった回数と最後の失敗の記録。テストで別の記録を渡す。
    ///   - generate: 生成の試しで、端末内 AI に 1 回生成させる。テストでは本物のモデルを呼ばない代わりに差し替える。
    ///   - generationTimeout: 生成の試しを待つ上限。
    init(
        context: ModelContext,
        storeURL: URL = ModelContainerFactory.storeURL,
        isProtectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        speech: @escaping @Sendable () async -> DiagnosticsReport.SpeechStatus = { await DiagnosticsProbe.speech() },
        iCloudAccount: @escaping @Sendable () async -> ICloudAccountStatus = { await ICloudAccountStatus.current() },
        settings: LaunchSettingsStore = LaunchSettingsStore(),
        copy: @escaping @MainActor (String) -> Void = { UIPasteboard.general.string = $0 },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        household: HouseholdHost? = nil,
        aiFallbackLog: AIFallbackLog = .shared,
        generate: @escaping @Sendable () async throws -> Void = { try await DiagnosticsProbe.generateOnce() },
        generationTimeout: Duration = DiagnosticsProbe.generationTimeout
    ) {
        self.household = household
        self.aiFallbackLog = aiFallbackLog
        self.generate = generate
        self.generationTimeout = generationTimeout
        self.context = context
        self.storeURL = storeURL
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.speech = speech
        self.iCloudAccount = iCloudAccount
        self.settings = settings
        self.copy = copy
        self.announce = announce
    }

    /// 値を読み直す。画面を開いたときと、再読み込みのボタンで呼ぶ（ロックの解除や設定の変更の後に見直せるように）。
    ///
    /// 音声の書き起こしの問い合わせ（端末の資産の問い合わせ）と iCloud のアカウントの問い合わせ（CloudKit）は、時間が
    /// かかったり返らなかったりしうる。実機で見たいもの（保存先の保護クラス・端末内 AI の可否・いまの保存先の iCloud の扱い）は
    /// それに関係なく読めるので、答えを待たずに先に出し、両方が返ったら埋める。
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        speechAnswer = nil
        accountAnswer = nil
        report = makeReport()
        let speech = speech
        let iCloudAccount = iCloudAccount
        async let speechStatus = speech()
        async let accountStatus = iCloudAccount()
        let answers = await (speech: speechStatus, account: accountStatus)
        // 待つ間に読み直しが始まっていれば、そちらに任せる（そちらの方が新しい値を読む）。
        guard generation == loadGeneration else { return }
        speechAnswer = answers.speech
        accountAnswer = answers.account
        report = makeReport()
    }

    /// 端末内 AI に、決まった短い文で 1 回だけ生成させ、かかった時間かエラー（か時間切れ）を出す（「生成を試す」）。
    ///
    /// 使えるか（availability）の行は available なのに、生成が毎回失敗する端末がある（モデルの資産が無いシミュレータなど）。
    /// アプリは失敗を利用者に見せずに辞書へ切り替えるので、実際に生成して確かめる。試している間に押し直しても重ねて試さない。
    func runGenerationProbe() async {
        guard generationProbe != .running else { return }
        generationProbe = .running
        refreshReport()
        generationProbe = await DiagnosticsProbe.tryGeneration(timeout: generationTimeout, generate)
        // 試している間に AI の記録が増えていることもあるので、表ごと作り直す。
        refreshReport()
        announce(String(localized: "生成を試しました"))
    }

    /// 読み込み済みの表を、いまの値で作り直す。まだ読み込んでいなければ何もしない（読み込みが作る）。
    private func refreshReport() {
        guard report != nil else { return }
        report = makeReport()
    }

    private func makeReport() -> DiagnosticsReport {
        DiagnosticsReport(
            app: DiagnosticsProbe.appInfo(),
            device: DiagnosticsProbe.deviceInfo(),
            foundationModels: DiagnosticsProbe.foundationModels(),
            speech: speechAnswer,
            storeFiles: DiagnosticsProbe.storeFiles(storeURL: storeURL),
            isProtectedDataAvailable: isProtectedDataAvailable(),
            counts: DiagnosticsProbe.counts(context: context),
            iCloud: DiagnosticsReport.ICloudStatus(
                account: accountAnswer?.diagnosticName,
                database: DiagnosticsProbe.cloudKitDatabase(container: context.container),
                // まだ書いていなければオフ（UserDefaults から移すのは、保存先を開くときとロックの設定を読むとき）。
                isSyncSettingOn: settings.load(migrating: false)?.iCloudSyncEnabled ?? false
            ),
            household: householdStatus(),
            aiFallbacks: aiFallbackLog.snapshot,
            generationProbe: generationProbe
        )
    }

    /// 家計の共有の状態。家計の共有が無効なら nil（行を出さない）。
    private func householdStatus() -> DiagnosticsReport.HouseholdStatus? {
        guard let household, household.isEnabled else { return nil }
        let current = household.currentHousehold
        return DiagnosticsReport.HouseholdStatus(
            isStoreOpen: household.store != nil,
            role: current?.role.rawValue ?? "none",
            entries: household.store.flatMap { try? $0.context.fetchCount(FetchDescriptor<HouseholdEntry>()) },
            hasMemberName: !(current?.memberName.isEmpty ?? true),
            storeFiles: DiagnosticsProbe.storeFiles(storeURL: ModelContainerFactory.householdStoreURL)
        )
    }

    /// 読んだ値をまとめてクリップボードへ写す。まだ読んでいなければ何もしない（音声の問い合わせが返る前なら、その行は checking のまま写す）。
    func copyReport() {
        guard let report else { return }
        copy(report.text)
        copyCount += 1
        announce(String(localized: "コピーしました"))
    }
}
#endif
