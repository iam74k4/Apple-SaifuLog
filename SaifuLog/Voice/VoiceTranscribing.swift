import Foundation
import SaifuLogCore

/// 声の書き起こしに使う経路。
///
/// rawValue は診断画面に出す（言語によらず同じ値で見比べられるように）。
enum VoiceRoute: String, Equatable, Sendable {
    /// iOS 26 の SpeechTranscriber（新しい書き起こしのモデル）。
    case speechTranscriber
    /// DictationTranscriber（キーボードの音声入力と同じモデル）。SpeechTranscriber が日本語に対応しない端末で使う。
    case dictationTranscriber
    /// どちらも日本語で使えない。マイクのボタンを出さない（キーボードの音声入力は、そのまま使える）。
    case none

    /// 経路を選ぶ。SpeechTranscriber を先に、使えなければ DictationTranscriber にする。
    ///
    /// SpeechTranscriber は iOS 26 の新しいモデルで、ふつうの話し言葉に向く（Apple の説明）。DictationTranscriber は古い端末にも
    /// 対応する（Apple の説明）ので、SpeechTranscriber が使えない端末でも声で入力できるように残す。
    /// - Parameters:
    ///   - speechTranscriber: SpeechTranscriber の日本語のモデルの状態。端末や日本語に対応しなければ nil。
    ///   - dictation: DictationTranscriber の日本語のモデルの状態。対応しなければ nil。
    static func choose(speechTranscriber: VoiceModelState?, dictation: VoiceModelState?) -> VoiceAvailability {
        if let speechTranscriber { return VoiceAvailability(route: .speechTranscriber, model: speechTranscriber) }
        if let dictation { return VoiceAvailability(route: .dictationTranscriber, model: dictation) }
        return .unavailable
    }
}

/// 書き起こしのモデル（端末に入れる資産）の状態。モデルは Apple のサーバーから端末に入れ、ほかのアプリと共有される。
enum VoiceModelState: Equatable, Sendable {
    /// 入っている（すぐ書き起こせる）。
    case installed
    /// 端末には入っている（ほかのアプリが入れた）が、このアプリの言語の枠（予約）をまだ取っていない。枠を取るだけで、
    /// ダウンロードは要らない（macOS 26 で、この状態から枠を取ると通信せずに 1 秒ほどで使えるようになった）。
    case needsReservation
    /// 入っていない（使う前にダウンロードする）。
    case needsDownload
    /// OS がダウンロードしている途中。
    case downloading
}

/// この端末で声の入力を使えるか。
struct VoiceAvailability: Equatable, Sendable {
    var route: VoiceRoute
    /// モデルの状態。経路が無ければ nil。
    var model: VoiceModelState?

    static let unavailable = VoiceAvailability(route: .none, model: nil)
}

/// 録音と書き起こしの間に起きること。
enum VoiceEvent: Equatable, Sendable {
    /// マイクの音の大きさ（0〜1。表示の目安）。
    case level(Double)
    /// 書き起こしの結果。
    case segment(VoiceTranscript.Segment)
    /// 電話・Siri・ほかのアプリの音声・マイクの付け外しで、録音が止められた。
    case interrupted
    /// 書き起こしが失敗した。
    case failed
}

/// 録音と書き起こしを始められなかった理由。
enum VoiceTranscriptionError: Error, Equatable {
    /// 日本語の経路が無い。
    case unavailable
    /// モデルが入っていない。
    case modelNotInstalled
    /// マイクが無い・使えない（音声の形式を読めない）。
    case noInput
    /// 録音の設定（AVAudioSession・AVAudioEngine）に失敗した。
    case audioSetupFailed
    /// 書き起こしを始められなかった。
    case analyzerFailed
}

/// 声の書き起こし。実機では `SpeechAnalyzerTranscriber`（端末の中の SpeechAnalyzer と、マイクの AVAudioEngine）、テストでは差し替える
/// （シミュレータではマイクの音を流せないため）。
@MainActor
protocol VoiceTranscribing: AnyObject {
    /// 日本語で使える経路と、モデルの状態。
    func availability() async -> VoiceAvailability
    /// モデルをダウンロードして入れる。進み（0〜1）を知らせる。入らなければ投げる。
    func installModel(progress: @escaping @MainActor (Double) -> Void) async throws
    /// 録音と書き起こしを始める。返す流れは、`stop()` の後に確定した結果を出し終えたとき、`cancel()` のとき、割り込みや
    /// 失敗の後に終わる。
    ///
    /// 前の `start()` が戻るまで、次の `start()` を呼ばない（`VoiceInputModel` が、戻るまでマイクのボタンを効かなくして守る）。
    /// 途中で `cancel()` が呼ばれたら、始めたものを片づけて（マイクは開かずに）`CancellationError` を投げる。止めるボタンを
    /// 押した後に、マイクが一瞬でも開かないようにするため。
    func start() async throws -> AsyncStream<VoiceEvent>
    /// 録音を止め、そこまでの音声を確定させる（確定した結果を出してから流れを終える）。
    func stop()
    /// 録音と書き起こしをすぐにやめる（確定を待たない）。`start()` の途中でも呼べる。
    func cancel()
}

/// マイクの使用の許可。
enum MicrophonePermission: Equatable, Sendable {
    case undetermined
    case denied
    case granted
}

/// マイクの許可を読む・求める。テストで差し替える。
@MainActor
protocol MicrophoneAuthorizing {
    var permission: MicrophonePermission { get }
    /// 許可を求める（初めてなら iOS の確認が出る）。許可されたら true。
    func requestPermission() async -> Bool
}

/// いまの回線が、大きなダウンロードを気にしたほうがよい回線か（モバイル回線・インターネット共有・低データモード）。テストで差し替える。
@MainActor
protocol NetworkCostChecking {
    func isExpensive() async -> Bool
}
