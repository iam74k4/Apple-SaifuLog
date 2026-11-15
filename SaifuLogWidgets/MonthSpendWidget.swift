import SaifuLogCore
import SwiftUI
import WidgetKit

/// 今月使った額と、予算を決めていれば残り（「あと ¥…」か「¥… オーバー」）とバー。ホームの帯と同じ数字だけを出す
/// （1 日あたり・カテゴリ・記録の品目は出さない。数字を増やすと、いちばん知りたい使った額が埋もれるため。`docs/design.md` §9）。
///
/// ホーム画面の小さいウィジェットと、ロック画面の 3 つ（長方形・丸・時計の上の 1 行）。ロック画面では、端末のロック中は金額を
/// 隠す（`privacySensitive`。ロック画面は端末を持っていない人にも見えるため）。アプリのロックをオンにしている間は、どこにも
/// 金額を出さない（アプリが数字を渡さない。`WidgetSnapshot.hidden`）。押すと、会話の入力欄を開いてアプリを開く（`WidgetLink`）。
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
struct MonthSpendEntry: TimelineEntry {
    let date: Date
    /// 出すもの。nil ならまだ数字が無い（入れてからアプリを開いていない・ファイルを読めない）。
    let display: WidgetDisplay?
}

/// アプリが書いた数字（`WidgetSnapshotFile`）を読んで並べる。いまの分と、次の月の始まりの分（月が替わると使った額が 0 に戻る）。
/// 記録が変わったときは、アプリが描き直させる（`WidgetPublisher`）。
struct MonthSpendProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthSpendEntry {
        Self.sample(now: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (MonthSpendEntry) -> Void) {
        let now = Date.now
        // ウィジェットを選ぶ画面では、まだ数字が無ければ見本の数字で見せる（何が出るのか分かるように）。
        let entry = Self.entry(at: now, snapshot: Self.readSnapshot(), calendar: .current)
        completion(context.isPreview && entry.display == nil ? Self.sample(now: now) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthSpendEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let snapshot = Self.readSnapshot()
        var entries = [Self.entry(at: now, snapshot: snapshot, calendar: calendar)]
        if let next = WidgetSnapshot.nextRefresh(after: now, calendar: calendar) {
            entries.append(Self.entry(at: next, snapshot: snapshot, calendar: calendar))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    static func readSnapshot() -> WidgetSnapshot? {
        WidgetSnapshotFile.defaultURL.flatMap(WidgetSnapshotFile.read(from:))
    }

    static func entry(at date: Date, snapshot: WidgetSnapshot?, calendar: Calendar) -> MonthSpendEntry {
        MonthSpendEntry(date: date, display: snapshot?.display(now: date, calendar: calendar))
    }

    /// 見本（ウィジェットを選ぶ画面と、読み込みの間の形）。
    static func sample(now: Date) -> MonthSpendEntry {
        let calendar = Calendar.current
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
        content
            .widgetURL(WidgetLink.record)
            // 地はアプリと同じく白（ダークでは黒）。色はアプリの外観に合わせて墨と白だけにし、注意の赤だけを足す。
            .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.display {
        case .figures(let spent, let budget):
            figures(spent: spent, budget: budget)
        case .hidden:
            message(symbol: "lock.fill", title: "ロック中", detail: "アプリのロック中は金額を出しません")
        case nil:
            message(symbol: "yensign.circle", title: "今月使った額", detail: "アプリを開くと出ます")
        }
    }

    // MARK: - 数字

    @ViewBuilder
    private func figures(spent: Int, budget: BudgetStatus?) -> some View {
        let amount = YenFormatter.string(from: spent)
        switch family {
        case .accessoryInline:
            inlineText(amount: amount, budget: budget)
                .privacySensitive()
        case .accessoryCircular:
            circular(amount: amount, budget: budget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("今月 \(amount)")
                    .font(.headline)
                    .monospacedDigit()
                    .widgetAccentable()
                    .privacySensitive()
                if let budget {
                    Gauge(value: budget.spentFraction) {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .privacySensitive()
                    budgetText(budget)
                        .font(.caption)
                        .privacySensitive()
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Text("今月使った額")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: amount)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .foregroundStyle(budget?.isOver == true ? Color.red : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .privacySensitive()
                Spacer(minLength: 0)
                if let budget {
                    ProgressView(value: budget.spentFraction)
                        .tint(budget.isOver ? Color.red : Color.primary)
                        .accessibilityHidden(true)
                        .privacySensitive()
                    budgetText(budget)
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .privacySensitive()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 予算の残り。超えたら、色だけでなくアイコンと「オーバー」の語でも伝える（ホームの帯と同じ）。
    @ViewBuilder
    private func budgetText(_ budget: BudgetStatus) -> some View {
        if budget.isOver {
            Label {
                Text("\(YenFormatter.string(from: budget.overspent)) オーバー")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(family == .systemSmall ? Color.red : Color.primary)
        } else {
            Text("あと \(YenFormatter.string(from: budget.remaining))")
                .foregroundStyle(.secondary)
        }
    }

    /// 時計の上の 1 行。
    private func inlineText(amount: String, budget: BudgetStatus?) -> Text {
        guard let budget else { return Text("今月 \(amount)") }
        return budget.isOver
            ? Text("今月 \(amount)・\(YenFormatter.string(from: budget.overspent)) オーバー")
            : Text("今月 \(amount)・あと \(YenFormatter.string(from: budget.remaining))")
    }

    /// 丸。予算があれば使った割合のゲージ（超えたら注意の印）、無ければ使った額だけ。
    @ViewBuilder
    private func circular(amount: String, budget: BudgetStatus?) -> some View {
        if let budget {
            Gauge(value: budget.spentFraction) {
                Image(systemName: "yensign")
                    .accessibilityHidden(true)
            } currentValueLabel: {
                if budget.isOver {
                    Image(systemName: "exclamationmark")
                        .accessibilityLabel(Text("\(YenFormatter.string(from: budget.overspent)) オーバー"))
                } else {
                    Text(Double(budget.spent) / Double(budget.budget), format: .percent.precision(.fractionLength(0)))
                        .minimumScaleFactor(0.5)
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .privacySensitive()
            .accessibilityLabel(Text("今月使った額"))
            .accessibilityValue(Text(verbatim: amount))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Text(verbatim: amount)
                    .font(.caption.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(4)
                    .privacySensitive()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("今月使った額"))
        }
    }

    // MARK: - 数字が無いとき・ロック中

    @ViewBuilder
    private func message(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        switch family {
        case .accessoryInline:
            Label(title, systemImage: symbol)
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol)
                    .font(.title3)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(detail))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .widgetAccentable()
                Text(detail)
                    .font(.caption)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
