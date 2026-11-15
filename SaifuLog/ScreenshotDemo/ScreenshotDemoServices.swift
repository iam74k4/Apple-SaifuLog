#if DEBUG
import CoreGraphics
import Foundation
import SaifuLogCore

// 撮影用のデモ（`ScreenshotDemo`）で、端末によって変わるものの代わりに使う決まった中身。実際のアプリが出しうる中身にする
// （レシートは文字認識の結果として読める文字）。

/// レシートの読み取りの画面で使う、文字認識の結果の代わり。架空の店（実在の店名・住所・電話番号は書かない）の内税のレシート。
enum ScreenshotDemoReceipt {
    /// 店名。架空の名前にする（実在の店と取り違えられないように）。
    static let storeName = "サイフマート 中央店"
    /// レシートの合計（品目の合計と同じ）。
    static let total = 1_766

    /// 文字認識の結果の行（デモの「いま」の日付と 18:32 の時刻を入れる）。軽減税率の品目には「※」を付ける。
    static func lines(now: Date, calendar: Calendar) -> [ReceiptTextLine] {
        // レシートは西暦で印字されるので、端末の暦（和暦など）によらず西暦の年月日で書く（時間帯は端末の暦のまま）。
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let parts = gregorian.dateComponents([.year, .month, .day, .weekday], from: now)
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        let weekday = weekdays[((parts.weekday ?? 1) - 1) % weekdays.count]
        let date = String(format: "%04d年%02d月%02d日(%@) 18:32", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, weekday)
        return [
            storeName,
            date,
            "※牛乳 ￥198",
            "※食パン ￥158",
            "※カット野菜 ￥128",
            "※卵 10個入 ￥258",
            "※鶏むね肉 ￥398",
            "洗剤 ￥328",
            "ティッシュ ￥298",
            "小計 ￥1,766",
            "(8%対象 ￥1,140 内税 ￥84)",
            "(10%対象 ￥626 内税 ￥56)",
            "合計 ￥1,766",
            "お預り ￥2,000",
            "お釣り ￥234",
        ].map { ReceiptTextLine($0) }
    }

    /// 読み取りに渡す画像（中身は使わない。読み取りは画像が無いと始まらないため、1 画素の白い画像を渡す）。
    static func image() -> ReceiptImage {
        let context = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let cgImage = context?.makeImage() else {
            preconditionFailure("1 画素の画像を作れませんでした")
        }
        return ReceiptImage(cgImage: cgImage)
    }
}
#endif
