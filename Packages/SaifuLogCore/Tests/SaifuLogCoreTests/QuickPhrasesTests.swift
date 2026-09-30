import Foundation
import Testing
@testable import SaifuLogCore

/// よく使うひとことの候補（`QuickPhrases`）。品目ごとのまとめ方・金額と書き方・並び・入力欄の文に合わせた出し方を確かめる。
@Suite("よく使うひとこと")
struct QuickPhrasesTests {
    struct Record: QuickPhraseRecord {
        var amount: Int
        var isIncome = false
        var memo: String
        var createdAt: Date

        init(_ memo: String, _ amount: Int, day: Int, isIncome: Bool = false) {
            self.memo = memo
            self.amount = amount
            self.isIncome = isIncome
            self.createdAt = Fixture.date(2026, 9, day, hour: 12)
        }
    }

    @Test("品目ごとにまとめ、回数の多い順に並べる（同じ回数なら新しい順）")
    func groupsAndSorts() {
        let phrases = QuickPhrases.phrases(from: [
            Record("ランチ", 850, day: 1),
            Record("コーヒー", 420, day: 2),
            Record("ランチ", 1_100, day: 3),
            Record("バス", 230, day: 4),
            Record("コーヒー", 480, day: 5),
            Record("ランチ", 780, day: 6),
        ])

        #expect(phrases.map(\.item) == ["ランチ", "コーヒー", "バス"])
        #expect(phrases.map(\.count) == [3, 2, 1])
    }

    @Test("金額と書き方は、その品目のいちばん新しい記録のもの（表記ゆれは同じ品目にまとめる）")
    func usesLatestRecord() throws {
        let phrases = QuickPhrases.phrases(from: [
            Record("ランチ", 780, day: 6),
            Record("らんち", 850, day: 1),
            Record("ランチ ", 1_100, day: 9),
        ])

        let lunch = try #require(phrases.first)
        #expect(phrases.count == 1)
        #expect(lunch.item == "ランチ")
        #expect(lunch.amount == 1_100)
        #expect(lunch.count == 3)
        #expect(lunch.draft == "ランチ 1100")
    }

    @Test("割り勘の記録は説明を除いた品目で、品目の無い記録は候補にしない")
    func usesItemAndSkipsEmpty() {
        let split = ParsedEntry.assemble(total: 12_000, category: .food, isIncome: false, item: "焼肉", daysAgo: 0, splitCount: 4)
        let phrases = QuickPhrases.phrases(from: [
            Record(split.memo, split.amount, day: 1),
            Record("焼肉", 2_800, day: 2),
            Record("", 500, day: 3),
        ])

        #expect(phrases.map(\.item) == ["焼肉"])
        #expect(phrases.first?.count == 2)
        #expect(phrases.first?.draft == "焼肉 2800")
    }

    @Test("収入は符号を付けずに品目の語で、品目に収入の語が無い返金はマイナスを付けて入れる")
    func incomeDraft() {
        let phrases = QuickPhrases.phrases(from: [
            Record("給料", 250_000, day: 1, isIncome: true),
            Record("返金", 500, day: 2, isIncome: true),
        ])

        #expect(Set(phrases.map(\.draft)) == ["給料 250000", "返金 -500"])
    }

    @Test("入力欄が空なら、2 回以上記録した品目を最大の数まで出す")
    func suggestionsWhenEmpty() {
        var records: [Record] = []
        for index in 0..<10 {
            records.append(Record("品目\(index)", 100 + index, day: 1))
            records.append(Record("品目\(index)", 100 + index, day: 2))
        }
        records.append(Record("一度だけ", 999, day: 3))
        let phrases = QuickPhrases.phrases(from: records)

        let suggestions = QuickPhrases.suggestions(phrases, draft: "  ")

        #expect(suggestions.count == QuickPhrases.maximumCount)
        #expect(!suggestions.contains { $0.item == "一度だけ" })
    }

    @Test("打ち始めたら、打った文字で始まる品目を回数によらず出す（ひらがなで打ってもよい）")
    func suggestionsForPrefix() {
        let phrases = QuickPhrases.phrases(from: [
            Record("コーヒー", 420, day: 1),
            Record("コーヒー", 420, day: 2),
            Record("コンビニ", 650, day: 3),
            Record("ランチ", 850, day: 4),
        ])

        #expect(QuickPhrases.suggestions(phrases, draft: "こ").map(\.item) == ["コーヒー", "コンビニ"])
        #expect(QuickPhrases.suggestions(phrases, draft: "コン").map(\.item) == ["コンビニ"])
        #expect(QuickPhrases.suggestions(phrases, draft: "ランチ").map(\.item) == ["ランチ"])
        #expect(QuickPhrases.suggestions(phrases, draft: "寿司").isEmpty)
    }

    @Test("打った文に数字があれば出さない（金額まで打った後は候補が要らない）")
    func noSuggestionsAfterDigits() {
        let phrases = QuickPhrases.phrases(from: [Record("ランチ", 850, day: 1), Record("ランチ", 850, day: 2)])

        #expect(QuickPhrases.suggestions(phrases, draft: "ランチ 8").isEmpty)
        #expect(QuickPhrases.suggestions(phrases, draft: "ランチ８").isEmpty)
    }
}
