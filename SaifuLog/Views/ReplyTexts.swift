import Foundation
import SaifuLogCore
import SwiftUI

/// ホームのタイムラインの、送信へのアプリの返事（`RecordedReplyCard`）に添える文。数字はどれもコードが計算したもの
/// （AI には書かせない。docs/design.md §3-4・§9）で、AI が使えない端末でも同じ文になる。
enum ReplyTexts {
    /// 解析がメモに書き足した説明（`EntryMemoNote`）を、返事の行の下に添える文にする（「¥12,000 を4人で割り勘。立て替えた ¥9,000 は
    /// メモに残しました。」）。
    ///
    /// メモ（保存する形）は変えないので、⑥ のメモの欄と CSV には説明が書かれたまま残る。「メモに残しました」はそのことを指す。
    static func note(for note: EntryMemoNote) -> String {
        switch note.kind {
        case .split(let split):
            let total = YenFormatter.string(from: split.total)
            // 立て替えた額が 0 になるのは、総額が人数より少ないとき（¥1 を 2 人で割る）だけ。0 円の立て替えは書かない。
            guard split.advance > 0 else {
                return String(
                    localized: "\(total) を\(split.count)人で割り勘。",
                    comment: "ホームの返事の行の下の文（割り勘で、立て替えた額が無いとき）。%1$@ は総額、%2$lld は人数（2 以上）"
                )
            }
            return String(
                localized: "\(total) を\(split.count)人で割り勘。立て替えた \(YenFormatter.string(from: split.advance)) はメモに残しました。",
                comment: "ホームの返事の行の下の文（割り勘）。%1$@ は総額、%2$lld は人数（2 以上）、%3$@ はほかの人の分として立て替えた額（あとで返ってくる額）。メモ（直す画面のメモの欄）には「焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）」のように書いてある"
            )
        case .perPerson(let count?):
            return String(
                localized: "\(count)人で割り勘の1人分として記録しました。",
                comment: "ホームの返事の行の下の文。「1人3000」のように 1 人分として書かれた額を、割らずにそのまま記録したとき。%lld は割り勘の人数（2 以上）"
            )
        case .perPerson(nil):
            return String(
                localized: "1人分として記録しました。",
                comment: "ホームの返事の行の下の文。「ひとり3000」のように 1 人分として書かれた額を、割らずにそのまま記録したとき（割り勘の人数は書かれていない）"
            )
        }
    }

    /// 直前の送信の返事の最後に添える、今月の状況の一行。ホームの帯と同じ数字（`MonthSummaryHeader.figures`）から作る。
    ///
    /// - 予算を決めていれば「今月あと ¥…（1日あたり ¥…）」、超えていれば「今月の予算を ¥… 超えています」（額を注意の色に）。
    /// - 予算を決めていなければ「今月の支出 ¥…」。
    /// - 収入だけの送信（給料など）は、予算があっても「今月の収入 ¥…」。予算の残りは収入で増えない（`BudgetStatus`）ので、
    ///   給料を送った返事に予算の残りを出しても、送ったものと関係の無い数字になるため。
    static func status(summary: MonthlySummary, budget: BudgetStatus?, isIncomeOnly: Bool) -> ReplySentence {
        if isIncomeOnly {
            let income = YenFormatter.string(from: summary.income)
            return ReplySentence(
                text: String(localized: LocalizedStringResource(
                    "今月の収入 %@（返事）", defaultValue: "今月の収入 \(income)",
                    comment: "ホームの返事のカードの最後の一行（直前の送信が収入だけのとき）。%@ は今月の収入の合計（「¥250,000」）"
                )),
                figures: [income]
            )
        }
        guard let budget else {
            let expense = YenFormatter.string(from: summary.expense)
            return ReplySentence(
                text: String(
                    localized: "今月の支出 \(expense)",
                    comment: "ホームの返事のカードの最後の一行（直前の送信で、月の予算を決めていないとき）。%@ は今月の支出の合計（「¥42,380」）"
                ),
                figures: [expense]
            )
        }
        if budget.isOver {
            let over = YenFormatter.string(from: budget.overspent)
            return ReplySentence(
                text: String(
                    localized: "今月の予算を \(over) 超えています",
                    comment: "ホームの返事のカードの最後の一行（直前の送信で、今月の予算を超えたとき）。%@ は超えた額（「¥3,000」）。額は注意の色で、アイコンを添えて出す"
                ),
                figures: [over],
                isWarning: true
            )
        }
        let remaining = YenFormatter.string(from: budget.remaining)
        let daily = YenFormatter.string(from: budget.dailyAllowance)
        return ReplySentence(
            text: String(
                localized: "今月あと \(remaining)（1日あたり \(daily)）",
                comment: "ホームの返事のカードの最後の一行（直前の送信で、月の予算を決めているとき）。%1$@ は今月の予算の残り、%2$@ は今日から月末まで 1 日あたりに使える額（ホームの帯と同じ数字）"
            ),
            figures: [remaining, daily]
        )
    }
}

/// コードが数字を入れた返事の文と、その中で強める数字（直前の送信の返事の今月の状況・質問の答え）。
///
/// 文（`text`）はそのまま VoiceOver に読ませ、画面に出すときだけ数字を太字にする（`attributed`）。数字は「¥12,000」のように
/// 桁区切りまで含めて 1 つにする。文の中の金額は、1 行に収まる幅があれば桁の途中で折り返されない（文字の組みの決まりで、
/// 標準と AX5 の文字で幅を変えながら画像で確かめた）ので、区切りの記号は入れない。
struct ReplySentence: Equatable {
    /// 文（訳した文に、コードが計算した数字を入れたもの）。
    let text: String
    /// 文の中で強める数字（金額・件数）。
    let figures: [String]
    /// 数字を注意の色で出すか（予算を超えた額）。文も「超えています」と言うので、色だけで伝えることにはならない。
    var isWarning = false

    /// 数字を太字にした文字。
    ///
    /// - Parameter figureColor: 数字の色。nil なら文の色のまま。
    func attributed(figureColor: Color? = nil) -> AttributedString {
        var result = AttributedString(text)
        for figure in figures where !figure.isEmpty {
            var start = result.startIndex
            while start < result.endIndex, let range = result[start...].range(of: figure) {
                // 「¥4,209」を探して「¥14,209」の一部に当てないよう、前後に数字が続く所は飛ばす。
                if !Self.touchesDigit(range, in: result) {
                    result[range].inlinePresentationIntent = .stronglyEmphasized
                    if let figureColor { result[range].foregroundColor = figureColor }
                }
                start = range.upperBound
            }
        }
        return result
    }

    /// 範囲のすぐ前かすぐ後ろが数字（か桁区切り）か。
    private static func touchesDigit(_ range: Range<AttributedString.Index>, in text: AttributedString) -> Bool {
        let characters = text.characters
        let isDigit: (Character) -> Bool = { ($0.isASCII && $0.isWholeNumber) || $0 == "," }
        if range.lowerBound > characters.startIndex, isDigit(characters[characters.index(before: range.lowerBound)]) {
            return true
        }
        return range.upperBound < characters.endIndex && isDigit(characters[range.upperBound])
    }
}
