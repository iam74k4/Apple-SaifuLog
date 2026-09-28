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
    /// 何日前のことか（0 = 今日、1 = 昨日、-1 = 明日）。少し先の日付で書いた記録（払う予定の家賃）は負の数になる。
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
    ///   - isPerPerson: `total` が「1人あたり3000」のように 1 人分として書かれた額か。割らずにそのまま記録し、
    ///     メモに「（4人で割り勘・1人分）」（割り勘の語が無ければ「（1人分）」）と書き足す。
    public static func assemble(
        total: Int,
        category: EntryCategory,
        isIncome: Bool,
        item: String,
        daysAgo: Int,
        splitCount: Int,
        isPerPerson: Bool = false
    ) -> ParsedEntry {
        let item = item.trimmingCharacters(in: .whitespacesAndNewlines)
        // 1 人分の額はもう割ったあとの額なので、割らない。総額や人数をメモから除いたぶん、1 人分であることを書き足す。
        if !isIncome, isPerPerson {
            let note = splitCount >= 2 ? "\(splitCount)人で割り勘・1人分" : "1人分"
            return ParsedEntry(
                amount: total, category: category, isIncome: false,
                memo: item.isEmpty ? note : "\(item)（\(note)）", daysAgo: daysAgo, splitCount: 1
            )
        }
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

    /// 使った日時。今日なら `now` そのもの、ほかの日なら同じ時刻のその日。
    public func date(relativeTo now: Date, calendar: Calendar) -> Date {
        DateExpression.date(daysAgo: daysAgo, now: now, calendar: calendar)
    }

    /// 1 回の送信で読んだ記録に、保存する日時（記録した日時と使った日時）を振る。
    ///
    /// 複数件に分けたときは、書いた順に並ぶよう記録した日時を 1 ミリ秒ずつずらす。同じ日時だと並べ替えの
    /// 順が定まらず、「スーパー」と「ドラッグ」が入れ替わることがあるため。使った日時も、ずらした日時から
    /// 決める（同じ日の記録が書いた順に並ぶように）。
    ///
    /// ずらした日時が `now` の日の終わりを越えるとき（23:59:59.9995 に送った 3 件）は、ずらす起点を前へ寄せ、
    /// すべてを `now` と同じ日の中に収める。越えたまま保存すると、後ろの件だけが翌日（月末なら翌月）の記録になり、
    /// 「9/26」と書いた件が 9/27 になったり、今月の合計から黙って抜けたりするため。
    ///
    /// - Parameter now: 送信した瞬間の日時。解析で「昨日」「9/26」を読んだときと同じ値を渡す（違う値だと、
    ///   解析と保存の間に日付が変わったとき、何日前かの基準がずれて 1 日ずれた日付で保存される）。
    public static func timestamps(for entries: [ParsedEntry], now: Date, calendar: Calendar) -> [EntryTimestamps] {
        var start = now
        if let day = calendar.dateInterval(of: .day, for: now) {
            // 最後の件が日の終わり（翌日の 0 時）の 1 ステップ前に来るよう、起点を寄せる。
            let latestStart = day.end.addingTimeInterval(-Double(entries.count) * orderingStep)
            start = min(now, latestStart)
        }
        return entries.enumerated().map { index, entry in
            let createdAt = start.addingTimeInterval(Double(index) * orderingStep)
            return EntryTimestamps(createdAt: createdAt, spentAt: entry.date(relativeTo: createdAt, calendar: calendar))
        }
    }

    /// 1 回の送信で読んだ複数件の、記録した日時の間隔（秒）。
    static let orderingStep: TimeInterval = 0.001
}

/// 保存する 1 件の日時。
public struct EntryTimestamps: Sendable, Hashable {
    /// 記録した日時。タイムラインはこの順に並べる。
    public var createdAt: Date
    /// 使った日時（収入なら受け取った日時）。
    public var spentAt: Date

    public init(createdAt: Date, spentAt: Date) {
        self.createdAt = createdAt
        self.spentAt = spentAt
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
