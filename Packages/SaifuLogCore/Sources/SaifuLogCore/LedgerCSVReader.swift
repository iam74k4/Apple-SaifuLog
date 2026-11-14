import Foundation

/// このアプリで書き出した CSV（`LedgerCSVWriter`）を読み、記録に戻す行にする（設定の「CSV から読み込む」。機種変更や、
/// iCloud 同期を使わない人の戻し先。docs/design.md §13 の「CSV の読み込み」）。
///
/// 読むのは書き出しと同じ形だけにする（見出しの行が日本語か英語の書き出しと同じでなければ読まない）。ほかのアプリの CSV は
/// 列の意味も金額の符号も決まっておらず、当て推量で読むと、利用者の気づかないまま違う記録が入るため。
///
/// - 文字コードは UTF-8（BOM は有っても無くてもよい）。表計算ソフトで開いて保存し直すと Shift_JIS になることがあるので、
///   UTF-8 として読めなければ Shift_JIS でも読む。
/// - 形式は RFC 4180。行の区切りは CRLF・LF・CR のどれでもよい（保存し直すと変わることがあるため）。ダブルクォートの中の
///   改行・カンマ・`""` はそのまま値に戻す。
/// - 書き出しが数式インジェクション対策で頭に付けた `'`（`LedgerCSVWriter.field`）は外す。外すのは、`'` の次が数式の頭の文字
///   （`=` `+` `-` `@` タブ CR）のときだけ（書き出しが付けるのはそのときだけなので）。元から「'=」で始まる品目は「=」で始まる
///   品目として戻る（書き出した CSV からは見分けられない）。
/// - 日付は `yyyy-MM-dd`、時刻は `HH:mm`（渡された時間帯の西暦）。保存し直すと「2026/9/28」「9:05」「12:00:00」になることが
///   あるので、区切りの「/」と 1 桁の月日・時、秒も読む。
/// - 金額は正の整数（「1,280」の桁区切りも読む）。0 や上限（`EntryAmountInput.maximumAmount`）を超える額は読まない。
/// - カテゴリは名前で戻す（組み込みは日本語と英語の名前、作ったカテゴリは渡された一覧の同じ名前）。どれでもなければ「その他」
///   （記録は落とさない。消したカテゴリの記録も「その他」になるのと同じ扱い）。収入はカテゴリを持たない（「その他」）。
/// - 数字はどれも書かれた値をそのまま使い、計算しない（AI も使わない）。
public enum LedgerCSVReader {
    /// 読む記録の行の上限。多すぎるファイルを読むと、端末のメモリを使い切りうるため（1 日に 5 件で 10 年分を超える）。
    public static let maximumRows = 20_000
    /// 読むファイルの大きさの上限（バイト）。上の行の上限の記録が収まる大きさ（1 行は長い品目でも 300 バイトほど）に余裕を持たせる。
    public static let maximumBytes = 20 * 1024 * 1024

    /// 読んだ記録の 1 行。
    public struct Row: Sendable, Hashable {
        /// ファイルの中で何件目の行か（見出しの行を 1 とした数え方。品目の中の改行は数えない）。
        public let line: Int
        /// 使った日時（収入なら受け取った日時）。CSV は分までなので、秒は 0。
        public let spentAt: Date
        public let isIncome: Bool
        /// カテゴリ。収入はいつも「その他」。
        public let category: EntryCategory
        public let memo: String
        public let amount: Int
        /// 送った文。
        public let originalText: String

        public init(
            line: Int, spentAt: Date, isIncome: Bool, category: EntryCategory, memo: String, amount: Int, originalText: String
        ) {
            self.line = line
            self.spentAt = spentAt
            self.isIncome = isIncome
            self.category = isIncome ? .other : category
            self.memo = memo
            self.amount = amount
            self.originalText = originalText
        }
    }

    /// 読めなかった行と、その理由。
    public struct Issue: Sendable, Hashable {
        public let line: Int
        public let reason: IssueReason
    }

    /// 行を読めなかった理由。
    public enum IssueReason: Sendable, Hashable {
        /// 列の数が見出しと違う。
        case columnCount
        /// 日付か時刻が読めない（無い日付も）。
        case date
        /// 種類が「支出」「収入」（英語は Expense・Income）のどれでもない。
        case kind
        /// 金額が正の整数でないか、上限を超えている。
        case amount
    }

