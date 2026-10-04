import AppIntents
import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// Apple Pay の支払いの自動記録（受け箱 `PaymentInbox`・ショートカットの操作 `RecordPaymentIntent`・ホームの取り込み
/// `HomeModel.importCapturedPayments`）。
@MainActor
@Suite(.serialized)
struct PaymentCaptureAppTests {
    typealias Fixture = HomeModelTests.Fixture

    static func temporaryInbox() -> PaymentInbox {
        PaymentInbox(directory: URL.temporaryDirectory.appending(path: "PaymentInbox-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    // MARK: - 受け箱

    /// 足した順に読め、記録にした分を消せる。空になったらファイルごと消す。
    @Test func inboxAppendsAndRemoves() throws {
        let inbox = Self.temporaryInbox()
        #expect(inbox.pending().isEmpty)

        let first = try inbox.append(amount: 450, merchant: "STARBUCKS", paidAt: TestSupport.now)
        let second = try inbox.append(amount: 980, merchant: "マツモトキヨシ", paidAt: TestSupport.now.addingTimeInterval(60))
        #expect(inbox.pending() == [first, second])

        try inbox.remove([first.id])
        #expect(inbox.pending() == [second])
        try inbox.remove([second.id])
        #expect(inbox.pending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: inbox.directory.appending(path: "pending.json").path))
    }

    // MARK: - ショートカットの操作

    @Test func unreadableInboxIsNeverReplacedOrRemoved() throws {
        let inbox = Self.temporaryInbox()
        try FileManager.default.createDirectory(at: inbox.directory, withIntermediateDirectories: true)
        let url = inbox.directory.appending(path: "pending.json")
        let damaged = Data("broken payment data".utf8)
        try damaged.write(to: url)
        #expect(throws: (any Error).self) { try inbox.readPending() }
        #expect(throws: (any Error).self) { try inbox.append(amount: 450, merchant: "Cafe", paidAt: TestSupport.now) }
        #expect(throws: (any Error).self) { try inbox.remove([UUID()]) }
        #expect(try Data(contentsOf: url) == damaged)
        let model = WalletCaptureModel(inbox: inbox)
        #expect(model.loadFailed)
        try JSONEncoder().encode([CapturedPayment]()).write(to: url)
        model.reload()
        #expect(!model.loadFailed)
    }

    @Test func receiptStatusSurvivesImportWithoutRetainingPaymentDetails() throws {
        let inbox = Self.temporaryInbox()
        #expect(inbox.lastReceivedAt == nil)
        let payment = try inbox.append(amount: 450, merchant: "PRIVATE SHOP", paidAt: TestSupport.now)
        try inbox.remove([payment.id])
        let reopened = PaymentInbox(directory: inbox.directory)
        #expect(try reopened.readPending().isEmpty)
        #expect(reopened.lastReceivedAt == TestSupport.now)
        let metadata = try Data(contentsOf: inbox.directory.appending(path: "last-received.json"))
        #expect(try JSONDecoder().decode(Date.self, from: metadata) == TestSupport.now)
        let model = WalletCaptureModel(inbox: reopened)
        #expect(model.pendingCount == 0)
        #expect(model.lastReceivedAt == TestSupport.now)
    }

    @Test func missingReceiptMetadataDoesNotHidePendingPayments() throws {
        let inbox = Self.temporaryInbox()
        try inbox.append(amount: 450, merchant: "Cafe", paidAt: TestSupport.now)
        try FileManager.default.removeItem(at: inbox.directory.appending(path: "last-received.json"))
        let model = WalletCaptureModel(inbox: inbox)
        #expect(model.pendingCount == 1)
        #expect(model.lastReceivedAt == nil)
        #expect(!model.loadFailed)
    }

    @Test func duplicateLookupFailureKeepsPaymentForRetry() throws {
        let fixture = try Fixture()
        try fixture.paymentInbox.append(amount: 450, merchant: "Cafe", paidAt: TestSupport.now)
        let lookup = fixture.model.loadPaymentOccurrenceKeys
        fixture.model.loadPaymentOccurrenceKeys = { throw CocoaError(.fileReadNoPermission) }
        #expect(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).isEmpty)
        #expect(fixture.paymentInbox.pending().count == 1)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Entry>()) == 0)
        fixture.model.loadPaymentOccurrenceKeys = lookup
        #expect(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).count == 1)
        #expect(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).isEmpty)
        #expect(try fixture.context.fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    /// 円の支払いを受け箱に置き、アプリは開かない。円のほかの通貨は受け取らない。
    @Test func intentStoresYenPayments() async throws {
        let previous = PaymentInbox.shared
        let inbox = Self.temporaryInbox()
        PaymentInbox.shared = inbox
        defer { PaymentInbox.shared = previous }
        #expect(!RecordPaymentIntent.openAppWhenRun)

        var intent = RecordPaymentIntent()
        intent.amount = IntentCurrencyAmount(amount: 450, currencyCode: "JPY")
        intent.merchant = "ｽﾀｰﾊﾞｯｸｽ"
        _ = try await intent.perform()
        #expect(inbox.pending().map(\.amount) == [450])
        #expect(inbox.pending().map(\.merchant) == ["ｽﾀｰﾊﾞｯｸｽ"])

        var dollars = RecordPaymentIntent()
        dollars.amount = IntentCurrencyAmount(amount: Decimal(string: "4.50")!, currencyCode: "USD")
        await #expect(throws: PaymentCaptureError.self) { _ = try await dollars.perform() }
        #expect(inbox.pending().count == 1)
    }

    // MARK: - ホーム

    /// 受け取った支払いを、店名の品目・辞書のカテゴリ・払った日時で記録し、1 つの返事にまとめて「取り消す」を出し、受け箱を空にする。
    @Test func importsPaymentsAsOneReply() throws {
        let fixture = try Fixture()
        try fixture.paymentInbox.append(amount: 450, merchant: "ｽﾀｰﾊﾞｯｸｽ ｺｰﾋｰ", paidAt: TestSupport.date(2026, 9, 28, hour: 8))
        try fixture.paymentInbox.append(amount: 298, merchant: "7-ELEVEN", paidAt: TestSupport.date(2026, 9, 28, hour: 9))

        let recorded = fixture.model.importCapturedPayments(calendar: TestSupport.calendar)

        #expect(recorded.map(\.memo) == ["スターバックス コーヒー", "7-ELEVEN"])
        #expect(recorded.map(\.category) == [.cafe, .food])
        #expect(recorded.map(\.spentAt) == [TestSupport.date(2026, 9, 28, hour: 8), TestSupport.date(2026, 9, 28, hour: 9)])
        #expect(recorded.allSatisfy { $0.source == .wallet && $0.originalText.isEmpty && $0.recurrenceKey.hasPrefix("wallet/") })
        let sends = TimelineSend.groupRanges(of: recorded.map {
            TimelineSend.Record(id: $0.memo, originalText: $0.originalText, source: $0.source, createdAt: $0.createdAt)
        })
        #expect(sends == [0..<2])
        #expect(fixture.model.canUndo)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
        #expect(fixture.paymentInbox.pending().isEmpty)
        #expect(fixture.announcements.last?.contains("¥450") == true)
    }

    /// 分からないお店は「その他」で記録して聞き返し、選ぶと店名を覚えて、次の支払いからそのカテゴリにする。
    @Test func unknownMerchantAsksAndIsLearned() throws {
        let fixture = try Fixture()
        try fixture.paymentInbox.append(amount: 3990, merchant: "ユニクロ 新宿店", paidAt: TestSupport.now)
        let entry = try #require(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).first)
        #expect(entry.memo == "ユニクロ")
        #expect(entry.category == .other)
        #expect(fixture.model.categoryQuestionIDs == [entry.persistentModelID])

        fixture.model.chooseCategory(.daily, for: entry)
        // ほかの店舗の支払いにも当てる（支店名を外して覚えるため）。
        try fixture.paymentInbox.append(amount: 1990, merchant: "ﾕﾆｸﾛ ｼﾌﾞﾔﾃﾝ", paidAt: TestSupport.now)
        let next = try #require(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).first)

        #expect(next.category == .daily)
        #expect(fixture.model.categoryQuestionIDs.isEmpty)
    }

    /// もう記録した支払い（受け箱から消せなかったなど）は、もう一度記録しない。
    @Test func doesNotImportTwice() throws {
        let fixture = try Fixture()
        let payment = try fixture.paymentInbox.append(amount: 450, merchant: "STARBUCKS", paidAt: TestSupport.now)
        let existing = TestSupport.entry(amount: 450, category: .cafe, memo: "STARBUCKS")
        existing.recurrenceKey = PaymentCapture.occurrenceKey(paymentID: payment.id.uuidString)
        try fixture.insert(existing)

        #expect(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).isEmpty)
        #expect(try fixture.entries().count == 1)
        #expect(fixture.paymentInbox.pending().isEmpty)
    }

    /// 取り消すと記録を消し、入力欄には何も戻さない（打った文が無い）。
    @Test func undoDoesNotRestoreDraft() throws {
        let fixture = try Fixture()
        try fixture.paymentInbox.append(amount: 450, merchant: "STARBUCKS", paidAt: TestSupport.now)
        fixture.model.importCapturedPayments(calendar: TestSupport.calendar)
        fixture.model.draft = "打ちかけ"

        fixture.model.undoLastRecord()

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.draft == "打ちかけ")
    }

    /// 読み取りの間は記録せず、受け箱に残す。
    @Test func waitsWhileParsing() async throws {
        let fixture = try Fixture()
        let gate = AsyncGate()
        fixture.parser = StubParser { text in
            await gate.wait()
            return [ParsedEntry(amount: 400, category: .cafe, memo: text)]
        }
        fixture.model.draft = "コーヒー 400"
        let sending = fixture.model.send(calendar: TestSupport.calendar)
        try fixture.paymentInbox.append(amount: 450, merchant: "STARBUCKS", paidAt: TestSupport.now)

        #expect(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).isEmpty)
        #expect(fixture.paymentInbox.pending().count == 1)

        await gate.open()
        await sending?.value
        #expect(fixture.model.importCapturedPayments(calendar: TestSupport.calendar).count == 1)
    }

    /// Apple Pay の支払いは、よく使うひとことの候補に出さない（払うだけで記録されるので、打つ候補ではない）。
    @Test func quickPhrasesSkipPayments() throws {
        let fixture = try Fixture()
        for _ in 0..<3 {
            try fixture.paymentInbox.append(amount: 450, merchant: "STARBUCKS", paidAt: TestSupport.now)
        }
        fixture.model.importCapturedPayments(calendar: TestSupport.calendar)

        fixture.model.refreshQuickPhrases()

        #expect(fixture.model.quickPhrases.isEmpty)
    }
}
