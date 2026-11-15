import Foundation

/// 過去の記録から学んだ、品目ごとのいつものカテゴリ（docs/design.md §3-2 の「過去の記録から学ぶ」）。
///
/// 覚えたカテゴリ（`CategoryMemory`）は、利用者が返事や ⑥ ではっきり選んだものだけを覚える。それだけだと、AI やキーワード辞書が
/// 読んだカテゴリをそのまま残した記録（直さずに使い続けた＝それでよいという記録）が、次の記録の振り分けに生かされない。
/// AI は同じ品目でも毎回同じカテゴリを選ぶとは限らないので、これまでの記録で同じ品目をどのカテゴリにしてきたかを数え、
/// はっきり多いカテゴリがあれば、次の記録もそれにそろえる（使うほど振り分けがそろう）。
///
/// 決め事:
/// - 品目は覚えたカテゴリと同じ形にそろえて比べる（`CategoryMemory.key(for:)`）。同じ品目（そろえた形が同じ）だけに当て、
///   品目に含まれるかでは当てない（覚えたカテゴリより弱い手がかりなので、広げない）。
/// - 同じ品目の記録が `minimumCount` 件以上あり、いちばん多いカテゴリが半分を超えるときだけ当てる（1 件だけ・割れているときは
///   決めない）。
/// - 「その他」は数えない（決められなかった記録や、聞き返しに答えていない記録の印でもあるため）。収入も数えない。
/// - 当てる順は、作ったカテゴリの名前・覚えたカテゴリの後、読み取ったカテゴリの前（`CategoryResolver`）。
public struct CategoryHistory: Sendable, Hashable {
    /// 過去の記録 1 件（品目とカテゴリ）。
    public struct Record: Sendable, Hashable {
        /// 品目（割り勘などの説明を除いたメモ。`CategoryMemory.item(ofMemo:amount:isIncome:)`）。
        public let item: String
        public let category: EntryCategory

        public init(item: String, category: EntryCategory) {
            self.item = item
            self.category = category
        }
    }

    /// 品目（そろえた形）ごとの、いつものカテゴリ。
    public let rules: [String: EntryCategory]

    /// 当てるのに要る、同じ品目の記録の件数。
    public static let minimumCount = 2

    public init(rules: [String: EntryCategory] = [:]) {
        self.rules = rules
    }

    /// 過去の記録から、品目ごとのいつものカテゴリを決める（上の決め事）。
    public init<Records: Sequence>(records: Records) where Records.Element == Record {
        var counts: [String: [EntryCategory: Int]] = [:]
        for record in records where record.category != .other {
            guard let key = CategoryMemory.key(for: record.item) else { continue }
            counts[key, default: [:]][record.category, default: 0] += 1
        }
        var rules: [String: EntryCategory] = [:]
        for (key, byCategory) in counts {
            let total = byCategory.values.reduce(0, +)
            // 件数の多い順、同じ件数ならカテゴリの rawValue の順（読み直すたびに結果が変わらないように）。
            guard let best = byCategory.max(by: { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key.rawValue > rhs.key.rawValue
            }) else { continue }
            guard best.value >= Self.minimumCount, best.value * 2 > total else { continue }
            rules[key] = best.key
        }
        self.rules = rules
    }

    /// 品目のいつものカテゴリ。決められなければ nil。
    public func category(forItem item: String) -> EntryCategory? {
        guard let key = CategoryMemory.key(for: item) else { return nil }
        return rules[key]
    }
}
