import Foundation

/// くり返しの記録の「どの月の分か」（西暦の年と月）。docs/design.md §9 のくり返しの記録の決め事。
///
/// 瞬間ではなく暦の年と月で持ち、保存には数（2026 年 10 月なら 202610）を使う。端末の暦（和暦など）や時間帯を変えても、
/// iCloud で同期したほかの端末でも、同じ月を指すようにするため（無料の回数の月 `QuotaMonth` と同じ考え方）。
public struct RecurringMonth: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    /// 1〜12。
    public let month: Int

    /// 年と月から作る。月が 1〜12 の外なら、前後の年に繰り越す（13 月は次の年の 1 月）。
    public init(year: Int, month: Int) {
        let index = year * 12 + (month - 1)
        let yearPart = index >= 0 ? index / 12 : (index - 11) / 12
        self.year = yearPart
        self.month = index - yearPart * 12 + 1
    }

    /// 保存した数（202610）から作る。0 や月の読めない数は nil。
    public init?(key: Int) {
        let month = key % 100
        guard key > 0, (1...12).contains(month) else { return nil }
        self.init(year: key / 100, month: month)
    }

    /// その瞬間を含む月（西暦で、`timeZone` の時間帯で数える）。
    public init(containing date: Date, timeZone: TimeZone) {
        let components = RecurringSchedule.calendar(timeZone).dateComponents([.year, .month], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1)
    }

    /// 保存に使う数（202610）。
    public var key: Int { year * 100 + month }

    /// `months` か月後（負の数なら前）の月。
    public func adding(months: Int) -> RecurringMonth {
        RecurringMonth(year: year, month: month + months)
    }

    public static func < (lhs: RecurringMonth, rhs: RecurringMonth) -> Bool {
        lhs.key < rhs.key
    }

    public var description: String { "\(year)-\(month)" }
}

/// くり返しの記録の決まり（何を・毎月何日に・どの月から）。保存の型（アプリの `RecurringEntry`）から値だけを渡す。
public struct RecurringRule: Hashable, Sendable {
    /// ID（作った端末で UUID から決める）。記録に付ける印（`RecurringSchedule.occurrenceKey`）の頭にする。
    public var id: String
    /// 品目（空でもよい。空なら記録の見出しはカテゴリ名）。
    public var memo: String
    public var amount: Int
    public var isIncome: Bool
    public var category: EntryCategory
    /// 毎月の何日か（1〜31）。その月に無い日（2 月の 30 日など）は、その月の最後の日にする。
    public var dayOfMonth: Int
    /// 最初に記録する月。
    public var startMonth: RecurringMonth
    /// 記録した（取り消したものも含め、記録を済ませた）いちばん新しい月。まだなら nil。
    public var lastRecordedMonth: RecurringMonth?

    public init(
        id: String, memo: String, amount: Int, isIncome: Bool, category: EntryCategory, dayOfMonth: Int,
        startMonth: RecurringMonth, lastRecordedMonth: RecurringMonth? = nil
    ) {
        self.id = id
        self.memo = memo
        self.amount = amount
        self.isIncome = isIncome
        self.category = category
        self.dayOfMonth = dayOfMonth
        self.startMonth = startMonth
        self.lastRecordedMonth = lastRecordedMonth
    }
}

/// くり返しの記録の日付の決め事（いつ、どの月の分を記録するか）。
///
/// - 毎月、決めた日（無い日なら月末）になったら、その月の分を記録する。アプリは開いたときに記録するので、記録するのは
///   その日を過ぎて最初に開いたとき。記録する日時は、その日の正午（`hourOfDay`）にする（時間帯のずれで前の日や次の日に
///   見えないように）。
/// - 開かなかった月の分も、開いたときにまとめて記録する（家賃は開かなくても払っている）。ただしさかのぼるのは今月を含めて
///   `maximumCatchUpMonths` か月まで（1 年以上開かなかった後に、何十件も記録しないように）。
/// - 記録した月（取り消した月も）は覚えて（`RecurringRule.lastRecordedMonth`）、同じ月の分をもう記録しない。
/// - 日付は西暦で数える（端末の暦が和暦などでも、毎月の同じ日にするため）。時間帯は端末のもの。
public enum RecurringSchedule {
    /// 選べる日（毎月の何日か）。31 日は、どの月でも月末になる。
    public static let dayRange = 1...31
    /// さかのぼって記録する月の数（今月を含む）。
    public static let maximumCatchUpMonths = 12
    /// 記録する日時の時（正午）。
    public static let hourOfDay = 12

    /// 西暦の暦（`timeZone` の時間帯）。
    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// その月の記録する日（その月に無い日なら月末）。
    public static func day(in month: RecurringMonth, dayOfMonth: Int, timeZone: TimeZone) -> Int? {
        let calendar = calendar(timeZone)
        guard let first = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
        return min(max(dayOfMonth, dayRange.lowerBound), days)
    }

    /// その月の記録する日時（その日の正午）。
    public static func date(in month: RecurringMonth, dayOfMonth: Int, timeZone: TimeZone) -> Date? {
        guard let day = day(in: month, dayOfMonth: dayOfMonth, timeZone: timeZone) else { return nil }
        return calendar(timeZone).date(from: DateComponents(year: month.year, month: month.month, day: day, hour: hourOfDay))
    }

