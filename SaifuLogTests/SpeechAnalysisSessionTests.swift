import AVFoundation
import Foundation
import SaifuLogCore
import Synchronization
import Testing
@testable import SaifuLog

/// 端末の書き起こし（SpeechAnalyzer）へ音声を渡す部分。マイクの代わりに、読み上げ（AVSpeechSynthesizer）で作った日本語の声を渡す。
///
/// 書き起こしのモデルは端末に入れる資産で、CI のシミュレータには入っていないことがある。そのときは飛ばさず、理由を既知の問題として
/// 結果に残して先へ進む（テストを止めない。モデルを入れるダウンロードもしない）。
@MainActor
struct SpeechAnalysisSessionTests {
    // MARK: - 音声の形式

    @Test("マイクの形式（48kHz の浮動小数点）を、書き起こしの形式（16kHz の整数）に変える")
    func convertsSampleRateAndFormat() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let output = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false))
        let converter = AudioBufferConverter(outputFormat: output)

        let converted = try converter.convert(Self.sine(format: input, frames: 4_800))

        #expect(converted.format == output)
        // 0.1 秒の音声は、16kHz で 1,600 標本ほど（変換の遅れで少し少なくなることがある）。
        #expect((1_400...1_600).contains(Int(converted.frameLength)))
    }

    @Test("形式が同じなら写しを返す（録音のバッファは使い回されるため、同じものを渡さない）")
    func copiesMatchingFormat() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let converter = AudioBufferConverter(outputFormat: format)
        let buffer = Self.sine(format: format, frames: 160)

        let converted = try converter.convert(buffer)

        #expect(converted !== buffer)
        #expect(converted.frameLength == buffer.frameLength)
        #expect(converted.floatChannelData?[0][10] == buffer.floatChannelData?[0][10])
    }

    @Test("音の大きさの目安は、無音で 0、-50dBFS 以下で 0、0dBFS で 1")
    func level() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let silent = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        silent.frameLength = 160
        #expect(AudioLevel.normalized(silent) == 0)
        #expect(AudioLevel.normalized(rootMeanSquare: 0.001) == 0)
        #expect(AudioLevel.normalized(rootMeanSquare: 1) == 1)
        #expect(AudioLevel.normalized(Self.sine(format: format, frames: 160)) > 0.5)
    }

    // MARK: - 書き起こし

    @Test("読み上げた日本語の声を、端末の書き起こしで文字にし、金額を数字で返す")
    func transcribesSynthesizedJapaneseSpeech() async throws {
        let availability = await SpeechModules.availability()
        guard availability.route != .none else {
            Self.recordUnverified("この端末（シミュレータ）では、日本語の書き起こしの経路がありません（SpeechTranscriber と DictationTranscriber のどちらも日本語に対応していない）。")
            return
        }
        guard availability.model == .installed else {
            Self.recordUnverified("この端末（シミュレータ）には、\(availability.route.rawValue) の日本語のモデルが入っていません（テストではダウンロードしない）。")
            return
        }
        guard let voice = AVSpeechSynthesisVoice(language: "ja-JP") else {
            Self.recordUnverified("この端末（シミュレータ）には、日本語の読み上げの声がありません。")
            return
        }
        guard let buffers = await Self.synthesize("ランチ 850円", voice: voice), let first = buffers.first else {
            Self.recordUnverified("日本語の声を読み上げで作れませんでした。")
            return
        }

        let session = try await SpeechAnalysisSession.start(route: availability.route, naturalFormat: first.format)
        let collecting = Task {
            var transcript = VoiceTranscript()
            for await event in session.events {
                if case .segment(let segment) = event { transcript.apply(segment) }
            }
            transcript.finish()
            return transcript.text
        }
        for buffer in buffers { session.feeder.feed(buffer) }
        await session.finish()
        let text = await collecting.value

        #expect(text.contains("850"), "書き起こし: \(text)")
        #expect(text.contains("ランチ"), "書き起こし: \(text)")
    }

    /// 確かめられなかった理由を、既知の問題として結果に残す（失敗にはしない）。
    private static func recordUnverified(_ reason: String) {
        withKnownIssue(Comment(rawValue: "書き起こしを確かめられませんでした: \(reason)")) {
            Issue.record(Comment(rawValue: reason))
        }
    }

    /// 読み上げで声を作る（ファイルには書かず、メモリの上のバッファだけ）。作れなければ nil。
    private static func synthesize(_ text: String, voice: AVSpeechSynthesisVoice) async -> [AVAudioPCMBuffer]? {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let collected = SynthesizedBuffers()
        let finished: Bool = await withCheckedContinuation { continuation in
            let resumer = OnceResumer(continuation)
            synthesizer.write(utterance) { buffer in
                // 長さ 0 のバッファが終わりの印。
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    resumer.resume(true)
                    return
                }
                collected.append(pcm)
            }
            // 読み上げの声が使えない端末では、終わりの印が来ないことがある。
            Task {
                try? await Task.sleep(for: .seconds(20))
                resumer.resume(false)
            }
        }
        withExtendedLifetime(synthesizer) {}
        let buffers = collected.all
        return finished && !buffers.isEmpty ? buffers : nil
    }

    /// 440Hz の正弦波（振幅 0.5）。
    private static func sine(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            samples[index] = 0.5 * sin(2 * .pi * 440 * Float(index) / Float(format.sampleRate))
        }
        return buffer
    }
}

/// 読み上げが作ったバッファ（読み上げのスレッドから足す）。
private final class SynthesizedBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { buffers.append(buffer) }
    }

    var all: [AVAudioPCMBuffer] {
        lock.withLock { buffers }
    }
}

/// 続きを 1 回だけ再開する（終わりの印と時間切れのどちらか先のほう）。
private final class OnceResumer: Sendable {
    private let continuation: Mutex<CheckedContinuation<Bool, Never>?>

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ value: Bool) {
        let pending = continuation.withLock { stored in
            defer { stored = nil }
            return stored
        }
        pending?.resume(returning: value)
    }
}
