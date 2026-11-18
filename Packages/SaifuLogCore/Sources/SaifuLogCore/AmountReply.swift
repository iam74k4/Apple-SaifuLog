import Foundation

/// 金額を聞き返した後の返事（「850」「850円」「¥1,200」「1.2万」「850です」）から、金額の表記を取り出す。
///
/// 金額の無い文（「ランチ」）を送ると、アプリは「いくらでしたか？」と聞き返す。次の文が金額だけなら、前の文の後ろに金額を
/// 足して（「ランチ 850」）ふつうの送信と同じように読む。前の文とつなげて読むので、日付・割り勘・払い方の言葉は前の文の
/// ものがそのまま効く。金額のほかに品目や日付のある文は、新しい記録として読む（つなげると、別の記録のつもりの文が
/// 前の文の品目で記録されるため）。
public enum AmountReply {
    /// 金額だけの返事なら、前の文に足す金額の表記（正規化した文の、金額の部分。「¥1,200」「1.2万」）を返す。金額だけでなければ nil。
    ///
    /// 金額だけとみなすのは、金額がちょうど 1 つで、ほかには返事の言い回し（「です」「くらい」「約」など）と記号しか無いとき。
    /// マイナスの額（返金）・1 人分の額・おつりやポイントなどの添えた額・0 円・日付・人数は、前の文に足すと意味が変わるので
    /// 金額だけとみなさない。
    public static func amountText(in text: String) -> String? {
        let normalized = TextNormalizer.normalize(text)
        // 金額だけを見るので、日付の解釈の基準はいつでもよい（日付が書かれていれば、その時点で金額だけではない）。
        let scan = EntryScan(normalized, now: Date(), calendar: Calendar(identifier: .gregorian))
        guard scan.amounts.count == 1, let amount = scan.amounts.first,
              amount.role == .primary || amount.role == .taxIncluded,
              !amount.isNegative, !amount.isPerPerson, amount.value > 0,
              scan.dates.isEmpty, scan.people.isEmpty
        else { return nil }
        let rest = scan.chars.indices
            .filter { !amount.range.contains($0) }
            .map { scan.chars[$0] }
        guard isFiller(String(rest)) else { return nil }
        return String(scan.chars[amount.range]).trimmingCharacters(in: .whitespaces)
    }

    /// 金額の前に付ける言い回し（「約850」「だいたい850」）。
    private static let prefixes = ["だいたい", "大体", "およそ", "たぶん", "多分", "約"]
    /// 金額の後ろに付ける言い回し（「850くらいでした」）。長いものから外す（「でした」を「で」と「した」に分けないため）。
    private static let suffixes = [
        "円", "くらい", "ぐらい", "位", "ほど", "程", "でした", "だった", "です", "だよ", "かな", "だね",
    ].sorted { $0.count > $1.count }

    /// 金額を除いた残りが、返事の言い回しと記号だけか。
    private static func isFiller(_ text: String) -> Bool {
        var rest = String(text.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) && !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar) && scalar != "ー" && scalar != "〜"
        })
        if let prefix = prefixes.first(where: { rest.hasPrefix($0) }) {
            rest.removeFirst(prefix.count)
        }
        // 「くらいでした」のように重ねて付けることがあるので、外せなくなるまで外す。
        while let suffix = suffixes.first(where: { rest.hasSuffix($0) }) {
            rest.removeLast(suffix.count)
        }
        return rest.isEmpty
    }
}
