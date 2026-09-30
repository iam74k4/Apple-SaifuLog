import Foundation

/// CSV に書き出す記録の形。集計の形（`LedgerRecord`）に、品目・送った文・記録した日時を足したもの。
///
/// 保存用のモデル（SwiftData）をコアに持ち込まずに書き出すための境目。アプリ側のモデルがこれに準拠する。
public protocol LedgerCSVRecord: LedgerRecord {
    /// 品目（メモ）。
    var memo: String { get }
    /// ひとこと入力で送った元の文。
    var originalText: String { get }
    /// 記録した日時。使った日時が同じ記録を、送った順に並べるのに使う。
    var createdAt: Date { get }
}

/// 書き出す期間（設定の「記録を書き出す」で選ぶもの）。
///
/// 区切りは `ReportPeriod` に任せる（ホームやまとめと同じ、利用者が選んだ暦の月と年）。書き出しのためだけに
/// 期間を計算し直すと、まとめの「今月」と CSV の「今月」が別の期間になりうるため。
public enum LedgerExportPeriod: String, CaseIterable, Sendable, Identifiable {
    case thisMonth
    case lastMonth
    case thisYear
    /// すべての記録（期間で絞り込まない）。
    case all

    public var id: String { rawValue }

    /// 絞り込む期間。すべてなら nil（絞り込まない）。
    public var reportPeriod: ReportPeriod? {
        switch self {
        case .thisMonth: .thisMonth
        case .lastMonth: .lastMonth
        case .thisYear: .thisYear
        case .all: nil
        }
    }

    /// `now` を基準にした、読み込む範囲。すべてなら nil（全期間を読む）。
    ///
    /// 暦で区切れなかったとき（実際には起きない）は、空の範囲を返す。すべての記録に広げてしまうと、選んだ期間より
    /// 多くの記録を外に渡すことになるため。
    public func interval(now: Date, calendar: Calendar) -> DateInterval? {
        guard let reportPeriod else { return nil }
        return reportPeriod.interval(now: now, calendar: calendar) ?? DateInterval(start: now, duration: 0)
    }
}

/// 記録を CSV にする。Excel・Numbers・Google スプレッドシートでそのまま開ける形にする。
///
/// - 文字コードは UTF-8 で、先頭に BOM を付ける。BOM が無いと、日本語版の Excel が Shift_JIS として読み、
///   日本語が文字化けするため。
/// - 形式は RFC 4180。行の区切りは CRLF（最後の行の後にも付ける）。カンマ・改行・ダブルクォートを含む値は
///   ダブルクォートで囲み、中の `"` は `""` にする。
/// - 数式インジェクション対策（OWASP の CSV Injection の推奨）として、`=` `+` `-` `@` タブ CR で始まる値の先頭に
///   `'` を付ける。品目や送った文は利用者が打った文なので、`=HYPERLINK(...)` のような文が表計算ソフトで数式として
///   動かないようにする。金額の列は符号なしの数字だけなので付けない（付けると数として合計できなくなる）。
/// - 日付と時刻は、渡された時間帯の西暦で `yyyy-MM-dd` と `HH:mm`（24 時間）にする。和暦やイスラム暦の暦を
///   使っていても、表計算ソフトが日付として読める形にするため。
public enum LedgerCSVWriter {
    /// 見出しと値（種類・カテゴリ）の言語。アプリの表示の言語に合わせる。
    public enum Language: Sendable, Hashable {
        case japanese
        case english

        /// アプリが表示に使っている言語（`Bundle.main.preferredLocalizations.first`）から決める。
        ///
        /// 英語で表示しているときだけ英語にする。それ以外は、開発言語の日本語で表示しているので日本語にする
        /// （日本語と英語のどちらも優先言語に無い端末でも、画面は日本語で出る）。
        public init(localization: String?) {
            let language = localization.map { Locale.Language(identifier: $0).languageCode?.identifier }
            self = language == "en" ? .english : .japanese
        }
    }

    /// UTF-8 の BOM。
    public static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// 行の区切り（RFC 4180）。
    static let lineBreak = "\r\n"

    /// 見出しの行の値。
    public static func header(language: Language) -> [String] {
        switch language {
        case .japanese: ["日付", "時刻", "種類", "カテゴリ", "品目", "金額", "送った文"]
        case .english: ["Date", "Time", "Type", "Category", "Item", "Amount", "What you sent"]
        }
    }

    /// 種類の列の値（支出か収入か）。アプリの画面と同じ言葉にする。
    public static func kindName(isIncome: Bool, language: Language) -> String {
        switch language {
        case .japanese: isIncome ? "収入" : "支出"
        case .english: isIncome ? "Income" : "Expense"
        }
    }

