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
