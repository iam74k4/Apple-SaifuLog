import Charts
import SaifuLogCore
import SwiftData
import SwiftUI
import UIKit

/// ⑦ 月のまとめ。何にいくら使ったかを一目で分かるようにする月の報告。ホームの帯（今月の合計）から横に進む。
///
/// 上に月送り（前の月・次の月）、その下に AI の一言（プレミアムと体験中で、AI が使える端末だけ）、月の支出・収入・収支・
/// 1 日あたりの平均・前の月との差、予算の進み（予算を当てはめる月だけ）、カテゴリ別の内訳（横棒グラフと行）を並べる。
/// 行を押すと、その月のそのカテゴリの記録の一覧へ進む。
///
/// 状態と操作は `MonthlyReportModel` が持ち、数字の計算はコア（`MonthlyReport`）が受け持つ。ここは表示と、文字の大きさに
/// 合わせた出し方だけ。アクセシビリティサイズの文字では、グラフを出さずに行（表）だけにする（棒の横に名前と金額を
/// 収める幅が無く、行の文字と同じ内容なので）。
struct MonthlyReportView: View {
    @Bindable var model: MonthlyReportModel

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MonthSwitcher(model: model)
                content
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle("月のまとめ")
        .navigationBarTitleDisplayMode(.inline)
        // ホームはナビゲーションバーを隠しているので、ここでは戻るボタンのために出す。
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $model.selectedCategory) { category in
            CategoryEntriesView(model: model, category: category)
        }
        // 保存先に書き込まれたら読み直す。まとめを開く直前に送った文の読み取り（AI だと 1 秒以上かかる）が、
        // 開いた後に記録されることがあるため。ここから直したり消したりしたときは、モデルが自分で読み直す。
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            model.reload()
        }
        // iCloud で届いたほかの端末の変更でも読み直す（SwiftData が裏で取り込むので didSave にならない）。
        .onReceive(StoreChanges.remote) { _ in
            model.reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshToday() }
        }
        // 日付が変わったとき（0 時・時間帯の変更など）。今月かどうかと平均の日数が変わる。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            model.refreshToday()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loadFailed {
            LoadFailedView(retry: { model.reload() })
        } else if let report = model.report {
            if report.recordCount == 0 {
                EmptyMonthView(isCurrentMonth: report.timing == .current)
            } else {
                // 一言は数字（コードが計算したもの）の前に添える。数字は下のカードにいつも出ている。
                if model.remark.state != .none {
                    RecapRemarkView(state: model.remark.state)
                        .reportCard()
                }
                SummaryCard(report: report)
                if let budget = report.budget {
                    BudgetCard(report: report, budget: budget)
                }
                BreakdownCard(breakdown: report.breakdown, select: { model.showEntries(in: $0) })
            }
        }
    }
}

// MARK: - 月送り

/// 前の月・月の見出し・次の月。今月より先と、記録のある最初の月より前には進めない（ボタンを押せなくする）。
private struct MonthSwitcher: View {
    let model: MonthlyReportModel

    var body: some View {
        HStack(spacing: 8) {
            Button(action: model.showPreviousMonth) {
                chevron("chevron.left", isEnabled: model.canShowPreviousMonth)
            }
            .disabled(!model.canShowPreviousMonth)
            .accessibilityLabel("前の月")
            Text(verbatim: model.monthTitle)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button(action: model.showNextMonth) {
                chevron("chevron.right", isEnabled: model.canShowNextMonth)
            }
            .disabled(!model.canShowNextMonth)
            .accessibilityLabel("次の月")
        }
    }

