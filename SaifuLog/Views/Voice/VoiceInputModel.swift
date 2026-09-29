import Foundation
import Observation
import SaifuLogCore

/// 声の入力（ホームの入力欄のマイクのボタン）の状態と操作。
///
/// 話した内容を端末の中で書き起こし、入力欄へ入れるまでを受け持つ。**送信はしない**（書き起こしを利用者が見て直してから、
/// 送信ボタンを押したときだけ記録や質問になる）。書き起こしは読み違えることがあり、黙って記録すると合計が狂うため。
///
/// 流れ: 待機 → マイクの許可 →（モデルが無ければダウンロードの確認と進み）→ 準備 → 聞いている（途中の文を薄く出す）→
/// 止める（ボタン・話し終えて 2 秒・話し始めずに 6 秒・30 秒・割り込み・アプリが裏へ）→ 確定を待つ → 入力欄へ入れて待機。
///
/// 書き起こし（`VoiceTranscribing`）・マイクの許可・回線の種類・時計・待ち方・読み上げは外から渡し、SaifuLogTests で差し替えて
/// 確かめる（シミュレータではマイクの声を流せないため）。
@MainActor
@Observable
final class VoiceInputModel {
    enum Phase: Equatable {
        /// 待機（マイクのボタンを出す）。
        case idle
        /// マイクの許可を求めている（iOS の確認が出ている）。
        case requestingPermission
        /// 書き起こしのモデルをダウンロードしている（進みは 0〜1）。
        case downloading(progress: Double)
        /// 録音と書き起こしを始めている。
        case preparing
        /// 聞いている。
        case listening
        /// 録音を止め、確定した結果を待っている。
        case finishing
    }

    /// 止めた理由。
    enum StopReason: Equatable, Sendable {
        /// 止めるボタン。
        case user
        /// 話し終えた（聞こえなくなって 2 秒）。
        case silence
        /// 話し始めなかった（6 秒）。
        case noSpeech
        /// 30 秒に届いた。
        case maximumDuration
        /// 電話・Siri・ほかのアプリの音声・マイクの付け外し。
        case interrupted
        /// アプリが裏に回った。
        case background
        /// 書き起こしが失敗した。
        case failed

        /// 確定を待たずに締めくくるか。割り込みやアプリが裏に回ったときは、その後に確定を待てる保証が無い（アプリが止められる）
        /// ので、聞き取れた分（途中の文を含む）ですぐ入力欄へ入れる。
        var endsImmediately: Bool {
            switch self {
            case .interrupted, .background, .failed: true
            case .user, .silence, .noSpeech, .maximumDuration: false
            }
        }
    }

    /// 声の入力の後に、入力欄の上に少しの間だけ出す知らせ。
    enum Notice: Equatable, Sendable {
        /// 何も聞き取れなかった。
        case nothingHeard
        /// 声の入力を始められなかった・途中で失敗した。
        case failed
        /// モデルを入れ終えた（続けてマイクのボタンで話せる）。
        case modelReady
        /// モデルを入れられなかった。
        case downloadFailed
    }

    /// モデルのダウンロードの確認。
    struct DownloadConfirmation: Equatable {
        /// いまの回線がモバイル回線か低データモードか（Wi‑Fi をすすめる文を添える）。
        let onExpensiveNetwork: Bool
    }

    private(set) var phase: Phase = .idle
    /// この端末で使える経路とモデルの状態。まだ調べていなければ nil（マイクのボタンを出さない）。
    private(set) var availability: VoiceAvailability?
    /// 書き起こし（聞いている間の確定した文と途中の文）。
    private(set) var transcript = VoiceTranscript()
    /// マイクの音の大きさ（0〜1。表示の目安）。
    private(set) var level: Double = 0
    /// マイクの許可が無いときの案内（設定を開くボタンつき）。
    var showsPermissionAlert = false
    /// モデルのダウンロードの確認。出していなければ nil。
    var downloadConfirmation: DownloadConfirmation?
    /// 入力欄の上の知らせ。出していなければ nil（画面が少し後に nil に戻す）。
    var notice: Notice?
    /// 書き起こしを始める呼び出し（`VoiceTranscribing.start()`）が、まだ戻っていないか。準備の間に止めると待機に戻るが、戻るまでは
    /// マイクのボタンを効かなくする（前の回を始め終える前に次の回を始めると、2 つの回が入り交じって、片方のマイクや書き起こしを
    /// 止められなくなるため）。
    private(set) var isStartPending = false

