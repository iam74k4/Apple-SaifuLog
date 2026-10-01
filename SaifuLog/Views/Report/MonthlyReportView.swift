import SaifuLogCore
import SwiftData
import SwiftUI
import UIKit

/// ⑦ 月のまとめ。何にいくら使ったかを一目で分かるようにする月の報告。ホームの帯（今月の合計）から横に進む。
///
/// 上に月送り（前の月・次の月）、その下に AI の一言（プレミアムと体験中で、AI が使える端末だけ）、月の支出・収入・収支・
/// 1 日あたりの平均・前の月との差、予算の進み（予算を当てはめる月だけ）、カテゴリ別の内訳（横棒グラフと行）を並べる。
/// カテゴリ別の予算を決めたカテゴリの行には、その予算の進み（プレミアムと体験中で、予算を当てはめる月だけ）を添える。
/// 行を押すと、その月のそのカテゴリの記録の一覧へ進む。
///
/// 状態と操作は `MonthlyReportModel` が持ち、数字の計算はコア（`MonthlyReport`）が受け持つ。ここは表示と、文字の大きさに
/// 合わせた出し方だけ。アクセシビリティサイズの文字では、グラフを出さずに行（表）だけにする（棒の横に名前と金額を
/// 収める幅が無く、行の文字と同じ内容なので）。
struct MonthlyReportView: View {
    @Bindable var model: MonthlyReportModel

    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    /// 撮影用のデモで下の端へ送るための位置（DEBUG のビルドだけ）。
    @State private var screenshotScrollPosition = ScrollPosition()
    #endif

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
        #if DEBUG
        // 撮影用のデモで、カテゴリ別のグラフと金額の行を写すときだけ下の端へ送る（上から開くと、グラフが画面の下で切れる）。
        // 横に進む動きと中身の並べ直しが済んでから送る。開く時点の位置（defaultScrollAnchor）だけでは、シミュレータ
        // （iOS 26.4）で下の端まで届かずに途中で止まったため。
        .scrollPosition($screenshotScrollPosition)
        .task(id: model.screenshotScrollsToBottom) {
            guard model.screenshotScrollsToBottom else { return }
            try? await Task.sleep(for: .milliseconds(800))
            screenshotScrollPosition.scrollTo(edge: .bottom)
        }
        #endif
        .background(Theme.background)
        .navigationTitle("月のまとめ")
        .navigationBarTitleDisplayMode(.inline)
        // ホームはナビゲーションバーを隠しているので、ここでは戻るボタンのために出す。
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $model.selectedCategory) { category in
            CategoryEntriesView(model: model, category: category)
        }
        .sheet(item: $model.premiumSheet) { premium in
            PremiumSheet(model: premium)
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
                BreakdownCard(
                    breakdown: report.breakdown,
                    categoryBudgets: model.categoryBudgets,
                    budgetedCategoriesWithoutExpense: model.budgetedCategoriesWithoutExpense,
                    select: { model.showEntries(in: $0) }
                )
                if model.showsCategoryBudgetUpsell {
                    CategoryBudgetUpsell(canStartTrial: model.canStartTrial, open: { model.presentPremium() })
                }
            }
        }
    }
}

// MARK: - カテゴリ別の予算の案内

/// 無料の人への、カテゴリ別の予算（プレミアム）の案内。カテゴリ別の支出の下に 1 枚だけ置き、押すとプレミアム（⑨）を開く。
/// 閉じるボタンは付けない（押さなければ何も起きず、1 枚だけで場所も取らないため）。
private struct CategoryBudgetUpsell: View {
    let canStartTrial: Bool
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                // アクセシビリティサイズの文字では印を省き、文に幅を使わせる（返事の行の印と同じ）。
                if !dynamicTypeSize.isAccessibilitySize {
                    PremiumSymbolTile(symbolName: PremiumFeature.categoryBudget.symbolName)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("カテゴリごとに予算を決める")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Group {
                        if canStartTrial {
                            Text("プレミアムの機能です。14日間 無料で試せます。")
                        } else {
                            Text("プレミアムの機能です。")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .reportCard()
        .accessibilityHint("プレミアムの画面を開きます")
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
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
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
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!model.canShowNextMonth)
            .accessibilityLabel("次の月")
        }
    }

    /// 矢印は墨にする（山吹は塗りにだけ使い、文字や記号には使わない）。画面の根元で色を墨に決めていて、押せないときに
    /// システムが薄くしてくれないので、押せないときの薄い色はここで付ける。
    ///
    /// ボタンはガラスの丸にする（ナビゲーションバーの戻るボタンと同じ形。ガラスの余白を足して 44pt 四方になる大きさ）。
    private func chevron(_ name: String, isEnabled: Bool) -> some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Theme.ink : Theme.inkSecondary.opacity(0.4))
            .frame(width: 30, height: 30)
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

