import Foundation
import SaifuLogCore

extension QuestionPeriod {
    /// 回答カードに出す期間の名前（「今月」「直近 7 日」）。
    var label: LocalizedStringResource {
        switch self {
        case .today: "今日"
        case .yesterday: "昨日"
        case .thisWeek: "今週"
        case .lastWeek: "先週"
        case .thisMonth: "今月"
        case .lastMonth: "先月"
        case .thisYear: "今年"
        case .recentDays(let days): "直近 \(days) 日"
        }
    }
}

/// 回答カードと読み上げの文。回答カード（`QuestionReplyCard`）と、答えを VoiceOver に読み上げるホームのモデル（`HomeModel`）で
/// 同じ文を使う（画面の文と読み上げの文を食い違わせないため）。
enum QuestionTexts {
    /// AI の一言を捨てたときの定型文（`QuestionRemark.fixed`）。
    static let fixedRemark: LocalizedStringResource = "数字はアプリが記録から計算しました。"

    /// 知りたいことの見出し（「カフェの支出」「収入の合計」）。
    static func title(for question: LedgerQuestion) -> String {
        switch question.metric {
        case .expenseTotal: return String(localized: "支出の合計")
        case .categoryExpense:
            let name = String(localized: (question.category ?? .other).label)
            return String(localized: "\(name)の支出", comment: "回答カードの見出し。%@ はカテゴリの名前（「カフェ」）")
        case .incomeTotal: return String(localized: "収入の合計")
        case .balance: return String(localized: "収支")
        case .expenseByCategory:
            // 月のまとめの欄の見出し（英語は語頭を大文字にする）とは別のキーにする。日本語は同じでも、英語では回答カードの
            // ほかの見出しと同じく文の形（Spending by category）にするため。
            return String(localized: LocalizedStringResource(
                "カテゴリ別の支出（回答カード）", defaultValue: "カテゴリ別の支出",
                comment: "家計への質問の回答カードの見出し。支出のカテゴリ別の内訳を答えたとき"
            ))
        case .entryCount:
            guard let category = question.category else {
                // 診断画面の項目名（Record count）とは別のキーにする。英語で、同じカードの「Based on N entries」と語をそろえるため。
                return String(localized: LocalizedStringResource(
                    "記録の件数（回答カード）", defaultValue: "記録の件数",
                    comment: "家計への質問の回答カードの見出し。カテゴリを聞かれていない記録の件数（支出と収入）を答えたとき"
                ))
            }
            let name = String(localized: category.label)
            return String(localized: "\(name)の件数", comment: "回答カードの見出し。%@ はカテゴリの名前（「カフェ」）")
        case .remainingBudget: return String(localized: "予算の残り")
        case .dailyAllowance: return String(localized: "1日あたりに使える額")
        case .topCategory: return String(localized: "いちばん使ったカテゴリ")
        }
    }

    /// 期間の日付（「9月1日～30日」）。1 日だけの期間は、その日だけ。年をまたぐ期間は年も添える。
    ///
    /// 期間を区切ったのと同じ暦・時間帯で書く（月のまとめの見出しと同じ）。終わりの時刻は含まないので、終わりの前の日までを書く。
    static func dateRange(_ interval: DateInterval, calendar: Calendar) -> String {
        let lastDay = interval.end > interval.start ? interval.end.addingTimeInterval(-1) : interval.start
        let crossesYear = !calendar.isDate(interval.start, equalTo: lastDay, toGranularity: .year)
        if calendar.isDate(interval.start, inSameDayAs: lastDay) {
            var style = Date.FormatStyle.dateTime.month().day()
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return interval.start.formatted(style)
        }
        var style = Date.IntervalFormatStyle(calendar: calendar, timeZone: calendar.timeZone).month().day()
        if crossesYear { style = style.year() }
        return (interval.start..<lastDay).formatted(style)
    }

