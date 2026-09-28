import SaifuLogCore
import SwiftUI

/// 月のまとめ（⑦）の内訳の行から進む、その月のそのカテゴリの支出の記録の一覧。
///
/// 読むための一覧で、ここでは並べ替えも削除もしない。記録を押すと「直す」（⑥）のシートを開き、そこで直したり
/// 消したりできる（直してカテゴリや月が変わった記録は、一覧から外れる）。並びは使った日時の新しい順。
struct CategoryEntriesView: View {
    @Bindable var model: MonthlyReportModel
    let category: EntryCategory

    var body: some View {
        let entries = model.entries(in: category)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(count: entries.count)
                if entries.isEmpty {
                    Text("この月の記録はありません")
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            if entry.persistentModelID != entries.first?.persistentModelID {
                                Divider()
                            }
                            CategoryEntryRow(entry: entry, today: model.today, calendar: model.calendar) {
                                model.presentEdit(entry)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Theme.surface, in: .rect(cornerRadius: 16))
                }
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(Text(category.label))
        .navigationBarTitleDisplayMode(.inline)
        // item で出す（閉じる間も中身を保つ。ホームの「直す」と同じ）。閉じると editing は nil に戻る。
        .sheet(item: $model.editing) { editing in
            EditEntrySheet(model: editing)
        }
    }

    /// 月・そのカテゴリの合計と割合・件数。合計と割合は内訳の行と同じ値（`MonthlyReport` の内訳）を出す。
    private func header(count: Int) -> some View {
        let item = model.report?.breakdown.item(for: category)
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: model.monthTitle)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            Text(verbatim: YenFormatter.string(from: item?.amount ?? 0))
                .font(.largeTitle.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 8) {
                if let item {
                    Text(verbatim: item.percentText)
                        .accessibilityLabel(Text(verbatim: item.spokenPercent))
                }
                Text("\(count) 件")
            }
            .font(.footnote)
            .foregroundStyle(Theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 一覧の 1 件。品目（無ければカテゴリ名）と日付、金額。押すと「直す」のシートを開く。
private struct CategoryEntryRow: View {
    let entry: Entry
    /// 今日。日付に年を添えるかの基準。
    let today: Date
    let calendar: Calendar
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleAndDate
                    Spacer(minLength: 8)
                    amount
                }
                VStack(alignment: .leading, spacing: 4) {
                    titleAndDate
                    amount
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(.rect)
        }
        // 文字の色は行の中で決めているので、tint に染めない形にする（押している間は薄くなる）。
        .buttonStyle(.plain)
        .accessibilityHint("記録を直す画面を開きます")
    }

    private var titleAndDate: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 品目が無ければカテゴリ名（吹き出しの見出しと同じ）。
            if entry.memo.isEmpty {
                Text(entry.category.label)
            } else {
                Text(verbatim: entry.memo)
            }
            Text(entry.spentAt, format: dateFormat)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .foregroundStyle(Theme.ink)
    }

    private var amount: some View {
        Text(verbatim: YenFormatter.string(from: entry.amount))
            .font(.headline)
            .monospacedDigit()
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// 月を区切ったのと同じ暦・時間帯で日付を書く（今年でなければ年も）。
    private var dateFormat: Date.FormatStyle {
        var format: Date.FormatStyle = entry.showsYear(today: today, calendar: calendar)
            ? .dateTime.year().month().day() : .dateTime.month().day()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        return format
    }
}
