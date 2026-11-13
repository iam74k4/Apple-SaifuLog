import SaifuLogCore
import SwiftData
import SwiftUI

/// ホームの上に置く今月の帯。「今月いくら使ったか」を大きく出し、予算を決めていれば「あと ¥…」と細いバーだけを添える。
///
/// 1 日あたり・のこりの日数・今日までの目安・収入は出さない（帯は会話の上に常に出ているので、数字を増やすほど会話の場所が減り、
/// いちばん知りたい「使った額」が埋もれるため。細かい数字は月のまとめにあり、会話で聞いても答える）。予算を超えたら「¥… オーバー」を
/// 注意の色とアイコンと文字で出す（色だけに頼らない）。
///
/// 見出しと数字を押すと「月のまとめ」（⑦）へ進む（`openReport` を渡したとき）。見出しに「›」を添えて、押せば詳しく見られることを
/// 示す。右上の歯車は「設定」（⑧）の入口（`openSettings` を渡したとき）。予算は設定と会話（「今月の予算を5万にして」）で決める。
struct SummaryHeader: View {
    let summary: MonthlySummary
    /// 今月の予算の進み。予算を決めていなければ nil。
    let budget: BudgetStatus?
    /// 月のまとめへ進む。nil なら見出しと数字は押せない（プレビューなど）。
    var openReport: (() -> Void)?
    /// 設定へ進む。nil なら歯車のボタンを出さない（プレビューなど）。
    var openSettings: (() -> Void)?
    /// カレンダーのページを出す（VoiceOver の操作「カレンダー」）。左へのスワイプで出るページなので、帯にボタンは置かない
    /// （ボタンとページで同じ入口が重なるため）。VoiceOver ではページを送るスワイプが見つけにくいので、数字の要素の操作に置く。
    /// nil なら操作を出さない（プレビューなど）。
    var openCalendar: (() -> Void)?
    /// 低い帯にするか（入力欄にキーボードを出している間）。見出しの行に使った額だけを並べ、大きな数字とバーを出さない。
    /// キーボードが画面の下の半分ほどを占める間も帯が同じ高さのままだと、送った記録の返事の「取り消す」やカテゴリの聞き返しが
    /// 帯の下に隠れたため（iPhone 17 Pro のシミュレータ）。
    var isCompact = false

    #if DEBUG || INTERNAL_DIAGNOSTICS
    /// 診断画面を出す（社内テスト用のビルドと DEBUG だけ。ホームが環境で渡す）。
    @Environment(\.openDiagnostics) private var openDiagnostics
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isCompact {
                compactRow
            } else {
                titleRow
                figuresElement(figures)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        // 上はボタンの高さ（44pt）の中に余白があるので詰める。
        .padding(.top, 4)
        .padding(.bottom, isCompact ? 4 : 12)
        // 地は塗らない（ホームが帯を safeAreaBar に置き、スクロール端の効果が地になる。`HomeView`）。
        .accessibilityElement(children: .contain)
        .animation(.default, value: summary)
        .animation(.default, value: budget)
        .animation(.default, value: isCompact)
    }

    /// 見出し。
    private var title: Text {
        Text("今月使った額")
    }

    /// 数字の要素。VoiceOver では数字をまとめて 1 つの要素として読ませる（見出し・使った額・予算の残り）。ボタンより先に読ませる。
    /// まとめへ進めるときは、その要素を押すとまとめを開く。
    @ViewBuilder
    private func figuresElement(_ figures: some View) -> some View {
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

    /// 見出しと、右のボタン（設定。社内テスト用のビルドでは診断も）の行。
    private var titleRow: some View {
        HStack(spacing: 0) {
            titleButton
            Spacer(minLength: 8)
            trailingButtons
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// 低い帯の行（`isCompact`）。数字の行と右のボタンを 1 行に並べ、収まらなければ（アクセシビリティサイズの文字・英語の大きな
    /// 文字）ボタンを出さない。積む形にすると帯がまた高くなるため（設定は、キーボードを閉じれば出る）。
    private var compactRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                figuresElement(compactFigures)
                Spacer(minLength: 8)
                trailingButtons
                    .fixedSize(horizontal: true, vertical: false)
            }
            figuresElement(compactFigures)
        }
    }

