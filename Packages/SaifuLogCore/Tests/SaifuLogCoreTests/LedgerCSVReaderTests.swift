import Foundation
import Testing
@testable import SaifuLogCore

@Suite("CSV の読み込み")
struct LedgerCSVReaderTests {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let hobby = CustomCategoryInfo(id: "hobby", name: "推し活", symbolName: "heart", colorIndex: 0)
    static let catalog = CategoryCatalog(customs: [hobby])

    static func read(_ text: String, catalog: CategoryCatalog = .builtIn) throws -> LedgerCSVReader.Result {
        try LedgerCSVReader.read(text: text, timeZone: tokyo, catalog: catalog)
    }

    /// 書き出した記録の値が、読み込んだ行に戻っているか（記録した日時は CSV に無いので比べない）。
    static func expectSame(_ row: LedgerCSVReader.Row, _ record: CSVRecord) {
        #expect(row.spentAt == record.spentAt, "\(record.memo)")
        #expect(row.isIncome == record.isIncome, "\(record.memo)")
        #expect(row.category == (record.isIncome ? .other : record.category), "\(record.memo)")
        #expect(row.memo == record.memo, "\(record.memo)")
        #expect(row.amount == record.amount, "\(record.memo)")
        #expect(row.originalText == record.originalText, "\(record.memo)")
    }

    // MARK: - 書き出しとの往復

    @Test("書き出した CSV（BOM つきのファイル）を読むと、同じ記録に戻る", arguments: [LedgerCSVWriter.Language.japanese, .english])
    func roundTripsWriterOutput(language: LedgerCSVWriter.Language) throws {
        let records = [
            CSVRecord(),
            CSVRecord(amount: 400, category: .cafe, spentAt: Fixture.date(2026, 9, 28, hour: 9, minute: 5), memo: "カフェラテ",
                      originalText: "カフェラテ 400"),
            CSVRecord(amount: 250_000, isIncome: true, category: .other, memo: "給料", originalText: "給料 25万"),
            // 品目にカンマ・改行・ダブルクォート、送った文に数式の頭の文字。
            CSVRecord(amount: 1_280, category: .daily, memo: "洗剤, \"特売\"\nほか", originalText: "=HYPERLINK(\"x\")"),
            CSVRecord(amount: 3_990, category: Self.hobby.category, memo: "グッズ", originalText: "グッズ 3990"),
            // くり返しの記録は送った文が空。
            CSVRecord(amount: 80_000, category: .utilities, memo: "家賃", originalText: ""),
        ]
        let data = LedgerCSVWriter.data(records, language: language, timeZone: Self.tokyo, catalog: Self.catalog)

        let result = try LedgerCSVReader.read(data, timeZone: Self.tokyo, catalog: Self.catalog)

        #expect(result.language == language)
        #expect(result.issues.isEmpty)
        try #require(result.rows.count == records.count)
        for (row, record) in zip(result.rows, records) {
            Self.expectSame(row, record)
        }
        #expect(result.rows.map(\.line) == [2, 3, 4, 5, 6, 7])
    }

    @Test("数式インジェクション対策で付けた ' は外し、それ以外の ' は残す")
    func removesFormulaPrefixOnly() throws {
        let records = [
            CSVRecord(memo: "-割引", originalText: "+1"),
            CSVRecord(memo: "@home", originalText: "'quoted'"),
        ]
        let result = try Self.read(LedgerCSVWriter.text(records, language: .japanese, timeZone: Self.tokyo))

        #expect(result.rows.map(\.memo) == ["-割引", "@home"])
        #expect(result.rows.map(\.originalText) == ["+1", "'quoted'"])
    }

    // MARK: - 保存し直した CSV

    @Test("表計算ソフトで保存し直した形（BOM なし・LF の改行・「/」の日付・1 桁の時・秒・桁区切り）も読む")
    func readsResavedForms() throws {
        let text = "日付,時刻,種類,カテゴリ,品目,金額,送った文\n2026/9/8,9:05,支出,食費,ランチ,\"1,280\",ランチ 1280\n2026-09-08,21:30:00,収入,,給料,250000,\n"

        let result = try Self.read(text)

        #expect(result.issues.isEmpty)
        try #require(result.rows.count == 2)
        #expect(result.rows[0].spentAt == Fixture.date(2026, 9, 8, hour: 9, minute: 5))
        #expect(result.rows[0].amount == 1_280)
        #expect(result.rows[0].category == .food)
        #expect(result.rows[1].spentAt == Fixture.date(2026, 9, 8, hour: 21, minute: 30))
        #expect(result.rows[1].isIncome)
        #expect(result.rows[1].category == .other)
    }

