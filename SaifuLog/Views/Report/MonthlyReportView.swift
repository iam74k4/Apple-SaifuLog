import SaifuLogCore
import SwiftData
import SwiftUI
import UIKit

/// ⑦ 月のまとめ（月の画面）。何にいくら使ったかを一目で分かるようにする月の報告。ホームの帯（今月の合計）から横に進む。
///
/// 上のバーに「内訳」と「カレンダー」の切り替え、下に浮くバーに月送り（前の月・月の題・次の月と「今月」）を置き、ガラスは
/// この 2 つのバーにだけ使う（Liquid Glass は中身の層に使わない）。中身は、月に使った額（大きく）と前の月との差（終わった
/// 月だけ）、収入があれば収入と収支の小さな 1 行を共通に出し、その下に、内訳なら予算の進み（予算を当てはめる月だけ）と
/// カテゴリ別の内訳（割合の帯と行）、カレンダーなら日ごとに使った額と選んだ日の記録（`MonthCalendarContent`）を並べる。
/// 前はカレンダーを、ホームを左へスワイプした別のページにしていたが、見えない入口で見つけにくく、同じ月を 2 つの画面で
/// 見せていたので、この画面の切り替えにまとめた。
/// 「いくら使ったか」がすぐ分かるよう、平均や日割りの目安のような副次的な数字は出さない（質問で聞ける）。
/// 行を押すと、その月のそのカテゴリの記録の一覧へ進む。
///
/// 状態と操作は `MonthlyReportModel` が持ち、数字の計算はコア（`MonthlyReport`）が受け持つ。ここは表示と、文字の大きさに
/// 合わせた出し方だけ。割合の帯は名前を横に並べないので、アクセシビリティサイズの文字でも出す（行は丸を省いて名前と金額に
/// 幅を使わせる）。
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
        // 上へ流れた金額が、題と戻るボタンの後ろで透けて重ならないよう、上ははっきりした効果にする（文の多いシートと同じ）。
        .scrollEdgeEffectStyle(.hard, for: .top)
        .background(Theme.background)
        .navigationTitle("月のまとめ")
        .navigationBarTitleDisplayMode(.inline)
        // ホームはナビゲーションバーを隠しているので、ここでは戻るボタンのために出す。
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TabPicker(tab: $model.tab)
            }
            MonthSwitcher(model: model)
        }
        .modifier(ReportEntryModals(model: model, isActive: model.selectedCategory == nil))
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
        // 日付が変わったとき（0 時・時間帯の変更など）。今月かどうかと予算の残りの日数が変わる。
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
                // 使った額は、内訳とカレンダーのどちらの見方でも同じ場所に出す（切り替えても数字が動かないように）。
                SummaryCard(report: report)
                switch model.tab {
                case .breakdown:
                    if let budget = report.budget {
                        BudgetCard(report: report, budget: budget)
                    }
                    BreakdownCard(breakdown: report.breakdown, select: { model.showEntries(in: $0) })
                    if let payments = model.paymentBreakdown {
                        PaymentBreakdownCard(breakdown: payments)
                    }
                case .calendar:
                    MonthCalendarContent(
                        model: model.days,
                        edit: { model.presentEdit($0) },
                        requestDelete: { model.requestDelete($0) },
                        makeRecurring: model.makeRecurring
                    )
                }
            }
        }
    }
}

// MARK: - 見方と月送り

/// 上のバーの「内訳」と「カレンダー」の切り替え（同じ月の 2 つの見方。HIG の切り替えの使いどころ）。
private struct TabPicker: View {
    @Binding var tab: MonthlyReportModel.Tab

    var body: some View {
        Picker(selection: $tab) {
            Text("内訳").tag(MonthlyReportModel.Tab.breakdown)
            Text("カレンダー").tag(MonthlyReportModel.Tab.calendar)
        } label: {
            Text("見方")
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier(AccessibilityID.Report.tabPicker)
    }
}

/// 下に浮くバーの月送り。前の月・月の題・次の月を 1 つのガラスにまとめて真ん中に置き、今月でなければ右に「今月」を置く。
/// 今月より先と、記録のある最初の月より前には進めない（ボタンを押せなくする）。
///
/// 片手で届く下に置く（前は中身の上に置いていて、戻るボタンの真下に「前の月」の ‹ が縦に並び、押し間違えやすかった）。
private struct MonthSwitcher: ToolbarContent {
    let model: MonthlyReportModel

    var body: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            HStack(spacing: 4) {
                Button(action: model.showPreviousMonth) {
                    chevron("chevron.left")
                }
                .disabled(!model.canShowPreviousMonth)
                .accessibilityLabel("前の月")
                .accessibilityIdentifier(AccessibilityID.Report.previousMonth)
                Text(verbatim: model.monthTitle)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.Report.monthTitle)
                Button(action: model.showNextMonth) {
                    chevron("chevron.right")
                }
                .disabled(!model.canShowNextMonth)
                .accessibilityLabel("次の月")
                .accessibilityIdentifier(AccessibilityID.Report.nextMonth)
            }
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        if !model.isCurrentMonth {
            ToolbarItem(placement: .bottomBar) {
                Button("今月", action: model.showThisMonth)
                    .accessibilityIdentifier(AccessibilityID.Report.thisMonth)
            }
        }
    }

    /// 矢印。押せる範囲を 44pt 四方にする（記号だけだと、押せる範囲が記号の大きさしか無かった）。
    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