    /// ファイルとして読めなかった理由。
    public enum ReadError: Error, Sendable, Hashable {
        /// 文字として読めない（UTF-8 でも Shift_JIS でもない）。
        case unreadableText
        /// 見出しの行が、このアプリの書き出しと違う（ほかのアプリの CSV か、列を変えたもの）。空のファイルも。
        case unrecognizedHeader
        /// 大きすぎる（`maximumBytes` か `maximumRows` を超える）。
        case tooLarge
    }

    /// 読んだ結果。
    public struct Result: Sendable, Hashable {
        /// 記録に戻せる行（ファイルの順）。
        public let rows: [Row]
        /// 読めなかった行（ファイルの順）。
        public let issues: [Issue]
        /// 見出しの言語。
        public let language: LedgerCSVWriter.Language
    }

    /// ファイルの中身を読む。
    /// - Parameters:
    ///   - timeZone: 日付と時刻を読む時間帯（書き出しと同じく、画面の暦の時間帯）。
    ///   - catalog: 作ったカテゴリの一覧（名前で戻す）。
    public static func read(_ data: Data, timeZone: TimeZone, catalog: CategoryCatalog = .builtIn) throws -> Result {
        guard data.count <= maximumBytes else { throw ReadError.tooLarge }
        return try read(text: decode(data), timeZone: timeZone, catalog: catalog)
    }

    /// 文字にした中身を読む（BOM が残っていれば外す）。
    public static func read(text: String, timeZone: TimeZone, catalog: CategoryCatalog = .builtIn) throws -> Result {
        var text = Substring(text)
        if text.unicodeScalars.first == "\u{FEFF}" { text = Substring(text.unicodeScalars.dropFirst()) }
        let records = try parse(text)
        guard let header = records.first, let language = language(ofHeader: header) else {
            throw ReadError.unrecognizedHeader
        }
        guard records.count - 1 <= maximumRows else { throw ReadError.tooLarge }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let categories = categoryNames(catalog: catalog)
        var rows: [Row] = []
        var issues: [Issue] = []
        for (offset, fields) in records.enumerated().dropFirst() {
            let line = offset + 1
            switch row(fields, line: line, calendar: calendar, categories: categories) {
            case .success(let row): rows.append(row)
            case .failure(let issue): issues.append(Issue(line: line, reason: issue))
            }
        }
        return Result(rows: rows, issues: issues, language: language)
    }

    // MARK: - 文字

