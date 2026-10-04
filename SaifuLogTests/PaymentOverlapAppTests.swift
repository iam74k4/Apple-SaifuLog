import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// Apple Pay の支払いの記録と、同じ買い物を打った・レシートで記録したものとの重なりの聞き返し（`HomeModel.paymentOverlaps`・
/// `removeOverlappingPayment`・`keepOverlappingPayment`）。固定の日時は 2026-09-28 12:00（日本時間）。
@MainActor
@Suite(.serialized)
struct PaymentOverlapAppTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 受け箱に支払いを置き、記録にする（払ってからアプリを開いたとき）。
    @discardableResult
    static func pay(_ fixture: Fixture, _ amount: Int, merchant: String = "STARBUCKS", at paidAt: Date) throws -> Entry {
        try fixture.paymentInbox.append(amount: amount, merchant: merchant, paidAt: paidAt)
        return try #require(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).first)
    }

    static func walletEntries(_ fixture: Fixture) throws -> [Entry] {
        try fixture.entries().filter { $0.source == .wallet }
    }

    // MARK: - 払った後に打った・レシートで記録した

    /// 前に記録した支払いと同じ日・同じ額を打つと、その行の下に聞き、消すと支払いの記録だけを消して「取り消す」を引っ込める。
    @Test func typedRecordAsksAboutEarlierPayment() async throws {
        let fixture = try Fixture()
        let payment = try Self.pay(fixture, 450, at: TestSupport.date(2026, 9, 28, hour: 8, minute: 3))

        await fixture.send("コーヒー 450")

        let typed = try #require(fixture.model.justRecorded.first)
        let question = try #require(fixture.model.paymentOverlaps[typed.persistentModelID])
        #expect(question.kind == .earlierPayment(total: nil))
        #expect(question.paymentID == payment.persistentModelID)
        #expect(question.counterpart.hasPrefix("STARBUCKS ¥450"))
        #expect(fixture.announcements.last == "記録しました: カフェ ¥450。Apple Pay の支払いと同じか選べます")

        fixture.model.removeOverlappingPayment(for: typed.persistentModelID)

        #expect(try Self.walletEntries(fixture).isEmpty)
        #expect(try fixture.entries().map(\.memo) == ["コーヒー"])
        #expect(fixture.model.paymentOverlaps.isEmpty)
        // 取り消すと、この買い物の記録が 1 つも残らなくなるので、「取り消す」を引っ込める。
        #expect(!fixture.model.canUndo)
        #expect(fixture.announcements.last == "Apple Pay の記録を消しました: STARBUCKS ¥450")
    }

    /// 「別の支払い」なら、どちらも残して聞き返しだけをやめる（「取り消す」は残す）。
    @Test func keepsBothWhenDifferent() async throws {
        let fixture = try Fixture()
        try Self.pay(fixture, 450, at: TestSupport.date(2026, 9, 28, hour: 8))
        await fixture.send("コーヒー 450")
        let typed = try #require(fixture.model.justRecorded.first)

        fixture.model.keepOverlappingPayment(for: typed.persistentModelID)

        #expect(try fixture.entries().count == 2)
        #expect(fixture.model.paymentOverlaps.isEmpty)
        #expect(fixture.model.canUndo)
        #expect(fixture.announcements.last == "どちらの記録も残しました")
    }

    /// まとめて払った買い物を 1 行で打つと、合計で当てて、最後の行の下に合計を添えて聞く。
    @Test func jointPaymentMatchesTotal() async throws {
        let fixture = try Fixture()
        let payment = try Self.pay(fixture, 1500, merchant: "カフェ・ド・パリ", at: TestSupport.date(2026, 9, 28, hour: 11))

        await fixture.send("ランチ 1200 コーヒー 300")

        let recorded = fixture.model.justRecorded
        #expect(recorded.map(\.amount) == [1200, 300])
        let last = try #require(recorded.last)
        #expect(Array(fixture.model.paymentOverlaps.keys) == [last.persistentModelID])
        let question = try #require(fixture.model.paymentOverlaps[last.persistentModelID])
        #expect(question.kind == .earlierPayment(total: 1500))
        #expect(question.paymentID == payment.persistentModelID)
    }

    /// Apple Pay で払った買い物のレシートを読み取ると、合計で当てて聞き、消すと内訳だけが残る。
    @Test func receiptTotalAsksAboutEarlierPayment() async throws {
        let fixture = try Fixture()
        // レシートは 2026-09-27 18:32、合計 ¥496（`HomeModelReceiptTests.receiptText`）。
        let payment = try Self.pay(fixture, 496, merchant: "イオン 渋谷店", at: TestSupport.date(2026, 9, 27, hour: 18, minute: 33))

        let result = try await HomeModelReceiptTests.read(fixture)
        result.requestRecord()

        let receipt = fixture.model.justRecorded
        #expect(receipt.map(\.memo) == ["牛乳", "ティッシュ"])
        // 合計で当てたので、最後の行（ティッシュ）の下に聞く。
        let last = try #require(receipt.last).persistentModelID
        let question = try #require(fixture.model.paymentOverlaps[last])
        #expect(question.kind == .earlierPayment(total: 496))
        #expect(question.paymentID == payment.persistentModelID)
        #expect(question.counterpart.hasPrefix("イオン ¥496"))
        #expect(fixture.announcements.last?.hasSuffix("Apple Pay の支払いと同じか選べます") == true)

        fixture.model.removeOverlappingPayment(for: last)

        #expect(try Self.walletEntries(fixture).isEmpty)
        #expect(try fixture.entries().map(\.amount).reduce(0, +) == 496)
        #expect(!fixture.model.canUndo)
    }

    /// 使った日か金額が違えば聞かない。
    @Test func differentDayOrAmountDoesNotAsk() async throws {
        let fixture = try Fixture()
        try Self.pay(fixture, 450, at: TestSupport.date(2026, 9, 27, hour: 20))

        await fixture.send("コーヒー 450")
        #expect(fixture.model.paymentOverlaps.isEmpty)

        try Self.pay(fixture, 480, at: TestSupport.date(2026, 9, 28, hour: 8))
        await fixture.send("コーヒー 450")
        #expect(fixture.model.paymentOverlaps.isEmpty)
        #expect(fixture.announcements.last == "記録しました: カフェ ¥450")
    }

    // MARK: - 打った後に支払いが届いた

    /// 払う前に打った買い物は、支払いを記録したときに支払いの行の下で聞き、消すとその支払いの記録を消す。
    @Test func paymentAfterTypedRecordAsks() async throws {
        let fixture = try Fixture()
        await fixture.send("ランチ 1200")

        let payment = try Self.pay(fixture, 1200, merchant: "サイゼリヤ", at: TestSupport.date(2026, 9, 28, hour: 12, minute: 30))

        let question = try #require(fixture.model.paymentOverlaps[payment.persistentModelID])
        #expect(question.kind == .earlierRecord)
        #expect(question.paymentID == payment.persistentModelID)
        #expect(question.counterpart == "ランチ ¥1,200")
        #expect(fixture.announcements.last?.hasSuffix("前の記録と同じか選べます") == true)

        fixture.model.removeOverlappingPayment(for: payment.persistentModelID)

        #expect(try Self.walletEntries(fixture).isEmpty)
        #expect(try fixture.entries().map(\.memo) == ["ランチ"])
        #expect(fixture.model.paymentOverlaps.isEmpty)
        // 取り消せる記録（いまの支払い）が無くなった。
        #expect(!fixture.model.canUndo)
    }

    /// 支払いが先に届いたレシートの合計とも比べる（レシートの要約を相手の文にする）。
    @Test func paymentAfterReceiptAsks() async throws {
        let fixture = try Fixture()
        let result = try await HomeModelReceiptTests.read(fixture)
        result.requestRecord()

        let payment = try Self.pay(fixture, 496, merchant: "イオン", at: TestSupport.date(2026, 9, 27, hour: 18, minute: 33))

        let question = try #require(fixture.model.paymentOverlaps[payment.persistentModelID])
        #expect(question.kind == .earlierRecord)
        #expect(question.counterpart.hasPrefix("レシート:"))
    }

    // MARK: - 聞き返しをやめるとき

    /// 次を送っても、確認待ちから重複を解決できる。
    @Test func nextSendKeepsUnresolvedQuestion() async throws {
        let fixture = try Fixture()
        try Self.pay(fixture, 450, at: TestSupport.date(2026, 9, 28, hour: 8))
        await fixture.send("コーヒー 450")
        #expect(!fixture.model.paymentOverlaps.isEmpty)

        await fixture.send("パン 280")

        #expect(fixture.model.paymentOverlaps.count == 1)
        #expect(try fixture.entries().count == 3)
    }

    /// 聞き返している支払いを長押しで消したら、聞き返しもやめる。
    @Test func deletingPaymentClearsQuestion() async throws {
        let fixture = try Fixture()
        let payment = try Self.pay(fixture, 450, at: TestSupport.date(2026, 9, 28, hour: 8))
        await fixture.send("コーヒー 450")
        #expect(!fixture.model.paymentOverlaps.isEmpty)

        fixture.model.requestDelete(payment)
        fixture.model.delete(try #require(fixture.model.pendingDeletion))

        #expect(fixture.model.paymentOverlaps.isEmpty)
        // いま打った記録の「取り消す」は残す（前の記録を消しただけ）。
        #expect(fixture.model.canUndo)
    }

    /// ほかの端末（iCloud）で支払いが先に消えていたら、消すを選んでも何もせず、聞き返しだけをやめる。
    @Test func removingAlreadyDeletedPaymentOnlyClearsQuestion() async throws {
        let fixture = try Fixture()
        let payment = try Self.pay(fixture, 450, at: TestSupport.date(2026, 9, 28, hour: 8))
        await fixture.send("コーヒー 450")
        let typed = try #require(fixture.model.justRecorded.first)
        try EntryStore(context: fixture.context).delete([payment])

        fixture.model.removeOverlappingPayment(for: typed.persistentModelID)

        #expect(fixture.model.paymentOverlaps.isEmpty)
        #expect(try fixture.entries().map(\.memo) == ["コーヒー"])
        #expect(fixture.model.storeFailure == nil)
    }

    /// 支払いの記録を消せなければ、聞き返しを残して知らせる（もう一度選べるように）。
    @Test func failedRemovalKeepsQuestion() async throws {
        let fixture = try Fixture()
        try Self.pay(fixture, 450, at: TestSupport.date(2026, 9, 28, hour: 8))
        await fixture.send("コーヒー 450")
        let typed = try #require(fixture.model.justRecorded.first)
        fixture.failsSave = true

        fixture.model.removeOverlappingPayment(for: typed.persistentModelID)

        #expect(fixture.model.storeFailure == .delete)
        #expect(fixture.model.paymentOverlaps[typed.persistentModelID] != nil)
        #expect(try Self.walletEntries(fixture).count == 1)
        #expect(fixture.model.canUndo)
    }
}
