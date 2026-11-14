#if canImport(FoundationModels)
import Foundation
import SaifuLogCore
import Testing
@testable import SaifuLog

extension AIEvaluationTests {
    /// ひとこと入力の読み取り（`FoundationModelsEntryParser`）。アプリは AI の読み取りが投げたらキーワード辞書で読み直す
    /// （`FallbackEntryParser`）が、ここでは AI だけの答えを見る（投げた件は外れに数える）。
    @Suite("ひとこと入力の読み取り")
    struct EntryReading {
        /// 1 件の記録で、合っているとみなす値。カテゴリが nil の件はカテゴリを問わない（どちらにも読める品目）。
        struct Expected: Sendable {
            var amount: Int
            var category: EntryCategory?
            var isIncome = false
            var daysAgo = 0
            var splitCount = 1

            func matches(_ entry: ParsedEntry) -> Bool {
                entry.amount == amount && entry.isIncome == isIncome && entry.daysAgo == daysAgo
                    && entry.splitCount == splitCount && (category.map { $0 == entry.category } ?? true)
            }
        }

        static let cases: [(text: String, entries: [Expected])] = [
            ("ランチ 850", [Expected(amount: 850, category: .food)]),
            ("昨日 焼肉12000 4人で割り勘", [Expected(amount: 3_000, category: .food, daysAgo: 1, splitCount: 4)]),
            ("スタバ 450 と 本 1200", [Expected(amount: 450, category: .cafe), Expected(amount: 1_200)]),
            ("給料 25万", [Expected(amount: 250_000, isIncome: true)]),
            ("タクシー 1800", [Expected(amount: 1_800, category: .transport)]),
            ("電気代 6500", [Expected(amount: 6_500, category: .utilities)]),
            ("おととい 映画 1900", [Expected(amount: 1_900, category: .entertainment, daysAgo: 2)]),
            ("病院 1500", [Expected(amount: 1_500, category: .medical)]),
            ("シャンプー 600", [Expected(amount: 600, category: .daily)]),
            ("家賃 80000", [Expected(amount: 80_000, category: .housing)]),
            ("美容院 4500", [Expected(amount: 4_500, category: .clothing)]),
        ]

        @Test("金額・日付・割り勘・収入・件の数を読み、上限の時間に収まる。入力に無い金額は作らない")
        func readsEntries() async throws {
            try AIEvaluation.requireModel()
            await AIEvaluation.warmUp()
            var card = AIScorecard("ひとこと入力の読み取り（上限 \(AIEvaluation.seconds(AITimeouts.entry))）")
            for (text, expected) in Self.cases {
                let timed = await AIEvaluation.measure { try await AIEvaluation.entryParser.parse(text) }
                if let entries = timed.value {
                    // 揺れてはいけない: 件の数は区間の数と同じで、金額は入力に書かれた金額（割り勘なら割った額）だけ
                    // （ExtractedEntry.resolveAll が、合わない答えを投げて捨てる）。
                    #expect(entries.count == expected.count, "「\(text)」の件の数が区間の数と違う: \(Self.describe(entries))")
                    let amounts = Set(expected.map(\.amount))
                    #expect(
                        entries.allSatisfy { amounts.contains($0.amount) },
                        "「\(text)」に書かれていない金額を読んだ: \(Self.describe(entries))"
                    )
                }
                let matched = timed.value.map { entries in
                    entries.count == expected.count && zip(entries, expected).allSatisfy { $1.matches($0) }
                } ?? false
                card.record("「\(text)」", passed: matched && timed.isWithin(AITimeouts.entry), timed.describe(Self.describe))
            }
            print(card.report)
            #expect(card.rate >= AIEvaluation.passRate, "\(card.report)")
        }

        private static func describe(_ entries: [ParsedEntry]) -> String {
            entries.map { entry in
                var text = "¥\(entry.amount) \(entry.isIncome ? "収入" : entry.category.displayName)"
                if entry.daysAgo != 0 { text += " \(entry.daysAgo)日前" }
                if entry.splitCount > 1 { text += " \(entry.splitCount)人で割り勘" }
                return text
            }.joined(separator: "、")
        }
    }
}
#endif
