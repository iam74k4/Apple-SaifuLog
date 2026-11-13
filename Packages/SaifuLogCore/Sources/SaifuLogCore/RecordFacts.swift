import Foundation

/// 記録した直後の数字を、端末内 AI に渡す文にする（記録の返事に添える AI の一言。docs/design.md §3 の「記録の返事の一言」）。
///
/// AI にはこの文だけを渡し、気づきか励ましの一言を書かせる。数字はここで計算し（AI には計算させない）、一言に出てよい数字は
/// この文に書いた数字だけ（`AnswerSentenceCheck`。月のまとめの一言・質問の一言と同じ照合）。金額は画面と同じ「¥1,280」の形
/// （`YenFormatter`）で書く。
///
/// 書くこと: いま記録した支出（品目・金額・カテゴリ。3 件まで）、いま記録した支出のうち「その他」でない最初のカテゴリの今月の
/// 合計と件数（「その他」は書かない。何に使ったかが分からず、一言の材料にならないため）、今月の支出の合計と件数、予算を決めていれば予算の残り
/// （超えていれば超えた額）。収入は書かない（記録の返事は「使ったお金」についての一言にするため）。
public enum RecordFacts {
    /// いま記録した支出の 1 件。
    public struct Item: Sendable, Hashable {
        /// 品目（割り勘などの説明を除いたメモ）。空ならカテゴリの名前で書く。
        public let item: String
        public let amount: Int
        public let category: EntryCategory

        public init(item: String, amount: Int, category: EntryCategory) {
            self.item = item
            self.amount = amount
            self.category = category
        }
    }

    /// 文に書く、いま記録した支出の件数の上限（多いと一言が長くなり、確かめる数字も増えるため）。
    static let maximumItems = 3

    /// 記録した直後の文。支出を記録していなければ（収入だけ）nil。
    ///
    /// - Parameters:
    ///   - recorded: いま記録した支出（記録した順）。
    ///   - monthRecords: 今月の記録（いま記録したものを含む）。月の外の記録は数えない。
    ///   - budget: 月の全体の予算。決めていなければ nil。
    ///   - now: 記録した日時（今月の基準）。
    ///   - calendar: 月を区切る暦（画面の暦）。
    ///   - catalog: カテゴリの一覧（作ったカテゴリの名前を書く）。
    public static func text<Records: Sequence>(
        recorded: [Item], monthRecords: Records, budget: Int?, now: Date, calendar: Calendar,
        catalog: CategoryCatalog = .builtIn
    ) -> String? where Records.Element: LedgerRecord {
        guard !recorded.isEmpty,
              let month = ReportPeriod.thisMonth.interval(now: now, calendar: calendar) else { return nil }
        let yen = YenFormatter.string(from:)
        let summary = LedgerSummary(records: monthRecords, interval: month, calendar: calendar)
        let items = recorded.prefix(maximumItems).map { item in
            let name = catalog.name(of: item.category)
            let title = item.item.isEmpty ? name : item.item
            return "\(title) \(yen(item.amount))（\(name)）"
        }
        var lines = ["いま記録した支出: " + items.joined(separator: "、")]
        if let category = recorded.first(where: { $0.category != .other })?.category,
           let total = summary.expenseByCategory[category], let count = summary.expenseCountByCategory[category] {
            lines.append("今月の\(catalog.name(of: category)): \(yen(total))（記録 \(count)件）")
        }
        lines.append("今月の支出の合計: \(yen(summary.expense))（支出の記録 \(summary.expenseCount)件）")
        if let status = BudgetStatus(budget: budget, summary: summary, now: now, calendar: calendar) {
            if status.isOver {
                lines.append("月の予算: \(yen(status.budget)) を \(yen(status.overspent)) 超えている")
            } else {
                lines.append("月の予算: \(yen(status.budget)) のうち \(yen(status.spent)) を使い、残りは \(yen(status.remaining))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
