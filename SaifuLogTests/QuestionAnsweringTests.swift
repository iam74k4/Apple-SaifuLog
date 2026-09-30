import Foundation
import SaifuLogCore
import Synchronization
import Testing
@testable import SaifuLog

/// 家計への質問の答え方（キーワード辞書・AI からの切り替え・AI のツール呼び出し）。
///
/// AI の経路はモデルの代わりに、ツールを直接呼んで一言を返す偽物を使う（モデルがツールを呼ぶ・呼ばない・ツールの結果に
/// 無い数字を書く、を決めて確かめる）。固定の日時は 2026-09-28 12:00（日本時間）。
struct QuestionAnsweringTests {
    /// 今月のカフェ ¥1,600（2 件）、食費 ¥850、先月のカフェ ¥700。
    static let ledger = QuestionLedger(records: [
        LedgerRecordValue(amount: 400, category: .cafe, spentAt: TestSupport.date(2026, 9, 28, hour: 9)),
        LedgerRecordValue(amount: 1_200, category: .cafe, spentAt: TestSupport.date(2026, 9, 27, hour: 15)),
        LedgerRecordValue(amount: 850, category: .food, spentAt: TestSupport.date(2026, 9, 28, hour: 12)),
        LedgerRecordValue(amount: 700, category: .cafe, spentAt: TestSupport.date(2026, 8, 1)),
    ])

    static func answer(_ question: LedgerQuestion) throws -> LedgerAnswer {
        try #require(LedgerQuestionAnswerer.answer(question, ledger: ledger, now: TestSupport.now, calendar: TestSupport.calendar))
    }

