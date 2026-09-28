#if DEBUG || INTERNAL_DIAGNOSTICS
import Foundation
import Observation
import SwiftData
import UIKit

/// 診断画面の状態と操作（値を読む・まとめてコピーする）。
///
/// 端末に依存する部分（ロックの状態・音声の書き起こしの問い合わせ・クリップボード）は外から渡せるようにし、
/// SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class DiagnosticsModel {
    /// 読んだ値。最初の読み込みを始めるまでは nil。音声の書き起こしの行は、問い合わせが返るまで checking。
    private(set) var report: DiagnosticsReport?
    /// まとめてコピーした回数（「コピーしました」の表示と、手ざわりの合図に使う）。
    private(set) var copyCount = 0
    /// 読み込みを始めた回数。前の読み込みの音声の答えが、後から始めた読み込みより遅れて返ったときに、
    /// 新しい値を古い値で上書きしないため。
    @ObservationIgnored private var loadGeneration = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let storeURL: URL
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let speech: @Sendable () async -> DiagnosticsReport.SpeechStatus
    @ObservationIgnored private let copy: @MainActor (String) -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// - Parameters:
    ///   - context: 件数を数える保存先。
    ///   - storeURL: 保護クラスを見る保存先のファイル。テストで一時フォルダを渡す。
    ///   - isProtectedDataAvailable: 保護されたデータを読めるか（ロック中でないか）。
    ///   - speech: 音声の書き起こしが使えるかの問い合わせ。テストでは OS に問い合わせない値に差し替える。
    ///   - copy: まとめてコピーする先（クリップボード）。テストで文を集める。
    ///   - announce: VoiceOver に読み上げさせる。
    init(
        context: ModelContext,
        storeURL: URL = ModelContainerFactory.storeURL,
        isProtectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        speech: @escaping @Sendable () async -> DiagnosticsReport.SpeechStatus = { await DiagnosticsProbe.speech() },
        copy: @escaping @MainActor (String) -> Void = { UIPasteboard.general.string = $0 },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.context = context
        self.storeURL = storeURL
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.speech = speech
        self.copy = copy
        self.announce = announce
    }

    /// 値を読み直す。画面を開いたときと、再読み込みのボタンで呼ぶ（ロックの解除や設定の変更の後に見直せるように）。
    ///
    /// 音声の書き起こしの問い合わせ（端末の資産の問い合わせ）は、時間がかかったり返らなかったりしうる。実機で見たいもの
    /// （保存先の保護クラス・端末内 AI の可否）はそれに関係なく読めるので、音声の答えを待たずに先に出し、返ったら埋める。
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        report = makeReport(speech: nil)
        let speech = await speech()
        // 待つ間に読み直しが始まっていれば、そちらに任せる（そちらの方が新しい値を読む）。
        guard generation == loadGeneration else { return }
        report = makeReport(speech: speech)
    }

    private func makeReport(speech: DiagnosticsReport.SpeechStatus?) -> DiagnosticsReport {
        DiagnosticsReport(
            app: DiagnosticsProbe.appInfo(),
            device: DiagnosticsProbe.deviceInfo(),
            foundationModels: DiagnosticsProbe.foundationModels(),
            speech: speech,
            storeFiles: DiagnosticsProbe.storeFiles(storeURL: storeURL),
            isProtectedDataAvailable: isProtectedDataAvailable(),
            counts: DiagnosticsProbe.counts(context: context)
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