/// カテゴリ別の支出。割合を 1 本の横棒で塗り分けた帯（`BreakdownCompositionBar`）と、押すとその期間の記録の一覧へ進む行。
/// 先週のふりかえりの内訳でも使う（期間の言葉だけ差し替える）。カテゴリ別の予算の進みは月のまとめだけが渡す（予算は月の
/// ものなので、週の内訳には渡さない）。
struct BreakdownCard: View {
    let breakdown: CategoryBreakdown
    /// カテゴリ別の予算の進み。渡したカテゴリの行に、使った額と予算・バー・残りか超えた額を添える。
    var categoryBudgets: [EntryCategory: BudgetStatus] = [:]
    /// 予算の進みを出すカテゴリのうち、支出の無いもの。内訳の行の後ろに ¥0 の行として並べる（グラフには足さない）。
    var budgetedCategoriesWithoutExpense: [EntryCategory] = []
    /// 支出が無いときの案内。
    var emptyText: LocalizedStringResource = "この月の支出の記録はありません"
    /// 行を押したときに開くものの説明（VoiceOver）。
    var rowHint: LocalizedStringResource = "この月の記録の一覧を開きます"
    let select: (EntryCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ別の支出")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if breakdown.isEmpty {
                Text(emptyText)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                BreakdownCompositionBar(items: breakdown.items)
            }
            if !breakdown.isEmpty || !budgetedCategoriesWithoutExpense.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Divider()
                        }
                        BreakdownRow(
                            category: row.id,
                            item: row.item,
                            budget: categoryBudgets[row.id],
                            hint: rowHint,
                            // 支出の無い行は押せなくする（開いても記録の一覧は空のため）。
                            action: row.item == nil ? nil : { select(row.id) }
                        )
                    }
                }
            }
        }
        .reportCard()
    }

    /// 並べる行: 内訳の行（支出の多い順）の後ろに、支出の無い予算のカテゴリ（定義順）。
    private var rows: [Row] {
        breakdown.items.map { Row(id: $0.category, item: $0) }
            + budgetedCategoriesWithoutExpense.map { Row(id: $0, item: nil) }
    }

    private struct Row: Identifiable {
        let id: EntryCategory
        /// 内訳の行。支出の無い予算のカテゴリでは nil。
        let item: CategoryBreakdown.Item?
    }
}

/// カテゴリ別の支出の割合を、1 本の横棒の塗り分けで見せる（多い順に左から。色はカテゴリの色）。
///
/// 以前はカテゴリごとの横棒グラフ（Swift Charts）だったが、下の行と同じ並び・同じ値を繰り返して画面の縦を取り、行まで
/// 送らないと金額が見えなかったので、1 本にまとめた。金額と割合は下の行に文字で出すので、帯は目安として添えるだけにし、
/// VoiceOver では読ませない（行が同じ内容を読む）。
struct BreakdownCompositionBar: View {
    let items: [CategoryBreakdown.Item]

    @Environment(\.categoryCatalog) private var catalog
    @ScaledMetric(relativeTo: .body) private var height = 14

    /// 塗り分けの間の隙間と、小さな割合のカテゴリにも残す最低の幅。
    nonisolated static let gap: CGFloat = 2
    nonisolated static let minimumWidth: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let widths = Self.widths(for: items.map(\.amount), in: proxy.size.width)
            HStack(spacing: Self.gap) {
                ForEach(Array(items.enumerated()), id: \.element.category) { index, item in
                    Rectangle()
                        .fill(catalog.color(for: item.category))
                        .frame(width: widths[index])
                }
            }
        }
        .frame(height: height)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }

    /// 幅を金額の比で配る。間の隙間を除いた幅に収め、0 円でない項目は最低の幅を残す（1% 未満のカテゴリも見えるように。
    /// 最低の幅に上げた分は、ほかの項目から比で引く）。
    /// 画面に依存しない計算なので、どのスレッドからも呼べるようにする（テストから呼ぶ）。
    nonisolated static func widths(for amounts: [Int], in total: CGFloat) -> [CGFloat] {
        let sum = amounts.reduce(0, +)
        let available = total - gap * CGFloat(max(amounts.count - 1, 0))
        guard sum > 0, available > 0 else { return amounts.map { _ in 0 } }
        var widths = amounts.map { available * CGFloat($0) / CGFloat(sum) }
        let small = Set(widths.indices.filter { amounts[$0] > 0 && widths[$0] < minimumWidth })
        guard !small.isEmpty, small.count < widths.count else { return widths }
        let raised = small.reduce(CGFloat(0)) { $0 + (minimumWidth - widths[$1]) }
        let others = widths.indices.filter { !small.contains($0) }.reduce(CGFloat(0)) { $0 + widths[$1] }
        for index in widths.indices {
            if small.contains(index) {
                widths[index] = minimumWidth
            } else if others > 0 {
                widths[index] -= raised * widths[index] / others
            }
        }
        return widths
    }
}

