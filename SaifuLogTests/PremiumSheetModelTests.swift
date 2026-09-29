import Foundation
import SaifuLogCore
import StoreKit
import Testing
@testable import SaifuLog

/// プレミアムのシートの状態と結果の知らせ方（PremiumSheetModel）。購入の事実と復元の同期を差し替えて確かめる。
@MainActor
struct PremiumSheetModelTests {
    final class Announcements {
        var texts: [String] = []
    }

    static func model(_ manager: PurchaseManager, announcements: Announcements = Announcements()) -> PremiumSheetModel {
        PremiumSheetModel(purchases: manager, announce: { announcements.texts.append($0) })
    }

    /// 体験のボタンは、まだ体験していない無料のときだけ出す。
    @Test(arguments: [
        ([PremiumPurchase](), true),
        ([TestSupport.trial(startedDaysAgo: 3)], false),
        ([TestSupport.trial(startedDaysAgo: 20)], false),
        ([PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)], false),
    ])
    func showsTrialOnlyBeforeTrying(records: [PremiumPurchase], expected: Bool) async {
        let model = Self.model(await TestSupport.purchases(records))

        #expect(model.showsTrial == expected)
    }

    /// 価格を読めていなければ、買うボタンも体験のボタンも押せない（金額をアプリに書かない）。
    @Test func buttonsAreDisabledUntilProductsLoad() async {
        let model = Self.model(await TestSupport.purchases())

        await model.loadProducts()

        #expect(model.premiumPrice == nil)
        #expect(!model.canPurchase)
        #expect(!model.canStartTrial)
        #expect(model.purchases.productsState == .failed)
    }

    @Test func purchasedAnnouncesWithoutAlert() async {
        let announcements = Announcements()
        let model = Self.model(await TestSupport.purchases(), announcements: announcements)

        model.finish(.purchased, kind: .premium)
        model.finish(.purchased, kind: .trial14)

        #expect(model.alert == nil)
        #expect(announcements.texts == [String(localized: "プレミアムを購入しました"), String(localized: "14日間の無料体験を始めました")])
    }

    @Test(arguments: [
        (PurchaseOutcome.pending, PurchaseAlert?.some(.pending)),
        (.cancelled, nil),
        (.busy, nil),
        (.failed(.network), .purchaseFailed(.network)),
        (.failed(.unverified), .purchaseFailed(.unverified)),
    ])
    func purchaseOutcomeAlerts(outcome: PurchaseOutcome, expected: PurchaseAlert?) async {
        let announcements = Announcements()
        let model = Self.model(await TestSupport.purchases(), announcements: announcements)

        model.finish(outcome, kind: .premium)

        #expect(model.alert == expected)
        #expect(announcements.texts.isEmpty)
    }

    /// 体験を終えた人に体験の手続きを、プレミアムを持っている人に購入の手続きを始めない。
    @Test func doesNotPurchaseWhenButtonIsHidden() async {
        var calls = 0
        let ended = Self.model(await TestSupport.purchases([TestSupport.trial(startedDaysAgo: 20)]))
        let owner = Self.model(await TestSupport.purchases([PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)]))

        await ended.startTrial { _ in
            calls += 1
            return .userCancelled
        }
        await owner.buyPremium { _ in
            calls += 1
            return .userCancelled
        }

        #expect(calls == 0)
        #expect(ended.alert == nil)
        #expect(owner.alert == nil)
    }

    @Test func restoreShowsResult() async {
        let model = Self.model(await TestSupport.purchases())

        await model.restore()

        #expect(model.alert == .nothingToRestore)
    }

    @Test func restoreFailureShowsAlert() async {
        let model = Self.model(await TestSupport.purchases(sync: { throw URLError(.notConnectedToInternet) }))

        await model.restore()

        #expect(model.alert == .restoreFailed(.network))
    }

    /// 利用者が Apple ID の確認をやめたら、何も知らせない。
    @Test func cancelledRestoreShowsNothing() async {
        let model = Self.model(await TestSupport.purchases(sync: { throw StoreKitError.userCancelled }))

        await model.restore()

        #expect(model.alert == nil)
    }

    /// 無料とプレミアムの違いの表で「近日」と書く機能。まだ出していない機能を、できるように書かない。
    /// 家計への質問とふりかえりの AI の一言は出したので「近日」を外した（出した機能を「近日」のままにしない）。
    @Test func comingSoonFeatures() {
        #expect(PremiumFeature.receiptScan.isComingSoon)
        #expect(!PremiumFeature.question.isComingSoon)
        #expect(!PremiumFeature.recapAI.isComingSoon)
        #expect(!PremiumFeature.categoryBudget.isComingSoon)
    }

    @Test func termsLinkPointsToAppleStandardEULA() {
        #expect(PremiumSheet.termsURL.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }
}
