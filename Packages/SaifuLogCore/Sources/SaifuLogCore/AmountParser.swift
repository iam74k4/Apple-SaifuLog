import Foundation

/// 金額の表記を円の整数に直す。
///
/// AI には金額を「入力に書かれたとおり」に抜き出させ、数への換算はここで行う。
/// 「25万」を 250000 にするような換算も、小さなモデルには間違えやすい計算のうちだから。
public enum AmountParser {
    /// 「850」「¥1,280」「１万２千円」「25万」を円の整数にする。読めなければ nil。
    /// 数字が複数あるときは最後のものを採る（ルールベースの解析と同じ読み方）。
    public static func yen(from text: String) -> Int? {
        scan(text).amounts.last?.value
    }

    /// AI が抜き出した金額が、入力文に書かれた金額のどれかと一致するか。
    ///
    /// 一致しなければ、モデルが数字を作ったか、割り算などの計算をしてしまったとみなす。
    /// その場合は AI の結果を捨ててルールベースで読み直す。
    public static func isGrounded(_ amountText: String, in input: String) -> Bool {
        guard let value = yen(from: amountText) else { return false }
        return scan(input).amounts.contains { $0.value == value }
    }

    private static func scan(_ text: String) -> EntryScan {
        // 金額だけを見るので、日付の解釈の基準はいつでもよい。
        EntryScan(TextNormalizer.normalize(text), now: Date(), calendar: Calendar(identifier: .gregorian))
    }
}
