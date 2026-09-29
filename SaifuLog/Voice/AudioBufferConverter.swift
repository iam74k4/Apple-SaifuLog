@preconcurrency import AVFoundation
import Foundation

/// マイクの音声（機種やつないだ機器で形式が違う）を、書き起こしが受け取る形式に変える。
///
/// SpeechAnalyzer は、受け取った音声の標本化の周波数や形式を自分では変えない（時刻を標本単位で正しく保つため。Apple の説明の
/// bestAvailableAudioFormat）。そのため、渡す前に `SpeechAnalyzer.bestAvailableAudioFormat` の形式に変える。
/// iOS 27 には同じことをする `AnalyzerInputConverter` があるが、iOS 26 でも動くよう AVAudioConverter で行う。
///
/// 録音のタップ（音声のスレッド）からだけ、1 つずつ順に呼ぶ。AVAudioConverter はスレッドをまたいで使えないので、
/// 呼ぶ側が同時に呼ばないことを約束する（そのため `@unchecked Sendable`）。
final class AudioBufferConverter: @unchecked Sendable {
    enum ConversionError: Error {
        case cannotCreateConverter
        case cannotCreateBuffer
        case failed
    }

    let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    /// 形式を変えた新しいバッファを返す。形式が同じなら写しを返す（タップのバッファは、呼び出しから戻った後に使い回されうるため）。
    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if buffer.format == outputFormat {
            return try Self.copy(buffer)
        }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
            // 最初の数標本の質より、時刻がずれないことを優先する（書き起こしの結果の時刻を音声と合わせるため）。
            converter?.primeMethod = .none
        }
        guard let converter else { throw ConversionError.cannotCreateConverter }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: max(capacity, 1)) else {
            throw ConversionError.cannotCreateBuffer
        }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            // 1 回の呼び出しで渡すのはこのバッファだけ。渡し終えたら「いまは無い」と答え、次のタップを待つ。
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { throw ConversionError.failed }
        return output
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: max(buffer.frameLength, 1)) else {
            throw ConversionError.cannotCreateBuffer
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }
}

/// マイクの音の大きさ（表示の目安）。
enum AudioLevel {
    /// バッファの音の大きさを 0〜1 にする。-50 dBFS 以下は 0、0 dBFS は 1。
    ///
    /// 声で入力しているあいだ、聞こえていることを目で確かめられるようにする目安で、自動で止める判断には使わない
    /// （止める判断は書き起こしの文の変化で行う。`VoiceListeningLimit`）。
    static func normalized(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        return normalized(rootMeanSquare: Double(meanSquare.squareRoot()))
    }

    static func normalized(rootMeanSquare: Double) -> Double {
        guard rootMeanSquare > 0 else { return 0 }
        let decibels = 20 * log10(rootMeanSquare)
        return min(max((decibels + floor) / floor, 0), 1)
    }

    /// 0 とみなす大きさ（dBFS の負の値の大きさ）。
    private static let floor = 50.0
}