/// 内訳の 1 行。カテゴリの色と記号の丸・名前・金額・割合。押すとその期間のそのカテゴリの記録の一覧へ進む。
/// カテゴリ別の予算があれば、その下に予算の進み（`CategoryBudgetProgress`）を添える。
private struct BreakdownRow: View {
    let category: EntryCategory
    /// 内訳の行。支出の無い予算のカテゴリでは nil（金額は ¥0 で、割合は出さない）。
    let item: CategoryBreakdown.Item?
    /// そのカテゴリの予算の進み。予算が無いか、出さないときは nil。
    let budget: BudgetStatus?
    let hint: LocalizedStringResource
    /// 押したとき。nil なら押せない行にする（支出の無い予算のカテゴリ）。
    let action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.categoryCatalog) private var catalog

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            // 文字の色は行の中で決めているので、tint に染めない形にする（押している間は薄くなる）。
            .buttonStyle(.plain)
            .accessibilityLabel(catalog.label(for: category))
            .accessibilityValue(Text(verbatim: spokenValue))
            .accessibilityHint(Text(hint))
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(catalog.label(for: category))
                .accessibilityValue(Text(verbatim: spokenValue))
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            // アクセシビリティサイズの文字では丸を省き、名前と金額に幅を使わせる（名前は常に出る）。
            if !dynamicTypeSize.isAccessibilitySize {
                CategoryIcon(category: category)
            }
            VStack(alignment: .leading, spacing: 8) {
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
                if let budget {
                    CategoryBudgetProgress(budget: budget)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 押せない行にも同じ幅を空けておき、金額の右端をほかの行とそろえる。
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .opacity(action == nil ? 0 : 1)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private var name: some View {
        catalog.label(for: category)
            .foregroundStyle(Theme.ink)
    }

    private var figures: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: YenFormatter.string(from: item?.amount ?? 0))
                .foregroundStyle(Theme.ink)
            if let item {
                Text(verbatim: item.percentText)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    /// VoiceOver で読む値。金額と割合（支出の無い行は金額だけ）に、予算の進み（「予算 ¥…、使った額 ¥…、残り ¥…」）を足す。
    /// 予算の進みのバーは読ませないので、進みは文で伝える。区切りは言語に合わせる（ホームの帯の読み上げと同じ）。
    private var spokenValue: String {
        var items = [item?.spokenValue ?? YenFormatter.string(from: 0)]
        if let budget {
            items += budget.spokenProgress
        }
        return items.formatted(.list(type: .and))
    }
}

/// カテゴリの行に添える予算の進み。使った割合のバー（山吹。超えたら注意の色で満たす）と、「使った額 / 予算」、残りか超えた額。
///
/// 超えたことは、注意の色だけでなくアイコンと「オーバー」の語でも伝える（全体の予算のカードと同じ）。バーと文は VoiceOver では
/// 読ませず、行の読み上げ（`BudgetStatus.spokenProgress`）で伝える。金額は桁の途中で改行させない。
private struct CategoryBudgetProgress: View {
    let budget: BudgetStatus

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            BudgetProgressBar(fraction: budget.spentFraction, isOver: budget.isOver)
            // アクセシビリティサイズの文字では、「/」の後で改行して金額を 1 行ずつにし、残りか超えた額もその下に置く（1 行に
            // 並べると金額が縮みすぎるため）。それより小さい文字では、1 行に収まらなければ縦に積む。
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    amountLine("\(spent) /")
                    amountLine(limit)
                    status
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        amountLine("\(spent) / \(limit)")
                        Spacer(minLength: 8)
                        status
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        amountLine("\(spent) / \(limit)")
                        status
                    }
                }
            }
        }
        .font(.footnote)
        .accessibilityHidden(true)
    }

    private var spent: String {
        YenFormatter.string(from: budget.spent)
    }

    private var limit: String {
        YenFormatter.string(from: budget.budget)
    }

    /// 金額の文字の 1 行。桁の途中で折らず、収まらなければ縮める。
    private func amountLine(_ text: String) -> some View {
        Text(verbatim: text)
            .monospacedDigit()
            .foregroundStyle(Theme.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private var status: some View {
        if budget.isOver {
            Group {
                // アクセシビリティサイズの文字では、アイコンを文の上に置き、文に行の幅をすべて使わせる（横に並べると、アイコンに
                // 幅を取られて文が縮み、行のほかの金額まで小さくなった。シミュレータの AX5 で確かめた）。
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        overIcon
                        overTextStacked
                    }
                } else {
                    Label { overText } icon: { overIcon }
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(Theme.danger)
        } else {
            Text("残り \(YenFormatter.string(from: budget.remaining))")
                .foregroundStyle(Theme.inkSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var overIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
    }

    /// 「¥2,300 オーバー」の文（訳したもの）。
    private var overString: String {
        String(localized: "\(YenFormatter.string(from: budget.overspent)) オーバー")
    }

    /// 「¥2,300 オーバー」。金額は桁の途中で改行させず（全体の予算のカードの「オーバー」と同じ）、収まらなければ縮める。
    private var overText: some View {
        Text(verbatim: overString)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// アクセシビリティサイズの文字の「¥2,300 オーバー」。1 行に収まらなければ、金額と語を 2 行に分ける。
    ///
    /// 1 行のまま縮めると、日本語の文は大きく縮んで読みにくく、折り返しに任せると「オー」「バー」のように語の途中で折れた
    /// （シミュレータの AX5 で確かめた）。分けられない文（訳で金額が語の後ろに来るなど）は 1 行のまま縮める。
    @ViewBuilder
    private var overTextStacked: some View {
        let text = overString
        if let lines = BudgetOverText.lines(text, amount: YenFormatter.string(from: budget.overspent)) {
            ViewThatFits(in: .horizontal) {
                Text(verbatim: text)
                    .monospacedDigit()
                    .fixedSize()
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: lines.amount)
                    Text(verbatim: lines.rest)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
        } else {
            overText
        }
    }
}

/// 予算を超えた額の文（「¥2,300 オーバー」）の分け方。
enum BudgetOverText {
    /// 訳した文を、金額まで（「¥2,300」）と残りの語（「オーバー」「over」）の 2 行に分ける。文の中に金額が無いか、金額の前か
    /// 後ろに何も無ければ（訳で語順が変わったときなど）nil。
    static func lines(_ text: String, amount: String) -> (amount: String, rest: String)? {
        guard let range = text.range(of: amount) else { return nil }
        let head = text[..<range.upperBound].trimmingCharacters(in: .whitespaces)
        let rest = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !head.isEmpty, !rest.isEmpty else { return nil }
        return (head, rest)
    }
}

extension BudgetStatus {
    /// VoiceOver で読む予算の進み（「予算 ¥40,000」「使った額 ¥12,300」「残り ¥27,700」か「¥2,300 オーバー」）。
    /// 並べ方は呼び出し側が言語に合わせて決める（`formatted(.list(type: .and))`）。
    var spokenProgress: [String] {
        [
            String(localized: "予算 \(YenFormatter.string(from: budget))"),
            String(localized: "使った額 \(YenFormatter.string(from: spent))"),
            isOver
                ? String(localized: "\(YenFormatter.string(from: overspent)) オーバー")
                : String(localized: "残り \(YenFormatter.string(from: remaining))"),
        ]
    }
}

/// カテゴリの色と記号の丸（記録の吹き出しの横の丸と同じ）。質問の回答カードの内訳でも使う。
struct CategoryIcon: View {
    let category: EntryCategory

    @Environment(\.categoryCatalog) private var catalog
    @ScaledMetric(relativeTo: .body) private var size = 28

    var body: some View {
        Image(systemName: catalog.symbolName(for: category))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Theme.onCategory)
            .frame(width: size, height: size)
            .background(catalog.color(for: category), in: .circle)
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

#Preview("カテゴリ別の予算（プレミアム）") {
    if let container = try? ModelContainerFactory.makeInMemoryContainer() {
        let context = container.mainContext
        let _ = [
            Entry(amount: 12_300, isIncome: false, category: .food, memo: "スーパー", spentAt: .now, source: .text, originalText: ""),
            Entry(amount: 4_800, isIncome: false, category: .cafe, memo: "", spentAt: .now, source: .text, originalText: ""),
            Entry(amount: 3_200, isIncome: false, category: .transport, memo: "", spentAt: .now, source: .text, originalText: ""),
        ].forEach { context.insert($0) }
        let _ = [
            Budget(scope: .category(.food), amount: 40_000, updatedAt: .now),
            Budget(scope: .category(.cafe), amount: 4_000, updatedAt: .now),
            Budget(scope: .category(.medical), amount: 5_000, updatedAt: .now),
        ].forEach { context.insert($0) }
        let purchases = PurchaseManager(
            loadPurchases: { [VerifiedPurchase(transactionID: 1, purchase: PremiumPurchase(product: .premium, purchaseDate: .now))] },
            loadProducts: { _ in [] },
            sync: {}
        )
        NavigationStack {
            MonthlyReportView(model: MonthlyReportModel(
                store: EntryStore(context: context), calendar: .current, purchases: purchases
            ))
        }
        .modelContainer(container)
        .task { await purchases.refreshPurchases() }
    }
}
