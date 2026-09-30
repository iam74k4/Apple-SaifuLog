import Foundation

/// 答え（`LedgerAnswer`）を、端末内 AI のツールの結果として渡す文にする。
///
/// AI にはこの文だけを渡し、答えの一言をこの内容から書かせる。モデルの一言に出てよい数字は、この文に書いた
/// 数字だけ（`AnswerSentenceCheck`）。AI への指示と同じく日本語で書く（入力の解析が日本語を前提にしているため）。
/// 金額は画面と同じ「¥1,280」の形（`YenFormatter`）で書き、モデルが表記を写しやすいようにする。
public enum LedgerAnswerFacts {
    /// ツールの結果の文。
    /// - Parameters:
    ///   - calendar: 期間の日付を書く暦（期間を区切った暦）。日付は西暦で書く。
    ///   - catalog: カテゴリの一覧（作ったカテゴリの名前を書く）。
    public static func text(for answer: LedgerAnswer, calendar: Calendar, catalog: CategoryCatalog = .builtIn) -> String {
        var lines = [
            "期間: \(periodName(answer.period))（\(dateRange(answer.interval, calendar: calendar))）",
            "知りたいこと: \(metricName(answer.question, catalog: catalog))",
            "結果: \(result(answer.value, catalog: catalog))",
            "元になった記録: \(answer.recordCount)件",
        ]
        if answer.period != answer.question.period {
            // 予算は月で数えるので、聞かれた期間と違う期間で答えたことを、モデルにも伝える。
            lines.insert("聞かれた期間: \(periodName(answer.question.period))（予算は月ごとなので、上の期間で数えた）", at: 1)
        }
        if let comparison = answer.comparison {
            lines.append("前の期間との比べ: \(comparisonText(comparison, value: answer.value))")
        }
        return lines.joined(separator: "\n")
    }

    /// 前の期間との比べの文（「先月の同じ日まで（¥5,400）より ¥1,800 多い」）。比べた期間の日付は書かない（一言に期間の日付の
    /// 数字を増やさないため）。
    static func comparisonText(_ comparison: LedgerComparison, value: LedgerAnswer.Value) -> String {
        let name = baselineName(comparison.baseline)
        guard comparison.previousRecordCount > 0 else { return "\(name)は記録が無いので、比べられない" }
        let figure: (Int) -> String
        if case .count = value {
            figure = { "\($0)件" }
        } else {
            figure = YenFormatter.string(from:)
        }
        let previous = figure(comparison.previous)
        switch comparison.difference {
        case 1...: return "\(name)（\(previous)）より \(figure(comparison.difference)) 多い"
        case ..<0: return "\(name)（\(previous)）より \(figure(-comparison.difference)) 少ない"
        default: return "\(name)（\(previous)）と同じ"
        }
    }

    /// 比べた期間の名前（AI に渡す日本語）。
    public static func baselineName(_ baseline: LedgerComparison.Baseline) -> String {
        switch baseline {
        case .yesterdaySameTime: "昨日の同じ時刻まで"
        case .dayBeforeYesterday: "一昨日"
        case .lastWeekToDate: "先週の同じ曜日の同じ時刻まで"
        case .weekBeforeLast: "先々週"
        case .lastMonthToDate: "先月の同じ日まで"
        case .monthBeforeLast: "先々月"
        case .lastYearToDate: "去年の同じ日まで"
        case .previousDays(let days): "その前の\(days)日"
        }
    }

    /// 期間の名前（AI に渡す日本語）。
    public static func periodName(_ period: QuestionPeriod) -> String {
        switch period {
        case .today: "今日"
        case .yesterday: "昨日"
        case .thisWeek: "今週"
        case .lastWeek: "先週"
        case .thisMonth: "今月"
        case .lastMonth: "先月"
        case .thisYear: "今年"
        case .recentDays(let days): "直近\(days)日"
        }
    }

    static func metricName(_ question: LedgerQuestion, catalog: CategoryCatalog = .builtIn) -> String {
        switch question.metric {
        case .expenseTotal: "支出の合計"
        case .categoryExpense: "\(catalog.name(of: question.category ?? .other))の支出の合計"
        case .incomeTotal: "収入の合計"
        case .balance: "収支（収入から支出を引いた額）"
        case .expenseByCategory: "支出のカテゴリ別の内訳"
        case .entryCount:
            question.category.map { "\(catalog.name(of: $0))の支出の記録の件数" } ?? "記録の件数（支出と収入）"
        case .remainingBudget: "月の予算の残り"
        case .dailyAllowance: "今日から月末まで、1日あたりに使える額"
        case .topCategory: "いちばん多く使ったカテゴリ"
        }
    }

    static func result(_ value: LedgerAnswer.Value, catalog: CategoryCatalog = .builtIn) -> String {
        let yen = YenFormatter.string(from:)
        switch value {
        case .amount(let amount):
            return yen(amount)
        case .balance(let balance):
            let note = balance > 0 ? "収入が支出より多い" : balance < 0 ? "支出が収入より多い" : "収入と支出が同じ"
            return "\(YenFormatter.signedString(from: balance))（\(note)）"
        case .count(let count):
            return "\(count)件"
        case .breakdown(let breakdown):
            guard !breakdown.isEmpty else { return "この期間の支出はありません" }
            let items = breakdown.items.map { "\(catalog.name(of: $0.category)) \(yen($0.amount))（\($0.percent)%）" }
            return "支出の合計 \(yen(breakdown.total))。" + items.joined(separator: "、")
        case .topCategory(let item):
            guard let item else { return "この期間の支出はありません" }
            return "いちばん多いのは\(catalog.name(of: item.category))で \(yen(item.amount))（支出全体の\(item.percent)%）"
        case .budget(let status):
            if status.isOver {
                return "予算 \(yen(status.budget)) を \(yen(status.overspent)) 超えています（使った額 \(yen(status.spent))）"
            }
            return "予算 \(yen(status.budget)) のうち \(yen(status.spent)) を使い、残りは \(yen(status.remaining))"
        case .dailyAllowance(let status):
            if status.isOver {
                return "予算 \(yen(status.budget)) を \(yen(status.overspent)) 超えているので、使える額はありません"
            }
            return "1日あたり \(yen(status.dailyAllowance))（予算の残り \(yen(status.remaining))、今日を含めて残り\(status.remainingDays)日）"
        case .noBudget:
            return "月の予算が決まっていないので、答えられません"
        case .budgetNotApplicable:
            return "この月は、いまの予算を決める前の月なので、予算の残りは分かりません"
        }
    }

    /// 期間の日付（「2026年9月1日から2026年9月30日まで」）。終わりの時刻は含まないので、終わりの前の日までを書く。
    static func dateRange(_ interval: DateInterval, calendar: Calendar) -> String {
        // 和暦などの暦でも、西暦の年月日で書く（入力の日付と同じ方針。AI にもそのまま写させるため）。
        let gregorian = ReportPeriod.gregorian(like: calendar)
        func day(_ date: Date) -> String {
            let parts = gregorian.dateComponents([.year, .month, .day], from: date)
            return "\(parts.year ?? 0)年\(parts.month ?? 0)月\(parts.day ?? 0)日"
        }
        let lastDay = interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
        let first = day(interval.start)
        let last = day(lastDay)
        return first == last ? first : "\(first)から\(last)まで"
    }
}
