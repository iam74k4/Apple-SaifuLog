import Foundation
import SaifuLogCore

/// カードの締め・引き落としの文（設定の「カード」・質問の答え・読み上げで同じ書き方にする）。
enum CardTexts {
    /// 「12月10日」。日付は締めを数えた時間帯で出す（端末の時間帯を変えても、締めた日がずれて見えないように）。
    static func day(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.month().day()
        style.timeZone = calendar.timeZone
        style.calendar = calendar
        return date.formatted(style)
    }

    /// 締めの期間（「10月16日〜11月15日」）。終わりは締め日。
    static func period(_ statement: CardStatement, calendar: Calendar) -> String {
        String(localized: "\(day(statement.period.start, calendar: calendar))〜\(day(statement.closingDate, calendar: calendar))")
    }

    /// 締め日と引き落とし日の決まり（「15日締め・翌月10日引き落とし」）。31 日は月末と書く。
    static func schedule(of card: PaymentCard) -> String {
        let closing = card.closingDay >= 31
            ? String(localized: "月末締め")
            : String(localized: "\(card.closingDay)日締め")
        let month = card.paymentMonthOffset >= 2 ? String(localized: "翌々月") : String(localized: "翌月")
        let payment = card.paymentDay >= 31
            ? String(localized: "\(month)末日引き落とし")
            : String(localized: "\(month)\(card.paymentDay)日引き落とし")
        return String(localized: "\(closing)・\(payment)")
    }

    /// 日の選択肢の名前（「15日」、31 は「末日」）。
    static func dayChoice(_ day: Int) -> String {
        day >= 31 ? String(localized: "末日") : String(localized: "\(day)日")
    }

    /// カードの質問の答えの読み上げ。
    static func spoken(_ answer: CardAnswer, calendar: Calendar) -> String {
        let parts = answer.rows.map { row in
            let amount = YenFormatter.string(from: row.summary.total)
            switch answer.kind {
            case .nextPayment:
                return String(localized: "\(row.card.name)、\(day(row.summary.statement.paymentDate, calendar: calendar))に \(amount) 引き落とし")
            case .currentUsage, .previousUsage:
                return String(localized: "\(row.card.name)、\(period(row.summary.statement, calendar: calendar))の利用 \(amount)")
            }
        }
        guard !parts.isEmpty else { return String(localized: "登録したカードがありません") }
        return parts.formatted(.list(type: .and))
    }
}
