import CoreGraphics
import Foundation
import SaifuLogCore
import Vision

/// レシートの画像の文字を、端末の中で読む（Vision の文字認識）。
///
/// iOS 26 の書類の読み取り（`RecognizeDocumentsRequest`）が日本語に対応していればそれを使い、対応していないか何も読めなければ、
/// 文字の読み取り（`VNRecognizeTextRequest`。日本語と英語、正確さを優先）で読み直す。どちらも端末の中だけで動き、画像を
/// 外へ送らない。読んだ行は、画像の中の位置（左上を原点にした 0〜1）と一緒にコアへ渡し、行のまとめ方と金額の読み方は
/// コア（`ReceiptLineScanner`）に任せる。
enum ReceiptTextRecognizer {
    /// 読む言語（日本語を先に）。
    static let languages = ["ja-JP", "en-US"]

    /// 複数のページ（長いレシートを分けて撮ったもの）の文字を、ページの順に読む。
    ///
    /// ページごとに縦の位置をずらし、別のページの行を 1 行にまとめないようにする。
    @concurrent
    static func lines(in images: [ReceiptImage]) async throws -> [ReceiptTextLine] {
        var result: [ReceiptTextLine] = []
        for (page, image) in images.enumerated() {
            let lines = try await lines(in: image)
            result += lines.map { line in
                guard let frame = line.frame else { return line }
                return ReceiptTextLine(line.text, frame: .init(
                    x: frame.minX, y: frame.minY + Double(page), width: frame.maxX - frame.minX, height: frame.maxY - frame.minY
                ))
            }
        }
        return result
    }

    @concurrent
    static func lines(in image: ReceiptImage) async throws -> [ReceiptTextLine] {
        if let lines = try? await documentLines(in: image), !lines.isEmpty {
            return lines
        }
        return try await textLines(in: image)
    }

    /// 書類の読み取り（iOS 26）。日本語に対応していなければ nil（文字の読み取りで読み直す）。
    private static func documentLines(in image: ReceiptImage) async throws -> [ReceiptTextLine]? {
        var request = RecognizeDocumentsRequest()
        let supported = request.supportedRecognitionLanguages
        let wanted = languages.map { Locale.Language(identifier: $0) }
        let usable = wanted.filter { language in
            supported.contains { $0.languageCode == language.languageCode }
        }
        guard usable.contains(where: { $0.languageCode == .japanese }) else { return nil }
        request.textRecognitionOptions.recognitionLanguages = usable
        request.textRecognitionOptions.useLanguageCorrection = true
        let observations = try await request.perform(on: image.cgImage, orientation: image.orientation)
        return observations.flatMap { $0.document.text.lines }.compactMap { line in
            guard let text = line.topCandidates(1).first?.string else { return nil }
            let box = line.boundingBox
            return ReceiptTextLine(text, frame: frame(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height))
        }
    }

    /// 文字の読み取り（`VNRecognizeTextRequest`）。
    private static func textLines(in image: ReceiptImage) async throws -> [ReceiptTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image.cgImage, orientation: image.orientation)
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return ReceiptTextLine(text, frame: frame(x: box.origin.x, y: box.origin.y, width: box.width, height: box.height))
        }
    }

    /// Vision の位置（左下を原点にした 0〜1）を、上から並べられるよう左上を原点にした位置に直す。
    private static func frame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> ReceiptTextLine.Frame {
        ReceiptTextLine.Frame(x: Double(x), y: Double(1 - y - height), width: Double(width), height: Double(height))
    }
}
