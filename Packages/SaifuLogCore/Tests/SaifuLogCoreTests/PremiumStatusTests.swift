import Foundation
import Testing
@testable import SaifuLogCore

@Suite("プレミアムの状態")
struct PremiumStatusTests {
    static let day = TrialPeriod.secondsPerDay

    static func purchase(
        _ product: PremiumProduct, _ ownership: PremiumOwnership = .purchased, at date: Date = Fixture.now,
        revokedAt: Date? = nil
    ) -> PremiumPurchase {
        PremiumPurchase(product: product, ownership: ownership, purchaseDate: date, revocationDate: revokedAt)
    }

    /// 製品 ID は App Store Connect に登録した値。変えると買った人がプレミアムを使えなくなる。
    @Test("製品 ID は App Store Connect に登録した値のまま")
    func productIdentifiersAreStable() {
        #expect(PremiumProduct.premium.rawValue == "com.iam74k4.SaifuLog.premium")
        #expect(PremiumProduct.trial14.rawValue == "com.iam74k4.SaifuLog.trial14")
        #expect(PremiumProduct.allCases.count == 2)
    }

    @Test("購入の事実が無ければ無料で、体験を始められる")
    func freeWithoutPurchases() {
        let status = PremiumStatus(purchases: [], now: Fixture.now)

        #expect(status == .free)
        #expect(!status.unlocksPremium)
        #expect(status.canStartTrial)
        #expect(status.canPurchase)
    }

    @Test("自分で買ったプレミアム")
    func purchasedPremium() {
        let status = PremiumStatus(purchases: [Self.purchase(.premium)], now: Fixture.now)

        #expect(status == .premium(.purchased))
        #expect(status.unlocksPremium)
        #expect(!status.canStartTrial)
        #expect(!status.canPurchase)
    }

    @Test("ファミリー共有のプレミアム")
    func familySharedPremium() {
        let status = PremiumStatus(purchases: [Self.purchase(.premium, .familyShared)], now: Fixture.now)

        #expect(status == .premium(.familyShared))
        #expect(status.unlocksPremium)
    }

    /// 家族が共有をやめても使い続けられるのは、自分で買ったほう。
    @Test("自分で買ったものとファミリー共有の両方があれば、自分で買ったもの", arguments: [
        [PremiumOwnership.familyShared, .purchased],
        [.purchased, .familyShared],
    ])
    func purchasedWinsOverFamilyShared(order: [PremiumOwnership]) {
        let status = PremiumStatus(purchases: order.map { Self.purchase(.premium, $0) }, now: Fixture.now)

        #expect(status == .premium(.purchased))
    }

    @Test("返金で失効したプレミアムは数えない")
    func refundedPremiumIsNotPremium() {
        let status = PremiumStatus(
            purchases: [Self.purchase(.premium, at: Fixture.date(2026, 9, 1), revokedAt: Fixture.date(2026, 9, 20))],
            now: Fixture.now
        )

        #expect(status == .free)
    }

    @Test("ファミリー共有が取り消されたら、自分で買ったものが無ければプレミアムではなくなる")
    func revokedFamilySharingFallsBack() {
        let revoked = Self.purchase(.premium, .familyShared, at: Fixture.date(2026, 9, 1), revokedAt: Fixture.date(2026, 9, 27))

        #expect(PremiumStatus(purchases: [revoked], now: Fixture.now) == .free)
        #expect(PremiumStatus(purchases: [revoked, Self.purchase(.premium)], now: Fixture.now) == .premium(.purchased))
    }

    @Test("体験を始めた直後は、あと 14 日")
    func trialJustStarted() {
        let status = PremiumStatus(purchases: [Self.purchase(.trial14, at: Fixture.now)], now: Fixture.now)

        #expect(status == .trial(daysRemaining: 14, endsAt: Fixture.now.addingTimeInterval(14 * Self.day)))
        #expect(status.unlocksPremium)
        #expect(!status.canStartTrial)
        #expect(status.canPurchase)
    }

