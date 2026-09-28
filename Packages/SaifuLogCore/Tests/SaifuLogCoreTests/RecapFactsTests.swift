import Foundation
import Testing
@testable import SaifuLogCore

/// ふりかえりの数字を AI に渡す文（RecapFacts）と、AI の一言の照合（AnswerSentenceCheck。質問の一言と同じもの）。
/// Fixture の今日は 2026-09-28 12:00（日本時間、月曜）で、月曜始まりの先週は 9/21〜9/27。
@Suite("ふりかえりの AI に渡す文と一言の照合")
struct RecapFactsTests {
    static let calendar = Fixture.calendar(firstWeekday: 2)

    /// 先週 ¥12,300（食費 ¥6,000・カフェ ¥3,000・交通 ¥1,500・日用品 ¥1,800）、前の週 ¥14,400。
    static let records = [
        TestRecord(amount: 14_400, category: .food, spentAt: Fixture.date(2026, 9, 16, hour: 12)),
        TestRecord(amount: 4_000, category: .food, spentAt: Fixture.date(2026, 9, 23, hour: 19)),
        TestRecord(amount: 2_000, category: .food, spentAt: Fixture.date(2026, 9, 21, hour: 12)),
        TestRecord(amount: 3_000, category: .cafe, spentAt: Fixture.date(2026, 9, 22, hour: 9)),
        TestRecord(amount: 1_500, category: .transport, spentAt: Fixture.date(2026, 9, 24, hour: 8)),
        TestRecord(amount: 1_800, category: .daily, spentAt: Fixture.date(2026, 9, 26, hour: 15)),
    ]

    static func weeklyFacts(budget: Int? = 150_000) throws -> String {
        let recap = try #require(WeeklyRecap(
            records: records, now: Fixture.now, budget: budget, budgetDecidedAt: Fixture.date(2026, 9, 1), calendar: calendar
        ))
        return try #require(RecapFacts.text(for: recap, calendar: calendar))
    }

    // MARK: - 先週

    @Test("先週の文には、期間・合計・前の週との差・上位 3 カテゴリ・いちばん使った日・記録のある日・週の目安を書く")
    func weeklyFactsText() throws {
        let facts = try Self.weeklyFacts()

        #expect(facts.contains("期間: 先週の1週間（2026年9月21日から2026年9月27日まで）"))
        // 週の日数（7日間）は書かない（記録のある日が 5 日なのに「7日とも」を通さないため）。
        #expect(!facts.contains("日間"))
        #expect(AnswerSentenceCheck.numbers(in: facts)[.days] == [5])
        // 「1週間」の 1 は週の数で、ほかの数え方の数字は書かない（書くと、一言の「1割」「1か月」などを通してしまう）。
        #expect(AnswerSentenceCheck.numbers(in: facts)[.weeks] == [1])
        #expect(AnswerSentenceCheck.numbers(in: facts)[.other].isEmpty)
        #expect(facts.contains("支出の合計: ¥12,300（支出の記録 5件）"))
        #expect(facts.contains("前の週（¥14,400）より ¥2,100 少ない"))
        #expect(facts.contains("食費 ¥6,000（49%）、カフェ ¥3,000（24%）、日用品 ¥1,800（15%）"))
        #expect(!facts.contains("交通"))
        #expect(facts.contains("いちばん多く使った日: 2026年9月23日（¥4,000）"))
        #expect(facts.contains("記録のある日: 5日"))
        #expect(facts.contains("週の予算の目安（月の予算を日割りした額）: ¥35,000（目安より ¥22,700 少ない）"))
    }

    @Test("予算が無ければ、週の目安を書かない")
    func weeklyFactsWithoutBudget() throws {
        #expect(!(try Self.weeklyFacts(budget: nil)).contains("目安"))
    }

    @Test("前の週に支出が無ければ、比べられないと書く")
    func weeklyFactsWithoutPreviousWeek() throws {
        let recap = try #require(WeeklyRecap(records: Array(Self.records.dropFirst()), now: Fixture.now, calendar: Self.calendar))

        #expect(try #require(RecapFacts.text(for: recap, calendar: Self.calendar)).contains("比べられない"))
    }

    @Test("記録が無かった週は、AI に渡す文を作らない")
    func noFactsForEmptyWeek() throws {
        let recap = try #require(WeeklyRecap(records: [TestRecord](), now: Fixture.now, calendar: Self.calendar))

        #expect(RecapFacts.text(for: recap, calendar: Self.calendar) == nil)
    }

    @Test("先週の文にある数字だけの一言は使う", arguments: [
        "先週は¥12,300で、前の週より¥2,100少なめでした。よく続けられています。",
        "食費が¥6,000といちばん多く、全体の49%でした。",
        "先週は5日記録できました。この調子です。",
        "9月23日の¥4,000がいちばん大きな出費でした。",
        "週の目安¥35,000より¥22,700少なく、ゆとりのある一週間でした。",
        "一週間おつかれさまでした。無理なく続けていきましょう。",
        "この1週間で¥12,300でした。",
    ])
    func acceptsSentenceWithFactNumbers(sentence: String) throws {
        #expect(AnswerSentenceCheck.accepts(sentence, facts: try Self.weeklyFacts()))
    }

    @Test("先週の文に無い数字や、収支の向きを書いた一言は捨てる", arguments: [
        "先週は¥13,000でした。",
        "前の週より¥2,000少なめでした。",
        "今月もあと3日です。",
        "食費が半分の50%でした。",
        "9月24日がいちばん使った日でした。",
        "先週は黒字でした。",
        "",
        // 結果の文の「1週間」の 1 を、別の数え方（割・人・か月・位・時）の 1 として通さない。
        "食費が1割でした。",
        "食費が一割でした。",
        "一人でよく頑張りました。",
        "1か月続きました。",
        "1位は食費でした。",
        "1時に使いました。",
        // 週の数も、結果の文と同じ数だけ通す。
        "2週続けて減りました。",
        "二週間続けて減りました。",
        // 週の日数（7）は結果の文に書かないので、記録のある日（5日）と合わない「7日とも」は通さない。
        "7日とも記録できました。",
    ])
    func rejectsSentenceWithOtherNumbers(sentence: String) throws {
        #expect(!AnswerSentenceCheck.accepts(sentence, facts: try Self.weeklyFacts()))
    }

    // MARK: - 月のまとめ

    static func monthlyFacts(_ records: [TestRecord], month: Date = Fixture.date(2026, 9, 1), budget: Int? = nil) throws -> String? {
        let report = try #require(MonthlyReport(
            records: records, month: month, now: Fixture.now, budget: budget, budgetDecidedAt: Fixture.date(2026, 8, 1),
            calendar: Fixture.calendar
        ))
        return RecapFacts.text(for: report, calendar: Fixture.calendar)
    }

    @Test("月のまとめの文には、期間・合計・平均・前の月との差・上位カテゴリ・予算を書く（収入があれば収支も）")
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
        #expect(facts.contains("1日あたりの平均の支出: ¥1,000（28日で割った額）"))
        #expect(facts.contains("前の月（¥20,000）より ¥8,000 多い"))
        #expect(facts.contains("食費 ¥28,000（100%）"))
        #expect(facts.contains("月の予算: ¥100,000 のうち ¥28,000 を使い、残りは ¥72,000"))
        #expect(facts.contains("今日までの予算の目安: ¥93,333（目安より ¥65,333 少ない）"))
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

    @Test("記録の無い月は、AI に渡す文を作らない")
    func noMonthlyFactsForEmptyMonth() throws {
        #expect(try Self.monthlyFacts([]) == nil)
    }
}
