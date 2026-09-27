import SaifuLogCore
import SwiftUI

/// ホームの上に置く今月の合計。
///
/// 予算を決める画面（②）ができたら「今月あと ¥…」に置き換える。いまは予算が無いので支出の合計を出す。
struct SummaryHeader: View {
    let summary: MonthlySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今月の支出")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: YenFormatter.string(from: summary.expense))
                .font(.largeTitle.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            if summary.income > 0 {
                HStack(spacing: 4) {
                    Text("今月の収入")
                    Text(verbatim: YenFormatter.string(from: summary.income))
                        .monospacedDigit()
                        .foregroundStyle(Theme.income)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .animation(.default, value: summary)
    }
}

#Preview {
    SummaryHeader(summary: MonthlySummary(expense: 42_380, income: 250_000))
}
