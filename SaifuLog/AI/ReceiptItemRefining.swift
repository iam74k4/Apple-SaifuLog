import Foundation
import SaifuLogCore

/// レシートの品目の品名とカテゴリを、端末内 AI で整える。
///
/// AI には OCR から読んだ品目の一覧（番号・品名・金額）だけを渡す。店名・電話番号・カード番号などのほかの行は渡さない
/// （端末の中の処理でも、要らない情報をモデルに見せないため）。返した金額は照合にだけ使い、記録する額には使わない
/// （`ReceiptItemRefinement`）。
protocol ReceiptItemRefining: Sendable {
    /// 画像も渡すか（iOS 27 以降で、モデルが画像の入力に対応している端末）。
    var usesImage: Bool { get }

    /// 品目ごとの、整えた品名とカテゴリ。
    ///
    /// - Parameter image: レシートの画像（`usesImage` のときだけ）。
    func suggestions(for items: [ReceiptItem], storeName: String?, image: ReceiptImage?) async throws -> [ReceiptItemSuggestion]
}

/// いまの端末で品目を整えられるものを選ぶ。
enum ReceiptItemRefinerFactory {
    /// AI が使えない端末（非対応機種・オフ・モデルの準備中）では nil（キーワード辞書のカテゴリのまま）。
    ///
    /// iOS 27 以降で、モデルが画像の入力（capabilities の vision）に対応していれば画像と文字を、iOS 26 か対応していなければ
    /// 文字だけを渡す。読み取りのたびに呼ぶ（AI の使える・使えないは、設定の変更やモデルのダウンロードで途中から変わるため）。
    static func makeRefiner() -> (any ReceiptItemRefining)? {
        #if canImport(FoundationModels)
        guard FoundationModelsEntryParser.isAvailable else { return nil }
        return FoundationModelsReceiptItemRefiner(usesImage: FoundationModelsReceiptItemRefiner.supportsImageInput)
        #else
        return nil
        #endif
    }
}
