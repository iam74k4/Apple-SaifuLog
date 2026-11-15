#if canImport(FoundationModels)
import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

extension AIEvaluationTests {
    /// 記録の返事に添える一言（`FoundationModelsRecordRemarkWriter`）と、月のまとめの一言（`FoundationModelsRecapRemarkWriter`）。
    ///
    /// どちらも数字の文（コアの `RecordFacts`・`RecapFacts`）だけを渡して書かせ、文に無い数字があれば捨てる（`RecapRemark.checked`）。
    /// 捨てた一言は画面に出さない（定型の一行だけにする）ので、ここでは同じ文から何度か書かせて、照合に通って上限の時間に収まる
    /// 割合を見る。
    @Suite("一言")
    struct Remarks {
        /// 記録の返事の一言に渡す、いま記録した支出と月の予算（予算の内・超えた）。
        static let recordFixtures: [(label: String, recorded: RecordFacts.Item, budget: Int?)] = [
            ("予算の内", RecordFacts.Item(item: "カフェラテ", amount: 480, category: .cafe), AIEvaluation.budget),
            ("予算を超えた", RecordFacts.Item(item: "焼肉", amount: 3_000, category: .food), 5_000),
        ]

        @Test("記録の返事の一言が、数字の照合に通り、上限の時間に収まる")
        func recordRemarks() async throws {
            try AIEvaluation.requireModel()
            await AIEvaluation.warmUp()
            var card = AIScorecard("記録の返事の一言（上限 \(AIEvaluation.seconds(AITimeouts.recordRemark))）")
            for (label, recorded, budget) in Self.recordFixtures {
                let records = AIEvaluation.records + [
                    LedgerRecordValue(amount: recorded.amount, category: recorded.category, spentAt: TestSupport.now),
                ]
                let facts = try #require(RecordFacts.text(
                    recorded: [recorded], monthRecords: records, budget: budget, now: TestSupport.now, calendar: TestSupport.calendar
                ))
                for run in 1...AIEvaluation.remarkRuns {
                    let timed = await AIEvaluation.measure { try await FoundationModelsRecordRemarkWriter().remark(from: facts) }
                    let checked = timed.value.flatMap { RecapRemark.checked($0, facts: facts) }
                    card.record(
                        "\(label) \(run) 回目",
                        passed: checked != nil && timed.isWithin(AITimeouts.recordRemark),
                        timed.describe { Self.describe($0, accepted: checked != nil) }
                    )
                }
            }
            print(card.report)
            #expect(card.rate >= AIEvaluation.remarkPassRate, "\(card.report)")
        }

        /// 月のまとめの一言に渡す月（途中の今月・終わった先月）。
        static let recapMonths: [(label: String, month: Date)] = [
            ("今月（途中）", TestSupport.now),
            ("先月（終わった月）", TestSupport.date(2026, 8, 15)),
        ]

        @Test("月のまとめの一言が、数字の照合に通り、上限の時間に収まる")
        func recapRemarks() async throws {
            try AIEvaluation.requireModel()
            await AIEvaluation.warmUp()
            var card = AIScorecard("月のまとめの一言（上限 \(AIEvaluation.seconds(AITimeouts.recapRemark))）")
            for (label, month) in Self.recapMonths {
                let report = try #require(MonthlyReport(
                    records: AIEvaluation.records, month: month, now: TestSupport.now, budget: AIEvaluation.budget,
                    budgetDecidedAt: AIEvaluation.budgetDecidedAt, calendar: TestSupport.calendar
                ))
                let facts = try #require(RecapFacts.text(for: report, calendar: TestSupport.calendar))
                for run in 1...AIEvaluation.remarkRuns {
                    let timed = await AIEvaluation.measure { try await FoundationModelsRecapRemarkWriter().remark(from: facts) }
                    let checked = timed.value.flatMap { RecapRemark.checked($0, facts: facts) }
                    card.record(
                        "\(label) \(run) 回目",
                        passed: checked != nil && timed.isWithin(AITimeouts.recapRemark),
                        timed.describe { Self.describe($0, accepted: checked != nil) }
                    )
                }
            }
            print(card.report)
            #expect(card.rate >= AIEvaluation.remarkPassRate, "\(card.report)")
        }

        private static func describe(_ remark: String, accepted: Bool) -> String {
            let sentence = remark.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
            return "「\(sentence)」\(accepted ? "" : "（照合で捨てる）")"
        }
    }
}
#endif
