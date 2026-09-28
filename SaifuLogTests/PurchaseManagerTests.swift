import Foundation
import Observation
import os
import SaifuLogCore
import StoreKit
import Testing
@testable import SaifuLog

/// プレミアムの状態と購入・復元の扱い（PurchaseManager）のうち、StoreKit を使わずに確かめられるもの。
/// 購入の事実の読み込みと復元の同期を差し替える。StoreKit の購入の流れは `StoreKitPurchaseTests`。
@MainActor
struct PurchaseManagerTests {
    @Test func statusIsFreeBeforeLoading() async {
        let manager = await TestSupport.purchases([PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)], load: false)

        #expect(!manager.hasLoadedPurchases)
        #expect(manager.status == .free)

        await manager.refreshPurchases()

        #expect(manager.hasLoadedPurchases)
        #expect(manager.status == .premium(.purchased))
    }

    /// SKTestSession ではファミリー共有の購入を作れないので、購入の事実を差し替えて確かめる。
    @Test func familySharedPremium() async {
        let manager = await TestSupport.purchases([
            PremiumPurchase(product: .premium, ownership: .familyShared, purchaseDate: TestSupport.date(2026, 9, 1)),
        ])

        #expect(manager.status == .premium(.familyShared))
        #expect(manager.status.unlocksPremium)
    }

    /// 体験の残りは読むたびに今の時刻で決める（体験は時間で終わる）。
    @Test func trialStatusFollowsClock() async {
        var now = TestSupport.now
        let start = TestSupport.now
        let manager = await TestSupport.purchases([PremiumPurchase(product: .trial14, purchaseDate: start)], now: { now })

        #expect(manager.status == .trial(daysRemaining: 14, endsAt: start.addingTimeInterval(TrialPeriod.duration)))

        now = start.addingTimeInterval(TrialPeriod.duration - 1)
        manager.clockDidChange()
        #expect(manager.status == .trial(daysRemaining: 1, endsAt: start.addingTimeInterval(TrialPeriod.duration)))

        now = start.addingTimeInterval(TrialPeriod.duration)
        manager.clockDidChange()
        #expect(manager.status == .trialEnded(endedAt: start.addingTimeInterval(TrialPeriod.duration)))
    }

    /// 失効（返金・ファミリー共有の取り消し）が届いたら、端末の記録の側がまだ古くても、すぐにプレミアムでなくする。
    @Test func revokedUpdateOverridesStaleEntitlement() async {
        let purchase = PremiumPurchase(product: .premium, ownership: .familyShared, purchaseDate: TestSupport.date(2026, 9, 1))
        let manager = await TestSupport.purchases([purchase])
        #expect(manager.status == .premium(.familyShared))

        var revoked = purchase
        revoked.revocationDate = TestSupport.date(2026, 9, 27)
        await manager.refreshPurchases(applying: VerifiedPurchase(transactionID: 0, purchase: revoked))

        #expect(manager.status == .free)
        #expect(manager.purchases.count == 1)
    }

    // MARK: - 失効した体験

    /// `Transaction.currentEntitlements` は返金されたものを返さないので、失効した体験は購入の履歴から足す。足さないと、
    /// 体験の返金の後の起動で「体験していない無料」に戻り、体験をやり直せてしまう。
    @Test func revokedTrialFromHistoryKeepsTrialEnded() {
        let revokedAt = TestSupport.date(2026, 9, 3)
        let trial = VerifiedPurchase(
            transactionID: 1,
            purchase: PremiumPurchase(product: .trial14, purchaseDate: TestSupport.date(2026, 9, 1), revocationDate: revokedAt)
        )

        let merged = PurchaseManager.mergingRevokedTrials(entitlements: [], history: [trial])

        #expect(merged == [trial])
        let status = PremiumStatus(purchases: merged.map(\.purchase), now: TestSupport.now)
        #expect(status == .trialEnded(endedAt: revokedAt))
        #expect(!status.canStartTrial)
    }

    /// 足すのは失効した体験だけで、同じ Transaction を二度数えない。失効したプレミアムは足さない（数えないので要らない）。
    @Test func mergingAddsOnlyRevokedTrialsOnce() {
        let premium = VerifiedPurchase(transactionID: 5, purchase: PremiumPurchase(product: .premium, purchaseDate: TestSupport.now))
        let revokedPremium = VerifiedPurchase(
            transactionID: 7,
            purchase: PremiumPurchase(product: .premium, purchaseDate: TestSupport.date(2026, 9, 1), revocationDate: TestSupport.date(2026, 9, 2))
        )
        let revokedTrial = VerifiedPurchase(
            transactionID: 8,
            purchase: PremiumPurchase(product: .trial14, purchaseDate: TestSupport.date(2026, 8, 1), revocationDate: TestSupport.date(2026, 8, 2))
        )

        let merged = PurchaseManager.mergingRevokedTrials(
            entitlements: [premium],
            history: [premium, revokedPremium, revokedTrial, revokedTrial]
        )

        #expect(merged == [premium, revokedTrial])
    }

    // MARK: - 体験の残りの日数が減る瞬間

    /// 残りの日数は購入の時刻から 24 時間ごとに減る（0 時ではない）。画面を開いたままでもその瞬間に描き直させ、次の瞬間を
    /// 待ち直す。
    @Test func trialRedrawsWhenDaysRemainingDrops() async {
        let start = TestSupport.now
        let end = start.addingTimeInterval(TrialPeriod.duration)
        let clock = ManualClock(now: start.addingTimeInterval(12 * 60 * 60))
        let manager = Self.manager(purchases: [PremiumPurchase(product: .trial14, purchaseDate: start)], clock: clock)
        defer { manager.stop(); clock.releaseAll() }

        await manager.refreshPurchases()
        #expect(await Self.waitUntil { clock.requests.count == 1 })
        #expect(clock.requests == [start.addingTimeInterval(TrialPeriod.secondsPerDay)])
        #expect(manager.status == .trial(daysRemaining: 14, endsAt: end))

        let redrawn = Self.observeStatus(of: manager)
        clock.advance(to: start.addingTimeInterval(TrialPeriod.secondsPerDay))

        #expect(await Self.waitUntil { redrawn.withLock { $0 } })
        #expect(manager.status == .trial(daysRemaining: 13, endsAt: end))
        #expect(await Self.waitUntil { clock.requests.count == 2 })
        #expect(clock.requests.last == start.addingTimeInterval(2 * TrialPeriod.secondsPerDay))
    }

    /// 残り 1 日なら終わる瞬間に起き、体験の終わりを出させる。終わった後は待たない。
    @Test func trialRedrawsWhenItEnds() async {
        let start = TestSupport.now
        let end = start.addingTimeInterval(TrialPeriod.duration)
        let clock = ManualClock(now: end.addingTimeInterval(-60 * 60))
        let manager = Self.manager(purchases: [PremiumPurchase(product: .trial14, purchaseDate: start)], clock: clock)
        defer { manager.stop(); clock.releaseAll() }

        await manager.refreshPurchases()
        #expect(await Self.waitUntil { clock.requests.count == 1 })
        #expect(clock.requests == [end])
        #expect(manager.status == .trial(daysRemaining: 1, endsAt: end))

        let redrawn = Self.observeStatus(of: manager)
        clock.advance(to: end)

        #expect(await Self.waitUntil { redrawn.withLock { $0 } })
        #expect(manager.status == .trialEnded(endedAt: end))
        for _ in 0..<20 { await Task.yield() }
        #expect(clock.requests.count == 1)
    }

    /// 体験中でなければ、時間がたつだけでは状態が変わらないので待たない。
    @Test(arguments: [
        [PremiumPurchase](),
        [PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)],
        [PremiumPurchase(product: .trial14, purchaseDate: TestSupport.date(2026, 8, 1))],
    ])
    func noWakeOutsideTrial(purchases: [PremiumPurchase]) async {
        let clock = ManualClock(now: TestSupport.now)
        let manager = Self.manager(purchases: purchases, clock: clock)
        defer { manager.stop(); clock.releaseAll() }

        await manager.refreshPurchases()
        for _ in 0..<20 { await Task.yield() }

        #expect(clock.requests.isEmpty)
    }

    /// 体験中にプレミアムを買ったら、体験の待ちを取り消す（起きても描き直させない）。
    @Test func purchaseDuringTrialCancelsWake() async {
        let start = TestSupport.now
        let clock = ManualClock(now: start)
        let manager = Self.manager(purchases: [PremiumPurchase(product: .trial14, purchaseDate: start)], clock: clock)
        defer { manager.stop(); clock.releaseAll() }
        await manager.refreshPurchases()
        #expect(await Self.waitUntil { clock.requests.count == 1 })

        await manager.refreshPurchases(
            applying: VerifiedPurchase(transactionID: 99, purchase: PremiumPurchase(product: .premium, purchaseDate: start))
        )
        #expect(manager.status == .premium(.purchased))
        let redrawn = Self.observeStatus(of: manager)
        clock.advance(to: start.addingTimeInterval(TrialPeriod.secondsPerDay))
        for _ in 0..<20 { await Task.yield() }

        #expect(!redrawn.withLock { $0 })
        #expect(clock.requests.count == 1)
    }

    /// 前面に戻ったとき・時計を合わせ直したとき（`clockDidChange`）は、今の時刻で次に起きる瞬間を決め直す。
    @Test func clockChangeReschedulesWake() async {
        let start = TestSupport.now
        let clock = ManualClock(now: start)
        let manager = Self.manager(purchases: [PremiumPurchase(product: .trial14, purchaseDate: start)], clock: clock)
        defer { manager.stop(); clock.releaseAll() }
        await manager.refreshPurchases()
        #expect(await Self.waitUntil { clock.requests.count == 1 })

        // 裏にいる間に 5 日半たった（待ちは起きていない）。
        clock.now = start.addingTimeInterval(5.5 * TrialPeriod.secondsPerDay)
        manager.clockDidChange()

        #expect(await Self.waitUntil { clock.requests.count == 2 })
        #expect(clock.requests.last == start.addingTimeInterval(6 * TrialPeriod.secondsPerDay))
        #expect(manager.status == .trial(daysRemaining: 9, endsAt: start.addingTimeInterval(TrialPeriod.duration)))
    }

    /// 前の読み直しが後から終わっても、後から始めた読み直しの結果を上書きしない。
    @Test func staleRefreshDoesNotOverwriteNewerOne() async {
        let (gate, open) = AsyncStream<Void>.makeStream()
        var calls = 0
        let premium = VerifiedPurchase(transactionID: 1, purchase: PremiumPurchase(product: .premium, purchaseDate: TestSupport.now))
        let manager = PurchaseManager(
            now: { TestSupport.now },
            loadPurchases: {
                calls += 1
                if calls == 1 {
                    // 1 回目（古い読み直し）は、2 回目が終わるまで待たせてから、古い（購入の無い）記録を返す。
                    for await _ in gate { break }
                    return []
                }
                return [premium]
            },
            loadProducts: { _ in [] },
            sync: {}
        )

        let stale = Task { await manager.refreshPurchases() }
        while calls < 1 { await Task.yield() }
        await manager.refreshPurchases()
        #expect(manager.status == .premium(.purchased))
        open.yield()
        open.finish()
        await stale.value

        #expect(manager.status == .premium(.purchased))
    }

    // MARK: - 商品

    @Test func productsFailWhenPremiumIsMissing() async {
        let manager = await TestSupport.purchases()

        await manager.loadProductsIfNeeded()

        #expect(manager.productsState == .failed)
        #expect(manager.products.isEmpty)
    }

    @Test func productsFailWhenLoadingThrows() async {
        let manager = PurchaseManager(
            loadPurchases: { [] },
            loadProducts: { _ in throw StoreKitError.networkError(URLError(.notConnectedToInternet)) },
            sync: {}
        )

        await manager.loadProductsIfNeeded()

        #expect(manager.productsState == .failed)
    }

    /// 商品を読めていなければ、購入の手続きに進まない。
    @Test func purchaseWithoutProductFails() async {
        let manager = await TestSupport.purchases()
        var called = false

        let outcome = await manager.purchase(.premium) { _ in
            called = true
            return .userCancelled
        }

        #expect(outcome == .failed(.productUnavailable))
        #expect(!called)
        #expect(!manager.isPurchasing)
    }

    // MARK: - 復元

    @Test func restoreFindsPremium() async {
        var synced = false
        var records: [VerifiedPurchase] = []
        let manager = PurchaseManager(
            loadPurchases: { records },
            loadProducts: { _ in [] },
            sync: {
                synced = true
                // 同期で、ほかの端末で買ったプレミアムが届いた。
                records = [VerifiedPurchase(transactionID: 3, purchase: PremiumPurchase(product: .premium, purchaseDate: TestSupport.now))]
            }
        )

        let outcome = await manager.restore()

        #expect(synced)
        #expect(outcome == .restored)
        #expect(manager.status == .premium(.purchased))
        #expect(!manager.isRestoring)
    }

    /// 体験の記録だけが見つかっても、プレミアムの復元ではない。
    @Test func restoreWithoutPremium() async {
        let manager = await TestSupport.purchases([TestSupport.trial(startedDaysAgo: 3)])

        #expect(await manager.restore() == .nothingToRestore)
        #expect(manager.status.unlocksPremium)
    }

    @Test(arguments: [
        (StoreKitError.networkError(URLError(.notConnectedToInternet)) as any Error, RestoreOutcome.failed(.network)),
        (StoreKitError.userCancelled, .cancelled),
        (StoreKitError.unknown, .failed(.unknown)),
    ])
    func restoreFailure(error: any Error, expected: RestoreOutcome) async {
        let manager = await TestSupport.purchases(sync: { throw error })

        #expect(await manager.restore() == expected)
        #expect(!manager.isRestoring)
    }

    /// 復元の途中は、もう 1 回の復元も購入も受け付けない。
    @Test func restoreIsNotReentrant() async {
        let (gate, open) = AsyncStream<Void>.makeStream()
        let manager = await TestSupport.purchases(sync: { for await _ in gate { break } })

        let first = Task { await manager.restore() }
        while !manager.isRestoring { await Task.yield() }

        #expect(await manager.restore() == .busy)
        #expect(await manager.purchase(.premium) == .busy)
        open.yield()
        open.finish()
        #expect(await first.value == .nothingToRestore)
    }

    // MARK: - 手助け

    /// 購入の事実と時計を決めた PurchaseManager（まだ読んでいない）。
    static func manager(purchases: [PremiumPurchase], clock: ManualClock) -> PurchaseManager {
        let verified = purchases.enumerated().map { VerifiedPurchase(transactionID: UInt64($0.offset), purchase: $0.element) }
        return PurchaseManager(
            now: { clock.now },
            loadPurchases: { verified },
            loadProducts: { _ in [] },
            sync: {},
            sleepUntil: { try await clock.sleep(until: $0) }
        )
    }

    /// 状態を出している画面が描き直されるか（`status` の観察が変化を知らせたか）。
    static func observeStatus(of manager: PurchaseManager) -> OSAllocatedUnfairLock<Bool> {
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = manager.status
        } onChange: {
            changed.withLock { $0 = true }
        }
        return changed
    }

    /// 条件を満たすまで待つ。
    static func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    // MARK: - 失敗の分け方

    @Test(arguments: [
        (StoreKitError.networkError(URLError(.timedOut)) as any Error, PurchaseFailure.network),
        (URLError(.notConnectedToInternet), .network),
        (StoreKitError.notAvailableInStorefront, .productUnavailable),
        (Product.PurchaseError.productUnavailable, .productUnavailable),
        (Product.PurchaseError.purchaseNotAllowed, .notAllowed),
        (StoreKitError.userCancelled, .cancelled),
        (VerificationResult<Transaction>.VerificationError.invalidSignature, .unverified),
        (StoreKitError.unknown, .unknown),
        (Product.PurchaseError.ineligibleForOffer, .unknown),
        (CocoaError(.fileReadUnknown), .unknown),
    ])
    func failureKinds(error: any Error, expected: PurchaseFailure) {
        #expect(PurchaseFailure(error) == expected)
    }
}

/// 体験の残りの日数が減る瞬間に起きるかを確かめる時計。起きる瞬間を覚え、`advance(to:)` で進めるまで待たせる。
@MainActor
final class ManualClock {
    var now: Date
    /// 待つように頼まれた瞬間（頼まれた順）。
    private(set) var requests: [Date] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(now: Date) {
        self.now = now
    }

    /// その瞬間まで待つ（`advance(to:)` か `releaseAll()` まで）。取り消されていたら、起きた後に投げる。
    func sleep(until date: Date) async throws {
        requests.append(date)
        await withCheckedContinuation { waiters.append($0) }
        try Task.checkCancellation()
    }

    /// 時計を進め、待っているものをすべて起こす。
    func advance(to date: Date) {
        now = date
        releaseAll()
    }

    /// 待っているものをすべて起こす（テストの後片づけ。起こさないまま捨てると、待ちが漏れる）。
    func releaseAll() {
        let resumed = waiters
        waiters = []
        for waiter in resumed {
            waiter.resume()
        }
    }
}
