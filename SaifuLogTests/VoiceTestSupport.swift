import Foundation
import SaifuLogCore
@testable import SaifuLog

/// 声の書き起こしの代わり。シミュレータではマイクの声を流せないので、書き起こしの結果（途中・確定）や割り込みを、テストが決めて流す。
@MainActor
final class FakeVoiceTranscriber: VoiceTranscribing {
    /// 調べたときに返す、経路とモデルの状態。
    var availabilityResult = VoiceAvailability(route: .speechTranscriber, model: .installed)
    /// モデルを入れるときに知らせる進み。
    var installProgress: [Double] = [0.25, 0.75]
    /// モデルを入れるのに失敗させるか。
    var failsInstall = false
    /// 始めるときに投げるもの（nil なら始められる）。
    var startError: VoiceTranscriptionError?
    /// `stop()` のときに流す確定の結果。流した後に流れを終える。nil なら流れを終えない（確定が返らない場面）。
    var finalsOnStop: [VoiceTranscript.Segment]? = []
    /// 始めるときに待つ門（書き起こしを始める呼び出しの途中で止める場面）。nil なら待たない。
    var startGate: Gate?
    /// 始める途中で `cancel()` されても、取りやめずに流れを返すか（取りやめに応えない書き起こしの場面）。既定は、
    /// `VoiceTranscribing.start()` の決め事どおり `CancellationError` を投げる。
    var ignoresCancelWhileStarting = false

    private(set) var availabilityCalls = 0
    private(set) var installCalls = 0
    private(set) var startCalls = 0
    private(set) var stopCalls = 0
    private(set) var cancelCalls = 0
    /// 戻っていない `start()` の数と、同時に走った数の最大（前の回を始め終える前に次の回を始めていないかを確かめる）。
    private(set) var startsInFlight = 0
    private(set) var maxConcurrentStarts = 0
    private var continuation: AsyncStream<VoiceEvent>.Continuation?

    func availability() async -> VoiceAvailability {
        availabilityCalls += 1
        return availabilityResult
    }

    func installModel(progress: @escaping @MainActor (Double) -> Void) async throws {
        installCalls += 1
        for value in installProgress { progress(value) }
        if failsInstall { throw VoiceTranscriptionError.modelNotInstalled }
        availabilityResult.model = .installed
    }

    func start() async throws -> AsyncStream<VoiceEvent> {
        startCalls += 1
        startsInFlight += 1
        maxConcurrentStarts = max(maxConcurrentStarts, startsInFlight)
        defer { startsInFlight -= 1 }
        let cancelsBefore = cancelCalls
        if let startGate { await startGate.wait() }
        if let startError { throw startError }
        if cancelCalls != cancelsBefore, !ignoresCancelWhileStarting { throw CancellationError() }
        let (stream, continuation) = AsyncStream.makeStream(of: VoiceEvent.self)
        self.continuation = continuation
        return stream
    }

    func stop() {
        stopCalls += 1
        guard let finals = finalsOnStop else { return }
        for segment in finals { emit(.segment(segment)) }
        endStream()
    }

    func cancel() {
        cancelCalls += 1
        continuation?.finish()
        continuation = nil
    }

    /// 聞いている間の知らせを流す。
    func emit(_ event: VoiceEvent) {
        continuation?.yield(event)
    }

    /// 流れを終える（確定し終えた・書き起こしが止まった）。
    func endStream() {
        continuation?.finish()
        continuation = nil
    }
}

/// マイクの許可の代わり。
@MainActor
final class FakeMicrophone: MicrophoneAuthorizing {
    var permission: MicrophonePermission
    /// 許可を求めたときの答え。
    var grantsOnRequest: Bool
    /// 許可を求めたときに待つ門（iOS の確認を出している間の場面）。nil なら待たない。
    var requestGate: Gate?
    private(set) var requestCalls = 0

    init(permission: MicrophonePermission = .granted, grantsOnRequest: Bool = true) {
        self.permission = permission
        self.grantsOnRequest = grantsOnRequest
    }

    func requestPermission() async -> Bool {
        requestCalls += 1
        if let requestGate { await requestGate.wait() }
        permission = grantsOnRequest ? .granted : .denied
        return grantsOnRequest
    }
}

/// 回線の種類の代わり。
struct FakeNetworkCost: NetworkCostChecking {
    var expensive = false

    func isExpensive() async -> Bool {
        expensive
    }
}

/// 声の入力のモデルと、その書き起こし・マイク・時計・読み上げの代わり。
@MainActor
final class VoiceFixture {
    let transcriber = FakeVoiceTranscriber()
    let microphone: FakeMicrophone
    var now = TestSupport.now
    /// 聞き始めの読み上げ（読み終えるまで待つもの）を止めておく門。nil なら待たない。
    var announcementGate: Gate?
    /// 確定を待つ上限の待ちを開ける門（開けると上限に届いたことになる）。
    let finishingTimeoutGate = Gate()
    private(set) var announcements: [String] = []
    /// 聞き始めに、読み終えるまで待って読み上げた文。
    private(set) var waitedAnnouncements: [String] = []
    /// 入力欄へ入れた文（`HomeModel` につながないとき）。
    private(set) var inserted: [String] = []
    private(set) var model: VoiceInputModel!

    /// - Parameters:
    ///   - permission: マイクの許可の状態。
    ///   - grantsOnRequest: 許可を求めたときに許可するか。
    ///   - expensiveNetwork: いまの回線がモバイル回線か低データモードか。
    init(permission: MicrophonePermission = .granted, grantsOnRequest: Bool = true, expensiveNetwork: Bool = false) {
        microphone = FakeMicrophone(permission: permission, grantsOnRequest: grantsOnRequest)
        let finishingTimeoutGate = finishingTimeoutGate
        model = VoiceInputModel(
            transcriber: transcriber,
            microphone: microphone,
            network: FakeNetworkCost(expensive: expensiveNetwork),
            now: { [unowned self] in now },
            // 自動で止めるかを確かめる間隔は、待ち続ける（テストが時計を進めて `tick()` を呼ぶ）。確定を待つ上限は、門を開けたら届く。
            sleep: { duration in
                if duration == VoiceInputModel.finishingTimeout {
                    await finishingTimeoutGate.wait()
                } else {
                    try await Task.sleep(for: .seconds(3_600))
                }
            },
            announce: { [unowned self] in announcements.append($0) },
            announceAndWait: { [unowned self] text in
                waitedAnnouncements.append(text)
                if let announcementGate { await announcementGate.wait() }
            }
        )
        model.insertTranscript = { [unowned self] in inserted.append($0) }
    }

    /// マイクのボタンを押して、聞き始めるまで進める。
    func startListening() async throws {
        await model.refreshAvailability()
        await model.toggle()?.value
    }

    /// 流した知らせをモデルが受け取り終えるまで待つ（知らせは Task で受け取るため）。
    func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// `condition` が成り立つまで、ほかの Task に順番を譲りながら待つ。回数を使い切っても成り立たなければ false。
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if condition() { return true }
            await Task.yield()
        }
        return false
    }

    /// 時計を進める。
    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

extension VoiceTranscript.Segment {
    /// テスト用の途中の結果。
    static func volatile(_ text: String, _ start: Double, _ end: Double, finalizedThrough: Double = 0) -> Self {
        Self(text: text, start: start, end: end, finalizedThrough: finalizedThrough)
    }

    /// テスト用の確定した結果。
    static func final(_ text: String, _ start: Double, _ end: Double) -> Self {
        Self(text: text, start: start, end: end, finalizedThrough: end)
    }
}
