import SaifuLogCore
import SwiftUI
import WidgetKit

/// 今月使った額と、予算を決めていれば残り（「あと ¥…」か「¥… オーバー」）とバー。ホームの帯と同じ数字だけを出す
/// （1 日あたり・カテゴリ・記録の品目は出さない。数字を増やすと、いちばん知りたい使った額が埋もれるため。`docs/design.md` §9）。
///
/// ホーム画面の小さいウィジェットと、ロック画面の 3 つ（長方形・丸・時計の上の 1 行）。ロック画面では、端末のロック中は金額を
/// 隠す（`privacySensitive`。ロック画面は端末を持っていない人にも見えるため）。アプリのロックをオンにしている間は、どこにも
/// 金額を出さない（アプリが数字を渡さない。`WidgetSnapshot.hidden`）。押すと、会話の入力欄を開いてアプリを開く（`WidgetLink`）。
/// 出す文と数字の決め事は `MonthSpendPresentation`、並べ方は `MonthSpendContent`。
struct MonthSpendWidget: Widget {
    static let kind = "MonthSpend"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: MonthSpendProvider()) { entry in
            MonthSpendWidgetView(entry: entry)
        }
        .configurationDisplayName("今月使った額")
        .description("今月使った額と予算の残りを出します。押すと記録の入力欄を開きます。")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// ウィジェットの 1 回分の表示。
struct MonthSpendEntry: TimelineEntry, Equatable {
    let date: Date
    /// 出すもの。nil ならまだ数字が無い（入れてからアプリを開いていない・ファイルを読めない）。
    let display: WidgetDisplay?
}

/// アプリが書いた数字（`WidgetSnapshotFile`）を読んで並べる。いまの分と、次の月の始まりの分（月が替わると使った額が 0 に戻る）。
/// 記録が変わったときは、アプリが描き直させる（`WidgetPublisher`）。
struct MonthSpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthSpendEntry {
        Self.sample(now: .now, calendar: .current)
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthSpendEntry) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let entry = Self.entry(at: now, snapshot: Self.readSnapshot(), calendar: calendar)
        completion(Self.snapshotEntry(entry, isPreview: context.isPreview, calendar: calendar))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthSpendEntry>) -> Void) {
        completion(Timeline(entries: Self.entries(now: .now, snapshot: Self.readSnapshot(), calendar: .current), policy: .atEnd))
    }

    static func readSnapshot() -> WidgetSnapshot? {
        WidgetSnapshotFile.defaultURL.flatMap(WidgetSnapshotFile.read(from:))
    }

    /// 並べる表示: いまの分と、次の月の始まりの分。最後の分を出したら描き直させる（`.atEnd`）ので、アプリを開かなくても月ごとに
    /// 並べ直す。
    static func entries(now: Date, snapshot: WidgetSnapshot?, calendar: Calendar) -> [MonthSpendEntry] {
        var entries = [entry(at: now, snapshot: snapshot, calendar: calendar)]
        if let next = WidgetSnapshot.nextRefresh(after: now, calendar: calendar) {
            entries.append(entry(at: next, snapshot: snapshot, calendar: calendar))
        }
        return entries
    }

    static func entry(at date: Date, snapshot: WidgetSnapshot?, calendar: Calendar) -> MonthSpendEntry {
        MonthSpendEntry(date: date, display: snapshot?.display(now: date, calendar: calendar))
    }

    /// ウィジェットを選ぶ画面（`isPreview`）では、まだ数字が無ければ見本の数字で見せる（何が出るのか分かるように）。それ以外は
    /// 読んだとおり。
    static func snapshotEntry(_ entry: MonthSpendEntry, isPreview: Bool, calendar: Calendar) -> MonthSpendEntry {
        isPreview && entry.display == nil ? sample(now: entry.date, calendar: calendar) : entry
    }

    /// 見本（ウィジェットを選ぶ画面と、読み込みの間の形）。
    static func sample(now: Date, calendar: Calendar) -> MonthSpendEntry {
        let budget = ReportPeriod.thisMonth.interval(now: now, calendar: calendar).flatMap {
            BudgetStatus(budget: 50_000, spent: 32_480, now: now, month: $0, calendar: calendar)
        }
        return MonthSpendEntry(date: now, display: .figures(spent: 32_480, budget: budget))
    }
}

