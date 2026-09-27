import Testing
@testable import SaifuLogCore

@Suite("AI の出力の突き合わせ")
struct ExtractedEntryTests {
    func extracted(
        item: String = "焼肉",
        amount: String = "12000",
        category: String = "食費",
        isIncome: Bool = false,
        split: Int = 1,
        date: String = ""
    ) -> ExtractedEntry {
        ExtractedEntry(
            item: item, amountText: amount, categoryName: category,
            isIncome: isIncome, splitCount: split, dateText: date
        )
    }

    func resolve(_ entry: ExtractedEntry, _ input: String) throws -> ParsedEntry {
        try entry.resolved(against: input, now: Fixture.now, calendar: Fixture.calendar)
    }

    @Test("入力に書かれた値はそのまま使い、割り算はコードで行う")
    func groundedValues() throws {
        let entry = try resolve(extracted(split: 4, date: "昨日"), "昨日 焼肉12000 4人で割り勘")
        #expect(entry == ParsedEntry(
            amount: 3_000, category: .food, memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）",
            daysAgo: 1, splitCount: 4
        ))
    }

    @Test("入力に無い金額（計算した値）は使わない")
    func ungroundedAmountThrows() {
        #expect(throws: ExtractedEntry.ResolveError.ungroundedAmount) {
            try resolve(extracted(amount: "3000", split: 4), "昨日 焼肉12000 4人で割り勘")
        }
    }

    @Test("割り勘の語か人数が入力に無ければ、人数を返されても割らない", arguments: [
        ("焼肉 12000 割り勘", 2),
        ("4人で焼肉 12000", 4),
        ("焼肉12000 4人で割り勘", 3),
    ])
    func ungroundedSplitIsIgnored(input: String, split: Int) throws {
        let entry = try resolve(extracted(split: split), input)
        #expect(entry.amount == 12_000)
        #expect(entry.splitCount == 1)
    }

    @Test("入力に無い日付の表記は使わず、入力そのものから読む", arguments: [
        ("昨日", "焼肉 12000", 0),
        ("昨日", "一昨日 焼肉 12000", 2),
        ("", "昨日 焼肉 12000", 1),
        ("9/20", "9/26 焼肉 12000", 2),
    ])
    func ungroundedDateFallsBackToInput(date: String, input: String, daysAgo: Int) throws {
        #expect(try resolve(extracted(date: date), input).daysAgo == daysAgo)
    }

    @Test("日付が複数ある入力では、件ごとの日付の表記を使う")
    func perEntryDate() throws {
        let input = "昨日スーパー2480、今日ドラッグ1200"
        let first = try resolve(extracted(item: "スーパー", amount: "2480", date: "昨日"), input)
        let second = try resolve(extracted(item: "ドラッグ", amount: "1200", category: "日用品", date: "今日"), input)
        #expect(first.daysAgo == 1)
        #expect(second.daysAgo == 0)
    }

    @Test("知らないカテゴリ名はその他にする")
    func unknownCategory() throws {
        #expect(try resolve(extracted(category: "外食"), "焼肉 12000").category == .other)
    }
}
