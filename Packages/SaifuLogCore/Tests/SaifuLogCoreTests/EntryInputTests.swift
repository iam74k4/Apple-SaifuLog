import Testing
@testable import SaifuLogCore

@Suite("入力の区間")
struct EntryInputTests {
    func input(_ text: String) -> EntryInput {
        EntryInput(text, now: Fixture.now, calendar: Fixture.calendar)
    }

    @Test("1 件ずつの区間の文字列を返す（AI にはこれを 1 件ずつ読ませる）", arguments: [
        ("ランチ 850", ["ランチ 850"]),
        ("昨日 スーパー2480とドラッグ1200", ["昨日 スーパー2480", "ドラッグ1200"]),
        ("スーパー2480、ドラッグ1200", ["スーパー2480", "ドラッグ1200"]),
        ("スーパー2480 と ドラッグ1200", ["スーパー2480", "ドラッグ1200"]),
        ("ランチとコーヒー 1200", ["ランチとコーヒー 1200"]),
        ("焼肉12000 4人で割り勘", ["焼肉12000 4人で割り勘"]),
        ("ランチ", []),
    ])
    func segmentTexts(text: String, expected: [String]) {
        let segments = input(text).segments
        #expect(segments.map(\.text) == expected)
        #expect(segments.map(\.index) == Array(expected.indices))
    }

    @Test("区間ごとのルールベースの記録は RuleBasedParser と同じ", arguments: [
        "ランチ 850", "昨日 焼肉12000 4人で割り勘、今日 ランチ 850", "スーパー2480とドラッグ1200", "返金 -500",
    ])
    func ruleBasedEntriesMatchParser(text: String) {
        #expect(input(text).ruleBasedEntries == Fixture.parser.entries(from: text))
        #expect(input(text).segments.map(\.ruleBasedEntry) == Fixture.parser.entries(from: text))
    }

    @Test("元の入力を持つ")
    func keepsOriginalText() {
        #expect(input("ランチ　８５０").text == "ランチ　８５０")
        #expect(input("ランチ　８５０").segments.map(\.text) == ["ランチ 850"])
    }
}
