import Foundation

/// 金額を「¥1,280」の形で書く。
///
/// `NumberFormatter` の通貨表記は、地域設定によって全角の「￥」になったり「JP¥」になったりする。
/// 家計簿の金額はどの言語でも同じ見た目にしたいので、ここで決め打ちで組み立てる。
public enum YenFormatter {
    /// 「¥1,280」。負の数は「-¥1,280」。
    public static func string(from amount: Int) -> String {
        let body = "¥" + grouped(amount.magnitude)
        return amount < 0 ? "-" + body : body
    }

    /// 符号付きの「+¥250,000」「-¥850」。0 は符号なしの「¥0」。
    /// 収入と支出を同じ一覧に並べるときに、向きが一目で分かるようにするため。
    public static func signedString(from amount: Int) -> String {
        switch amount {
        case 0: string(from: 0)
        case ..<0: string(from: amount)
        default: "+" + string(from: amount)
        }
    }

    /// 3 桁ごとにカンマを入れる。`Int.min` でも桁あふれしないよう、符号なしで受け取る。
    static func grouped(_ value: UInt) -> String {
        let digits = Array(String(value))
        var result = ""
        for (i, digit) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 {
                result.append(",")
            }
            result.append(digit)
        }
        return result
    }
}