    /// UTF-8 で読み、読めなければ Shift_JIS で読む。
    static func decode(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .shiftJIS) { return text }
        throw ReadError.unreadableText
    }

    // MARK: - RFC 4180

    /// 行と欄に分ける。中身の無い行（最後の改行の後など）は落とす。
    ///
    /// 文字（Character）ではなくスカラーで見る。Swift では CRLF が 1 文字になり、CR と LF を別々に扱えないため。
    static func parse(_ text: Substring) throws -> [[String]] {
        var records: [[String]] = []
        var fields: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var fieldWasQuoted = false
        var scalars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?

        func endField() {
            fields.append(String(field))
            field = String.UnicodeScalarView()
            fieldWasQuoted = false
        }
        func endRecord() throws {
            endField()
            // 改行だけの行（空の 1 欄）は記録として数えない。
            if !(fields.count == 1 && fields[0].isEmpty) {
                records.append(fields)
                // 見出しの行を除いて上限を超えたら、それ以上は読まない（大きなファイルでメモリを使い切らないように）。
                if records.count - 1 > maximumRows { throw ReadError.tooLarge }
            }
            fields = []
        }

        while let scalar = pending ?? scalars.next() {
            pending = nil
            if inQuotes {
                if scalar == "\"" {
                    let next = scalars.next()
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = next
                    }
                } else {
                    field.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where field.isEmpty && !fieldWasQuoted:
                inQuotes = true
                fieldWasQuoted = true
            case ",":
                endField()
            case "\r":
                let next = scalars.next()
                if next != "\n" { pending = next }
                try endRecord()
            case "\n":
                try endRecord()
            default:
                field.append(scalar)
            }
        }
        if !field.isEmpty || !fields.isEmpty || fieldWasQuoted {
            try endRecord()
        }
        return records
    }

    // MARK: - 見出し

    /// 見出しの行の言語。このアプリの書き出しの見出しと同じでなければ nil。
    static func language(ofHeader fields: [String]) -> LedgerCSVWriter.Language? {
        let trimmed = fields.map { unescape($0).trimmingCharacters(in: .whitespaces) }
        for language in [LedgerCSVWriter.Language.japanese, .english]
        where trimmed == LedgerCSVWriter.header(language: language) {
            return language
        }
        return nil
    }

    // MARK: - 行

    /// 列の並び（書き出しの `LedgerCSVWriter.text` と同じ）。
    private enum Column: Int {
        case date, time, kind, category, item, amount, originalText
    }

    private static func row(
        _ raw: [String], line: Int, calendar: Calendar, categories: [String: EntryCategory]
    ) -> Swift.Result<Row, IssueReason> {
        guard raw.count == LedgerCSVWriter.header(language: .japanese).count else { return .failure(.columnCount) }
        let fields = raw.map(unescape)
        func value(_ column: Column) -> String { fields[column.rawValue] }
        guard let spentAt = date(value(.date), time: value(.time), calendar: calendar) else { return .failure(.date) }
        guard let isIncome = isIncome(value(.kind)) else { return .failure(.kind) }
        guard let amount = amount(value(.amount)) else { return .failure(.amount) }
        let category = isIncome ? .other : categories[CategoryCatalog.fold(value(.category))] ?? .other
        return .success(Row(
            line: line, spentAt: spentAt, isIncome: isIncome, category: category, memo: value(.item), amount: amount,
            originalText: value(.originalText)
        ))
    }

    /// 書き出しが数式インジェクション対策で付けた `'` を外す。
    static func unescape(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard scalars.first == "'", let second = scalars.dropFirst().first,
              LedgerCSVWriter.formulaTriggers.contains(second) else { return value }
        return String(String.UnicodeScalarView(scalars.dropFirst()))
    }

    /// 日付と時刻（渡された暦の時間帯）。読めないか、無い日付（2 月 30 日など）なら nil。
    static func date(_ date: String, time: String, calendar: Calendar) -> Date? {
        let dateParts = date.trimmingCharacters(in: .whitespaces).split(
            omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "/" }
        )
        let timeParts = time.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard dateParts.count == 3, (2...3).contains(timeParts.count),
              let year = number(dateParts[0], digits: 4...4), let month = number(dateParts[1], digits: 1...2),
              let day = number(dateParts[2], digits: 1...2), let hour = number(timeParts[0], digits: 1...2),
              let minute = number(timeParts[1], digits: 2...2),
              timeParts.count == 2 || number(timeParts[2], digits: 2...2) != nil,
              (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let result = calendar.date(from: components) else { return nil }
        // 無い日付（2 月 30 日）は暦が次の月へ繰り上げるので、読み直して同じ日かを確かめる。
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        guard check.year == year, check.month == month, check.day == day, check.hour == hour, check.minute == minute
        else { return nil }
        return result
    }

    /// 半角の数字だけでできた、桁数が `digits` の数。
    private static func number(_ text: Substring, digits: ClosedRange<Int>) -> Int? {
        guard digits.contains(text.count), text.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(text)
    }

    /// 種類の列（日本語と英語の書き出しのどちらの言葉も読む）。どちらでもなければ nil。
    static func isIncome(_ kind: String) -> Bool? {
        let kind = kind.trimmingCharacters(in: .whitespaces)
        for language in [LedgerCSVWriter.Language.japanese, .english] {
            if kind == LedgerCSVWriter.kindName(isIncome: true, language: language) { return true }
            if kind == LedgerCSVWriter.kindName(isIncome: false, language: language) { return false }
        }
        return nil
    }

    /// 金額の列。正の整数（桁区切りのカンマは読む）で、上限以下のときだけ。
    static func amount(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard !digits.isEmpty, digits.count <= String(EntryAmountInput.maximumAmount).count,
              digits.allSatisfy(\.isASCIIDigit), let amount = Int(digits),
              amount > 0, amount <= EntryAmountInput.maximumAmount else { return nil }
        return amount
    }

    /// カテゴリの名前（そろえた形）から、カテゴリへの表。組み込みの日本語と英語の名前と、作ったカテゴリの名前。
    ///
    /// 作ったカテゴリの名前は組み込みの名前と重ならない（`CategoryCatalog.validateName`）が、重なっていれば組み込みを先にする
    /// （書き出しは組み込みのカテゴリを組み込みの名前で書くので）。
    static func categoryNames(catalog: CategoryCatalog) -> [String: EntryCategory] {
        var names: [String: EntryCategory] = [:]
        for custom in catalog.customs {
            names[CategoryCatalog.fold(custom.name)] = custom.category
        }
        for category in EntryCategory.builtIns {
            for language in [LedgerCSVWriter.Language.japanese, .english] {
                names[CategoryCatalog.fold(LedgerCSVWriter.categoryName(category, language: language))] = category
            }
        }
        return names
    }
}
