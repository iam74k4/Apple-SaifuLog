import Foundation

/// 先週のふりかえり（ホームのカードとその内訳）の数字。先週の支出の合計、前の週との差、カテゴリ別の内訳、いちばん多く
/// 使った日、記録のある日の数、予算があれば週の目安との比べ。
///
/// 数字はすべてコードで計算する（AI には計算させない）。週の区切りは `ReportPeriod.lastWeek`（週の始まりは渡された暦の
/// `firstWeekday`。アプリは設定の「週の始まり」を当てはめた画面の暦を渡す）、集計は `LedgerSummary`、内訳は
/// `CategoryBreakdown` を使い、月のまとめ・質問の答えと食い違わせない。AI には、この数字から作った文（`WeeklyRecapFacts`）
/// だけを渡して一言を書かせ、一言の数字は `AnswerSentenceCheck` で照合する。
///
/// 決め事:
/// - 前の週との差は、先週の支出 − 前の週の支出。前の週に支出の記録が 1 件も無ければ比べない（`Change.noComparison`）。
///   使い始めた週の翌週に「前の週より ¥（まるごと）多い」と出ても、比べたことにならないため（月のまとめと同じ）。
/// - 日は暦で区切り、秒数で数えない（夏時間の日は 23 時間や 25 時間になるため）。週は 7 日のまま。
/// - いちばん多く使った日は、支出の合計がいちばん多い日。同じ額なら早い日。支出が無ければ nil。
/// - 記録のある日の数は、支出か収入の記録（使った日時で数える）が 1 件でもある日の数。
/// - 週の目安は、月の予算 × 週のうちその月の日数 ÷ その月の日数を、週がかかる月ごとに足して切り捨てる（月をまたぐ週は日ごとに
///   按分する。9 月の 3 日と 10 月の 4 日なら、予算 × 3 ÷ 30 + 予算 × 4 ÷ 31）。月の日数は `ReportPeriod.thisMonth`
///   （ホームの今月と同じ、利用者が選んだ暦の月）で数える。切り捨てるのは、予算の 1 日あたりの額（`BudgetStatus`）と同じく、
///   目安どおりに使っても月の予算を超えないようにするため。
/// - 週の目安は、いまの予算をその額に決めた日時（`BudgetPlan.decidedAt`）がその週の終わりより前のときだけ出す（月のまとめの
///   予算の進みと同じ考え方）。予算は月ごとに持たないので、決める前の週の予算は分からないため。
public struct WeeklyRecap: Sendable, Hashable {
    /// 前の週との差。
    public enum Change: Sendable, Hashable {
        /// 前の週に支出の記録が無い（比べない）。
        case noComparison
        /// 前の週より多い（差額、正の数）。
        case more(Int)
        /// 前の週より少ない（差額、正の数）。
        case less(Int)
        /// 前の週と同じ。
        case same
    }

    /// 1 日の支出。
    public struct Day: Sendable, Hashable {
        /// その日（0 時から翌日の 0 時まで。終わりの時刻は含まない）。
        public let interval: DateInterval
        /// その日の支出の合計。
        public let expense: Int
    }

    /// 先週の集計（期間は先週）。
    public let summary: LedgerSummary
    /// 前の週の集計。
    public let previousSummary: LedgerSummary
    /// 先週の支出のカテゴリ別の内訳。
    public let breakdown: CategoryBreakdown
    /// 前の週の支出の記録の件数。0 なら前の週と比べない。
    public let previousExpenseCount: Int
    /// 先週のうち、支出がいちばん多かった日。支出が無ければ nil。
    public let busiestDay: Day?
    /// 先週のうち、記録（支出か収入）のある日の数。
    public let recordedDayCount: Int
    /// 月の予算から出した先週の目安。予算が無いか、先週には当てはめない（上の決め事）なら nil。
    public let budgetPace: Int?

    /// `now` を含む週の 1 つ前の週（先週）のふりかえりを作る。
    ///
    /// - Parameters:
    ///   - records: 先週と前の週の記録（ほかの期間の記録が混じっていても数えない）。
    ///   - now: 今日の日時。先週はこの日時を含む週の前の週。
    ///   - budget: いまの月の全体の予算。nil か 0 以下なら予算なし。
    ///   - budgetDecidedAt: その予算を決めた日時（`BudgetPlan.decidedAt`）。この日時が先週の終わりより前のときだけ目安を出す。
    ///   - calendar: 週と日と月の区切りの暦（週の始まりは `firstWeekday`）。
    /// - Returns: 暦で週を区切れなければ nil。
    public init?<Records: Sequence>(
        records: Records,
        now: Date,
        budget: Int? = nil,
        budgetDecidedAt: Date? = nil,
        calendar: Calendar
    ) where Records.Element: LedgerRecord {
        guard let week = ReportPeriod.lastWeek.interval(now: now, calendar: calendar),
              let previous = ReportPeriod.lastWeek.interval(now: week.start, calendar: calendar)
        else { return nil }
        // 同じ記録を何度か数えるので、1 度だけ読む（Sequence は 2 度読めるとは限らない）。
        let records = Array(records)
        let summary = LedgerSummary(records: records, interval: week, calendar: calendar)
        self.summary = summary
        self.previousSummary = LedgerSummary(records: records, interval: previous, calendar: calendar)
        self.breakdown = CategoryBreakdown(summary)
        self.previousExpenseCount = self.previousSummary.expenseCount

        let days = Self.days(in: week, calendar: calendar)
        var busiest: Day?
        var recordedDays = 0
        for day in days {
            // 区切りは LedgerSummary と同じ（始まりは含み、終わりは含まない）。
            let inDay = records.filter { $0.spentAt >= day.start && $0.spentAt < day.end }
            if !inDay.isEmpty { recordedDays += 1 }
            let expense = inDay.reduce(0) { $0 + ($1.isIncome ? 0 : $1.amount) }
            // 同じ額なら早い日のまま（後の日で置き換えない）。
            if expense > 0, expense > (busiest?.expense ?? 0) {
                busiest = Day(interval: day, expense: expense)
            }
        }
        self.busiestDay = busiest
        self.recordedDayCount = recordedDays

        let applies = budgetDecidedAt.map { $0 < week.end } ?? false
        if let budget, budget > 0, applies {
            self.budgetPace = Self.pace(budget: budget, days: days, calendar: calendar)
        } else {
            self.budgetPace = nil
        }
    }

