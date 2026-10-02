import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

/// ふりかえりの AI の一言の状態（RecapRemarkModel）のうち、画面を通さずに確かめるもの。書いている途中で数字の文が替わったとき・
/// プレミアムでなくなったとき・覚えておく結果の数・購入の事実を読み終える前に書かせたとき。
/// 数字の文は、照合に使う行だけの短いもの（`facts(_:)`）にする。
@MainActor
struct RecapRemarkModelTests {
    static let premium = [PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)]

    /// 支出の合計が `thousands` × ¥1,000 の数字の文。
    nonisolated static func facts(_ thousands: Int) -> String {
        "支出の合計: \(YenFormatter.string(from: thousands * 1_000))（支出の記録 2件）"
    }

    /// `facts(thousands)` の数字だけで書いた一言（照合を通る）。
    nonisolated static func sentence(_ thousands: Int) -> String {
        "先週は\(YenFormatter.string(from: thousands * 1_000))でした。"
    }

    /// 数字の文ごとに違う一言を書く書き手（書き直した一言が、古い文のものか新しい文のものかを見分けるため）。
    static func echoingWriter() -> StubRemarkWriter {
        StubRemarkWriter { facts in
            try #require((1...100).first { Self.facts($0) == facts }.map(Self.sentence))
        }
    }

    // MARK: - 書いている途中で数字の文が替わったとき

    /// 古い文の一言が、新しい文の一言より先に書き終わっても出さない（新しい文を書いている間は、書いている印のまま）。
    @Test func staleRemarkIsNotShownWhileNewFactsAreBeingWritten() async throws {
        let purchases = await TestSupport.purchases(Self.premium)
        let oldStarted = Gate(), oldRelease = Gate(), newStarted = Gate(), newRelease = Gate()
        let writer = StubRemarkWriter { facts in
            if facts == Self.facts(3) {
                oldStarted.open()
                await oldRelease.wait()
                return Self.sentence(3)
            }
            newStarted.open()
            await newRelease.wait()
            return Self.sentence(4)
        }
        let model = RecapRemarkModel(purchases: purchases, makeWriter: { writer })

        let oldTask = try #require(model.update(facts: Self.facts(3)))
        await oldStarted.wait()
        #expect(model.state == .writing)

        let newTask = try #require(model.update(facts: Self.facts(4)))
        await newStarted.wait()
        oldRelease.open()
        await oldTask.value
        #expect(model.state == .writing)

        newRelease.open()
        await newTask.value
        #expect(model.state == .written(Self.sentence(4)))
    }

    /// 古い文の書き手が、新しい文の一言を出した後に失敗しても、新しい一言を消さない。取り消した後の失敗なので、AI の記録にも残さない。
    @Test func staleFailureDoesNotClearNewRemark() async throws {
        let purchases = await TestSupport.purchases(Self.premium)
        let oldStarted = Gate(), oldRelease = Gate()
        let writer = StubRemarkWriter { facts in
            if facts == Self.facts(3) {
                oldStarted.open()
                await oldRelease.wait()
                throw TestError()
            }
            return Self.sentence(4)
        }
        let log = AIFallbackLog()
        let model = RecapRemarkModel(purchases: purchases, makeWriter: { writer }, aiFallbackLog: log)

        let oldTask = try #require(model.update(facts: Self.facts(3)))
        await oldStarted.wait()
        await model.update(facts: Self.facts(4))?.value
        #expect(model.state == .written(Self.sentence(4)))

        oldRelease.open()
        await oldTask.value

        #expect(model.state == .written(Self.sentence(4)))
        #expect(log.snapshot == AIFallbackLog.Snapshot())
    }

    // MARK: - 書けなかったとき

    /// モデルが失敗したら一言を添えず（定型文だけ）、失敗を AI の記録に残す（利用者には知らせない）。
    @Test func failureIsRecordedWithoutRemark() async throws {
        let purchases = await TestSupport.purchases(Self.premium)
        let writer = StubRemarkWriter { _ in throw TestError() }
        let log = AIFallbackLog()
        let model = RecapRemarkModel(purchases: purchases, makeWriter: { writer }, aiFallbackLog: log)

        await model.update(facts: Self.facts(3))?.value

        #expect(model.state == .none)
        #expect(log.snapshot.fallbacks == [.recap: 1])
        #expect(log.snapshot.lastError?.feature == .recap)
        #expect(log.snapshot.lastError?.error.type == String(reflecting: TestError.self))
    }

    /// モデルが返らないまま止まっても、上限（アプリは `AITimeouts.recapRemark` の 8 秒。テストでは短くする）で書いている印をやめ、
    /// 一言を添えない（定型文だけ）。時間切れを AI の記録に残す。書けなかったときと同じく結果は覚えず、決め直したときにまた書かせる。
    @Test(.timeLimit(.minutes(1)))
    func timeoutShowsNoRemarkAndRetriesLater() async throws {
        let purchases = await TestSupport.purchases(Self.premium)
        let stuck = Gate()
        defer { stuck.open() }
        let writer = StubRemarkWriter { _ in
            // 取り消されても、門が開くまで返らない（取り消しに応じずに止まったモデルの代わり）。
            await stuck.wait()
            return Self.sentence(3)
        }
        let log = AIFallbackLog()
        let model = RecapRemarkModel(
            purchases: purchases, makeWriter: { writer }, aiFallbackLog: log, remarkTimeout: .milliseconds(200)
        )

        await model.update(facts: Self.facts(3))?.value

        #expect(model.state == .none)
        #expect(log.snapshot.fallbacks == [.recap: 1])
        #expect(log.snapshot.timeouts == [.recap: 1])
        #expect(log.snapshot.lastError == nil)

        stuck.open()
        await model.refresh()?.value

        #expect(model.state == .written(Self.sentence(3)))
        #expect(writer.calls.count == 2)
    }

    // MARK: - プレミアムの状態

    /// 体験が終わったら（プレミアムでなくなったら）、決め直したときに一言を外す。覚えていた一言も出さない。
    @Test func remarkIsRemovedWhenTrialEnds() async throws {
        let start = TestSupport.now.addingTimeInterval(-13 * TrialPeriod.secondsPerDay)
        var now = TestSupport.now
        let purchases = await TestSupport.purchases([PremiumPurchase(product: .trial14, purchaseDate: start)], now: { now })
        let writer = Self.echoingWriter()
        let model = RecapRemarkModel(purchases: purchases, makeWriter: { writer })
        await model.update(facts: Self.facts(3))?.value
        #expect(model.state == .written(Self.sentence(3)))

        now = start.addingTimeInterval(TrialPeriod.duration)
        purchases.clockDidChange()
        await model.refresh()?.value

        #expect(!purchases.status.unlocksPremium)
        #expect(model.state == .none)
        #expect(writer.calls.count == 1)
    }

    /// 購入の事実を読み終える前（起動した直後）に書かせても、読み終えてから決める（プレミアムなのに無料と見て一言を外さない）。
    @Test func waitsForPurchasesToLoadBeforeDeciding() async throws {
        let purchases = await TestSupport.purchases(Self.premium, load: false)
        let writer = Self.echoingWriter()
        let model = RecapRemarkModel(purchases: purchases, makeWriter: { writer })
        #expect(!purchases.hasLoadedPurchases)
        #expect(!purchases.status.unlocksPremium)

        await model.update(facts: Self.facts(3))?.value

        #expect(purchases.hasLoadedPurchases)
        #expect(model.state == .written(Self.sentence(3)))
    }

    /// 読み終えて無料だったら、書かせない。
    @Test func unloadedFreePurchasesWriteNothing() async throws {
        let purchases = await TestSupport.purchases(load: false)
        let writer = Self.echoingWriter()
        let model = RecapRemarkModel(purchases: purchases, makeWriter: { writer })

        await model.update(facts: Self.facts(3))?.value

        #expect(purchases.hasLoadedPurchases)
        #expect(model.state == .none)
        #expect(writer.calls.count == 0)
    }

    // MARK: - 覚えておく結果

    /// 覚えておく結果は `cacheLimit` 件まで。あふれたら古いものから忘れ、その文に戻ったときに書き直す。
    @Test func oldestResultIsForgottenBeyondCacheLimit() async throws {
        let purchases = await TestSupport.purchases(Self.premium)
        let writer = Self.echoingWriter()
        let model = RecapRemarkModel(purchases: purchases, makeWriter: { writer })
        let count = RecapRemarkModel.cacheLimit + 1
        for thousands in 1...count {
            await model.update(facts: Self.facts(thousands))?.value
        }
        #expect(writer.calls.count == count)

        // 2 番目に書いたものはまだ覚えているので、書き直さない。
        await model.update(facts: Self.facts(2))?.value
        #expect(model.state == .written(Self.sentence(2)))
        #expect(writer.calls.count == count)

        // 最初に書いたものは忘れたので、書き直す。
        await model.update(facts: Self.facts(1))?.value
        #expect(model.state == .written(Self.sentence(1)))
        #expect(writer.calls.count == count + 1)
    }
}
