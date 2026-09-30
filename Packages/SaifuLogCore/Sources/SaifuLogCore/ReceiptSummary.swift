import Foundation

/// レシートから記録するときに残す店名の決め方。
///
/// 記録の「元の文」（`Entry.originalText`）には、レシートの OCR の全文ではなく、店名と合計だけの短い要約を入れる
/// （アプリは「レシート: 店名 合計 ¥…」の形にする）。全文には電話番号・住所・カード番号の一部・レジの担当者の名前なども
/// 含まれ、保存すると CSV の書き出しや iCloud の同期に乗って、利用者の個人情報を増やすため。
public enum ReceiptSummary {
    /// 要約に入れる店名の最大の文字数。
    public static let maximumStoreNameLength = 24

    /// 要約とメモに入れる店名。電話番号やカード番号のような 4 桁以上の数字の並び、「TEL」から後ろ、記号の並びを除き、
    /// 短くする。何も残らなければ nil。
    public static func storeLabel(_ name: String?) -> String? {
        guard let name else { return nil }
        let cleaned = cleanedStoreName(name)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// 店名の行から、店名でない部分（電話番号・長い数字・記号の並び）を除く。
    static func cleanedStoreName(_ text: String) -> String {
        var name = TextNormalizer.normalize(text)
        // 「TEL」「電話」から後ろは連絡先。
        for marker in ["TEL", "Tel", "tel", "電話", "℡", "FAX"] {
            if let range = name.range(of: marker) { name = String(name[..<range.lowerBound]) }
        }
        // 4 桁以上の数字の並び（「-」や空白でつないだものも）は、電話番号・カード番号・登録番号・郵便番号。
        name = name.replacingOccurrences(of: #"[T#*xX]?\d[\d\-\s*]{2,}\d"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"[*#=\-_~]{2,}"#, with: " ", options: .regularExpression)
        // 端の「·」（U+00B7）は、品名と同じく OCR が「¥」を読み違えた点か、つなぎの点（`ReceiptLineScanner.nameEdgeSeparators`）。
        name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".…・·:：-=_~〜|/")))
        guard name.contains(where: \.isLetter) else { return "" }
        if name.count > maximumStoreNameLength {
            name = String(name.prefix(maximumStoreNameLength)).trimmingCharacters(in: .whitespaces)
        }
        return name
    }
}
