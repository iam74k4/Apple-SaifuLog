import Testing
@testable import SaifuLogCore

@Suite("表記ゆれの吸収")
struct TextNormalizerTests {
    @Test("全角の数字・記号・スペースを半角にする", arguments: [
        ("１２００円", "1200円"),
        ("￥８５０", "¥850"),
        ("ランチ　８５０", "ランチ 850"),
        ("ＳＵＩＣＡ", "SUICA"),
    ])
    func convertsFullwidth(input: String, expected: String) {
        #expect(TextNormalizer.normalize(input) == expected)
    }

    @Test("カタカナは半角にしない")
    func keepsKatakana() {
        #expect(TextNormalizer.normalize("ランチ") == "ランチ")
    }

    @Test("桁区切りのカンマだけを取り除く", arguments: [
        ("1,280", "1280"),
        ("¥1,000,000", "¥1000000"),
        ("１，２８０円", "1280円"),
        ("2480,1200", "2480,1200"),
        ("2480,120", "2480,120"),
        ("2480,120,500", "2480,120,500"),
        ("12,300", "12300"),
        ("1,0000", "1,0000"),
        ("12,34", "12,34"),
        ("A,B", "A,B"),
    ])
    func removesThousandsSeparators(input: String, expected: String) {
        #expect(TextNormalizer.normalize(input) == expected)
    }
}
