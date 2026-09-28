import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

struct EntryTests {
    private let calendar = TestSupport.calendar

    /// 1 回の送信を複数件に分けたときは、書いた順に並ぶよう記録の日時をずらす。
    @Test func recordsKeepWrittenOrder() {
        let parsed = [
            ParsedEntry(amount: 2_480, category: .food, memo: "スーパー"),
            ParsedEntry(amount: 1_200, category: .daily, memo: "ドラッグ"),
        ]

        let records = Entry.records(
            from: parsed, originalText: "スーパー2480、ドラッグ1200", source: .text,
            now: TestSupport.now, calendar: calendar
        )

        #expect(records.map(\.memo) == ["スーパー", "ドラッグ"])
        #expect(records[0].createdAt < records[1].createdAt)
        #expect(records.allSatisfy { $0.originalText == "スーパー2480、ドラッグ1200" })
        #expect(records.allSatisfy { calendar.isDate($0.spentAt, inSameDayAs: TestSupport.now) })
    }

    /// 日時の振り方はコアの `ParsedEntry.timestamps` のとおりにする（アプリ側で独自にずらさない）。
    /// 昨日や少し先の日付の件も、使った日時がその日になり、記録した日時は書いた順に並ぶ。
    @Test func recordsUseCoreTimestamps() {
        let parsed = [
            ParsedEntry(amount: 12_000, category: .food, memo: "焼肉", daysAgo: 1),
            ParsedEntry(amount: 80_000, category: .other, memo: "家賃", daysAgo: -1),
            ParsedEntry(amount: 850, category: .food, memo: "ランチ"),
        ]

        let records = Entry.records(
            from: parsed, originalText: "昨日 焼肉12000、9/29 家賃 80000、ランチ 850", source: .text,
            now: TestSupport.now, calendar: calendar
        )
        let expected = ParsedEntry.timestamps(for: parsed, now: TestSupport.now, calendar: calendar)

        #expect(records.map(\.createdAt) == expected.map(\.createdAt))
        #expect(records.map(\.spentAt) == expected.map(\.spentAt))
        #expect(records.map(\.createdAt) == records.map(\.createdAt).sorted())
        #expect(calendar.isDate(records[0].spentAt, inSameDayAs: TestSupport.date(2026, 9, 27)))
        #expect(calendar.isDate(records[1].spentAt, inSameDayAs: TestSupport.date(2026, 9, 29)))
    }

    /// 今年でない記録には年を添える。年なしだと去年の記録が今年の記録に見え、今月の合計に入らない理由が分からない。
    @Test(arguments: [
        (TestSupport.date(2026, 9, 26), false),
        (TestSupport.date(2026, 1, 1), false),
        (TestSupport.date(2025, 9, 29), true),
        (TestSupport.date(2027, 1, 5), true),
    ])
    func showsYearOnlyOutsideThisYear(spentAt: Date, showsYear: Bool) {
        let entry = TestSupport.entry(spentAt: spentAt)
        #expect(entry.showsYear(today: TestSupport.now, calendar: calendar) == showsYear)
    }

    @Test func summaryTextUsesMemoAndAmount() {
        #expect(TestSupport.entry(amount: 12_000, memo: "焼肉").summaryText == "焼肉 ¥12,000")
    }
}
