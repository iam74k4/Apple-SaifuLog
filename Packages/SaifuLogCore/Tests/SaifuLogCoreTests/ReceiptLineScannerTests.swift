import Foundation
import Testing
@testable import SaifuLogCore

/// レシートの文字の読み取り（`ReceiptLineScanner`）。Fixture の今日は 2026-09-28 12:00（日本時間）。
@Suite("レシートの文字の読み取り")
struct ReceiptLineScannerTests {
    /// 品目の名前・額（値引きを引く前）・値引き・カテゴリ。
    struct ItemSnapshot: Equatable, CustomStringConvertible {
        var name: String
        var amount: Int
        var discount = 0
        var category: EntryCategory

        var description: String { "\(name) \(amount) -\(discount) \(category)" }
    }

    static func snapshot(_ scan: ReceiptScan) -> [ItemSnapshot] {
        scan.items.map { ItemSnapshot(name: $0.name, amount: $0.amount, discount: $0.discount, category: $0.category) }
    }

    // MARK: - 典型的なレシート

    @Test("スーパーの内税: 店名・日時・品目・軽減税率の印・合計・お預かり・お釣り")
    func supermarketInclusive() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.supermarketInclusive)

        #expect(scan.storeName == "イオン 渋谷店")
        #expect(scan.storeCategory == .food)
        #expect(scan.purchasedOn == ReceiptDate(daysAgo: 1, hour: 18, minute: 32))
        #expect(Self.snapshot(scan) == [
            ItemSnapshot(name: "牛乳", amount: 198, category: .food),
            ItemSnapshot(name: "食パン", amount: 158, category: .food),
            // 辞書に無い品名は、店の既定のカテゴリ（スーパーは食費）。半角のカナは全角にする。
            ItemSnapshot(name: "バナナ", amount: 128, category: .food),
            ItemSnapshot(name: "ティッシュ", amount: 298, category: .daily),
        ])
        #expect(scan.items.map(\.isReducedTaxRate) == [true, true, true, false])
        #expect(scan.subtotal == 782)
        #expect(scan.total == 782)
        #expect(scan.taxMode == .inclusive)
        #expect(scan.exclusiveTax == 0)
        #expect(scan.tendered == 1_000)
        #expect(scan.change == 218)
        #expect(scan.itemsTotal == 782)
        // 住所・電話番号・印の説明は品目にしない。
        #expect(scan.rows.filter { $0.kind == .item }.count == 4)
        #expect(scan.rows.first { $0.text.hasPrefix("TEL") }?.kind == .noise)
        #expect(scan.rows.last?.kind == .noise)
    }

    @Test("スーパーの外税: 小計と外税を足した合計、カード番号の行を見分ける")
    func supermarketExclusive() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.supermarketExclusive)

        #expect(scan.storeName == "業務スーパー 中野店")
        #expect(scan.purchasedOn == ReceiptDate(daysAgo: 2, hour: 10, minute: 5))
        #expect(Self.snapshot(scan) == [
            ItemSnapshot(name: "豚肉", amount: 498, category: .food),
            ItemSnapshot(name: "キャベツ", amount: 158, category: .food),
            ItemSnapshot(name: "卵 10個入", amount: 228, category: .food),
        ])
        #expect(scan.subtotal == 884)
        #expect(scan.taxMode == .exclusive)
        #expect(scan.exclusiveTax == 70)
        #expect(scan.total == 954)
        #expect(scan.rows.contains { $0.kind == .cardNumber && $0.text.hasSuffix("1234") })
        #expect(scan.rows.contains { $0.kind == .payment })
    }

    @Test("コンビニ: 金額の前の「＊」は軽減税率の印、対象額と内消費税の行は品目にしない")
    func convenienceStore() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.convenienceStore)

        #expect(scan.storeName == "セブン-イレブン")
        #expect(scan.storeCategory == .food)
        #expect(scan.purchasedOn == ReceiptDate(daysAgo: 0, hour: 8, minute: 15))
        #expect(Self.snapshot(scan) == [
            ItemSnapshot(name: "おにぎり 鮭", amount: 150, category: .food),
            ItemSnapshot(name: "サンドイッチ", amount: 328, category: .food),
            ItemSnapshot(name: "ホットコーヒーR", amount: 120, category: .cafe),
        ])
        #expect(scan.items.map(\.isReducedTaxRate) == [true, true, false])
        #expect(scan.total == 598)
        #expect(scan.taxMode == .inclusive)
        #expect(scan.rows.filter { $0.kind == .taxBase }.count == 2)
        #expect(scan.rows.contains { $0.kind == .tax })
    }

    @Test("ドラッグストア: 品目の下の値引き（「-100」「▲256」）をその品目から引く")
    func drugstoreDiscounts() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.drugstoreDiscounts)

        #expect(scan.storeName == "マツモトキヨシ 新宿店")
        #expect(scan.storeCategory == .daily)
        #expect(Self.snapshot(scan) == [
            ItemSnapshot(name: "シャンプー", amount: 698, discount: 100, category: .daily),
            ItemSnapshot(name: "目薬", amount: 1_280, discount: 256, category: .medical),
            ItemSnapshot(name: "ポテトチップス", amount: 158, category: .daily),
        ])
        #expect(scan.items.map(\.netAmount) == [598, 1_024, 158])
        #expect(scan.receiptDiscount == 0)
        #expect(scan.itemsTotal == 1_780)
        #expect(scan.total == 1_780)
        #expect(scan.rows.filter { $0.kind == .discount }.count == 2)
    }

    @Test("飲食店の合計だけ: 品目は無く、合計と店名のカテゴリを読む")
    func restaurantTotalOnly() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.restaurantTotalOnly)

        #expect(scan.storeName == "居酒屋 はなこ")
        #expect(scan.storeCategory == .food)
        #expect(scan.purchasedOn == ReceiptDate(daysAgo: 8))
        #expect(scan.items.isEmpty)
        #expect(scan.total == 8_800)
        #expect(!scan.hasNoAmounts)
        #expect(scan.tendered == 10_000)
        #expect(scan.change == 1_200)
    }

    @Test("軽減税率の混在: 「軽」の印の有無を品目ごとに持ち、税の行は品目にしない")
    func mixedTaxRates() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.mixedTaxRates)

        #expect(Self.snapshot(scan) == [
            ItemSnapshot(name: "からあげクン", amount: 238, category: .food),
            ItemSnapshot(name: "緑茶 500ml", amount: 140, category: .food),
            ItemSnapshot(name: "電池 単3 4本", amount: 440, category: .daily),
        ])
        #expect(scan.items.map(\.isReducedTaxRate) == [true, true, false])
        #expect(scan.total == 818)
        // 品目の合計が合計と同じなので、税は品目に含まれている（内税）。
        #expect(scan.taxMode == .inclusive)
        #expect(scan.exclusiveTax == 0)
    }

    @Test("数量 × 単価: 品名の下・上の数量の行、同じ行の数量を品目に合わせる")
    func quantities() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.quantities)

        #expect(Self.snapshot(scan) == [
            ItemSnapshot(name: "もやし", amount: 76, category: .food),
            ItemSnapshot(name: "ヨーグルト", amount: 396, category: .food),
            ItemSnapshot(name: "チョコレート", amount: 196, category: .food),
            ItemSnapshot(name: "豆腐", amount: 264, category: .food),
        ])
        #expect(scan.items.map(\.quantity) == [2, 3, 2, 3])
        #expect(scan.items.map(\.unitPrice) == [38, 132, 98, 88])
        #expect(scan.total == 932)
        #expect(scan.itemsTotal == 932)
    }

    @Test("和暦の日付と、内税・外税の語の無い消費税（小計 + 税 = 合計なら外税）")
    func japaneseEraDate() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.japaneseEraDate)

        #expect(scan.storeName == "コープ みらい")
        #expect(scan.purchasedOn == ReceiptDate(daysAgo: 2, hour: 15, minute: 22))
        #expect(scan.items.map(\.name) == ["ギュウニュウ 1000ml", "タマゴ 10コ"])
        #expect(scan.items.map(\.amount) == [238, 248])
        #expect(scan.taxMode == .exclusive)
        #expect(scan.exclusiveTax == 38)
        #expect(scan.total == 524)
    }

    @Test("合計が読めない: 品目だけを読み、合計は nil のまま")
    func totalMissing() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.totalMissing)

        #expect(scan.storeName == "八百屋 まるやま")
        #expect(scan.items.map(\.amount) == [298, 150, 198])
        #expect(scan.items.allSatisfy { $0.category == .food })
        #expect(scan.total == nil)
        #expect(!scan.hasNoAmounts)
    }

    @Test("品目が 0: 金額の無い紙は、品目も合計も無い")
    func noItems() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.noItems)

        #expect(scan.items.isEmpty)
        #expect(scan.total == nil)
        #expect(scan.hasNoAmounts)
        #expect(!scan.hasNoText)
        // 挨拶の文は店名にしない。
        #expect(scan.storeName == nil)
    }

    @Test("文字が無い: 空の行だけなら、文字が無いと分かる")
    func noText() {
        let scan = ReceiptLineScanner.scan(
            [ReceiptTextLine(""), ReceiptTextLine("   ")], now: Fixture.now, calendar: Fixture.calendar
        )

        #expect(scan.hasNoText)
        #expect(scan.hasNoAmounts)
    }

    @Test("ノイズの多い行: 住所・電話・登録番号・営業時間・レジ・担当者・JAN のコード・点数・URL を品目にしない")
    func noisy() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.noisy)

        #expect(scan.storeName == "スーパーマーケット さくら")
        #expect(scan.purchasedOn == ReceiptDate(daysAgo: 1, hour: 11, minute: 48))
        #expect(Self.snapshot(scan) == [
            ItemSnapshot(name: "キャベツ", amount: 158, category: .food),
            ItemSnapshot(name: "バラ肉", amount: 580, category: .food),
        ])
        #expect(scan.total == 738)
        #expect(scan.tendered == 1_000)
        #expect(scan.change == 262)
        #expect(scan.rows.contains { $0.kind == .count })
    }

    @Test("小計の後の値引きは、品目に付けずにレシート全体の値引きにする")
    func receiptDiscount() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.receiptDiscount)

        #expect(scan.items.map(\.discount) == [0, 0])
        #expect(scan.receiptDiscount == 100)
        #expect(scan.taxMode == .exclusive)
        #expect(scan.exclusiveTax == 46)
        #expect(scan.total == 624)
    }

    @Test("店名と電話番号が 1 行でも、電話番号の前を店名にする")
    func storeNameBeforePhoneNumber() {
        let scan = ReceiptFixtures.scan("""
            業務スーパー 中野店 TEL03-0000-0000
            2026/09/26
            豚肉 498
            合計 ¥498
            """)

        #expect(scan.storeName == "業務スーパー 中野店")
        #expect(scan.items.map(\.amount) == [498])
    }

    // MARK: - 品名と値引き・税の見分け

    @Test("英語の品名の中の OFF（COFFEE・Coffee）は値引きにせず、品目の下の「20%OFF」は値引きにする")
    func englishNamesAreNotDiscounts() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.cafeEnglishNames)

        #expect(scan.storeCategory == .cafe)
        #expect(scan.items.map(\.name) == ["サンドイッチ", "ICED COFFEE", "Coffee"])
        #expect(scan.items.map(\.amount) == [480, 380, 300])
        #expect(scan.items.map(\.discount) == [96, 0, 0])
        #expect(scan.receiptDiscount == 0)
        #expect(scan.itemsTotal == 1_064)
        #expect(scan.total == 1_064)
        #expect(scan.rows.filter { $0.kind == .discount }.count == 1)
    }

    @Test("品名の中の「オフ」「引き」（オフィス・引き出し）は値引きにしない")
    func japaneseNamesAreNotDiscounts() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.officeSupplies)

        #expect(scan.items.map(\.name) == ["ノート", "オフィスクリップ", "引き出し整理トレー"])
        #expect(scan.items.map(\.amount) == [110, 220, 330])
        #expect(scan.items.allSatisfy { $0.discount == 0 })
        #expect(scan.receiptDiscount == 0)
        #expect(scan.itemsTotal == 660)
        #expect(scan.total == 660)
    }

    @Test("値引きの語の見分け", arguments: [
        ("値引", true), ("割引20%", true), ("20%OFF", true), ("50円 OFF", true), ("10%オフ", true), ("30円引", true),
        ("アプリクーポン", true), ("ネビキ", true),
        ("ICED COFFEE", false), ("Coffee", false), ("OFFICE ペン", false), ("オフィスクリップ", false),
        ("引き出し整理トレー", false), ("引越し用ダンボール", false),
    ])
    func discountLabels(label: String, isDiscount: Bool) {
        #expect(ReceiptLineScanner.isDiscountLabel(label) == isDiscount)
    }

    @Test("税率が 1 つの外税で、税率の行とまとめた行の両方があれば、まとめた行だけを税にする")
    func singleRateTaxSummaryIsNotDoubled() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.singleRateExclusiveWithSummary)

        #expect(scan.items.map(\.amount) == [500])
        #expect(scan.subtotal == 500)
        #expect(scan.taxMode == .exclusive)
        #expect(scan.exclusiveTax == 40)
        #expect(scan.total == 540)
        #expect(scan.rows.filter { $0.kind == .tax }.count == 2)
    }

    /// 同じ額でも税率の違う 2 行は、別々の税なので足す。同じ税率を 2 度印字した行と、税率の無いまとめた行は 1 つだけ数える。
    @Test("税の行の合計")
    func taxSums() {
        typealias Tax = ReceiptLineScanner.Parser.TaxLine
        func sum(_ taxes: [(Int, Int?)]) -> Int {
            ReceiptLineScanner.Parser.taxSum(taxes.map { Tax(amount: $0.0, mode: .exclusive, rate: $0.1) })
        }

        #expect(sum([(70, 8)]) == 70)
        #expect(sum([(40, 8), (40, nil)]) == 40)
        #expect(sum([(40, nil), (40, 8)]) == 40)
        #expect(sum([(40, 10), (40, 10)]) == 40)
        #expect(sum([(40, 8), (40, 10)]) == 80)
        #expect(sum([(40, 8), (50, 10)]) == 90)
        #expect(sum([(40, 8), (50, 10), (90, nil)]) == 90)
        #expect(sum([(90, nil), (40, 8), (50, 10)]) == 90)
    }

    @Test("同じ額で税率の違う外税の 2 行は、足して税にする")
    func twoRatesWithSameAmountAreAdded() {
        let scan = ReceiptFixtures.scan("""
            西友 中野店
            2026/09/27 19:20
            牛肉 500
            洗剤 400
            小計 ¥900
            外税8% ¥40
            外税10% ¥40
            合計 ¥980
            """)

        #expect(scan.taxMode == .exclusive)
        #expect(scan.exclusiveTax == 80)
    }

    /// 「うち消費税」は内税の書き方。印が無いと足し算で外税と決めてしまい、税と同じ額の品目を読み落としたことが隠れる。
    @Test("「うち消費税」「(内 消費税等」は内税と読み、読み落としを外税の税と取り違えない")
    func uchiMeansInclusive() {
        let missing = ReceiptFixtures.scan(ReceiptFixtures.inclusiveMissingLine)

        #expect(missing.items.map(\.amount) == [1_000])
        #expect(missing.taxMode == .inclusive)
        #expect(missing.exclusiveTax == 0)
        #expect(missing.total == 1_080)

        let complete = ReceiptFixtures.scan(
            ReceiptFixtures.inclusiveMissingLine.replacingOccurrences(of: "牛乳 ¥1,000", with: "パン ¥80\n牛乳 ¥1,000")
        )
        #expect(complete.itemsTotal == 1_080)
        #expect(complete.taxMode == .inclusive)

        let parenthesized = ReceiptFixtures.scan(
            ReceiptFixtures.inclusiveMissingLine.replacingOccurrences(of: "(うち消費税 ¥80)", with: "(内 消費税等 ¥80)")
        )
        #expect(parenthesized.taxMode == .inclusive)
        #expect(parenthesized.exclusiveTax == 0)
    }

    @Test("時刻が日付より上の行にあっても、日付にその時刻を付ける")
    func timeBeforeDate() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.timeBeforeDate)

        #expect(scan.purchasedOn == ReceiptDate(daysAgo: 1, hour: 18, minute: 32))
        #expect(scan.items.map(\.amount) == [150])
        #expect(scan.rows.filter { $0.kind == .date }.count == 2)
    }

    /// 「·」が品名に残ると（「洗剤 ·」）、⑤ の品目の行にも、記録のメモ・CSV の書き出し・iCloud にもそのまま入る。
    @Test("OCR が「¥」を「·」と読んだ行も、品名に「·」を残さず、金額と集計の行を読む")
    func misreadYenMarks() {
        let scan = ReceiptFixtures.scan(ReceiptFixtures.misreadYenMarks)

        #expect(scan.storeName == "ローソン 中野店")
        #expect(Self.snapshot(scan) == [
            ItemSnapshot(name: "洗剤", amount: 398, category: .daily),
            ItemSnapshot(name: "おにぎり鮭", amount: 150, category: .food),
            ItemSnapshot(name: "緑茶500ml", amount: 138, category: .food),
            ItemSnapshot(name: "グリーンサラダ", amount: 298, category: .food),
            ItemSnapshot(name: "ヨーグルト", amount: 128, category: .food),
        ])
        #expect(scan.subtotal == 1_112)
        #expect(scan.total == 1_112)
        // 1 文字の「計」は、行がその語だけのときに合計の行とみなす。「·」を「¥」として除かないと「計 ·」になり、合計の行と分からない。
        #expect(scan.rows.first { $0.text.hasPrefix("計") }?.kind == .total)
        #expect(scan.itemsTotal == 1_112)
        #expect(scan.tendered == 2_000)
        #expect(scan.change == 888)
    }

    // MARK: - 行のまとめ方

    /// OCR は品名と金額を別の行として返すことが多い。位置が分かれば、縦に重なるものを 1 行にまとめ、左から並べる。
    @Test("位置のある行は、縦に重なるものを 1 行にまとめる（傾いて写っても）")
    func mergesRowsByPosition() {
        func line(_ text: String, x: Double, y: Double, width: Double = 0.2) -> ReceiptTextLine {
            ReceiptTextLine(text, frame: .init(x: x, y: y, width: width, height: 0.02))
        }
        let lines = [
            line("¥198※", x: 0.7, y: 0.305),
            line("牛乳", x: 0.05, y: 0.30),
            line("食パン", x: 0.05, y: 0.33),
            line("¥158", x: 0.7, y: 0.336),
            line("合計", x: 0.05, y: 0.40),
            line("¥356", x: 0.7, y: 0.398),
        ]

        #expect(ReceiptLineScanner.rows(from: lines) == ["牛乳 ¥198※", "食パン ¥158", "合計 ¥356"])
        let scan = ReceiptLineScanner.scan(lines, now: Fixture.now, calendar: Fixture.calendar)
        #expect(scan.items.map(\.name) == ["牛乳", "食パン"])
        #expect(scan.total == 356)
    }

    /// Vision の返し方（行ごとに位置があり、品名と金額が別の塊で、金額の方が少し下に写ることもある）にした Fixture も、
    /// 文字だけの Fixture と同じに読む。値引き・税・数量の行も、位置から行にまとめた後の同じ読み方を通す。
    @Test("位置のある行にした Fixture も、文字だけと同じに読む", arguments: [
        ReceiptFixtures.supermarketInclusive, ReceiptFixtures.supermarketExclusive, ReceiptFixtures.convenienceStore,
        ReceiptFixtures.drugstoreDiscounts, ReceiptFixtures.mixedTaxRates, ReceiptFixtures.quantities,
        ReceiptFixtures.japaneseEraDate, ReceiptFixtures.noisy, ReceiptFixtures.receiptDiscount,
        ReceiptFixtures.cafeEnglishNames, ReceiptFixtures.singleRateExclusiveWithSummary, ReceiptFixtures.misreadYenMarks,
    ])
    func positionedFixturesMatchText(text: String) {
        let positioned = ReceiptLineScanner.scan(ReceiptFixtures.positionedLines(text), now: Fixture.now, calendar: Fixture.calendar)

        #expect(positioned == ReceiptFixtures.scan(text))
    }

    @Test("位置の無い行は渡した順のまま、名前だけの行と金額だけの行を合わせる")
    func joinsNameAndPriceRowsWithoutPosition() {
        let scan = ReceiptFixtures.scan("""
            2026/09/27
            牛乳
            ¥198
            合計
            ¥198
            """)

        #expect(scan.items.map(\.name) == ["牛乳"])
        #expect(scan.items.map(\.amount) == [198])
        #expect(scan.total == 198)
    }

    // MARK: - 金額と日付の読み方

    @Test("行の最後の金額の読み方", arguments: [
        ("牛乳 ¥198", 198, false),
        ("牛乳 198円", 198, false),
        ("牛乳 198※", 198, false),
        ("牛乳 198 軽", 198, false),
        ("牛乳 ¥1,280", 1_280, false),
        ("牛乳 １，２８０", 1_280, false),
        ("値引 -20", 20, true),
        ("値引 ▲20", 20, true),
        ("値引 20-", 20, true),
        ("牛乳198", 198, false),
        ("20%OFF ▲96", 96, true),
        ("20%OFF -96", 96, true),
    ])
    func trailingAmount(text: String, amount: Int, isNegative: Bool) {
        let parsed = ReceiptLineScanner.trailing(in: ReceiptLineScanner.normalize(text))

        #expect(parsed.amount == amount)
        #expect(parsed.isNegative == isNegative)
    }

    /// OCR は「¥」を中点の「·」（U+00B7）と読むことがある。数字にすぐ続き、前が数字でない「·」だけを「¥」とみなし、
    /// 品名の端に残った「·」は除く。
    @Test("数字の直前の「·」は、OCR が読み違えた「¥」とみなす", arguments: [
        ("洗剤 \u{B7}398", "洗剤"),
        ("洗剤\u{B7}398", "洗剤"),
        ("お預り \u{B7}2,000", "お預り"),
    ])
    func misreadYenMark(text: String, body: String) {
        let parsed = ReceiptLineScanner.trailing(in: ReceiptLineScanner.normalize(text))

        #expect(parsed.amount != nil)
        #expect(parsed.hasYenMark)
        #expect(parsed.body == body)
    }

    /// 空白を挟んだ「·」（つなぎの点かもしれない）と、数字に挟まれた「·」（小数点や時刻の読み違いかもしれない）は、「¥」の
    /// 手がかりにしない。品名の端に残った「·」は、どちらでも除く。
    @Test("数字から離れた「·」と、数字に挟まれた「·」は「¥」とみなさない")
    func middleDotAwayFromDigitsIsNotYen() {
        let spaced = ReceiptLineScanner.trailing(in: "洗剤 \u{B7} 398")
        #expect(spaced.amount == 398)
        #expect(!spaced.hasYenMark)
        #expect(ReceiptLineScanner.cleanedName(spaced.body).name == "洗剤")

        let between = ReceiptLineScanner.trailing(in: "1\u{B7}5")
        #expect(!between.hasYenMark)

        #expect(ReceiptLineScanner.cleanedName("おにぎり鮭 \u{B7}").name == "おにぎり鮭")
        // 品名の中の「·」は残す（端だけを除く）。
        #expect(ReceiptLineScanner.cleanedName("カフェ\u{B7}ラテ").name == "カフェ\u{B7}ラテ")
    }

    /// 住所・電話番号・番号・時刻・小数は金額にしない。
    @Test("金額にしない数字", arguments: [
        "渋谷区1-2-3", "TEL03-0000-0000", "No1234", "T1234567890123", "12:30", "1.5", "@98", "SKU-123",
    ])
    func notAnAmount(text: String) {
        #expect(ReceiptLineScanner.trailing(in: ReceiptLineScanner.normalize(text)).amount == nil)
    }

    @Test("レシートの日付の書き方", arguments: [
        ("2026年09月27日(日) 18:32", ReceiptDate(daysAgo: 1, hour: 18, minute: 32)),
        ("2026/9/27", ReceiptDate(daysAgo: 1)),
        ("2026-09-26 10:05:12", ReceiptDate(daysAgo: 2, hour: 10, minute: 5)),
        ("26.09.27 9:05", ReceiptDate(daysAgo: 1, hour: 9, minute: 5)),
        ("令和8年9月26日", ReceiptDate(daysAgo: 2)),
        ("R8.9.26", ReceiptDate(daysAgo: 2)),
        ("令和元年5月1日", ReceiptDate(daysAgo: 2_707)),
        ("9月20日 18時05分", ReceiptDate(daysAgo: 8, hour: 18, minute: 5)),
    ])
    func dates(text: String, expected: ReceiptDate) {
        let date = ReceiptDateReader.date(in: ReceiptLineScanner.normalize(text), now: Fixture.now, calendar: Fixture.calendar)

        #expect(date == expected)
    }

    /// 先の日付（読み違い）、成り立たない日付、電話番号は日付にしない。
    @Test("日付にしないもの", arguments: ["2026/10/01", "2026/02/30", "03-0000-0000", "2026年13月1日"])
    func notADate(text: String) {
        #expect(ReceiptDateReader.date(in: text, now: Fixture.now, calendar: Fixture.calendar) == nil)
    }

    @Test("日付は時刻があればその時刻、無ければ今の時刻のその日にする")
    func receiptDateToDate() {
        #expect(ReceiptDate(daysAgo: 1, hour: 18, minute: 32).date(now: Fixture.now, calendar: Fixture.calendar)
            == Fixture.date(2026, 9, 27, hour: 18, minute: 32))
        #expect(ReceiptDate(daysAgo: 2).date(now: Fixture.now, calendar: Fixture.calendar) == Fixture.date(2026, 9, 26, hour: 12))
    }

    @Test("半角のカナは全角に、全角の英数字は半角にそろえる")
    func normalizesWidths() {
        #expect(ReceiptLineScanner.normalize("ｷﾞｭｳﾆｭｳ　１０００ｍｌ　￥２３８") == "ギュウニュウ 1000ml ¥238")
    }

    @Test("店名のカテゴリ", arguments: [
        ("ファミリーマート 新宿店", EntryCategory.food),
        ("スターバックス コーヒー", .cafe),
        ("ダイソー", .daily),
        ("ウエルシア", .daily),
        ("町の本屋", nil),
    ])
    func storeCategories(name: String, category: EntryCategory?) {
        #expect(ReceiptStoreDictionary.category(forStoreName: name) == category)
    }
}
