import Foundation
import SaifuLogCore
import StoreKit
import StoreKitTest
import Testing
@testable import SaifuLog

/// テストのバンドルを見つけるための目印。
private final class StoreKitTestBundleToken {}

/// StoreKit の購入の流れ（PurchaseManager）を、StoreKit の設定ファイル（Config/SaifuLog.storekit）と SKTestSession で確かめる。
///
/// SKTestSession は端末（シミュレータ）の StoreKit の状態を 1 つだけ持つので、テストは 1 つずつ動かす（`.serialized`）。
/// ほかのテストは StoreKit を使わない（購入の事実を差し替える。`PurchaseManagerTests`）。
///
/// SKTestSession が使えないシミュレータでは飛ばす（`StoreKitTestEnvironment.isAvailable`）。iOS 26.3・26.4 のシミュレータは、
/// Xcode のデバッグの外（xcodebuild test）から SKTestSession の設定を渡せず（Apple の不具合）、本物の App Store の Sandbox に
/// つながって購入の確認を待ち続ける。飛ばさないと、CI が時間切れまで止まるため。iOS 26.2 のシミュレータで動くことを確かめた。
///
/// ただし `make test-storekit`（CI も）は REQUIRE_STOREKIT_TESTS=1 を渡し、そのときは飛ばさずに失敗させる
/// （`StoreKitTestEnvironment.isRequired`）。飛ばしただけでは結果が成功のままで、購入の流れが 1 つも確かめられないまま
/// CI が緑になるため。失敗は購入を試す前（SKTestSession を作るとき）に起こすので、Sandbox で待ち続けることはない。
@MainActor
@Suite(
    .serialized,
    .timeLimit(.minutes(1)),
    .enabled("SKTestSession が使えないシミュレータ（iOS 26.3・26.4 など）では飛ばす（REQUIRE_STOREKIT_TESTS=1 なら失敗にする）") {
        await StoreKitTestEnvironment.shouldRun
    }
)
struct StoreKitPurchaseTests {
    /// SKTestSession と PurchaseManager。テストごとに購入の記録を空にして始める。
    @MainActor
    final class Fixture {
        let session: SKTestSession
        let manager: PurchaseManager

        init(listens: Bool = false) async throws {
            session = try await StoreKitTestEnvironment.makeSession()
            // 購入の日時は StoreKit（実際の時刻）が決めるので、体験の判定も実際の時刻でする。
            manager = PurchaseManager(now: { .now })
            if listens { manager.start() }
            await manager.loadProductsIfNeeded()
        }

        /// テストの後片づけ。購読をやめ、購入の記録を空にする。
        func cleanUp() {
            manager.stop()
            session.clearTransactions()
        }

        /// SKTestSession の購入の記録のうち、その商品のもの。
        func transactions(of product: PremiumProduct) -> [SKTestTransaction] {
            session.allTransactions().filter { $0.productIdentifier == product.rawValue }
        }
    }

    /// 条件を満たすまで待つ（Transaction.updates から届くのを待つ）。
    static func waitUntil(timeout: Duration = .seconds(10), _ condition: @MainActor () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    // MARK: - 商品

    /// 価格は App Store の表示（日本の App Store では ¥1,800）をそのまま使い、アプリに金額を書かない。
    @Test func loadsProductsFromConfiguration() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }

