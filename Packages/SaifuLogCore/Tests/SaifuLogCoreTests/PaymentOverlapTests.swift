import Foundation
import Testing
@testable import SaifuLogCore

@Suite("Apple Pay の支払いとの重なり")
struct PaymentOverlapTests {
    typealias Amount = PaymentOverlap.Amount<String>

    static func amount(_ id: String, _ yen: Int, day: Int = 28, hour: Int = 12, minute: Int = 0) -> Amount {
        Amount(id: id, amount: yen, spentAt: Fixture.date(2026, 9, day, hour: hour, minute: minute))
    }

    @Test("打った文は 1 件ずつの額と、同じ日に 2 件以上なら合計。1 件だけなら合計を作らない")
    func textSendAmounts() {
        let single = PaymentOverlap.sendAmounts([Self.amount("a", 450)], isReceipt: false, calendar: Fixture.calendar)
        #expect(single.items == [Self.amount("a", 450)])
        #expect(single.totals.isEmpty)

        let pair = PaymentOverlap.sendAmounts(
            [Self.amount("a", 1200), Self.amount("b", 300)], isReceipt: false, calendar: Fixture.calendar
        )
        #expect(pair.items.map(\.amount) == [1200, 300])
        // 合計の id はその日のいちばん後の記録（返事の最後の行に聞き返しを出す）。
        #expect(pair.totals == [Self.amount("b", 1500)])
    }

    @Test("日をまたぐ送信は日ごとに合計する（1 件だけの日は合計を作らない）")
    func textSendAcrossDays() {
        let send = PaymentOverlap.sendAmounts(
            [Self.amount("a", 1200, day: 27), Self.amount("b", 300), Self.amount("c", 500)],
            isReceipt: false, calendar: Fixture.calendar
        )
        #expect(send.items.map(\.id) == ["a", "b", "c"])
        #expect(send.totals == [Self.amount("c", 800)])
    }

    @Test("レシートは合計だけで比べる（1 行だけでも）")
    func receiptSendAmounts() {
        let lines = PaymentOverlap.sendAmounts(
            [Self.amount("a", 298), Self.amount("b", 1980), Self.amount("c", 182)], isReceipt: true, calendar: Fixture.calendar
        )
        #expect(lines.items.isEmpty)
        #expect(lines.totals == [Self.amount("c", 2460)])

        let single = PaymentOverlap.sendAmounts([Self.amount("a", 3280)], isReceipt: true, calendar: Fixture.calendar)
        #expect(single.totals == [Self.amount("a", 3280)])
    }

    @Test("金額と使った日が同じものだけを当てる")
    func pairsNeedSameAmountAndDay() {
        let payments = [
            Self.amount("p1", 450, day: 27, hour: 8),
            Self.amount("p2", 480, hour: 8),
            Self.amount("p3", 450, hour: 8),
        ]
        let pairs = PaymentOverlap.pairs([Self.amount("a", 450, hour: 9)], among: payments, calendar: Fixture.calendar)
        #expect(pairs == [PaymentOverlap.Pair(query: "a", candidate: "p3")])

        #expect(PaymentOverlap.pairs([Self.amount("b", 500)], among: payments, calendar: Fixture.calendar).isEmpty)
        // 日の区切りは暦のまま（日本時間の 0 時の前と後は別の日）。
        let lateNight = [Self.amount("p", 450, day: 27, hour: 23, minute: 59)]
        #expect(PaymentOverlap.pairs([Self.amount("c", 450, hour: 0, minute: 1)], among: lateNight, calendar: Fixture.calendar).isEmpty)
    }

    @Test("同じ日に候補がいくつもあれば時刻の近いものにし、1 つの候補は 1 つの額にだけ当てる")
    func pairsChooseClosestAndUseOnce() {
        let payments = [Self.amount("morning", 450, hour: 8), Self.amount("evening", 450, hour: 18)]

        let one = PaymentOverlap.pairs([Self.amount("a", 450, hour: 17)], among: payments, calendar: Fixture.calendar)
        #expect(one == [PaymentOverlap.Pair(query: "a", candidate: "evening")])

        let three = PaymentOverlap.pairs(
            [Self.amount("a", 450, hour: 17), Self.amount("b", 450, hour: 17), Self.amount("c", 450, hour: 17)],
            among: payments, calendar: Fixture.calendar
        )
        #expect(three == [
            PaymentOverlap.Pair(query: "a", candidate: "evening"),
            PaymentOverlap.Pair(query: "b", candidate: "morning"),
        ])
    }

    @Test("送信に重なる支払いは 1 件ずつの額で探し、当たらなければ合計で探す")
    func paymentPairsPreferItems() {
        let send = PaymentOverlap.sendAmounts(
            [Self.amount("lunch", 1200), Self.amount("coffee", 300)], isReceipt: false, calendar: Fixture.calendar
        )

        // 別々に払った（1 件ずつに当たる）なら、偶然同じ額の合計は聞かない。
        let separate = [Self.amount("p1", 1200, hour: 11), Self.amount("p2", 1500, hour: 11)]
        #expect(PaymentOverlap.paymentPairs(for: send, among: separate, calendar: Fixture.calendar) == PaymentOverlap.SendMatches(
            pairs: [PaymentOverlap.Pair(query: "lunch", candidate: "p1")], byTotal: false
        ))

        // まとめて払った（1 件ずつには当たらない）なら、合計で当てて、最後の行に聞き返す。
        let together = [Self.amount("p", 1500, hour: 11)]
        #expect(PaymentOverlap.paymentPairs(for: send, among: together, calendar: Fixture.calendar) == PaymentOverlap.SendMatches(
            pairs: [PaymentOverlap.Pair(query: "coffee", candidate: "p")], byTotal: true
        ))

        let none = PaymentOverlap.paymentPairs(for: send, among: [Amount](), calendar: Fixture.calendar)
        #expect(none.pairs.isEmpty)
        #expect(!none.byTotal)
    }
}
