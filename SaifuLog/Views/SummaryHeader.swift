import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの上に置く今月の帯。
///
/// 予算を決めていれば「今月あと ¥…」を大きく、「1日あたり ¥… ・のこり N 日」を小さく出し、使った割合を
/// 山吹のバーで示す。予算を超えたら「¥… オーバー」を注意の色とアイコンと文字で出す（色だけに頼らない）。
/// 予算を決めていなければ、今月の支出の合計と「予算を決める」のボタンを出す。
struct SummaryHeader: View {
    let summary: MonthlySummary
    /// 今月の予算の進み。予算を決めていなければ nil。
    let budget: BudgetStatus?
    /// 予算を決める（変える）画面を出す。
    let editBudget: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleRow
            figures
                // VoiceOver では、数字をまとめて 1 つの要素として読ませる（見出し・残り・1 日あたり・残りの日数・
                // 予算と使った額・収入の順）。ボタンより先に読ませる。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(Text(verbatim: spokenFigures))
                .accessibilitySortPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        // 上はボタンの高さ（44pt）の中に余白があるので詰める。
        .padding(.top, 4)
        .padding(.bottom, 12)
        // 画面の背景と同じ色で塗る。すりガラス（.bar）は灰色がかり、墨 × 山吹の温かい地から浮くため。
        // 不透明なので、上へ流れた記録は帯の下に隠れる。
        .background(Theme.background)
        // 帯とタイムラインが同じ色なので、境目が無いと帯の下で一直線に切れた吹き出しが帯の一部に見える
        // （すりガラスのころはぼかしが境目になっていた）。下端に細い線を引いて帯の終わりを示す。
        // iOS 26 のスクロール端の効果（safeAreaBar）は、不透明な帯の下に隠れて境目にならなかった。
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .animation(.default, value: summary)
        .animation(.default, value: budget)
    }

    /// 見出し（予算の有無と超えたかで変わる）。
    private var title: Text {
        switch budget {
        case nil: Text("今月の支出")
        case let budget? where budget.isOver: Text("今月の予算")
        case _?: Text("今月あと")
        }
    }

    /// 見出しと、予算を決める（変える）ボタンの行。アクセシビリティサイズの文字で 1 行に収まらなければ縦に積む。
    @ViewBuilder
    private var titleRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    titleText
                    Spacer(minLength: 8)
                    budgetButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    titleText
                    budgetButton
                }
            }
        } else {
            HStack(spacing: 0) {
                titleText
                Spacer(minLength: 8)
                budgetButton
            }
        }
    }

    private var titleText: some View {
        title
            .font(.subheadline)
            .foregroundStyle(Theme.inkSecondary)
            // 見出しは下の数字の要素の名前として読ませる（ここで読むと 2 回になる）。
            .accessibilityHidden(true)
    }

    private var budgetButton: some View {
        Button(action: editBudget) {
            Text(budget == nil ? "予算を決める" : "予算を変更")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .lineLimit(1)
                // 押せる範囲を 44pt 四方以上にする。
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
    }

    @ViewBuilder
    private var figures: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let budget {
                budgetFigures(budget)
            } else {
                amount(YenFormatter.string(from: summary.expense))
            }
            if summary.income > 0 {
                incomeRow
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private func budgetFigures(_ budget: BudgetStatus) -> some View {
        if budget.isOver {
            // 超えたことは、注意の色だけでなく、アイコンと「オーバー」の語でも伝える。
            Label {
                Text("\(YenFormatter.string(from: budget.overspent)) オーバー")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.largeTitle.bold())
            .monospacedDigit()
            .foregroundStyle(Theme.danger)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
        } else {
            amount(YenFormatter.string(from: budget.remaining))
        }
        detailRow(budget)
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
        BudgetProgressBar(fraction: budget.spentFraction, isOver: budget.isOver)
            .padding(.vertical, 4)
    }

    /// 「1日あたり ¥… ・のこり N 日」（超えたら「予算 ¥… ・のこり N 日」）。アクセシビリティサイズの文字で
    /// 1 行に収まらなければ縦に積み、そのときだけ区切りの点を外す（行の頭に点が残らないように）。
    @ViewBuilder
    private func detailRow(_ budget: BudgetStatus) -> some View {
        let lead = budget.isOver
            ? figure(Text("予算 \(YenFormatter.string(from: budget.budget))"))
            : figure(Text("1日あたり \(YenFormatter.string(from: budget.dailyAllowance))"))
        let days = figure(Text("のこり \(budget.remainingDays) 日"))
        let inline = HStack(alignment: .firstTextBaseline, spacing: 4) {
            lead
            // 区切りの点も訳す。日本語の中黒（全角）のままだと、英語の半角の文の間で幅が広く浮いて見えるため
            // （英語では中点「·」にする）。
            Text("・")
            days
        }
        if dynamicTypeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                inline
                VStack(alignment: .leading, spacing: 2) {
                    lead
                    days
                }
            }
        } else {
            inline
        }
    }

    /// 大きく出す金額。
    private func amount(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.largeTitle.bold())
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            // 金額は「¥」と数字の間や桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
    }

    /// 小さく出す数字の 1 項目。桁の途中で改行させない。
    private func figure(_ text: Text) -> some View {
        text
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// 今月の収入の行。アクセシビリティサイズの文字では、横に並べると金額が桁の途中で折り返されることが
    /// あるので、1 行に収まらなければ見出しと金額を縦に積み、金額に全幅を使わせる。
    private var incomeRow: some View {
        AdaptiveRow(stacks: dynamicTypeSize.isAccessibilitySize, alignment: .firstTextBaseline, spacing: 4) {
            Text("今月の収入")
            Text(verbatim: YenFormatter.string(from: summary.income))
                .monospacedDigit()
                .foregroundStyle(Theme.income)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// VoiceOver で読ませる数字（見出しの後に続く）。画面に出ている項目に「予算」と「使った額」を足し、言語に合った
    /// 区切りで並べる。予算と使った額は画面には出さない（予算は超えたときだけ出す）が、読ませないバーの代わりに、
    /// 予算のうちどれだけ使ったかを伝えるために読む。
    private var spokenFigures: String {
        var items: [String] = []
        if let budget {
            if budget.isOver {
                items.append(String(localized: "\(YenFormatter.string(from: budget.overspent)) オーバー"))
            } else {
                items.append(YenFormatter.string(from: budget.remaining))
                items.append(String(localized: "1日あたり \(YenFormatter.string(from: budget.dailyAllowance))"))
            }
            items.append(String(localized: "のこり \(budget.remainingDays) 日"))
            items.append(String(localized: "予算 \(YenFormatter.string(from: budget.budget))"))
            items.append(String(localized: "使った額 \(YenFormatter.string(from: budget.spent))"))
        } else {
            items.append(YenFormatter.string(from: summary.expense))
        }
        if summary.income > 0 {
            items.append(String(localized: "今月の収入 \(YenFormatter.string(from: summary.income))"))
        }
        return items.formatted(.list(type: .and))
    }
}

/// 予算のうち使った割合のバー。山吹で塗り、予算を超えたら注意の色で満たす。
///
/// 数字（残り・超えた額）は帯の文字で出しているので、バーは目安として添えるだけにし、VoiceOver では読ませない
/// （割合は帯の要素の「予算」「使った額」で伝わる）。
private struct BudgetProgressBar: View {
    let fraction: Double
    let isOver: Bool

    @ScaledMetric(relativeTo: .footnote) private var height = 6

    var body: some View {
        Capsule()
            .fill(Theme.track)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(isOver ? Theme.danger : Theme.accentFill)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .clipShape(.capsule)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// 横に並べる行。`stacks` のとき（アクセシビリティサイズの文字）は、1 行に収まらなければ縦に積む。
///
/// 一律に縦に積むと、1 行に収まるものまで行が増えて帯が高くなり、タイムラインの場所が減るため、
/// 収まるかどうかで選ぶ。
private struct AdaptiveRow<Content: View>: View {
    let stacks: Bool
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat?
    @ViewBuilder let content: Content

    var body: some View {
        if stacks {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: alignment, spacing: spacing) { content }
                VStack(alignment: .leading, spacing: 2) { content }
            }
        } else {
            HStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}

/// 今日を含む月の記録と予算を読み、SummaryHeader に合計と予算の進みを出す。
///
/// 読み込みの条件は月ごとに変わるので、今日を受け取るビューに @Query を置く
/// （呼び出し側が今日を変えると、ここが作り直されて条件も変わる）。予算の行は少ないので全部読む。
struct MonthSummaryHeader: View {
    private let today: Date
    private let calendar: Calendar
    private let editBudget: () -> Void
    @Query private var records: [Entry]
    @Query private var budgets: [Budget]

    init(today: Date, calendar: Calendar, editBudget: @escaping () -> Void) {
        self.today = today
        self.calendar = calendar
        self.editBudget = editBudget
        _records = Query(Entry.monthDescriptor(containing: today, calendar: calendar))
    }

    var body: some View {
        let figures = Self.figures(records: records, budgets: budgets, today: today, calendar: calendar)
        SummaryHeader(summary: figures.summary, budget: figures.budget, editBudget: editBudget)
    }

    /// 帯に出す今月の合計と予算の進み。
    ///
    /// 月の集計（`LedgerSummary`）は 1 回だけ行い、合計と予算の進みの両方に使う（同じ記録から別々に数えて、
    /// 合計と予算の「使った額」が食い違わないように）。
    static func figures(
        records: [Entry], budgets: [Budget], today: Date, calendar: Calendar
    ) -> (summary: MonthlySummary, budget: BudgetStatus?) {
        guard let month = ReportPeriod.thisMonth.interval(now: today, calendar: calendar) else {
            return (MonthlySummary(), nil)
        }
        let ledger = LedgerSummary(records: records, interval: month, calendar: calendar)
        let budget = BudgetStatus(budget: BudgetPlan.resolve(budgets).total, summary: ledger, now: today, calendar: calendar)
        return (MonthlySummary(ledger), budget)
    }
}

#Preview("予算なし") {
    SummaryHeader(summary: MonthlySummary(expense: 42_380, income: 250_000), budget: nil, editBudget: {})
}

#Preview("予算あり") {
    SummaryHeader(
        summary: MonthlySummary(expense: 57_000),
        budget: BudgetStatus(
            budget: 150_000, spent: 57_000, now: .now,
            month: Calendar.current.dateInterval(of: .month, for: .now)!, calendar: .current
        ),
        editBudget: {}
    )
}

#Preview("予算オーバー") {
    SummaryHeader(
        summary: MonthlySummary(expense: 162_000, income: 500),
        budget: BudgetStatus(
            budget: 150_000, spent: 162_000, now: .now,
            month: Calendar.current.dateInterval(of: .month, for: .now)!, calendar: .current
        ),
        editBudget: {}
    )
}