    /// 期間の名前と日付（「今月・9月1日～30日」「This Month · Sep 1–30」）。
    ///
    /// 区切りはホームの帯の「・」と別のキーにする。帯は区切りの前後に並べ方で空きを入れるので訳に空白を持たないが、ここは
    /// 文字をつなげるだけなので、英語の訳で前後に空白を入れないと「This Month·Sep 1–30」と詰まるため。
    static func periodText(for answer: LedgerAnswer, calendar: Calendar) -> String {
        let name = String(localized: answer.period.label)
        let range = dateRange(answer.interval, calendar: calendar)
        return String(localized: "\(name)・\(range)")
    }

    /// 大きく出す数字（または、数字の無い答えの文）。
    static func headline(for value: LedgerAnswer.Value) -> String {
        switch value {
        case .amount(let amount): YenFormatter.string(from: amount)
        case .balance(let balance): YenFormatter.signedString(from: balance)
        case .count(let count): String(localized: "\(count) 件")
        case .breakdown(let breakdown): YenFormatter.string(from: breakdown.total)
        case .topCategory(let item):
            item.map { YenFormatter.string(from: $0.amount) } ?? String(localized: "この期間の支出はありません")
        case .budget(let status):
            status.isOver ? overText(status) : YenFormatter.string(from: status.remaining)
        case .dailyAllowance(let status):
            status.isOver ? overText(status) : YenFormatter.string(from: status.dailyAllowance)
        case .noBudget: String(localized: "月の予算が決まっていません")
        case .budgetNotApplicable: String(localized: "この月の予算の残りは出せません")
        }
    }

    /// 大きく出すのが数字（金額か件数）か。数字でなければ、大きな文字にせずに文として出す。
    static func headlineIsFigure(_ value: LedgerAnswer.Value) -> Bool {
        switch value {
        case .noBudget, .budgetNotApplicable, .topCategory(nil): false
        default: true
        }
    }

    /// 予算を超えた額（「¥12,000 オーバー」。ホームの帯と同じ文）。
    static func overText(_ status: BudgetStatus) -> String {
        String(localized: "\(YenFormatter.string(from: status.overspent)) オーバー")
    }

    /// 元になった記録の件数（「元になった記録 5 件」）。
    static func recordCount(_ count: Int) -> String {
        String(localized: "元になった記録 \(count) 件")
    }

    /// 今月の無料の質問の残り（「今月の無料の質問 あと 3 回」）。
    static func freeQuestionsLeft(_ count: Int) -> String {
        String(localized: "今月の無料の質問 あと \(count) 回")
    }

    /// VoiceOver に読み上げる答え（期間・見出し・数字・件数・一言・無料の残りの回数）。
    /// - Parameter freeQuestionsLeft: 回答カードに出す無料の残りの回数（少ないときだけ。出さないなら nil）。
    static func spoken(_ answer: LedgerAnswer, remark: QuestionRemark?, freeQuestionsLeft: Int? = nil, calendar: Calendar) -> String {
        var parts = [String(localized: answer.period.label), title(for: answer.question), spokenValue(answer.value)]
        parts.append(recordCount(answer.recordCount))
        if case .ai(let sentence) = remark { parts.append(sentence) }
        if let freeQuestionsLeft { parts.append(self.freeQuestionsLeft(freeQuestionsLeft)) }
        return parts.joined(separator: String(localized: LocalizedStringResource(
            "読み上げの区切り", defaultValue: "、", comment: "回答を VoiceOver で読み上げるときの、項目の間の区切り"
        )))
    }

    /// 読み上げる数字（大きな数字に、いちばん多いカテゴリの名前や予算の残りの日数を添える）。
    static func spokenValue(_ value: LedgerAnswer.Value) -> String {
        switch value {
        case .topCategory(let item?):
            "\(String(localized: item.category.label)) \(item.spokenValue)"
        case .breakdown(let breakdown):
            ([headline(for: value)] + breakdown.items.map { "\(String(localized: $0.category.label)) \($0.spokenValue)" })
                .joined(separator: " ")
        case .dailyAllowance(let status) where !status.isOver:
            "\(headline(for: value)) \(String(localized: "のこり \(status.remainingDays) 日"))"
        default:
            headline(for: value)
        }
    }
}