        #expect(fixture.manager.productsState == .loaded)
        let premium = try #require(fixture.manager.products[.premium])
        let trial = try #require(fixture.manager.products[.trial14])
        #expect(premium.price == 1_800)
        #expect(premium.displayPrice == "¥1,800")
        #expect(premium.type == .nonConsumable)
        #expect(premium.isFamilyShareable)
        #expect(premium.displayName == "サイフログ プレミアム")
        #expect(trial.price == 0)
        #expect(trial.type == .nonConsumable)
        #expect(!trial.isFamilyShareable)
        #expect(trial.displayName == "14日間の無料体験")
    }

    @Test func productsLoadFailure() async throws {
        let session = try await StoreKitTestEnvironment.makeSession()
        defer { session.clearTransactions() }
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        let manager = PurchaseManager()

        await manager.loadProductsIfNeeded()

        #expect(manager.productsState == .failed)
        #expect(manager.products[.premium] == nil)
    }

    // MARK: - 購入

    @Test func purchaseUnlocksPremiumAndFinishesTransaction() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.manager.status == .free)

        let outcome = await fixture.manager.purchase(.premium)

        #expect(outcome == .purchased)
        #expect(fixture.manager.status == .premium(.purchased))
        #expect(!fixture.manager.isPurchasing)
        // Transaction を終えている（終えないと、起動のたびに届け直される）。
        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        #expect(unfinished == 0)
    }

    /// 体験（価格 0 の非消耗型）の購入日時から 14 日（経過時間）が体験。
    @Test func trialStartsFourteenDayTrial() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        #expect(fixture.manager.status.canStartTrial)

        #expect(await fixture.manager.purchase(.trial14) == .purchased)

        let purchaseDate = try #require(fixture.manager.purchases.first { $0.purchase.product == .trial14 }?.purchase.purchaseDate)
        #expect(fixture.manager.status == .trial(daysRemaining: 14, endsAt: purchaseDate.addingTimeInterval(TrialPeriod.duration)))
        #expect(fixture.manager.status.unlocksPremium)
        #expect(!fixture.manager.status.canStartTrial)
    }

    /// 15 日前に始めた体験は終わっている。やり直せない（体験のボタンは出さない）。
    @Test func trialStartedFifteenDaysAgoHasEnded() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let startedAt = Date.now.addingTimeInterval(-15 * TrialPeriod.secondsPerDay)
        try await fixture.session.buyProduct(identifier: PremiumProduct.trial14.rawValue, options: [.purchaseDate(startedAt)])

        await fixture.manager.refreshPurchases()

        guard case .trialEnded(let endedAt) = fixture.manager.status else {
            Issue.record("体験が終わっていない: \(fixture.manager.status)")
            return
        }
        #expect(abs(endedAt.timeIntervalSince(startedAt) - TrialPeriod.duration) < 1)
        #expect(!fixture.manager.status.canStartTrial)
        #expect(fixture.manager.status.canPurchase)
    }

    /// 利用者がやめたら何もしない。
    @Test func cancelledPurchaseDoesNothing() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)

        #expect(await fixture.manager.purchase(.premium) == .cancelled)
        await fixture.manager.refreshPurchases()
        #expect(fixture.manager.status == .free)
    }

    @Test func purchaseNotAllowed() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.session.setSimulatedError(.purchase(.purchaseNotAllowed), forAPI: .purchase)

        #expect(await fixture.manager.purchase(.premium) == .failed(.notAllowed))
        #expect(fixture.manager.status == .free)
    }

    /// 検証できない購入は受け入れない（プレミアムにしない）。
    @Test func unverifiedPurchaseIsRejected() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)

        let outcome = await fixture.manager.purchase(.premium)
        await fixture.manager.refreshPurchases()

        guard case .failed = outcome else {
            Issue.record("検証できない購入を受け入れた: \(outcome)")
            return
        }
        #expect(fixture.manager.status == .free)
    }

    /// 購入の途中は、もう 1 回の購入を受け付けない（二重の購入を防ぐ）。
    @Test func secondPurchaseWhilePurchasingIsIgnored() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        let (gate, open) = AsyncStream<Void>.makeStream()
        let manager = fixture.manager

        let first = Task {
            await manager.purchase(.premium) { product in
                for await _ in gate { break }
                return try await product.purchase()
            }
        }
        #expect(await Self.waitUntil { manager.isPurchasing })

        #expect(await manager.purchase(.premium) == .busy)
        #expect(await manager.purchase(.trial14) == .busy)
        #expect(await manager.restore() == .busy)
        open.yield()
        open.finish()

        #expect(await first.value == .purchased)
        #expect(fixture.transactions(of: .premium).count == 1)
        #expect(fixture.transactions(of: .trial14).isEmpty)
    }

    // MARK: - 承認待ち（Ask to Buy）

    /// 承認待ちは案内だけを返し、承認されたら Transaction.updates からプレミアムにする。
    @Test func askToBuyApprovalUnlocksPremium() async throws {
        let fixture = try await Fixture(listens: true)
        defer { fixture.cleanUp() }
        fixture.session.askToBuyEnabled = true

        #expect(await fixture.manager.purchase(.premium) == .pending)
        #expect(fixture.manager.status == .free)

        let pending = try #require(fixture.transactions(of: .premium).first { $0.pendingAskToBuyConfirmation })
        try fixture.session.approveAskToBuyTransaction(identifier: pending.identifier)

        #expect(await Self.waitUntil { fixture.manager.status == .premium(.purchased) })
    }

    @Test func askToBuyDeclinedStaysFree() async throws {
        let fixture = try await Fixture(listens: true)
        defer { fixture.cleanUp() }
        fixture.session.askToBuyEnabled = true

        #expect(await fixture.manager.purchase(.premium) == .pending)
        let pending = try #require(fixture.transactions(of: .premium).first { $0.pendingAskToBuyConfirmation })
        try fixture.session.declineAskToBuyTransaction(identifier: pending.identifier)
        try await Task.sleep(for: .milliseconds(500))
        await fixture.manager.refreshPurchases()

        #expect(fixture.manager.status == .free)
    }

    // MARK: - 返金・ほかの端末での購入

    /// 返金されたら、Transaction.updates から届いた時点でプレミアムでなくする。
    @Test func refundRevokesPremium() async throws {
        let fixture = try await Fixture(listens: true)
        defer { fixture.cleanUp() }
        #expect(await fixture.manager.purchase(.premium) == .purchased)
        let transactionID = try #require(fixture.manager.purchases.first { $0.purchase.product == .premium }?.transactionID)

        try fixture.session.refundTransaction(identifier: UInt(transactionID))

        #expect(await Self.waitUntil { fixture.manager.status == .free })
    }

    /// 体験中に買ったプレミアムを返金されたら、体験の残りに戻る。
    @Test func refundDuringTrialFallsBackToTrial() async throws {
        let fixture = try await Fixture(listens: true)
        defer { fixture.cleanUp() }
        #expect(await fixture.manager.purchase(.trial14) == .purchased)
        #expect(await fixture.manager.purchase(.premium) == .purchased)
        #expect(fixture.manager.status == .premium(.purchased))
        let transactionID = try #require(fixture.manager.purchases.first { $0.purchase.product == .premium }?.transactionID)

        try fixture.session.refundTransaction(identifier: UInt(transactionID))

        #expect(await Self.waitUntil {
            if case .trial = fixture.manager.status { return true }
            return false
        })
    }

    /// 体験の購入が返金されたら、起動し直しても（`Transaction.currentEntitlements` は返金されたものを返さない）体験の
    /// 終わりのままにし、体験をやり直させない（体験のボタンを出さない）。
    @Test func refundedTrialStaysEndedAfterRelaunch() async throws {
        let fixture = try await Fixture(listens: true)
        defer { fixture.cleanUp() }
        #expect(await fixture.manager.purchase(.trial14) == .purchased)
        let transactionID = try #require(fixture.manager.purchases.first { $0.purchase.product == .trial14 }?.transactionID)

        try fixture.session.refundTransaction(identifier: UInt(transactionID))
        #expect(await Self.waitUntil {
            if case .trialEnded = fixture.manager.status { return true }
            return false
        })

        // 起動し直したときと同じく、新しい PurchaseManager で端末の購入の記録から読み直す。
        let relaunched = PurchaseManager(now: { .now })
        await relaunched.refreshPurchases()
        guard case .trialEnded = relaunched.status else {
            Issue.record("返金された体験が、起動し直すと体験の終わりでなくなった: \(relaunched.status)")
            return
        }
        #expect(!relaunched.status.canStartTrial)
        #expect(relaunched.status.canPurchase)

        // 購入の復元の後も同じ。
        #expect(await relaunched.restore() == .nothingToRestore)
        guard case .trialEnded = relaunched.status else {
            Issue.record("返金された体験が、購入の復元の後に体験の終わりでなくなった: \(relaunched.status)")
            return
        }
    }

    /// アプリの外（ほかの端末など）で買ったプレミアムも、Transaction.updates から届いたら反映する。
    @Test func purchaseOutsideAppArrivesThroughUpdates() async throws {
        let fixture = try await Fixture(listens: true)
        defer { fixture.cleanUp() }

        try await fixture.session.buyProduct(identifier: PremiumProduct.premium.rawValue)

        #expect(await Self.waitUntil { fixture.manager.status == .premium(.purchased) })
    }

    // MARK: - 復元

    @Test func restoreLoadsPurchaseMadeElsewhere() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.session.buyProduct(identifier: PremiumProduct.premium.rawValue)

        #expect(await fixture.manager.restore() == .restored)
        #expect(fixture.manager.status == .premium(.purchased))
    }

    @Test func restoreWithNothingToRestore() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }

        #expect(await fixture.manager.restore() == .nothingToRestore)
        #expect(fixture.manager.status == .free)
    }

    @Test func restoreFailsOffline() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanUp() }
        try await fixture.session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .appStoreSync)

        #expect(await fixture.manager.restore() == .failed(.network))
    }
}

