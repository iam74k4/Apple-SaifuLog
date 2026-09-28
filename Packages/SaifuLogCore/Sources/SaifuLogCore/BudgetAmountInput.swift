import Foundation

/// 予算の金額の入力欄の文字の扱い（「150,000」のように 3 桁ごとにカンマを入れて見せる）。
///
/// 入力欄は数字のキーボードだが、貼り付けや外付けのキーボードで数字以外や全角の数字も入りうる。
/// 読み取りと見せ方をここにまとめ、画面ごとにそろえ方が変わらないようにする。
public enum BudgetAmountInput {
    /// 入力できる桁数（¥99,999,999 まで）。月の予算には十分で、合計の計算で桁があふれない。
    public static let maximumDigits = String(BudgetPlan.maximumAmount).count

    /// 入力欄の文字から金額を読む。数字が 1 つも無ければ nil。
    public static func amount(from text: String) -> Int? {
        let digits = digits(in: text)
        return digits.isEmpty ? nil : Int(digits)
    }

    /// 入力欄に見せる形にそろえる。数字以外を除き、先頭の 0 を落とし、3 桁ごとにカンマを入れる。
    ///
    /// 桁数を超えた分は捨てる（打った数字の後ろを捨てる。前を捨てると、打ったつもりの額と桁がずれるため）。
    public static func formatted(_ text: String) -> String {
        guard let amount = amount(from: text) else { return "" }
        return YenFormatter.grouped(UInt(amount))
    }

    /// 金額を入力欄の形にする。0 以下（設定なし）は空欄。
    public static func text(for amount: Int) -> String {
        amount > 0 ? formatted(String(min(amount, BudgetPlan.maximumAmount))) : ""
    }

    /// 半角と全角の数字だけを半角にして取り出し、先頭の 0 を落として桁数で切る。
    static func digits(in text: String) -> String {
        var digits = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39:
                digits.unicodeScalars.append(scalar)
            case 0xFF10...0xFF19:
                // 全角の数字は、半角から 0xFEE0 ずれた位置にある（TextNormalizer と同じ）。
                digits.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            default:
                continue
            }
        }
        let significant = digits.drop { $0 == "0" }
        // すべて 0 なら「0」を 1 つ残す（打った 0 が消えて、何も打っていないように見えないように）。
        if significant.isEmpty { return digits.isEmpty ? "" : "0" }
        return String(significant.prefix(maximumDigits))
    }
}