    /// 始まりは含み、終わりは含まない。
    @Test("体験の終わる瞬間の 1 秒前は体験中（あと 1 日）、終わる瞬間からは体験の終わり")
    func trialEndsAtExactInstant() {
        let start = Fixture.date(2026, 9, 14, hour: 21, minute: 30)
        let end = start.addingTimeInterval(14 * Self.day)
        let purchases = [Self.purchase(.trial14, at: start)]

        #expect(PremiumStatus(purchases: purchases, now: end.addingTimeInterval(-1)) == .trial(daysRemaining: 1, endsAt: end))
        #expect(PremiumStatus(purchases: purchases, now: end) == .trialEnded(endedAt: end))
        #expect(PremiumStatus(purchases: purchases, now: end.addingTimeInterval(1)) == .trialEnded(endedAt: end))
        #expect(!PremiumStatus(purchases: purchases, now: end).unlocksPremium)
        // 体験は 1 回だけ。終わった後は始められない。
        #expect(!PremiumStatus(purchases: purchases, now: end).canStartTrial)
        #expect(PremiumStatus(purchases: purchases, now: end).canPurchase)
    }

    @Test("体験中にプレミアムを買えば、体験より購入を採る")
    func premiumDuringTrial() {
        let status = PremiumStatus(
            purchases: [Self.purchase(.trial14, at: Fixture.date(2026, 9, 20)), Self.purchase(.premium)],
            now: Fixture.now
        )

        #expect(status == .premium(.purchased))
    }

    @Test("体験中に買ったプレミアムを返金したら、体験の残りに戻る")
    func refundDuringTrialFallsBackToTrial() {
        let start = Fixture.date(2026, 9, 20)
        let status = PremiumStatus(
            purchases: [
                Self.purchase(.trial14, at: start),
                Self.purchase(.premium, at: Fixture.date(2026, 9, 21), revokedAt: Fixture.date(2026, 9, 27)),
            ],
            now: Fixture.now
        )

        // 9/20 0:00 から 8 日半たち、残りは 5 日半（切り上げて 6 日）。
        #expect(status == .trial(daysRemaining: 6, endsAt: start.addingTimeInterval(14 * Self.day)))
    }

    @Test("体験が終わった後に買えばプレミアム")
    func premiumAfterTrialEnded() {
        let status = PremiumStatus(
            purchases: [Self.purchase(.trial14, at: Fixture.date(2026, 8, 1)), Self.purchase(.premium)],
            now: Fixture.now
        )

        #expect(status == .premium(.purchased))
    }

    /// 体験は 1 回だけで、失効してもやり直しにはしない。アプリは失効した体験の購入を `Transaction.all` から読んで渡す
    /// （`Transaction.currentEntitlements` は失効したものを返さない。`PurchaseManager.storedPurchases`）。
    @Test("体験の購入が失効したら、体験は終わったものとする")
    func revokedTrialEnds() {
        let start = Fixture.date(2026, 9, 20)
        let revokedAt = Fixture.date(2026, 9, 25)

        let status = PremiumStatus(purchases: [Self.purchase(.trial14, at: start, revokedAt: revokedAt)], now: Fixture.now)

        #expect(status == .trialEnded(endedAt: revokedAt))
        #expect(!status.canStartTrial)
    }

    @Test("体験の購入が 2 件あれば、最初に買った日時から数える")
    func earliestTrialWins() {
        let first = Fixture.date(2026, 9, 1)
        let status = PremiumStatus(
            purchases: [Self.purchase(.trial14, at: Fixture.date(2026, 9, 20)), Self.purchase(.trial14, at: first)],
            now: Fixture.now
        )

        #expect(status == .trialEnded(endedAt: first.addingTimeInterval(14 * Self.day)))
    }

