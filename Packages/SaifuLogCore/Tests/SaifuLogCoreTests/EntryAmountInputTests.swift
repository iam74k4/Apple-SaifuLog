import Testing
@testable import SaifuLogCore

@Suite("記録の金額の入力（直すシート）")
struct EntryAmountInputTests {
    @Test("入力欄には 3 桁ごとにカンマを入れて見せる", arguments: [
        ("850", "850"),
        ("1280", "1,280"),
        ("¥1,280", "1,280"),
        ("１２８０", "1,280"),
        ("1 280円", "1,280"),
        ("000850", "850"),
        ("0", "0"),
        ("", ""),
        ("abc", ""),
    ])
    func formats(text: String, expected: String) {
        #expect(EntryAmountInput.formatted(text) == expected)
    }

    @Test("保存できる額を読む", arguments: [
        ("850", 850),
        ("1,280", 1_280),
        ("１", 1),
        ("999,999,999,999", 999_999_999_999),
    ])
    func validAmounts(text: String, expected: Int) {
        #expect(EntryAmountInput.validate(text) == .success(expected))
    }

    /// 支出も収入も正の数で持つので、0 円は保存しない。空欄も保存しない。
    @Test("空欄と 0 円は保存できない")
    func missingAndZero() {
        #expect(EntryAmountInput.validate("") == .failure(.missing))
        #expect(EntryAmountInput.validate("abc") == .failure(.missing))
        #expect(EntryAmountInput.validate("0") == .failure(.notPositive))
        #expect(EntryAmountInput.validate("000") == .failure(.notPositive))
    }

    /// 上限の桁数で黙って切ると、打った 13 桁目が消え、打ったつもりと違う額が保存されてしまう。
    /// 1 桁多くまで残し、超えたことを理由つきで知らせる。
    @Test("上限を超えた額は、切り捨てずに保存できないと知らせる")
    func tooLarge() {
        #expect(EntryAmountInput.maximumDigits == 13)
        #expect(EntryAmountInput.formatted("1000000000000") == "1,000,000,000,000")
        #expect(EntryAmountInput.validate("1000000000000") == .failure(.tooLarge))
        // 13 桁より後ろ（貼り付けたカード番号など）は捨てるが、それでも上限を超えるので保存できない。
        #expect(EntryAmountInput.formatted("4111111111111111") == "4,111,111,111,111")
        #expect(EntryAmountInput.validate("4111111111111111") == .failure(.tooLarge))
    }

    @Test("金額を入力欄の形にする（0 以下は空欄）", arguments: [
        (850, "850"),
        (250_000, "250,000"),
        (999_999_999_999, "999,999,999,999"),
        (0, ""),
        (-500, ""),
    ])
    func textForAmount(amount: Int, expected: String) {
        #expect(EntryAmountInput.text(for: amount) == expected)
    }

    @Test("そろえた形をもう一度そろえても変わらない", arguments: ["1,280", "999,999,999,999", "1,000,000,000,000", "0", ""])
    func formattingIsIdempotent(text: String) {
        #expect(EntryAmountInput.formatted(EntryAmountInput.formatted(text)) == EntryAmountInput.formatted(text))
    }

    /// ひとことで記録できた額は、直すシートでも保存できる（上限が食い違うと、金額を変えずにカテゴリだけ直すことも
    /// できなくなる）。上限を超える数字は、ひとこと入力でも金額として読まない。
    @Test("上限は、ひとこと入力で金額として読む上限と同じ")
    func maximumMatchesParser() async throws {
        let largest = try await Fixture.parser.parse("給料 999999999999")
        #expect(largest.map(\.amount) == [EntryAmountInput.maximumAmount])
        #expect(EntryAmountInput.validate(EntryAmountInput.text(for: largest[0].amount)) == .success(largest[0].amount))

        #expect(try await Fixture.parser.parse("ランチ 1000000000000").isEmpty)
    }
}