    /// 低い帯の数字の行。見出し・使った額・「›」を 1 行に並べる。
    private var compactFigures: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            title
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            if budget?.isOver == true {
                // 予算を超えたことを色だけで伝えない（広い帯の「¥… オーバー」と同じアイコンを添える。読み上げは数字の要素が
                // 「… オーバー」と読む）。低い帯は 1 行なので、語は添えずにアイコンだけにする。
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.danger)
                    .accessibilityHidden(true)
            }
            Text(verbatim: YenFormatter.string(from: summary.expense))
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(budget?.isOver == true ? Theme.danger : Theme.ink)
                .contentTransition(.numericText())
            if openReport != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        // 押せる範囲を 44pt の高さ以上にする（見出しの行のボタンと同じ）。
        .frame(minHeight: 44)
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

    /// 見出しの行の右のボタン。設定の歯車で、社内テスト用のビルドでは診断のボタンが前に付く。ガラスのボタンにする（ほかの画面の
    /// ナビゲーションバーのボタンと同じ見た目。ホームはナビゲーションバーを隠しているので、帯の中に同じ形で置く）。
    private var trailingButtons: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                diagnosticsButton
                settingsButton
            }
        }
    }

    /// 設定を開く歯車のボタン。記号だけのガラスの丸にする。
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

    /// 診断画面を開く小さなボタン（社内テスト用のビルドと DEBUG だけ）。歯車より目立たせない。
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

    /// 使った額（大きく）と、予算があれば細いバーと残り。
    private var figures: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: YenFormatter.string(from: summary.expense))
                .font(.largeTitle.bold())
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                // 金額は「¥」と数字の間や桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            if let budget {
                BudgetProgressBar(fraction: budget.spentFraction, isOver: budget.isOver)
                    .padding(.vertical, 4)
                budgetText(budget)
                    .font(.footnote)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
        }
    }

    /// 予算の残り（「あと ¥…」）。超えたら、注意の色だけでなく、アイコンと「オーバー」の語でも伝える。
    @ViewBuilder
    private func budgetText(_ budget: BudgetStatus) -> some View {
        if budget.isOver {
            Label {
                Text("\(YenFormatter.string(from: budget.overspent)) オーバー")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(Theme.danger)
        } else {
            Text("あと \(YenFormatter.string(from: budget.remaining))")
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// VoiceOver で読ませる数字（見出しの後に続く）。使った額と、予算があれば残り（超えたら超えた額）と予算。
    private var spokenFigures: String {
        var items = [YenFormatter.string(from: summary.expense)]
        if let budget {
            items.append(budget.isOver
                ? String(localized: "\(YenFormatter.string(from: budget.overspent)) オーバー")
                : String(localized: "あと \(YenFormatter.string(from: budget.remaining))"))
            items.append(String(localized: "予算 \(YenFormatter.string(from: budget.budget))"))
        }
        return items.formatted(.list(type: .and))
    }
}

/// 予算の使った割合のバー（主の塗り。超えたら注意の色）。数字は文字で伝えるので、VoiceOver では読ませない。
struct BudgetProgressBar: View {
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

/// 今日を含む月の記録と予算を読み、SummaryHeader に合計と予算の進みを出す。
///
/// 読み込みの条件は月ごとに変わるので、今日を受け取るビューに @Query を置く
/// （呼び出し側が今日を変えると、ここが作り直されて条件も変わる）。予算の行は少ないので全部読む。
struct MonthSummaryHeader: View {
    private let today: Date
    private let calendar: Calendar
    private let openReport: () -> Void
    private let openSettings: () -> Void
    private let openCalendar: (() -> Void)?
    /// 低い帯にするか（入力欄にキーボードを出している間。`SummaryHeader.isCompact`）。
    private let isCompact: Bool
    @Query private var records: [Entry]
    @Query private var budgets: [Budget]

    init(
        today: Date,
        calendar: Calendar,
        openReport: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openCalendar: (() -> Void)? = nil,
        isCompact: Bool = false
    ) {
        self.today = today
        self.calendar = calendar
        self.openReport = openReport
        self.openSettings = openSettings
        self.openCalendar = openCalendar
        self.isCompact = isCompact
        _records = Query(Entry.monthDescriptor(containing: today, calendar: calendar))
    }

    var body: some View {
        let figures = Self.figures(records: records, budgets: budgets, today: today, calendar: calendar)
        SummaryHeader(
            summary: figures.summary,
            budget: figures.budget,
            openReport: openReport,
            openSettings: openSettings,
            openCalendar: openCalendar,
            isCompact: isCompact
        )
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
        let total = BudgetPlan.resolve(budgets).total
        let budget = BudgetStatus(budget: total, summary: ledger, now: today, calendar: calendar)
        return (MonthlySummary(ledger), budget)
    }
}

#Preview("予算なし") {
    SummaryHeader(summary: MonthlySummary(expense: 42_380, income: 250_000), budget: nil)
}

#Preview("予算あり") {
    SummaryHeader(
        summary: MonthlySummary(expense: 57_000),
        budget: BudgetStatus(
            budget: 150_000, spent: 57_000, now: .now,
            month: Calendar.current.dateInterval(of: .month, for: .now)!, calendar: .current
        )
    )
}

#Preview("予算オーバー") {
    SummaryHeader(
        summary: MonthlySummary(expense: 162_000, income: 500),
        budget: BudgetStatus(
            budget: 150_000, spent: 162_000, now: .now,
            month: Calendar.current.dateInterval(of: .month, for: .now)!, calendar: .current
        )
    )
}
