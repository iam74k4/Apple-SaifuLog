import SaifuLogCore
import SwiftUI

/// 先週のふりかえりの内訳。ホームのタイムラインのカードを押すと横に進む。
///
/// 月のまとめ（⑦）に週の表示を足さず、⑦ と同じ部品（数字の行・内訳のグラフと行・カテゴリの記録の一覧）で先週だけを出す。
/// ⑦ は月送りの画面で、週を足すと月と週の切り替えと週送りが要り、ふりかえりから開く先としては重いため。週送りは作らない
/// （先週だけ。前の週との差はカードと同じく数字で出す）。
///
/// 上に期間、その下に先週の支出・前の週との差・記録のある日・いちばん使った日、週の目安との比べ（予算を当てはめるときだけ）、
/// カテゴリ別の内訳（横棒グラフと行）を並べる。行を押すと、先週のそのカテゴリの記録の一覧へ進み、そこから ⑥ で直せる。
/// 保存先に書き込まれたときの読み直しは、ホーム（この画面の下に残っている）が受け持つ（同じモデルを 2 度読み直さないため）。
struct WeeklyRecapView: View {
    @Bindable var model: WeeklyRecapModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(verbatim: model.periodTitle)
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .foregroundStyle(Theme.ink)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(Text(RecapTexts.title))
        .navigationBarTitleDisplayMode(.inline)
        // ホームはナビゲーションバーを隠しているので、ここでは戻るボタンのために出す。
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(item: $model.selectedCategory) { category in
            CategoryEntriesView(model: model, category: category)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.loadFailed {
            LoadFailedView(retry: { model.reload() })
        } else if let recap = model.recap {
            if recap.isEmpty {
                Text("先週の記録はありません")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
            } else {
                WeekSummaryCard(recap: recap, calendar: model.calendar)
                if let pace = recap.budgetPace {
                    WeekPaceCard(recap: recap, pace: pace)
                }
                BreakdownCard(
                    breakdown: recap.breakdown,
                    emptyText: "この週の支出の記録はありません",
                    rowHint: "この週の記録の一覧を開きます",
                    select: { model.showEntries(in: $0) }
                )
            }
        }
    }
}

/// 先週の支出を大きく、その下に前の週との差、記録のある日、いちばん使った日を並べる。
private struct WeekSummaryCard: View {
    let recap: WeeklyRecap
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("支出")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                Text(verbatim: YenFormatter.string(from: recap.expense))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    // 金額は桁の途中で改行させない。収まらなければ縮めて 1 行に収める。
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityElement(children: .combine)
            changeLabel
                .labelStyle(TrendLabelStyle())
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            Divider()
            ReportRow(label: Text("記録のある日"), value: String(localized: "\(recap.recordedDayCount) 日", comment: "先週のふりかえりの内訳。記録のある日の数。%lld は日数"))
            if let day = recap.busiestDay {
                ReportRow(label: Text("いちばん使った日"), value: "\(dayText(day.interval.start)) \(YenFormatter.string(from: day.expense))")
            }
        }
        .reportCard()
    }

    /// 前の週との差。多いか少ないかは、矢印だけでなく語でも伝える。前の週に支出の記録が無ければ出さない。
    @ViewBuilder
    private var changeLabel: some View {
        switch recap.change {
        case .more(let difference):
            Label { Text("前の週より \(YenFormatter.string(from: difference)) 多い") } icon: { Image(systemName: "arrow.up.right") }
        case .less(let difference):
            Label { Text("前の週より \(YenFormatter.string(from: difference)) 少ない") } icon: { Image(systemName: "arrow.down.right") }
        case .same:
            Label { Text("前の週と同じ") } icon: { Image(systemName: "equal") }
        case .noComparison:
            EmptyView()
        }
    }

    /// 週を区切ったのと同じ暦・時間帯で、月日と曜日を書く（「9月23日(水)」）。
    private func dayText(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}

/// 週の目安（月の予算を先週の日数で日割りした額）と、先週の支出との比べ。
private struct WeekPaceCard: View {
    let recap: WeeklyRecap
    let pace: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 見出しは月のまとめの予算の欄と同じ「予算」（下の行の「週の目安」と重ねない）。
            Text("予算")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ReportRow(label: Text("週の目安"), value: YenFormatter.string(from: pace))
            ReportRow(label: Text("先週の支出"), value: YenFormatter.string(from: recap.expense))
            if let comparison = RecapTexts.paceComparison(for: recap) {
                Label {
                    Text(verbatim: comparison.text)
                } icon: {
                    Image(systemName: comparison.beyond > 0
                        ? "arrow.up.right" : comparison.beyond < 0 ? "arrow.down.right" : "equal")
                }
                .labelStyle(TrendLabelStyle())
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
            }
            Text("月の予算を、先週の日ごとにその月の日数で割って足した額です（月をまたぐ週は、それぞれの月で割ります）。")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .reportCard()
    }
}
