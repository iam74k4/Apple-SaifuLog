import Foundation

/// Apple Pay（ウォレット）の支払いから記録を作る決め事。ショートカットのオートメーションの「取引」から受け取った金額と店名を使う。
/// docs/design.md §9 の Apple Pay の支払いの決め事。
///
/// 金額はウォレットの値をそのまま使い、AI にも文の読み取りにも通さない（店名の数字（「7-ELEVEN」）を金額と取り違えないため。
/// 数字は AI に扱わせない決まりとも合う）。店名から品目とカテゴリを決める。カテゴリは、作ったカテゴリの名前と覚えたカテゴリ
/// （修正の記憶）→ 店の名前の辞書（レシートと同じ `ReceiptStoreDictionary`）→ キーワード辞書 → 「その他」（返事で聞き返す）の順。
public enum PaymentCapture {
    /// 受け取る通貨（円だけ。家計簿の金額は円の整数で持つので、ほかの通貨は記録しない）。
    public static let currencyCode = "JPY"

    /// 円の金額に直す（1 円未満は四捨五入）。円でない・1 円未満・記録できる上限を超えるなら nil。
    public static func yenAmount(_ amount: Decimal, currencyCode: String) -> Int? {
        guard currencyCode.uppercased() == Self.currencyCode else { return nil }
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        guard rounded >= 1, rounded <= Decimal(EntryAmountInput.maximumAmount) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// 店名を記録の品目の形にそろえる。半角のカナを全角に、全角の英数字と記号を半角にし（NFKC）、空白をまとめ、後ろの支店名
    /// （「新宿店」「ｼﾌﾞﾔﾃﾝ」のように「店」「テン」で終わる語）を外す。
    ///
    /// ウォレットの店名は、カード会社が送る表記（「ｽﾀｰﾊﾞｯｸｽ」「ＳＴＡＲＢＵＣＫＳ」）のことがあるので、辞書と照合できる形にする。
    /// 支店名を外すのは、覚えたカテゴリ（修正の記憶）をほかの店舗にも当てるため（「ユニクロ 新宿店」で覚えると、「ユニクロ 渋谷店」に
    /// 当たらない）。語が 1 つだけのとき（「喫茶店」）は外さない。
    public static func memo(fromMerchant merchant: String) -> String {
        var words = merchant.precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count >= 2, let last = words.last, last.hasSuffix("店") || last.hasSuffix("テン") {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    /// 店名（`memo(fromMerchant:)` でそろえたもの）からカテゴリを決める。
    ///
    /// - Parameters:
    ///   - memory: 覚えたカテゴリ（返事の聞き返しや ⑥ で選んだ店名とカテゴリの組）。いちばん先に見る（利用者が選んだもののため）。
    ///   - catalog: カテゴリの一覧（店名に作ったカテゴリの名前があればそれにし、一覧に無いカテゴリを指す覚えは使わない）。
    public static func category(
        forMerchant memo: String, amount: Int, memory: CategoryMemory, catalog: CategoryCatalog = .builtIn
    ) -> EntryCategory {
        let dictionary = ReceiptStoreDictionary.category(forStoreName: memo) ?? EntryCategory.guess(from: memo)
        let entry = ParsedEntry(amount: amount, category: dictionary, memo: memo)
        return memory.applying(to: [entry], catalog: catalog).first?.category ?? dictionary
    }

    /// 支払いの記録に付ける印（`Entry` の自動で記録したものの印）。同じ支払いを 2 回記録しないために使う。
    public static func occurrenceKey(paymentID: String) -> String {
        "wallet/\(paymentID.lowercased())"
    }
}
