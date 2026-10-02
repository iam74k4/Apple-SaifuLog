import Foundation

/// よく使うひとことの候補を作るのに読む、記録の最小の形。
///
/// 保存用のモデル（SwiftData）をコアに持ち込まずに読むための境目。アプリ側のモデルがこれに準拠する。
public protocol QuickPhraseRecord {
    var amount: Int { get }
    var isIncome: Bool { get }
    var memo: String { get }
    /// 記録した日時。新しい記録の書き方と金額を候補に使う。
    var createdAt: Date { get }
}

/// よく使うひとこと（入力欄の上に並べる候補）の 1 つ。押すと入力欄に「ランチ 850」の形で入る（送るのは利用者）。
public struct QuickPhrase: Sendable, Hashable, Identifiable {
    /// そろえた品目（`CategoryMemory.key(for:)`）。同じ品目の記録をまとめるのに使う。
    public let key: String
    /// 見せる品目（いちばん新しい記録の書き方）。
    public let item: String
    /// いちばん新しい記録の金額。
    public let amount: Int
    /// いちばん新しい記録が収入か。
    public let isIncome: Bool
    /// 読んだ記録の中で、その品目を記録した回数。
    public let count: Int
    /// いちばん新しい記録の記録した日時。
    public let lastRecordedAt: Date

    public var id: String { key }

    public init(key: String, item: String, amount: Int, isIncome: Bool, count: Int, lastRecordedAt: Date) {
        self.key = key
        self.item = item
        self.amount = amount
        self.isIncome = isIncome
        self.count = count
        self.lastRecordedAt = lastRecordedAt
    }

    /// 入力欄に入れる文（「ランチ 850」）。ひとこと入力と同じ形にし、送ればいつもの読み取り（AI かキーワード辞書）で記録する。
    ///
    /// 収入は品目の語（「給料」など）で収入と読むので、金額に符号は付けない。返金（マイナスを付けた額）で記録した収入や、
    /// 収入の語があっても辞書では収入と読まない品目（「Suica入金」）を収入に直した記録は、「-」を付けて返金として読ませる
    /// （付けないと支出として記録されるため）。収入と読むかは、記録を読むときと同じ決まり（`IncomeRule`）で見る。
    public var draft: String {
        let plain = item.isEmpty ? "\(amount)" : "\(item) \(amount)"
        guard isIncome, !IncomeRule.isIncome(plain) else { return plain }
        return item.isEmpty ? "-\(amount)" : "\(item) -\(amount)"
    }
}

/// よく使うひとことの候補。入力の手間を減らすため、よく記録する品目を入力欄の上に並べ、押すとその文を入力欄に入れる
/// （docs/design.md §9 のよく使うひとことの決め事）。
///
/// 決め事:
/// - 品目ごとにまとめる（品目は `CategoryMemory.item(ofMemo:amount:isIncome:)` で割り勘の説明を除き、`CategoryMemory.key(for:)`
///   でそろえた形が同じものを同じ品目とする）。品目の無い記録は候補にしない。
/// - 金額と書き方は、その品目のいちばん新しい記録のもの（同じ品目でも額は変わるので、平均ではなく最後に払った額にする。押した後に
///   入力欄で直せる）。
/// - 並びは記録した回数の多い順、同じならいちばん新しい記録の新しい順。
/// - 入力欄が空のときは、2 回以上記録した品目だけを出す（1 回だけの品目は「よく使う」とは言えないため）。打ち始めたら、打った文字で
///   始まる品目を、回数によらず出す（続きを打たずに選べるように）。打った文に数字があれば出さない（金額まで打った後は候補が要らない）。
public enum QuickPhrases {
    /// 候補の最大の数。
    public static let maximumCount = 8
    /// 入力欄が空のときに出す品目の、最小の記録の回数。
    public static let minimumCountWhenEmpty = 2

    /// 記録から、品目ごとの候補を作る（並びは上の決め事。数は絞らない）。
    public static func phrases<Records: Sequence>(from records: Records) -> [QuickPhrase]
    where Records.Element: QuickPhraseRecord {
        var groups: [String: (latest: Records.Element, item: String, count: Int)] = [:]
        for record in records {
            let item = CategoryMemory.item(ofMemo: record.memo, amount: record.amount, isIncome: record.isIncome)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard record.amount > 0, !item.isEmpty, let key = CategoryMemory.key(for: item) else { continue }
            if var group = groups[key] {
                group.count += 1
                if record.createdAt > group.latest.createdAt {
                    group.latest = record
                    group.item = item
                }
                groups[key] = group
            } else {
                groups[key] = (record, item, 1)
            }
        }
        return groups.map { key, group in
            QuickPhrase(
                key: key, item: group.item, amount: group.latest.amount, isIncome: group.latest.isIncome,
                count: group.count, lastRecordedAt: group.latest.createdAt
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.lastRecordedAt != rhs.lastRecordedAt { return lhs.lastRecordedAt > rhs.lastRecordedAt }
            return lhs.key < rhs.key
        }
    }

    /// 入力欄の文に合わせて出す候補（上の決め事）。
    public static func suggestions(_ phrases: [QuickPhrase], draft: String) -> [QuickPhrase] {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            return Array(phrases.filter { $0.count >= minimumCountWhenEmpty }.prefix(maximumCount))
        }
        let normalized = TextNormalizer.normalize(typed)
        guard !normalized.contains(where: \.isASCIIDigit), let prefix = CategoryMemory.key(for: normalized) else { return [] }
        return Array(phrases.filter { $0.key.hasPrefix(prefix) }.prefix(maximumCount))
    }
}