    /// その月の分を記録してよいか（記録する日の始まりを過ぎたか）。記録する日になったら、正午より前に開いても記録する。
    static func isDue(_ month: RecurringMonth, dayOfMonth: Int, now: Date, timeZone: TimeZone) -> Bool {
        guard let day = day(in: month, dayOfMonth: dayOfMonth, timeZone: timeZone),
              let start = calendar(timeZone).date(from: DateComponents(year: month.year, month: month.month, day: day)) else {
            return false
        }
        return start <= now
    }

    /// いま記録する月（古い順）。最初の月と、前に記録した月の次の月の遅いほうから、今月まで（さかのぼるのは
    /// `maximumCatchUpMonths` か月まで）のうち、記録する日を過ぎた月。
    public static func dueMonths(for rule: RecurringRule, now: Date, timeZone: TimeZone) -> [RecurringMonth] {
        let current = RecurringMonth(containing: now, timeZone: timeZone)
        var first = max(rule.startMonth, current.adding(months: -(maximumCatchUpMonths - 1)))
        if let last = rule.lastRecordedMonth {
            first = max(first, last.adding(months: 1))
        }
        var months: [RecurringMonth] = []
        var month = first
        while month <= current {
            if isDue(month, dayOfMonth: rule.dayOfMonth, now: now, timeZone: timeZone) {
                months.append(month)
            }
            month = month.adding(months: 1)
        }
        return months
    }

    /// 次に記録する日時（設定の一覧と作るシートに「次は 11月25日」と出す）。記録する日を過ぎた月は、開けばすぐ記録するので
    /// 数えず、まだ来ていないいちばん早い月の日時。
    public static func nextDate(for rule: RecurringRule, now: Date, timeZone: TimeZone) -> Date? {
        let current = RecurringMonth(containing: now, timeZone: timeZone)
        var month = max(rule.startMonth, current)
        if let last = rule.lastRecordedMonth {
            month = max(month, last.adding(months: 1))
        }
        // 今月の日を過ぎていれば来月（2 回で必ず見つかる）。
        for _ in 0..<2 {
            if !isDue(month, dayOfMonth: rule.dayOfMonth, now: now, timeZone: timeZone) {
                return date(in: month, dayOfMonth: rule.dayOfMonth, timeZone: timeZone)
            }
            month = month.adding(months: 1)
        }
        return date(in: month, dayOfMonth: rule.dayOfMonth, timeZone: timeZone)
    }

    /// 今月の記録する日を過ぎたか（作るときに「今月の分も記録する」を出すか）。
    public static func hasPassedThisMonth(dayOfMonth: Int, now: Date, timeZone: TimeZone) -> Bool {
        isDue(RecurringMonth(containing: now, timeZone: timeZone), dayOfMonth: dayOfMonth, now: now, timeZone: timeZone)
    }

    /// 作るときの最初の月。今月の記録する日がまだ来ていなければ今月、過ぎていれば来月から（`includesThisMonth` なら今月から。
    /// 過ぎた今月の分は、保存したらすぐ記録する）。今月の分をもう記録してある（記録から作った）なら、`notBefore` に来月を渡す。
    public static func startMonth(
        dayOfMonth: Int, now: Date, timeZone: TimeZone, includesThisMonth: Bool, notBefore: RecurringMonth? = nil
    ) -> RecurringMonth {
        let current = RecurringMonth(containing: now, timeZone: timeZone)
        let passed = hasPassedThisMonth(dayOfMonth: dayOfMonth, now: now, timeZone: timeZone)
        let start = passed && !includesThisMonth ? current.adding(months: 1) : current
        return max(start, notBefore ?? start)
    }

    /// 記録に付ける印（どの決まりの、どの月の分か）。iCloud で 2 台が同じ月を記録したときに見つけるため。
    public static func occurrenceKey(ruleID: String, month: RecurringMonth) -> String {
        "\(ruleID)/\(month.key)"
    }
}

/// iCloud で同期している 2 台が、同じ月の分をそれぞれ記録したときの片づけ（`RecurringSchedule.occurrenceKey` が同じ記録）。
///
/// 記録した日時のいちばん古い 1 件を残し、ほかを消す。どの端末でも同じ 1 件を残すので、消した結果が同期されても
/// 食い違わない。
public enum RecurringDuplicates {
    /// 片づけに使う記録の値（記録のモデルに依存しないように、値だけを渡す）。
    public struct Record<ID: Hashable>: Hashable {
        public var id: ID
        /// 記録に付けた印。空の記録（くり返しの記録でないもの）は数えない。
        public var key: String
        public var createdAt: Date

        public init(id: ID, key: String, createdAt: Date) {
            self.id = id
            self.key = key
            self.createdAt = createdAt
        }
    }

    /// 消す記録。
    public static func redundant<ID: Hashable>(in records: [Record<ID>]) -> [ID] {
        Dictionary(grouping: records.filter { !$0.key.isEmpty }, by: \.key).values.flatMap { group in
            group.sorted { $0.createdAt < $1.createdAt }.dropFirst().map(\.id)
        }
    }
}