    /// 矢印は墨にする（山吹は塗りにだけ使い、文字や記号には使わない）。画面の根元で色を墨に決めていて、押せないときに
    /// システムが薄くしてくれないので、押せないときの薄い色はここで付ける。
    private func chevron(_ name: String, isEnabled: Bool) -> some View {
        Image(systemName: name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(isEnabled ? Theme.ink : Theme.inkSecondary.opacity(0.4))
            // 押せる範囲を 44pt 四方以上にする。
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}

// MARK: - 数字

/// 月の支出を大きく、その下に前の月との差、収入・収支・1 日あたりの平均を並べる。
private struct SummaryCard: View {
    let report: MonthlyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("支出")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Text(verbatim: YenFormatter.string(from: report.expense))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    // 金額は桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityElement(children: .combine)
            if let change = report.expenseChange {
                changeLabel(change)
                    .labelStyle(TrendLabelStyle())
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Divider()
            // 収入の色は、収入があるときだけ（¥0 を収入の色にすると、何かあったように見えるため）。
            ReportRow(
                label: Text("収入"), value: YenFormatter.string(from: report.income),
                valueColor: report.income > 0 ? Theme.income : Theme.ink
            )
            ReportRow(label: Text("収支"), value: YenFormatter.signedString(from: report.balance))
            ReportRow(label: Text("1日あたりの平均"), value: YenFormatter.string(from: report.dailyAverage))
        }
        .reportCard()
    }

    /// 前の月との差。多いか少ないかは、矢印だけでなく語でも伝える。
    @ViewBuilder
    private func changeLabel(_ change: Int) -> some View {
        let amount = YenFormatter.string(from: abs(change))
        switch change {
        case 1...:
            Label { Text("前月より \(amount) 多い") } icon: { Image(systemName: "arrow.up.right") }
        case ..<0:
            Label { Text("前月より \(amount) 少ない") } icon: { Image(systemName: "arrow.down.right") }
        default:
            Label { Text("前月と同じ") } icon: { Image(systemName: "equal") }
        }
    }
}

/// 予算の進み。使った額と予算、使った割合のバー（山吹）、残りか超えた額、今月なら 1 日あたりの額と日割りの目安との比べ
/// （先の日付の記録があれば、比べた今日までの支出も）。
///
/// バーは目安として添えるだけで、VoiceOver では読ませない（数字は行の文字で伝える。ホームの帯と同じ）。
/// 予算を超えたことは、注意の色だけでなくアイコンと「オーバー」の語でも伝える。
private struct BudgetCard: View {
    let report: MonthlyReport
    let budget: BudgetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("予算")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            BudgetProgressBar(
                fraction: budget.spentFraction,
                isOver: budget.isOver,
                paceFraction: report.budgetPace.map { min(max(Double($0) / Double(budget.budget), 0), 1) }
            )
            .padding(.vertical, 4)
            if budget.isOver {
                Label {
                    Text("\(YenFormatter.string(from: budget.overspent)) オーバー")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.danger)
                // 金額は桁の途中で改行させない（ホームの帯の「オーバー」と同じ）。この画面は文字の大きさに上限が無く、
                // AX5 ではアイコンに幅を取られて 7 桁の額が折り返すため、縮めて 1 行に収める。
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
            ReportRow(label: Text("使った額"), value: YenFormatter.string(from: budget.spent))
            ReportRow(label: Text("予算"), value: YenFormatter.string(from: budget.budget))
            if !budget.isOver {
                ReportRow(label: Text("残り"), value: YenFormatter.string(from: budget.remaining))
            }
            if report.timing == .current {
                if !budget.isOver {
                    ReportRow(label: Text("1日あたり"), value: YenFormatter.string(from: budget.dailyAllowance))
                }
                if let pace = report.budgetPace, let beyond = report.spentBeyondPace {
                    ReportRow(label: Text("今日までの目安"), value: YenFormatter.string(from: pace))
                    // 目安と比べるのは今日までの支出（MonthlyReport.spentBeyondPace）。先の日付の記録（払う予定の家賃など）が
                    // あると上の「使った額」と違い、比べた結果が「使った額」と目安の差に合わなくなるので、比べた額も出す。
                    if report.expenseThroughToday != budget.spent {
                        ReportRow(label: Text("今日までに使った額"), value: YenFormatter.string(from: report.expenseThroughToday))
                    }
                    paceComparison(beyond)
                        .labelStyle(TrendLabelStyle())
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .reportCard()
    }

    /// 日割りの目安と比べて、多く使っているか少ないか。矢印だけでなく語でも伝える。
    @ViewBuilder
    private func paceComparison(_ beyond: Int) -> some View {
        let amount = YenFormatter.string(from: abs(beyond))
        switch beyond {
        case 1...:
            Label { Text("今日までの目安より \(amount) 多い") } icon: { Image(systemName: "arrow.up.right") }
        case ..<0:
            Label { Text("今日までの目安より \(amount) 少ない") } icon: { Image(systemName: "arrow.down.right") }
        default:
            Label { Text("今日までの目安どおり") } icon: { Image(systemName: "equal") }
        }
    }
}

/// 多い・少ないの矢印と文。アクセシビリティサイズの文字では矢印を省き、文に幅を使わせる（多い・少ないは文で分かる。
/// 矢印を残すと、文が数文字ずつに折り返されて読みにくくなる）。矢印は VoiceOver では読ませない（文と同じ内容のため）。
/// 先週のふりかえりのカードと内訳でも使う。
struct TrendLabelStyle: LabelStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !dynamicTypeSize.isAccessibilitySize {
                configuration.icon
                    .accessibilityHidden(true)
            }
            configuration.title
        }
    }
}

