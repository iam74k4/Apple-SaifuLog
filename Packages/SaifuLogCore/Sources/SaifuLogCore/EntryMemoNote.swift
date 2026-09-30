import Foundation

/// 解析が記録のメモに書き足した説明（割り勘の内訳・1 人分として書かれた額であること）を、品目と分けて読み戻したもの。
///
/// 解析は、割り勘や 1 人分の額を記録したとき、品目の後ろに全角の括弧で説明を書き足してメモに保存する
/// （「焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）」「焼肉（4人で割り勘・1人分）」、品目が無ければ説明だけ。
/// `ParsedEntry.assemble`）。保存する形と CSV の書き出しはそのまま（メモ 1 つに収める）にし、ホームの返事の行では品目（「焼肉」）
/// だけを見出しにして、説明は行の下の文にする。そのために、書き足した形をここで読み戻す。書く側（`memo(item:note:)` と
/// `perPersonNote(splitCount:)`）もここに置き、`assemble` と読み戻しが同じ書き方を使う。
///
/// 読み戻すのは、コアが書く形そのものだけ。読んだ品目と説明から書く形を作り直し、メモと 1 文字も違わないときだけ受け入れる。
/// 桁区切りや人数の書き方が違う・半角の括弧・立替の額が総額と人数から出る額と合わない・記録の金額が割った額と合わない（直す
/// シートで金額だけを直した）・収入に直した記録は受け入れない（呼び出し側はメモをそのまま出す）。利用者が直したメモを、解析が
/// 書いたものと取り違えて言い換えないため。入力の文の全角の括弧は解析の前に半角にそろえる（`TextNormalizer`）ので、全角の
/// 括弧で囲んだ説明が品目の中から出てくることはない。
public struct EntryMemoNote: Sendable, Hashable {
    /// 書き足した説明の種類。
    public enum Kind: Sendable, Hashable {
        /// 割り勘で割った（総額・人数・立て替えた額は `BillSplit`）。記録の金額は `BillSplit.share`。
        case split(BillSplit)
        /// 1 人分として書かれた額を、割らずにそのまま記録した。割り勘の人数が書かれていれば、その人数（2 以上）。
        case perPerson(splitCount: Int?)
    }

    /// 品目（書き足した説明を除いたメモ）。品目の無い記録（説明だけのメモ）では空。
    public let item: String
    public let kind: Kind

    /// メモが、解析の書き足した形そのものなら、品目と説明に分けて読む。そうでなければ nil（メモをそのまま出す）。
    ///
    /// - Parameters:
    ///   - amount: 記録の金額。割り勘の説明は、割った額（`BillSplit.share`）と同じときだけ受け入れる。
    ///   - isIncome: 収入なら受け入れない（解析は収入に説明を書き足さない）。
    public init?(memo: String, amount: Int, isIncome: Bool) {
        // たいていのメモは説明を持たないので、書き足した形の最後の文字（括弧・「1人分」の「分」・総額の数字）で先に外す
        // （ホームは返事の行を描くたびに読むため）。
        guard !isIncome, let last = memo.last, last == "）" || last == "分" || last.isASCIIDigit else { return nil }
        let item: String
        let note: Substring
        if last == "）", let open = memo.lastIndex(of: "（") {
            item = String(memo[..<open])
            note = memo[memo.index(after: open)..<memo.index(before: memo.endIndex)]
        } else {
            item = ""
            note = memo[...]
        }
        // 品目は前後の空白を除いてから書き足す（`assemble`）ので、空白の残る品目は解析の書いた形ではない。
        guard item == item.trimmingCharacters(in: .whitespacesAndNewlines),
              let kind = Self.kind(of: note, amount: amount),
              Self.memo(item: item, note: String(note)) == memo
        else { return nil }
        self.item = item
        self.kind = kind
    }

    /// 説明の部分を読む。書く形そのものでなければ nil。
    private static func kind(of note: Substring, amount: Int) -> Kind? {
        if note == perPersonNote(splitCount: 1) { return .perPerson(splitCount: nil) }
        guard let joint = note.range(of: "人で割り勘・"), let count = Int(note[..<joint.lowerBound]) else { return nil }
        let rest = note[joint.upperBound...]
        if rest == "1人分" {
            guard count >= 2, perPersonNote(splitCount: count) == note else { return nil }
            return .perPerson(splitCount: count)
        }
        // 「総額 ¥12,000・立替 ¥9,000」。総額と人数から割り勘を作り直し、立替の額と書き方ごと同じ説明になるかで確かめる。
        guard rest.hasPrefix(totalLabel), let advance = rest.range(of: advanceLabel),
              let total = yen(rest[rest.index(rest.startIndex, offsetBy: totalLabel.count)..<advance.lowerBound]),
              let split = BillSplit(total: total, count: count),
              split.note == note, split.share == amount
        else { return nil }
        return .split(split)
    }

    /// 「¥12,000」の額。桁区切りの位置は確かめない（説明を作り直して比べるときに確かめる）。
    private static func yen(_ text: Substring) -> Int? {
        guard text.hasPrefix("¥") else { return nil }
        let digits = text.dropFirst().filter { $0 != "," }
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(digits)
    }

    private static let totalLabel = "総額 "
    private static let advanceLabel = "・立替 "

    // MARK: - 書く側（`ParsedEntry.assemble`）

    /// 品目に説明を書き足したメモ（「焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）」）。品目が無ければ説明だけ。
    static func memo(item: String, note: String) -> String {
        item.isEmpty ? note : "\(item)（\(note)）"
    }

    /// 1 人分として書かれた額の説明（「4人で割り勘・1人分」。割り勘の人数が書かれていなければ「1人分」）。
    static func perPersonNote(splitCount: Int) -> String {
        splitCount >= 2 ? "\(splitCount)人で割り勘・1人分" : "1人分"
    }
}