/// SKTestSession を作る。
enum StoreKitTestEnvironment {
    /// テストのバンドルに入れた StoreKit の設定ファイル（project.yml の SaifuLogTests の resources）。
    static var configurationURL: URL? {
        Bundle(for: StoreKitTestBundleToken.self).url(forResource: "SaifuLog", withExtension: "storekit")
    }

    /// 購入のテストを飛ばさずに動かすことを求められているか（`make test-storekit` と CI が REQUIRE_STOREKIT_TESTS=1 を渡す。
    /// xcodebuild は環境変数 TEST_RUNNER_REQUIRE_STOREKIT_TESTS の TEST_RUNNER_ を外してテストに渡す）。
    static var isRequired: Bool {
        ProcessInfo.processInfo.environment["REQUIRE_STOREKIT_TESTS"] == "1"
    }

    /// 購入のテストを動かすか。求められていれば、使えないシミュレータでも動かして失敗させる（`makeSession()`）。
    static var shouldRun: Bool {
        get async {
            if isRequired { return true }
            return await isAvailable
        }
    }

    /// SKTestSession がこのシミュレータで使えるか。
    ///
    /// 使えないシミュレータでは、SKTestSession を作れても設定を StoreKit に渡せず（ログに SKInternalErrorDomain Code=3 が出る）、
    /// 設定ファイルの App Store（JPN）を読み返せない。そのときは購入を試す前に飛ばす（本物の Sandbox で確認を待ち続けるため）。
    static var isAvailable: Bool {
        get async {
            guard let url = configurationURL, let session = try? SKTestSession(contentsOf: url) else { return false }
            return session.storefront == "JPN"
        }
    }

