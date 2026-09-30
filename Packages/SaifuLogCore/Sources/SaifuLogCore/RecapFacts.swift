import Foundation

/// ふりかえり（先週のふりかえり・月のまとめ）の数字を、端末内 AI に渡す文にする。
///
/// AI にはこの文だけを渡し、励ましか気づきの一言をこの内容から書かせる。モデルの一言に出てよい数字は、この文に書いた
/// 数字だけ（`AnswerSentenceCheck`。家計への質問の一言と同じ照合）。質問の結果の文（`LedgerAnswerFacts`）と同じく日本語で書き、
/// 金額は画面と同じ「¥1,280」の形（`YenFormatter`）、日付は西暦の年月日で書く。
///
/// 収支の向き（黒字・赤字）の語や符号を書かないのは、照合が一言の向きを結果の文の向きと比べるため（先週のふりかえりは支出
/// だけを扱うので、向きを書いた一言はいつも捨てる）。月のまとめは収支を書くので、その向き（「収入が支出より多い」など）を添える。
public enum RecapFacts {
    /// 先週のふりかえりの文。記録が無かった週は nil（ふりかえる数字が無いので、AI に一言を書かせない）。
    /// - Parameters:
    ///   - calendar: 週を区切った暦。
    ///   - catalog: カテゴリの一覧（作ったカテゴリの名前を書く）。
    public static func text(for recap: WeeklyRecap, calendar: Calendar, catalog: CategoryCatalog = .builtIn) -> String? {
        guard !recap.isEmpty else { return nil }
        let yen = YenFormatter.string(from:)
        // 「1週間」と書いておくのは、一言の「一週間」「1週間」を照合で通すため（照合は、結果の文に無い数え方の数字を捨てる）。
        // 週の数は照合で別の種類に分けるので、この 1 が「1割」「1か月」などの 1 を通すことはない。
        // 「7日間」は書かない。書くと日数の 7 が結果の文に入り、記録のある日が 5 日の週でも「7日とも記録できました」を通してしまう。
        var lines = [
            "期間: 先週の1週間（\(LedgerAnswerFacts.dateRange(recap.week, calendar: calendar))）",
            "支出の合計: \(yen(recap.expense))（支出の記録 \(recap.summary.expenseCount)件）",
        ]
        switch recap.change {
        case .noComparison:
            lines.append("前の週との比べ: 前の週は支出の記録が無いので、比べられない")
        case .more(let difference):
            lines.append("前の週との比べ: 前の週（\(yen(recap.previousSummary.expense))）より \(yen(difference)) 多い")
        case .less(let difference):
            lines.append("前の週との比べ: 前の週（\(yen(recap.previousSummary.expense))）より \(yen(difference)) 少ない")
        case .same:
            lines.append("前の週との比べ: 前の週と同じ")
        }
        if !recap.breakdown.isEmpty {
            lines.append("支出の多いカテゴリ: " + categories(recap.topCategories(), catalog: catalog))
        }
        if let day = recap.busiestDay {
            lines.append("いちばん多く使った日: \(date(day.interval.start, calendar: calendar))（\(yen(day.expense))）")
        }
        lines.append("記録のある日: \(recap.recordedDayCount)日")
        if let pace = recap.budgetPace, let beyond = recap.spentBeyondPace {
            lines.append("週の予算の目安（月の予算を日割りした額）: \(yen(pace))（\(paceComparison(beyond))）")
        }
        return lines.joined(separator: "\n")
    }

    /// 月のまとめの文。記録が無い月と、まだ始まっていない月は nil。
    /// - Parameters:
    ///   - calendar: 月を区切った暦。
    ///   - catalog: カテゴリの一覧（作ったカテゴリの名前を書く）。
    public static func text(for report: MonthlyReport, calendar: Calendar, catalog: CategoryCatalog = .builtIn) -> String? {
        guard report.recordCount > 0, report.timing != .future else { return nil }
        let yen = YenFormatter.string(from:)
        let range = LedgerAnswerFacts.dateRange(report.month, calendar: calendar)
        var lines = [
            report.timing == .current ? "期間: 今月（\(range)。まだ月の途中）" : "期間: \(range)",
            "支出の合計: \(yen(report.expense))（支出の記録 \(report.summary.expenseCount)件）",
        ]
        // 収入を記録していない人（支出だけをつける人）に「赤字」と書かせないよう、収入があるときだけ収支を渡す。
        if report.income > 0 {
            lines.append("収入の合計: \(yen(report.income))")
            lines.append("収支: \(YenFormatter.signedString(from: report.balance))（\(balanceNote(report.balance))）")
        }
        lines.append("1日あたりの平均の支出: \(yen(report.dailyAverage))（\(report.averagingDays)日で割った額）")
        if let change = report.expenseChange {
            let comparison = change > 0
                ? "\(yen(change)) 多い" : change < 0 ? "\(yen(-change)) 少ない" : "同じ"
            lines.append("前の月との比べ: 前の月（\(yen(report.previousSummary.expense))）より \(comparison)")
        }
        if !report.breakdown.isEmpty {
            lines.append("支出の多いカテゴリ: " + categories(Array(report.breakdown.items.prefix(3)), catalog: catalog))
        }
        if let budget = report.budget {
            if budget.isOver {
                lines.append("月の予算: \(yen(budget.budget)) を \(yen(budget.overspent)) 超えている")
            } else {
                lines.append("月の予算: \(yen(budget.budget)) のうち \(yen(budget.spent)) を使い、残りは \(yen(budget.remaining))")
            }
            if let pace = report.budgetPace, let beyond = report.spentBeyondPace {
                lines.append("今日までの予算の目安: \(yen(pace))（\(paceComparison(beyond))）")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 「食費 ¥6,000（49%）、カフェ ¥3,000（24%）」
    static func categories(_ items: [CategoryBreakdown.Item], catalog: CategoryCatalog = .builtIn) -> String {
        items.map { "\(catalog.name(of: $0.category)) \(YenFormatter.string(from: $0.amount))（\($0.percent)%）" }
            .joined(separator: "、")
    }

    /// 目安との比べ（目安より多い・少ない・目安どおり）。
    static func paceComparison(_ beyond: Int) -> String {
        switch beyond {
        case 1...: "目安より \(YenFormatter.string(from: beyond)) 多い"
        case ..<0: "目安より \(YenFormatter.string(from: -beyond)) 少ない"
        default: "目安どおり"
        }
    }

    /// 収支の向きの注記（質問の結果の文と同じ言葉。照合が一言の向きと比べる）。
    static func balanceNote(_ balance: Int) -> String {
        balance > 0 ? "収入が支出より多い" : balance < 0 ? "支出が収入より多い" : "収入と支出が同じ"
    }

    /// 西暦の年月日（「2026年9月23日」）。和暦などの暦でも西暦で書く（`LedgerAnswerFacts` と同じ）。
    static func date(_ date: Date, calendar: Calendar) -> String {
        LedgerAnswerFacts.dateRange(DateInterval(start: date, duration: 0), calendar: calendar)
    }
}
