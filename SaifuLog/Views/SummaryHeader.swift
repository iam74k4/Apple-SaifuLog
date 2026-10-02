import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの上に置く今月の帯。
///
/// 予算を決めていれば「今月あと ¥…」を大きく、「1日あたり ¥… ・のこり N 日」を小さく出し、使った割合を
/// 主の塗りのバーで示す。予算を超えたら「¥… オーバー」を注意の色とアイコンと文字で出す（色だけに頼らない）。
/// 予算を決めていなければ、今月の支出の合計と「予算を決める」のボタンを出す。
///
/// 見出しと数字を押すと「月のまとめ」（⑦）へ進む（`openReport` を渡したとき）。見出しに「›」を添えて、押せば
/// 詳しく見られることを示す。帯のほかにまとめの入口のボタンを置かないのは、ホームのナビゲーションバーを出さずに
/// タイムラインを広く使っているのと、今月の合計を見て「何に使ったか」を知りたくなる場所がここだから。
/// 右上の歯車は「設定」（⑧）の入口（`openSettings` を渡したとき）。ナビゲーションバーを出していないので、ここに置く。
struct SummaryHeader: View {
    let summary: MonthlySummary
    /// 今月の予算の進み。予算を決めていなければ nil。
    let budget: BudgetStatus?
    /// 予算を決める（変える）画面を出す。nil なら予算のボタンを出さない（家族の家計。予算は v1 では「自分」だけ）。
    let editBudget: (() -> Void)?
    /// 月のまとめへ進む。nil なら見出しと数字は押せない（プレビューなど）。
    var openReport: (() -> Void)?
    /// 設定へ進む。nil なら歯車のボタンを出さない（プレビューなど）。
    var openSettings: (() -> Void)?
    /// カレンダーのページを出す（VoiceOver の操作「カレンダー」）。左へのスワイプで出るページなので、帯にボタンは置かない
    /// （ボタンとページで同じ入口が重なるため）。VoiceOver ではページを送るスワイプが見つけにくいので、数字の要素の操作に置く。
    /// nil なら操作を出さない（家族の家計・プレビュー）。
    var openCalendar: (() -> Void)?
    /// 「自分／家族」の切り替え。家計に入っているときだけ渡す（nil なら出さない）。
    var ledgerScope: Binding<HomeModel.LedgerScope>?
    /// 家族の家計の今月の合計か（見出しを「家族の今月の支出」にする）。
    var isHousehold = false
    /// 今日までの日割りの目安（月のまとめと同じ `MonthlyReport.budgetPace`・`spentBeyondPace`）。予算を決めていないときは nil。
    var pace: Pace?

    /// 今日までの日割りの目安と、今日までに使った額がそれより多い額（少なければ負）。
    struct Pace: Equatable {
        let amount: Int
        let beyond: Int
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if DEBUG || INTERNAL_DIAGNOSTICS
    /// 診断画面を出す（社内テスト用のビルドと DEBUG だけ。ホームが環境で渡す）。
    @Environment(\.openDiagnostics) private var openDiagnostics
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ledgerScope {
                LedgerScopePicker(selection: ledgerScope)
                    .padding(.top, 8)
            }
            titleRow
            figuresElement
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        // 上はボタンの高さ（44pt）の中に余白があるので詰める。
        .padding(.top, 4)
        .padding(.bottom, 12)
        // 地は塗らない（ホームが帯を safeAreaBar に置き、スクロール端の効果が地になる。`HomeView`）。
        .accessibilityElement(children: .contain)
        .animation(.default, value: summary)
        .animation(.default, value: budget)
        .animation(.default, value: pace)
    }

    /// 見出し（予算の有無と超えたかで変わる）。
    private var title: Text {
        if isHousehold { return Text("家族の今月の支出") }
        return switch budget {
        case nil: Text("今月の支出")
        case let budget? where budget.isOver: Text("今月の予算")
        case _?: Text("今月あと")
        }
    }

