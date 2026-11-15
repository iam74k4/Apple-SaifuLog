import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 登録したクレジットカード（保存・記録への当て方・引き落としの確認・質問・直す・一覧・まとめ・くり返し・レシート・CSV）。
@MainActor
struct CreditCardTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 楽天カード（月末締め・翌月 27 日）と JCB（15 日締め・翌月 10 日）を登録する。最初の 1 枚がいつものカードになる。
    @discardableResult
    private func registerCards(in context: ModelContext, ids: [String] = ["rakuten", "jcb"]) throws -> [PaymentCard] {
        var remaining = ids
        var store = CreditCardStore(context: context, now: { TestSupport.now })
        store.makeID = { remaining.removeFirst() }
        let rakuten = try store.create(PaymentCard(id: "", name: "楽天カード", closingDay: 31, paymentDay: 27))
        let jcb = try store.create(PaymentCard(id: "", name: "JCB", closingDay: 15, paymentDay: 10))
        return [rakuten, jcb]
    }

    private func entry(_ amount: Int, cardID: String, spentAt: Date, income: Bool = false) -> Entry {
        let entry = Entry(
            amount: amount, isIncome: income, category: income ? .other : .food, memo: "ランチ", spentAt: spentAt, createdAt: spentAt,
            source: .text, originalText: "ランチ"
        )
        entry.cardID = cardID
        return entry
    }

    // MARK: - 保存

    @Test func storeCreatesUpdatesAndKeepsOneDefault() throws {
        let context = try TestSupport.makeContext()
        let cards = try registerCards(in: context)
        #expect(cards.map(\.isDefault) == [true, false])
        let store = CreditCardStore(context: context, now: { TestSupport.now })

        var jcb = cards[1]
        jcb.isDefault = true
        try store.update(jcb)
        #expect(try store.cards().map(\.isDefault) == [false, true])

        #expect(throws: CardNameIssue.duplicate) {
            try store.create(PaymentCard(id: "", name: "jcb", closingDay: 15, paymentDay: 10))
        }
    }

    @Test func storeCapsCardCount() throws {
        let context = try TestSupport.makeContext()
        let store = CreditCardStore(context: context, now: { TestSupport.now })
        for index in 0..<PaymentCard.maximumCount {
            try store.create(PaymentCard(id: "", name: "カード\(index)", closingDay: 31, paymentDay: 27))
        }
        #expect(throws: CreditCardError.tooMany) {
            try store.create(PaymentCard(id: "", name: "もう 1 枚", closingDay: 31, paymentDay: 27))
        }
    }

    /// 消すと、そのカードの記録とくり返しの記録はカードなし（現金・その他）になる。記録そのものは残る。
    @Test func deletingCardClearsRecords() throws {
        let context = try TestSupport.makeContext()
        try registerCards(in: context)
        try EntryStore(context: context).insert([entry(850, cardID: "rakuten", spentAt: TestSupport.now)])
        let recurring = RecurringEntryStore(context: context, now: { TestSupport.now })
        try recurring.create(
            RecurringDraft(amount: 980, memo: "サブスク", isIncome: false, category: .entertainment, dayOfMonth: 1, cardID: "rakuten"),
            startMonth: RecurringMonth(year: 2026, month: 10)
        )
        let store = CreditCardStore(context: context, now: { TestSupport.now })
        #expect(try store.entryCount(of: "rakuten") == 1)

        try store.delete("rakuten")

        #expect(try store.cards().map(\.id) == ["jcb"])
        let entries = try context.fetch(FetchDescriptor<Entry>())
        #expect(entries.map(\.cardID) == [""])
        #expect(try recurring.rules().map(\.cardID) == [""])
    }

    // MARK: - 記録に当てる

    @Test func recordsCardNamedInText() async throws {
        let fixture = try Fixture()
        try registerCards(in: fixture.context)
        fixture.model.cards.reload()

        await fixture.send("ランチ 850 JCBで")

        let entry = try #require(try fixture.entries().first)
        #expect(entry.cardID == "jcb")
        #expect(entry.memo == "ランチ")
        #expect(entry.category == .food)
    }

    @Test func genericCardWordUsesDefaultCardAndCashUsesNone() async throws {
        let fixture = try Fixture()
        try registerCards(in: fixture.context)
        fixture.model.cards.reload()

        await fixture.send("コーヒー 400 パン 300 カードで")
        fixture.now = TestSupport.now.addingTimeInterval(60)
        await fixture.send("ランチ 850 現金で")

        let entries = try fixture.entries()
        #expect(entries.map(\.cardID) == ["rakuten", "rakuten", ""])
        #expect(entries.map(\.memo) == ["コーヒー", "パン", "ランチ"])
    }

    // MARK: - 引き落としの確認

    @Test func cardBillAsksBeforeRecording() async throws {
        let fixture = try Fixture()
        try registerCards(in: fixture.context)
        fixture.model.cards.reload()

        await fixture.send("クレカ引き落とし 50000")

        #expect(try fixture.entries().isEmpty)
        let pending = try #require(fixture.model.pendingCardBill)
        #expect(pending.text == "クレカ引き落とし 50000")
        #expect(fixture.model.isPresentingOtherScreen)

        fixture.model.cancelCardBill(pending)

        #expect(try fixture.entries().isEmpty)
        #expect(fixture.model.pendingCardBill == nil)
        #expect(fixture.model.draft == "クレカ引き落とし 50000")
        #expect(fixture.lastQuestionState == .cardBillNotRecorded)
    }

    @Test func confirmingCardBillRecordsIt() async throws {
        let fixture = try Fixture()

        await fixture.send("カードの引き落とし 50000")
        let pending = try #require(fixture.model.pendingCardBill)
        await fixture.model.confirmCardBill(pending)?.value

        #expect(try fixture.entries().map(\.amount) == [50_000])
        #expect(fixture.model.pendingCardBill == nil)
    }

    /// 金額の無い文は確かめずに、これまでどおり「金額が見つかりませんでした」。
    @Test func cardBillWithoutAmountIsNotAsked() async throws {
        let fixture = try Fixture()

        await fixture.send("カードの引き落とし")

        #expect(fixture.model.pendingCardBill == nil)
        #expect(fixture.showedNoAmount)
    }

    // MARK: - 質問

    @Test func answersCardQuestion() async throws {
        let fixture = try Fixture()
        try registerCards(in: fixture.context)
        fixture.model.cards.reload()
        // 楽天カードは月末締め。9 月の分（9/1〜9/30）を 10/27 に引き落とす。
        try fixture.insert(
            entry(1200, cardID: "rakuten", spentAt: TestSupport.date(2026, 9, 3)),
            entry(800, cardID: "rakuten", spentAt: TestSupport.date(2026, 9, 20)),
            entry(500, cardID: "jcb", spentAt: TestSupport.date(2026, 9, 20)),
            entry(300, cardID: "", spentAt: TestSupport.date(2026, 9, 20))
        )

        await fixture.send("楽天カードの利用額は？")

        guard case .cardAnswered(let answer) = fixture.lastQuestionState else {
            Issue.record("カードの質問として答えていない: \(String(describing: fixture.lastQuestionState))")
            return
        }
        #expect(answer.kind == .currentUsage)
        #expect(answer.rows.map(\.card.id) == ["rakuten"])
        #expect(answer.total == 2000)
        #expect(try fixture.entries().count == 4)
    }

    // MARK: - 直す

    @Test func editingChangesCardAndIncomeClearsIt() throws {
        let context = try TestSupport.makeContext()
        try registerCards(in: context)
        let record = entry(850, cardID: "", spentAt: TestSupport.now)
        try EntryStore(context: context).insert([record])

        let model = EditEntryModel(entry: record, store: EntryStore(context: context), calendar: TestSupport.calendar, now: { TestSupport.now })
        model.cardID = "jcb"
        #expect(model.canSave)
        #expect(model.save())
        #expect(record.cardID == "jcb")

        let income = EditEntryModel(entry: record, store: EntryStore(context: context), calendar: TestSupport.calendar, now: { TestSupport.now })
        income.isIncome = true
        #expect(income.save())
        #expect(record.cardID == "")
    }

    // MARK: - 一覧

    @Test func listShowsCurrentStatementAndNextPayment() throws {
        let context = try TestSupport.makeContext()
        try registerCards(in: context)
        // JCB は 15 日締め・翌月 10 日。いま（9/28）の締めは 9/16〜10/15、次の引き落としは 8/16〜9/15 の分の 10/10。
        try EntryStore(context: context).insert([
            entry(1000, cardID: "jcb", spentAt: TestSupport.date(2026, 9, 10)),
            entry(2000, cardID: "jcb", spentAt: TestSupport.date(2026, 9, 20)),
            entry(4000, cardID: "jcb", spentAt: TestSupport.date(2026, 9, 25), income: true),
        ])
        let list = CardListModel(
            cards: CardCatalogModel(store: CreditCardStore(context: context)), context: context, now: { TestSupport.now },
            timeZone: TestSupport.calendar.timeZone, announce: { _ in }
        )
        list.reload()

        let overview = try #require(list.overviews["jcb"])
        #expect(overview.current.total == 2000)
        #expect(overview.next?.total == 1000)
        #expect(overview.next?.statement.paymentDate == TestSupport.date(2026, 10, 10))

        let statement = list.statementModel(for: try #require(list.cards.last))
        #expect(statement.entries.map(\.amount) == [2000])
        #expect(!statement.canShowNext)
        statement.showPrevious()
        #expect(statement.entries.map(\.amount) == [1000])
        #expect(statement.canShowNext)

        list.requestDeletion(try #require(list.cards.last))
        #expect(list.pendingDeletion?.entryCount == 3)
    }

    // MARK: - まとめ

    @Test func monthlyReportShowsPaymentBreakdownOnlyWithCardRecords() throws {
        let context = try TestSupport.makeContext()
        try registerCards(in: context)
        let catalog = CardCatalogModel(store: CreditCardStore(context: context))
        try EntryStore(context: context).insert([entry(300, cardID: "", spentAt: TestSupport.date(2026, 9, 3))])
        let cashOnly = MonthlyReportModel(store: EntryStore(context: context), cards: catalog, calendar: TestSupport.calendar, now: { TestSupport.now })
        #expect(cashOnly.paymentBreakdown == nil)

        try EntryStore(context: context).insert([entry(850, cardID: "jcb", spentAt: TestSupport.date(2026, 9, 4))])
        let report = MonthlyReportModel(store: EntryStore(context: context), cards: catalog, calendar: TestSupport.calendar, now: { TestSupport.now })
        let rows = try #require(report.paymentBreakdown?.rows)
        #expect(rows.map(\.card?.id) == ["jcb", nil])
        #expect(rows.map(\.amount) == [850, 300])
    }

    // MARK: - くり返しとレシート

    @Test func recurringRecordsCarryCard() throws {
        let context = try TestSupport.makeContext()
        let store = RecurringEntryStore(context: context, now: { TestSupport.now })
        try store.create(
            RecurringDraft(amount: 980, memo: "サブスク", isIncome: false, category: .entertainment, dayOfMonth: 1, cardID: "rakuten"),
            startMonth: RecurringMonth(year: 2026, month: 9)
        )

        let recorded = try store.recordDue(now: TestSupport.now, timeZone: TestSupport.calendar.timeZone)

        #expect(recorded.map(\.cardID) == ["rakuten"])
    }

    @Test func receiptRecordsCarryCard() {
        let submission = ReceiptResultModel.Submission(
            records: [ReceiptRecord(memo: "おにぎり", amount: 160, category: .food)],
            spentAt: TestSupport.now, originalText: "レシート: コンビニ 合計 ¥160", cardID: "jcb"
        )

        let entries = Entry.records(fromReceipt: submission, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(entries.map(\.cardID) == ["jcb"])
    }

    // MARK: - CSV

    @Test func importerRestoresCards() {
        let rows = [
            LedgerCSVReader.Row(
                line: 2, spentAt: TestSupport.now, isIncome: false, category: .food, memo: "ランチ", amount: 850,
                originalText: "ランチ 850", cardID: "rakuten"
            ),
            LedgerCSVReader.Row(
                line: 3, spentAt: TestSupport.now, isIncome: false, category: .food, memo: "パン", amount: 300, originalText: "パン 300"
            ),
        ]

        #expect(LedgerImporter.entries(from: rows).map(\.cardID) == ["rakuten", ""])
    }
}
