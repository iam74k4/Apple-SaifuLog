import Foundation
import Testing
@testable import SaifuLogCore

/// カードのテストで使う記録。
struct TestCardRecord: CardLedgerRecord {
    var amount: Int
    var isIncome = false
    var category: EntryCategory = .other
    var spentAt: Date
    var cardID: String = ""
}

@Suite("カードの締めと引き落とし")
struct PaymentCardTests {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    /// 15 日締め・翌月 10 日引き落とし。
    static let mid = PaymentCard(id: "mid", name: "楽天カード", closingDay: 15, paymentDay: 10)
    /// 月末締め・翌月 27 日引き落とし。
    static let endOfMonth = PaymentCard(id: "end", name: "エポス", closingDay: 31, paymentDay: 27)
    /// 月末締め・翌々月 4 日引き落とし。
    static let twoMonths = PaymentCard(id: "two", name: "アメックス", closingDay: 31, paymentDay: 4, paymentMonthOffset: 2)

    @Test("締めの期間は前の締め日の翌日から締め日まで。引き落としは締めた月の翌月")
    func statementPeriod() throws {
        let statement = try #require(Self.mid.statement(closingIn: RecurringMonth(year: 2026, month: 11), timeZone: Self.tokyo))
        #expect(statement.period.start == Fixture.date(2026, 10, 16))
        #expect(statement.period.end == Fixture.date(2026, 11, 16))
        #expect(statement.closingDate == Fixture.date(2026, 11, 15))
        #expect(statement.paymentDate == Fixture.date(2026, 12, 10))
    }

    @Test("締め日の日のうちに使った記録はその締め、次の日からは次の締め")
    func statementContaining() throws {
        let onClosing = try #require(Self.mid.statement(containing: Fixture.date(2026, 11, 15, hour: 23, minute: 59), timeZone: Self.tokyo))
        #expect(onClosing.closingMonth == RecurringMonth(year: 2026, month: 11))
        let after = try #require(Self.mid.statement(containing: Fixture.date(2026, 11, 16), timeZone: Self.tokyo))
        #expect(after.closingMonth == RecurringMonth(year: 2026, month: 12))
        #expect(after.paymentDate == Fixture.date(2027, 1, 10))
    }

    @Test("月末締めは、その月に無い日を月末にする（2 月は 28 日）")
    func monthEnd() throws {
        let february = try #require(Self.endOfMonth.statement(closingIn: RecurringMonth(year: 2026, month: 2), timeZone: Self.tokyo))
        #expect(february.period.start == Fixture.date(2026, 2, 1))
        #expect(february.period.end == Fixture.date(2026, 3, 1))
        #expect(february.paymentDate == Fixture.date(2026, 3, 27))
    }

    @Test("次の引き落としは、今日を含めてこれからのいちばん早い引き落とし")
    func nextPayment() throws {
        // 11/10 の引き落とし日の当日は、その日の引き落とし。
        let onDay = try #require(Self.mid.nextPaymentStatement(after: Fixture.date(2026, 11, 10, hour: 20), timeZone: Self.tokyo))
        #expect(onDay.paymentDate == Fixture.date(2026, 11, 10))
        // 過ぎたら、10/16〜11/15 の分の 12/10。
        let after = try #require(Self.mid.nextPaymentStatement(after: Fixture.date(2026, 11, 11), timeZone: Self.tokyo))
        #expect(after.paymentDate == Fixture.date(2026, 12, 10))
        #expect(after.closingMonth == RecurringMonth(year: 2026, month: 11))
    }

    @Test("翌々月に引き落とすカードは、締めた後でまだ引き落としていない分が次の引き落とし")
    func nextPaymentTwoMonths() throws {
        let next = try #require(Self.twoMonths.nextPaymentStatement(after: Fixture.date(2026, 11, 15), timeZone: Self.tokyo))
        // 10 月の分（10/1〜10/31）を 12/4 に引き落とす。9 月の分は 11/4 に済んでいる。
        #expect(next.closingMonth == RecurringMonth(year: 2026, month: 10))
        #expect(next.paymentDate == Fixture.date(2026, 12, 4))
    }

