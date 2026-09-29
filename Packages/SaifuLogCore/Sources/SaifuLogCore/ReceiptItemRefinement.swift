import Foundation

/// 端末内 AI が返した、品目 1 つの読み（品名とカテゴリの整え）。
public struct ReceiptItemSuggestion: Sendable, Hashable {
    /// 品目の番号（1 から。AI に渡した一覧の番号）。
    public var number: Int
    /// 整えた品名。
    public var name: String
    /// カテゴリの表示名（`EntryCategory.displayName`）。
    public var categoryName: String
    /// AI が読んだ、その品目の金額の表記。照合にだけ使い、記録する額には使わない。
    public var amountText: String

    public init(number: Int, name: String, categoryName: String, amountText: String) {
        self.number = number
        self.name = name
        self.categoryName = categoryName
        self.amountText = amountText
    }
}

/// AI の読みを、OCR から読んだ品目に当てはめる。
///
/// **金額はいつも OCR の文字からコードが読んだ額を使い、AI の返した金額は使わない。** AI の金額は、その番号の品目の
/// 額と照合するためだけに使い、合わなければ（番号を取り違えた・別の行を読んだ・作った）その品目の AI の読みを捨てて、
/// OCR の品名とキーワード辞書のカテゴリのままにする。品目を足したり消したりもしない（AI の一覧に無い品目はそのまま、
/// 一覧にしか無い品目は捨てる）。端末内のモデルは小さく、数字を読み違えたり作ったりするため。
public enum ReceiptItemRefinement {
    /// 品名として受け付ける最大の文字数。
    public static let maximumNameLength = 40

    public static func apply(_ suggestions: [ReceiptItemSuggestion], to items: [ReceiptItem]) -> [ReceiptItem] {
        var result = items
        var used = Set<Int>()
        for suggestion in suggestions {
            let index = suggestion.number - 1
            guard items.indices.contains(index), !used.contains(index) else { continue }
            used.insert(index)
            let item = items[index]
            guard let amount = AmountParser.yen(from: suggestion.amountText),
                  [item.amount, item.netAmount, item.unitPrice].contains(amount)
            else { continue }
            if let name = acceptedName(suggestion.name) { result[index].name = name }
            if let category = EntryCategory(displayName: suggestion.categoryName) { result[index].category = category }
        }
        return result
    }

    /// AI の品名を受け付けるか。金額や印を除いても文字が残り、長すぎなければ、整えた品名を返す。
    static func acceptedName(_ text: String) -> String? {
        let normalized = ReceiptLineScanner.normalize(text)
        // 品名に金額を付けて返したとき（「牛乳 198」）は、金額を除く。
        let trailing = ReceiptLineScanner.trailing(in: normalized)
        let name = ReceiptLineScanner.cleanedName(trailing.amount == nil ? normalized : trailing.body).name
        guard ReceiptLineScanner.hasLetters(name), name.count <= maximumNameLength else { return nil }
        return name
    }
}