/// 見出しと金額の 1 行。アクセシビリティサイズの文字で 1 行に収まらなければ縦に積み、金額に全幅を使わせる。
/// VoiceOver では 1 行を 1 つの要素として読ませる。先週のふりかえりの内訳でも使う。
struct ReportRow: View {
    let label: Text
    let value: String
    var valueColor: Color = Theme.ink

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                labelText
                Spacer(minLength: 8)
                valueText
            }
            VStack(alignment: .leading, spacing: 2) {
                labelText
                valueText
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelText: some View {
        label
            .foregroundStyle(Theme.inkSecondary)
    }

    private var valueText: some View {
        Text(verbatim: value)
            .monospacedDigit()
            .foregroundStyle(valueColor)
            // 金額は桁の途中で改行させない。
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - カテゴリ別の内訳

/// カテゴリ別の支出。横棒グラフ（アクセシビリティサイズの文字では出さない）と、押すとその期間の記録の一覧へ進む行。
/// 先週のふりかえりの内訳でも使う（期間の言葉だけ差し替える）。
struct BreakdownCard: View {
    let breakdown: CategoryBreakdown
    /// 支出が無いときの案内。
    var emptyText: LocalizedStringResource = "この月の支出の記録はありません"
    /// 行を押したときに開くものの説明（VoiceOver）。
    var rowHint: LocalizedStringResource = "この月の記録の一覧を開きます"
    let select: (EntryCategory) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ別の支出")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if breakdown.isEmpty {
                Text(emptyText)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                if !dynamicTypeSize.isAccessibilitySize {
                    BreakdownChart(items: breakdown.items)
                }
                VStack(spacing: 0) {
                    ForEach(breakdown.items) { item in
                        if item.category != breakdown.items.first?.category {
                            Divider()
                        }
                        BreakdownRow(item: item, hint: rowHint, action: { select(item.category) })
                    }
                }
            }
        }
        .reportCard()
    }
}

/// カテゴリ別の横棒グラフ。棒はカテゴリの色（Theme）で塗り、多い順に上から並べる。
///
/// VoiceOver では棒ごとに「食費」「¥12,300 42%」と読ませる（オーディオグラフでも同じ値をたどれる）。
private struct BreakdownChart: View {
    let items: [CategoryBreakdown.Item]

    @ScaledMetric(relativeTo: .body) private var rowHeight = 30