    /// 書き起こした文を入力欄へ入れる（`HomeModel` が決める）。
    @ObservationIgnored var insertTranscript: @MainActor (String) -> Void = { _ in }
    /// ホームの上にほかの画面やシートを出しているか（`HomeModel` が決める）。マイクの許可の確認やモデルの枠を取るのを待つ間に
    /// 出る（体験の終わりの案内など）ことがあり、そのまま聞き始めると、見えない入力欄に向けてマイクを開くことになるため、
    /// 聞き始める前に確かめる。
    @ObservationIgnored var isCoveredByOtherScreen: @MainActor () -> Bool = { false }

    @ObservationIgnored private let transcriber: any VoiceTranscribing
    @ObservationIgnored private let microphone: any MicrophoneAuthorizing
    @ObservationIgnored private let network: any NetworkCostChecking
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let announceAndWait: @MainActor (String) async -> Void

    /// 聞き始めた日時と、最後に書き起こしの文が変わった日時（自動で止める判断。`VoiceListeningLimit`）。
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var lastHeardAt: Date?
    @ObservationIgnored private var stopReason: StopReason?
    /// 録音の回の番号。止めた後に届いた前の回の知らせを捨てるため（テストで前の回の番号を取る）。
    @ObservationIgnored private(set) var session = 0
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var finishingTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTask: Task<Void, Never>?

    /// 止めた後に確定を待つ上限。確定が返らなくても入力欄へ入れて終えるため。
    nonisolated static let finishingTimeout: Duration = .seconds(3)
    /// 自動で止めるかを確かめる間隔。
    nonisolated static let clockInterval: Duration = .milliseconds(250)

