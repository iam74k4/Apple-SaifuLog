@preconcurrency import AVFoundation
import Foundation
import SaifuLogCore
import Speech

/// マイクの声を、端末の中の SpeechAnalyzer（SpeechTranscriber か DictationTranscriber）で書き起こす。
///
/// 声は録音のタップからメモリの上で書き起こしへ渡すだけで、ファイルには書かず、どこへも送らない。SpeechAnalyzer の書き起こしの
/// モジュールは、声を Apple のサーバーへ送らない（Apple の説明の「Asking Permission to Use Speech Recognition」）。そのため
/// 音声認識の許可（SFSpeechRecognizer の許可と NSSpeechRecognitionUsageDescription）は求めず、マイクの許可だけを使う。
@MainActor
final class SpeechAnalyzerTranscriber: VoiceTranscribing {
    /// 最後に調べた経路（`availability()`）。モデルのダウンロードと書き起こしに使う。
    private var route: VoiceRoute = .none
    private var engine: AVAudioEngine?
    private var session: SpeechAnalysisSession?
    /// 返した流れへ渡す口（割り込みの知らせを混ぜるため）。
    private var continuation: AsyncStream<VoiceEvent>.Continuation?
    private var forwarding: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    /// `start()` の回の番号。`cancel()`（次の `start()` の初めにも呼ぶ）で進める。`start()` は準備を待つ間にメインアクターを
    /// 手放すので、その間に取りやめられたら、戻ってきた古い `start()` は自分で始めたものだけを片づけて投げる（後の回の
    /// engine・session・割り込みの observer を上書きすると、後の回を止められなくなるため）。
    private var generation = 0

    isolated deinit {
        stopAudio()
    }

    func availability() async -> VoiceAvailability {
        let availability = await SpeechModules.availability()
        route = availability.route
        return availability
    }

    func installModel(progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let module = await SpeechModules.makeModule(for: route) else { throw VoiceTranscriptionError.unavailable }
        // 入っていれば nil が返る。言語の枠（予約）は、足りなければ自動で取る（Apple の説明の assetInstallationRequest）。
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            let polling = Task { @MainActor in
                while !Task.isCancelled {
                    progress(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { polling.cancel() }
            try await request.downloadAndInstall()
        }
        // 回線の都合で初めの試みが済まなくても、投げずに戻ることがある（OS が後で試し直す。Apple の説明の downloadAndInstall）。
        // 入ったことを確かめてから、使えるものとして扱う。
        guard await AssetInventory.status(forModules: [module]) == .installed else {
            throw VoiceTranscriptionError.modelNotInstalled
        }
        progress(1)
    }

    func start() async throws -> AsyncStream<VoiceEvent> {
        cancel()
        let current = generation
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // 録音だけに使う。聞いている間、ほかのアプリの音は小さくする（止めたら戻す）。Apple の音声認識のサンプル
            // （Recognizing speech in live audio）と同じ設定。小さくする指定を受け付けない機器では、指定なしで録音する。
            do {
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            } catch {
                try audioSession.setCategory(.record, mode: .measurement)
            }
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceTranscriptionError.audioSetupFailed
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // マイクが無い・使えないと、形式が空（0 Hz・0 チャンネル）で返る。
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Self.deactivateAudioSession()
            throw VoiceTranscriptionError.noInput
        }
        let session: SpeechAnalysisSession
        do {
            session = try await SpeechAnalysisSession.start(route: route, naturalFormat: format)
        } catch {
            // 取りやめられていれば、録音の設定は取りやめた側が戻した（次の回がもう使っていることもある）ので触らない。
            if generation == current { Self.deactivateAudioSession() }
            throw error
        }
        guard generation == current else {
            // 準備を待つ間に取りやめられた（止めるボタン・アプリが裏へ・次の回）。エンジンはまだ動かしていないので、マイクは
            // 開かずに、自分の書き起こしだけを片づける。
            await session.cancel()
            throw CancellationError()
        }
        // ここから self に入れ終えるまでは待たない（途中で取りやめられて、古い回が self を書き換えることがないように）。
        input.installTap(onBus: 0, bufferSize: 4096, format: format, block: Self.makeTap(feeding: session.feeder))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            // 書き起こしの片づけを待つ間に次の回が録音の設定を使い始めることがあるので、先に戻す。
            Self.deactivateAudioSession()
            await session.cancel()
            throw VoiceTranscriptionError.audioSetupFailed
        }
        self.engine = engine
        self.session = session

        let (stream, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
        self.continuation = continuation
        observeInterruptions(of: engine, into: continuation)
        forwarding = Task { [weak self] in
            for await event in session.events {
                continuation.yield(event)
            }
            // 確定し終えた（か、やめた・失敗した）。
            continuation.finish()
            self?.sessionDidEnd(session)
        }
        return stream
    }

    func stop() {
        guard let session else { return }
        stopAudio()
        Task { await session.finish() }
    }

    func cancel() {
        // 途中の `start()` があれば、戻ってきたところで取りやめさせる。
        generation += 1
        let session = self.session
        self.session = nil
        stopAudio()
        forwarding?.cancel()
        forwarding = nil
        continuation?.finish()
        continuation = nil
        if let session {
            Task { await session.cancel() }
        }
    }

    private func sessionDidEnd(_ ended: SpeechAnalysisSession) {
        guard session === ended else { return }
        session = nil
        continuation = nil
        forwarding = nil
    }

    /// 録音を止める（書き起こしは続けて、渡した分を確定させる）。
    private func stopAudio() {
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        Self.deactivateAudioSession()
    }

    /// 録音の設定を戻す（小さくしたほかのアプリの音を戻す）。
    private static func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 電話・Siri・ほかのアプリの音声（割り込み）、マイクやイヤホンの付け外し（エンジンの構成の変化）、音声の仕組みの再起動で
    /// 録音が止められたら知らせる。止められた後は音が来ないので、そこまでを入力欄へ入れて終える。
    private func observeInterruptions(of engine: AVAudioEngine, into continuation: AsyncStream<VoiceEvent>.Continuation) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { notification in
                // 割り込みの始まりだけを見る（終わりの知らせは、止めた後なので要らない）。
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began
                else { return }
                continuation.yield(.interrupted)
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
                continuation.yield(.interrupted)
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
                continuation.yield(.interrupted)
            },
        ]
    }

    /// 録音のタップ。音声のスレッドで呼ばれるので、メインアクターの外で作る（メインアクターの中で作った閉包は、音声のスレッドで
    /// 呼ばれたときに実行時の確かめで止まるため）。
    private nonisolated static func makeTap(feeding feeder: AnalyzerFeeder) -> AVAudioNodeTapBlock {
        { buffer, _ in feeder.feed(buffer) }
    }
}

/// マイクの許可（AVAudioApplication）。
struct SystemMicrophone: MicrophoneAuthorizing {
    var permission: MicrophonePermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .denied
        }
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
