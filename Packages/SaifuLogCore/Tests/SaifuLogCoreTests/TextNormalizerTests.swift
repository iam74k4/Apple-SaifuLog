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
        ("1、280円", "1280円"),
        ("12、800", "12800"),
        ("128、000円", "128000円"),
        ("1、280、000", "1280000"),
        ("1,280、000", "1280000"),
        ("850、カフェ", "850、カフェ"),
        ("2480、120", "2480、120"),
        ("850、400", "850、400"),
        ("850、100円引き", "850、100円引き"),
        ("1、28", "1、28"),
        ("1、2800", "1、2800"),
        ("-1、280円", "-1280円"),
        ("会費年12、000円", "会費年12000円"),
    ])
    func removesThousandsSeparators(input: String, expected: String) {
        #expect(TextNormalizer.normalize(input) == expected)
    }

    // 日付の日や時刻の分を数の先頭の組とみなすと、「9/26、850円」が「9/26850円」になり、¥26,850 のような
    // 金額を黙って記録してしまう。
    @Test("日付・時刻・小数に続く「、」「,」は桁区切りにしない", arguments: [
        "9/26、850円", "12:30、400円", "2026-09-26、850円", "9.26、850円", "9月26、850円",
        "9/26,850円", "12:30,400円",
    ])
    func keepsSeparatorAfterDateOrTime(input: String) {
        #expect(TextNormalizer.normalize(input) == input)
    }

    // Swift の String は「\r\n」を 1 文字として数えるので、そのままだと区切りの記号（「\n」）に当たらない。
    @Test("CRLF と CR を改行（\\n）にそろえる", arguments: [
        ("a\r\nb", "a\nb"), ("a\rb", "a\nb"), ("a\n\r\nb", "a\n\nb"),
    ])
    func normalizesLineBreaks(input: String, expected: String) {
        #expect(TextNormalizer.normalize(input) == expected)
    }

    @Test("マイナス記号の異体（全角・ハイフン・ダッシュ）を「-」にそろえる", arguments: [
        "\u{FF0D}", "\u{2212}", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2015}", "\u{FE63}",
    ])
    func normalizesMinusVariants(sign: String) {
        #expect(TextNormalizer.normalize("\(sign)500") == "-500")
    }
}
