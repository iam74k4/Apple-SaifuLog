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

    // 電話番号は実際の形（11 桁の携帯・10 桁の固定・ハイフン付き）で確かめる。以前は 15 桁の数字だけを見ていて、
    // 11 桁の携帯番号が ¥9,012,345,678 の支出として保存されるのを見逃していた。
    @Test("数字が無ければ空配列", arguments: [
        "", "  ", "ランチ", "コーヒー代", "0円", "09012345678", "0312345678", "090-1234-5678", "03-1234-5678",
    ])
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
        ("家電 1万2千500円", 12_500),
        ("家電 3万2千100円", 32_100),
        ("車 1千万", 10_000_000),
        ("お菓子 5百円", 500),
        ("家電 1万2千3百", 12_300),
        ("ランチ 850 円", 850),
        ("ランチ ¥ 850", 850),
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

    // 以前は成り立たない日付をメモから黙って消していた。今日の記録として保存されるので、読めなかったことに
    // 気づけるよう、メモには残す。
    @Test("成り立たない日付（9/31、13/5）は、数字を金額にせず件も分けず、メモに残す", arguments: [
        ("9/31 ランチ 900", "9/31 ランチ"),
        ("13/5 ランチ 900", "13/5 ランチ"),
        ("2026/13/5 ランチ 900", "2026/13/5 ランチ"),
    ])
    func impossibleDate(text: String, memo: String) {
        #expect(parse(text) == [ParsedEntry(amount: 900, category: .food, memo: memo)])
    }

    @Test("今月に無い日・その年に無い日は、今日の記録にしてメモに残す", arguments: [
        ("31日 家賃 80000", 80_000, "31日 家賃"),
        ("2月29日 1000", 1_000, "2月29日"),
        ("2026年2月30日 家賃 80000", 80_000, "2026年2月30日 家賃"),
    ])
    func unreadDateStaysInMemo(text: String, amount: Int, memo: String) {
        #expect(parse(text) == [ParsedEntry(amount: amount, category: .other, memo: memo)])
    }

    @Test("先頭に置いた日付は、後ろの件にも引き継ぐ", arguments: [
        "昨日 スーパー2480とドラッグ1200",
        "昨日 スーパー2480、ドラッグ1200",
        "昨日、スーパー2480、ドラッグ1200",
    ])
    func leadingDateCarriesForward(text: String) {
        #expect(parse(text).map(\.daysAgo) == [1, 1])
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
        ("給料日 焼肉 5000", 5_000, .food),
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

    @Test("文の後ろに置いた割り勘は、同じ文の件すべてにかかる", arguments: [
        "焼肉12000と飲み物3000 3人で割り勘",
        "焼肉12000、飲み物3000、3人で割り勘",
        "3人で割り勘 焼肉12000と飲み物3000",
    ])
    func trailingSplitAppliesToClause(text: String) {
        #expect(parse(text).map(\.amount) == [4_000, 1_000])
        #expect(parse(text).map(\.splitCount) == [3, 3])
    }

    // MARK: - 件ごとの日付と割り勘

    // 以前は最初に見つけた日付と人数を全件にかけていたため、下の入力でランチが ¥213（4人割り）・昨日になっていた。
    @Test("日付と割り勘は文ごとに割り当てる")
    func perClauseDateAndSplit() {
        #expect(parse("昨日 焼肉12000 4人で割り勘、今日 ランチ 850") == [
            ParsedEntry(
                amount: 3_000, category: .food, memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）",
                daysAgo: 1, splitCount: 4
            ),
            ParsedEntry(amount: 850, category: .food, memo: "ランチ"),
        ])
    }

    @Test("件ごとに書いた日付はその件だけにかかる", arguments: [
        ("9/26 ランチ 900、昨日 カフェ 400", [2, 1]),
        ("昨日スーパー2480、今日ドラッグ1200", [1, 0]),
        ("昨日ランチ850 今日カフェ400", [1, 0]),
    ])
    func perEntryDates(text: String, daysAgo: [Int]) {
        #expect(parse(text).map(\.daysAgo) == daysAgo)
    }

    @Test("後ろに置いた日付は、同じ文の件と、独立して置いたときは全件にかかる", arguments: [
        "スーパー2480とドラッグ1200 昨日",
        "ランチ850、コーヒー400、昨日",
    ])
    func trailingDate(text: String) {
        #expect(parse(text).map(\.daysAgo) == [1, 1])
    }

    @Test("割り勘や日付のある文の後ろの件には、その割り勘や日付をかけない", arguments: [
        "焼肉12000 3人で割り勘、ランチ 850",
        "焼肉 12000 割り勘 3人、ランチ 850",
    ])
    func splitDoesNotLeakToNextClause(text: String) {
        #expect(parse(text).map(\.amount) == [4_000, 850])
        #expect(parse(text).map(\.splitCount) == [3, 1])
    }

    @Test("金額の後ろに置いた日付は、その件の日付にする（次の文へは引き継ぐ）")
    func dateAfterAmountBelongsToEntry() {
        #expect(parse("ランチ 850 昨日、カフェ 400").map(\.daysAgo) == [1, 1])
        #expect(parse("ランチ 850 昨日、今日 カフェ 400").map(\.daysAgo) == [1, 0])
    }

    // MARK: - 1 人分の額

    // 以前は 1 人分の額もさらに人数で割り、¥750 で保存していた。
    // メモには以前、総額や割り勘の語がそのまま残っていた（「焼肉 12000 4人で割り勘」）。記録した額と違う金額が
    // 並ばないよう除き、1 人分であることを書き足す。
    @Test("1 人分として書いた額は割らず、メモには総額を残さずに 1 人分と書き足す", arguments: [
        ("4人で割り勘 1人あたり3000円", "4人で割り勘・1人分"),
        ("焼肉 12000 4人で割り勘 1人3000", "焼肉（4人で割り勘・1人分）"),
        ("割り勘で1人3000 4人", "4人で割り勘・1人分"),
        ("焼肉 4人で割り勘 一人 3000", "焼肉（4人で割り勘・1人分）"),
        ("焼肉 12000 ひとり3000", "焼肉（1人分）"),
    ])
    func perPersonAmountIsNotSplit(text: String, memo: String) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [3_000])
        #expect(entries.map(\.splitCount) == [1])
        #expect(entries.map(\.memo) == [memo])
    }

    // 以前は金額を先に書く並びで、総額と 1 人分の額を別の件に分け、同じ支出を 2 度記録していた（¥3,000 が 2 件）。
    @Test("総額を先に書いても、1 人分の額とは分けずに 1 件にする", arguments: [
        ("12000 焼肉 4人で割り勘 1人3000", 3_000, "焼肉（4人で割り勘・1人分）"),
        ("3000円 ランチ 1人1500", 1_500, "ランチ（1人分）"),
        ("12000 焼肉 1人3000 割り勘 4人", 3_000, "焼肉（4人で割り勘・1人分）"),
    ])
    func perPersonAfterTotalIsOneEntry(text: String, amount: Int, memo: String) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [amount])
        #expect(entries.map(\.memo) == [memo])
    }

    @Test("割り勘の人数は、割り勘の語に最も近い人数を採る")
    func nearestPeopleCount() {
        let entries = parse("友達3人と焼肉 12000 4人で割り勘")
        #expect(entries.map(\.amount) == [3_000])
        #expect(entries.map(\.splitCount) == [4])
    }

    // MARK: - 年月日・時刻・掛け算

    @Test("年まで書いた漢字の日付・2 桁の年・和暦の略記は、年も金額やメモにしない", arguments: [
        ("2025年9月26日 ランチ 900", 367),
        ("25/9/26 ランチ 900", 367),
        ("R7/9/26 ランチ 900", 367),
        ("2026-09-26 ランチ 900", 2),
        ("ランチ 900 9.26", 2),
        ("ランチ 900 9-26", 2),
    ])
    func writtenDates(text: String, daysAgo: Int) {
        #expect(parse(text) == [ParsedEntry(amount: 900, category: .food, memo: "ランチ", daysAgo: daysAgo)])
    }

    @Test("時刻は金額にも区切りにもしない", arguments: ["ランチ 850 12:30", "12:30 ランチ 850", "ランチ 12:30 850"])
    func timeIsNotAmount(text: String) {
        #expect(parse(text) == [ParsedEntry(amount: 850, category: .food, memo: "ランチ")])
    }

    @Test("位の付かない小数は金額にしない（単位の付いた小数は量のまま残す）")
    func decimalWithoutUnit() {
        #expect(parse("ビール 1.5L 300") == [ParsedEntry(amount: 300, category: .other, memo: "ビール 1.5L")])
        #expect(parse("家賃 8.5万").map(\.amount) == [85_000])
    }

    @Test("掛け算は単価と個数を掛けた額にし、個数を金額にしない", arguments: [
        ("ビール 500×3", 1_500, "ビール"),
        ("コーヒー 400 ×2", 800, "コーヒー"),
        ("りんご2個×300", 600, "りんご"),
        ("ビール 500x3本", 1_500, "ビール"),
        ("コーヒー×2 800", 800, "コーヒー×2"),
        ("ランチ 850 × 2人", 1_700, "ランチ"),
    ])
    func multiplication(text: String, amount: Int, memo: String) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [amount])
        #expect(entries.map(\.memo) == [memo])
    }

    @Test("先の月日は未来の日付、日だけの表記は今月のその日として読み、メモに残さない", arguments: [
        ("9/29 家賃 80000", -1),
        ("26日 家賃 80000", 2),
        ("30日 家賃 80000", -2),
        ("家賃 80000 30日", -2),
    ])
    func futureAndDayOnlyDates(text: String, daysAgo: Int) {
        #expect(parse(text) == [ParsedEntry(amount: 80_000, category: .other, memo: "家賃", daysAgo: daysAgo)])
    }

    @Test("「3日間」「2泊3日」は期間なので日付にしない", arguments: ["3日間 ホテル", "2泊3日 ホテル"])
    func periodIsNotDate(memo: String) {
        #expect(parse("\(memo) 30000") == [ParsedEntry(amount: 30_000, category: .other, memo: memo)])
    }

    @Test("日付の直後の助詞もメモに残さない", arguments: [
        ("昨日の飲み会 4000", "飲み会", 1),
        ("9/26の飲み会 3000", "飲み会", 2),
        ("3日前のタクシー 2000", "タクシー", 3),
        ("今日もランチ 850", "ランチ", 0),
        ("昨日は焼肉 5000", "焼肉", 1),
        ("2026年9月26日の飲み会 3000", "飲み会", 2),
        ("昨日のうどん 800", "うどん", 1),
        ("昨日のお茶 150", "お茶", 1),
        ("今日もご飯 500", "ご飯", 0),
    ])
    func stripsParticleAfterDate(text: String, memo: String, daysAgo: Int) {
        let entries = parse(text)
        #expect(entries.map(\.memo) == [memo])
        #expect(entries.map(\.daysAgo) == [daysAgo])
    }

    // 以前は「の」「は」をいつでも助詞として取り、「昨日のり」のメモが「り」、「今日はちみつ」が「ちみつ」になっていた。
    @Test("日付の後ろの語の頭のひらがなは残す", arguments: [
        ("昨日もやし 100", "もやし"), ("昨日にんじん 200", "にんじん"), ("今日にら 200", "にら"),
        ("昨日のり 300", "のり"), ("昨日のど飴 200", "のど飴"), ("昨日のみ 4000", "のみ"), ("今日はちみつ 500", "はちみつ"),
    ])
    func keepsWordAfterDate(text: String, memo: String) {
        #expect(parse(text).map(\.memo) == [memo])
    }

    // MARK: - 返金

    @Test("マイナスを付けた額は返金として収入にし、メモに「-」を残さない", arguments: [
        ("返金 -500", "返金"),
        ("返金 −500", "返金"),
        ("返金-500", "返金"),
        ("返金 ー500", "返金"),
        ("返品 ¥-1,200", "返品"),
        ("-500円 キャンセル", "キャンセル"),
    ])
    func negativeAmountIsRefund(text: String, memo: String) {
        let entries = parse(text)
        #expect(entries.count == 1)
        #expect(entries.first?.isIncome == true)
        #expect(entries.first?.category == .other)
        #expect(entries.first?.memo == memo)
    }

    @Test("語の一部の長音記号や日付・番号の「-」は符号にしない", arguments: [
        ("コーヒー500", false),
        ("ランチ 850 9-26", false),
    ])
    func hyphenInsideWordsIsNotMinus(text: String, isIncome: Bool) {
        #expect(parse(text).map(\.isIncome) == [isIncome])
    }

    // MARK: - 収入の打ち消しと追加の語

    @Test("収入の語の後ろに支出の語が続けば支出にする", arguments: [
        "入金手数料 330", "収入保障保険 3000", "個人年金保険 12000", "副業の経費 5000", "給料から天引き 2000",
        "配当再投資 10000",
    ])
    func expenseWordAfterIncomeKeyword(text: String) {
        #expect(parse(text).map(\.isIncome) == [false])
    }

    // 「給料日」は支出の言い回し（「給料日なので焼肉」）の打ち消しの語でもある。受け取った語が続くときと、
    // ほかに語が無いときは給料の記録なので、打ち消さない。
    @Test("よくある収入の書き方を収入にする", arguments: [
        "バイト代 8万", "ボーナスでた 30万", "ボーナスでました 30万", "給料日 手取り 25万", "日給 12000",
        "お年玉もらった 10000", "所得税の還付 30000", "給料日 入った 25万", "給料日 25万", "給料日 ¥250,000",
    ])
    func moreIncomePhrases(text: String) {
        #expect(parse(text).map(\.isIncome) == [true])
    }

    @Test("もらう・あげるの両方に使う語だけでは収入にしない", arguments: ["お年玉 5000", "ボーナスでマッサージ 8000"])
    func ambiguousGiftIsExpense(text: String) {
        #expect(parse(text).map(\.isIncome) == [false])
    }

    // MARK: - 区切り

    @Test("「。」でも分ける")
    func splitsOnPeriod() {
        #expect(parse("ランチ850。コーヒー400") == [
            ParsedEntry(amount: 850, category: .food, memo: "ランチ"),
            ParsedEntry(amount: 400, category: .cafe, memo: "コーヒー"),
        ])
    }

    @Test("区切らずに続けた複数件は、金額の後ろにカタカナの品目が続くところで分ける", arguments: [
        ("スーパー2480ドラッグ1200", [
            ParsedEntry(amount: 2_480, category: .food, memo: "スーパー"),
            ParsedEntry(amount: 1_200, category: .daily, memo: "ドラッグ"),
        ]),
        ("ランチ850円コーヒー400円", [
            ParsedEntry(amount: 850, category: .food, memo: "ランチ"),
            ParsedEntry(amount: 400, category: .cafe, memo: "コーヒー"),
        ]),
    ])
    func splitsWithoutSeparator(text: String, expected: [ParsedEntry]) {
        #expect(parse(text) == expected)
    }

    // 「ドラクエ12ソフト 8000」「コーラ500ペットボトル 160」は、一時「金額→カタカナの語→空白→金額」でも
    // 区切っていて、¥12 と ¥8000 のような偽の記録ができていた。
    @Test("型番や店名の数字では分けない", arguments: [
        ("iPhone15ケース2000", 2_000, "iPhone15ケース"),
        ("セブン11で500", 500, "セブン11"),
        ("100円ショップで500円", 500, "100円ショップ"),
        ("ペットボトル500ミリ 150", 150, "ペットボトル500ミリ"),
        ("500ポイント使って 1200", 1_200, "500ポイント使って"),
        ("ドラクエ12ソフト 8000", 8_000, "ドラクエ12ソフト"),
        ("コーラ500ペットボトル 160", 160, "コーラ500ペットボトル"),
        ("109で服 5000", 5_000, "109で服"),
    ])
    func doesNotSplitModelNumbers(text: String, amount: Int, memo: String) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [amount])
        #expect(entries.map(\.memo) == [memo])
    }

    @Test("空白を挟んだ「円」は金額に含め、次の件のメモの頭に付けない")
    func yenAfterSpace() {
        #expect(parse("ランチ 850 円、コーヒー 400 円").map(\.memo) == ["ランチ", "コーヒー"])
    }

    @Test("金額を先に書く複数件は、金額の後ろの語をその件の品目にする", arguments: [
        "850 ランチ 400 コーヒー",
        "850円 ランチ、400円 コーヒー",
        "¥850 ランチ と ¥400 コーヒー",
    ])
    func amountFirstEntries(text: String) {
        #expect(parse(text) == [
            ParsedEntry(amount: 850, category: .food, memo: "ランチ"),
            ParsedEntry(amount: 400, category: .cafe, memo: "コーヒー"),
        ])
    }

    // 金額で始まっても、最後が金額で終わる入力は、金額を先に書く並びとして読まない。以前は「3 コーヒー 1200」で
    // 「コーヒー」が ¥3 の件の品目になり、¥1,200 の件の品目が空になっていた。
    @Test("金額で終わる入力では、最後の金額の件に前の語を品目として付ける")
    func trailingAmountIsNotAmountFirst() {
        #expect(parse("3 コーヒー 1200").last == ParsedEntry(amount: 1_200, category: .cafe, memo: "コーヒー"))
    }

    // MARK: - 「.」「-」の数字・値引き・記号

    // 以前は「.」「-」でつないだ数字をいつでも日付として読み、「ver1.2」が 269 日前、「3-4人」が割り勘されずに
    // 208 日前の記録になっていた。
    @Test("型番・版・小数・人数の幅の「.」「-」は日付にしない", arguments: [
        ("ver1.2 アプリ 600", 600, "ver1.2 アプリ"),
        ("10.5 ランチ 850", 850, "10.5 ランチ"),
        ("ガソリン 1.5 3000", 3_000, "ガソリン 1.5"),
        ("PS5-2 500", 500, "PS5-2"),
    ])
    func dottedNumbersAreNotDates(text: String, amount: Int, memo: String) {
        let entries = parse(text)
        #expect(entries.map(\.amount) == [amount])
        #expect(entries.map(\.memo) == [memo])
        #expect(entries.map(\.daysAgo) == [0])
    }

    @Test("人数の幅（3-4人）は、上限の人数で割り勘にする")
    func peopleRangeIsNotDate() {
        #expect(parse("3-4人で割り勘 12000") == [
            ParsedEntry(amount: 3_000, category: .other, memo: "4人で割り勘・総額 ¥12,000・立替 ¥9,000", splitCount: 4),
        ])
    }

    @Test("「.」でつないだ月日は、日を 2 桁で書けば日付として読む")
    func dottedDateWithTwoDigitDay() {
        #expect(parse("ランチ 900 10.05") == [ParsedEntry(amount: 900, category: .food, memo: "ランチ", daysAgo: -7)])
    }

    // 以前は括弧の中の「-100」を返金とみなして区間の最後の金額に採り、¥850 の支出が ¥100 の収入になっていた。
    @Test("正の金額の後ろのマイナスの額は値引きで、返金にも金額にもしない", arguments: [
        "ランチ 850(-100引き)", "ランチ 850（-100引き）", "ランチ 850 (-100引き)",
    ])
    func discountIsNotRefund(text: String) {
        #expect(parse(text) == [ParsedEntry(amount: 850, category: .food, memo: "ランチ (-100引き)")])
    }

    @Test("金額のすぐ後ろのマイナスの額も値引きにし、語を挟んだ返金は別の件にする")
    func discountRightAfterAmount() {
        #expect(parse("ランチ 1000 -200") == [ParsedEntry(amount: 1_000, category: .food, memo: "ランチ -200")])
        #expect(parse("ランチ 850 返金 -500") == [
            ParsedEntry(amount: 850, category: .food, memo: "ランチ"),
            ParsedEntry(amount: 500, category: .other, isIncome: true, memo: "返金"),
        ])
    }

    // 以前は単独で置いた「x」も掛け算の記号とみなし、後ろの 500 を個数として捨てて「金額が無い」にしていた。
    @Test("記号の後ろの数字は、ほかに金額が無ければ金額にする", arguments: ["x 500", "×500", "x500"])
    func numberAfterSignWithoutOtherAmount(text: String) {
        #expect(parse(text).map(\.amount) == [500])
    }

    // MARK: - 非同期の入口

    @Test("EntryParsing として呼んでも同じ結果")
    func asyncParse() async throws {
        let parser: any EntryParsing = Fixture.parser
        let entries = try await parser.parse("ランチ 850")
        #expect(entries == [ParsedEntry(amount: 850, category: .food, memo: "ランチ")])
    }
}
