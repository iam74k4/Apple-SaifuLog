import SaifuLogCore
import SwiftUI

/// 正負のある比較を同じ尺度で描く。赤字を短い正の棒に見せないよう、0の線の左へ伸ばす。
struct PurchaseComparisonBars: View {
    struct Row: Identifiable {
        let title: LocalizedStringResource
        let amount: Int
        let symbol: String
        var id: String { symbol }
    }
    let rows: [Row]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasNegative: Bool { rows.contains { $0.amount < 0 } }
    private var scale: Double { max(1, rows.map { abs(Double($0.amount)) }.max() ?? 1) }

    var body: some View {
        VStack(spacing: 16) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 7) {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                    layout {
                        Label { Text(row.title) } icon: { Image(systemName: row.symbol) }
                            .font(.subheadline.weight(.medium))
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        Text(verbatim: YenFormatter.string(from: row.amount))
                            .font(.title3.bold()).monospacedDigit()
                            .foregroundStyle(row.amount < 0 ? Theme.danger : Theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    GeometryReader { geometry in
                        let origin = hasNegative ? geometry.size.width / 2 : 0
                        let available = hasNegative ? geometry.size.width / 2 : geometry.size.width
                        let width = abs(Double(row.amount)) / scale * available
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(row.amount < 0 ? Theme.danger : Theme.accentFill)
                                .frame(width: width)
                                .offset(x: row.amount < 0 ? origin - width : origin)
                            if hasNegative {
                                Rectangle().fill(Theme.inkSecondary).frame(width: 1)
                                    .offset(x: origin)
                            }
                        }
                    }.frame(height: 12).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(row.title))
                .accessibilityValue(Text(verbatim: YenFormatter.string(from: row.amount)))
            }
            if hasNegative {
                HStack {
                    Label("不足", systemImage: "arrow.left")
                    Spacer()
                    Text(verbatim: "0")
                    Spacer()
                    Label("余裕", systemImage: "arrow.right")
                }.font(.caption2).foregroundStyle(Theme.inkSecondary)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge).accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: rows.map(\.amount))
    }
}

/// 支出と確保額の配分。予算を超えたときも、各部分の比率を保って並べる。
struct PurchaseBudgetStrip: View {
    let outlook: SpendingOutlook
    let reserve: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var sections: [(title: LocalizedStringResource, value: Int, symbol: String, color: Color)] {
        [
            ("使った", outlook.spent, "checkmark.circle.fill", Theme.inkSecondary),
            ("固定費", outlook.plannedFixedTotal, "calendar", Theme.color(for: .utilities)),
            ("残す", reserve, "lock.fill", Theme.color(for: .cafe)),
            ("使える", max(0, (outlook.freeToSpend ?? 0) - reserve), "wallet.bifold", Theme.accentFill)
        ]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let total = max(1, sections.reduce(0.0) { $0 + Double($1.value) })
                HStack(spacing: 2) {
                    ForEach(sections.indices, id: \.self) { index in
                        let item = sections[index]
                        if item.value > 0 {
                            Rectangle().fill(item.color)
                                .frame(width: max(0, (geometry.size.width - 6) * Double(item.value) / total))
                        }
                    }
                }.clipShape(.capsule)
            }.frame(height: 16).accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { legend }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) { legend }
                    VStack(alignment: .leading, spacing: 8) { legend }
                }
            }
        }
    }
    @ViewBuilder private var legend: some View {
        ForEach(sections.indices, id: \.self) { index in
            let item = sections[index]
            Label { Text(item.title) } icon: { Image(systemName: item.symbol).foregroundStyle(item.color) }
                .font(.caption)
                .accessibilityLabel(Text(item.title))
                .accessibilityValue(Text(verbatim: YenFormatter.string(from: item.value)))
        }
    }
}

struct PurchaseCoverageRing: View {
    let saved: Int
    let price: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var fraction: Double { min(1, max(0, Double(saved) / Double(max(1, price)))) }
    private var percent: Int { Int(fraction * 100) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 18))
        layout {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 10)
                Circle().trim(from: 0, to: fraction)
                    .stroke(Theme.accentFill, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: "bag").font(.system(size: 20))
                    Text("\(percent)%").font(.system(size: 18, weight: .semibold)).monospacedDigit()
                }
            }.frame(width: 86, height: 86).padding(5).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("欲しいものに回せる目安").font(.subheadline)
                Text(verbatim: YenFormatter.string(from: saved))
                    .font(.title.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                Text("買い物代の\(percent)%分").font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .snappy, value: saved)
    }
}

struct PurchaseHabitCard: View {
    let habit: PurchaseCheck.Habit
    let count: Int
    let change: @MainActor @Sendable (Int) -> Void
    private var symbol: String { habit.category == .cafe ? "cup.and.saucer.fill" : "ticket.fill" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2).foregroundStyle(Theme.color(for: habit.category))
                    .frame(width: 44, height: 44)
                    .background(Theme.color(for: habit.category).opacity(0.12), in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: habit.name).font(.headline)
                    Text("1回の目安 \(YenFormatter.string(from: habit.typicalAmount))")
                        .font(.caption).foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 5) {
                ForEach(0..<min(8, habit.remainingCount), id: \.self) { index in
                    Image(systemName: index < count ? "minus.circle.fill" : symbol)
                        .foregroundStyle(index < count ? Theme.ink : Theme.inkSecondary.opacity(0.4))
                        .font(.system(size: 18))
                }
                if habit.remainingCount > 8 { Text(verbatim: "…") }
            }.accessibilityHidden(true)
            Stepper(value: Binding(get: { count }, set: change), in: 0...habit.remainingCount) {
                Text("\(count)回見送る").font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel(Text(verbatim: habit.name))
            .accessibilityValue(Text("\(count)回見送る"))
            if count > 0 {
                Text("\(YenFormatter.string(from: count * habit.typicalAmount))分を組み替え")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(14)
        .background(Theme.background, in: .rect(cornerRadius: 16))
    }
}
