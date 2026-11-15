#if canImport(FoundationModels)
import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

extension AIEvaluationTests {
    /// 家計への質問（`FoundationModelsQuestionAnswerer`。モデルが `queryLedger` ツールで期間・知りたいこと・カテゴリを選び、数字はコアが
    /// 計算する）。アプリはモデルがツールを呼ばなかったときなどにキーワード辞書で答え直す（`FallbackQuestionAnswerer`）が、ここでは
    /// AI だけの答えを見る。
    @Suite("家計への質問")
    struct QuestionAnswers {
        static let ledger = QuestionLedger(
            records: AIEvaluation.records, budget: BudgetPlan(total: AIEvaluation.budget),
            budgetDecidedAt: AIEvaluation.budgetDecidedAt
        )

        /// 質問の文と、正しい質問（期間・知りたいこと・カテゴリ）。
        static let cases: [(text: String, question: LedgerQuestion)] = [
            ("今月カフェいくら?", LedgerQuestion(period: .thisMonth, metric: .categoryExpense, category: .cafe)),
            ("先月の食費は?", LedgerQuestion(period: .lastMonth, metric: .categoryExpense, category: .food)),
            ("今月いくら使った?", LedgerQuestion(period: .thisMonth, metric: .expenseTotal)),
            ("今月の収支は?", LedgerQuestion(period: .thisMonth, metric: .balance)),
            ("予算あとどれくらい残ってる?", LedgerQuestion(period: .thisMonth, metric: .remainingBudget)),
            ("月末まで毎日いくらまで使える?", LedgerQuestion(period: .thisMonth, metric: .dailyAllowance)),
            ("先月いちばん使ったカテゴリは?", LedgerQuestion(period: .lastMonth, metric: .topCategory)),
            ("今週の交通費は?", LedgerQuestion(period: .thisWeek, metric: .categoryExpense, category: .transport)),
            ("今月の記録は何件?", LedgerQuestion(period: .thisMonth, metric: .entryCount)),
        ]

        @Test("ツールで期間・知りたいこと・カテゴリを選び、上限の時間に収まる。答えの数字はコードの計算と同じ")
        func answersQuestions() async throws {
            try AIEvaluation.requireModel()
            await AIEvaluation.warmUp()
            var card = AIScorecard("家計への質問（上限 \(AIEvaluation.seconds(AITimeouts.question))）")
            for (text, question) in Self.cases {
                let expected = try #require(Self.answer(question), "「\(text)」の正しい答えを計算できない")
                let timed = await AIEvaluation.measure {
                    try await FoundationModelsQuestionAnswerer().answer(
                        text, ledger: Self.ledger, now: TestSupport.now, calendar: TestSupport.calendar
                    )
                }
                var answer: LedgerAnswer?
                if case .answered(let answered)? = timed.value {
                    answer = answered
                }
                if let answer {
                    // 揺れてはいけない: 答えの数字は、モデルが選んだ質問をコードが計算したもの（モデルの書いた数字は使わない）。
                    #expect(answer == Self.answer(answer.question), "「\(text)」の答えの数字がコードの計算と違う: \(answer.value)")
                }
                card.record(
                    "「\(text)」",
                    passed: answer == expected && timed.isWithin(AITimeouts.question),
                    timed.describe { _ in Self.describe(answer) }
                )
            }
            print(card.report)
            #expect(card.rate >= AIEvaluation.passRate, "\(card.report)")
        }

        private static func answer(_ question: LedgerQuestion) -> LedgerAnswer? {
            LedgerQuestionAnswerer.answer(question, ledger: ledger, now: TestSupport.now, calendar: TestSupport.calendar)
        }

        private static func describe(_ answer: LedgerAnswer?) -> String {
            guard let answer else { return "読めない" }
            let question = answer.question
            let category = question.category.map { " \($0.displayName)" } ?? ""
            return "\(question.period) \(question.metric)\(category) → \(answer.value)"
        }
    }
}
#endif