    /// 購入の記録と、前のテストで起こした失敗を消し、確認の画面を出さない SKTestSession。
    ///
    /// 起こした失敗は `resetToDefaultState()` で消す。`setSimulatedError(nil, forAPI:)` で消すと、iOS 26.2 のシミュレータでは
    /// 次の購入が「Server canceled the purchase」で失敗した（SKTestSession の不具合）ため、テストの中では nil を渡さない。
    ///
    /// 使えないシミュレータでは、購入を試す前に投げる（飛ばさずに動かすことを求められたとき。本物の Sandbox で購入の確認を
    /// 待ち続けないように）。
    static func makeSession() async throws -> SKTestSession {
        guard let url = configurationURL else { throw CocoaError(.fileNoSuchFile) }
        let session = try SKTestSession(contentsOf: url)
        // 使えるかは `isAvailable` と同じく、設定ファイルの App Store（JPN）を読み返せるかで見る。
        guard session.storefront == "JPN" else { throw Unavailable() }
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    /// SKTestSession がこのシミュレータで使えない。
    struct Unavailable: Error, CustomStringConvertible {
        var description: String {
            "SKTestSession がこのシミュレータで使えません（iOS 26.3・26.4 など）。make test-storekit の STOREKIT_TEST_OS の版のシミュレータで動かしてください。"
        }
    }
}