    /// 数字の要素。VoiceOver では数字をまとめて 1 つの要素として読ませる（見出し・残り・1 日あたり・残りの日数・
    /// 予算と使った額・収入の順）。ボタンより先に読ませる。まとめへ進めるときは、その要素を押すとまとめを開く。
    @ViewBuilder
    private var figuresElement: some View {
        if let openReport {
            Button(action: openReport) {
                figures
                    // 数字の右の空いたところを押しても開くようにする。
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            // 文字の色は数字の側で決めているので、tint に染めない形にする（押している間は薄くなる）。
            .buttonStyle(.plain)
            // ボタンは中の文字を 1 つの要素にまとめるので、読む内容だけを差し替える（ボタンであることは残す）。
            .accessibilityLabel(title)
            .accessibilityValue(Text(verbatim: spokenFigures))
            .accessibilityHint("月のまとめを開きます")
            .accessibilityActions { calendarAction }
            .accessibilitySortPriority(1)
        } else {
            figures
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(Text(verbatim: spokenFigures))
                .accessibilityActions { calendarAction }
                .accessibilitySortPriority(1)
        }
    }

    /// VoiceOver の操作「カレンダー」（`openCalendar` を渡したとき）。
    @ViewBuilder
    private var calendarAction: some View {
        if let openCalendar {
            Button("カレンダー", action: openCalendar)
        }
    }

    /// 見出しと、右のボタン（予算・設定）の行。1 行に収まらなければ、文字の大きさによらずボタンを見出しの下の行に移す。
    ///
    /// アクセシビリティサイズに限らないのは、歯車を足してボタンが 2 つ（診断のボタンが入るビルドでは 3 つ）になり、英語の
    /// 大きな文字（xxxLarge）では、アクセシビリティサイズでなくても「予算を変更」が「Change…」と切れたため。
    @ViewBuilder
    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                titleButton
                Spacer(minLength: 8)
                // ボタンは縮めない。HStack は幅を子に等分に近い形で配るので、並べた幅が収まる場合でも、ボタンの側が
                // 等分より広いと予算のボタンの文字が省かれるため（収まらない場合は下の積む形になる）。
                trailingButtons
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 0) {
                titleButton
                trailingButtons
            }
        }
    }

    /// 見出し。まとめへ進めるときは、見出しを押しても開く（「›」は押せることの印）。
    ///
    /// VoiceOver では読ませない（見出しは数字の要素の名前として読み、押す操作も数字の要素にある。ここでも読むと 2 回になる）。
    @ViewBuilder
    private var titleButton: some View {
        if let openReport {
            Button(action: openReport) {
                titleText
                    // 押せる範囲を 44pt の高さ以上にする。
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        } else {
            titleText
        }
    }

    /// 見出しの行の右のボタン。予算のボタンと設定の歯車で、社内テスト用のビルドでは診断のボタンが前に付く。
    ///
    /// 予算のボタンは設定の中へ移さずに残す。予算は月の途中でも見直すもので、ホームから 1 回押すだけで開けるほうが
    /// よいため（設定の中からも開ける）。歯車は右の端に置く（設定の入口の置き場所として見慣れた位置のため）。
    /// どれもガラスのボタンにする（ほかの画面のナビゲーションバーのボタンと同じ見た目。ホームはナビゲーションバーを隠しているので、
    /// 帯の中に同じ形で置く）。ガラスの余白を足して、押せる範囲を 44pt にする。
    private var trailingButtons: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                diagnosticsButton
                budgetButton
                settingsButton
            }
        }
    }

    /// 設定を開く歯車のボタン。設定は必要なときだけ開く画面なので、記号だけのガラスの丸にして、文字のある予算のボタンより目立たせない。
    @ViewBuilder
    private var settingsButton: some View {
        if let openSettings {
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("設定")
        }
    }

    /// 診断画面を開く小さなボタン（社内テスト用のビルドと DEBUG だけ）。予算のボタンより目立たせない。
    @ViewBuilder
    private var diagnosticsButton: some View {
        #if DEBUG || INTERNAL_DIAGNOSTICS
        if let openDiagnostics {
            Button {
                openDiagnostics()
            } label: {
                Image(systemName: "stethoscope")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("診断")
        }
        #endif
    }

    private var titleText: some View {
        HStack(spacing: 4) {
            title
            if openReport != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.inkSecondary)
        // 見出しは下の数字の要素の名前として読ませる（ここで読むと 2 回になる）。
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var budgetButton: some View {
        if let editBudget {
            budgetButton(editBudget)
        }
    }

    private func budgetButton(_ editBudget: @escaping () -> Void) -> some View {
        Button(action: editBudget) {
            Text(budget == nil ? "予算を決める" : "予算を変更")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                // 見出しの下の行に移しても収まらないとき（英語のアクセシビリティサイズで、歯車と並べたとき）だけ
                // 2 行に折り返す。1 行に収まるときは、横に並べる形でも積む形でも 1 行のまま。
                .lineLimit(2)
                .frame(minHeight: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
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
        // バーに今日までの目安の印を立てる（月のまとめの予算の欄と同じ）。印より右まで塗られていれば、目安より多く使っている。
        BudgetProgressBar(
            fraction: budget.spentFraction,
            isOver: budget.isOver,
            paceFraction: pace.map { min(max(Double($0.amount) / Double(budget.budget), 0), 1) }
        )
        .padding(.vertical, 4)
        // 超えていないときは、目安と比べた一言も添える（超えたら上の「オーバー」で足りる）。
        if let pace, !budget.isOver {
            paceText(pace.beyond)
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(2)
                .contentTransition(.numericText())
        }
    }

    /// 今日までの目安と比べた一言（月のまとめの予算の欄と同じ文）。多い・少ないは矢印だけでなく語でも伝える。
    @ViewBuilder
    private func paceText(_ beyond: Int) -> some View {
        let amount = YenFormatter.string(from: abs(beyond))
        switch beyond {
        case 1...:
            Label { Text("今日までの目安より \(amount) 多い") } icon: { Image(systemName: "arrow.up.right").accessibilityHidden(true) }
        case ..<0:
            Label { Text("今日までの目安より \(amount) 少ない") } icon: { Image(systemName: "arrow.down.right").accessibilityHidden(true) }
        default:
            Label { Text("今日までの目安どおり") } icon: { Image(systemName: "equal").accessibilityHidden(true) }
        }
    }

    /// 読み上げる目安の一言。
    private func spokenPace(_ beyond: Int) -> String {
        let amount = YenFormatter.string(from: abs(beyond))
        return switch beyond {
        case 1...: String(localized: "今日までの目安より \(amount) 多い")
        case ..<0: String(localized: "今日までの目安より \(amount) 少ない")
        default: String(localized: "今日までの目安どおり")
        }
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
            if let pace, !budget.isOver { items.append(spokenPace(pace.beyond)) }
        } else {
            items.append(YenFormatter.string(from: summary.expense))
        }
        if summary.income > 0 {
            items.append(String(localized: "今月の収入 \(YenFormatter.string(from: summary.income))"))
        }
        return items.formatted(.list(type: .and))
    }
}

/// 帯の「自分／家族」の切り替え（家族と家計を共有しているときだけ）。
///
/// 選んだほうに記録し、タイムラインと帯の合計もそちらを出す。2 つしかなく、いまどちらかが常に見えている必要があるので、
/// 分段のピッカーにする。
private struct LedgerScopePicker: View {
    @Binding var selection: HomeModel.LedgerScope

    var body: some View {
        Picker(selection: $selection) {
            Text("自分").tag(HomeModel.LedgerScope.personal)
            Text("家族").tag(HomeModel.LedgerScope.household)
        } label: {
            Text("記録先")
        }
        .pickerStyle(.segmented)
        .accessibilityHint("記録する先と、表示する記録を切り替えます")
    }
}

/// 予算のうち使った割合のバー。主の塗り（墨か白）で塗り、予算を超えたら注意の色で満たす（ホームの帯と月のまとめ）。
///
/// 数字（残り・超えた額）は文字で出しているので、バーは目安として添えるだけにし、VoiceOver では読ませない
/// （割合は帯の要素の「予算」「使った額」や、まとめの行の文字で伝わる）。
///
/// `paceFraction` を渡すと、その位置に日割りの目安の印（墨の縦線）を立てる（月のまとめの今月）。印はバーの上下に
/// はみ出させ、onAccent の色で縁取る。印と塗りは同じ墨（ダークでは白）なので、縁が無いと塗りの上では印が消えるため。
struct BudgetProgressBar: View {
    let fraction: Double
    let isOver: Bool
    var paceFraction: Double?

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
            .overlay {
                if let paceFraction {
                    GeometryReader { proxy in
                        let width: CGFloat = 2
                        let outline: CGFloat = 1
                        Capsule()
                            .fill(Theme.ink)
                            .frame(width: width, height: height * 2.5)
                            // 塗りの上でも見えるよう、塗りの上の色（onAccent）で縁取る（印と塗りが同じ墨か白のため）。
                            .padding(outline)
                            .background(Theme.onAccent, in: .capsule)
                            // 端でもバーの外に出ないよう、縁を含めた線の幅の分だけ内側に収める。
                            .position(
                                x: min(
                                    max(proxy.size.width * paceFraction, width / 2 + outline),
                                    proxy.size.width - width / 2 - outline
                                ),
                                y: proxy.size.height / 2
                            )
                    }
                }
            }
            // 上下にはみ出した印がほかの文字に重ならないよう、はみ出す分の余白を取る。
            .padding(.vertical, paceFraction == nil ? 0 : height * 0.75)
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
    private let openReport: () -> Void
    private let openSettings: () -> Void
    private let openCalendar: (() -> Void)?
    private let ledgerScope: Binding<HomeModel.LedgerScope>?
    @Query private var records: [Entry]
    @Query private var budgets: [Budget]

    init(
        today: Date,
        calendar: Calendar,
        editBudget: @escaping () -> Void,
        openReport: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openCalendar: (() -> Void)? = nil,
        ledgerScope: Binding<HomeModel.LedgerScope>? = nil
    ) {
        self.today = today
        self.calendar = calendar
        self.editBudget = editBudget
        self.openReport = openReport
        self.openSettings = openSettings
        self.openCalendar = openCalendar
        self.ledgerScope = ledgerScope
        _records = Query(Entry.monthDescriptor(containing: today, calendar: calendar))
    }

    var body: some View {
        let figures = Self.figures(records: records, budgets: budgets, today: today, calendar: calendar)
        SummaryHeader(
            summary: figures.summary,
            budget: figures.budget,
            editBudget: editBudget,
            openReport: openReport,
            openSettings: openSettings,
            openCalendar: openCalendar,
            ledgerScope: ledgerScope,
            pace: figures.pace
        )
    }

    /// 帯に出す今月の合計と予算の進み。
    ///
    /// 月の集計（`LedgerSummary`）は 1 回だけ行い、合計と予算の進みの両方に使う（同じ記録から別々に数えて、
    /// 合計と予算の「使った額」が食い違わないように）。
    ///
    /// 今日までの目安は、月のまとめと同じ計算（`MonthlyReport`）で出す（帯とまとめの目安を食い違わせないため）。
    static func figures(
        records: [Entry], budgets: [Budget], today: Date, calendar: Calendar
    ) -> (summary: MonthlySummary, budget: BudgetStatus?, pace: SummaryHeader.Pace?) {
        guard let month = ReportPeriod.thisMonth.interval(now: today, calendar: calendar) else {
            return (MonthlySummary(), nil, nil)
        }
        let ledger = LedgerSummary(records: records, interval: month, calendar: calendar)
        let total = BudgetPlan.resolve(budgets).total
        let budget = BudgetStatus(budget: total, summary: ledger, now: today, calendar: calendar)
        var pace: SummaryHeader.Pace?
        if budget != nil,
           let report = MonthlyReport(records: records, month: today, now: today, budget: total, calendar: calendar),
           let amount = report.budgetPace, let beyond = report.spentBeyondPace {
            pace = SummaryHeader.Pace(amount: amount, beyond: beyond)
        }
        return (MonthlySummary(ledger), budget, pace)
    }
}

/// 家族の家計の今月の合計を読み、帯に出す（「家族」のとき）。予算は v1 では家計に持たせないので、合計だけを出す。
///
/// 家計の保存先（household.store）を読むので、呼び出し側が家計の保存先を環境に渡す（`.modelContainer`）。
struct HouseholdSummaryHeader: View {
    private let today: Date
    private let calendar: Calendar
    private let openSettings: () -> Void
    private let ledgerScope: Binding<HomeModel.LedgerScope>
    @Query private var records: [HouseholdEntry]

    init(
        zoneName: String, today: Date, calendar: Calendar, ledgerScope: Binding<HomeModel.LedgerScope>,
        openSettings: @escaping () -> Void
    ) {
        self.today = today
        self.calendar = calendar
        self.ledgerScope = ledgerScope
        self.openSettings = openSettings
        _records = Query(HouseholdEntry.monthDescriptor(zoneName: zoneName, containing: today, calendar: calendar))
    }

    var body: some View {
        SummaryHeader(
            summary: Self.summary(records: records, today: today, calendar: calendar),
            budget: nil,
            editBudget: nil,
            openReport: nil,
            openSettings: openSettings,
            ledgerScope: ledgerScope,
            isHousehold: true
        )
    }

    /// 家族の今月の合計（家族のだれが記録したかによらず、家計のすべての記録）。区切りと数え方は自分の記録と同じ
    /// （`ReportPeriod.thisMonth` と `LedgerSummary`）。
    static func summary(records: [HouseholdEntry], today: Date, calendar: Calendar) -> MonthlySummary {
        guard let month = ReportPeriod.thisMonth.interval(now: today, calendar: calendar) else { return MonthlySummary() }
        return MonthlySummary(LedgerSummary(records: records, interval: month, calendar: calendar))
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
