import Testing
@testable import SaifuLogCore

@Suite("AI の出力の突き合わせ")
struct ExtractedEntryTests {
    func extracted(
        item: String = "焼肉",
        amount: String = "12000",
        category: String = "食費",
        isIncome: Bool = false,
        split: Int = 1,
        date: String = ""
    ) -> ExtractedEntry {
        ExtractedEntry(
            item: item, amountText: amount, categoryName: category,
            isIncome: isIncome, splitCount: split, dateText: date
        )
    }

    func resolve(_ entry: ExtractedEntry, _ input: String) throws -> ParsedEntry {
        try entry.resolved(against: input, now: Fixture.now, calendar: Fixture.calendar)
    }

    func input(_ text: String) -> EntryInput {
        EntryInput(text, now: Fixture.now, calendar: Fixture.calendar)
    }

    @Test("入力に書かれた値はそのまま使い、割り算はコードで行う")
    func groundedValues() throws {
        let entry = try resolve(extracted(split: 4, date: "昨日"), "昨日 焼肉12000 4人で割り勘")
        #expect(entry == ParsedEntry(
            amount: 3_000, category: .food, memo: "焼肉（4人で割り勘・総額 ¥12,000・立替 ¥9,000）",
            daysAgo: 1, splitCount: 4
        ))
    }

    @Test("入力に無い金額（計算した値）は使わない")
    func ungroundedAmountThrows() {
        #expect(throws: ExtractedEntry.ResolveError.ungroundedAmount) {
            try resolve(extracted(amount: "3000", split: 4), "昨日 焼肉12000 4人で割り勘")
        }
    }

    // 以前は AmountParser.isGrounded に向けていたテスト。本番で突き合わせるのは resolved なので、こちらに移した。
    // 割り勘の入力は、入力の 4 人で割った額になる（¥12,000 → ¥3,000）。
    @Test("表記が違っても、入力に書かれた金額なら採る", arguments: [
        ("12000", "昨日 焼肉12000 4人で割り勘", 3_000),
        ("12,000円", "昨日 焼肉12000 4人で割り勘", 3_000),
        ("25万", "給料 25万", 250_000),
        ("250000", "給料 25万", 250_000),
        ("2480", "スーパー2480とドラッグ1200", 2_480),
        ("12500", "家電 1万2千500円", 12_500),
        ("1500", "ビール 500×3", 1_500),
        ("500", "ビール 500×3", 1_500),
    ])
    func acceptsGroundedAmount(amountText: String, input: String, amount: Int) throws {
        #expect(try resolve(extracted(amount: amountText), input).amount == amount)
    }

    // 掛け算は、単価（500）を返されても掛けた額で記録する。個数（3）は金額として突き合わせない。
    @Test("入力に無い金額（計算した値・人数・作った数字・読み違えた端数・個数）は採らない", arguments: [
        ("3000", "昨日 焼肉12000 4人で割り勘"),
        ("4", "昨日 焼肉12000 4人で割り勘"),
        ("3680", "スーパー2480とドラッグ1200"),
        ("なし", "ランチ 850"),
        ("500", "家電 1万2千500円"),
        ("3", "ビール 500×3"),
    ])
    func rejectsUngroundedAmount(amountText: String, input: String) {
        #expect(throws: ExtractedEntry.ResolveError.ungroundedAmount) {
            try resolve(extracted(amount: amountText), input)
        }
    }

    @Test("割り勘の語か人数が入力に無ければ、人数を返されても割らない", arguments: [
        ("焼肉 12000 割り勘", 2),
        ("4人で焼肉 12000", 4),
    ])
    func ungroundedSplitIsIgnored(input: String, split: Int) throws {
        let entry = try resolve(extracted(split: split), input)
        #expect(entry.amount == 12_000)
        #expect(entry.splitCount == 1)
    }

    // 以前は上のテストに ("焼肉12000 4人で割り勘", 3) が入っていて、モデルが違う人数を返すと割らずに
    // ¥12,000 で保存する動作を固定していた。ルールベースと同じく入力の 4 人で割る。
    @Test("モデルの人数が入力と違っても、1 を返しても、入力の人数で割る", arguments: [3, 1, 5])
    func splitFollowsInput(split: Int) throws {
        let entry = try resolve(extracted(split: split), "焼肉12000 4人で割り勘")
        #expect(entry.amount == 3_000)
        #expect(entry.splitCount == 4)
    }

    @Test("1 人分として書かれた額は、人数を返されても割らず、ルールベースと同じく 1 人分と書き足す")
    func perPersonAmountIsNotSplit() throws {
        let entry = try resolve(extracted(item: "焼肉", amount: "3000", split: 4), "焼肉 4人で割り勘 1人あたり3000円")
        #expect(entry == ParsedEntry(amount: 3_000, category: .food, memo: "焼肉（4人で割り勘・1人分）"))
    }

    @Test("入力に無い日付の表記は使わず、入力そのものから読む", arguments: [
        ("昨日", "焼肉 12000", 0),
        ("昨日", "一昨日 焼肉 12000", 2),
        ("", "昨日 焼肉 12000", 1),
        ("9/20", "9/26 焼肉 12000", 2),
    ])
    func ungroundedDateFallsBackToInput(date: String, input: String, daysAgo: Int) throws {
        #expect(try resolve(extracted(date: date), input).daysAgo == daysAgo)
    }

    @Test("日付が複数ある入力では、件ごとの日付の表記を使う")
    func perEntryDate() throws {
        let input = "昨日スーパー2480、今日ドラッグ1200"
        let first = try resolve(extracted(item: "スーパー", amount: "2480", date: "昨日"), input)
        let second = try resolve(extracted(item: "ドラッグ", amount: "1200", category: "日用品", date: "今日"), input)
        #expect(first.daysAgo == 1)
        #expect(second.daysAgo == 0)
    }

    @Test("知らないカテゴリ名はその他にする")
    func unknownCategory() throws {
        #expect(try resolve(extracted(category: "外食"), "焼肉 12000").category == .other)
    }

    // MARK: - 収入

    @Test("打ち消しの語や支出の言い回しがあれば、モデルが収入と返しても支出にする", arguments: [
        ("収入印紙", "200", "収入印紙 200"),
        ("入金手数料", "330", "入金手数料 330"),
        ("個人年金保険", "12000", "個人年金保険 12000"),
    ])
    func contradictedIncomeIsExpense(item: String, amount: String, input: String) throws {
        let entry = try resolve(extracted(item: item, amount: amount, category: "その他", isIncome: true), input)
        #expect(!entry.isIncome)
    }

    // 以前は「給料日」をいつでも打ち消しの語として扱い、モデルが収入と読んでも支出に戻していた。
    @Test("給料日の給料の記録は、モデルが収入と返せば収入にする", arguments: ["給料日 25万", "給料日 入った 25万"])
    func paydayIncomeIsKept(input: String) throws {
        let entry = try resolve(extracted(item: "給料", amount: "25万", category: "その他", isIncome: true), input)
        #expect(entry.isIncome)
    }

    @Test("給料日の支出の言い回しは、モデルが収入と返しても支出にする")
    func paydayExpenseIsExpense() throws {
        let entry = try resolve(
            extracted(item: "焼肉", amount: "5000", category: "食費", isIncome: true), "給料日なので焼肉 5000"
        )
        #expect(!entry.isIncome)
    }

    @Test("収入の語が無いだけなら、モデルの「収入」を採る")
    func incomeWithoutKeywordIsKept() throws {
        let entry = try resolve(
            extracted(item: "お小遣い", amount: "3000", category: "その他", isIncome: true), "お小遣いもらった 3000"
        )
        #expect(entry.isIncome)
    }

    @Test("マイナスを付けた額は、モデルの答えによらず返金として収入にする")
    func negativeAmountIsIncome() throws {
        let entry = try resolve(extracted(item: "返金", amount: "500", category: "その他", isIncome: false), "返金 -500")
        #expect(entry == ParsedEntry(amount: 500, category: .other, isIncome: true, memo: "返金"))
    }

    // 以前は値引きの「-100」も返金とみなし、モデルが 100 を返すと ¥100 の収入で保存していた。
    @Test("正の金額の後ろの値引きの額は突き合わせず、ルールベースで読み直させる")
    func discountAmountIsNotGrounded() throws {
        #expect(throws: ExtractedEntry.ResolveError.ungroundedAmount) {
            try resolve(extracted(item: "ランチ", amount: "100"), "ランチ 850(-100引き)")
        }
        let entry = try resolve(extracted(item: "ランチ", amount: "850"), "ランチ 850(-100引き)")
        #expect(entry == ParsedEntry(amount: 850, category: .food, memo: "ランチ"))
    }

    // MARK: - 品目とカテゴリ

    @Test("品目が日付の語だけなら、ルールベースのメモとカテゴリにする")
    func dateOnlyItemFallsBack() throws {
        let entry = try resolve(extracted(item: "昨日", amount: "1200", category: "食費"), "昨日 1200")
        #expect(entry == ParsedEntry(amount: 1_200, category: .other, memo: "", daysAgo: 1))
    }

    @Test("入力に無い品目は使わず、ルールベースのメモとカテゴリにする", arguments: [
        ("ランチ代", "ランチ 850", "ランチ", EntryCategory.food),
        ("スーパーで買い物", "1200", "", .other),
    ])
    func ungroundedItemFallsBack(item: String, input: String, memo: String, category: EntryCategory) throws {
        let amount = String(AmountParser.yen(from: input) ?? 0)
        let entry = try resolve(extracted(item: item, amount: amount, category: "娯楽"), input)
        #expect(entry.memo == memo)
        #expect(entry.category == category)
    }

    @Test("品目から金額・日付・人数を除き、入力に書かれた品目ならモデルのカテゴリを使う")
    func groundedItemKeepsModelCategory() throws {
        let entry = try resolve(extracted(item: "昨日の焼肉 12000", category: "娯楽"), "昨日 焼肉 12000")
        #expect(entry.memo == "焼肉")
        #expect(entry.category == .entertainment)
    }

    // 以前は品目から数字を抜いた残りをメモにしていて、「セブン11」が「セブン」、「100円ショップ」が「ショップ」になり、
    // ルールベースのメモと食い違っていた。
    @Test("数字を含む店名や品名は、区間に書かれたとおりにメモにする", arguments: [
        ("セブン11", "500", "セブン11で500"),
        ("100円ショップ", "500円", "100円ショップで500円"),
        ("iPhone15ケース", "2000", "iPhone15ケース2000"),
    ])
    func itemWithDigitsIsKept(item: String, amount: String, input: String) throws {
        let entry = try resolve(extracted(item: item, amount: amount, category: "日用品"), input)
        #expect(entry.memo == item)
        #expect(entry.memo == Fixture.parser.entries(from: input).first?.memo)
    }

    @Test("品目にその件の金額が入っていたら、金額は除いてメモにする")
    func itemWithChosenAmountIsCleaned() throws {
        #expect(try resolve(extracted(item: "焼肉 12000"), "焼肉 12000").memo == "焼肉")
    }

    // MARK: - 全件の照合

    @Test("区間ごとの結果をまとめて突き合わせる")
    func resolveAllPerSegment() throws {
        let parsed = input("昨日 スーパー2480とドラッグ1200")
        let entries = try ExtractedEntry.resolveAll([
            extracted(item: "スーパー", amount: "2480", date: "昨日"),
            extracted(item: "ドラッグ", amount: "1200", category: "日用品"),
        ], against: parsed)
        #expect(entries == [
            ParsedEntry(amount: 2_480, category: .food, memo: "スーパー", daysAgo: 1),
            ParsedEntry(amount: 1_200, category: .daily, memo: "ドラッグ", daysAgo: 1),
        ])
    }

    @Test("件数が区間の数と合わなければ throw する（同じ記録の繰り返し・抜け）", arguments: [
        ("コーヒー 400", 2),
        ("スーパー2480とドラッグ1200", 1),
        ("スーパー2480とドラッグ1200", 3),
    ])
    func resolveAllRejectsCountMismatch(text: String, count: Int) {
        let entries = Array(repeating: extracted(item: "コーヒー", amount: "400", category: "カフェ"), count: count)
        #expect(throws: ExtractedEntry.ResolveError.entryCountMismatch) {
            try ExtractedEntry.resolveAll(entries, against: input(text))
        }
    }

    @Test("同じ金額を二度使った結果は、その件の区間に金額が無いので throw する")
    func resolveAllRejectsDuplicateAmount() {
        let entries = [
            extracted(item: "スーパー", amount: "2480"),
            extracted(item: "スーパー", amount: "2480"),
        ]
        #expect(throws: ExtractedEntry.ResolveError.ungroundedAmount) {
            try ExtractedEntry.resolveAll(entries, against: input("スーパー2480とドラッグ1200"))
        }
    }

    @Test("区間に日付が無くても、その件に割り当てた日付と割り勘を使う")
    func segmentInheritsDateAndSplit() throws {
        let parsed = input("昨日 焼肉12000と飲み物3000 3人で割り勘")
        let entries = try ExtractedEntry.resolveAll([
            extracted(item: "焼肉", amount: "12000", split: 1),
            extracted(item: "飲み物", amount: "3000", category: "その他", split: 3),
        ], against: parsed)
        #expect(entries.map(\.amount) == [4_000, 1_000])
        #expect(entries.map(\.daysAgo) == [1, 1])
    }
}
