import Testing
@testable import SaifuLogCore

@Suite("ルールベースの解析")
struct RuleBasedParserTests {
    func parse(_ text: String) -> [ParsedEntry] {
        Fixture.parser.entries(from: text)
    }

    // MARK: - 設計メモの入力例

    @Test("ランチ 850 → 食費 ¥850")
    func simpleEntry() {
        #expect(parse("ランチ 850") == [ParsedEntry(amount: 850, category: .food, memo: "ランチ")])
    }

    @Test("昨日 焼肉12000 4人で割り勘 → 前日・食費・¥3,000（立替 ¥9,000 はメモ）")
    func splitBill() {
        #expect(parse("昨日 焼肉12000 4人で割り勘") == [
            ParsedEntry(
                amount: 3_000, category: .food, memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）",
                daysAgo: 1, splitCount: 4
            ),
        ])
    }

    @Test("スーパー2480とドラッグ1200 → 2 件に分ける")
    func multipleEntries() {
        #expect(parse("スーパー2480とドラッグ1200") == [
            ParsedEntry(amount: 2_480, category: .food, memo: "スーパー"),
            ParsedEntry(amount: 1_200, category: .daily, memo: "ドラッグ"),
        ])
    }

    @Test("給料 25万 → 収入 ¥250,000")
    func income() {
        #expect(parse("給料 25万") == [ParsedEntry(amount: 250_000, category: .other, isIncome: true, memo: "給料")])
    }

    // MARK: - 金額

    @Test("数字が無ければ空配列", arguments: ["", "  ", "ランチ", "コーヒー代", "0円", "090123456789012"])
    func noAmount(text: String) {
        #expect(parse(text).isEmpty)
    }

    @Test("全角・桁区切り・円・¥・万の表記を読む", arguments: [
        ("ランチ　１２００円", 1_200),
        ("ランチ ¥1,280", 1_280),
        ("ランチ ￥８５０", 850),
        ("ランチ 850円", 850),
        ("家賃 8.5万", 85_000),
        ("家電 1万2千", 12_000),
        ("家電 1万5", 15_000),
    ])
    func amountNotations(text: String, expected: Int) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [expected])
    }

    @Test("金額は最後の数字（数量や日時の数字は除く）", arguments: [
        ("コーヒー2杯 800", 800, "コーヒー2杯"),
        ("ビール 500 2本", 500, "ビール 2本"),
        ("ピザ3人前 3000", 3_000, "ピザ3人前"),
        ("100均 330", 330, "100均"),
        ("ランチ 850 900", 900, "ランチ 850"),
    ])
    func lastNumberIsAmount(text: String, amount: Int, memo: String) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [amount])
        #expect(entries.map(\.memo) == [memo])
    }

    @Test("金額を抜いた跡の助詞はメモに残さない")
    func stripsParticles() {
        #expect(parse("ランチで850").map(\.memo) == ["ランチ"])
    }

    // MARK: - 日付

    @Test("日付の言い回しを何日前かにする", arguments: [
        ("今日 ランチ 850", 0),
        ("ランチ 850", 0),
        ("昨日 ランチ 850", 1),
        ("一昨日 映画 1800", 2),
        ("おととい 映画 1800", 2),
        ("3日前 タクシー 2000", 3),
        ("9/26 ランチ 900", 2),
        ("9月26日 ランチ 900", 2),
    ])
    func dates(text: String, daysAgo: Int) {
        let entries = parse(text)
        #expect(entries.map(\.daysAgo) == [daysAgo])
        #expect(entries.count == 1)
    }

    @Test("日付の数字は金額にもメモにも入れない")
    func dateIsNotAmount() {
        #expect(parse("ランチ 900 9/26") == [ParsedEntry(amount: 900, category: .food, memo: "ランチ", daysAgo: 2)])
    }

    @Test("年から書いた日付は、年も金額にしない", arguments: [
        ("2026/9/26 ランチ 900", 2),
        ("2026/09/26 ランチ 900", 2),
        ("2025/9/28 ランチ 900", 365),
    ])
    func yearFirstDate(text: String, daysAgo: Int) {
        #expect(parse(text) == [ParsedEntry(amount: 900, category: .food, memo: "ランチ", daysAgo: daysAgo)])
    }

    @Test("成り立たない日付（9/31、13/5）も、数字を金額にせず件も分けない", arguments: [
        "9/31 ランチ 900",
        "13/5 ランチ 900",
        "2026/13/5 ランチ 900",
    ])
    func impossibleDate(text: String) {
        #expect(parse(text) == [ParsedEntry(amount: 900, category: .food, memo: "ランチ")])
    }

    @Test("日付は区切った全件にかかる")
    func dateAppliesToAllEntries() {
        #expect(parse("昨日 スーパー2480とドラッグ1200").map(\.daysAgo) == [1, 1])
    }

    // MARK: - 割り勘

    @Test("割り勘の人数と語の並びが違っても割る", arguments: [
        "焼肉12000 4人で割り勘",
        "焼肉12000 4人割り勘",
        "焼肉12000 わりかん 4人",
        "焼肉 12,000円 4名で割勘",
    ])
    func splitVariants(text: String) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [3_000])
        #expect(entries.map(\.splitCount) == [4])
    }

    @Test("割り切れないときは端数を自分が持ち、品目が無ければ説明だけをメモにする")
    func unevenSplitWithoutItem() {
        #expect(parse("1000円を3人で割り勘") == [
            ParsedEntry(amount: 334, category: .other, memo: "3人で割り勘・総額 ¥1,000・立替 ¥666", splitCount: 3),
        ])
    }

    @Test("人数だけ、割り勘の語だけでは割らない", arguments: [
        ("4人でランチ 4000", "4人でランチ"),
        ("焼肉 12000 割り勘", "焼肉 割り勘"),
    ])
    func needsBothWordAndCount(text: String, memo: String) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [text.contains("4000") ? 4_000 : 12_000])
        #expect(entries.map(\.splitCount) == [1])
        #expect(entries.map(\.memo) == [memo])
    }

    // MARK: - 収入

    @Test("収入の語があれば収入", arguments: ["給料 25万", "ボーナス 30万", "副業の報酬 5000", "給与振込 200,000円"])
    func incomeKeywords(text: String) {
        let entries = parse(text)
        #expect(entries.map(\.isIncome) == [true])
        #expect(entries.map(\.category) == [.other])
    }

    @Test("収入は割り勘の語があっても割らない")
    func incomeIsNotSplit() {
        #expect(parse("給料 25万 2人で割り勘").map(\.amount) == [250_000])
    }

    @Test("収入の語を含む支出の言い回しは支出にする", arguments: [
        ("給料日なので焼肉 5000", 5_000, EntryCategory.food),
        ("ボーナスで時計 30000", 30_000, .other),
        ("収入印紙 200", 200, .other),
        ("国民年金 16980", 16_980, .other),
    ])
    func incomeExclusions(text: String, amount: Int, category: EntryCategory) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [amount])
        #expect(entries.map(\.isIncome) == [false])
        #expect(entries.map(\.category) == [category])
    }

    @Test("打ち消す語とは別に収入の語があれば収入")
    func incomeBesideExclusion() {
        #expect(parse("給料日 給料 25万").map(\.isIncome) == [true])
    }

    // MARK: - 複数件

    @Test("区切りの記号で分ける", arguments: [
        "スーパー2480、ドラッグ1200",
        "スーパー2480，ドラッグ1200",
        "スーパー2480\nドラッグ1200",
        "スーパー2480+ドラッグ1200",
    ])
    func separators(text: String) {
        #expect(parse(text).map(\.amount) == [2_480, 1_200])
    }

    @Test("金額の無い区間は次の区間につなげる")
    func mergesSegmentsWithoutAmount() {
        let entries = parse("ランチとコーヒー 1200")
        #expect(entries.map(\.amount) == [1_200])
        #expect(entries.map(\.memo) == ["ランチとコーヒー"])
    }

    @Test("語の中の「と」では分けない")
    func doesNotSplitInsideWords() {
        #expect(parse("ひとり焼肉1500とビール500") == [
            ParsedEntry(amount: 1_500, category: .food, memo: "ひとり焼肉"),
            ParsedEntry(amount: 500, category: .other, memo: "ビール"),
        ])
    }

    @Test("金額の後ろの語が「と」を含んでも、語の途中で割らない", arguments: [
        ("ランチ850 とんかつ弁当900", [
            ParsedEntry(amount: 850, category: .food, memo: "ランチ"),
            ParsedEntry(amount: 900, category: .food, memo: "とんかつ弁当"),
        ]),
        ("パン200 おとうふ100", [
            ParsedEntry(amount: 200, category: .food, memo: "パン"),
            ParsedEntry(amount: 100, category: .other, memo: "おとうふ"),
        ]),
        ("コンビニ500 とり皮200", [
            ParsedEntry(amount: 500, category: .food, memo: "コンビニ"),
            ParsedEntry(amount: 200, category: .other, memo: "とり皮"),
        ]),
    ])
    func doesNotSplitWordsAfterAmount(text: String, expected: [ParsedEntry]) {
        #expect(parse(text) == expected)
    }

    @Test("金額の後ろに 1 語で置いた「と」でも分け、メモには残さない")
    func splitsOnStandaloneTo() {
        #expect(parse("スーパー2480 と ドラッグ1200") == [
            ParsedEntry(amount: 2_480, category: .food, memo: "スーパー"),
            ParsedEntry(amount: 1_200, category: .daily, memo: "ドラッグ"),
        ])
    }

    @Test("3 桁区切りになっていないカンマは区切りとして分ける")
    func splitsOnNonGroupingComma() {
        #expect(parse("スーパー2480,120").map(\.amount) == [2_480, 120])
    }

    @Test("末尾に金額の無い区間が残ったら直前の区間につなげる")
    func mergesTrailingSegment() {
        let entries = parse("ランチ850とコーヒー")
        #expect(entries.map(\.amount) == [850])
        #expect(entries.map(\.memo) == ["ランチとコーヒー"])
    }

    @Test("割り勘は区切った全件にかかる")
    func splitAppliesToAllEntries() {
        #expect(parse("焼肉12000と飲み物3000 3人で割り勘").map(\.amount) == [4_000, 1_000])
    }

    // MARK: - 非同期の入口

    @Test("EntryParsing として呼んでも同じ結果")
    func asyncParse() async throws {
        let parser: any EntryParsing = Fixture.parser
        let entries = try await parser.parse("ランチ 850")
        #expect(entries == [ParsedEntry(amount: 850, category: .food, memo: "ランチ")])
    }
}
