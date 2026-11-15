import SaifuLogCore
import SwiftUI

/// 月の画面（⑦ 月のまとめ）の「カレンダー」。月のカレンダーの日ごとに使った額と、選んだ日の合計と記録。
///
/// 前はホームを左へスワイプした 2 枚目のページだったが、見えない入口で見つけにくく、月のまとめと同じ月を別の画面で
/// 見せていたので、月の画面の切り替えの 1 つにした（月送りと使った額は月の画面が持つ）。「いくら使ったか」だけが分かる
/// ようにし、見通し・予算の日割りの印・くり返しの予定の印は出さない。
///
/// 文字がとても大きいとき（アクセシビリティサイズ）は 7 列の表をやめ、記録のある日と今日の一覧にして、選んだ日の記録をその日の
/// 行の下に出す（7 列では、日の数字も金額も読めない大きさまで縮むため）。
struct MonthCalendarContent: View {
    let model: LedgerCalendarModel
    let edit: (Entry) -> Void
    /// 削除を求める（確認は月の画面が出す）。
    let requestDelete: (Entry) -> Void
    /// その記録の中身で、くり返しの記録を作る画面を開く（行の長押しの「毎月くり返す」）。nil なら出さない。
    let makeRecurring: ((Entry) -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if model.loadFailed {
            LoadFailedView(retry: { model.reload() })
        } else if let days = model.days {
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

    private func dayPanel(_ day: LedgerCalendarMonth.Day, showsHeader: Bool) -> some View {
        CalendarDayPanel(
            day: day,
            showsHeader: showsHeader,
            records: model.selectedRecords,
            calendar: model.calendar,
            edit: { if let entry = model.entry(for: $0) { edit(entry) } },
            requestDelete: { if let entry = model.entry(for: $0) { requestDelete(entry) } },
            makeRecurring: makeRecurring.map { make in { if let entry = model.entry(for: $0) { make(entry) } } }
        )
    }
}

// MARK: - カレンダー

/// 月のカレンダー（7 列）。週の始まりは端末の設定のとおり（画面の暦の `firstWeekday`）。
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

/// カレンダーの 1 日。日の数字と、その日に使った額（無ければ空）。
///
/// 今日は日の数字を主の塗りの丸に入れ、選んでいる日は枠で囲む。収入はマスに出さない（「いくら使ったか」を見るページなので、
/// マスの数字は支出だけにそろえる。収入は選んだ日の合計に出す）。
private struct CalendarDayCell: View {
    let day: LedgerCalendarMonth.Day
    let isSelected: Bool
    let isToday: Bool
    let isFuture: Bool
    let calendar: Calendar
    let select: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var numberSize = 26

    var body: some View {
        Button(action: select) {
            VStack(spacing: 2) {
                number
                amount
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
        .accessibilityLabel(Text(day.start, format: CalendarDaySpeech.dateFormat(calendar)))
        .accessibilityValue(Text(verbatim: CalendarDaySpeech.value(day: day, isToday: isToday)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("この日の記録を出します")
        .accessibilityIdentifier(AccessibilityID.CalendarPage.day(calendar.component(.day, from: day.start)))
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
            Text(verbatim: YenFormatter.digits(from: day.expense))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                // 金額は桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// 日の読み上げ（表のセルと、アクセシビリティサイズの一覧の行で同じにする）。
private enum CalendarDaySpeech {
    static func dateFormat(_ calendar: Calendar) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month(.wide).day().weekday(.wide)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }

    /// 読み上げる中身（今日・使った額）。使っていなければ「使っていない」。画面の見出し（「使った額」）と同じ言葉で読む。
    static func value(day: LedgerCalendarMonth.Day, isToday: Bool) -> String {
        var items: [String] = []
        if isToday { items.append(String(localized: "今日")) }
        items.append(day.expense > 0
            ? String(localized: "使った額 \(YenFormatter.string(from: day.expense))")
            : String(localized: "使っていない"))
        return items.formatted(.list(type: .and))
    }
}

// MARK: - アクセシビリティサイズの一覧

/// 文字がとても大きいときの日の一覧（記録のある日と今日）。選んだ日の記録は、その日の行の下に出す。
private struct CalendarDayList<Panel: View>: View {
    let model: LedgerCalendarModel
    let days: LedgerCalendarMonth
    @ViewBuilder let panel: (LedgerCalendarMonth.Day) -> Panel

    var body: some View {
        let listed = days.days.filter { $0.recordCount > 0 || model.isToday($0) }
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

/// 一覧の 1 日。日付と曜日・その日に使った額。
private struct CalendarDayListRow: View {
    let day: LedgerCalendarMonth.Day
    let isSelected: Bool
    let isToday: Bool
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
                        .foregroundStyle(Theme.ink)
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
        .accessibilityLabel(Text(day.start, format: CalendarDaySpeech.dateFormat(calendar)))
        .accessibilityValue(Text(verbatim: CalendarDaySpeech.value(day: day, isToday: isToday)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("この日の記録を出します")
        .accessibilityIdentifier(AccessibilityID.CalendarPage.day(calendar.component(.day, from: day.start)))
    }

    private var dateFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}

// MARK: - 選んだ日

/// 選んだ日の合計と記録。記録の行は会話の返事の行と同じもの（押すと ⑥ 直す、長押しで直す・毎月くり返す・削除）。
private struct CalendarDayPanel: View {
    let day: LedgerCalendarMonth.Day
    /// 日付とその日に使った額の見出しを出すか（文字がとても大きいときの一覧では、上の行に出ているので出さない）。
    let showsHeader: Bool
    let records: [LedgerCalendarModel.DayRecord]
    let calendar: Calendar
    let edit: (LedgerCalendarModel.DayRecord) -> Void
    let requestDelete: (LedgerCalendarModel.DayRecord) -> Void
    /// nil なら長押しに「毎月くり返す」を出さない。
    let makeRecurring: ((LedgerCalendarModel.DayRecord) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                header
            }
            if records.isEmpty {
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
                    makeRecurring: record.isRecurring ? nil : makeRecurring.map { make in { make(record) } }
                )
            }
        }
        .reportCard()
    }

    /// 日付と曜日、その日に使った額（収入があれば収入も）。
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

    /// その日の合計。記録の無い日は出さない（下に「この日の記録はありません」と出るため）。
    @ViewBuilder
    private var totals: some View {
        if day.recordCount > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if day.expense > 0 || day.income == 0 {
                    Text(verbatim: YenFormatter.string(from: day.expense))
                        .foregroundStyle(Theme.ink)
                        .accessibilityLabel(Text("使った額 \(YenFormatter.string(from: day.expense))"))
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
    }

    private var titleFormat: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return style
    }
}
