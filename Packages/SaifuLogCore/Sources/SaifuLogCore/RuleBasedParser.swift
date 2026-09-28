import Foundation

/// キーワード辞書による解析。Apple Intelligence が使えない端末や、AI の生成が失敗したときに使う。
///
/// AI が無くても記録できるアプリにするための下支え。自然な文章の理解は AI に任せ、
/// ここでは「ランチ 850」の形を確実に読むことを優先する。
///
/// - 金額: 区間の中の最後の数字（全角数字・桁区切り・「円」「¥」・「25万」「1万2千」に対応）
/// - 日付: 「今日」「昨日」「一昨日」「3日前」「9/26」「9月26日」「2026/9/26」
/// - 割り勘: 「割り勘」の語と「N人」の両方があれば 1 人分に割る（割った内容はメモに残す）
/// - 収入: 「給料」「ボーナス」などの語があれば収入（「給料日」「収入印紙」のような支出の言い回しは除く）
/// - 複数件: 金額の後ろの「と」「、」などで区切られ、それぞれに金額があれば分けて記録する
public struct RuleBasedParser: EntryParsing {
    public var calendar: Calendar
    private let now: @Sendable () -> Date

    /// - Parameter now: 「昨日」「9/26」を解釈する基準の日時。テストで日付を固定するために差し替えられる。
    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.calendar = calendar
        self.now = now
    }

    public func parse(_ text: String) async throws -> [ParsedEntry] {
        entries(from: text)
    }

    /// 同期版。解析は端末内の文字列処理だけで終わるので、待つ必要はない。
    public func entries(from text: String) -> [ParsedEntry] {
        let scan = EntryScan(TextNormalizer.normalize(text), now: now(), calendar: calendar)
        return scan.segments().map { segment in
            let wholeText = scan.text(in: segment.range)
            return ParsedEntry.assemble(
                total: segment.amount.value,
                category: EntryCategory.guess(from: wholeText),
                isIncome: KeywordMatcher.containsAny(Self.incomeKeywords, in: wholeText, excluding: Self.incomeExclusions),
                item: scan.text(in: segment.range, excluding: segment.amount.range),
                daysAgo: scan.daysAgo ?? 0,
                splitCount: scan.splitCount ?? 1
            )
        }
    }

    /// 収入とみなす語。「お小遣い」「仕送り」は払う側でも使うので入れない。
    public static let incomeKeywords = [
        "給料", "給与", "月給", "賞与", "ボーナス", "収入", "入金", "報酬", "売上", "副業", "年金", "配当",
        "利息", "還付",
    ]

    /// 収入の語を含むが、支出の言い回しになる語。ここに当たった部分は収入の判定から外し、
    /// 支出としてカテゴリを推定する（「給料日なので焼肉 5000」は食費の支出）。
    /// 収入の語は部分一致で見るので、長い語で打ち消さないと、よく使う言い回しの支出が
    /// 収入（+¥）になって今月の収入に足されてしまうため（`EntryCategory.other` と同じ考え方）。
    public static let incomeExclusions = [
        "給料日", "ボーナスで", "ボーナス払い", "収入印紙", "国民年金", "年金保険料",
    ]
}
