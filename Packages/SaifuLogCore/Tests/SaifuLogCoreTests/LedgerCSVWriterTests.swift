import Foundation
import Testing
@testable import SaifuLogCore

/// CSV の書き出しのテストで使う記録。
struct CSVRecord: LedgerCSVRecord {
    var amount: Int = 850
    var isIncome = false
    var category: EntryCategory = .food
    var spentAt: Date = Fixture.now
    var memo = "ランチ"
    var originalText = "ランチ 850"
    var createdAt: Date = Fixture.now
}

@Suite("CSV の書き出し")
struct LedgerCSVWriterTests {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// BOM を除いた本文を行に分ける（最後の行の後の CRLF で空の要素ができるので落とす）。
    static func lines(_ text: String) -> [String] {
        var lines = text.components(separatedBy: "\r\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    static func text(_ records: [CSVRecord], language: LedgerCSVWriter.Language = .japanese) -> String {
        LedgerCSVWriter.text(records, language: language, timeZone: tokyo)
    }

    // MARK: - 文字コードと改行

    @Test("先頭に UTF-8 の BOM を付け、本文は UTF-8 で書く（Excel で文字化けしないように）")
    func startsWithByteOrderMark() throws {
        let data = LedgerCSVWriter.data([CSVRecord()], language: .japanese, timeZone: Self.tokyo)

        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let body = try #require(String(data: data.dropFirst(3), encoding: .utf8))
        #expect(body.hasPrefix("日付,"))
        #expect(!body.hasPrefix("\u{FEFF}"))
    }

    @Test("行の区切りは CRLF で、最後の行の後にも付ける")
    func separatesLinesWithCRLF() {
        let text = Self.text([CSVRecord(), CSVRecord(amount: 400, category: .cafe, memo: "カフェ")])

        #expect(text == """
            日付,時刻,種類,カテゴリ,品目,金額,送った文\r
            2026-09-28,12:00,支出,食費,ランチ,850,ランチ 850\r
            2026-09-28,12:00,支出,カフェ,カフェ,400,ランチ 850\r

            """)
        // CR を伴わない LF の改行が無い（どの LF も CR の直後にある）。
        let scalars = Array(text.unicodeScalars)
        for (index, scalar) in scalars.enumerated() where scalar == "\n" {
            #expect(index > 0 && scalars[index - 1] == "\r")
        }
    }

    @Test("記録が無ければ、見出しの行だけを書く")
    func headerOnlyWhenEmpty() {
        #expect(Self.text([]) == "日付,時刻,種類,カテゴリ,品目,金額,送った文\r\n")
        let data = LedgerCSVWriter.data([CSVRecord](), language: .english, timeZone: Self.tokyo)
        #expect(data == Data([0xEF, 0xBB, 0xBF]) + Data("Date,Time,Type,Category,Item,Amount,What you sent\r\n".utf8))
    }

    // MARK: - エスケープ

    @Test("カンマ・ダブルクォート・改行を含む値はダブルクォートで囲み、中の \" は \"\" にする", arguments: [
        ("コーヒー, ケーキ", "\"コーヒー, ケーキ\""),
        ("\"特売\"の卵", "\"\"\"特売\"\"の卵\""),
        ("ランチ\n850", "\"ランチ\n850\""),
        ("ランチ\r\n850", "\"ランチ\r\n850\""),
        ("ランチ\r850", "\"ランチ\r850\""),
        ("ランチ 850", "ランチ 850"),
        ("", ""),
    ])
    func escapes(value: String, expected: String) {
        #expect(LedgerCSVWriter.field(value) == expected)
    }

    @Test("改行を含む送った文は、囲んだまま 1 つの欄に入る（行は増えない）")
    func keepsMultilineTextInOneField() {
        let record = CSVRecord(memo: "ランチ", originalText: "ランチ 850\nカフェ, 400")
        let text = Self.text([record])

        #expect(text.hasSuffix(",ランチ,850,\"ランチ 850\nカフェ, 400\"\r\n"))
        #expect(Self.lines(text).count == 2)
    }

    // MARK: - 数式インジェクション

    @Test("= + - @ タブ CR で始まる値の先頭に ' を付ける（表計算ソフトで数式として動かないように）", arguments: [
        ("=1+1", "'=1+1"),
        ("+81 90", "'+81 90"),
        ("-500 返金", "'-500 返金"),
        ("@SUM(A1:A2)", "'@SUM(A1:A2)"),
        ("\tタブ", "'\tタブ"),
        ("\r改行", "\"'\r改行\""),
        ("\r\n改行", "\"'\r\n改行\""),
        ("=HYPERLINK(\"http://example.com\",\"x\")", "\"'=HYPERLINK(\"\"http://example.com\"\",\"\"x\"\")\""),
    ])
    func guardsFormulas(value: String, expected: String) {
        #expect(LedgerCSVWriter.field(value) == expected)
    }

    @Test("途中にある = や - には付けない", arguments: ["ランチ=850", "A-1 定食", "メール@会社", "'引用"])
    func leavesInnerSymbols(value: String) {
        #expect(LedgerCSVWriter.field(value) == value)
    }

    @Test("品目と送った文の数式の書き出しには ' を付け、金額の列には付けない（数として合計できるように）")
    func guardsTextColumnsOnly() {
        let record = CSVRecord(amount: 850, memo: "=cmd|' /C calc'!A0", originalText: "-1+1 ランチ 850")

        let line = Self.lines(Self.text([record]))[1]

        #expect(line == "2026-09-28,12:00,支出,食費,'=cmd|' /C calc'!A0,850,'-1+1 ランチ 850")
    }

    @Test("金額の列は符号なしの数字だけにする（桁区切りも ¥ も付けない）")
    func writesAmountAsDigitsOnly() {
        let records = [
            CSVRecord(amount: 1_234_567),
            // アプリは正の整数しか保存しないが、万一の負の数でも先頭を - にしない（数式の書き出しにならないように）。
            CSVRecord(amount: -500, isIncome: true),
        ]

        let lines = Self.lines(Self.text(records))

        #expect(lines[1].split(separator: ",", omittingEmptySubsequences: false)[5] == "1234567")
        #expect(lines[2].split(separator: ",", omittingEmptySubsequences: false)[5] == "500")
    }

    // MARK: - 言語

    @Test("日本語の見出しと値")
    func japanese() {
        let records = [
            CSVRecord(amount: 1_200, category: .utilities, memo: "スマホ", originalText: "スマホ 1200"),
            CSVRecord(amount: 250_000, isIncome: true, category: .other, memo: "給料", originalText: "給料 25万"),
        ]

        let lines = Self.lines(Self.text(records, language: .japanese))

        #expect(lines == [
            "日付,時刻,種類,カテゴリ,品目,金額,送った文",
            "2026-09-28,12:00,支出,光熱・通信,スマホ,1200,スマホ 1200",
            // 収入はカテゴリで分けていないので、カテゴリの欄は空にする。
            "2026-09-28,12:00,収入,,給料,250000,給料 25万",
        ])
    }

    @Test("英語の見出しと値（品目と送った文は訳さない）")
    func english() {
        let records = [
            CSVRecord(amount: 400, category: .cafe, memo: "コーヒー", originalText: "コーヒー 400"),
            CSVRecord(amount: 500, isIncome: true, category: .other, memo: "返金", originalText: "返金 -500"),
        ]

        let lines = Self.lines(Self.text(records, language: .english))

        #expect(lines == [
            "Date,Time,Type,Category,Item,Amount,What you sent",
            "2026-09-28,12:00,Expense,Café,コーヒー,400,コーヒー 400",
            "2026-09-28,12:00,Income,,返金,500,返金 -500",
        ])
    }

    @Test("カテゴリはすべて、言語ごとの名前で書く")
    func categoryNames() {
        #expect(EntryCategory.builtIns.map { LedgerCSVWriter.categoryName($0, language: .japanese) }
            == ["食費", "日用品", "交通", "カフェ", "娯楽", "光熱・通信", "医療", "その他"])
        #expect(EntryCategory.builtIns.map { LedgerCSVWriter.categoryName($0, language: .english) }
            == ["Food", "Daily goods", "Transport", "Café", "Entertainment", "Utilities & phone", "Medical", "Other"])
    }

    @Test("アプリの表示の言語から決める（英語で表示しているときだけ英語）", arguments: [
        ("en", LedgerCSVWriter.Language.english),
        ("en-GB", .english),
        ("en_US", .english),
        ("ja", .japanese),
        ("ja-JP", .japanese),
        ("fr", .japanese),
        (nil, .japanese),
    ] as [(String?, LedgerCSVWriter.Language)])
    func languageFromLocalization(localization: String?, expected: LedgerCSVWriter.Language) {
        #expect(LedgerCSVWriter.Language(localization: localization) == expected)
    }

    // MARK: - 日付と時刻

    @Test("日付と時刻は渡された時間帯で書く（同じ時刻でも、時間帯で日付が変わる）")
    func usesTimeZone() throws {
        // 2026-09-30 15:30（協定世界時）= 10/1 0:30（日本時間）= 9/30 11:30（ニューヨーク、夏時間）。
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-30T15:30:00Z"))
        let record = CSVRecord(spentAt: instant)

        func firstRow(_ zone: String) throws -> String {
            let text = LedgerCSVWriter.text([record], language: .japanese, timeZone: try #require(TimeZone(identifier: zone)))
            return Self.lines(text)[1]
        }

        #expect(try firstRow("Asia/Tokyo").hasPrefix("2026-10-01,00:30,"))
        #expect(try firstRow("UTC").hasPrefix("2026-09-30,15:30,"))
        #expect(try firstRow("America/New_York").hasPrefix("2026-09-30,11:30,"))
    }

    @Test("時刻は 24 時間の HH:mm、日付は 0 で埋めた yyyy-MM-dd")
    func formatsDateAndTime() {
        let record = CSVRecord(spentAt: Fixture.date(2026, 1, 5, hour: 21, minute: 7))

        #expect(Self.lines(Self.text([record]))[1].hasPrefix("2026-01-05,21:07,"))
    }

    @Test("和暦の暦を使っていても、日付とファイル名は西暦で書く（期間は利用者の暦で区切る）")
    func writesGregorianDates() {
        let japanese = Fixture.calendar(firstWeekday: 1, identifier: .japanese)
        let records = LedgerCSVWriter.records([CSVRecord()], in: .thisYear, now: Fixture.now, calendar: japanese)

        // 書くときは暦の時間帯だけを渡すので、令和 8 年ではなく 2026 年と書く。
        let text = LedgerCSVWriter.text(records, language: .japanese, timeZone: japanese.timeZone)

        #expect(Self.lines(text)[1].hasPrefix("2026-09-28,12:00,"))
        #expect(LedgerCSVWriter.fileName(exportedAt: Fixture.now, timeZone: japanese.timeZone) == "saifulog-20260928.csv")
    }

    @Test("ファイル名は書き出した日（渡された時間帯）で saifulog-YYYYMMDD.csv")
    func fileName() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-30T15:30:00Z"))

        #expect(LedgerCSVWriter.fileName(exportedAt: instant, timeZone: Self.tokyo) == "saifulog-20261001.csv")
        #expect(LedgerCSVWriter.fileName(exportedAt: instant, timeZone: TimeZone(identifier: "UTC")!)
            == "saifulog-20260930.csv")
    }

    // MARK: - 期間

    /// 期間の境目の前後の記録（日本時間）。
    static let boundaryRecords = [
        CSVRecord(amount: 1, spentAt: Fixture.date(2025, 12, 31, hour: 23, minute: 59)),
        CSVRecord(amount: 2, spentAt: Fixture.date(2026, 1, 1)),
        CSVRecord(amount: 3, spentAt: Fixture.date(2026, 8, 1)),
        CSVRecord(amount: 4, spentAt: Fixture.date(2026, 8, 31, hour: 23, minute: 59)),
        CSVRecord(amount: 5, spentAt: Fixture.date(2026, 9, 1)),
        CSVRecord(amount: 6, spentAt: Fixture.date(2026, 9, 30, hour: 23, minute: 59)),
        CSVRecord(amount: 7, spentAt: Fixture.date(2026, 10, 1)),
    ]

    @Test("期間の始まりの時刻は含み、終わりの時刻（次の期間の始まり）は含まない", arguments: [
        (LedgerExportPeriod.thisMonth, [5, 6]),
        (.lastMonth, [3, 4]),
        (.thisYear, [2, 3, 4, 5, 6, 7]),
        (.all, [1, 2, 3, 4, 5, 6, 7]),
    ])
    func filtersByPeriod(period: LedgerExportPeriod, amounts: [Int]) {
        let records = LedgerCSVWriter.records(Self.boundaryRecords, in: period, now: Fixture.now, calendar: Fixture.calendar)

        #expect(records.map(\.amount) == amounts)
    }

    @Test("期間は渡された暦の時間帯で区切る")
    func periodUsesCalendarTimeZone() {
        let utc = Fixture.calendar(firstWeekday: 1, timeZone: "UTC")
        let records = LedgerCSVWriter.records(Self.boundaryRecords, in: .thisMonth, now: Fixture.now, calendar: utc)

        // 協定世界時の 9 月は、日本時間の 9/1 9:00 から 10/1 9:00 まで。9/1 0:00（日本時間）は 8 月に入り、
        // 10/1 0:00（日本時間）は 9/30 15:00（協定世界時）なので 9 月に入る。
        #expect(records.map(\.amount) == [6, 7])
    }

    @Test("今月・先月・今年は ReportPeriod と同じ区切り、すべては絞り込まない")
    func periodsMatchReportPeriod() {
        #expect(LedgerExportPeriod.thisMonth.reportPeriod == .thisMonth)
        #expect(LedgerExportPeriod.lastMonth.reportPeriod == .lastMonth)
        #expect(LedgerExportPeriod.thisYear.reportPeriod == .thisYear)
        #expect(LedgerExportPeriod.all.reportPeriod == nil)
        #expect(LedgerExportPeriod.all.interval(now: Fixture.now, calendar: Fixture.calendar) == nil)
        #expect(LedgerExportPeriod.lastMonth.interval(now: Fixture.now, calendar: Fixture.calendar)
            == ReportPeriod.lastMonth.interval(now: Fixture.now, calendar: Fixture.calendar))
    }

    @Test("使った日時の古い順に並べ、同じ日時なら記録した順にする")
    func sortsBySpentAtThenCreatedAt() {
        let records = [
            CSVRecord(amount: 3, spentAt: Fixture.date(2026, 9, 28, hour: 12), createdAt: Fixture.date(2026, 9, 28, hour: 13)),
            CSVRecord(amount: 1, spentAt: Fixture.date(2026, 9, 2)),
            CSVRecord(amount: 2, spentAt: Fixture.date(2026, 9, 28, hour: 12), createdAt: Fixture.date(2026, 9, 28, hour: 12)),
        ]

        let sorted = LedgerCSVWriter.records(records, in: .all, now: Fixture.now, calendar: Fixture.calendar)

        #expect(sorted.map(\.amount) == [1, 2, 3])
    }

    @Test("1 万件でも書ける（行の数と見出し）")
    func writesManyRecords() {
        let records = (0..<10_000).map { index in
            CSVRecord(amount: index + 1, spentAt: Fixture.now.addingTimeInterval(TimeInterval(index)))
        }

        let lines = Self.lines(Self.text(records))

        #expect(lines.count == 10_001)
        #expect(lines.last == "2026-09-28,14:46,支出,食費,ランチ,10000,ランチ 850")
    }
}
