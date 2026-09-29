// App Store のスクリーンショットの画像を整える・確かめる（scripts/app-store-screenshots.sh が使う）。
//
//   xcrun swift scripts/screenshot-image.swift flatten <PNG>...   透過の層（アルファチャンネル）を外して、同じ場所に書き直す
//   xcrun swift scripts/screenshot-image.swift has-island <PNG>   Dynamic Island の黒い形が写っていれば終了コード 0、無ければ 1
//
// flatten: App Store Connect は、透過の層のあるスクリーンショットを受け付けない（アップロードの段階で弾かれる）。
// `xcrun simctl io screenshot` の PNG は、中身が不透明でも透過の層を持つので、白の地に描き直して層を外す。
//
// has-island: シミュレータのスクリーンショットには、ふだんは Dynamic Island が写らないが、ときどき黒い形が写り込む
// （iOS 26.4 のシミュレータで、シートを出した画面で見た）。ライトの外観で撮るので、画面の上の真ん中（状態バーの高さ）が
// ほぼ黒なら写り込んだとみなし、撮り直させる。
//
// ImageIO と CoreGraphics だけを使う（ほかの道具を入れずに済むように）。
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(2)
}

func loadImage(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { fail("\(path) を読めませんでした。") }
    return image
}

/// 透過の層の無い sRGB の画像に描き直す（地は白）。
func opaqueContext(for image: CGImage) -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
              space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          )
    else { fail("描き直す場所を用意できませんでした。") }
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(rect)
    context.draw(image, in: rect)
    return context
}

func flatten(_ path: String) {
    let context = opaqueContext(for: loadImage(path))
    let url = URL(fileURLWithPath: path)
    guard let flattened = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("\(path) を書き直せませんでした。") }
    CGImageDestinationAddImage(destination, flattened, nil)
    guard CGImageDestinationFinalize(destination) else { fail("\(path) を書き出せませんでした。") }
}

/// 画面の上の真ん中（幅の 42〜58%、高さの 1.5〜4.5%。1320 × 2868 なら x 554〜766、y 43〜129）の明るさの平均（0〜255）。
func islandAreaBrightness(_ path: String) -> Double {
    let image = loadImage(path)
    let context = opaqueContext(for: image)
    guard let data = context.data else { fail("\(path) の画素を読めませんでした。") }
    let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * image.height)
    // CGContext の画素は上の行から並ぶ（描いた画像の上が、メモリの先頭の行になる）。
    let xs = Int(Double(image.width) * 0.42)..<Int(Double(image.width) * 0.58)
    let ys = Int(Double(image.height) * 0.015)..<Int(Double(image.height) * 0.045)
    var total = 0.0
    for y in ys {
        for x in xs {
            let offset = y * context.bytesPerRow + x * 4
            total += (Double(pixels[offset]) + Double(pixels[offset + 1]) + Double(pixels[offset + 2])) / 3
        }
    }
    return total / Double(xs.count * ys.count)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "flatten" where arguments.count > 1:
    for path in arguments.dropFirst() { flatten(path) }
case "has-island" where arguments.count == 2:
    exit(islandAreaBrightness(arguments[1]) < 40 ? 0 : 1)
default:
    fail("使い方: screenshot-image.swift flatten <PNG>... / screenshot-image.swift has-island <PNG>")
}