    /// カテゴリの列の値。アプリの画面の名前と同じにする（英語はアプリの String Catalog の訳と同じ。アプリのテストで照合する）。
    /// 作ったカテゴリは、利用者が決めた名前のまま（どちらの言語でも）。一覧に無い作ったカテゴリは「その他」。
    public static func categoryName(
        _ category: EntryCategory, language: Language, catalog: CategoryCatalog = .builtIn
    ) -> String {
        if let custom = catalog.info(for: category) { return custom.name }
        switch language {
        case .japanese:
            return category.displayName
        case .english:
            switch category {
            case .food: return "Food"
            case .daily: return "Daily goods"
            case .transport: return "Transport"
            case .cafe: return "Café"
            case .entertainment: return "Entertainment"
            case .utilities: return "Utilities & phone"
            case .medical: return "Medical"
            case .other, .custom: return "Other"
            }
        }
    }

    /// 書き出す記録。`period` の範囲に入る記録だけを、使った日時の古い順（同じなら記録した順）に並べる。
    ///
    /// 範囲の区切りは `LedgerSummary` と同じ（始まりは含み、終わりは含まない）。まとめの数字と CSV の行が
    /// 食い違わないようにするため。
    public static func records<Records: Sequence>(
        _ records: Records, in period: LedgerExportPeriod, now: Date, calendar: Calendar
    ) -> [Records.Element] where Records.Element: LedgerCSVRecord {
        let interval = period.interval(now: now, calendar: calendar)
        return records
            .filter { record in
                guard let interval else { return true }
                return record.spentAt >= interval.start && record.spentAt < interval.end
            }
            .sorted { a, b in a.spentAt != b.spentAt ? a.spentAt < b.spentAt : a.createdAt < b.createdAt }
    }

    /// CSV の本文（BOM なし）。記録は渡された順に書く（並べ替えと絞り込みは `records(_:in:now:calendar:)`）。
    public static func text<Records: Sequence>(
        _ records: Records, language: Language, timeZone: TimeZone, catalog: CategoryCatalog = .builtIn
    ) -> String where Records.Element: LedgerCSVRecord {
        let calendar = gregorian(timeZone: timeZone)
        var text = line(header(language: language))
        for record in records {
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: record.spentAt)
            text += line([
                date(components),
                time(components),
                kindName(isIncome: record.isIncome, language: language),
                // 収入は支出とは別の種別で、カテゴリで分けていない（ひとこと入力は「その他」で保存する）。
                // 「その他」と書くと、支出のその他と見分けが付かず、分けたように見えるので空にする。
                record.isIncome ? "" : categoryName(record.category, language: language, catalog: catalog),
                record.memo,
                // 金額は符号なしの数字だけにする（支出か収入かは種類の列で分かる。アプリは正の整数しか保存しない）。
                // 数字だけなので数式にならず、数として合計できるよう、先頭に ' を付けない。
                String(record.amount.magnitude),
                record.originalText,
            ])
        }
        return text
    }

    /// 書き出すファイルの中身（BOM ＋ CSV の本文）。
    public static func data<Records: Sequence>(
        _ records: Records, language: Language, timeZone: TimeZone, catalog: CategoryCatalog = .builtIn
    ) -> Data where Records.Element: LedgerCSVRecord {
        Data(byteOrderMark) + Data(text(records, language: language, timeZone: timeZone, catalog: catalog).utf8)
    }

    /// 書き出すファイルの名前（`saifulog-20260928.csv`）。日付は書き出した日（渡された時間帯の西暦）。
    public static func fileName(exportedAt date: Date, timeZone: TimeZone) -> String {
        let components = gregorian(timeZone: timeZone).dateComponents([.year, .month, .day], from: date)
        return String(
            format: "saifulog-%04ld%02ld%02ld.csv", components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
    }

    /// 1 つの値を CSV の欄にする。数式として読まれる書き出しには ' を付け、必要ならダブルクォートで囲む。
    public static func field(_ value: String) -> String {
        var value = value
        if let first = value.unicodeScalars.first, formulaTriggers.contains(first) {
            value = "'" + value
        }
        // 改行は CR と LF のどちらか 1 つでも囲む（CRLF は Swift では 1 文字なので、スカラーで見る）。
        guard value.unicodeScalars.contains(where: { quotedScalars.contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// 先頭にあると、表計算ソフトが数式（や DDE のコマンド）として読む文字（OWASP の CSV Injection の一覧）。
    static let formulaTriggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]

    /// 含むとダブルクォートで囲む文字（RFC 4180）。
    static let quotedScalars: Set<Unicode.Scalar> = [",", "\"", "\r", "\n"]

    private static func line(_ values: [String]) -> String {
        values.map(field).joined(separator: ",") + lineBreak
    }

    private static func date(_ components: DateComponents) -> String {
        String(format: "%04ld-%02ld-%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func time(_ components: DateComponents) -> String {
        String(format: "%02ld:%02ld", components.hour ?? 0, components.minute ?? 0)
    }

    /// 日付の欄を書く暦。利用者の暦（和暦など）ではなく西暦にし、時間帯だけを合わせる。
    private static func gregorian(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
