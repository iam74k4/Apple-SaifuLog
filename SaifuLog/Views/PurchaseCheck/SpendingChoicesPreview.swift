import Foundation
import Observation
import SaifuLogCore
import SwiftUI

/// 初日でも買う前に触れる例。利用者の保存先や無料体験には一切触れず、本体と同じ計算を使う。
@MainActor
@Observable
final class SpendingChoicesPreviewModel {
    var count = 2
    let price = 6000
    let analysis: PurchaseCheck?
    var habit: PurchaseCheck.Habit? { analysis?.habits.first }
    var comparison: PurchaseCheck.Comparison? {
        analysis?.compare(amount: price, reserve: 10_000, reductions: habit.map { [$0.id: count] } ?? [:])
    }

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let records = (1...28).compactMap { offset -> PurchaseCheck.Record? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return .init(amount: 500, memo: String(localized: "コーヒー"), category: .cafe, spentAt: date)
        }
        let month = ReportPeriod.thisMonth.interval(now: now, calendar: calendar)!
        let outlook = SpendingOutlook(budget: 40_000, records: records.map {
            .init(amount: $0.amount, isIncome: false, spentAt: $0.spentAt, isRecurring: false)
        }, rules: [], now: now, month: month, calendar: calendar)!
        analysis = PurchaseCheck(outlook: outlook, records: records, now: now, calendar: calendar)
    }
}

struct SpendingChoicesPreview: View {
    @State private var model = SpendingChoicesPreviewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("サンプルで体験・購入不要", systemImage: "hand.tap")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            Text("コーヒーを何回、欲しいものへ？").font(.title3.bold())
            if let result = model.comparison {
                PurchaseCoverageRing(saved: result.adjustment, price: model.price)
                HStack(spacing: 7) {
                    ForEach(0..<6) { index in
                        Image(systemName: index < model.count ? "bag.fill" : "cup.and.saucer.fill")
                            .foregroundStyle(index < model.count ? Theme.accentFill : Theme.color(for: .cafe).opacity(0.5))
                            .font(.system(size: 22))
                    }
                }.accessibilityHidden(true)
                Stepper(value: $model.count, in: 0...6) { Text("\(model.count)回見送る") }
                    .accessibilityIdentifier("spending-preview-count")
                Text("1回500円・欲しいもの6,000円の例")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
                Text("月末の余裕を比較").font(.subheadline.weight(.semibold))
                PurchaseComparisonBars(rows: [
                    .init(title: "そのまま買う", amount: result.projectedWithPurchase ?? 0, symbol: "bag"),
                    .init(title: "組み替えて買う", amount: result.projectedWithAdjustment ?? 0, symbol: "arrow.triangle.branch")
                ])
            }
            Text("サンプルの月末の余裕です。あなたの記録・予算・無料体験は変わりません。")
                .font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 20))
    }
}
