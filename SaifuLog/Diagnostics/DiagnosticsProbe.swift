#if DEBUG || INTERNAL_DIAGNOSTICS
import Foundation
import SwiftData
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif
import SaifuLogCore
import Speech

/// 診断画面の値を、端末・OS・保存先から読む。
///
/// プライバシーマニフェストで理由の申告が要る API（ファイルの日時・起動からの時間・空き容量など）は使わない。
/// 社内テスト用のビルドも、アップロードの時点で App Store と同じ検査を受けるため。
enum DiagnosticsProbe {
    /// 保存先（SwiftData の SQLite）が作るファイル。本体と、書き込みの途中の記録（-wal）と共有メモリ（-shm）。
    /// 本体と -wal は記録の中身を含むので、どちらも NSFileProtectionComplete になっているはず（開いた直後に当てる。
    /// `StoreFileProtection`）。-shm は記録の中身を含まない索引で、わざと当てない（SwiftData が付けた保護のまま）。
    static let storeFileSuffixes = ["", "-wal", "-shm"]

    static func appInfo(bundle: Bundle = .main) -> DiagnosticsReport.AppInfo {
        let info = bundle.infoDictionary ?? [:]
        return DiagnosticsReport.AppInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown",
            kind: buildKind
        )
    }

    /// 社内テスト用（TestFlight の社内テスト専用）か、DEBUG か。
    static var buildKind: String {
        #if INTERNAL_DIAGNOSTICS && DEBUG
        "internal+debug"
        #elseif INTERNAL_DIAGNOSTICS
        "internal"
        #else
        "debug"
        #endif
    }

    @MainActor
    static func deviceInfo() -> DiagnosticsReport.DeviceInfo {
        let device = UIDevice.current
        return DiagnosticsReport.DeviceInfo(
            os: "\(device.systemName) \(device.systemVersion)",
            osDetail: ProcessInfo.processInfo.operatingSystemVersionString,
            model: modelIdentifier()
        )
    }

    /// 機種の ID（例: iPhone17,1）。`UIDevice.model` は「iPhone」としか返さないので、カーネルの機種名を読む。
    static func modelIdentifier() -> String {
        #if targetEnvironment(simulator)
        // シミュレータのカーネルは Mac の CPU（arm64）を返すので、シミュレートしている機種を出す。
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        #endif
        var system = utsname()
        guard uname(&system) == 0 else { return "unknown" }
        return withUnsafeBytes(of: system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// 端末内 AI の使える・使えないと、その理由。アプリが AI を使うかどうかの判定
    /// （`FoundationModelsEntryParser.isAvailable`）と同じものを、理由まで分けて出す。
    static func foundationModels() -> DiagnosticsReport.FoundationModelsStatus {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        let availability: String
        switch model.availability {
        case .available:
            availability = "available"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: availability = "unavailable(deviceNotEligible)"
            case .appleIntelligenceNotEnabled: availability = "unavailable(appleIntelligenceNotEnabled)"
            case .modelNotReady: availability = "unavailable(modelNotReady)"
            // 新しい OS で理由が足されても、名前が分かるように出す。
            @unknown default: availability = "unavailable(\(String(describing: reason)))"
            }
        }
        var supportsVision: Bool?
        // 画像の入力（レシートの読み取りで使う。`FoundationModelsReceiptItemRefiner.supportsImageInput`）は、iOS 27 からしか調べられない。
        if #available(iOS 27, *) {
            supportsVision = model.capabilities.contains(.vision)
        }
        return DiagnosticsReport.FoundationModelsStatus(
            availability: availability,
            supportsJapanese: model.supportsLocale(Locale(identifier: "ja_JP")),
            supportsVision: supportsVision
        )
        #else
        return DiagnosticsReport.FoundationModelsStatus(
            availability: "unavailable(frameworkMissing)", supportsJapanese: false, supportsVision: nil
        )
        #endif
    }

    // MARK: - 生成の試し

    /// 生成の試しを待つ上限。初めての生成はモデルの読み込みで数秒かかることがあるので、それより十分に長く、画面の前で
    /// 待っていられる長さにする。
    static let generationTimeout: Duration = .seconds(20)

    /// 生成の試しでモデルに渡す文。利用者の記録や入力は渡さない（決まった短い文だけ）。
    static let generationPrompt = "「はい」とだけ答えてください。"

    /// 生成の試しで返させる長さの上限（トークン）。答えの中身は見ないので、短く切り上げて待つ時間を減らす。
    static let generationMaximumTokens = 16

    enum GenerationProbeError: Error {
        /// Foundation Models の無い SDK でビルドした。
        case frameworkMissing
    }

    /// 端末内 AI に、決まった短い文で 1 回だけ生成させる（診断画面の「生成を試す」）。
    ///
    /// アプリの機能と同じく、試すたびに新しいセッションを作る（前の試しの文脈を引きずらず、初めての生成の読み込みも含めて測る）。
    static func generateOnce() async throws {
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        _ = try await session.respond(
            to: generationPrompt, options: GenerationOptions(maximumResponseTokens: generationMaximumTokens)
        )
        #else
        throw GenerationProbeError.frameworkMissing
        #endif
    }

    /// `generate` を 1 回呼び、かかった時間か、エラーか、時間切れかを返す。
    ///
    /// 時間切れのときは取り消しを伝え、生成が終わるのを待たずに返す（モデルが取り消しに応じずに止まっていても、画面を
    /// 「running」のままにしない）。待ち方はアプリの機能が端末内 AI を待つのと同じもの（コアの `withDeadline`）。
    static func tryGeneration(
        timeout: Duration, _ generate: @escaping @Sendable () async throws -> Void
    ) async -> DiagnosticsReport.GenerationProbe {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await withDeadline(timeout, operation: generate)
            return .succeeded(latency: start.duration(to: clock.now))
        } catch is DeadlineExceeded {
            return .timedOut(timeout)
        } catch {
            return .failed(AIErrorSummary(error))
        }
    }

    // MARK: - 音声の書き起こし

    /// 端末内の音声の書き起こし（声の入力）が、日本語で使えるか。声の入力が使っている経路も出す。
    ///
    /// 使えるかを尋ねるだけで、マイクも音声認識の許可も使わない（許可のダイアログは出ない）。
    static func speech() async -> DiagnosticsReport.SpeechStatus {
        let japanese = await SpeechTranscriber.supportedLocale(equivalentTo: SpeechModules.japanese)
        let installed = await SpeechTranscriber.installedLocales
        // 経路の選び方は声の入力と同じもの（`SpeechModules.availability`）を使う。
        let voice = await SpeechModules.availability()
        return DiagnosticsReport.SpeechStatus(
            isAvailable: SpeechTranscriber.isAvailable,
            japaneseLocale: japanese?.identifier,
            isJapaneseInstalled: installed.contains { $0.language.languageCode == .japanese },
            route: voice.route.rawValue,
            model: voice.model.map(modelName) ?? "none"
        )
    }

    /// モデルの状態の名前（訳さない）。
    static func modelName(_ state: VoiceModelState) -> String {
        switch state {
        case .installed: "installed"
        case .needsReservation: "needsReservation"
        case .needsDownload: "needsDownload"
        case .downloading: "downloading"
        }
    }

    /// 保存先のファイル（本体・-wal・-shm）の保護クラス。
    static func storeFiles(storeURL: URL) -> [DiagnosticsReport.StoreFile] {
        let folder = storeURL.deletingLastPathComponent()
        return storeFileSuffixes.map { suffix in
            let name = storeURL.lastPathComponent + suffix
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            return DiagnosticsReport.StoreFile(name: name, protection: protection(at: url))
        }
    }

    /// ファイルの保護クラス。ファイルが無ければ `.missing`。
    ///
    /// シミュレータはデータ保護を効かせないので、ここで確かめられるのは実機だけ（docs/design.md §5-4）。
    static func protection(at url: URL, fileManager: FileManager = .default) -> DiagnosticsReport.FileProtectionStatus {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else { return .missing }
        do {
            // URL は読んだ値を覚えているので、毎回作り直した URL で読む（前に読んだ古い値を返さないように）。
            let fresh = URL(filePath: url.path(percentEncoded: false), directoryHint: .notDirectory)
            guard let protection = try fresh.resourceValues(forKeys: [.fileProtectionKey]).fileProtection else {
                return .unknown
            }
            return .protected(protectionName(protection))
        } catch {
            let error = error as NSError
            // 確かめてから読むまでの間に消えた（-wal と -shm は SQLite が片づけることがある）。
            if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError {
                return .missing
            }
            return .failed(domain: error.domain, code: error.code)
        }
    }

    /// 保護クラスの名前。URL の値の名前（NSURLFileProtection…）ではなく、エンタイトルメント
    /// （project.yml の default-data-protection）と同じ名前（NSFileProtection…）で出す。見比べて一致を確かめやすいように。
    static func protectionName(_ protection: URLFileProtection) -> String {
        switch protection {
        case .complete: FileProtectionType.complete.rawValue
        case .completeUnlessOpen: FileProtectionType.completeUnlessOpen.rawValue
        case .completeUntilFirstUserAuthentication: FileProtectionType.completeUntilFirstUserAuthentication.rawValue
        case .none: FileProtectionType.none.rawValue
        // 新しい OS で足されたクラスは、そのままの名前で出す。
        default: protection.rawValue
        }
    }

    /// いま開いている保存先の iCloud の扱い（none / private(コンテナ)）。設定の値ではなく、開いた保存先の設定から読む
    /// （iCloud と同期する保存先を開けずに端末の中だけへ戻したときに、設定と見比べられるように）。
    @MainActor
    static func cloudKitDatabase(container: ModelContainer) -> String {
        cloudKitDatabaseName(configurations: Array(container.configurations))
    }

    static func cloudKitDatabaseName(configurations: [ModelConfiguration]) -> String {
        let values = configurations.map { configuration in
            configuration.cloudKitContainerIdentifier.map { "private(\($0))" } ?? "none"
        }
        return values.isEmpty ? "unknown" : values.joined(separator: ", ")
    }

    /// 記録と予算の件数。中身は読まない（数えるだけ）。
    @MainActor
    static func counts(context: ModelContext) -> DiagnosticsReport.RecordCounts {
        DiagnosticsReport.RecordCounts(
            entries: try? context.fetchCount(FetchDescriptor<Entry>()),
            budgetRows: try? context.fetchCount(FetchDescriptor<Budget>())
        )
    }
}
#endif
