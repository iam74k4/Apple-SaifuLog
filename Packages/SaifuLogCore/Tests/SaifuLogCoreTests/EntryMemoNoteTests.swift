import Foundation
import Testing
@testable import SaifuLogCore

/// 解析がメモに書き足した説明の読み戻し（`EntryMemoNote`）。書く側（`ParsedEntry.assemble`・解析の結果）の出力をそのまま読み戻せる
/// ことと、少しでも違う形（利用者が直したメモ）は読まないことを確かめる。
@Suite("メモに書き足した説明の読み戻し")
struct EntryMemoNoteTests {
    func note(_ entry: ParsedEntry) -> EntryMemoNote? {
        EntryMemoNote(memo: entry.memo, amount: entry.amount, isIncome: entry.isIncome)
    }

    @Test("割り勘の記録は、書いた形のまま品目と割り勘に読み戻せる（桁区切り・割り切れない額・品目の無いメモも）", arguments: [
        ("焼肉", 12_000, 4),
        ("焼肉", 1_000, 3),
        ("飲み会 渋谷", 1_234_567, 7),
        ("セブン11", 999, 2),
        ("旅行", 100_000_000, 100),
        ("", 12_000, 4),
        ("", 1_000, 3),
    ])
    func splitRoundTrips(item: String, total: Int, count: Int) throws {
        let entry = ParsedEntry.assemble(
            total: total, category: .food, isIncome: false, item: item, daysAgo: 0, splitCount: count
        )
        let split = try #require(BillSplit(total: total, count: count))
        let read = try #require(note(entry), "読み戻せません: \(entry.memo)")
        #expect(read.item == item)
        #expect(read.kind == .split(split))
    }

    @Test("1 人分の記録は、割り勘の人数とともに読み戻せる", arguments: [
        ("焼肉", 4, 4 as Int?),
        ("焼肉", 1, nil),
        ("", 4, 4),
        ("", 1, nil),
    ])
    func perPersonRoundTrips(item: String, splitCount: Int, expected: Int?) throws {
        let entry = ParsedEntry.assemble(
            total: 3_000, category: .food, isIncome: false, item: item, daysAgo: 0, splitCount: splitCount, isPerPerson: true
        )
        let read = try #require(note(entry), "読み戻せません: \(entry.memo)")
        #expect(read.item == item)
        #expect(read.kind == .perPerson(splitCount: expected))
    }

    /// 解析（キーワード辞書）が書いたメモも、同じように読み戻せる（全角の括弧と「¥12,000」の桁区切りを含む）。
    @Test("解析の書いたメモをそのまま読み戻せる", arguments: [
        ("昨日 焼肉12000 4人で割り勘", "焼肉", EntryMemoNote.Kind.split(BillSplit(total: 12_000, count: 4)!)),
        ("1000 3人で割り勘", "", .split(BillSplit(total: 1_000, count: 3)!)),
        ("飲み会 1万2千500円 5人で割り勘", "飲み会", .split(BillSplit(total: 12_500, count: 5)!)),
        ("焼肉 12000 4人で割り勘 1人3000", "焼肉", .perPerson(splitCount: 4)),
        ("焼肉 12000 ひとり3000", "焼肉", .perPerson(splitCount: nil)),
        ("4人で割り勘 1人あたり3000円", "", .perPerson(splitCount: 4)),
    ])
    func readsParserMemos(input: String, item: String, kind: EntryMemoNote.Kind) throws {
        let entry = try #require(Fixture.parser.entries(from: input).first)
        let read = try #require(note(entry), "読み戻せません: \(entry.memo)")
        #expect(read.item == item)
        #expect(read.kind == kind)
    }

    /// AI の読み取りを突き合わせた結果も同じ組み立てを通るので、同じように読み戻せる。
    @Test("AI の読み取りの突き合わせの結果も読み戻せる")
    func readsResolvedAIMemo() throws {
        let extracted = ExtractedEntry(
            item: "焼肉", amountText: "12000", categoryName: "食費", isIncome: false, splitCount: 4, dateText: "昨日"
        )
        let entry = try extracted.resolved(against: "昨日 焼肉12000 4人で割り勘", now: Fixture.now, calendar: Fixture.calendar)
        let read = try #require(note(entry))
        #expect(read.item == "焼肉")
        #expect(read.kind == .split(BillSplit(total: 12_000, count: 4)!))
    }

    /// 利用者が直したメモ（書く形と少しでも違うもの）や、金額・収入を直した記録は読まない（メモをそのまま出す）。
    @Test("書く形と違うメモは読まない", arguments: [
        ("焼肉（4人で割り勘）", 3_000),
        ("焼肉（4人で割り勘・総額 12,000・立替 ¥9,000）", 3_000),
        ("焼肉（4人で割り勘・総額 ¥12000・立替 ¥9000）", 3_000),
        ("焼肉（4人で割り勘・総額 ¥1,2000・立替 ¥9,000）", 3_000),
        ("焼肉(4人で割り勘・総額 ¥12,000・立替 ¥9,000)", 3_000),
        ("焼肉（4人で割り勘・総額 ¥12,000・立替 ¥8,000）", 3_000),
        ("焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）", 3_500),
        ("焼肉 （4人で割り勘・総額 ¥12,000・立替 ¥9,000）", 3_000),
        ("（4人で割り勘・総額 ¥12,000・立替 ¥9,000）", 3_000),
        ("焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）おいしかった", 3_000),
        ("焼肉（04人で割り勘・総額 ¥12,000・立替 ¥9,000）", 3_000),
        ("焼肉（1人で割り勘・総額 ¥12,000・立替 ¥0）", 12_000),
        ("焼肉（1人で割り勘・1人分）", 3_000),
        ("焼肉（4人で割り勘・2人分）", 3_000),
        ("焼肉（１人分）", 3_000),
        ("4人で割り勘・総額 ¥12,000・立替 ¥9,000 ", 3_000),
        ("ランチ", 850),
        ("", 850),
        ("牛乳（1L）", 198),
        ("25日分", 1_000),
        ("ロト7", 300),
    ])
    func rejectsOtherMemos(memo: String, amount: Int) {
        #expect(EntryMemoNote(memo: memo, amount: amount, isIncome: false) == nil)
    }

    @Test("収入に直した記録の説明は読まない")
    func rejectsIncome() {
        #expect(EntryMemoNote(memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）", amount: 3_000, isIncome: true) == nil)
        #expect(EntryMemoNote(memo: "焼肉（1人分）", amount: 3_000, isIncome: true) == nil)
    }
}