    /// 失効した体験の後に体験をもう一度買っても（返金された非消耗型は買い直せる）、体験は始まらない。
    @Test("失効した体験の後に買い直した体験では、体験をやり直さない")
    func repurchasedTrialAfterRevocationStaysEnded() {
        let revokedAt = Fixture.date(2026, 9, 5)
        let status = PremiumStatus(
            purchases: [
                Self.purchase(.trial14, at: Fixture.date(2026, 9, 1), revokedAt: revokedAt),
                Self.purchase(.trial14, at: Fixture.date(2026, 9, 27)),
            ],
            now: Fixture.now
        )

        #expect(status == .trialEnded(endedAt: revokedAt))
        #expect(!status.unlocksPremium)
    }

    /// 時間がたつだけで変わるのは体験中だけ。ほかの状態は購入の事実が変わるまで変わらないので、起きる瞬間は無い。
    @Test("体験中でなければ、時間がたつだけで変わる瞬間は無い", arguments: [
        PremiumStatus.free,
        .trialEnded(endedAt: Fixture.now),
        .premium(.purchased),
        .premium(.familyShared),
    ])
    func noNextChangeOutsideTrial(status: PremiumStatus) {
        #expect(status.nextChange == nil)
    }

    /// 状態の次に変わる瞬間は、体験の期間の次に変わる瞬間と同じ。
    @Test("体験中の状態の次に変わる瞬間", arguments: TrialPeriodTests.remainingCases.map(\.elapsed))
    func nextChangeMatchesTrialPeriod(elapsed: TimeInterval) {
        let start = TrialPeriodTests.start
        let now = start.addingTimeInterval(elapsed)
        let status = PremiumStatus(purchases: [Self.purchase(.trial14, at: start)], now: now)

        #expect(status.nextChange == TrialPeriod(start: start).nextChange(after: now))
    }
}

@Suite("無料体験の期間")
struct TrialPeriodTests {
    static let day = TrialPeriod.secondsPerDay
    static let start = Fixture.date(2026, 9, 28, hour: 12)

    @Test("長さは 14 × 24 時間")
    func durationIsFourteenDays() {
        let period = TrialPeriod(start: Self.start)

        #expect(TrialPeriod.dayCount == 14)
        #expect(period.end.timeIntervalSince(period.start) == 14 * 24 * 60 * 60)
    }

    /// 始まりからの経過時間と、画面に出す残りの日数。
    static let remainingCases: [(elapsed: TimeInterval, days: Int)] = [
        (0, 14),
        (1, 14),
        (day - 1, 14),
        (day, 13),
        (day + 1, 13),
        (7 * day, 7),
        (13 * day, 1),
        (14 * day - 1, 1),
        (14 * day, 0),
        (20 * day, 0),
    ]

    /// 1 日単位で切り上げる。
    @Test("残りの日数は切り上げ", arguments: remainingCases)
    func daysRemainingRoundsUp(elapsed: TimeInterval, expected: Int) {
        let period = TrialPeriod(start: Self.start)

        #expect(period.daysRemaining(at: Self.start.addingTimeInterval(elapsed)) == expected)
    }

    /// 始まりからの経過時間と、残りの日数が次に減る瞬間（始まりからの経過時間。nil は終わった後）。
    static let nextChangeCases: [(elapsed: TimeInterval, next: TimeInterval?)] = [
        (0, day),
        (1, day),
        (day - 1, day),
        (day, 2 * day),
        (7 * day + 1, 8 * day),
        (13 * day, 14 * day),
        (14 * day - 1, 14 * day),
        (14 * day, nil),
        (20 * day, nil),
    ]

    /// 残りの日数は購入の時刻から 24 時間ごとに減り、残り 1 日の次は終わる瞬間。
    @Test("残りの日数が次に減る瞬間", arguments: nextChangeCases)
    func nextChangeFollowsPurchaseTime(elapsed: TimeInterval, next: TimeInterval?) {
        let period = TrialPeriod(start: Self.start)

        #expect(period.nextChange(after: Self.start.addingTimeInterval(elapsed)) == next.map { Self.start.addingTimeInterval($0) })
    }

