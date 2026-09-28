import Testing
@testable import SaifuLogCore

@Suite("記録の組み立て")
struct ParsedEntryTests {
    @Test("割り勘は 1 人分に割り、総額と立替額をメモに残す")
    func assemblesSplit() {
        let entry = ParsedEntry.assemble(
            total: 12_000, category: .food, isIncome: false, item: "焼肉", daysAgo: 1, splitCount: 4
        )
        #expect(entry == ParsedEntry(
            amount: 3_000, category: .food, memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）",
            daysAgo: 1, splitCount: 4
        ))
    }

    @Test("品目が無い割り勘はメモが説明だけになる")
    func assemblesSplitWithoutItem() {
        let entry = ParsedEntry.assemble(
            total: 1_000, category: .other, isIncome: false, item: " ", daysAgo: 0, splitCount: 3
        )
        #expect(entry.amount == 334)
        #expect(entry.memo == "3人で割り勘・総額 ¥1,000・立替 ¥666")
    }

    @Test("収入は割らず、カテゴリはその他にする")
    func incomeIgnoresSplitAndCategory() {
        let entry = ParsedEntry.assemble(
            total: 250_000, category: .food, isIncome: true, item: "給料", daysAgo: 0, splitCount: 4
        )
        #expect(entry == ParsedEntry(amount: 250_000, category: .other, isIncome: true, memo: "給料"))
    }

    @Test("使った日時は何日前かから決まる")
    func dateRelativeToNow() {
        let entry = ParsedEntry(amount: 850, category: .food, daysAgo: 1)
        #expect(entry.date(relativeTo: Fixture.now, calendar: Fixture.calendar) == Fixture.date(2026, 9, 27, hour: 12))
    }
}
