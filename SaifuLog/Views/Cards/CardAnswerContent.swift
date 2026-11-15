import SaifuLogCore
import SwiftUI

/// カードの質問（「楽天カードの利用額は？」「次の引き落としはいくら？」）の答えの中身。返事のカードの中に置く。
///
/// カードごとに、額（大きく）と、締めの期間・引き落とし日を出す。カードが 2 枚以上なら合計も出す。数字はコードが数えたもの
/// （`CardStatementSummary`）。
struct CardAnswerContent: View {
    let answer: CardAnswer

    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
            ForEach(answer.rows) { row in
                rowView(row)
            }
            if answer.rows.count >= 2 {
                Divider()
                HStack {
                    Text("合計")
                    Spacer(minLength: 8)
                    Text(YenFormatter.string(from: answer.total))
                        .monospacedDigit()
                }
                .font(.headline)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(AccessibilityID.Reply.answerSummary)
    }

    private var title: LocalizedStringResource {
        switch answer.kind {
        case .nextPayment: "次の引き落とし"
        case .currentUsage: "今の締めの利用額"
        case .previousUsage: "前の締めの利用額"
        }
    }

    private func rowView(_ row: CardAnswer.Row) -> some View {
        let statement = row.summary.statement
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: row.card.name)
                .font(.headline)
            Text(YenFormatter.string(from: row.summary.total))
                .font(answer.rows.count == 1 ? .largeTitle.weight(.bold) : .title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Group {
                switch answer.kind {
                case .nextPayment:
                    Text("\(CardTexts.day(statement.paymentDate, calendar: calendar))に引き落とし（\(CardTexts.period(statement, calendar: calendar))の利用）")
                case .currentUsage, .previousUsage:
                    Text("\(CardTexts.period(statement, calendar: calendar))の利用・\(CardTexts.day(statement.paymentDate, calendar: calendar))に引き落とし")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
