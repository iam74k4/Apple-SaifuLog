import Foundation
import Testing
@testable import SaifuLogCore

@Suite("記録の返事の一言に渡す文")
struct RecordFactsTests {
    private static func record(_ amount: Int, _ category: EntryCategory, day: Int = 28, isIncome: Bool = false) -> LedgerRecordValue {
        LedgerRecordValue(amount: amount, isIncome: isIncome, category: category, spentAt: Fixture.date(2026, 9, day, hour: 9))
    }

    private static let month = [
        record(450, .cafe, day: 3),
        record(500, .cafe, day: 20),
        record(1_200, .food, day: 21),
        record(250_000, .other, day: 25, isIncome: true),
        // 先月の記録は数えない。
        LedgerRecordValue(amount: 9_999, category: .cafe, spentAt: Fixture.date(2026, 8, 31, hour: 9)),
    ]

    @Test("いま記録した支出・そのカテゴリの今月の合計と件数・今月の支出の合計・予算の残りを書く")
    func writesFacts() throws {
        let records = Self.month + [Self.record(480, .cafe)]

        let text = try #require(RecordFacts.text(
            recorded: [RecordFacts.Item(item: "カフェラテ", amount: 480, category: .cafe)],
            monthRecords: records, budget: 100_000, now: Fixture.now, calendar: Fixture.calendar
        ))

        #expect(text == """
            いま記録した支出: 「カフェラテ」 ¥480（カフェ）
            今月のカフェ: ¥1,430（記録 3件）
            今月の支出の合計: ¥2,630（支出の記録 4件）
            月の予算: ¥100,000 のうち ¥2,630 を使い、残りは ¥97,370
            """)
    }

    @Test("品目は「」で囲み、品目の中の「」は外す（照合で、利用者が書いた語から向きを読まないため）")
    func quotesItems() throws {
        let text = try #require(RecordFacts.text(
            recorded: [RecordFacts.Item(item: "「特売」の卵", amount: 250, category: .food)],
            monthRecords: [Self.record(250, .food)], budget: nil, now: Fixture.now, calendar: Fixture.calendar
        ))
        #expect(text.hasPrefix("いま記録した支出: 「特売の卵」 ¥250（食費）"))
    }

    @Test("予算を超えていれば超えた額。予算が無ければ書かない。その他のカテゴリの合計は書かない。品目が無ければカテゴリの名前")
    func overBudgetAndOther() throws {
        let records = Self.month + [Self.record(3_000, .other)]
        let item = RecordFacts.Item(item: "", amount: 3_000, category: .other)

        let over = try #require(RecordFacts.text(
            recorded: [item], monthRecords: records, budget: 5_000, now: Fixture.now, calendar: Fixture.calendar
        ))
        #expect(over == """
            いま記録した支出: その他 ¥3,000（その他）
            今月の支出の合計: ¥5,150（支出の記録 4件）
            月の予算: ¥5,000 を ¥150 超えている
            """)

        let noBudget = try #require(RecordFacts.text(
            recorded: [item], monthRecords: records, budget: nil, now: Fixture.now, calendar: Fixture.calendar
        ))
        #expect(!noBudget.contains("予算"))
    }

    @Test("支出を記録していなければ書かない。AI の一言は、文に書いた数字だけで照合に通る")
    func emptyAndCheck() throws {
        #expect(RecordFacts.text(
            recorded: [], monthRecords: Self.month, budget: nil, now: Fixture.now, calendar: Fixture.calendar
        ) == nil)

        let text = try #require(RecordFacts.text(
            recorded: [RecordFacts.Item(item: "カフェラテ", amount: 480, category: .cafe)],
            monthRecords: Self.month + [Self.record(480, .cafe)], budget: nil, now: Fixture.now, calendar: Fixture.calendar
        ))
        #expect(AnswerSentenceCheck.accepts("今月のカフェは3件目です。", facts: text))
        #expect(!AnswerSentenceCheck.accepts("今月のカフェは5件目です。", facts: text))
    }
}
