import SaifuLogCore
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

/// 描いた画像の画素を読む（sRGB の RGBA 8 ビットに描き直してから）。返事の行の並べ方のテスト（`RecordedReplyLayoutTests`）で使う。
struct RGBAImage {
    /// 画素の色の見分け。赤なら品目、青なら金額（文字の縁の半透明の画素も、色の偏りで見分ける）。
    enum Pixel: Equatable {
        case title, amount, clear, other
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        let (width, height) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        bytes = pixels
    }

    /// 左上を原点にした画素。
    func pixel(x: Int, y: Int) -> Pixel {
        let offset = (y * width + x) * 4
        let (red, green, blue, alpha) = (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]), Int(bytes[offset + 3]))
        if alpha < 16 { return .clear }
        if red >= 64 && green * 3 < red && blue * 3 < red { return .title }
        if blue >= 64 && red * 3 < blue && green * 3 < blue { return .amount }
        return .other
    }

    /// SwiftUI の部品を幅 `width`・倍率 1 で描く。描いた画像に何も写っていない（すべて透明な）ときは、少し待って描き直す（5 回まで）。
    ///
    /// GitHub の CI のシミュレータ（iOS 27.0）で、全部のテストと一緒に流したときに、大きさは決まっているのに文字が 1 画素も
    /// 描かれていない画像が返り、品目の位置を読めずに落ちたことがある（手元の iOS 27.0 では、単独でも全部のテストと一緒でも
    /// 起きなかった）。何も写っていない画像はどの確かめにも使えないので、描き直す。並べ方の誤りは、何かが写った画像の上で位置が
    /// ずれて現れるので、描き直しでは隠れない。
    @MainActor
    static func render(_ content: some View, width: CGFloat) -> RGBAImage? {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 1
        var image = renderer.cgImage.flatMap(RGBAImage.init)
        for _ in 0..<4 where image?.isBlank ?? true {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            image = renderer.cgImage.flatMap(RGBAImage.init)
        }
        return image
    }

    /// どの画素も透明か（何も描かれていない）。
    var isBlank: Bool {
        stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] < 16 }
    }

    /// その色の画素を囲む四角（左上を原点に、端の画素を含む）。その色が無ければ nil。
    func bounds(of kind: Pixel) -> Bounds? {
        var result: Bounds?
        for y in 0..<height {
            for x in 0..<width where pixel(x: x, y: y) == kind {
                if var found = result {
                    found.minX = min(found.minX, x)
                    found.maxX = max(found.maxX, x)
                    found.minY = min(found.minY, y)
                    found.maxY = max(found.maxY, y)
                    result = found
                } else {
                    result = Bounds(minX: x, minY: y, maxX: x, maxY: y)
                }
            }
        }
        return result
    }

    struct Bounds {
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int

        var height: Int { maxY - minY + 1 }
    }
}