    @Test("締めの合計は、そのカードの支出で期間に入るものだけ")
    func statementSummary() throws {
        let statement = try #require(Self.mid.statement(closingIn: RecurringMonth(year: 2026, month: 11), timeZone: Self.tokyo))
        let records = [
            TestCardRecord(amount: 850, spentAt: Fixture.date(2026, 10, 16), cardID: "mid"),
            TestCardRecord(amount: 1200, spentAt: Fixture.date(2026, 11, 15, hour: 23), cardID: "mid"),
            TestCardRecord(amount: 300, spentAt: Fixture.date(2026, 11, 16), cardID: "mid"),
            TestCardRecord(amount: 999, spentAt: Fixture.date(2026, 10, 15, hour: 23), cardID: "mid"),
            TestCardRecord(amount: 500, spentAt: Fixture.date(2026, 11, 1), cardID: "end"),
            TestCardRecord(amount: 700, spentAt: Fixture.date(2026, 11, 1)),
            TestCardRecord(amount: 5000, isIncome: true, spentAt: Fixture.date(2026, 11, 1), cardID: "mid"),
        ]
        let summary = CardStatementSummary(statement: statement, records: records)
        #expect(summary.total == 2050)
        #expect(summary.count == 2)
    }

    @Test("支払い方法の内訳は、カードの並びの順で、最後に現金・その他。消したカードの記録は現金・その他")
    func breakdown() {
        let interval = DateInterval(start: Fixture.date(2026, 11, 1), end: Fixture.date(2026, 12, 1))
        let records = [
            TestCardRecord(amount: 850, spentAt: Fixture.date(2026, 11, 2), cardID: "end"),
            TestCardRecord(amount: 400, spentAt: Fixture.date(2026, 11, 3), cardID: "mid"),
            TestCardRecord(amount: 300, spentAt: Fixture.date(2026, 11, 3)),
            TestCardRecord(amount: 200, spentAt: Fixture.date(2026, 11, 4), cardID: "gone"),
            TestCardRecord(amount: 9999, spentAt: Fixture.date(2026, 12, 1), cardID: "mid"),
            TestCardRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 11, 25)),
        ]
        let breakdown = PaymentBreakdown(records: records, interval: interval, cards: [Self.mid, Self.endOfMonth, Self.twoMonths])
        #expect(breakdown.rows.map(\.card?.id) == ["mid", "end", nil])
        #expect(breakdown.rows.map(\.amount) == [400, 850, 500])
        #expect(breakdown.rows.map(\.count) == [1, 1, 2])
        #expect(breakdown.hasCardRecords)
        let cashOnly = PaymentBreakdown(records: [records[2]], interval: interval, cards: [Self.mid])
        #expect(!cashOnly.hasCardRecords)
    }

    @Test("名前は空・長すぎる・ほかのカードと同じ（かなと英字の大小を問わない）を受け付けない")
    func validateName() {
        let cards = [Self.mid, PaymentCard(id: "visa", name: "VISA", closingDay: 31, paymentDay: 27)]
        #expect(PaymentCard.validateName("  エポス ", among: cards) == .success("エポス"))
        #expect(PaymentCard.validateName(" ", among: cards) == .failure(.empty))
        #expect(PaymentCard.validateName(String(repeating: "あ", count: 21), among: cards) == .failure(.tooLong))
        #expect(PaymentCard.validateName("楽天かーど", among: cards) == .failure(.duplicate))
        #expect(PaymentCard.validateName("visa", among: cards) == .failure(.duplicate))
        #expect(PaymentCard.validateName("楽天カード", among: cards, editing: "mid") == .success("楽天カード"))
    }

    @Test("いつものカードは、決めたカードか、1 枚だけならそのカード")
    func defaultCard() {
        var main = Self.endOfMonth
        main.isDefault = true
        #expect(PaymentCard.defaultCard(in: [Self.mid, main])?.id == "end")
        #expect(PaymentCard.defaultCard(in: [Self.mid])?.id == "mid")
        #expect(PaymentCard.defaultCard(in: [Self.mid, Self.endOfMonth]) == nil)
        #expect(PaymentCard.defaultCard(in: []) == nil)
    }
}

@Suite("払い方の読み取り")
struct PaymentLinkerTests {
    static let rakuten = PaymentCard(id: "rakuten", name: "楽天", closingDay: 31, paymentDay: 27, isDefault: true)
    static let epos = PaymentCard(id: "epos", name: "エポスカード", closingDay: 27, paymentDay: 4)
    static let linker = PaymentLinker(cards: [rakuten, epos])

    static func link(_ text: String, linker: PaymentLinker = linker) -> [ParsedEntry] {
        linker.link(Fixture.parser.entries(from: text), text: text)
    }

