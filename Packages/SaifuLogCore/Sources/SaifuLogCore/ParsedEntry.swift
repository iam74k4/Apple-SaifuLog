import Foundation

/// 一行の入力から読み取った 1 件の記録（保存する前の形）。
///
/// 保存用のモデル（SwiftData）とは分けている。解析はコアで完結させ、
/// 端末や OS に依存しないテストで確かめられるようにするため。
public struct ParsedEntry: Sendable, Hashable {
    /// 自分の負担額（円）。割り勘のときは割ったあとの額。
    public var amount: Int
    /// カテゴリ。収入のときは `.other`。
    public var category: EntryCategory
    /// 収入なら true。
    public var isIncome: Bool
    /// 何に使ったか。割り勘のときは総額と立替額の説明も入る。
    public var memo: String
    /// 何日前のことか（0 = 今日、1 = 昨日）。
    public var daysAgo: Int
    /// 割った人数。割り勘でなければ 1。
    public var splitCount: Int

    public init(
        amount: Int,
        category: EntryCategory,
        isIncome: Bool = false,
        memo: String = "",
        daysAgo: Int = 0,
        splitCount: Int = 1
    ) {
        self.amount = amount
        self.category = category
        self.isIncome = isIncome
        self.memo = memo
        self.daysAgo = daysAgo
        self.splitCount = splitCount
    }

    /// 読み取った値から 1 件を組み立てる。
    ///
    /// AI とルールベースのどちらもここを通す。割り勘の割り算やメモの書き方が、
    /// どちらで読み取ったかによって変わらないようにするため。
    ///
    /// - Parameters:
    ///   - total: 入力に書かれていた金額（割り勘なら割る前の総額）。
    ///   - item: 何に使ったか（金額や日付を除いた部分）。
    ///   - splitCount: 割り勘の人数。割り勘でなければ 1。
    public static func assemble(
        total: Int,
        category: EntryCategory,
        isIncome: Bool,
        item: String,
        daysAgo: Int,
        splitCount: Int
    ) -> ParsedEntry {
        let item = item.trimmingCharacters(in: .whitespacesAndNewlines)
        // 収入を割り勘することはないので、人数が読めても無視する。
        if !isIncome, let split = BillSplit(total: total, count: splitCount) {
            let memo = item.isEmpty ? split.note : "\(item)（\(split.note)）"
            return ParsedEntry(
                amount: split.share, category: category, isIncome: false,
                memo: memo, daysAgo: daysAgo, splitCount: split.count
            )
        }
        return ParsedEntry(
            amount: total, category: isIncome ? .other : category, isIncome: isIncome,
            memo: item, daysAgo: daysAgo, splitCount: 1
        )
    }

    /// 使った日時。今日なら `now` そのもの、過去の日なら同じ時刻のその日。
    public func date(relativeTo now: Date, calendar: Calendar) -> Date {
        DateExpression.date(daysAgo: daysAgo, now: now, calendar: calendar)
    }
}

/// 一行の入力を記録に読み解くもの。
///
/// 端末内 AI（Foundation Models）による実装と、キーワード辞書によるルールベースの実装を
/// 差し替えられるようにするための境目。アプリは「どちらで読んだか」を意識しない。
public protocol EntryParsing: Sendable {
    /// 読み取った記録。金額が見つからなければ空配列。
    func parse(_ text: String) async throws -> [ParsedEntry]
}
