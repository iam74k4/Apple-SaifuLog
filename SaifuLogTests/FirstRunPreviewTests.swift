import Foundation
import SaifuLogCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

@MainActor
@Suite(.serialized)
struct FirstRunPreviewTests {
    @Test func examplesDoNotStartTrialOrCreateRecords() throws {
        let fixture = try HomeModelTests.Fixture()
        let onboarding = OnboardingModel(budgetStore: BudgetStore(context: fixture.context), defaults: fixture.defaults,
                                          makeWalletCapture: { WalletCaptureModel(inbox: fixture.paymentInbox) })
        onboarding.previewsRecordedPayment = true
        let preview = SpendingChoicesPreviewModel()
        preview.count = 0
        let original = try #require(preview.comparison)
        preview.count = 6
        let changed = try #require(preview.comparison)
        #expect(changed.adjustment == 3000)
        #expect(original.withPurchase == changed.withPurchase)
        #expect(changed.projectedWithAdjustment == original.projectedWithPurchase! + 3000)
        #expect(try fixture.entries().isEmpty)
        #expect(fixture.purchases.status == .free)
        #expect(!onboarding.isCompleted)
        #expect(fixture.paymentInbox.pending().isEmpty)
    }

    @Test func paymentGuideCanBeSkippedAndDoesNotClaimConnection() throws {
        let fixture = try HomeModelTests.Fixture()
        let model = OnboardingModel(budgetStore: BudgetStore(context: fixture.context), defaults: fixture.defaults,
                                     makeWalletCapture: { WalletCaptureModel(inbox: fixture.paymentInbox) })
        model.showPaymentGuide()
        #expect(model.hasOpenedPaymentGuide)
        #expect(model.walletCapture?.lastReceivedAt == nil)
        #expect(!model.isCompleted)
        model.walletCapture = nil
        model.start()
        #expect(model.showsBudgetSetup)
        model.skipBudgetSetup()
        #expect(model.isCompleted)
    }

    @Test(arguments: ["ja_JP", "en_US"], [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge])
    func firstRunAndPaidPreviewFitPhone(locale: String, size: UIContentSizeCategory) async throws {
        let fixture = try HomeModelTests.Fixture()
        let onboarding = OnboardingModel(budgetStore: BudgetStore(context: fixture.context), defaults: fixture.defaults, aiStatus: { .available })
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let views: [(String, AnyView)] = [
            ("welcome", AnyView(OnboardingView(model: onboarding))),
            ("premium", AnyView(PremiumSheet(model: PremiumSheetModel(purchases: fixture.purchases))))
        ]
        for (name, view) in views {
            let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: locale)))
            host.traitOverrides.preferredContentSizeCategory = size
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            host.view.frame = window.bounds
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            window.layoutIfNeeded()
            func scrolls(_ view: UIView) -> [UIScrollView] {
                (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
            }
            let scroll = try #require(scrolls(host.view).first { $0.bounds.height > 250 })
            // SwiftUI のピクセル丸め（3倍表示では1/3pt）だけ許容する。画面外への拡張は見逃さない。
            #expect(scroll.bounds.width <= 375 + 1 / max(1, window.traitCollection.displayScale))
            #expect(scroll.contentSize.width <= scroll.bounds.width + 1)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let suffix = size == .large ? "normal" : "ax5"
            try #require(image.pngData()).write(to: URL.documentsDirectory.appending(path: "first-run-\(name)-\(locale)-\(suffix).png"))
        }
    }
}