    @Test(
        "払い方の言葉は品目から除き、カードを決める",
        arguments: [
            ("ランチ 850 カードで", "ランチ", "rakuten"),
            ("カードでランチ 850", "ランチ", "rakuten"),
            ("ランチ 850 クレカ払い", "ランチ", "rakuten"),
            ("ランチ 850 クレカ", "ランチ", "rakuten"),
            ("ランチ 850 エポスで", "ランチ", "epos"),
            ("エポスカードでランチ 850", "ランチ", "epos"),
            ("ランチ 850 楽天カード", "ランチ", "rakuten"),
            ("ランチ 850 えぽすかーどで", "ランチ", "epos"),
            ("VISAカードでランチ 850", "ランチ", "rakuten"),
            ("ランチ 850 現金で", "ランチ", nil),
            ("ランチ 850 現金", "ランチ", nil),
            ("ランチ 850 PayPayで", "ランチ", nil),
            ("Suicaでコンビニ 500", "コンビニ", nil),
        ] as [(String, String, String?)]
    )
    func links(text: String, memo: String, cardID: String?) throws {
        let entry = try #require(Self.link(text).first)
        #expect(entry.memo == memo)
        #expect(entry.cardID == cardID)
        #expect(entry.amount == (text.contains("500") ? 500 : 850))
    }

    @Test(
        "払い方でない言葉は品目に残し、カードにしない",
        arguments: [
            ("誕生日カード 300", "誕生日カード"),
            ("図書カード 1000", "図書カード"),
            ("誕生日 カード 300", "誕生日 カード"),
            ("Suica チャージ 3000", "Suica チャージ"),
            ("カードケース 1500", "カードケース"),
            ("ランチ 850", "ランチ"),
        ]
    )
    func keepsItems(text: String, memo: String) throws {
        let entry = try #require(Self.link(text).first)
        #expect(entry.memo == memo)
        #expect(entry.cardID == nil)
    }

    @Test("除くと品目が空になるときは、品目を残す")
    func keepsWhenEmpty() throws {
        let entry = try #require(Self.link("楽天カードで 3000").first)
        #expect(entry.memo == "楽天カード")
        #expect(entry.cardID == "rakuten")
    }

    @Test("1 つの払い方しか書いていなければ、送った文のすべての件に使う。混ざっていれば書いた件だけ")
    func sharedChoice() {
        let both = Self.link("コーヒー 400 パン 300 カードで")
        #expect(both.map(\.memo) == ["コーヒー", "パン"])
        #expect(both.map(\.cardID) == ["rakuten", "rakuten"])
        let mixed = Self.link("コーヒー 400 現金、パン 300 エポスで")
        #expect(mixed.map(\.cardID) == [nil, "epos"])
    }

    @Test("収入はカードの記録にしない")
    func incomeIsNotCard() throws {
        let entry = try #require(Self.link("給料 25万 カードで").first)
        #expect(entry.isIncome)
        #expect(entry.cardID == nil)
    }

    @Test("割り勘の説明は残し、品目からだけ除く")
    func keepsSplitNote() throws {
        let entry = try #require(Self.link("焼肉 12000 4人で割り勘 カードで").first)
        #expect(entry.amount == 3000)
        #expect(entry.cardID == "rakuten")
        let note = try #require(EntryMemoNote(memo: entry.memo, amount: entry.amount, isIncome: false))
        #expect(note.item == "焼肉")
    }

    @Test("カードを登録していなくても品目から除く。いつものカードが決められなければカードにしない")
    func withoutCards() throws {
        let none = try #require(Self.link("ランチ 850 カードで", linker: PaymentLinker(cards: [])).first)
        #expect(none.memo == "ランチ")
        #expect(none.cardID == nil)
        let two = PaymentLinker(cards: [Self.epos, PaymentCard(id: "x", name: "JCB", closingDay: 15, paymentDay: 10)])
        let ambiguous = try #require(Self.link("ランチ 850 カードで", linker: two).first)
        #expect(ambiguous.cardID == nil)
    }

    @Test("AI が品目だけを返したとき（払い方の言葉が品目に無い）も、文からカードを決める")
    func aiItem() throws {
        let parsed = [ParsedEntry(amount: 850, category: .food, memo: "ランチ")]
        let entry = try #require(Self.linker.link(parsed, text: "ランチ 850 エポスで").first)
        #expect(entry.memo == "ランチ")
        #expect(entry.cardID == "epos")
        let bracket = try #require(Self.linker.link([ParsedEntry(amount: 850, category: .food, memo: "ランチ(カード払い)")], text: "ランチ 850 カード払い").first)
        #expect(bracket.memo == "ランチ")
    }

