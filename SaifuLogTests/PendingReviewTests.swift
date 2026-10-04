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

    private func reopened(_ fixture: Fixture, classifier: CategoryRefiner? = nil) -> HomeModel {
        HomeModel(store: EntryStore(context: fixture.context), paymentInbox: fixture.paymentInbox,
                  purchases: fixture.purchases, defaults: fixture.defaults, makeCategoryRefiner: { classifier },
                  now: { TestSupport.now }, announce: { _ in })
    }

    @Test func interruptedClassificationResumesWithoutAnotherPayment() async throws {
        let fixture = try Fixture()
        let gate = PaymentCategoryAutomationTests.Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, onFallback: nil)
        let entry = try PaymentOverlapAppTests.pay(fixture, 3990, merchant: "ユニクロ", at: TestSupport.now)
        try await gate.waitUntilAsked()
        fixture.model.cancelPaymentClassification()
        await gate.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(entry.needsPaymentClassification)
        let model = reopened(fixture, classifier: CategoryRefiner(classifier: PaymentCategoryAutomationTests.Classifier(), onFallback: nil))
        #expect(model.reviewItems.count == 1)
        #expect(model.importCapturedPayments(calendar: TestSupport.calendar).isEmpty)
        await model.waitForPaymentClassification()
        #expect(entry.category == .daily)
        #expect(!entry.needsPaymentClassification && !entry.needsCategoryReview)
        #expect(model.reviewItems.isEmpty)
        #expect(try fixture.entries().count == 1)
    }

    @Test func oldCancelledAnswerCannotRemoveNewClassificationState() async throws {
        let fixture = try Fixture()
        let old = PaymentCategoryAutomationTests.Gate()
        let current = PaymentCategoryAutomationTests.Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: old, onFallback: nil)
        let entry = try PaymentOverlapAppTests.pay(fixture, 3990, merchant: "ユニクロ", at: TestSupport.now)
        try await old.waitUntilAsked()
        fixture.model.cancelPaymentClassification()
        fixture.categoryRefiner = CategoryRefiner(classifier: current, onFallback: nil)
        fixture.model.importCapturedPayments(calendar: TestSupport.calendar)
        try await current.waitUntilAsked()
        await old.finish()
        #expect(fixture.model.classifyingPaymentIDs.contains(entry.persistentModelID))
        await current.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(entry.category == .daily)
        #expect(fixture.pendingWrites.count == 0)
    }

    @Test func duplicateSurvivesNextSendAndReopenUntilResolved() async throws {
        let fixture = try Fixture()
        await fixture.send("コーヒー 450")
        let payment = try PaymentOverlapAppTests.pay(fixture, 450, at: TestSupport.now)
        await fixture.send("電車 200")
        #expect(fixture.model.paymentOverlaps.count == 1)
        let model = reopened(fixture)
        #expect(model.reviewItems.count == 1)
        model.removeOverlappingPayment(for: payment.persistentModelID)
        #expect(try fixture.entries().map(\.amount).reduce(0, +) == 650)
        #expect(model.reviewItems.isEmpty)
        #expect(reopened(fixture).reviewItems.isEmpty)
    }

    @Test func keepingSeparatePaymentsIsSavedAndSaveFailureKeepsQuestion() async throws {
        let fixture = try Fixture()
        await fixture.send("コーヒー 450")
        let payment = try PaymentOverlapAppTests.pay(fixture, 450, at: TestSupport.now)
        fixture.failsSave = true
        fixture.model.keepOverlappingPayment(for: payment.persistentModelID)
        #expect(fixture.model.storeFailure == .reviewChoice)
        #expect(fixture.model.reviewItems.count == 1)
        #expect(reopened(fixture).reviewItems.count == 1)
        fixture.failsSave = false
        fixture.model.keepOverlappingPayment(for: payment.persistentModelID)
        #expect(reopened(fixture).reviewItems.isEmpty)
        #expect(try fixture.entries().count == 2)
    }

    @Test func changedCounterpartCannotDeletePaymentUsingStaleQuestion() async throws {
        let fixture = try Fixture()
        await fixture.send("コーヒー 450")
        let typed = try #require(fixture.model.justRecorded.first)
        let payment = try PaymentOverlapAppTests.pay(fixture, 450, at: TestSupport.now)
        var edits = EntryEdits(typed)
        edits.amount = 500
        try EntryStore(context: fixture.context).update(typed, with: edits)
        fixture.model.removeOverlappingPayment(for: payment.persistentModelID)
        #expect(try fixture.entries().count == 2)
        #expect(fixture.model.reviewItems.isEmpty)
    }

    @Test func deletedMemberOfTotalCannotDeletePaymentUsingStaleQuestion() async throws {
        let fixture = try Fixture()
        let payment = try PaymentOverlapAppTests.pay(fixture, 1500, at: TestSupport.now)
        await fixture.send("ランチ 1200 コーヒー 300")
        let entries = fixture.model.justRecorded
        let anchor = try #require(entries.last).persistentModelID
        #expect(fixture.model.paymentOverlaps.count == 1)
        try EntryStore(context: fixture.context).delete([try #require(entries.first)])
        fixture.model.removeOverlappingPayment(for: anchor)
        #expect(try fixture.entries().contains { $0.persistentModelID == payment.persistentModelID })
        #expect(fixture.model.paymentOverlaps.isEmpty)
    }

    @Test func explicitOtherIsResolvedEvenThoughCategoryValueDoesNotChange() throws {
        let fixture = try Fixture()
        let entry = try PaymentOverlapAppTests.pay(fixture, 3990, merchant: "ユニクロ", at: TestSupport.now)
        fixture.model.chooseCategory(.other, for: entry)
        #expect(!entry.needsCategoryReview && !entry.needsPaymentClassification)
        #expect(reopened(fixture).reviewItems.isEmpty)
    }

    @Test func categoryConfirmedElsewhereIsNotRewrittenByLateAI() async throws {
        let fixture = try Fixture()
        let gate = PaymentCategoryAutomationTests.Gate()
        fixture.categoryRefiner = CategoryRefiner(classifier: gate, onFallback: nil)
        let entry = try PaymentOverlapAppTests.pay(fixture, 3990, merchant: "ユニクロ", at: TestSupport.now)
        try await gate.waitUntilAsked()
        try EntryStore(context: fixture.context).update(entry, with: EntryEdits(entry))
        await gate.finish()
        await fixture.model.waitForPaymentClassification()
        #expect(entry.category == .other)
        #expect(fixture.model.reviewItems.isEmpty)
    }

    @Test func reviewSurvivesClosingAndReopeningTheDatabase() async throws {
        let directory = URL.temporaryDirectory.appending(path: "PendingReview-\(UUID().uuidString)")
        let url = directory.appending(path: "review.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try Fixture()
        do {
            let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
            let model = HomeModel(store: EntryStore(context: container.mainContext), paymentInbox: fixture.paymentInbox,
                                  defaults: fixture.defaults,
                                  makeParser: { _, _ in RuleBasedParser(calendar: TestSupport.calendar, now: { TestSupport.now }) },
                                  makeCategoryRefiner: { nil }, now: { TestSupport.now }, announce: { _ in })
            model.draft = "コーヒー 450"
            await model.send(calendar: TestSupport.calendar)?.value
            try fixture.paymentInbox.append(amount: 450, merchant: "STARBUCKS", paidAt: TestSupport.now)
            model.importCapturedPayments(calendar: TestSupport.calendar)
            #expect(model.reviewItems.count == 1)
        }
        let container = try ModelContainerFactory.makeContainer(url: url, cloudKitDatabase: .none)
        let model = HomeModel(store: EntryStore(context: container.mainContext), paymentInbox: fixture.paymentInbox,
                              defaults: fixture.defaults, makeCategoryRefiner: { nil }, announce: { _ in })
        let item = try #require(model.reviewItems.first)
        model.removeOverlappingPayment(for: item.id)
        #expect(try container.mainContext.fetch(FetchDescriptor<Entry>()).map(\.amount) == [450])
    }

    @Test(arguments: ["ja_JP", "en_US"], [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge])
    func reviewQueueFitsPhone(locale: String, size: UIContentSizeCategory) async throws {
        let fixture = try Fixture()
        await fixture.send("コーヒー 450")
        try PaymentOverlapAppTests.pay(fixture, 450, at: TestSupport.now)
        try PaymentOverlapAppTests.pay(fixture, 3990, merchant: "ユニクロ", at: TestSupport.now)
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
