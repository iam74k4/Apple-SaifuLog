import Foundation

/// 答えの数字を、前の期間と比べたもの（回答カードの一文「先月の同じ日までより ¥1,800 多い」）。docs/design.md §3-4。
///
/// 数字はコードで計算する（AI には計算させない）。途中の期間（今日・今週・今月・今年）は、前の期間の同じところまでと比べる
/// （月の半ばに先月まるごとと比べると、いつも「少ない」になるため）。終わった期間（昨日・先週・先月・直近 N 日）は、その前の
/// 期間まるごとと比べる。
public struct LedgerComparison: Hashable, Sendable {
    /// 何と比べたか（画面の言葉と AI に渡す文の言葉を決める）。
    public enum Baseline: Hashable, Sendable {
        /// 昨日の同じ時刻まで（今日と比べる）。
        case yesterdaySameTime
        /// 一昨日（昨日と比べる）。
        case dayBeforeYesterday
        /// 先週の同じ曜日・時刻まで（今週と比べる）。
        case lastWeekToDate
        /// 先々週（先週と比べる）。
        case weekBeforeLast
        /// 先月の同じ日・時刻まで（今月と比べる）。
        case lastMonthToDate
        /// 先々月（先月と比べる）。
        case monthBeforeLast
        /// 去年の同じ日・時刻まで（今年と比べる）。
        case lastYearToDate
        /// その前の N 日（直近 N 日と比べる）。
        case previousDays(Int)
    }

    public let baseline: Baseline
    /// 比べた期間（終わりの時刻は含まない）。
    public let interval: DateInterval
    /// 比べた期間の値（金額か件数）。
    public let previous: Int
    /// 比べた期間の、元になった記録の件数（0 なら「記録がありません」と出し、差は出さない）。
    public let previousRecordCount: Int
    /// 答えの値 − 比べた期間の値。
    public let difference: Int

    public init(baseline: Baseline, interval: DateInterval, previous: Int, previousRecordCount: Int, difference: Int) {
        self.baseline = baseline
        self.interval = interval
        self.previous = previous
        self.previousRecordCount = previousRecordCount
        self.difference = difference
    }

    /// 直近 N 日を比べる N の上限。比べる期間（その前の N 日）が、質問のために読み込む範囲（`QuestionLedger.window` の
    /// 直近 366 日）に収まる長さにする。
    public static let maximumComparedDays = 183
}

extension QuestionPeriod {
    /// 比べる期間。比べられない期間（直近 N 日で N が `LedgerComparison.maximumComparedDays` を超える）や、暦で区切れなければ nil。
    public func comparison(now: Date, calendar: Calendar) -> (baseline: LedgerComparison.Baseline, interval: DateInterval)? {
        guard let current = interval(now: now, calendar: calendar) else { return nil }
        /// 途中の期間: 前の期間の始まりから、前の期間の同じところ（`now` を 1 単位前にずらした時刻）まで。前の期間の終わりを
        /// 超えない（3 月 31 日の「先月の同じ日」は 2 月の終わりまで）。
        func toDate(_ component: Calendar.Component, previous: QuestionPeriod) -> DateInterval? {
            guard let previousInterval = previous.interval(now: now, calendar: calendar),
                  let sameMoment = calendar.date(byAdding: component, value: -1, to: now) else { return nil }
            let end = min(max(sameMoment, previousInterval.start), previousInterval.end)
            return DateInterval(start: previousInterval.start, end: end)
        }
        /// 終わった期間: その前の同じ長さの期間まるごと。
        func whole(_ component: Calendar.Component) -> DateInterval? {
            guard let start = calendar.date(byAdding: component, value: -1, to: current.start) else { return nil }
            return DateInterval(start: start, end: current.start)
        }
        switch self {
        case .today:
            return toDate(.day, previous: .yesterday).map { (.yesterdaySameTime, $0) }
        case .yesterday:
            return whole(.day).map { (.dayBeforeYesterday, $0) }
        case .thisWeek:
            return toDate(.weekOfYear, previous: .lastWeek).map { (.lastWeekToDate, $0) }
        case .lastWeek:
            return whole(.weekOfYear).map { (.weekBeforeLast, $0) }
        case .thisMonth:
            return toDate(.month, previous: .lastMonth).map { (.lastMonthToDate, $0) }
        case .lastMonth:
            return whole(.month).map { (.monthBeforeLast, $0) }
        case .thisYear:
            guard let lastYear = calendar.date(byAdding: .year, value: -1, to: current.start),
                  let sameMoment = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }
            return (.lastYearToDate, DateInterval(start: lastYear, end: min(max(sameMoment, lastYear), current.start)))
        case .recentDays(let days):
            guard days <= LedgerComparison.maximumComparedDays,
                  let start = calendar.date(byAdding: .day, value: -days, to: current.start) else { return nil }
            return (.previousDays(days), DateInterval(start: start, end: current.start))
        }
    }
}

/// 月ごとの推移（回答カードの小さな棒グラフ）。答えの月を最後に、前の月から古い順に並べる。
public struct LedgerTrend: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        /// その月（終わりの時刻は含まない）。
        public let month: DateInterval
        public let value: Int

        public init(month: DateInterval, value: Int) {
            self.month = month
            self.value = value
        }
    }

    /// 並べる月の数（答えの月を含む）。
    public static let monthCount = 6

    /// 古い順。最後が答えの月。
    public let points: [Point]

    public init(points: [Point]) {
        self.points = points
    }

    /// いちばん大きい値（棒の高さの基準）。
    public var maximum: Int {
        points.map(\.value).max() ?? 0
    }
}

