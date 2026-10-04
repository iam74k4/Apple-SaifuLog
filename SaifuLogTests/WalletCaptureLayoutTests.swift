import Foundation
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

@MainActor
@Suite(.serialized)
struct WalletCaptureLayoutTests {
    @Test(arguments: ["ja_JP", "en_US"], [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge])
    func setupFitsNarrowPhone(locale: String, size: UIContentSizeCategory) async throws {
        let inbox = PaymentCaptureAppTests.temporaryInbox()
        try inbox.append(amount: 450, merchant: "Cafe", paidAt: TestSupport.now)
        let host = UIHostingController(rootView: NavigationStack {
            WalletCaptureView(model: WalletCaptureModel(inbox: inbox))
        }.environment(\.locale, Locale(identifier: locale)))
        host.traitOverrides.preferredContentSizeCategory = size
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        let scroll = try #require(Self.scrollViews(in: host.view).first { $0.bounds.height > 200 })
        #expect(scroll.bounds.width <= 375)
        #expect(scroll.contentSize.width <= scroll.bounds.width + 1)
        #expect(scroll.contentSize.height > 0)
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }
}
