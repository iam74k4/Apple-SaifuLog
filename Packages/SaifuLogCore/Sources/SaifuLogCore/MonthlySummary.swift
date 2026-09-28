import Foundation

/// ある月の支出と収入の合計（ホームの上の帯に出す）。
///
/// 集計そのものは `LedgerSummary` が受け持つ。これは月の分の合計の 2 つだけを取り出す薄い包み。
/// 帯は支出と収入しか出さないので、カテゴリ別の合計や期間まで持たせず、値の比較（数字が変わったときの
/// アニメーション）も 2 つの合計だけで済むようにしている。
public struct MonthlySummary: Sendable, Hashable {
    public var expense: Int
    public var income: Int

    public init(expense: Int = 0, income: Int = 0) {
        self.expense = expense
        self.income = income
    }

    public init(_ summary: LedgerSummary) {
        self.init(expense: summary.expense, income: summary.income)
    }

    /// `month` を含む月の記録だけを合計する。
    ///
    /// 月は `ReportPeriod.thisMonth` で区切る（ホームの読み込みの条件 `Entry.monthDescriptor`、まとめ・質問の
    /// 「今月」と同じ区切りにするため）。
    public init<Records: Sequence>(records: Records, month: Date, calendar: Calendar)
    where Records.Element: LedgerRecord {
        guard let interval = ReportPeriod.thisMonth.interval(now: month, calendar: calendar) else {
            self.init()
            return
        }
        self.init(LedgerSummary(records: records, interval: interval, calendar: calendar))
    }

    /// 収入から支出を引いた額。
    public var balance: Int {
        income - expense
    }
}
