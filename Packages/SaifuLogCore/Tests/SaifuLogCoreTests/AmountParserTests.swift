import Testing
@testable import SaifuLogCore

// AI が抜き出した金額が入力に書かれているかの突き合わせは ExtractedEntryTests で確かめる
// （本番で突き合わせを行うのは ExtractedEntry.resolved なので、そちらに向けてテストする）。
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

    @Test("万のまとまりの中の千・百を足し、万・億で繰り上げる", arguments: [
        ("1万2千500円", 12_500),
        ("3万2千100円", 32_100),
        ("1千万", 10_000_000),
        ("1千万円", 10_000_000),
        ("5百円", 500),
        ("1万2千3百", 12_300),
        ("1万2千5", 12_500),
        ("1億", 100_000_000),
        ("1億2000万", 120_000_000),
        ("2億5千万円", 250_000_000),
    ])
    func readsPositionalUnits(text: String, expected: Int) {
        #expect(AmountParser.yen(from: text) == expected)
    }

    @Test("単価と個数の掛け算は掛けた額にする", arguments: [
        ("500×3", 1_500),
        ("400 ×2", 800),
        ("3x500円", 1_500),
        ("¥500*2", 1_000),
    ])
    func multipliesQuantity(text: String, expected: Int) {
        #expect(AmountParser.yen(from: text) == expected)
    }

    @Test("マイナスを付けた額は、マイナスを外した額にする")
    func dropsMinusSign() {
        #expect(AmountParser.yen(from: "-500") == 500)
        #expect(AmountParser.yen(from: "−500") == 500)
    }

    @Test("数字が無い・0・桁が多すぎるものは読まない", arguments: [
        "", "ランチ", "0", "0円", "1234567890123",
    ])
    func rejects(text: String) {
        #expect(AmountParser.yen(from: text) == nil)
    }

    @Test("時刻・日付・位の無い小数・電話番号は金額にしない", arguments: [
        "12:30", "9/26", "9.26", "9-26", "3.14", "09012345678", "090-1234-5678", "26日",
    ])
    func rejectsNonAmountNumbers(text: String) {
        #expect(AmountParser.yen(from: text) == nil)
    }
}
