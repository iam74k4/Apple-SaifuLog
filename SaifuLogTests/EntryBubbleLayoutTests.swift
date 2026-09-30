import SaifuLogCore
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

/// タイムラインの吹き出しの、品目と金額の並べ方（`EntryTitleAmountRow`）。
///
/// 品目が折り返すほど長いのに金額を横に並べると、金額が品目の 1 行目の右端に並び、品目の文と金額が続けて読めて
/// しまう（「総額 ¥3,000 / ¥12,000・立替…」）。1 行に収まるときだけ横に並べ、収まらなければ金額を品目の下の行に
/// 置くことを、SwiftUI に測らせた大きさと描いた画像の画素で確かめる。
///
/// 画素で確かめるときは、品目を赤・金額を青で描いて位置を見る（高さだけでは「金額が別の行に下りた」と「品目の
/// 行が 1 行増えた」を見分けられないため）。
@MainActor
struct EntryBubbleLayoutTests {
    /// 撮影用のデモの割り勘の記録と同じ品目（2 行以上に折り返す長さ）。
    static let longMemo = "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）"
    /// 6.1 インチの iPhone（幅 393pt）の吹き出しで、品目と金額の行に使える幅のおよその値。
    static let rowWidth: CGFloat = 245

    @Test("品目と金額が 1 行に収まれば横に並べ、収まらなければ縦に積む（大きさの決まった部品で）")
    func stacksOnlyWhenTheRowDoesNotFit() {
        // 100 + 8 + 60 = 168 ≤ 200 なので横に並ぶ（高さは 1 行分）。
        let fits = Self.size(of: Self.standInRow(titleWidth: 100), width: 200)
        #expect(fits.height == 20)
        // 150 + 8 + 60 = 218 > 200 なので縦に積む（品目 + 間 + 金額）。
        let stacked = Self.size(of: Self.standInRow(titleWidth: 150), width: 200)
        #expect(stacked.height == 20 + EntryTitleAmountRow<Color, Color>.stackedSpacing + 20)
    }

    @Test("長い品目は折り返し、金額は品目の下の行の右端に置く")
    func longMemoPutsTheAmountOnItsOwnLine() throws {
        let image = try #require(Self.render(Self.coloredRow(memo: Self.longMemo, amount: "¥3,000"), width: Self.rowWidth))
        let memo = try #require(image.bounds(of: .title))
        let amount = try #require(image.bounds(of: .amount))
        // 前提: 品目が 2 行以上に折り返している（金額の行の高さの倍を超える）。
        #expect(memo.height > amount.height * 2)
        // 金額は品目のどの行とも重ならず、その下にある。
        #expect(amount.minY > memo.maxY)
        // 金額は右寄せ（行の右端）。
        #expect(amount.maxX >= image.width - 4)
    }

    @Test("短い品目は金額と 1 行に並べる（金額は品目の右）")
    func shortMemoStaysOnOneLine() throws {
        let image = try #require(Self.render(Self.coloredRow(memo: "ランチ", amount: "¥850"), width: Self.rowWidth))
        let memo = try #require(image.bounds(of: .title))
        let amount = try #require(image.bounds(of: .amount))
        #expect(amount.minY < memo.maxY && memo.minY < amount.maxY)
        #expect(amount.minX > memo.maxX)
    }

    /// 自分の記録と家計の記録（記録した人の名前つき）の両方の吹き出しで確かめる。
    @Test("吹き出しの長い品目は金額の幅によらず同じ幅で折り返す（金額が品目の行に並ばない）", arguments: [nil, "はなこ"])
    func bubbleWrapsTheMemoIndependentlyOfTheAmount(recorderName: String?) {
        // 金額を品目の横に並べていれば、金額が長いほど品目の幅が狭まって行が増え、吹き出しが高くなる。
        let narrowAmount = Self.size(of: Self.bubble(amount: 3_000, recorderName: recorderName), width: 361)
        let wideAmount = Self.size(of: Self.bubble(amount: 3_000_000_000, recorderName: recorderName), width: 361)
        #expect(narrowAmount.height == wideAmount.height)
    }

    // MARK: - 部品

    private struct Record: LedgerEntryDisplaying {
        var amount: Int
        var isIncome = false
        var category = EntryCategory.food
        var spentAt = TestSupport.date(2026, 9, 12, hour: 19)
        var memo: String
    }

    private static func bubble(amount: Int, recorderName: String?) -> some View {
        EntryBubble(
            entry: Record(amount: amount, memo: longMemo), today: TestSupport.now, edit: {}, requestDelete: {},
            recorderName: recorderName
        )
    }

    /// 品目を赤、金額を青で描いた行（金額は吹き出しと同じ文字の形）。
    private static func coloredRow(memo: String, amount: String) -> some View {
        EntryTitleAmountRow {
            Text(verbatim: memo)
                .foregroundStyle(Color(red: 1, green: 0, blue: 0))
        } amount: {
            Text(verbatim: amount)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Color(red: 0, green: 0, blue: 1))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// 品目の代わりに赤、金額の代わりに青の、高さ 20 の四角を並べた行。
    private static func standInRow(titleWidth: CGFloat) -> some View {
        EntryTitleAmountRow {
            Color(red: 1, green: 0, blue: 0).frame(width: titleWidth, height: 20)
        } amount: {
            Color(red: 0, green: 0, blue: 1).frame(width: 60, height: 20)
        }
    }

    /// 文字の大きさと言語を決めて、幅 `width` を与えたときの大きさを SwiftUI に測らせる。
    private static func size(of view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: fixedEnvironment(view))
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    private static func render(_ view: some View, width: CGFloat) -> RGBAImage? {
        let renderer = ImageRenderer(content: fixedEnvironment(view))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 1
        return renderer.cgImage.flatMap(RGBAImage.init)
    }

    private static func fixedEnvironment(_ view: some View) -> some View {
        view
            .environment(\.dynamicTypeSize, .large)
            .environment(\.locale, Locale(identifier: "ja_JP"))
            .environment(\.calendar, TestSupport.calendar)
    }
}

/// 描いた画像の画素を読む（sRGB の RGBA 8 ビットに描き直してから）。返事の行の並べ方のテスト（`RecordedReplyLayoutTests`）でも使う。
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
