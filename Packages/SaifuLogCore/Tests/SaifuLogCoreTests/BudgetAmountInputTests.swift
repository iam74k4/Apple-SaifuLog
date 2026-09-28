import Testing
@testable import SaifuLogCore

@Suite("予算の金額の入力")
struct BudgetAmountInputTests {
    @Test("入力欄には 3 桁ごとにカンマを入れて見せる", arguments: [
        ("150000", "150,000"),
        ("1,500,000", "1,500,000"),
        ("15,0000", "150,000"),
        ("¥150,000", "150,000"),
        ("１５００００", "150,000"),
        ("150 000円", "150,000"),
        ("850", "850"),
        ("000150", "150"),
        ("0", "0"),
        ("", ""),
        ("abc", ""),
    ])
    func formats(text: String, expected: String) {
        #expect(BudgetAmountInput.formatted(text) == expected)
    }

    /// 前を捨てると、打ったつもりの額と桁がずれる。
    @Test("8 桁を超えて打った数字は、後ろを捨てる")
    func dropsExtraDigits() {
        #expect(BudgetAmountInput.maximumDigits == 8)
        #expect(BudgetAmountInput.formatted("123456789") == "12,345,678")
        #expect(BudgetAmountInput.formatted("99,999,9999") == "99,999,999")
        #expect(BudgetAmountInput.amount(from: "123456789") == 12_345_678)
    }

    @Test("入力欄の文字から金額を読む", arguments: [
        ("150,000", 150_000 as Int?),
        ("¥80,000", 80_000),
        ("0", 0),
        ("", nil),
        ("abc", nil),
    ])
    func readsAmount(text: String, expected: Int?) {
        #expect(BudgetAmountInput.amount(from: text) == expected)
    }

    @Test("金額を入力欄の形にする（0 以下は空欄、上限を超える額は上限）", arguments: [
        (150_000, "150,000"),
        (5, "5"),
        (0, ""),
        (-1_000, ""),
        (1_000_000_000, "99,999,999"),
    ])
    func textForAmount(amount: Int, expected: String) {
        #expect(BudgetAmountInput.text(for: amount) == expected)
    }

    @Test("そろえた形をもう一度そろえても変わらない", arguments: ["150,000", "12,345,678", "0", ""])
    func formattingIsIdempotent(text: String) {
        #expect(BudgetAmountInput.formatted(BudgetAmountInput.formatted(text)) == BudgetAmountInput.formatted(text))
    }
}
