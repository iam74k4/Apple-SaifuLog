import Foundation
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

    @Test("1 人分として書かれた額は割らず、割り勘の人数とともに 1 人分とメモに書き足す", arguments: [
        ("焼肉", 4, "焼肉（4人で割り勘・1人分）"),
        ("焼肉", 1, "焼肉（1人分）"),
        ("", 4, "4人で割り勘・1人分"),
    ])
    func assemblesPerPersonAmount(item: String, splitCount: Int, memo: String) {
        let entry = ParsedEntry.assemble(
            total: 3_000, category: .food, isIncome: false, item: item, daysAgo: 0, splitCount: splitCount,
            isPerPerson: true
        )
        #expect(entry == ParsedEntry(amount: 3_000, category: .food, memo: memo))
    }

    @Test("収入は割らず、カテゴリはその他にする")
    func incomeIgnoresSplitAndCategory() {
        let entry = ParsedEntry.assemble(
            total: 250_000, category: .food, isIncome: true, item: "給料", daysAgo: 0, splitCount: 4
        )
        #expect(entry == ParsedEntry(amount: 250_000, category: .other, isIncome: true, memo: "給料"))
    }

    @Test("使った日時は何日前かから決まる（負の数は未来の日）")
    func dateRelativeToNow() {
        let entry = ParsedEntry(amount: 850, category: .food, daysAgo: 1)
        #expect(entry.date(relativeTo: Fixture.now, calendar: Fixture.calendar) == Fixture.date(2026, 9, 27, hour: 12))
        let rent = ParsedEntry(amount: 80_000, category: .other, daysAgo: -1)
        #expect(rent.date(relativeTo: Fixture.now, calendar: Fixture.calendar) == Fixture.date(2026, 9, 29, hour: 12))
    }

    @Test("1 回の送信で読んだ複数件は、書いた順に並ぶよう記録した日時を 1 ミリ秒ずつずらす")
    func timestampsKeepWrittenOrder() {
        let entries = [
            ParsedEntry(amount: 2_480, category: .food, memo: "スーパー", daysAgo: 1),
            ParsedEntry(amount: 1_200, category: .daily, memo: "ドラッグ", daysAgo: 1),
            ParsedEntry(amount: 850, category: .food, memo: "ランチ"),
        ]
        let timestamps = ParsedEntry.timestamps(for: entries, now: Fixture.now, calendar: Fixture.calendar)
        #expect(timestamps.map(\.createdAt) == [
            Fixture.now, Fixture.now.addingTimeInterval(0.001), Fixture.now.addingTimeInterval(0.002),
        ])
        #expect(timestamps.map(\.spentAt) == [
            Fixture.date(2026, 9, 27, hour: 12),
            Fixture.date(2026, 9, 27, hour: 12).addingTimeInterval(0.001),
            Fixture.now.addingTimeInterval(0.002),
        ])
        #expect(timestamps.map(\.createdAt) == timestamps.map(\.createdAt).sorted())
        #expect(ParsedEntry.timestamps(for: [], now: Fixture.now, calendar: Fixture.calendar).isEmpty)
    }
}
