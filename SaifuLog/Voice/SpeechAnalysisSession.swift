@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import SaifuLogCore
import Speech

/// 日本語の書き起こしのモジュール（SpeechTranscriber / DictationTranscriber）の選び方と作り方。
enum SpeechModules {
    /// 書き起こす言語。入力の解析が日本語の文を前提にしているので、端末の言語にかかわらず日本語にする（docs/design.md §10）。
    static let japanese = Locale(identifier: "ja_JP")

    /// 日本語で使える経路と、モデルの状態。
    ///
    /// 経路は `supportedLocale(equivalentTo:)` で日本語に当たる言語があるかと、`AssetInventory.status` が unsupported でないかで決める。
    /// 使えるかを尋ねるだけで、マイクの許可も使わない（許可のダイアログは出ない）。
    static func availability() async -> VoiceAvailability {
        var speechTranscriber: VoiceModelState?
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: japanese) {
            speechTranscriber = modelState(
                await AssetInventory.status(forModules: [makeSpeechTranscriber(locale: locale)]),
                isOnDevice: await SpeechTranscriber.installedLocales.contains { sameLocale($0, locale) }
            )
        }
        var dictation: VoiceModelState?
        if speechTranscriber == nil, let locale = await DictationTranscriber.supportedLocale(equivalentTo: japanese) {
            dictation = modelState(
                await AssetInventory.status(forModules: [makeDictationTranscriber(locale: locale)]),
                isOnDevice: await DictationTranscriber.installedLocales.contains { sameLocale($0, locale) }
            )
        }
        return VoiceRoute.choose(speechTranscriber: speechTranscriber, dictation: dictation)
    }

    /// - Parameter isOnDevice: 端末に、その言語のモデルが入っているか（`installedLocales`。ほかのアプリが入れたものも含む）。
    ///   このアプリが言語の枠（予約）を取るまでは、入っていても status は supported を返す（macOS 26 で確かめた）。そのまま
    ///   「ダウンロードしますか」と聞くと、通信しないのにダウンロードの確認を出すことになるので、枠を取るだけの状態に分ける。
    private static func modelState(_ status: AssetInventory.Status, isOnDevice: Bool) -> VoiceModelState? {
        switch status {
        case .installed: .installed
        case .downloading: .downloading
        case .supported: isOnDevice ? .needsReservation : .needsDownload
        case .unsupported: nil
        @unknown default: nil
        }
    }

    private static func sameLocale(_ lhs: Locale, _ rhs: Locale) -> Bool {
        lhs.identifier(.bcp47) == rhs.identifier(.bcp47)
    }

    /// 経路のモジュールを作る。日本語に対応していなければ nil。モジュールは 1 回の書き起こしごとに作り直す
    /// （1 つのモジュールは 1 つの SpeechAnalyzer にしか付けられないため）。
    static func makeModule(for route: VoiceRoute) async -> (any SpeechModule)? {
        switch route {
        case .speechTranscriber:
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: japanese) else { return nil }
            return makeSpeechTranscriber(locale: locale)
        case .dictationTranscriber:
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: japanese) else { return nil }
            return makeDictationTranscriber(locale: locale)
        case .none:
            return nil
        }
    }

    /// SpeechTranscriber は途中の結果（volatile）を出す設定にする。話している間に入力欄に薄く出すためと、話し終えたか
    /// （文が変わらなくなったか）で自動で止めるため。速さを優先する `fastResults` は付けない（短い文なので、金額の読み違いを
    /// 減らすほうを優先する）。
    private static func makeSpeechTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// DictationTranscriber は 1 分ほどまでの短い音声を、途中の結果と句読点つきで書き起こす設定（`progressiveShortDictation`）にする。
    private static func makeDictationTranscriber(locale: Locale) -> DictationTranscriber {
        DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    }
}

/// 書き起こしの結果（SpeechTranscriber と DictationTranscriber で共通の部分）。
protocol TranscriptionResult: SpeechModuleResult, Sendable {
    var text: AttributedString { get }
}

extension SpeechTranscriber.Result: TranscriptionResult {}
extension DictationTranscriber.Result: TranscriptionResult {}

extension VoiceTranscript.Segment {
    /// 書き起こしの結果から作る。時刻が読めない（無限・不定の）ときは、確定したかだけを残す。
    init(_ result: some TranscriptionResult) {
        let text = String(result.text.characters)
        let start = result.range.start.seconds
        let end = result.range.end.seconds
        let finalizedThrough = result.resultsFinalizationTime.seconds
        if start.isFinite, end.isFinite, finalizedThrough.isFinite {
            self.init(text: text, start: start, end: end, finalizedThrough: finalizedThrough)
        } else if result.isFinal {
            self.init(text: text, start: 0, end: 0, finalizedThrough: 0)
        } else {
            self.init(text: text, start: 0, end: .greatestFiniteMagnitude, finalizedThrough: 0)
        }
    }
}

/// 書き起こしへ音声を渡す口。録音のタップ（音声のスレッド）から、1 つずつ順に呼ぶ（`AudioBufferConverter` と同じ約束）。
final class AnalyzerFeeder: @unchecked Sendable {
    private let converter: AudioBufferConverter
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let events: AsyncStream<VoiceEvent>.Continuation