/// 回答カードの下に出す、続けて聞ける質問（「先月は？」「内訳は？」）。押すと `text` を送る（ふつうの質問と同じ流れ）。
///
/// 送る文は、質問の読み取り（`QuestionParser`）が同じ質問に読める文にする（AI が使えない端末でも同じ答えになるように。
/// `QuestionFollowUpTests` で確かめる）。
public struct QuestionFollowUp: Hashable, Sendable {
    /// 画面の言葉を決める種類。
    public enum Kind: Hashable, Sendable {
        /// 前の期間（今月 → 先月）。
        case previousPeriod(QuestionPeriod)
        /// いまの期間（先月 → 今月）。
        case currentPeriod(QuestionPeriod)
        /// 同じ期間の内訳。
        case breakdown
        /// 今月の予算の残り。
        case remainingBudget
    }

    public let kind: Kind
    public let question: LedgerQuestion
    /// 送る文（日本語。質問の読み取りが日本語を前提にしているため、訳さない）。
    public let text: String

    /// 答えに続けて聞ける質問（多くて 3 つ）。
    ///
    /// - 途中の期間（今日・今週・今月）なら前の期間、終わった期間（昨日・先週・先月）ならいまの期間を、同じ指標で聞く。
    ///   一昨日・先々週・先々月・去年は読めない期間なので出さない。
    /// - 支出の合計・カテゴリの支出・件数なら、同じ期間の内訳。
    /// - 内訳・いちばん多いカテゴリなら、今月の予算の残り（今月の答えで、予算を決めているとき）。
    /// - 予算の残り・1 日あたりに使える額なら、今月の内訳。
    public static func suggestions(for answer: LedgerAnswer, hasBudget: Bool, catalog: CategoryCatalog = .builtIn) -> [QuestionFollowUp] {
        let question = answer.question
        var result: [QuestionFollowUp] = []
        func append(_ kind: Kind, _ next: LedgerQuestion) {
            guard next != question, !result.contains(where: { $0.question == next }),
                  let text = text(for: next, catalog: catalog) else { return }
            result.append(QuestionFollowUp(kind: kind, question: next, text: text))
        }
        switch question.metric {
        case .expenseTotal, .categoryExpense, .incomeTotal, .entryCount, .balance:
            if let (kind, period) = neighbor(of: question.period) {
                append(kind, LedgerQuestion(period: period, metric: question.metric, category: question.category))
            }
            if question.metric != .incomeTotal, question.metric != .balance {
                append(.breakdown, LedgerQuestion(period: question.period, metric: .expenseByCategory))
            }
        case .expenseByCategory, .topCategory:
            if let (kind, period) = neighbor(of: question.period) {
                append(kind, LedgerQuestion(period: period, metric: question.metric))
            }
            if hasBudget, question.period == .thisMonth {
                append(.remainingBudget, LedgerQuestion(period: .thisMonth, metric: .remainingBudget))
            }
        case .remainingBudget, .dailyAllowance:
            append(.breakdown, LedgerQuestion(period: answer.period, metric: .expenseByCategory))
        }
        return Array(result.prefix(3))
    }

    /// 前の期間かいまの期間（読める期間だけ）。
    static func neighbor(of period: QuestionPeriod) -> (Kind, QuestionPeriod)? {
        switch period {
        case .today: (.previousPeriod(.yesterday), .yesterday)
        case .yesterday: (.currentPeriod(.today), .today)
        case .thisWeek: (.previousPeriod(.lastWeek), .lastWeek)
        case .lastWeek: (.currentPeriod(.thisWeek), .thisWeek)
        case .thisMonth: (.previousPeriod(.lastMonth), .lastMonth)
        case .lastMonth: (.currentPeriod(.thisMonth), .thisMonth)
        case .thisYear, .recentDays: nil
        }
    }

    /// 送る文。読み取りの辞書にある語だけで書く。書けない質問（直近 N 日など）は nil。
    static func text(for question: LedgerQuestion, catalog: CategoryCatalog) -> String? {
        let period: String
        switch question.period {
        case .today: period = "今日"
        case .yesterday: period = "昨日"
        case .thisWeek: period = "今週"
        case .lastWeek: period = "先週"
        case .thisMonth: period = "今月"
        case .lastMonth: period = "先月"
        case .thisYear: period = "今年"
        case .recentDays: return nil
        }
        switch question.metric {
        case .expenseTotal: return "\(period)の支出はいくら?"
        case .categoryExpense:
            guard let category = question.category else { return nil }
            return "\(period)の\(catalog.name(of: category))はいくら?"
        case .incomeTotal: return "\(period)の収入はいくら?"
        case .balance: return "\(period)の収支は?"
        case .entryCount:
            guard let category = question.category else { return "\(period)の記録は何件?" }
            return "\(period)の\(catalog.name(of: category))は何件?"
        case .expenseByCategory: return "\(period)の内訳は?"
        case .topCategory: return "\(period)いちばん使ったのは?"
        case .remainingBudget: return "\(period)の予算の残りは?"
        case .dailyAllowance: return "\(period)あと何日でいくら使える?"
        }
    }
}