struct MonthSpendWidgetView: View {
    let entry: MonthSpendEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let layout = MonthSpendLayout(family)
        MonthSpendContent(presentation: MonthSpendPresentation(display: entry.display, layout: layout), layout: layout)
            .widgetURL(WidgetLink.record)
            // 地はアプリと同じく白（ダークでは黒）。色はアプリの外観に合わせて墨と白だけにし、注意の赤だけを足す。
            .containerBackground(.background, for: .widget)
    }
}

extension MonthSpendLayout {
    init(_ family: WidgetFamily) {
        switch family {
        case .accessoryRectangular: self = .rectangular
        case .accessoryCircular: self = .circular
        case .accessoryInline: self = .inline
        default: self = .small
        }
    }
}

/// ウィジェットの中身（大きさごとの並べ方）。文と数字は `MonthSpendPresentation` が決める。金額はロック画面で端末のロック中に
/// 隠す（`privacySensitive`）。
struct MonthSpendContent: View {
    let presentation: MonthSpendPresentation
    let layout: MonthSpendLayout

    var body: some View {
        if presentation.kind == .figures {
            figures
        } else {
            message
        }
    }

    // MARK: - 数字

    @ViewBuilder
    private var figures: some View {
        switch layout {
        case .inline:
            Text(verbatim: presentation.primary)
                .privacySensitive()
        case .circular:
            circular
        case .rectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: presentation.primary)
                    .font(.headline)
                    .monospacedDigit()
                    .widgetAccentable()
                    .privacySensitive()
                if let fraction = presentation.fraction {
                    Gauge(value: fraction) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .privacySensitive()
                }
                if let budgetLine = presentation.budgetLine {
                    budgetText(budgetLine, warningColor: .primary)
                        .font(.caption)
                        .privacySensitive()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        case .small:
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: presentation.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: presentation.primary)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(presentation.isOver ? Color.red : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .privacySensitive()
                Spacer(minLength: 0)
                if let fraction = presentation.fraction {
                    ProgressView(value: fraction)
                        .tint(presentation.isOver ? Color.red : Color.primary)
                        .privacySensitive()
                }
                if let budgetLine = presentation.budgetLine {
                    budgetText(budgetLine, warningColor: .red)
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        }
    }

    /// 予算の行。超えたら、色だけでなくアイコンと「オーバー」の語でも伝える（ホームの帯と同じ）。
    @ViewBuilder
    private func budgetText(_ line: String, warningColor: Color) -> some View {
        if presentation.isOver {
            Label {
                Text(verbatim: line)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(warningColor)
        } else {
            Text(verbatim: line)
                .foregroundStyle(.secondary)
        }
    }

    /// 丸。予算があれば使った割合のゲージ（超えたら注意の印）、無ければ使った額だけ。
    @ViewBuilder
    private var circular: some View {
        if let fraction = presentation.fraction {
            Gauge(value: fraction) {
                if let symbol = presentation.symbol {
                    Image(systemName: symbol)
                }
            } currentValueLabel: {
                if presentation.isOver {
                    Image(systemName: "exclamationmark")
                } else {
                    Text(verbatim: presentation.primary)
                        .minimumScaleFactor(0.5)
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .privacySensitive()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text(verbatim: presentation.primary)
                    .font(.caption.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(4)
                    .privacySensitive()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        }
    }

    // MARK: - 数字が無いとき・ロック中

    @ViewBuilder
    private var message: some View {
        let symbol = presentation.symbol ?? "yensign.circle"
        switch layout {
        case .inline:
            Label {
                Text(verbatim: presentation.title)
            } icon: {
                Image(systemName: symbol)
            }
        case .circular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
                    .font(.title3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        case .rectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label {
                    Text(verbatim: presentation.title)
                } icon: {
                    Image(systemName: symbol)
                }
                .font(.headline)
                .widgetAccentable()
                Text(verbatim: presentation.primary)
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        case .small:
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(verbatim: presentation.title)
                } icon: {
                    Image(systemName: symbol)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(verbatim: presentation.primary)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: presentation.accessibilityLabel))
        }
    }
}