    init(converter: AudioBufferConverter, input: AsyncStream<AnalyzerInput>.Continuation, events: AsyncStream<VoiceEvent>.Continuation) {
        self.converter = converter
        self.input = input
        self.events = events
    }

    /// 書き起こしが受け取る形式。
    var format: AVAudioFormat { converter.outputFormat }

    /// 音声を 1 つ渡す。音の大きさも知らせる。
    func feed(_ buffer: AVAudioPCMBuffer) {
        events.yield(.level(AudioLevel.normalized(buffer)))
        // 形式を変えられなかった 1 つは飛ばす（止めると、それまでに話した分まで失うため）。
        guard let converted = try? converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    /// これ以上は渡さない。
    func finish() {
        input.finish()
    }
}

/// 書き起こしの 1 回分（SpeechAnalyzer とモジュールと、音声を渡す口と、結果の流れ）。
///
/// マイクの録音（`SpeechAnalyzerTranscriber`）と、読み上げの音声を渡すテストが同じものを使う。
@MainActor
final class SpeechAnalysisSession {
    /// 結果と音の大きさの流れ。確定し終えるか、やめたら終わる。
    let events: AsyncStream<VoiceEvent>
    /// 音声を渡す口。
    let feeder: AnalyzerFeeder

    private let analyzer: SpeechAnalyzer
    private let eventContinuation: AsyncStream<VoiceEvent>.Continuation
    private let resultsTask: Task<Void, Never>

    private init(
        events: AsyncStream<VoiceEvent>, feeder: AnalyzerFeeder, analyzer: SpeechAnalyzer,
        eventContinuation: AsyncStream<VoiceEvent>.Continuation, resultsTask: Task<Void, Never>
    ) {
        self.events = events
        self.feeder = feeder
        self.analyzer = analyzer
        self.eventContinuation = eventContinuation
        self.resultsTask = resultsTask
    }

    /// 書き起こしを始める。音声は `feeder` に渡す。
    ///
    /// - Parameters:
    ///   - route: 使う経路。
    ///   - naturalFormat: 渡す音声のもとの形式（マイクの形式）。近い形式を選んで、変換を少なくする。
    static func start(route: VoiceRoute, naturalFormat: AVAudioFormat?) async throws -> SpeechAnalysisSession {
        guard let module = await SpeechModules.makeModule(for: route) else { throw VoiceTranscriptionError.unavailable }
        // モデルが入っていなければ形式が決まらない（nil）。
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module], considering: naturalFormat) else {
            throw VoiceTranscriptionError.modelNotInstalled
        }
        let (inputs, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let (events, eventContinuation) = AsyncStream.makeStream(of: VoiceEvent.self)
        // 止めた後にもう一度押したとき、モデルを読み込み直さずに済むよう、使い終えても少しの間は残す。
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .lingering))
        let resultsTask = forwardResults(of: module, to: eventContinuation)
        do {
            // 先にモデルを読み込んでおく（最初の結果を早くするため。Apple の説明の prepareToAnalyze）。
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: inputs)
        } catch {
            inputContinuation.finish()
            await analyzer.cancelAndFinishNow()
            resultsTask.cancel()
            eventContinuation.finish()
            throw VoiceTranscriptionError.analyzerFailed
        }
        let feeder = AnalyzerFeeder(
            converter: AudioBufferConverter(outputFormat: format), input: inputContinuation, events: eventContinuation
        )
        return SpeechAnalysisSession(
            events: events, feeder: feeder, analyzer: analyzer, eventContinuation: eventContinuation, resultsTask: resultsTask
        )
    }

    private static func forwardResults(
        of module: any SpeechModule, to continuation: AsyncStream<VoiceEvent>.Continuation
    ) -> Task<Void, Never> {
        switch module {
        case let transcriber as SpeechTranscriber:
            Task.detached(priority: .userInitiated) { await forward(transcriber.results, to: continuation) }
        case let transcriber as DictationTranscriber:
            Task.detached(priority: .userInitiated) { await forward(transcriber.results, to: continuation) }
        default:
            Task { continuation.finish() }
        }
    }

    /// 結果を流れへ渡す。結果の流れが終わったら（確定し終えた・やめた・失敗した）流れを終える。
    private nonisolated static func forward<Results: AsyncSequence & Sendable>(
        _ results: Results, to continuation: AsyncStream<VoiceEvent>.Continuation
    ) async where Results.Element: TranscriptionResult {
        do {
            for try await result in results {
                continuation.yield(.segment(VoiceTranscript.Segment(result)))
            }
        } catch is CancellationError {
            // やめたとき。失敗ではない。
        } catch {
            continuation.yield(.failed)
        }
        continuation.finish()
    }

    /// 音声を渡し終えた。渡した分を確定させる。確定した結果を出し終えると、書き起こしが結果の流れを終え（Apple の説明）、
    /// `events` も終わる。
    func finish() async {
        feeder.finish()
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            // 確定できなかった。流れを終えて、聞き取れた分（途中の文を含む）で締めくくってもらう。
            await cancel()
        }
    }

    /// すぐにやめる（確定を待たない）。
    func cancel() async {
        feeder.finish()
        await analyzer.cancelAndFinishNow()
        resultsTask.cancel()
        eventContinuation.finish()
    }
}
