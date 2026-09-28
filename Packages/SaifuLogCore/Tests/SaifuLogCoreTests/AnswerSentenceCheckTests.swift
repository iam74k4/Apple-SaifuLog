import Foundation
import Testing
@testable import SaifuLogCore

/// AI の一言の数字の照合（AnswerSentenceCheck）と、AI に渡すツールの結果の文（LedgerAnswerFacts）。
@Suite("AI の一言の数字の照合")
struct AnswerSentenceCheckTests {
    /// 今月のカフェの支出 ¥3,200（5 件）。
    static let cafeAnswer = LedgerAnswer(
        question: LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe),
        period: .thisMonth,
        interval: DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)),
        recordCount: 5,
        value: .amount(3_200)
    )

    static var cafeFacts: String {
        LedgerAnswerFacts.text(for: cafeAnswer, calendar: Fixture.calendar)
    }

    @Test("ツールの結果の文には、期間・知りたいこと・結果・件数を書く")
    func factsText() {
        let facts = Self.cafeFacts

        #expect(facts.contains("今月（2026年9月1日から2026年9月30日まで）"))
        #expect(facts.contains("カフェの支出の合計"))
        #expect(facts.contains("¥3,200"))
        #expect(facts.contains("5件"))
    }

    @Test("予算を月で数えたときは、聞かれた期間も書く")
    func factsMentionsAskedPeriod() {
        let answer = LedgerAnswer(
            question: LedgerQuestion(period: .thisYear, metric: .remainingBudget),
            period: .thisMonth,
            interval: DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)),
            recordCount: 3,
            value: .noBudget
        )

        let facts = LedgerAnswerFacts.text(for: answer, calendar: Fixture.calendar)

        #expect(facts.contains("聞かれた期間: 今年"))
        #expect(facts.contains("月の予算が決まっていない"))
    }

    @Test("ツールの結果にある数字だけなら使う", arguments: [
        "今月のカフェは¥3,200でした。",
        "今月はカフェに3200円使いました（5件）。",
        "カフェの支出は ¥3,200 です。",
        "今月のカフェ代は3,200円で、5回分です。",
        "カフェには３２００円使っています。",
        "9月のカフェは¥3,200でした。",
        "今月はカフェに一番使ったわけではありません。",
        "今月のカフェの支出をまとめました。",
        "今月はカフェに三千二百円使いました。",
        "2026年9月のカフェは¥3,200でした。",
        "9月30日までのカフェは¥3,200です。",
        "9/1から9/30までのカフェは¥3,200です。",
        "今月のカフェは5回で¥3,200でした。",
        "今月のカフェは十分に使っています。",
    ])
    func accepts(sentence: String) {
        #expect(AnswerSentenceCheck.accepts(sentence, facts: Self.cafeFacts), "\(sentence)")
    }

    @Test("ツールの結果に無い数字があれば使わない", arguments: [
        "今月のカフェは¥3,500でした。",
        "今月のカフェは¥32,000でした。",
        "カフェに1日あたり640円使っています。",
        "今月のカフェは¥5でした。",
        "今月はカフェに三千五百円使いました。",
        "今月はカフェに千円使いました。",
        "カフェは支出の12.5%です。",
        "カフェは6件でした。",
        "今月のカフェは¥3,200で、先月より¥800多いです。",
        "カフェの支出は1234567890123円です。",
        // 期間の日付（2026年9月1日から9月30日）の数字を、件数や種類の無い数字として書いたもの。
        "カフェは30件でした。",
        "収入が9件ありました。",
        "カフェは2026件でした。",
        "カフェは1件でした。",
        "カフェは30でした。",
        "今月のカフェは¥3,200で、30日間の合計です。",
        // 結果の文に無い数え方。
        "カフェには5人で行きました。",
        // 収支ではない答えに、向きを書いたもの。
        "今月のカフェは¥3,200の赤字です。",
        "今月のカフェは-¥3,200です。",
    ])
    func rejects(sentence: String) {
        #expect(!AnswerSentenceCheck.accepts(sentence, facts: Self.cafeFacts), "\(sentence)")
    }

    static func balanceFacts(_ balance: Int) -> String {
        let answer = LedgerAnswer(
            question: LedgerQuestion(period: .thisMonth, metric: .balance),
            period: .thisMonth,
            interval: DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)),
            recordCount: 2,
            value: .balance(balance)
        )
        return LedgerAnswerFacts.text(for: answer, calendar: Fixture.calendar)
    }

    @Test("収支が黒字なら、黒字の向きの一言だけ使う（数字が合っていても、逆の向きは使わない）")
    func surplusDirection() {
        let facts = Self.balanceFacts(3_000)

        for sentence in ["今月は¥3,000の黒字です。", "今月は+¥3,000でした。", "収入が支出より¥3,000多いです。", "今月の収支は¥3,000のプラスです。",
                         "支出が収入より¥3,000少ないです。", "今月の収支は¥3,000です。"] {
            #expect(AnswerSentenceCheck.accepts(sentence, facts: facts), "\(sentence)")
        }
        for sentence in ["今月は¥3,000の赤字です。", "今月は-¥3,000です", "今月は3,000円のマイナスです。", "支出が収入より¥3,000多いです。",
                         "今月は¥-3,000です。", "収入が支出より¥3,000少ないです。", "収入と支出が同じです。", "支出の方が多いです。"] {
            #expect(!AnswerSentenceCheck.accepts(sentence, facts: facts), "\(sentence)")
        }
    }

    @Test("収支が赤字なら、赤字の向きの一言だけ使う")
    func deficitDirection() {
        let facts = Self.balanceFacts(-3_000)

        for sentence in ["今月は¥3,000の赤字です。", "今月は-¥3,000でした。", "支出が収入より¥3,000多いです。", "3,000円のマイナスです。"] {
            #expect(AnswerSentenceCheck.accepts(sentence, facts: facts), "\(sentence)")
        }
        for sentence in ["今月は¥3,000の黒字です。", "今月は+¥3,000でした。", "収入が支出より¥3,000多いです。"] {
            #expect(!AnswerSentenceCheck.accepts(sentence, facts: facts), "\(sentence)")
        }
    }

    @Test("収支が 0 なら、黒字や赤字と書いた一言は使わない")
    func evenDirection() {
        let facts = Self.balanceFacts(0)

        #expect(AnswerSentenceCheck.accepts("今月は収入と支出が同じです。", facts: facts))
        #expect(AnswerSentenceCheck.accepts("今月の収支は¥0です。", facts: facts))
        #expect(!AnswerSentenceCheck.accepts("今月は¥0の黒字です。", facts: facts))
        #expect(!AnswerSentenceCheck.accepts("今月は赤字です。", facts: facts))
    }

    @Test("空の文と長すぎる文は使わない")
    func rejectsEmptyOrLong() {
        #expect(!AnswerSentenceCheck.accepts("", facts: Self.cafeFacts))
        #expect(!AnswerSentenceCheck.accepts("  \n", facts: Self.cafeFacts))
        #expect(!AnswerSentenceCheck.accepts(String(repeating: "カフェ", count: 60), facts: Self.cafeFacts))
    }

    @Test("位を使った書き方も、同じ額なら使う")
    func acceptsUnits() {
        let answer = LedgerAnswer(
            question: LedgerQuestion(period: .thisMonth, metric: .incomeTotal),
            period: .thisMonth,
            interval: DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)),
            recordCount: 1,
            value: .amount(250_000)
        )
        let facts = LedgerAnswerFacts.text(for: answer, calendar: Fixture.calendar)

        #expect(AnswerSentenceCheck.accepts("今月の収入は25万円です。", facts: facts))
        #expect(AnswerSentenceCheck.accepts("今月の収入は二十五万円です。", facts: facts))
        #expect(!AnswerSentenceCheck.accepts("今月の収入は26万円です。", facts: facts))
    }

    @Test("内訳の割合と金額は、ツールの結果にあるものなら使う")
    func breakdownNumbers() {
        let breakdown = CategoryBreakdown(expenseByCategory: [.food: 20_000, .cafe: 5_000])
        let answer = LedgerAnswer(
            question: LedgerQuestion(period: .thisMonth, metric: .expenseByCategory),
            period: .thisMonth,
            interval: DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)),
            recordCount: 8,
            value: .breakdown(breakdown)
        )
        let facts = LedgerAnswerFacts.text(for: answer, calendar: Fixture.calendar)

        #expect(facts.contains("食費 ¥20,000（80%）"))
        #expect(AnswerSentenceCheck.accepts("今月は食費が¥20,000で80%を占めます。", facts: facts))
        #expect(!AnswerSentenceCheck.accepts("今月は食費が¥20,000で75%を占めます。", facts: facts))
        // 割合の数字を、金額として書いたら使わない。
        #expect(!AnswerSentenceCheck.accepts("今月は食費が80円です。", facts: facts))
    }

    @Test("1 日あたりの額と残りの日数")
    func dailyAllowanceNumbers() throws {
        let status = try #require(BudgetStatus(
            budget: 150_000, spent: 57_000, now: Fixture.now,
            month: DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)), calendar: Fixture.calendar
        ))
        let answer = LedgerAnswer(
            question: LedgerQuestion(period: .thisMonth, metric: .dailyAllowance),
            period: .thisMonth,
            interval: DateInterval(start: Fixture.date(2026, 9, 1), end: Fixture.date(2026, 10, 1)),
            recordCount: 12,
            value: .dailyAllowance(status)
        )
        let facts = LedgerAnswerFacts.text(for: answer, calendar: Fixture.calendar)

        #expect(facts.contains("1日あたり ¥31,000"))
        #expect(AnswerSentenceCheck.accepts("月末まであと3日、1日あたり¥31,000使えます。", facts: facts))
        #expect(AnswerSentenceCheck.accepts("一日あたり¥31,000使えます。", facts: facts))
        #expect(!AnswerSentenceCheck.accepts("あと4日、1日あたり¥31,000使えます。", facts: facts))
    }
}
