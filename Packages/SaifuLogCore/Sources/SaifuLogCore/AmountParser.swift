import Foundation

/// 金額の表記を円の整数に直す。
///
/// AI には金額を「入力に書かれたとおり」に抜き出させ、数への換算はここで行う。
/// 「25万」を 250000 にするような換算も、小さなモデルには間違えやすい計算のうちだから。
/// AI が返した金額が入力に書かれているかの突き合わせは `ExtractedEntry` が行う。
public enum AmountParser {
    /// 「850」「¥1,280」「１万２千円」「25万」「1万2千500円」「500×3」を円の整数にする。読めなければ nil。
    /// 数字が複数あるときは最後のものを採る（ルールベースの解析と同じ読み方）。
    /// 「-500」はマイナスを外した 500 を返す（返金かどうかは入力の側の表記で決める）。
    public static func yen(from text: String) -> Int? {
        // 金額だけを見るので、日付の解釈の基準はいつでもよい。
        EntryScan(TextNormalizer.normalize(text), now: Date(), calendar: Calendar(identifier: .gregorian))
            .amounts.last?.value
    }
}