    var body: some View {
        Chart(items) { item in
            BarMark(
                x: .value("金額", item.amount),
                y: .value("カテゴリ", item.category.rawValue)
            )
            .foregroundStyle(Theme.color(for: item.category))
            .cornerRadius(4)
            .accessibilityLabel(Text(item.category.label))
            .accessibilityValue(Text(verbatim: item.spokenValue))
        }
        // 並びは内訳の順（多い順）に固定する。
        .chartYScale(domain: items.map(\.category.rawValue))
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let rawValue = value.as(String.self), let category = EntryCategory(rawValue: rawValue) {
                        Text(category.label)
                            .font(.caption)
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        // 金額の目盛りは出さない（金額と割合は下の行に文字で出す）。
        .chartXAxis(.hidden)
        .frame(height: rowHeight * CGFloat(items.count))
    }
}

/// 内訳の 1 行。カテゴリの色と記号の丸・名前・金額・割合。押すとその期間のそのカテゴリの記録の一覧へ進む。
private struct BreakdownRow: View {
    let item: CategoryBreakdown.Item
    let hint: LocalizedStringResource
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // アクセシビリティサイズの文字では丸を省き、名前と金額に幅を使わせる（名前は常に出る）。
                if !dynamicTypeSize.isAccessibilitySize {
                    CategoryIcon(category: item.category)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        name
                        Spacer(minLength: 8)
                        figures
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        figures
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        // 文字の色は行の中で決めているので、tint に染めない形にする（押している間は薄くなる）。
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.category.label))
        .accessibilityValue(Text(verbatim: item.spokenValue))
        .accessibilityHint(Text(hint))
    }

    private var name: some View {
        Text(item.category.label)
            .foregroundStyle(Theme.ink)
    }

    private var figures: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: YenFormatter.string(from: item.amount))
                .foregroundStyle(Theme.ink)
            Text(verbatim: item.percentText)
                .foregroundStyle(Theme.inkSecondary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// カテゴリの色と記号の丸（記録の吹き出しの横の丸と同じ）。質問の回答カードの内訳でも使う。
struct CategoryIcon: View {
    let category: EntryCategory

    @ScaledMetric(relativeTo: .body) private var size = 28

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Theme.onCategory)
            .frame(width: size, height: size)
            .background(Theme.color(for: category), in: .circle)
            // 丸はダークでもライトの色で塗る（EntryBubble と同じ理由。ダークの色に白い記号は読めない）。
            .environment(\.colorScheme, .light)
            .accessibilityHidden(true)
    }
}

extension CategoryBreakdown.Item {
    /// 画面に出す割合（「42%」）。0% の行は 0 円ではない（0 円のカテゴリは行にしない）ので「<1%」と出す。
    var percentText: String {
        percent == 0 ? "<1%" : "\(percent)%"
    }

    /// VoiceOver で読む割合。「<」は記号の名前で読まれるので、1% 未満は語で読ませる。
    var spokenPercent: String {
        percent == 0 ? String(localized: "1パーセント未満") : "\(percent)%"
    }

    /// VoiceOver で読む金額と割合（「¥12,300 42%」）。
    var spokenValue: String {
        "\(YenFormatter.string(from: amount)) \(spokenPercent)"
    }
}

// MARK: - 空・失敗

/// 記録の無い月の案内。今月なら、記録するとここに内訳が出ることを伝える。
private struct EmptyMonthView: View {
    let isCurrentMonth: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("この月の記録はありません")
                .font(.title3.bold())
            if isCurrentMonth {
                Text("ホームの入力欄から「ランチ 850」のように送ると、ここに何にいくら使ったかが出ます。")
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

/// 保存先を読めなかったときの案内と、もう一度読むボタン。先週のふりかえりの内訳でも使う。
struct LoadFailedView: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("記録を読み込めませんでした")
                .font(.title3.bold())
            Button(action: retry) {
                Text("もう一度試す")
                    .fontWeight(.semibold)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }
}

extension View {
    /// まとめの 1 まとまり（面の色の角丸の板）。先週のふりかえりの内訳でも使う。
    func reportCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        let context = container.mainContext
        let _ = [
            Entry(amount: 12_300, isIncome: false, category: .food, memo: "スーパー", spentAt: .now, source: .text, originalText: ""),
            Entry(amount: 4_800, isIncome: false, category: .cafe, memo: "", spentAt: .now, source: .text, originalText: ""),
            Entry(amount: 3_200, isIncome: false, category: .transport, memo: "", spentAt: .now, source: .text, originalText: ""),
            Entry(amount: 250_000, isIncome: true, category: .other, memo: "給料", spentAt: .now, source: .text, originalText: ""),
        ].forEach { context.insert($0) }
        let _ = context.insert(Budget(scope: .total, amount: 150_000, updatedAt: .now))
        NavigationStack {
            MonthlyReportView(model: MonthlyReportModel(store: EntryStore(context: context), calendar: .current))
        }
        .modelContainer(container)
    }
}
