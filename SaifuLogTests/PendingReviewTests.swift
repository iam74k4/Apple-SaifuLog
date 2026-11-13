import Foundation
import SaifuLogCore
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SaifuLog

@MainActor
@Suite(.serialized)
struct PendingReviewTests {
    typealias Fixture = HomeModelTests.Fixture

    /// カテゴリの聞き返しは保存先に残り、開き直した後も確認待ちの一覧から選べる。
    @Test func reviewSurvivesClosingAndReopeningTheDatabase() async throws {
        let directory = URL.temporaryDirectory.appending(path: "PendingReview-\(UUID().uuidString)")
        let url = directory.appending(path: "review.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Fixture()
        do {
            let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
            let model = HomeModel(store: EntryStore(context: container.mainContext), defaults: fixture.defaults,
                                  makeParser: { _, _ in RuleBasedParser(calendar: TestSupport.calendar, now: { TestSupport.now }) },
                                  makeCategoryRefiner: { nil }, now: { TestSupport.now }, announce: { _ in })
            model.draft = "ぽんかん 450"
            await model.send(calendar: TestSupport.calendar)?.value
            #expect(model.reviewItems.count == 1)
        }
        let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        let model = HomeModel(store: EntryStore(context: container.mainContext), defaults: fixture.defaults,
                              makeCategoryRefiner: { nil }, now: { TestSupport.now }, announce: { _ in })
        let item = try #require(model.reviewItems.first)
        model.chooseReviewCategory(.food, for: item.id)
        let entry = try #require(try container.mainContext.fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.category == .food)
        #expect(!entry.needsCategoryReview)
        #expect(model.reviewItems.isEmpty)
    }

    @Test(arguments: ["ja_JP", "en_US"], [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge])
    func reviewQueueFitsPhone(locale: String, size: UIContentSizeCategory) async throws {
        let fixture = try Fixture()
        await fixture.send("ぽんかん 450")
        await fixture.send("ガジェット 3990")
        let host = UIHostingController(rootView: EntryReviewQueueView(model: fixture.model).environment(\.locale, Locale(identifier: locale)))
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
        func scrolls(_ view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
        }
        let scroll = try #require(scrolls(host.view).first { $0.bounds.height > 300 })
        #expect(scroll.bounds.width <= 375)
        #expect(scroll.contentSize.width <= scroll.bounds.width + 1)
        if size == .large && locale == "ja_JP" {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            try #require(image.pngData()).write(to: URL.documentsDirectory.appending(path: "pending-reviews-ja.png"))
        }
    }
}
