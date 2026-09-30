import Foundation
import SaifuLogCore

/// 先週のふりかえりのカードと内訳の文。カード・内訳・VoiceOver の読み上げで同じ文を使う（画面の文と読み上げの文を
/// 食い違わせないため）。
///
/// 無料の人に出すのは、ここでコードが作る文だけ（定型文）。プレミアムと体験中は、これに AI の一言を添える（`RecapRemarkModel`）。
enum RecapTexts {
    /// カードの見出し。
    static let title: LocalizedStringResource = "先週のふりかえり"

    /// 定型文（「先週の支出は ¥12,300。前の週より ¥2,100 少なめでした。」）。数字はコアの `WeeklyRecap` のまま。
    static func fixedSentence(for recap: WeeklyRecap) -> String {
        guard !recap.isEmpty else { return String(localized: "先週は記録がありませんでした。") }
        let total = YenFormatter.string(from: recap.expense)
        switch recap.change {
        case .noComparison:
            return String(localized: "先週の支出は \(total) でした。", comment: "先週のふりかえり。前の週に支出の記録が無いとき。%@ は先週の支出の合計")
        case .more(let difference):
            let difference = YenFormatter.string(from: difference)
            return String(
                localized: "先週の支出は \(total)。前の週より \(difference) 多めでした。",
                comment: "先週のふりかえり。前の週より多く使ったとき。1 つ目の %@ は先週の支出の合計、2 つ目は前の週との差額"
            )
        case .less(let difference):
            let difference = YenFormatter.string(from: difference)
            return String(
                localized: "先週の支出は \(total)。前の週より \(difference) 少なめでした。",
                comment: "先週のふりかえり。前の週より少なく使ったとき。1 つ目の %@ は先週の支出の合計、2 つ目は前の週との差額"
            )
        case .same:
            return String(localized: "先週の支出は \(total)。前の週と同じでした。", comment: "先週のふりかえり。前の週と同じ額のとき。%@ は先週の支出の合計")
        }
    }

    /// 記録が無かった週に添える案内。例の文は日本語のまま見せる（解析が日本語の入力を前提にしているため、訳さない）。
    static var emptyWeekHint: String {
        let example = "9/23 ランチ 850"
        return String(
            localized: "思い出した支出は、「\(example)」のように日付を付けて記録できます。",
            comment: "先週のふりかえり。記録が無かった週の案内。%@ は日付を付けた入力の例（日本語のまま）"
        )
    }

    /// 週の目安との比べ（「週の目安 ¥35,000 より ¥22,700 少ない」）。目安を出さないときは nil。
    static func paceComparison(for recap: WeeklyRecap) -> (text: String, beyond: Int)? {
        guard let pace = recap.budgetPace, let beyond = recap.spentBeyondPace else { return nil }
        let paceText = YenFormatter.string(from: pace)
        let amount = YenFormatter.string(from: abs(beyond))
        let text = switch beyond {
        case 1...: String(localized: "週の目安 \(paceText) より \(amount) 多い", comment: "先週のふりかえり。1 つ目の %@ は月の予算を日割りした週の目安、2 つ目は差額")
        case ..<0: String(localized: "週の目安 \(paceText) より \(amount) 少ない", comment: "先週のふりかえり。1 つ目の %@ は月の予算を日割りした週の目安、2 つ目は差額")
        default: String(localized: "週の目安 \(paceText) どおり", comment: "先週のふりかえり。%@ は月の予算を日割りした週の目安")
        }
        return (text, beyond)
    }

    /// 予算の目安の文（「これまでの支出から見た、月の予算の目安: ¥120,000」）。
    static func suggestionText(_ suggestion: BudgetSuggestion) -> String {
        String(
            localized: "これまでの支出から見た、月の予算の目安: \(YenFormatter.string(from: suggestion.amount))",
            comment: "先週のふりかえりのカード。%@ は直近の月の支出の中央値を 1,000 円単位に丸めた額"
        )
    }

    /// 予算の目安の出し方の説明（「直近 3 か月の支出の中央値を、1,000 円単位に丸めた額です。」）。
    static func suggestionBasis(_ suggestion: BudgetSuggestion) -> String {
        String(
            localized: "直近 \(suggestion.monthCount) か月の支出の中央値を、1,000 円単位に丸めた額です。",
            comment: "先週のふりかえりのカード。予算の目安の出し方。%lld は元にした月の数（1〜3。記録の無い月は数えない）"
        )
    }

    /// いまの予算（「いまの予算 ¥100,000」）。
    static func currentBudget(_ amount: Int) -> String {
        String(localized: "いまの予算 \(YenFormatter.string(from: amount))", comment: "先週のふりかえりのカード。%@ はいまの月の予算")
    }

    /// VoiceOver に読ませるカードの中身（見出し・期間・定型文・AI の一言・上位のカテゴリ・目安との比べ）。
    static func spokenSummary(
        for recap: WeeklyRecap, remark: String?, calendar: Calendar, catalog: CategoryCatalog = .builtIn
    ) -> String {
        var parts = [String(localized: title), QuestionTexts.dateRange(recap.week, calendar: calendar), fixedSentence(for: recap)]
        if let remark { parts.append(remark) }
        for item in recap.topCategories() {
            parts.append("\(catalog.localizedName(for: item.category)) \(item.spokenValue)")
        }
        if let pace = paceComparison(for: recap) { parts.append(pace.text) }
        return parts.joined(separator: String(localized: LocalizedStringResource(
            "読み上げの区切り", defaultValue: "、", comment: "回答を VoiceOver で読み上げるときの、項目の間の区切り"
        )))
    }
}
