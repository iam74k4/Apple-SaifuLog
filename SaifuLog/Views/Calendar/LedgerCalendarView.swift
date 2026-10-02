import SaifuLogCore
import SwiftUI

/// カレンダーのページ（ホームを左へスワイプした 2 枚目。docs/design.md §9 の ⑩）。
///
/// 上から、今月の見通し（今日あと・固定費を引いた今月あと・月末の見込み。ほかの月はその月の支出と収入）、月のカレンダー（日ごとの
/// 支出と、予算の日割りより多い日・くり返しの予定の印）、選んだ日の記録。会話は記録した順に流れるので、日ごとに見返す・抜けた日を
/// 見つける・決まった支出の予定を見るのはこのページで行う。
///
/// 入力欄は置かない。「この日に記録」で会話のページへ戻り、入力欄にその日の日付を入れる（記録の入口を会話の入力欄の 1 つに
/// 保つ。入口を分けると、どこに書けばよいかを考えさせるため。`HomeView` の説明と同じ）。
///
/// 文字がとても大きいとき（アクセシビリティサイズ）は 7 列の表をやめ、記録か予定のある日と今日の一覧にして、選んだ日の記録をその日の
/// 行の下に出す（7 列では 1 日の幅が 50pt ほどしかなく、金額が読めないため）。
struct LedgerCalendarView: View {
    let model: LedgerCalendarModel
    /// 会話のページへ戻る。
    let showConversation: () -> Void
    /// 「この日に記録」。会話のページへ戻り、入力欄にその日の日付を入れる。
    let recordOnDay: (Date) -> Void
    let edit: (Entry) -> Void
    /// 削除を求める（確認はホームが出す）。
    let requestDelete: (Entry) -> Void
    /// その記録の中身で、くり返しの記録を作る画面を開く（行の長押しの「毎月くり返す」）。
    let makeRecurring: (Entry) -> Void
    /// その月の月のまとめを開く。
    let openReport: (Date) -> Void
    /// 予算を決める（変える）画面を出す。
    let editBudget: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.loadFailed {
                    LoadFailedView(retry: { model.reload() })
                } else if let days = model.days {
                    summary(days)
                    if dynamicTypeSize.isAccessibilitySize {
                        // 一覧の行に日付とその日の支出があるので、行の下に出す記録には見出しを付けない。
                        CalendarDayList(model: model, days: days) { dayPanel($0, showsHeader: false) }
                    } else {
                        CalendarMonthGrid(model: model, days: days)
                        if let day = model.selectedSummary {
                            dayPanel(day, showsHeader: true)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 上へ流れた数字やカレンダーが、題とボタンの後ろで透けて重ならないよう、上ははっきりした効果にする（月のまとめと同じ）。
        .scrollEdgeEffectStyle(.hard, for: .top)
        // 下は画面の端まで流す（ページの入れ物は下の安全領域の手前で切るので、そのままだとホームインジケータの上で記録が途切れて
        // 見える）。いちばん下の中身は、スクロールすれば安全領域の上まで上がる。
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Theme.background)
        .safeAreaBar(edge: .top, spacing: 0) {
            CalendarPageHeader(
                title: model.shortMonthTitle,
                spokenTitle: model.monthTitle,
                isShowingToday: model.isShowingToday,
                showConversation: showConversation,
                showPreviousMonth: { model.showMonth(offset: -1) },
                showNextMonth: { model.showMonth(offset: 1) },
                showToday: { model.showThisMonth() }
            )
            // ホームの帯と同じく、上に常に出ている帯なので文字の大きさに上限を設ける（下のカレンダーの場所を残すため）。
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
    }

    /// いちばん上の数字。今月は見通し、ほかの月はその月の支出と収入。先の月には月のまとめの入口を出さない（月のまとめは
    /// 今月より先を出さず、押すと今月が開いて、見ていた月と食い違うため）。
    @ViewBuilder
    private func summary(_ days: LedgerCalendarMonth) -> some View {
        let openMonthReport = { openReport(days.month.start) }
        if let outlook = model.outlook {
            SpendingOutlookCard(outlook: outlook, editBudget: editBudget, openReport: openMonthReport)
        } else {
            CalendarMonthTotalsCard(days: days, openReport: model.isFutureMonth ? nil : openMonthReport)
        }
    }

    private func dayPanel(_ day: LedgerCalendarMonth.Day, showsHeader: Bool) -> some View {
        CalendarDayPanel(
            day: day,
            showsHeader: showsHeader,
            records: model.selectedRecords,
            planned: model.planned(on: day.start),
            calendar: model.calendar,
            edit: { if let entry = model.entry(for: $0) { edit(entry) } },
            requestDelete: { if let entry = model.entry(for: $0) { requestDelete(entry) } },
            makeRecurring: { if let entry = model.entry(for: $0) { makeRecurring(entry) } },
            recordOnDay: { recordOnDay(day.start) }
        )
    }
}

// MARK: - 上の帯

/// ページの上の帯。左に会話へ戻るボタン、真ん中に月の題と前後の月のボタン、右に「今日」。1 行に収まらなければ 2 行にする。
private struct CalendarPageHeader: View {
    /// 月の題（略した形）。
    let title: String
    /// 読み上げる月の題（略さない形）。
    let spokenTitle: String
    let isShowingToday: Bool
    let showConversation: () -> Void
    let showPreviousMonth: () -> Void
    let showNextMonth: () -> Void
    let showToday: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                conversationButton
                Spacer(minLength: 0)
                monthSwitcher
                Spacer(minLength: 0)
                todayButton
            }
            VStack(spacing: 4) {
                HStack {
                    conversationButton
                    Spacer(minLength: 8)
                    todayButton
                }
                monthSwitcher
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// 会話へ戻るボタン（右へスワイプするのと同じ）。ホームの帯のカレンダーのボタンと対になる、記号だけのガラスの丸。
    private var conversationButton: some View {
        Button(action: showConversation) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("会話")
        .accessibilityHint("記録と質問の会話に戻ります")
    }

    private var monthSwitcher: some View {
        HStack(spacing: 4) {
            Button(action: showPreviousMonth) {
                chevron("chevron.left")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("前の月")
            Text(verbatim: title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel(Text(verbatim: spokenTitle))
                .accessibilityAddTraits(.isHeader)
            Button(action: showNextMonth) {
                chevron("chevron.right")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("次の月")
        }
    }

    /// 今月の今日へ戻るボタン。今日を見ているときは押せない（押しても何も変わらないため）。
    private var todayButton: some View {
        Button(action: showToday) {
            Text("今日")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isShowingToday ? Theme.inkSecondary : Theme.accentText)
                .frame(minHeight: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .disabled(isShowingToday)
    }

    /// 前後の月の矢印（月のまとめの月送りと同じ形）。
    private func chevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(width: 30, height: 30)
    }
}

// MARK: - 見通し

/// 今月の見通し（`SpendingOutlook`）。予算を決めていれば「今日あと」を大きく出し、決めていなければ今月の支出と、予算を決める案内。
///
/// 今日あとは、まだ記録していない今月の固定費（くり返しの記録）を先に引いて日割りにした額から、今日の支出を引いたもの。ホームの帯の
/// 「1日あたり」は固定費を引かないので、固定費の多い月は、こちらのほうが小さく出る（使える額を多く見せないため）。
/// 超えたことは、注意の色だけでなく、アイコンと「オーバー」の語でも伝える（ホームの帯と同じ）。
private struct SpendingOutlookCard: View {
    let outlook: SpendingOutlook
    let editBudget: () -> Void
    let openReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let left = outlook.todayLeft, let allowance = outlook.todayAllowance {
                todayFigures(left: left, allowance: allowance)
            } else {
                spentFigures
            }
            Divider()
            rows
            if outlook.budget == nil {
                Text("予算を決めると、今日あといくら使えるかが出ます。")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
            footer
        }
        .reportCard()
    }

    /// 今日あと（大きく）と、今日の目安・今日の支出。
    private func todayFigures(left: Int, allowance: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日あと")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            if left >= 0 {
                Text(verbatim: YenFormatter.string(from: left))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            } else {
                Label {
                    Text("\(YenFormatter.string(from: -left)) オーバー")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.largeTitle.bold())
                .monospacedDigit()
                .foregroundStyle(Theme.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            }
            FigurePair(
                first: Text("今日の目安 \(YenFormatter.string(from: allowance))"),
                second: Text("使った額 \(YenFormatter.string(from: outlook.spentToday))")
            )
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
        }
        // 見出し・額・目安と使った額を 1 つの要素として読ませる。
        .accessibilityElement(children: .combine)
    }

    /// 予算を決めていないときの、今月の支出。
    private var spentFigures: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今月の支出")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            Text(verbatim: YenFormatter.string(from: outlook.spent))
                .font(.largeTitle.bold())
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var rows: some View {
        let fixed = outlook.plannedFixedTotal
        if fixed > 0 {
            ReportRow(label: Text("まだ記録していない固定費"), value: YenFormatter.string(from: fixed))
        }
        if let free = outlook.freeToSpend {
            ReportRow(
                label: fixed > 0 ? Text("固定費を引いた今月あと") : Text("今月あと"),
                value: free >= 0
                    ? YenFormatter.string(from: free) : String(localized: "\(YenFormatter.string(from: -free)) オーバー"),
                valueColor: free >= 0 ? Theme.ink : Theme.danger
            )
        }
        if let projection = outlook.projection {
            ReportRow(label: Text("このペースだと今月の支出"), value: YenFormatter.string(from: projection))
            if let over = outlook.projectedOverBudget, over > 0 {
                Label {
                    Text("予算を \(YenFormatter.string(from: over)) 超える見込み")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .labelStyle(TrendLabelStyle())
                .font(.footnote)
                .foregroundStyle(Theme.danger)
            }
        } else {
            // 月の初めは数日の支出で大きく振れるので、見込みは出さない（`SpendingOutlook.projectionMinimumDay`）。出ない理由を添える。
            Text("今月の支出の見込みは、月の \(SpendingOutlook.projectionMinimumDay) 日目から出します。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    /// 予算のボタンと月のまとめへの入口。予算を決めたら、帯の「予算を変更」の代わりにここから変える（帯にはカレンダーのボタンを置く）。
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                budgetButton
                Spacer(minLength: 8)
                ReportLink(action: openReport)
            }
            VStack(alignment: .leading, spacing: 8) {
                budgetButton
                ReportLink(action: openReport)
            }
        }
    }

    private var budgetButton: some View {
        Button(action: editBudget) {
            Text(outlook.budget == nil ? "予算を決める" : "予算を変更")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accentText)
                .lineLimit(2)
                .frame(minHeight: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    }
}

/// 今月でない月の、支出と収入。見通し（今日あと）は今月だけに出す。
private struct CalendarMonthTotalsCard: View {
    let days: LedgerCalendarMonth
    /// 月のまとめを開く。nil なら入口を出さない（先の月）。
    let openReport: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReportRow(label: Text("支出"), value: YenFormatter.string(from: days.expense))
            // 収入の色は、収入があるときだけ（月のまとめと同じ）。
            ReportRow(
                label: Text("収入"), value: YenFormatter.string(from: days.income),
                valueColor: days.income > 0 ? Theme.income : Theme.ink
            )
            if let openReport {
                HStack {
                    Spacer(minLength: 0)
                    ReportLink(action: openReport)
                }
            }
        }
        .reportCard()
    }
}

/// 月のまとめ（⑦）への入口。「›」で横に進むことを示す。
private struct ReportLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("月のまとめ")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accentText)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// 「今日の目安 ¥…・使った額 ¥…」のような 2 つの数字。アクセシビリティサイズの文字で 1 行に収まらなければ縦に積み、そのときだけ
/// 区切りの点を外す（ホームの帯の「1日あたり ¥…・のこり N 日」と同じ）。
private struct FigurePair: View {
    let first: Text
    let second: Text

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let inline = HStack(alignment: .firstTextBaseline, spacing: 4) {
            figure(first)
            Text("・")
            figure(second)
        }
        if dynamicTypeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                inline
                VStack(alignment: .leading, spacing: 2) {
                    figure(first)
                    figure(second)
                }
            }
        } else {
            inline
        }
    }

    private func figure(_ text: Text) -> some View {
        text
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - カレンダー

/// 月のカレンダー（7 列）。週の始まりは設定のとおり（画面の暦の `firstWeekday`）。
private struct CalendarMonthGrid: View {
    let model: LedgerCalendarModel
    let days: LedgerCalendarMonth

    var body: some View {
        VStack(spacing: 6) {
            weekdayRow
            // 週ごとの横の並び。列の幅は中身によらずそろえる（日ごとに金額の桁が違っても、列がずれないように）。
            // 行の高さは、その週のいちばん高い日に合わせ、どの日の枠も同じ高さにする。
            VStack(spacing: 2) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 2) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            if let day {
                                CalendarDayCell(
                                    day: day,
                                    isSelected: model.selectedDay == day.start,
                                    isToday: model.isToday(day),
                                    isFuture: model.isFuture(day),
                                    exceedsPace: model.exceedsPace(day),
                                    plannedCount: model.planned(on: day.start).count,
                                    calendar: model.calendar
                                ) {
                                    model.select(day)
                                }
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            CalendarLegend(showsPace: days.dailyPace(budget: model.budget) != nil, showsPlanned: !model.planned.isEmpty)
        }
        .reportCard()
    }

    /// 曜日の見出し（週の始まりから）。日のボタンが日付と曜日を読むので、VoiceOver では読ませない。
    private var weekdayRow: some View {
        let symbols = model.calendar.veryShortStandaloneWeekdaySymbols
        let first = model.calendar.firstWeekday - 1
        return HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                Text(verbatim: symbols[(first + index) % 7])
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// 週ごとの日（1 日の前と月の終わりの後の空きは nil）。
    private var weeks: [[LedgerCalendarMonth.Day?]] {
        var cells: [LedgerCalendarMonth.Day?] = Array(repeating: nil, count: days.leadingBlankCount) + days.days.map(Optional.some)
        while !cells.count.isMultiple(of: 7) { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

/// カレンダーの 1 日。日・その日の支出（支出が無く収入があれば収入）・印（予算の日割りより多い日の点と、くり返しの予定の記号）。
///
/// 今日は日の数字を主の塗りの丸に入れ、選んでいる日は枠で囲む。予算の日割りより多い日は、点（形）と注意の色の金額で示す
/// （色だけに頼らない。下の凡例に意味を書き、VoiceOver では語で読む）。
private struct CalendarDayCell: View {
    let day: LedgerCalendarMonth.Day
    let isSelected: Bool
    let isToday: Bool
    let isFuture: Bool
    let exceedsPace: Bool
    let plannedCount: Int
    let calendar: Calendar
    let select: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var numberSize = 26

    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                number
                amount
                marks
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity, alignment: .top)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.ink, lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        // 文字の色はセルの中で決めているので、tint に染めない形にする（押している間は薄くなる）。
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.start, format: spokenDateFormat))
        .accessibilityValue(Text(verbatim: spokenValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("この日の記録を出します")
    }

    private var number: some View {
        Text(verbatim: "\(day.dayOfMonth)")
            .font(.subheadline.weight(isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(isToday ? Theme.onAccent : isFuture ? Theme.inkSecondary : Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: numberSize, height: numberSize)
            .background {
                if isToday {
                    Circle().fill(Theme.accentFill)
                }
            }
    }

    @ViewBuilder
    private var amount: some View {
        if day.expense > 0 {
            amountText(YenFormatter.digits(from: day.expense), color: exceedsPace ? Theme.danger : Theme.ink)
        } else if day.income > 0 {
            amountText("+" + YenFormatter.digits(from: day.income), color: Theme.income)
        }
    }

    private func amountText(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(color)
            // 金額は桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var marks: some View {
        if exceedsPace || plannedCount > 0 {
            HStack(spacing: 3) {
                if exceedsPace {
                    PaceMark()
                }
                if plannedCount > 0 {
                    Image(systemName: "repeat")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
    }

    private var spokenDateFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.wide).day().weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }

    /// 読み上げる中身（今日・支出・収入・目安より多い・予定）。何も無ければ「記録なし」。
    private var spokenValue: String {
        CalendarDaySpeech.items(
            day: day, isToday: isToday, exceedsPace: exceedsPace, plannedCount: plannedCount
        ).formatted(.list(type: .and))
    }
}

/// 日の読み上げの中身（表のセルと、アクセシビリティサイズの一覧の行で同じにする）。
private enum CalendarDaySpeech {
    static func items(day: LedgerCalendarMonth.Day, isToday: Bool, exceedsPace: Bool, plannedCount: Int) -> [String] {
        var items: [String] = []
        if isToday { items.append(String(localized: "今日")) }
        if day.expense > 0 { items.append(String(localized: "支出 \(YenFormatter.string(from: day.expense))")) }
        if day.income > 0 { items.append(String(localized: "収入 \(YenFormatter.string(from: day.income))")) }
        if exceedsPace { items.append(String(localized: "日割りの目安より多い")) }
        if plannedCount > 0 { items.append(String(localized: "くり返しの予定 \(plannedCount) 件")) }
        if day.recordCount == 0, plannedCount == 0 { items.append(String(localized: "記録なし")) }
        return items
    }
}

/// 予算の日割りより多い日の印（注意の色の点）。
private struct PaceMark: View {
    @ScaledMetric(relativeTo: .caption2) private var size = 6

    var body: some View {
        Circle()
            .fill(Theme.danger)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 印の意味。出ている印だけを書く。日のボタンが印の意味を語で読むので、VoiceOver では読ませない。
private struct CalendarLegend: View {
    let showsPace: Bool
    let showsPlanned: Bool

    var body: some View {
        if showsPace || showsPlanned {
            HStack(spacing: 12) {
                if showsPace {
                    Label { Text("日割りの目安より多い") } icon: { PaceMark() }
                }
                if showsPlanned {
                    Label { Text("くり返しの予定") } icon: { Image(systemName: "repeat") }
                }
                Spacer(minLength: 0)
            }
            .labelStyle(LegendLabelStyle())
            .font(.caption)
            .foregroundStyle(Theme.inkSecondary)
            .accessibilityHidden(true)
        }
    }
}

/// 凡例の印と語を近づけて並べる（既定の Label は印と語の間が広く、隣の項目の印と見分けにくいため）。
private struct LegendLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - アクセシビリティサイズの一覧

/// 文字がとても大きいときの日の一覧（記録か予定のある日と今日）。選んだ日の記録は、その日の行の下に出す。
private struct CalendarDayList<Panel: View>: View {
    let model: LedgerCalendarModel
    let days: LedgerCalendarMonth
    @ViewBuilder let panel: (LedgerCalendarMonth.Day) -> Panel

    var body: some View {
        let listed = days.days.filter { $0.recordCount > 0 || !model.planned(on: $0.start).isEmpty || model.isToday($0) }
        VStack(alignment: .leading, spacing: 8) {
            if listed.isEmpty {
                Text("この月の記録はありません")
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.vertical, 8)
            }
            ForEach(listed) { day in
                CalendarDayListRow(
                    day: day,
                    isSelected: model.selectedDay == day.start,
                    isToday: model.isToday(day),
                    exceedsPace: model.exceedsPace(day),
                    plannedCount: model.planned(on: day.start).count,
                    calendar: model.calendar
                ) {
                    model.select(day)
                }
                if model.selectedDay == day.start {
                    panel(day)
                }
            }
        }
    }
}

/// 一覧の 1 日。日付と曜日・その日の支出（収入）・印の語。
private struct CalendarDayListRow: View {
    let day: LedgerCalendarMonth.Day
    let isSelected: Bool
    let isToday: Bool
    let exceedsPace: Bool
    let plannedCount: Int
    let calendar: Calendar
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 4) {
                Text(day.start, format: dateFormat)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if day.expense > 0 {
                    Text(verbatim: YenFormatter.string(from: day.expense))
                        .monospacedDigit()
                        .foregroundStyle(exceedsPace ? Theme.danger : Theme.ink)
                } else if day.income > 0 {
                    Text(verbatim: YenFormatter.signedString(from: day.income))
                        .monospacedDigit()
                        .foregroundStyle(Theme.income)
                }
                if exceedsPace {
                    Label { Text("日割りの目安より多い") } icon: { PaceMark() }
                        .labelStyle(LegendLabelStyle())
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
                if plannedCount > 0 {
                    Label("くり返しの予定", systemImage: "repeat")
                        .labelStyle(LegendLabelStyle())
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: .rect(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.ink, lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.start, format: spokenDateFormat))
        .accessibilityValue(Text(verbatim: CalendarDaySpeech.items(
            day: day, isToday: isToday, exceedsPace: exceedsPace, plannedCount: plannedCount
        ).formatted(.list(type: .and))))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("この日の記録を出します")
    }

    private var dateFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }

    private var spokenDateFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.wide).day().weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}

// MARK: - 選んだ日

/// 選んだ日の記録と予定。記録の行は会話の返事の行と同じもの（押すと ⑥ 直す、長押しで直す・毎月くり返す・削除）。
/// 下の「この日に記録」で、会話の入力欄にその日の日付を入れる。
private struct CalendarDayPanel: View {
    let day: LedgerCalendarMonth.Day
    /// 日付とその日の支出の見出しを出すか（文字がとても大きいときの一覧では、上の行に出ているので出さない）。
    let showsHeader: Bool
    let records: [LedgerCalendarModel.DayRecord]
    let planned: [PlannedOccurrence]
    let calendar: Calendar
    let edit: (LedgerCalendarModel.DayRecord) -> Void
    let requestDelete: (LedgerCalendarModel.DayRecord) -> Void
    let makeRecurring: (LedgerCalendarModel.DayRecord) -> Void
    let recordOnDay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                header
            }
            if records.isEmpty, planned.isEmpty {
                Text("この日の記録はありません")
                    .foregroundStyle(Theme.inkSecondary)
            }
            ForEach(records) { record in
                RecordedReplyRow(
                    // 使った日を「送った日」として渡し、行に日付を添えない（どの行もこの日の記録で、日付は見出しにあるため）。
                    // 日付を添えないので、年を添えるかの基準（today）は使われない。
                    entry: record, sentAt: record.spentAt, today: day.start,
                    edit: { edit(record) },
                    requestDelete: { requestDelete(record) },
                    // くり返しの記録から記録したものは、もうくり返しているので出さない（会話の返事と同じ）。
                    makeRecurring: record.isRecurring ? nil : { makeRecurring(record) }
                )
            }
            ForEach(planned) { occurrence in
                PlannedOccurrenceRow(occurrence: occurrence)
            }
            Button(action: recordOnDay) {
                Label("この日に記録", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .accessibilityHint("会話に戻り、入力欄にこの日の日付を入れます")
        }
        .reportCard()
    }

    /// 日付と曜日、その日の支出（収入があれば収入も）。
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title
                Spacer(minLength: 8)
                totals
            }
            VStack(alignment: .leading, spacing: 4) {
                title
                totals
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text(day.start, format: titleFormat)
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }

    /// その日の合計。記録の無い日（予定だけの日も）は出さない（「¥0」と出すと、予定の額が数えられていないように見えるため）。
    @ViewBuilder
    private var totals: some View {
        if day.recordCount > 0 {
            totalFigures
        }
    }

    private var totalFigures: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if day.expense > 0 || day.income == 0 {
                Text(verbatim: YenFormatter.string(from: day.expense))
                    .foregroundStyle(Theme.ink)
                    .accessibilityLabel(Text("支出 \(YenFormatter.string(from: day.expense))"))
            }
            if day.income > 0 {
                Text(verbatim: YenFormatter.signedString(from: day.income))
                    .foregroundStyle(Theme.income)
                    .accessibilityLabel(Text("収入 \(YenFormatter.string(from: day.income))"))
            }
        }
        .font(.headline)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    private var titleFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}

/// まだ記録していない、くり返しの記録の予定の行。記録の行と同じ並び（印・品目・種別・金額）で、印はくり返しの記号の淡い塗りにして、
/// まだ記録ではないことを示す（記録する日を過ぎたら、開いたときにアプリが記録し、記録の行に替わる）。
private struct PlannedOccurrenceRow: View {
    let occurrence: PlannedOccurrence

    @Environment(\.categoryCatalog) private var catalog
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var tileSize = 36

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "repeat")
                    .font(.system(size: tileSize * 0.45, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: tileSize, height: tileSize)
                    .background(Theme.track, in: .rect(cornerRadius: tileSize * 0.28))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        titleText
                        Spacer(minLength: 8)
                        amountText
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        titleText
                        amountText
                    }
                }
                Text("くり返しの予定・\(kind)")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var kind: String {
        occurrence.isIncome ? String(localized: "収入") : catalog.localizedName(for: occurrence.category)
    }

    private var titleText: some View {
        Text(verbatim: occurrence.memo.isEmpty ? kind : occurrence.memo)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.ink)
    }

    private var amountText: some View {
        Text(verbatim: occurrence.isIncome
            ? YenFormatter.signedString(from: occurrence.amount) : YenFormatter.string(from: occurrence.amount))
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(occurrence.isIncome ? Theme.income : Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
