import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// 読み取るレシートの画像 1 枚。
///
/// **画像はメモリの中にだけ置き、ファイルにもアルバムにも保存しない。** 読み取りが終わってシートを閉じれば、どこにも残らない
/// （保存するのは、利用者が「記録する」を押したときの記録だけ）。レシートにはカード番号の一部や店の場所が写るため。
struct ReceiptImage: Sendable {
    let cgImage: CGImage
    /// 画像の向き（Vision と Foundation Models にそのまま渡す）。
    let orientation: CGImagePropertyOrientation

    /// 読み取りに使う画像の長い辺の最大の画素数。写真の元の大きさ（4,800 万画素など）のままだとメモリを多く使い、
    /// 文字認識もかえって遅くなるため、レシートの文字が読める大きさまで縮める。
    static let maximumPixelSize = 4_096

    init(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.cgImage = cgImage
        self.orientation = orientation
    }

    /// 書類カメラ（VisionKit）が返したページの画像から作る。
    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
    }

    /// 写真（PhotosPicker が渡したデータ）から作る。向きは画像に焼き込み、大きすぎれば縮める。読めなければ nil。
    ///
    /// データはメモリの上で読み、一時ファイルも作らない。
    init?(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        self.init(cgImage: cgImage, orientation: .up)
    }
}

extension CGImagePropertyOrientation {
    /// UIKit の画像の向きを、Vision と ImageIO の向きに直す。
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// どこからレシートを取り込むか。
enum ReceiptCaptureSource: Hashable, Sendable {
    /// 書類カメラで撮る。
    case camera
    /// 写真（スクリーンショットを含む）から選ぶ。
    case photos
}