    static let cafeThisMonth = LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe)

    // MARK: - キーワード辞書

    @Test func ruleBasedAnswersWithCode() async throws {
        let reply = try await RuleBasedQuestionAnswerer().answer(
            "今月カフェいくら?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar
        )

        #expect(reply == .answered(try Self.answer(Self.cafeThisMonth), remark: nil))
    }

    @Test func ruleBasedUnreadable() async throws {
        let reply = try await RuleBasedQuestionAnswerer().answer(
            "去年の食費は?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar
        )

        #expect(reply == .unreadable)
    }

    // MARK: - AI からの切り替え

    /// AI の結果を使わなかったことを残す記録をつないだ切り替え（記録はテストごとに新しくする）。
    static func fallbackAnswerer(primary: StubAnswerer, log: AIFallbackLog) -> FallbackQuestionAnswerer {
        FallbackQuestionAnswerer(primary: primary, fallback: RuleBasedQuestionAnswerer(), onFallback: log.reporter(for: .question))
    }

    /// AI が失敗したら、キーワード辞書で答え直し、失敗を AI の記録に残す（利用者には知らせない）。
    @Test func fallbackAnswersWhenPrimaryFails() async throws {
        let log = AIFallbackLog()
        let answerer = Self.fallbackAnswerer(primary: StubAnswerer { _, _ in throw TestError() }, log: log)

        let reply = try await answerer.answer("今月カフェいくら?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(reply == .answered(try Self.answer(Self.cafeThisMonth), remark: nil))
        #expect(log.snapshot.fallbacks == [.question: 1])
        #expect(log.snapshot.lastError?.feature == .question)
        #expect(log.snapshot.lastError?.error.type == String(reflecting: TestError.self))
    }

    /// AI が答えられなかったときも、キーワード辞書で答え直し、結果が無かったこととして回数だけを残す。
    @Test func fallbackAnswersWhenPrimaryCannot() async throws {
        let log = AIFallbackLog()
        let answerer = Self.fallbackAnswerer(primary: StubAnswerer { _, _ in .unreadable }, log: log)

        let reply = try await answerer.answer("先月の支出は?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(reply == .answered(try Self.answer(LedgerQuestion(period: .lastMonth, metric: .expenseTotal)), remark: nil))
        #expect(log.snapshot.fallbacks == [.question: 1])
        #expect(log.snapshot.lastError == nil)
    }

    /// AI が答えたら、そのまま使う（AI の記録には何も残さない）。
    @Test func fallbackKeepsPrimaryAnswer() async throws {
        let log = AIFallbackLog()
        let expected = QuestionReply.answered(try Self.answer(Self.cafeThisMonth), remark: .ai("今月のカフェは¥1,600でした。"))
        let answerer = Self.fallbackAnswerer(primary: StubAnswerer { _, _ in expected }, log: log)

        let reply = try await answerer.answer("カフェ代は?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(reply == expected)
        #expect(log.snapshot == AIFallbackLog.Snapshot())
    }

    /// 取り消しは失敗ではないので、答え直さずに伝える（AI の記録にも残さない）。
    @Test func fallbackPassesCancellation() async throws {
        let log = AIFallbackLog()
        let answerer = Self.fallbackAnswerer(primary: StubAnswerer { _, _ in throw CancellationError() }, log: log)

        await #expect(throws: CancellationError.self) {
            _ = try await answerer.answer("今月の支出は?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)
        }
        #expect(log.snapshot == AIFallbackLog.Snapshot())
    }

    #if canImport(FoundationModels)
    // MARK: - AI のツール呼び出し

    static func tool(for text: String, recorder: LedgerToolRecorder = LedgerToolRecorder()) -> LedgerQuestionTool {
        LedgerQuestionTool(
            reading: QuestionParser.read(text, now: TestSupport.now, calendar: TestSupport.calendar),
            ledger: ledger, now: TestSupport.now, calendar: TestSupport.calendar, recorder: recorder
        )
    }

    /// ツールはモデルの選択から、コードで数字を計算して返す（結果の文と、画面に出す答えを残す）。
    @Test func toolComputesFromChoice() async throws {
        let recorder = LedgerToolRecorder()
        let tool = Self.tool(for: "カフェ代は?", recorder: recorder)

        let facts = try await tool.call(arguments: LedgerQueryArguments(period: .lastMonth, metric: .categoryExpense, category: .cafe))

        #expect(facts.contains("¥700"))
        #expect(recorder.latest?.answer == (try Self.answer(LedgerQuestion(period: .lastMonth, metric: .categoryExpense, category: .cafe))))
        #expect(recorder.latest?.facts == facts)
    }

    /// 文から読めた期間とカテゴリは、モデルの選択より優先する。
    @Test func toolPrefersWhatTheTextSays() async throws {
        let recorder = LedgerToolRecorder()
        let tool = Self.tool(for: "今月カフェいくら?", recorder: recorder)

        _ = try await tool.call(arguments: LedgerQueryArguments(period: .lastMonth, metric: .categoryExpense, category: .food))

        #expect(recorder.latest?.answer == (try Self.answer(Self.cafeThisMonth)))
    }

    /// 金額を聞く語だけの文（「今月カフェいくら?」）で、モデルが件数・いちばん多いカテゴリ・内訳を選んでも、金額で答える
    /// （件数を答えたり、聞かれたカテゴリを落としたりしない）。
    @Test(arguments: [
        LedgerQueryArguments.MetricChoice.entryCount, .topCategory, .expenseByCategory,
    ])
    func toolAnswersAmountForAmountQuestion(metric: LedgerQueryArguments.MetricChoice) async throws {
        let recorder = LedgerToolRecorder()
        let tool = Self.tool(for: "今月カフェいくら?", recorder: recorder)

        _ = try await tool.call(arguments: LedgerQueryArguments(period: .thisMonth, metric: metric, category: .unspecified))

        #expect(recorder.latest?.answer == (try Self.answer(Self.cafeThisMonth)))
    }

    /// モデルの一言がツールの結果の数字だけなら、その一言を添える。回答カードの数字はツールが計算したもの。
    @Test func modelSentenceWithToolNumbersIsKept() async throws {
        let answerer = FoundationModelsQuestionAnswerer { _, tool in
            _ = try await tool.call(arguments: LedgerQueryArguments(period: .thisMonth, metric: .categoryExpense, category: .cafe))
            return " 今月のカフェは¥1,600（2件）でした。\n"
        }

        let reply = try await answerer.answer("今月カフェいくら?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(reply == .answered(try Self.answer(Self.cafeThisMonth), remark: .ai("今月のカフェは¥1,600（2件）でした。")))
    }

    /// モデルの一言にツールの結果に無い数字があれば、一言を捨てて定型文にする（数字はツールのまま）。
    @Test func modelSentenceWithOtherNumbersIsReplaced() async throws {
        let answerer = FoundationModelsQuestionAnswerer { _, tool in
            _ = try await tool.call(arguments: LedgerQueryArguments(period: .thisMonth, metric: .categoryExpense, category: .cafe))
            return "今月のカフェは¥2,000でした。"
        }

        let reply = try await answerer.answer("今月カフェいくら?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(reply == .answered(try Self.answer(Self.cafeThisMonth), remark: .fixed))
    }

    /// モデルの一言に、期間の日付の数字を件数として書いたもの（「30件」）があれば、一言を捨てて定型文にする。
    @Test func modelSentenceWithDateDigitAsCountIsReplaced() async throws {
        let answerer = FoundationModelsQuestionAnswerer { _, tool in
            _ = try await tool.call(arguments: LedgerQueryArguments(period: .thisMonth, metric: .categoryExpense, category: .cafe))
            return "今月のカフェは¥1,600（30件）でした。"
        }

        let reply = try await answerer.answer("今月カフェいくら?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(reply == .answered(try Self.answer(Self.cafeThisMonth), remark: .fixed))
    }

    /// モデルがツールを呼ばずに答えたら使わない（投げて、キーワード辞書に答え直させる）。ツールを呼ばなかったことは、AI の記録の
    /// 最後のエラーで分かる（実機でどのくらい起きるかを数える。docs/design.md §15）。
    @Test func modelWithoutToolCallFallsBack() async throws {
        let ai = FoundationModelsQuestionAnswerer { _, _ in "今月のカフェは¥1,600でした。" }
        let log = AIFallbackLog()

        await #expect(throws: QuestionAIError.self) {
            _ = try await ai.answer("今月カフェいくら?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)
        }
        let reply = try await FallbackQuestionAnswerer(
            primary: ai, fallback: RuleBasedQuestionAnswerer(), onFallback: log.reporter(for: .question)
        ).answer("今月カフェいくら?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)
        #expect(reply == .answered(try Self.answer(Self.cafeThisMonth), remark: nil))
        #expect(log.snapshot.lastError?.error.type == "SaifuLog.QuestionAIError.toolNotCalled")
    }

    /// 答えられない書き方（「去年」など）を含む質問は、モデルに渡さない。
    @Test func unsupportedQuestionIsNotSentToModel() async throws {
        let calls = CallCounter()
        let answerer = FoundationModelsQuestionAnswerer { _, _ in
            calls.increment()
            return ""
        }

        let reply = try await answerer.answer("去年の食費は?", ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar)

        #expect(reply == .unreadable)
        #expect(calls.count == 0)
    }

    /// 指示文とツールの説明に、具体的な数字や単位の例を書かない（モデルが入力に無くても写して返すため）。
    @Test func instructionsHaveNoNumberExamples() {
        let texts = [FoundationModelsQuestionAnswerer.instructions, Self.tool(for: "").description]
        for text in texts {
            #expect(!text.contains { ("0"..."9").contains($0) || ("０"..."９").contains($0) }, "\(text)")
            #expect(!text.contains("円"), "\(text)")
            #expect(!text.contains("¥"), "\(text)")
        }
    }
    #endif
}

/// モデルの代わりが呼ばれた回数（呼ばれないことを確かめる）。
final class CallCounter: Sendable {
    private let value = Mutex(0)

    func increment() {
        value.withLock { $0 += 1 }
    }

    var count: Int {
        value.withLock { $0 }
    }
}