    @Test("UTF-8 で読めなければ Shift_JIS で読む")
    func readsShiftJIS() throws {
        let text = "日付,時刻,種類,カテゴリ,品目,金額,送った文\r\n2026-09-28,12:00,支出,カフェ,カフェラテ,480,カフェラテ 480\r\n"
        let data = try #require(text.data(using: .shiftJIS))

        let result = try LedgerCSVReader.read(data, timeZone: Self.tokyo)

        #expect(result.rows.map(\.memo) == ["カフェラテ"])
        #expect(result.rows.map(\.category) == [.cafe])
    }

    // MARK: - カテゴリ

    @Test("カテゴリは名前で戻す。英語の名前も、作ったカテゴリも読み、知らない名前は「その他」にする")
    func mapsCategoryNames() throws {
        let text = """
            Date,Time,Type,Category,Item,Amount,What you sent\r
            2026-09-28,12:00,Expense,Café,Latte,480,Latte 480\r
            2026-09-28,12:01,Expense,推し活,Goods,3990,Goods 3990\r
            2026-09-28,12:02,Expense,消したカテゴリ,Gift,2000,Gift 2000\r
            2026-09-28,12:03,支出,日用品,洗剤,300,洗剤 300\r

            """

        let result = try Self.read(text, catalog: Self.catalog)

        #expect(result.language == .english)
        #expect(result.rows.map(\.category) == [.cafe, Self.hobby.category, .other, .daily])
    }

    @Test("作ったカテゴリが一覧に無ければ（ほかの端末で作った・消した）、その名前は「その他」にする")
    func unknownCustomCategoryReadsAsOther() throws {
        let text = "日付,時刻,種類,カテゴリ,品目,金額,送った文\r\n2026-09-28,12:00,支出,推し活,グッズ,3990,グッズ 3990\r\n"

        #expect(try Self.read(text).rows.map(\.category) == [.other])
    }

    // MARK: - 読めないファイル・行

    @Test("見出しがこのアプリの書き出しと違うファイルは読まない", arguments: [
        "",
        "\r\n",
        "Date,Amount,Memo\r\n2026-09-28,850,Lunch\r\n",
        "日付,時刻,種類,カテゴリ,品目,金額\r\n2026-09-28,12:00,支出,食費,ランチ,850\r\n",
    ])
    func rejectsUnknownHeader(text: String) {
        #expect(throws: LedgerCSVReader.ReadError.unrecognizedHeader) {
            try Self.read(text)
        }
    }

    @Test("読めない行は飛ばして、何行目がなぜ読めなかったかを返す（ほかの行は読む）")
    func reportsBadRows() throws {
        let text = """
            日付,時刻,種類,カテゴリ,品目,金額,送った文\r
            2026-09-28,12:00,支出,食費,ランチ,850,ランチ 850\r
            2026-02-30,12:00,支出,食費,ランチ,850,\r
            2026-09-28,25:00,支出,食費,ランチ,850,\r
            2026-09-28,12:00,返金,食費,ランチ,850,\r
            2026-09-28,12:00,支出,食費,ランチ,0,\r
            2026-09-28,12:00,支出,食費,ランチ,-850,\r
            2026-09-28,12:00,支出,食費,ランチ,850.5,\r
            2026-09-28,12:00,支出,食費,ランチ\r
            2026-09-28,12:30,支出,カフェ,コーヒー,400,コーヒー 400\r

            """

        let result = try Self.read(text)

        #expect(result.rows.map(\.memo) == ["ランチ", "コーヒー"])
        #expect(result.rows.map(\.line) == [2, 10])
        #expect(result.issues == [
            .init(line: 3, reason: .date),
            .init(line: 4, reason: .date),
            .init(line: 5, reason: .kind),
            .init(line: 6, reason: .amount),
            .init(line: 7, reason: .amount),
            .init(line: 8, reason: .amount),
            .init(line: 9, reason: .columnCount),
        ])
    }

    @Test("行の番号は記録の行で数える（品目の中の改行は数えない）")
    func countsRecordsNotPhysicalLines() throws {
        let text = "日付,時刻,種類,カテゴリ,品目,金額,送った文\r\n2026-09-28,12:00,支出,食費,\"1行目\r\n2行目\",850,\r\n2026-09-28,12:00,返金,食費,x,1,\r\n"

        let result = try Self.read(text)

        #expect(result.rows.map(\.memo) == ["1行目\r\n2行目"])
        #expect(result.issues == [.init(line: 3, reason: .kind)])
    }

    @Test("行が多すぎるファイルは読まない")
    func rejectsTooManyRows() {
        let row = "2026-09-28,12:00,支出,食費,ランチ,850,\r\n"
        let text = "日付,時刻,種類,カテゴリ,品目,金額,送った文\r\n" + String(repeating: row, count: LedgerCSVReader.maximumRows + 1)

        #expect(throws: LedgerCSVReader.ReadError.tooLarge) {
            try Self.read(text)
        }
    }

    @Test("上限ちょうどの行は読む")
    func readsMaximumRows() throws {
        let row = "2026-09-28,12:00,支出,食費,ランチ,850,\r\n"
        let text = "日付,時刻,種類,カテゴリ,品目,金額,送った文\r\n" + String(repeating: row, count: LedgerCSVReader.maximumRows)

        #expect(try Self.read(text).rows.count == LedgerCSVReader.maximumRows)
    }

    @Test("大きすぎるファイルは中身を読まずに断る")
    func rejectsTooLargeData() {
        let data = Data(count: LedgerCSVReader.maximumBytes + 1)

        #expect(throws: LedgerCSVReader.ReadError.tooLarge) {
            try LedgerCSVReader.read(data, timeZone: Self.tokyo)
        }
    }
}

