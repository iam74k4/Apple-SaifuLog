import Foundation

/// 支出のカテゴリ別の内訳（月のまとめのグラフと行）。金額の多い順に並べ、割合を整数の % で添える。
///
/// 割合はコードで計算する（AI には計算させない）。月のまとめと、あとで作る質問・月のレポートが同じ内訳を使い、
/// 画面の数字と AI に渡す数字を食い違わせないため、ここに集める。
///
/// 決め事:
/// - 0 円（以下）のカテゴリは出さない。記録の無いカテゴリを 0% の行として並べても、読む手間が増えるだけのため。
/// - 並びは金額の多い順。同じ額ならカテゴリの定義順（`EntryCategory.areInStandardOrder`。組み込みの順、作ったカテゴリ、「その他」）。
///   辞書の並びに任せると、開くたびに同じ額の行の順が入れ替わるため。
/// - 割合は最大剰余法で整数の % に丸め、合計をちょうど 100 にする。1 つずつ四捨五入すると、33.3% が 3 つで
///   99%、16.7% が 6 つで 102% のように合計が 100 にならず、「計算が合っていない」と読まれるため。
///   端数の大きい行から 1 ずつ足し、端数が同じなら上の行（並びの順）から足す。
public struct CategoryBreakdown: Sendable, Hashable {
    /// 内訳の 1 行。
    public struct Item: Sendable, Hashable, Identifiable {
        public let category: EntryCategory
        /// そのカテゴリの支出の合計（円）。
        public let amount: Int
        /// 支出の合計に占める割合（0〜100 の整数）。行の割合を足すとちょうど 100。
        ///
        /// ごく小さい額は 0 になることがある（0 円のカテゴリは行にしないので、0 は「1% 未満」の意味）。
        public let percent: Int

        public var id: EntryCategory { category }

        public init(category: EntryCategory, amount: Int, percent: Int) {
            self.category = category
            self.amount = amount
            self.percent = percent
        }
    }

    /// 金額の多い順の行。支出が無ければ空。
    public let items: [Item]
    /// 行の金額の合計（割合の分母）。
    public let total: Int

    /// カテゴリ別の合計から内訳を作る。
    public init(expenseByCategory: [EntryCategory: Int]) {
        let sorted = expenseByCategory
            .filter { $0.value > 0 }
            .sorted { a, b in
                a.value != b.value ? a.value > b.value : EntryCategory.areInStandardOrder(a.key, b.key)
            }
        let total = sorted.reduce(0) { $0 + $1.value }
        self.total = total
        guard total > 0 else {
            self.items = []
            return
        }

        // 100 倍してから割る（先に割ると端数が消える）。掛け算は桁あふれしないよう 2 倍の幅で行う。
        // 1 行の額は合計以下なので、商は 0〜100 に収まる。
        var parts = sorted.map { key, value in
            let (quotient, remainder) = total.dividingFullWidth(value.multipliedFullWidth(by: 100))
            return (category: key, amount: value, percent: quotient, remainder: remainder)
        }
        let leftover = 100 - parts.reduce(0) { $0 + $1.percent }
        // 端数の大きい順（同じなら並びの順）に 1 ずつ足す。足す数は行の数より少ない（端数の合計 < 行の数 × 1）。
        let receivers = parts.indices.sorted { a, b in
            parts[a].remainder != parts[b].remainder ? parts[a].remainder > parts[b].remainder : a < b
        }
        for index in receivers.prefix(leftover) {
            parts[index].percent += 1
        }
        self.items = parts.map { Item(category: $0.category, amount: $0.amount, percent: $0.percent) }
    }

    /// 期間の集計（`LedgerSummary`）の支出から内訳を作る。収入は数えない（`LedgerSummary` と同じ）。
    public init(_ summary: LedgerSummary) {
        self.init(expenseByCategory: summary.expenseByCategory)
    }

    /// 支出が無いか。
    public var isEmpty: Bool {
        items.isEmpty
    }

    /// そのカテゴリの行。支出が無ければ nil。
    public func item(for category: EntryCategory) -> Item? {
        items.first { $0.category == category }
    }
}