    /// 先週（終わりの時刻は含まない）。
    public var week: DateInterval {
        summary.interval
    }

    /// 先週の支出の合計。
    public var expense: Int {
        summary.expense
    }

    /// 先週の記録の件数（支出と収入）。0 なら「記録が無かった週」として扱う。
    public var recordCount: Int {
        summary.recordCount
    }

    /// 記録が 1 件も無かった週か。
    public var isEmpty: Bool {
        recordCount == 0
    }

    /// 前の週の支出との差（先週 − 前の週）。前の週に支出の記録が無ければ nil。
    public var expenseChange: Int? {
        previousExpenseCount > 0 ? expense - previousSummary.expense : nil
    }

    /// 前の週との差を、多い・少ない・同じ・比べない、に分けたもの。
    public var change: Change {
        guard let change = expenseChange else { return .noComparison }
        switch change {
        case 1...: return .more(change)
        case ..<0: return .less(-change)
        default: return .same
        }
    }

    /// 先週の支出が、週の目安より多い額（目安より少なければ負）。目安を出さないときは nil。
    public var spentBeyondPace: Int? {
        budgetPace.map { expense - $0 }
    }

    /// 支出の多いカテゴリ（多い順に最大 `limit` 件）。カードは上位 3 件を出す。
    public func topCategories(_ limit: Int = 3) -> [CategoryBreakdown.Item] {
        Array(breakdown.items.prefix(limit))
    }

    // MARK: - カードを出すか

    /// 先週のふりかえりのカードを、いま出すか。
    ///
    /// 週が替わって最初に開いたときだけ出す。最後に出した日時（`lastShownAt`）が、`now` を含む週（今週）より前なら、まだ今週は
    /// 出していない。今週より後なら、端末の時計を先へずらしていたときに出したものなので、これも出していないとみなす（時計を
    /// 直した後、ずらしていた日まで出なくならないように）。今週かどうかはいまの暦で決めるので、週の始まりの設定を変えると、
    /// 変えた後の週の区切りで決め直す（変えた日に新しい週が始まる設定にしたら、その日にもう一度出る）。
    ///
    /// 記録を始めたのが先週の終わり以降（`earliestRecordAt` が先週の終わりより後か、記録が無い）なら出さない。ふりかえる週が
    /// 無いため（初めて使う人に「記録が無かった週」を出さない）。記録を始めた後で記録の無かった週は、「記録が無かった週」として出す。
    ///
    /// - Parameters:
    ///   - lastShownAt: 最後にカードを出した日時。まだ出したことが無ければ nil。
    ///   - earliestRecordAt: 使った日時のいちばん古い記録の日時。記録が無ければ nil。
    public static func isDue(lastShownAt: Date?, earliestRecordAt: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let thisWeek = ReportPeriod.thisWeek.interval(now: now, calendar: calendar),
              let earliestRecordAt, earliestRecordAt < thisWeek.start
        else { return false }
        guard let lastShownAt else { return true }
        return lastShownAt < thisWeek.start || lastShownAt >= thisWeek.end
    }

    // MARK: - 計算

    /// 週の日（0 時から翌日の 0 時まで）。暦で区切る（夏時間の日も 1 日）。
    static func days(in week: DateInterval, calendar: Calendar) -> [DateInterval] {
        var days: [DateInterval] = []
        var cursor = week.start
        while cursor < week.end, let day = calendar.dateInterval(of: .day, for: cursor) {
            // 暦が進まない日を返したときに止まらなくなるのを防ぐ（実際には無いはず）。
            guard day.end > cursor else { break }
            days.append(DateInterval(start: max(day.start, week.start), end: min(day.end, week.end)))
            cursor = day.end
        }
        return days
    }

    /// 週の目安。日ごとに「予算 ÷ その日の月の日数」を足した額を切り捨てる（上の決め事）。
    ///
    /// 日ごとに切り捨ててから足すと、月をまたがない週でも 1 か月分を足した額が予算より数円少なくなるので、分数のまま足して
    /// 最後に 1 度だけ切り捨てる。
    static func pace(budget: Int, days: [DateInterval], calendar: Calendar) -> Int? {
        var daysPerMonth: [Date: (inWeek: Int, inMonth: Int)] = [:]
        for day in days {
            guard let month = ReportPeriod.thisMonth.interval(now: day.start, calendar: calendar) else { return nil }
            let inMonth = LedgerSummary.dayCount(of: month, calendar: calendar)
            guard inMonth > 0 else { return nil }
            daysPerMonth[month.start, default: (0, inMonth)].inWeek += 1
        }
        // 分数（分子 / 分母）で足す。分母は月の日数の積までで、予算の上限（8 桁）× 7 日と掛けても桁あふれしない。
        var numerator = 0
        var denominator = 1
        for (_, counts) in daysPerMonth {
            numerator = numerator * counts.inMonth + budget * counts.inWeek * denominator
            denominator *= counts.inMonth
            let divisor = gcd(numerator, denominator)
            if divisor > 1 {
                numerator /= divisor
                denominator /= divisor
            }
        }
        return numerator / denominator
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (abs(a), abs(b))
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}
