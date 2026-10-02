import Testing
@testable import SaifuLogCore

@Suite("金額の表記")
struct YenFormatterTests {
    @Test("¥1,280 の形で書く", arguments: [
        (0, "¥0"),
        (5, "¥5"),
        (850, "¥850"),
        (1_280, "¥1,280"),
        (12_000, "¥12,000"),
        (250_000, "¥250,000"),
        (1_000_000, "¥1,000,000"),
        (-850, "-¥850"),
        (-1_280, "-¥1,280"),
    ])
    func formats(amount: Int, expected: String) {
        #expect(YenFormatter.string(from: amount) == expected)
    }

    @Test("Int.min でも桁あふれしない")
    func handlesMinimum() {
        #expect(YenFormatter.string(from: Int.min) == "-¥9,223,372,036,854,775,808")
    }

    @Test("「¥」を付けない表記", arguments: [
        (0, "0"),
        (850, "850"),
        (1_280, "1,280"),
        (-12_000, "-12,000"),
    ])
    func formatsDigits(amount: Int, expected: String) {
        #expect(YenFormatter.digits(from: amount) == expected)
    }

    @Test("符号付きの表記", arguments: [
        (250_000, "+¥250,000"),
        (-850, "-¥850"),
        (0, "¥0"),
    ])
    func formatsSigned(amount: Int, expected: String) {
        #expect(YenFormatter.signedString(from: amount) == expected)
    }
}