    /// 次に変わる瞬間の 1 秒前までは同じ日数で、その瞬間に 1 減る（残り 1 日なら体験が終わる）。
    @Test("次に変わる瞬間の直前は同じ日数、その瞬間に 1 減る", arguments: remainingCases.map(\.elapsed))
    func nextChangeIsExactBoundary(elapsed: TimeInterval) throws {
        let period = TrialPeriod(start: Self.start)
        let now = Self.start.addingTimeInterval(elapsed)
        let days = period.daysRemaining(at: now)
        guard let next = period.nextChange(after: now) else {
            #expect(days == 0)
            #expect(!period.isActive(at: now))
            return
        }

        #expect(next > now)
        #expect(period.daysRemaining(at: next.addingTimeInterval(-1)) == days)
        #expect(period.daysRemaining(at: next) == days - 1)
        #expect(period.isActive(at: next) == (days > 1))
    }

    @Test("端末の時計が購入日時より前にずれていても、体験中で 14 日を超えない")
    func clockBeforeStart() {
        let period = TrialPeriod(start: Self.start)
        let before = Self.start.addingTimeInterval(-3 * Self.day)

        #expect(period.isActive(at: before))
        #expect(period.daysRemaining(at: before) == 14)
        // 14 日から 13 日に減るのは、購入日時から 24 時間後（ずれた時計の 24 時間後ではない）。
        #expect(period.nextChange(after: before) == Self.start.addingTimeInterval(Self.day))
    }

    /// 経過時間で数えるので、夏時間の切り替わり（米国 2026-11-01 に 25 時間の日）をまたいでも 14 × 24 時間。
    /// 暦の日付で数えると、終わる時刻が 1 時間ずれる。
    @Test("夏時間の切り替わりをまたいでも、長さは変わらない")
    func daylightSavingDoesNotChangeLength() throws {
        let newYork = Fixture.calendar(firstWeekday: 1, timeZone: "America/New_York")
        let start = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9)))
        let period = TrialPeriod(start: start)

        #expect(period.end.timeIntervalSince(start) == 14 * Self.day)
        // 暦で 14 日後の同じ時刻は、夏時間が終わるので 1 時間長い。
        let calendarEnd = try #require(newYork.date(byAdding: .day, value: 14, to: start))
        #expect(calendarEnd.timeIntervalSince(start) == 14 * Self.day + 3_600)
        #expect(period.end < calendarEnd)
    }

    /// 期間は瞬間で決まり、暦も時間帯も使わない。端末の時間帯を変えても、終わる瞬間と残りの日数は同じ。
    @Test("時間帯を変えても、終わる瞬間と残りの日数は同じ")
    func timeZoneChangeDoesNotMatter() {
        let status = PremiumStatus(
            purchases: [PremiumPurchase(product: .trial14, purchaseDate: Self.start)],
            now: Self.start.addingTimeInterval(10 * Self.day)
        )

        #expect(status == .trial(daysRemaining: 4, endsAt: Self.start.addingTimeInterval(14 * Self.day)))
        // 終わる瞬間は、東京では 10/12 12:00、ホノルルでは 10/11 17:00。表示の時刻が違うだけで、同じ瞬間。
        let tokyo = Fixture.calendar(firstWeekday: 1, timeZone: "Asia/Tokyo")
        let honolulu = Fixture.calendar(firstWeekday: 1, timeZone: "Pacific/Honolulu")
        let end = TrialPeriod(start: Self.start).end
        #expect(tokyo.dateComponents([.month, .day, .hour], from: end) == DateComponents(month: 10, day: 12, hour: 12))
        #expect(honolulu.dateComponents([.month, .day, .hour], from: end) == DateComponents(month: 10, day: 11, hour: 17))
    }
}
