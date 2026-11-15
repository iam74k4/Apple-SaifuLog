import Foundation
import Testing
@testable import SaifuLogCore

/// 月のまとめの数字を AI に渡す文（RecapFacts）と、AI の一言の照合（AnswerSentenceCheck。質問の一言と同じもの）。
/// Fixture の今日は 2026-09-28 12:00（日本時間、月曜）。
@Suite("月のまとめの AI に渡す文と一言の照合")
struct RecapFactsTests {
    static func monthlyFacts(_ records: [TestRecord], month: Date = Fixture.date(2026, 9, 1), budget: Int? = nil) throws -> String? {
        let report = try #require(MonthlyReport(
            records: records, month: month, now: Fixture.now, budget: budget, budgetDecidedAt: Fixture.date(2026, 8, 1),
            calendar: Fixture.calendar
        ))
        return RecapFacts.text(for: report, calendar: Fixture.calendar)
    }

    @Test("月のまとめの文には、期間・合計・上位カテゴリ・予算を書く（収入があれば収支も。画面に無い平均と目安は書かない）")
    func monthlyFactsText() throws {
        let records = [
            TestRecord(amount: 28_000, category: .food, spentAt: Fixture.date(2026, 9, 10)),
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25)),
            TestRecord(amount: 20_000, category: .food, spentAt: Fixture.date(2026, 8, 10)),
        ]

        let facts = try #require(try Self.monthlyFacts(records, budget: 100_000))

        #expect(facts.contains("今月（2026年9月1日から2026年9月30日まで。まだ月の途中）"))
        #expect(facts.contains("支出の合計: ¥28,000（支出の記録 1件）"))
        #expect(facts.contains("収入の合計: ¥250,000"))
        #expect(facts.contains("収支: +¥222,000（収入が支出より多い）"))
        #expect(!facts.contains("1日あたり"))
        // 今月は途中なので、前の月との差は書かない（画面にも出さない）。
        #expect(!facts.contains("前の月"))
        #expect(facts.contains("食費 ¥28,000（100%）"))
        #expect(facts.contains("月の予算: ¥100,000 のうち ¥28,000 を使い、残りは ¥72,000"))
        #expect(!facts.contains("目安"))
        // 確かめられない数え方の数字は書かない（書くと、一言の同じ数え方の数字を通してしまう）。
        #expect(AnswerSentenceCheck.numbers(in: facts)[.other].isEmpty)
        #expect(AnswerSentenceCheck.accepts("今月は黒字で、予算の残りは¥72,000です。", facts: facts))
        #expect(!AnswerSentenceCheck.accepts("今月は赤字です。", facts: facts))
    }

    @Test("収入の記録が無い月は、収支を書かない（支出だけをつける人に赤字と書かせない）")
    func monthlyFactsWithoutIncome() throws {
        let facts = try #require(try Self.monthlyFacts([TestRecord(amount: 5_000, spentAt: Fixture.date(2026, 8, 10))],
                                                       month: Fixture.date(2026, 8, 1)))

        #expect(facts.contains("期間: 2026年8月1日から2026年8月31日まで"))
        #expect(!facts.contains("収支"))
        #expect(!AnswerSentenceCheck.accepts("先月は赤字でした。", facts: facts))
    }

    @Test("終わった月には、前の月との差を書く")
    func monthlyFactsWithPreviousMonth() throws {
        let facts = try #require(try Self.monthlyFacts([
            TestRecord(amount: 20_000, spentAt: Fixture.date(2026, 8, 10)),
            TestRecord(amount: 10_000, spentAt: Fixture.date(2026, 7, 10)),
        ], month: Fixture.date(2026, 8, 1)))

        #expect(facts.contains("前の月（¥10,000）より ¥10,000 多い"))
    }

    @Test("記録の無い月は、AI に渡す文を作らない")
    func noMonthlyFactsForEmptyMonth() throws {
        #expect(try Self.monthlyFacts([]) == nil)
    }
}
