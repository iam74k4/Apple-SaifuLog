import Foundation
import SaifuLogCore

/// レシートの画像を読み取る流れ（文字認識 → コアの読み取り → 端末内 AI の品名とカテゴリの整え）。
///
/// 文字認識と AI は差し替えられるようにし、SaifuLogTests では決めた文字や偽物の AI で確かめる（シミュレータにはカメラも
/// Apple Intelligence も無いため）。
struct ReceiptReader: Sendable {
    /// 画像の文字を読む。既定は Vision（`ReceiptTextRecognizer`）。
    var recognize: @Sendable ([ReceiptImage]) async throws -> [ReceiptTextLine] = { try await ReceiptTextRecognizer.lines(in: $0) }
    /// 品名とカテゴリを整える AI を選ぶ。AI が使えなければ nil（キーワード辞書のカテゴリのまま）。読み取りのたびに呼ぶ
    /// （AI の使える・使えないは途中から変わるため）。
    var makeRefiner: @Sendable () -> (any ReceiptItemRefining)? = { ReceiptItemRefinerFactory.makeRefiner() }

    /// 画像を読み取る。画像が無い（写真や撮った画像を読み込めなかった）・文字が無い・品目も合計も無ければ、読めなかった理由を返す。
    ///
    /// **金額はコアが OCR の文字から読んだ額だけを使う。** AI には品名とカテゴリだけを整えさせ、AI の返した金額は
    /// その品目の額との照合にだけ使う（`ReceiptItemRefinement`）。AI が失敗したら、辞書のカテゴリのまま出す。
    ///
    /// - Parameters:
    ///   - now: 日付を「何日前か」にする基準（読み取りを始めた瞬間）。
    ///   - calendar: 日付の区切り（画面の暦）。
    @concurrent
    func read(_ images: [ReceiptImage], now: Date, calendar: Calendar) async -> ReceiptReading {
        guard !images.isEmpty else { return .unreadable(.imageUnavailable) }
        let lines = (try? await recognize(images)) ?? []
        var scan = ReceiptLineScanner.scan(lines, now: now, calendar: calendar)
        if scan.hasNoText { return .unreadable(.noText) }
        if scan.hasNoAmounts { return .unreadable(.noAmounts) }
        if !scan.items.isEmpty, let refiner = makeRefiner() {
            let image = refiner.usesImage ? images.first : nil
            if let suggestions = try? await refiner.suggestions(for: scan.items, storeName: scan.storeName, image: image) {
                scan.items = ReceiptItemRefinement.apply(suggestions, to: scan.items)
            }
        }
        return .read(scan)
    }
}

/// 読み取りの結果。
enum ReceiptReading: Sendable, Equatable {
    case read(ReceiptScan)
    case unreadable(ReceiptUnreadableReason)
}