    @Test(
        "カードの引き落としを書いた文を見分ける",
        arguments: [
            ("クレカ引き落とし 50000", true),
            ("カードの引き落とし 50000", true),
            ("引き落とし 楽天カード 50000", true),
            ("エポスカードの請求 30000", true),
            ("カードの支払い 50000", true),
            ("カード代 5万", true),
            ("楽天カード 50000", true),
            ("クレカ 11月分 50000", true),
            ("VISAカードの引落 20000", true),
            ("ランチ 850 カードで", false),
            ("ランチ カード払い 850", false),
            ("カード支払い ランチ 850", false),
            ("カード 300", false),
            ("誕生日カード 300", false),
            ("図書カード代 1000", false),
            ("カードの年会費 1100", false),
            ("電気代 引き落とし 8000", false),
            ("Suicaの明細 3000", false),
        ]
    )
    func cardBill(text: String, isBill: Bool) {
        #expect(Self.linker.isCardBill(text) == isBill)
    }
}

@Suite("カードの質問")
struct CardQuestionTests {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let cards = [
        PaymentCard(id: "rakuten", name: "楽天カード", closingDay: 31, paymentDay: 27),
        PaymentCard(id: "epos", name: "エポス", closingDay: 27, paymentDay: 4),
    ]

    @Test(
        "カードのことを聞いた質問を読む",
        arguments: [
            ("楽天カードの利用額は？", CardQuestion.Kind.currentUsage, ["rakuten"]),
            ("エポスで今月いくら使った？", .currentUsage, ["epos"]),
            ("カードの利用額は？", .currentUsage, ["rakuten", "epos"]),
            ("先月のクレカはいくら？", .previousUsage, ["rakuten", "epos"]),
            ("次の引き落としはいくら？", .nextPayment, ["rakuten", "epos"]),
            ("楽天カードの請求は？", .nextPayment, ["rakuten"]),
            ("エポスの支払いはいつ？", .nextPayment, ["epos"]),
        ] as [(String, CardQuestion.Kind, [String])]
    )
    func reads(text: String, kind: CardQuestion.Kind, ids: [String]) throws {
        let question = try #require(CardQuestion.read(text, cards: Self.cards))
        #expect(question.kind == kind)
        #expect(question.cardIDs == ids)
    }

    @Test("カードの質問でなければ読まない。カードを登録していなければ読まない")
    func ignores() {
        #expect(CardQuestion.read("今月いくら使った？", cards: Self.cards) == nil)
        #expect(CardQuestion.read("今月の支払いは？", cards: Self.cards) == nil)
        #expect(CardQuestion.read("カードの利用額は？", cards: []) == nil)
    }

    @Test("答えはカードごとの締めの額。引き落としは早い順")
    func answer() {
        let now = Fixture.date(2026, 11, 15, hour: 12)
        let records = [
            TestCardRecord(amount: 1000, spentAt: Fixture.date(2026, 10, 20), cardID: "rakuten"),
            TestCardRecord(amount: 2000, spentAt: Fixture.date(2026, 11, 2), cardID: "rakuten"),
            TestCardRecord(amount: 500, spentAt: Fixture.date(2026, 10, 28), cardID: "epos"),
            TestCardRecord(amount: 700, spentAt: Fixture.date(2026, 11, 3), cardID: "epos"),
        ]
        var asked: [DateInterval] = []
        let next = CardAnswer(
            question: CardQuestion(kind: .nextPayment, cardIDs: ["rakuten", "epos"]), cards: Self.cards, now: now,
            timeZone: Self.tokyo
        ) { interval in
            asked.append(interval)
            return records.filter { interval.contains($0.spentAt) }
        }
        // 楽天は 10 月の分（10/1〜10/31）を 11/27 に、エポスは 10/28〜11/27 の分を 12/4 に引き落とす。
        #expect(next.rows.map(\.card.id) == ["rakuten", "epos"])
        #expect(next.rows.map(\.summary.total) == [1000, 1200])
        #expect(next.rows.map(\.summary.statement.paymentDate) == [Fixture.date(2026, 11, 27), Fixture.date(2026, 12, 4)])
        #expect(next.total == 2200)
        #expect(asked.count == 1)

        let current = CardAnswer(
            question: CardQuestion(kind: .currentUsage, cardIDs: ["rakuten"]), cards: Self.cards, now: now, timeZone: Self.tokyo
        ) { interval in records.filter { interval.contains($0.spentAt) } }
        #expect(current.rows.map(\.summary.total) == [2000])
    }
}
