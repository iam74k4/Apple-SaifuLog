import SaifuLogCore
import SwiftUI

/// タイムラインの 1 件。自分が送ったメッセージのように右寄せの吹き出しで出す。
struct EntryBubble: View {
    let entry: Entry

    @ScaledMetric(relativeTo: .body) private var iconSize = 28

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    title
                        .multilineTextAlignment(.trailing)
                    Text(verbatim: amountText)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(entry.isIncome ? Theme.income : .primary)
                }
                HStack(spacing: 6) {
                    kindLabel
                    Text(entry.spentAt, format: .dateTime.month().day())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.bubble, in: .rect(cornerRadius: 18))

            Image(systemName: entry.isIncome ? "yensign" : entry.category.symbolName)
                .font(.system(size: iconSize * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: iconSize, height: iconSize)
                .background(tint, in: .circle)
                .accessibilityHidden(true)
        }
        // VoiceOver では 1 件を 1 つの要素として、品目・金額・カテゴリ・日付の順に読ませる。
        .accessibilityElement(children: .combine)
    }

    /// メモが空なら（品目が書かれていなければ）カテゴリ名を見出しにする。
    @ViewBuilder
    private var title: some View {
        if entry.memo.isEmpty {
            Text(entry.isIncome ? "収入" : entry.category.label)
        } else {
            Text(verbatim: entry.memo)
        }
    }

    @ViewBuilder
    private var kindLabel: some View {
        if entry.isIncome {
            Text("収入")
        } else {
            Text(entry.category.label)
        }
    }

    private var amountText: String {
        entry.isIncome ? YenFormatter.signedString(from: entry.amount) : YenFormatter.string(from: entry.amount)
    }

    private var tint: Color {
        entry.isIncome ? Theme.income : Theme.color(for: entry.category)
    }
}