// MARK: - 数字

/// 月に使った額を大きく、その下に前の月との差（終わった月だけ）と、収入があれば収入と収支を小さく 1 行で出す（支出だけを
/// つける人に、毎月「収入 ¥0・収支 -¥…」と赤字のように見せないため。カレンダーと同じ出し方）。
private struct SummaryCard: View {
    let report: MonthlyReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("使った額")
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
            if report.income > 0 {
                Text("収入 \(YenFormatter.string(from: report.income))・収支 \(YenFormatter.signedString(from: report.balance))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.inkSecondary)
            }
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

/// 予算の進み。使った割合のバー（主の塗り）、残りか超えた額、予算の額、今月なら 1 日あたりに使える額。使った額は上の
/// カードと同じ値なので出さない。
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
            BudgetProgressBar(fraction: budget.spentFraction, isOver: budget.isOver)
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
            if !budget.isOver {
                // 終わった月は「残り」ではなく「余った額」と言う（もう使えないため）。
                ReportRow(
                    label: report.timing == .past ? Text("余った額") : Text("残り"),
                    value: YenFormatter.string(from: budget.remaining)
                )
            }
            ReportRow(label: Text("予算"), value: YenFormatter.string(from: budget.budget))
            if report.timing == .current, !budget.isOver {
                ReportRow(label: Text("1日あたりに使える額"), value: YenFormatter.string(from: budget.dailyAllowance))
            }
        }
        .reportCard()
    }
}

/// 多い・少ないの矢印と文。アクセシビリティサイズの文字では矢印を省き、文に幅を使わせる（多い・少ないは文で分かる。
/// 矢印を残すと、文が数文字ずつに折り返されて読みにくくなる）。矢印は VoiceOver では読ませない（文と同じ内容のため）。
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
/// VoiceOver では 1 行を 1 つの要素として読ませる。
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

// MARK: - 支払い方法の内訳

/// 支払い方法の内訳（カードごとと、現金・その他）。使った日の月で数えた額で、カードの引き落としの額（締めごと）とは違う
/// （引き落としの額は設定の「カード」に出す）。
struct PaymentBreakdownCard: View {
    let breakdown: PaymentBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支払い方法")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(breakdown.rows) { row in
                    if row.id != breakdown.rows.first?.id {
                        Divider()
                    }
                    HStack(spacing: 10) {
                        Image(systemName: row.card == nil ? "banknote" : "creditcard")
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityHidden(true)
                        Group {
                            if let card = row.card {
                                Text(verbatim: card.name)
                            } else {
                                Text("現金・その他")
                            }
                        }
                        Spacer(minLength: 8)
                        Text(YenFormatter.string(from: row.amount))
                            .monospacedDigit()
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
            }
            Text("使った日の月で数えた額です。カードの引き落としの額は、設定の「カード」で見られます。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
        .reportCard()
    }
}

// MARK: - カテゴリ別の内訳

/// カテゴリ別の支出。割合を 1 本の横棒で塗り分けた帯（`BreakdownCompositionBar`）と、押すとその月の記録の一覧へ進む行。
struct BreakdownCard: View {
    let breakdown: CategoryBreakdown
    let select: (EntryCategory) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ別の支出")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if breakdown.isEmpty {
                Text("この月の支出の記録はありません")
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                BreakdownCompositionBar(items: breakdown.items)
                VStack(spacing: 0) {
                    ForEach(breakdown.items, id: \.category) { item in
                        if item.category != breakdown.items.first?.category {
                            Divider()
                        }
                        BreakdownRow(item: item, action: { select(item.category) })
                    }
                }
            }
        }
        .reportCard()
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

/// 内訳の 1 行。カテゴリの色と記号の丸・名前・金額・割合。押すとその月のそのカテゴリの記録の一覧へ進む。
private struct BreakdownRow: View {
    let item: CategoryBreakdown.Item
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.categoryCatalog) private var catalog

    var body: some View {
        Button(action: action) {
            content
        }
        // 文字の色は行の中で決めているので、tint に染めない形にする（押している間は薄くなる）。
        .buttonStyle(.plain)
        .accessibilityLabel(catalog.label(for: item.category))
        .accessibilityValue(Text(verbatim: item.spokenValue))
        .accessibilityHint(Text("この月の記録の一覧を開きます"))
    }

    private var content: some View {
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

    private var name: some View {
        catalog.label(for: item.category)
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

    @Environment(\.categoryCatalog) private var catalog
    @ScaledMetric(relativeTo: .body) private var size = 28

    var body: some View {
        Image(systemName: catalog.symbolName(for: category))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Theme.onCategory)
            .frame(width: size, height: size)
            // 形はホームの返事の行の印と同じ角の丸い四角にそろえる（前は丸で、画面によって形が違った）。
            .background(catalog.color(for: category), in: .rect(cornerRadius: size * 0.28))
            // 印はダークでもライトの色で塗る（EntryBubble と同じ理由。ダークの色に白い記号は読めない）。
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

/// 保存先を読めなかったときの案内と、もう一度読むボタン。
struct LoadFailedView: View {
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("記録を読み込めませんでした")
                .font(.title3.bold())
            // 文字だけのボタンは本文と同じ墨になり、見出しの補足に見えるので、記号を添える（docs/design.md §7）。
            Button(action: retry) {
                Label("もう一度試す", systemImage: "arrow.clockwise")
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
    /// まとめの 1 まとまり（面の色の角丸の板）。
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
