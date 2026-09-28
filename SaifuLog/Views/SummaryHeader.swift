import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの上に置く今月の合計。
///
/// 予算を決める画面（②）ができたら「今月あと ¥…」に置き換える。いまは予算が無いので支出の合計を出す。
struct SummaryHeader: View {
    let summary: MonthlySummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今月の支出")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(verbatim: YenFormatter.string(from: summary.expense))
                .font(.largeTitle.bold())
                .monospacedDigit()
                // 金額は「¥」と数字の間や桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if summary.income > 0 {
                incomeRow
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

    /// 今月の収入の行。アクセシビリティサイズの文字では、横に並べると金額が桁の途中で折り返されることが
    /// あるので、1 行に収まらなければ見出しと金額を縦に積み、金額に全幅を使わせる。
    @ViewBuilder
    private var incomeRow: some View {
        let content = Group {
            Text("今月の収入")
            Text(verbatim: YenFormatter.string(from: summary.income))
                .monospacedDigit()
                .foregroundStyle(Theme.income)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        if dynamicTypeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { content }
                VStack(alignment: .leading, spacing: 2) { content }
            }
        } else {
            HStack(spacing: 4) { content }
        }
    }
}

/// `month` を含む月の記録だけを読み、SummaryHeader に合計を出す。
///
/// 読み込みの条件は月ごとに変わるので、月を受け取るビューに @Query を置く
/// （呼び出し側が月を変えると、ここが作り直されて条件も変わる）。
struct MonthSummaryHeader: View {
    private let month: Date
    private let calendar: Calendar
    @Query private var records: [Entry]

    init(month: Date, calendar: Calendar) {
        self.month = month
        self.calendar = calendar
        _records = Query(Entry.monthDescriptor(containing: month, calendar: calendar))
    }

    var body: some View {
        SummaryHeader(summary: MonthlySummary(records: records, month: month, calendar: calendar))
    }
}

#Preview {
    SummaryHeader(summary: MonthlySummary(expense: 42_380, income: 250_000))
}
