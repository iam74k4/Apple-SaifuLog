import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

/// 送信へのアプリの返事（`RecordedReplyCard`）に添える文（`ReplyTexts`）。数字はコードが計算したものをそのまま使い、AI が使えない
/// 端末でも同じ文になることを、日本語と英語の訳で確かめる。
@MainActor
struct ReplyTextsTests {
    typealias Fixture = HomeModelTests.Fixture

    /// 英語の訳の書式に値を入れた文。
    static func english(_ key: String, _ arguments: any CVarArg...) throws -> String {
        let format = try LocalizationTests.bundle(for: "en").localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: Locale(identifier: "en_US"), arguments: arguments)
    }

    // MARK: - 割り勘・1 人分の説明

    @Test("割り勘の説明は、総額・人数・立て替えた額をそのまま使った文にする（日本語は「¥12,000 を4人で割り勘。…」）")
    func splitNote() throws {
        let note = try #require(EntryMemoNote(memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）", amount: 3_000, isIncome: false))

        #expect(note.item == "焼肉")
        #expect(ReplyTexts.note(for: note) == "¥12,000 を4人で割り勘。立て替えた ¥9,000 はメモに残しました。")
        #expect(try Self.english("%@ を%lld人で割り勘。立て替えた %@ はメモに残しました。", "¥12,000", 4, "¥9,000")
            == "¥12,000 split 4 ways. The ¥9,000 you paid for the others is noted in the memo.")
    }

    @Test("割り切れない割り勘は、自分が持った端数を引いた立て替えの額を書く")
    func unevenSplitNote() throws {
        let note = try #require(EntryMemoNote(memo: "3人で割り勘・総額 ¥1,000・立替 ¥666", amount: 334, isIncome: false))

        #expect(note.item.isEmpty)
        #expect(ReplyTexts.note(for: note) == "¥1,000 を3人で割り勘。立て替えた ¥666 はメモに残しました。")
    }

    @Test("立て替えた額が 0 円の割り勘は、立て替えを書かない")
    func splitNoteWithoutAdvance() throws {
        let note = try #require(EntryMemoNote(memo: "2人で割り勘・総額 ¥1・立替 ¥0", amount: 1, isIncome: false))

        #expect(ReplyTexts.note(for: note) == "¥1 を2人で割り勘。")
        #expect(try Self.english("%@ を%lld人で割り勘。", "¥1", 2) == "¥1 split 2 ways.")
    }

    @Test("1 人分として書いた額は、1 人分として記録したことを書く（割り勘の人数が書かれていれば人数も）")
    func perPersonNote() throws {
        let withCount = try #require(EntryMemoNote(memo: "焼肉（4人で割り勘・1人分）", amount: 3_000, isIncome: false))
        let withoutCount = try #require(EntryMemoNote(memo: "焼肉（1人分）", amount: 3_000, isIncome: false))

        #expect(ReplyTexts.note(for: withCount) == "4人で割り勘の1人分として記録しました。")
        #expect(ReplyTexts.note(for: withoutCount) == "1人分として記録しました。")
        #expect(try Self.english("%lld人で割り勘の1人分として記録しました。", 4) == "Recorded as your share of a 4-way split.")
        #expect(try Self.english("1人分として記録しました。") == "Recorded as one person’s share.")
    }

    // MARK: - 直前の送信の返事の、今月の状況の一行

    /// 2026-09-28 の今月（9/28・9/29・9/30 の 3 日が残る）の予算の進み。
    static func budget(_ amount: Int, spent: Int) throws -> BudgetStatus {
        let month = try #require(ReportPeriod.thisMonth.interval(now: TestSupport.now, calendar: TestSupport.calendar))
        return try #require(BudgetStatus(budget: amount, spent: spent, now: TestSupport.now, month: month, calendar: TestSupport.calendar))
    }

    @Test("予算を決めていれば、帯と同じ残りと 1 日あたりの額で「今月あと ¥…（1日あたり ¥…）」")
    func statusWithBudget() throws {
        let sentence = ReplyTexts.status(
            summary: MonthlySummary(expense: 82_656), budget: try Self.budget(150_000, spent: 82_656), isIncomeOnly: false
        )

        #expect(sentence.text == "今月あと ¥67,344（1日あたり ¥22,448）")
        #expect(sentence.figures == ["¥67,344", "¥22,448"])
        #expect(!sentence.isWarning)
        #expect(try Self.english("今月あと %@（1日あたり %@）", "¥67,344", "¥22,448") == "¥67,344 left this month (¥22,448 a day)")
    }

    @Test("予算を超えていれば「今月の予算を ¥… 超えています」（額は注意の色）")
    func statusOverBudget() throws {
        let sentence = ReplyTexts.status(
            summary: MonthlySummary(expense: 153_000), budget: try Self.budget(150_000, spent: 153_000), isIncomeOnly: false
        )

        #expect(sentence.text == "今月の予算を ¥3,000 超えています")
        #expect(sentence.figures == ["¥3,000"])
        #expect(sentence.isWarning)
        #expect(try Self.english("今月の予算を %@ 超えています", "¥3,000") == "¥3,000 over this month’s budget")
    }

    @Test("予算を決めていなければ「今月の支出 ¥…」")
    func statusWithoutBudget() throws {
        let sentence = ReplyTexts.status(summary: MonthlySummary(expense: 42_380, income: 1_000), budget: nil, isIncomeOnly: false)

        #expect(sentence.text == "今月の支出 ¥42,380")
        #expect(sentence.figures == ["¥42,380"])
        #expect(try Self.english("今月の支出 %@", "¥42,380") == "Spent this month: ¥42,380")
    }

    /// 予算の残りは収入で増えないので、給料を送った返事には、予算があっても今月の収入を出す。
    @Test("収入だけの送信は、予算があっても「今月の収入 ¥…」")
    func statusForIncomeOnlySend() throws {
        let summary = MonthlySummary(expense: 82_656, income: 250_000)
        let withBudget = ReplyTexts.status(summary: summary, budget: try Self.budget(150_000, spent: 82_656), isIncomeOnly: true)
        let withoutBudget = ReplyTexts.status(summary: summary, budget: nil, isIncomeOnly: true)

        #expect(withBudget.text == "今月の収入 ¥250,000")
        #expect(withBudget == withoutBudget)
        #expect(withBudget.figures == ["¥250,000"])
        #expect(try Self.english("今月の収入 %@（返事）", "¥250,000") == "Income this month: ¥250,000")
    }

    /// 数字は太字にし、ほかの数字の一部（「¥14,209」の中の「¥4,209」）には当てない。注意の文は数字を注意の色にする。
    @Test("文の中の数字だけを太字にする（ほかの数字の一部には当てない）")
    func figuresAreEmphasized() {
        let sentence = ReplySentence(text: "今月あと ¥14,209（1日あたり ¥4,209）", figures: ["¥4,209"])

        let emphasized = sentence.attributed().runs
            .filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(sentence.attributed()[$0.range].characters) }
        #expect(emphasized == ["¥4,209"])
        let colored = sentence.attributed(figureColor: .red).runs.compactMap(\.foregroundColor)
        #expect(colored == [.red])
    }

    /// 返事の行は品目だけを見出しにして説明を文で添えるが、保存するメモと CSV の書き出しは変えない。
    @Test("割り勘を送っても、保存するメモと CSV の書き出しは説明を書き足したまま")
    func splitSendKeepsStoredMemo() async throws {
        let fixture = try Fixture()

        await fixture.send("昨日 焼肉12000 4人で割り勘")

        let entry = try #require(try fixture.entries().first)
        let memo = "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）"
        #expect(entry.memo == memo)
        #expect(entry.amount == 3_000)
        let note = try #require(EntryMemoNote(memo: entry.memo, amount: entry.amount, isIncome: entry.isIncome))
        #expect(note.item == "焼肉")
        #expect(ReplyTexts.note(for: note) == "¥12,000 を4人で割り勘。立て替えた ¥9,000 はメモに残しました。")
        let csv = LedgerCSVWriter.text([entry], language: .japanese, timeZone: TestSupport.calendar.timeZone)
        #expect(csv.contains(memo))
    }

    /// 直すシートでメモを直すと、説明を書き足した形でなくなるので、メモをそのまま見出しにする（言い換えない）。金額だけを直した
    /// ときも、説明の額と合わなくなるので同じ。
    @Test("メモか金額を直した割り勘の記録は、説明を読まない")
    func editedSplitIsNotRead() async throws {
        let fixture = try Fixture()
        await fixture.send("昨日 焼肉12000 4人で割り勘")
        let entry = try #require(try fixture.entries().first)

        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        let amountEdit = try #require(fixture.model.editing)
        amountEdit.amountText = "3,500"
        #expect(amountEdit.save())
        #expect(EntryMemoNote(memo: entry.memo, amount: entry.amount, isIncome: entry.isIncome) == nil)

        fixture.model.presentEdit(entry, calendar: TestSupport.calendar)
        let memoEdit = try #require(fixture.model.editing)
        memoEdit.amountText = "3,000"
        memoEdit.memo = "焼肉（5人で割り勘）"
        #expect(memoEdit.save())
        #expect(EntryMemoNote(memo: entry.memo, amount: entry.amount, isIncome: entry.isIncome) == nil)
    }
}
