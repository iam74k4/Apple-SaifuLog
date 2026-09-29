import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// 無料で使える回数の読み書き（QuotaStore）。使い捨ての設定の領域と、固定の日時（2026-09-28 12:00、日本時間）で確かめる。
@MainActor
struct QuotaStoreTests {
    @MainActor
    final class Fixture {
        let suiteName = "QuotaStoreTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var now = TestSupport.now

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }

        func makeStore() -> QuotaStore {
            QuotaStore(defaults: defaults, now: { [unowned self] in now })
        }
    }

    @Test func startsWithFullAllowance() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()

        #expect(store.allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar) == .limited(remaining: 5, limit: 5))
        #expect(store.allowance(for: .question, status: .free, calendar: TestSupport.calendar) == .limited(remaining: 10, limit: 10))
    }

    /// 使った回数は設定に残り、アプリを開き直しても（新しい QuotaStore でも）同じ。機能ごとに別に数える。
    @Test func usesArePersistedPerFeature() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()

        for _ in 0..<5 {
            #expect(store.recordUse(of: .receiptScan, status: .free, calendar: TestSupport.calendar))
        }
        #expect(!store.recordUse(of: .receiptScan, status: .free, calendar: TestSupport.calendar))
        #expect(store.recordUse(of: .question, status: .free, calendar: TestSupport.calendar))

        let reopened = fixture.makeStore()
        #expect(reopened.allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar) == .limited(remaining: 0, limit: 5))
        #expect(reopened.allowance(for: .question, status: .free, calendar: TestSupport.calendar) == .limited(remaining: 9, limit: 10))
        #expect(fixture.defaults.data(forKey: "quota.receiptScan") != nil)
        #expect(fixture.defaults.data(forKey: "quota.question") != nil)
    }

    @Test func resetsWhenMonthChanges() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.now = TestSupport.date(2026, 9, 30, hour: 23, minute: 59)
        let store = fixture.makeStore()
        for _ in 0..<5 {
            store.recordUse(of: .receiptScan, status: .free, calendar: TestSupport.calendar)
        }
        #expect(!store.allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar).canUse)

        fixture.now = TestSupport.date(2026, 10, 1)

        #expect(store.allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar) == .limited(remaining: 5, limit: 5))
        #expect(store.recordUse(of: .receiptScan, status: .free, calendar: TestSupport.calendar))
        #expect(fixture.makeStore().allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar)
            == .limited(remaining: 4, limit: 5))
    }

    /// プレミアムと体験中は無制限で、使っても数えない（設定にも書かない）。
    @Test func unlimitedWhenPremiumOrTrial() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()
        let trial = PremiumStatus.trial(daysRemaining: 3, endsAt: TestSupport.date(2026, 10, 1))

        for status in [PremiumStatus.premium(.purchased), .premium(.familyShared), trial] {
            #expect(store.allowance(for: .question, status: status, calendar: TestSupport.calendar) == .unlimited)
            #expect(store.recordUse(of: .question, status: status, calendar: TestSupport.calendar))
        }

        #expect(fixture.defaults.data(forKey: "quota.question") == nil)
        #expect(store.allowance(for: .question, status: .free, calendar: TestSupport.calendar) == .limited(remaining: 10, limit: 10))
    }

    /// 壊れた値が残っていても落ちず、使っていないものとして読む。
    @Test func brokenValueFallsBackToDefault() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(Data("not json".utf8), forKey: "quota.receiptScan")

        #expect(fixture.makeStore().allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar)
            == .limited(remaining: 5, limit: 5))
    }
    /// レシートは記録したときに数え、記録の直後に取り消したら戻す。数えたことも戻したことも設定に残る。
    @Test func useAndRefundArePersisted() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()

        let use = store.use(.receiptScan, status: .free, calendar: TestSupport.calendar)

        let month = QuotaMonth(containing: TestSupport.now, calendar: TestSupport.calendar)
        #expect(use == .counted(month))
        #expect(fixture.makeStore().allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar)
            == .limited(remaining: 4, limit: 5))

        store.refundUse(of: .receiptScan, month: month)

        #expect(store.allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar) == .limited(remaining: 5, limit: 5))
        #expect(fixture.makeStore().allowance(for: .receiptScan, status: .free, calendar: TestSupport.calendar)
            == .limited(remaining: 5, limit: 5))
    }

    /// プレミアムと体験中は数えず（設定にも書かず）、使い切っていたら数えない。
    @Test func useReportsUnlimitedAndLimit() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore()

        #expect(store.use(.receiptScan, status: .premium(.purchased), calendar: TestSupport.calendar) == .unlimited)
        #expect(fixture.defaults.data(forKey: "quota.receiptScan") == nil)
        for _ in 0..<5 {
            store.use(.receiptScan, status: .free, calendar: TestSupport.calendar)
        }
        #expect(store.use(.receiptScan, status: .free, calendar: TestSupport.calendar) == .limitReached)
    }
}