@Suite("CSV の読み込みで入れる記録")
struct LedgerCSVImportTests {
    static func row(
        _ memo: String = "ランチ", amount: Int = 850, minute: Int = 0, isIncome: Bool = false, category: EntryCategory = .food,
        line: Int = 2, originalText: String = ""
    ) -> LedgerCSVReader.Row {
        LedgerCSVReader.Row(
            line: line, spentAt: Fixture.date(2026, 9, 28, hour: 12, minute: minute), isIncome: isIncome, category: category,
            memo: memo, amount: amount, originalText: originalText
        )
    }

    @Test("保存先に同じ記録（分まで同じ日時・金額・種類・カテゴリ・品目）があれば飛ばす。秒と送った文は見ない")
    func skipsExistingRecords() {
        let existing = [
            LedgerCSVImport.Key(
                spentAt: Fixture.date(2026, 9, 28, hour: 12).addingTimeInterval(42), amount: 850, isIncome: false,
                category: .food, memo: "ランチ"
            ),
        ]
        let rows = [
            Self.row(originalText: "ランチ 850"),
            Self.row(minute: 1),
            Self.row(amount: 900),
            Self.row(category: .cafe),
            Self.row("弁当"),
        ]

        let plan = LedgerCSVImport.plan(rows: rows, existing: existing)

        #expect(plan.duplicateCount == 1)
        #expect(plan.rows == Array(rows.dropFirst()))
    }

    @Test("同じ鍵の行は数で比べる（同じ分に同じものを 2 つ記録したことがあるので、ファイルの中の同じ行はまとめない）")
    func comparesByCount() {
        let rows = [Self.row(line: 2), Self.row(line: 3), Self.row(line: 4)]

        #expect(LedgerCSVImport.plan(rows: rows, existing: []).rows.count == 3)
        let once = LedgerCSVImport.plan(rows: rows, existing: [LedgerCSVImport.Key(rows[0])])
        #expect(once.rows.map(\.line) == [3, 4])
        #expect(once.duplicateCount == 1)
        // 同じファイルを 2 回読み込んでも二重にならない。
        let again = LedgerCSVImport.plan(rows: rows, existing: rows.map(LedgerCSVImport.Key.init))
        #expect(again.rows.isEmpty)
        #expect(again.duplicateCount == 3)
    }

    @Test("収入はカテゴリを持たないので、カテゴリが違っても同じ記録とみなす")
    func incomeIgnoresCategory() {
        let existing = [LedgerCSVImport.Key(
            spentAt: Fixture.date(2026, 9, 28, hour: 12), amount: 250_000, isIncome: true, category: .food, memo: "給料"
        )]

        let plan = LedgerCSVImport.plan(rows: [Self.row("給料", amount: 250_000, isIncome: true)], existing: existing)

        #expect(plan.rows.isEmpty)
    }

    @Test("記録した日時は使った日時にし、同じ分の行はファイルの順に 1 ミリ秒ずつずらす")
    func createdAtFollowsSpentAt() {
        let rows = [Self.row(minute: 0), Self.row("弁当", minute: 0), Self.row(minute: 5), Self.row("水", minute: 0)]
        let base = Fixture.date(2026, 9, 28, hour: 12)

        #expect(LedgerCSVImport.createdAt(for: rows) == [
            base,
            base.addingTimeInterval(0.001),
            Fixture.date(2026, 9, 28, hour: 12, minute: 5),
            base.addingTimeInterval(0.002),
        ])
    }
}
