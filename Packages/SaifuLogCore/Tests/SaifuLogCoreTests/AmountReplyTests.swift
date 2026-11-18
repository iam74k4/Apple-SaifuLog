import Testing
@testable import SaifuLogCore

@Suite("金額の聞き返しへの返事")
struct AmountReplyTests {
    @Test("金額だけの返事は、前の文に足す金額の表記を返す", arguments: [
        ("850", "850"),
        (" 850 ", "850"),
        ("850円", "850円"),
        ("８５０円", "850円"),
        ("¥1,200", "¥1200"),
        ("1.2万", "1.2万"),
        ("3千円", "3千円"),
        ("850です", "850"),
        ("850円でした", "850円"),
        ("850くらい", "850"),
        ("850円ぐらいでした", "850円"),
        ("約850円", "850円"),
        ("だいたい1200", "1200"),
        ("850!", "850"),
        ("850円です。", "850円"),
        ("税込1100", "税込1100"),
    ])
    func readsAmountOnlyReply(text: String, expected: String) {
        #expect(AmountReply.amountText(in: text) == expected)
    }

    /// 品目・日付・人数のある文は新しい記録として読む（前の文の品目で記録しないため）。マイナス・1 人分・添えた額・0 円は、
    /// 前の文に足すと意味が変わるので金額だけとみなさない。
    @Test("金額だけでない文は nil", arguments: [
        "",
        "ランチ",
        "コーヒー 400",
        "400 コーヒー",
        "昨日 850",
        "4人で 12000",
        "850と400",
        "-500",
        "1人あたり3000",
        "おつり150円",
        "ポイント100",
        "0",
        "今月いくら?",
        "さっきのを900に直して",
    ])
    func rejectsOtherText(text: String) {
        #expect(AmountReply.amountText(in: text) == nil)
    }

    /// 前の文の後ろに足して読むと、前の文の日付・割り勘・品目がそのまま効く（ふつうに 1 行で送ったときと同じ記録になる）。
    @Test("前の文に足して、1 行で送ったときと同じ記録に読める")
    func combinedTextParsesLikeOneLine() throws {
        func combined(_ question: String, _ reply: String) throws -> [ParsedEntry] {
            let amount = try #require(AmountReply.amountText(in: reply))
            return Fixture.parser.entries(from: "\(question) \(amount)")
        }
        #expect(try combined("ランチ", "850円です") == Fixture.parser.entries(from: "ランチ 850"))
        #expect(try combined("昨日 タクシー", "1200") == Fixture.parser.entries(from: "昨日 タクシー 1200"))
        #expect(
            try combined("昨日 焼肉 4人で割り勘", "1.2万")
                == Fixture.parser.entries(from: "昨日 焼肉 4人で割り勘 1.2万")
        )
        #expect(try combined("昨日 焼肉 4人で割り勘", "1.2万").first?.amount == 3_000)
    }
}
