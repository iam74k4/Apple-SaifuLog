import Testing
@testable import SaifuLogCore

@Suite("金額の読み取り")
struct AmountParserTests {
    @Test("表記を円の整数にする", arguments: [
        ("850", 850),
        ("850円", 850),
        ("¥1,280", 1_280),
        ("１２００円", 1_200),
        ("￥８５０", 850),
        ("25万", 250_000),
        ("25万円", 250_000),
        ("1.5万", 15_000),
        ("1万2千", 12_000),
        ("1万2000円", 12_000),
        ("1万5", 15_000),
        ("3千", 3_000),
        ("3千5", 3_500),
        ("3千500", 3_500),
        ("1,000,000", 1_000_000),
    ])
    func parsesYen(text: String, expected: Int) {
        #expect(AmountParser.yen(from: text) == expected)
    }

    @Test("数字が無い・0・桁が多すぎるものは読まない", arguments: [
        "", "ランチ", "0", "0円", "1234567890123",
    ])
    func rejects(text: String) {
        #expect(AmountParser.yen(from: text) == nil)
    }

    @Test("AI が抜き出した金額が入力に書かれていれば採る", arguments: [
        ("12000", "昨日 焼肉12000 4人で割り勘"),
        ("12,000円", "昨日 焼肉12000 4人で割り勘"),
        ("25万", "給料 25万"),
        ("250000", "給料 25万"),
        ("2480", "スーパー2480とドラッグ1200"),
    ])
    func acceptsGroundedAmount(amountText: String, input: String) {
        #expect(AmountParser.isGrounded(amountText, in: input))
    }

    @Test("入力に無い金額（計算した値・人数・作った数字）は採らない", arguments: [
        ("3000", "昨日 焼肉12000 4人で割り勘"),
        ("4", "昨日 焼肉12000 4人で割り勘"),
        ("3680", "スーパー2480とドラッグ1200"),
        ("なし", "ランチ 850"),
    ])
    func rejectsUngroundedAmount(amountText: String, input: String) {
        #expect(!AmountParser.isGrounded(amountText, in: input))
    }
}
