import Foundation

/// CSV から読んだ行（`LedgerCSVReader.Row`）のうち、どれを記録として入れるかを決める（設定の「CSV から読み込む」）。
///
/// 同じファイルを 2 回読み込んだり、同じ端末で書き出した CSV を読み込んだりしても、記録が二重にならないようにする。
/// 同じ記録とみなすのは、使った日時（分まで。CSV は分までしか書かない）・金額・支出か収入か・カテゴリ・品目がすべて
/// 同じもの（`Key`）。送った文は見ない（直した記録は、送った文が元のまま品目や金額だけ変わっているので、送った文では
/// 見分けられないうえ、見分けに使う意味も無い）。
///
/// 同じ鍵の行は、数で比べる（ファイルに 3 行あり、保存先に 1 件あれば 2 行を入れる）。同じ分に同じ品目を 2 つ記録すること
/// （「コーヒー400 コーヒー400」）は実際にあるので、ファイルの中の同じ行を 1 つにまとめると、まだ無い記録まで落としてしまうため。
public enum LedgerCSVImport {
    /// 同じ記録かを見分ける鍵。
    public struct Key: Sendable, Hashable {
        /// 使った日時を分に切り捨てたもの（基準日からの分）。時間帯に左右されない（時間帯のずれは分の単位なので）。
        let minute: Int
        let amount: Int
        let isIncome: Bool
        /// カテゴリの rawValue。収入はカテゴリを持たないので、いつも「その他」として比べる。
        let category: String
        let memo: String

        public init(spentAt: Date, amount: Int, isIncome: Bool, category: EntryCategory, memo: String) {
            minute = Int((spentAt.timeIntervalSinceReferenceDate / 60).rounded(.down))
            self.amount = amount
            self.isIncome = isIncome
            self.category = (isIncome ? EntryCategory.other : category).rawValue
            self.memo = memo
        }

        public init(_ row: LedgerCSVReader.Row) {
            self.init(spentAt: row.spentAt, amount: row.amount, isIncome: row.isIncome, category: row.category, memo: row.memo)
        }
    }

    /// 入れる行と、すでにあって飛ばした行の数。
    public struct Plan: Sendable, Hashable {
        /// 記録として入れる行（ファイルの順）。
        public let rows: [LedgerCSVReader.Row]
        /// すでに同じ記録があるので飛ばした行の数。
        public let duplicateCount: Int
    }

    /// 入れる行を決める。
    /// - Parameters:
    ///   - rows: CSV から読んだ行（ファイルの順）。
    ///   - existing: 保存先にある記録の鍵（同じ鍵がいくつあってもよい）。
    public static func plan<Existing: Sequence>(rows: [LedgerCSVReader.Row], existing: Existing) -> Plan
    where Existing.Element == Key {
        var remaining: [Key: Int] = [:]
        for key in existing {
            remaining[key, default: 0] += 1
        }
        var accepted: [LedgerCSVReader.Row] = []
        var duplicateCount = 0
        for row in rows {
            let key = Key(row)
            if let count = remaining[key], count > 0 {
                remaining[key] = count - 1
                duplicateCount += 1
            } else {
                accepted.append(row)
            }
        }
        return Plan(rows: accepted, duplicateCount: duplicateCount)
    }

    /// 入れる行の記録した日時。CSV には記録した日時が無いので、使った日時にする（タイムラインは記録した日時の順に並ぶので、
    /// 読み込んだ記録が今日の送信として並ばず、使った日のところに入る）。同じ分の行はファイルの順に 1 ミリ秒ずつずらす
    /// （並びを保ち、1 回の送信で記録した複数件が、タイムラインで 1 つの送信にまとまるように。`TimelineSend`）。
    public static func createdAt(for rows: [LedgerCSVReader.Row]) -> [Date] {
        var offsets: [Date: Int] = [:]
        return rows.map { row in
            let offset = offsets[row.spentAt, default: 0]
            offsets[row.spentAt] = offset + 1
            return row.spentAt.addingTimeInterval(Double(offset) / 1000)
        }
    }
}
