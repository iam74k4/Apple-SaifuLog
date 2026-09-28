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
        ("9/26 ランチ 850 9/27 カフェ 400", ["9/26 ランチ 850", "9/27 カフェ 400"]),
        ("ランチ 850 12:30 カフェ 400", ["ランチ 850", "12:30 カフェ 400"]),
        ("焼肉12000 4人で割り勘 ランチ 850", ["焼肉12000 4人で割り勘", "ランチ 850"]),
        ("焼肉12000 4人で割り勘 と ランチ 850", ["焼肉12000 4人で割り勘", "ランチ 850"]),
        ("ランチ850 コーヒー400 合計1250", ["ランチ850", "コーヒー400 合計1250"]),
        ("ランチ 1000円 (税込1100円)", ["ランチ 1000円 (税込1100円)"]),
        ("焼肉12000 4人で割り勘\r\nランチ 850", ["焼肉12000 4人で割り勘", "ランチ 850"]),
        ("クーポン100円引き ランチ 850", ["クーポン100円引き ランチ 850"]),
        ("9/26、850円 ランチ", ["9/26、850円 ランチ"]),
        ("12:30、400円", ["12:30、400円"]),
        ("ランチ", []),
    ])
    func segmentTexts(text: String, expected: [String]) {
        let segments = input(text).segments
        #expect(segments.map(\.text) == expected)
        #expect(segments.map(\.index) == Array(expected.indices))
    }

    @Test("区間ごとのルールベースの記録は RuleBasedParser と同じ", arguments: [
        "ランチ 850", "昨日 焼肉12000 4人で割り勘、今日 ランチ 850", "スーパー2480とドラッグ1200", "返金 -500",
        "9/26 ランチ 850 9/27 カフェ 400", "焼肉12000 4人で割り勘 ランチ 850", "ランチ 850 100円引き",
        "ランチ 1000円 (税込1100円)", "ランチ850 コーヒー400 合計1250", "ランチ 850円 おつり150円",
        "クーポン100円引き ランチ 850", "9/26、850円 ランチ", "昨日12:30、500円 カフェ",
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
