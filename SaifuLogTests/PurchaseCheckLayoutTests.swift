import Foundation
import SaifuLogCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

@MainActor
@Suite(.serialized)
struct PurchaseCheckLayoutTests {
    @Test(arguments: ["ja_JP", "en_US"], [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge])
    func chartsStayInsidePhoneWidth(locale: String, size: UIContentSizeCategory) async throws {
        let context = try TestSupport.makeContext()
        let purchases = await TestSupport.purchases([PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)])
        let model = PurchaseCheckModel(context: context, purchases: purchases, calendar: TestSupport.calendar, now: { TestSupport.now })
        try BudgetStore(context: context).setAmounts([.total: 50_000])
        for day in 1...28 {
            context.insert(TestSupport.entry(amount: 500, category: .cafe, memo: "いつものコーヒー", spentAt: TestSupport.calendar.date(byAdding: .day, value: -day, to: TestSupport.now)!))
        }
        try context.save()
        model.amountText = "999,999,999,999"
        model.reload()
        if let habit = model.analysis?.habits.first { model.setReduction(1, for: habit) }
        let root = PurchaseCheckView(model: model)
            .environment(\.calendar, TestSupport.calendar)
            .environment(\.locale, Locale(identifier: locale))
        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = size
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400))
        window.layoutIfNeeded()
        let scroll = try #require(Self.scrollViews(in: host.view).first { $0.bounds.height > 300 })
        #expect(scroll.bounds.width <= 375)
        #expect(scroll.contentSize.width <= scroll.bounds.width + 1, "大きい文字で図が画面を横にはみ出しています")
        #expect(scroll.contentSize.height > 0)
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}