    /// - Parameters:
    ///   - transcriber: 書き起こし。テストで差し替える。
    ///   - microphone: マイクの許可。テストで差し替える。
    ///   - network: 回線の種類（ダウンロードの確認の文を選ぶ）。テストで差し替える。
    ///   - now: 自動で止める判断の時計。テストで決めた日時にする。
    ///   - sleep: 待ち方（自動で止めるかを確かめる間隔と、確定を待つ上限）。テストでは待たずに止めておく。
    ///   - announce: VoiceOver に読み上げさせる。
    ///   - announceAndWait: 読み上げて、読み終えるまで待つ（聞き始めの知らせをマイクが拾わないように）。
    init(
        transcriber: any VoiceTranscribing = SpeechAnalyzerTranscriber(),
        microphone: any MicrophoneAuthorizing = SystemMicrophone(),
        network: any NetworkCostChecking = SystemNetworkCost(),
        now: @escaping () -> Date = { .now },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) },
        announceAndWait: @escaping @MainActor (String) async -> Void = { await VoiceOver.announceAndWait($0) }
    ) {
        self.transcriber = transcriber
        self.microphone = microphone
        self.network = network
        self.now = now
        self.sleep = sleep
        self.announce = announce
        self.announceAndWait = announceAndWait
    }

    /// マイクのボタンを出すか（日本語で使える経路がある）。
    var isAvailable: Bool {
        guard let availability else { return false }
        return availability.route != .none
    }

    /// マイクのボタンを押せるか。待機していて、前の回を始める呼び出しも戻っている（`isStartPending`）。
    var canStart: Bool {
        phase == .idle && !isStartPending
    }

    /// 入力欄の代わりに声の入力の表示を出しているか（ダウンロード・準備・聞いている・確定を待っている）。
    var isActive: Bool {
        switch phase {
        case .idle, .requestingPermission: false
        case .downloading, .preparing, .listening, .finishing: true
        }
    }

    /// 聞いている間に入力欄の代わりに出す文。
    struct Preview: Equatable {
        /// 打ちかけの文と確定した文（墨で出す）。
        var settled: String
        /// 途中の文（薄く出す。後から変わりうる）。
        var tentative: String

        var full: String { settled + tentative }
    }

    /// 聞いている間に出す文。入力欄に打ちかけの文（`prefix`）があれば、その後ろに書き起こしを続ける（止めたときに入力欄へ入る
    /// 形と同じ）。
    func preview(prefix: String) -> Preview {
        let full = VoiceTranscript.draft(appending: transcript.text, to: prefix)
        let settled = VoiceTranscript.draft(appending: transcript.finalizedText, to: prefix)
        guard full.hasPrefix(settled) else { return Preview(settled: full, tentative: "") }
        return Preview(settled: settled, tentative: String(full.dropFirst(settled.count)))
    }

    // MARK: - 使えるか

    /// 使える経路とモデルの状態を調べ直す（ホームが出たとき・前面に戻ったとき）。ほかのアプリがモデルを入れたり、OS が
    /// 後からダウンロードを済ませたりするので、そのつど読み直す。
    func refreshAvailability() async {
        availability = await transcriber.availability()
    }

    // MARK: - 始める・止める

    /// マイクのボタン（聞いている間は止めるボタン）。始めるときは、聞き始める（か、許可やダウンロードの案内を出す）までを待つ
    /// Task を返す（テストで使う）。
    @discardableResult
    func toggle() -> Task<Void, Never>? {
        switch phase {
        case .idle:
            guard !isStartPending else { return nil }
            return Task { await begin() }
        case .preparing, .listening:
            stop(.user)
            return nil
        case .requestingPermission, .downloading, .finishing:
            return nil
        }
    }

    private func begin() async {
        notice = nil
        if availability?.model != .installed {
            await refreshAvailability()
        }
        guard let availability, availability.route != .none, phase == .idle, !isStartPending else { return }
        // 許可を先に確かめる（許可されないのに、大きなモデルをダウンロードさせないため）。
        switch microphone.permission {
        case .granted:
            break
        case .denied:
            showsPermissionAlert = true
            return
        case .undetermined:
            phase = .requestingPermission
            let granted = await microphone.requestPermission()
            phase = .idle
            guard granted else {
                showsPermissionAlert = true
                return
            }
        }
        // 許可の確認を出している間に、ほかの画面やシートが出ていることがある。聞き始めず、ダウンロードの確認も重ねない。
        guard !isCoveredByOtherScreen() else { return }
        switch availability.model {
        case .installed:
            await startListening()
        case .needsReservation:
            // 端末にはもう入っている（ほかのアプリが入れた）。このアプリの枠を取るだけでダウンロードは要らないので、確かめずに
            // 枠を取って聞き始める。取れなければ、ダウンロードの確認に回す。
            do {
                try await transcriber.installModel { _ in }
                self.availability?.model = .installed
                await startListening()
            } catch {
                self.availability?.model = .needsDownload
                downloadConfirmation = DownloadConfirmation(onExpensiveNetwork: await network.isExpensive())
            }
        case .downloading:
            // OS がもうダウンロードしている。確かめずに進みを出して待つ（同じダウンロードにまとめられる。Apple の説明）。
            await startDownload().value
        case .needsDownload, nil:
            downloadConfirmation = DownloadConfirmation(onExpensiveNetwork: await network.isExpensive())
        }
    }

    private func startListening() async {
        // 前の回を始める呼び出しが戻る前には始めない（`isStartPending`）。枠を取るのを待つ間にほかの画面が出たときも始めない。
        guard !isStartPending, !isCoveredByOtherScreen() else { return }
        session += 1
        let current = session
        phase = .preparing
        transcript = VoiceTranscript()
        level = 0
        stopReason = nil
        // VoiceOver の読み上げをマイクが拾って書き起こさないよう、読み終えてから聞き始める（VoiceOver を使っていなければすぐ戻る）。
        await announceAndWait(String(localized: "声の入力を始めます"))
        guard phase == .preparing, session == current else { return }
        let events: AsyncStream<VoiceEvent>
        do {
            events = try await startTranscriber()
        } catch VoiceTranscriptionError.modelNotInstalled {
            guard session == current else { return }
            // 調べた後にモデルが消された（使われていないモデルは OS が外すことがある）。入れ直しを案内する。
            phase = .idle
            availability?.model = .needsDownload
            downloadConfirmation = DownloadConfirmation(onExpensiveNetwork: await network.isExpensive())
            return
        } catch {
            guard session == current else { return }
            phase = .idle
            show(.failed)
            return
        }
        // 始める間に止められた（止めるボタン・アプリが裏へ・ホームが片づけられた）。止めたときに取りやめを頼んである（`stop`・
        // `cancel`）が、取りやめずに始め終えた書き起こしもありうるので、ここでもやめる。
        guard phase == .preparing, session == current else {
            transcriber.cancel()
            return
        }
        phase = .listening
        startedAt = now()
        lastHeardAt = nil
        eventsTask = Task { [weak self] in
            for await event in events {
                self?.handle(event, session: current)
            }
            self?.eventsDidEnd(session: current)
        }
        let sleep = sleep
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(Self.clockInterval)
                } catch {
                    return
                }
                self?.tick()
            }
        }
    }

    /// 書き起こしを始める。戻るまで `isStartPending` を立てる（その間はマイクのボタンを効かなくする）。
    private func startTranscriber() async throws -> AsyncStream<VoiceEvent> {
        isStartPending = true
        defer { isStartPending = false }
        return try await transcriber.start()
    }

    /// 自動で止めるかを確かめる（話し終えた・話し始めない・30 秒）。一定の間隔で呼ぶ（テストでは時計を進めて呼ぶ）。
    func tick() {
        guard phase == .listening, let startedAt else { return }
        switch VoiceListeningLimit.stopReason(startedAt: startedAt, lastHeardAt: lastHeardAt, now: now()) {
        case .silence: stop(.silence)
        case .noSpeech: stop(.noSpeech)
        case .maximumDuration: stop(.maximumDuration)
        case nil: break
        }
    }

    /// 書き起こしの知らせを受け取る。前の回（`current` がいまの回でない）の知らせは使わない。受け取りの Task は止めた後にも
    /// 溜まった知らせを渡すことがあり、次の回を始めた後に動くこともあるため（テストで前の回の番号を渡して確かめる）。
    func handle(_ event: VoiceEvent, session current: Int) {
        guard session == current else { return }
        switch event {
        case .level(let value):
            if phase == .listening { level = value }
        case .segment(let segment):
            let before = transcript.text
            transcript.apply(segment)
            if transcript.text != before { lastHeardAt = now() }
        case .interrupted:
            stop(.interrupted)
        case .failed:
            stop(.failed)
        }
    }

    /// 止める。止めるボタン・話し終えた・30 秒のときは、そこまでの音声の確定を待ってから入力欄へ入れる。割り込み・アプリが裏へ・
    /// 失敗のときは、待たずに聞き取れた分ですぐ入力欄へ入れる。
    func stop(_ reason: StopReason) {
        switch phase {
        case .preparing:
            // まだ始めている途中。回の番号を進めて待機に戻る。書き起こしを始める呼び出しの途中なら取りやめを頼む（マイクを開かずに
            // 投げて戻る。`VoiceTranscribing.start()`）。戻るまではマイクのボタンを効かなくし（`canStart`）、戻ったところで
            // 取りやめる（`startListening`）。
            session += 1
            phase = .idle
            if isStartPending { transcriber.cancel() }
        case .listening:
            stopReason = reason
            clockTask?.cancel()
            level = 0
            if reason.endsImmediately {
                complete(cancellingTranscriber: true)
            } else {
                phase = .finishing
                transcriber.stop()
                let current = session
                let sleep = sleep
                finishingTimeoutTask = Task { [weak self] in
                    try? await sleep(Self.finishingTimeout)
                    guard !Task.isCancelled else { return }
                    self?.finishingDidTimeOut(session: current)
                }
            }
        case .finishing:
            if reason.endsImmediately {
                complete(cancellingTranscriber: true)
            }
        case .idle, .requestingPermission, .downloading:
            break
        }
    }

    /// 声の入力をやめる（入力欄には入れない）。ホームの画面が片づけられるとき（保存先の開き直し）に呼ぶ。
    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        guard phase != .idle, phase != .requestingPermission else { return }
        session += 1
        transcriber.cancel()
        eventsTask?.cancel()
        clockTask?.cancel()
        finishingTimeoutTask?.cancel()
        transcript = VoiceTranscript()
        level = 0
        phase = .idle
    }

    /// 書き起こしの流れが終わった。前の回の流れの終わりは使わない（止めてすぐ次の回を始めたとき、次の回を締めくくらないように。
    /// テストで前の回の番号を渡して確かめる）。
    func eventsDidEnd(session current: Int) {
        guard session == current, phase == .listening || phase == .finishing else { return }
        // 止める前に流れが終わった（書き起こしが失敗した）。聞き取れた分は入れる。
        if phase == .listening { stopReason = .failed }
        complete(cancellingTranscriber: false)
    }

    private func finishingDidTimeOut(session current: Int) {
        guard session == current, phase == .finishing else { return }
        complete(cancellingTranscriber: true)
    }

    /// 締めくくる。聞き取れた分（残っている途中の文を含む）を入力欄へ入れて、待機に戻る。
    private func complete(cancellingTranscriber: Bool) {
        session += 1
        if cancellingTranscriber { transcriber.cancel() }
        eventsTask?.cancel()
        clockTask?.cancel()
        finishingTimeoutTask?.cancel()
        transcript.finish()
        let text = transcript.text
        transcript = VoiceTranscript()
        level = 0
        phase = .idle
        if text.isEmpty {
            show(stopReason == .failed ? .failed : .nothingHeard)
        } else {
            insertTranscript(text)
            // 何が入ったかを VoiceOver の利用者にも伝える（読み違いに、送る前に気づけるように）。
            announce(String(localized: "声の入力を終えました。入力欄: \(text)"))
        }
    }

    /// 知らせを出し、同じ文を VoiceOver に読み上げる（入力欄の上の小さな知らせは、VoiceOver の利用者には見つけにくいため）。
    private func show(_ notice: Notice) {
        self.notice = notice
        announce(notice.message)
    }

    // MARK: - モデルのダウンロード

    /// ダウンロードの確認で「ダウンロード」を選んだ。入れ終えるまでを待つ Task を返す（テストで使う）。
    ///
    /// 入れ終えても自動では聞き始めない（ダウンロードは時間がかかることがあり、その後に黙ってマイクを開くと驚かせるため）。
    /// 入れ終えたことを知らせ、マイクのボタンを押し直してもらう。
    @discardableResult
    func confirmDownload() -> Task<Void, Never> {
        downloadConfirmation = nil
        return startDownload()
    }

    /// ダウンロードの確認で「キャンセル」を選んだ。
    func declineDownload() {
        downloadConfirmation = nil
    }

    /// ダウンロードの進みの「やめる」。待つのをやめる（OS はダウンロードを続けることがあり、次に押したときに入っていれば使える）。
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if case .downloading = phase { phase = .idle }
    }

    private func startDownload() -> Task<Void, Never> {
        phase = .downloading(progress: 0)
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await transcriber.installModel { [weak self] progress in
                    guard let self, case .downloading = phase else { return }
                    phase = .downloading(progress: min(max(progress, 0), 1))
                }
                guard !Task.isCancelled, case .downloading = phase else { return }
                availability?.model = .installed
                phase = .idle
                show(.modelReady)
            } catch {
                guard !Task.isCancelled, case .downloading = phase else { return }
                phase = .idle
                show(.downloadFailed)
            }
        }
        downloadTask = task
        return task
    }
}

extension VoiceInputModel.Notice {
    /// 知らせの文（画面と読み上げで同じ）。
    var message: String {
        switch self {
        case .nothingHeard: String(localized: "声を聞き取れませんでした。マイクのボタンを押して、もう一度話してください。")
        case .failed: String(localized: "声の入力を使えませんでした。もう一度お試しください。")
        case .modelReady: String(localized: "日本語の音声モデルを入れました。マイクのボタンで話せます。")
        case .downloadFailed: String(localized: "日本語の音声モデルを入れられませんでした。インターネットにつないで、もう一度お試しください。")
        }
    }
}
