#if canImport(FoundationModels)
import Foundation
import FoundationModels
import SaifuLogCore

/// 端末内 AI（Foundation Models のガイド付き生成）で、レシートの品目の品名とカテゴリを整える。
///
/// - iOS 27 以降で画像の入力に対応したモデル: 画像と、OCR の品目の一覧を渡す（OCR が崩した品名を画像から読ませる）
/// - iOS 26・画像に対応していないモデル: OCR の品目の一覧だけを渡し、品名の整形（半角のカナ・略した名前）とカテゴリだけをさせる
///
/// どちらも、品目ごとに金額の表記も返させるが、記録する額には使わない。番号の取り違えを見つけるために、その品目の OCR の額と
/// 照合するだけ（`ReceiptItemRefinement`）。
struct FoundationModelsReceiptItemRefiner: ReceiptItemRefining {
    let usesImage: Bool

    /// この端末のモデルが画像の入力に対応しているか。iOS 26 では画像を渡せない。
    static var supportsImageInput: Bool {
        if #available(iOS 27, *) {
            return SystemLanguageModel.default.capabilities.contains(.vision)
        }
        return false
    }

    func suggestions(
        for items: [ReceiptItem], storeName: String?, image: ReceiptImage?
    ) async throws -> [ReceiptItemSuggestion] {
        guard !items.isEmpty else { return [] }
        let prompt = Self.prompt(items: items, storeName: storeName)
        // 読み取りのたびに新しいセッションにする（前のレシートの品目を引きずらないため）。
        let generated: GeneratedReceiptItems
        if #available(iOS 27, *), usesImage, let image {
            let session = LanguageModelSession(instructions: Self.instructions + Self.imageInstructions)
            generated = try await session.respond(generating: GeneratedReceiptItems.self) {
                prompt
                Attachment(image.cgImage, orientation: image.orientation)
            }.content
        } else {
            let session = LanguageModelSession(instructions: Self.instructions)
            generated = try await session.respond(to: prompt, generating: GeneratedReceiptItems.self).content
        }
        return generated.items.map { item in
            ReceiptItemSuggestion(number: item.number, name: item.name, categoryName: item.category, amountText: item.amountText)
        }
    }

    /// モデルに渡す品目の一覧。店名はカテゴリの手がかりとして添える（電話番号などは除いたもの）。
    static func prompt(items: [ReceiptItem], storeName: String?) -> String {
        var lines: [String] = []
        if let store = ReceiptSummary.storeLabel(storeName) {
            lines.append("店名: \(store)")
        }
        lines.append("品目の一覧:")
        for (index, item) in items.enumerated() {
            lines.append("\(index + 1). \(item.name) \(YenFormatter.string(from: item.amount))")
        }
        return lines.joined(separator: "\n")
    }

    /// 指示文。具体的な数字や品名の例は書かない（端末内のモデルは、説明に書いた例を入力に無くても写して返すため）。
    static let instructions = """
        あなたは家計簿アプリで、レシートの品目を整えるアシスタントです。
        番号の付いた品目の一覧（文字認識で読んだ品名と金額）が渡されます。品目ごとに、分かりやすい品名とカテゴリを返してください。
        品名は、半角のカナや略した名前を、ふつうの書き方に整えてください。一覧に無い品目は足さないでください。
        金額は、一覧に書かれた金額の表記をそのまま写してください。計算や換算はしないでください。
        """

    static let imageInstructions = """

        レシートの画像も渡します。文字認識の品名が崩れているときは、画像の同じ品目の行を見て品名を読んでください。
        """
}

/// モデルに返させる形（品目の一覧）。
@Generable(description: "レシートの品目の整え")
struct GeneratedReceiptItems {
    @Guide(description: "一覧の品目ごとの整え。一覧の番号ごとに 1 つ")
    var items: [GeneratedReceiptItem]
}

/// モデルに返させる形（品目 1 つ）。
@Generable(description: "レシートの品目 1 つ")
struct GeneratedReceiptItem {
    @Guide(description: "一覧の品目の番号")
    var number: Int

    @Guide(description: "整えた品名。金額・数量・記号は含めない")
    var name: String

    @Guide(description: "品目のカテゴリ", .anyOf(EntryCategory.allCases.map(\.displayName)))
    var category: String

    @Guide(description: "一覧に書かれたその品目の金額の部分を、書かれた文字のまま写す")
    var amountText: String
}
#endif
