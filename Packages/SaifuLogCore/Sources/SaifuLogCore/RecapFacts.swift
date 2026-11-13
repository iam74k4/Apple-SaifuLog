import Foundation

/// 月のまとめの数字を、端末内 AI に渡す文にする。
///
/// AI にはこの文だけを渡し、励ましか気づきの一言をこの内容から書かせる。モデルの一言に出てよい数字は、この文に書いた
/// 数字だけ（`AnswerSentenceCheck`。家計への質問の一言と同じ照合）。質問の結果の文（`LedgerAnswerFacts`）と同じく日本語で書き、
/// 金額は画面と同じ「¥1,280」の形（`YenFormatter`）、日付は西暦の年月日で書く。
///
/// 収支を書くときは、その向き（「収入が支出より多い」など）を添える。照合が一言の向きを結果の文の向きと比べるため（収入の
/// 無い月は収支を書かないので、向きを書いた一言はいつも捨てる）。
public enum RecapFacts {
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
}
