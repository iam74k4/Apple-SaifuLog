import Foundation

/// 集計に使う記録の最小の形。
///
/// 保存用のモデル（SwiftData）をコアに持ち込まずに集計するための境目。
/// アプリ側のモデルがこれに準拠する。
public protocol LedgerRecord {
    /// 金額（円）。支出も収入も正の数で持つ。
    var amount: Int { get }
    var isIncome: Bool { get }
    /// 支出のカテゴリ。収入の記録のカテゴリは、カテゴリ別の合計に数えない（収入は支出とは別の種別のため）。
    var category: EntryCategory { get }
    /// 使った日時（受け取った日時）。
    var spentAt: Date { get }
}

/// ある期間の支出と収入の合計と件数、支出のカテゴリ別の合計と件数。
///
/// 合計はコードで計算する（AI には計算させない）。ホームの合計、月のまとめ、質問への答え、週のふりかえりが
/// 同じ計算を使い、画面の数字と AI に渡す数字を食い違わせないため、集計はここに集める。
public struct LedgerSummary: Sendable, Hashable {
    /// 集計した期間。終わりの時刻ちょうどの記録は含めない（次の期間の最初の記録になるため）。
    public let interval: DateInterval
    public let expense: Int
    public let income: Int
    /// 支出のカテゴリ別の合計。記録の無いカテゴリは入れない（`expense(in:)` なら 0 が返る）。
    public let expenseByCategory: [EntryCategory: Int]
    /// 期間の支出の記録の件数。
    public let expenseCount: Int
    /// 期間の収入の記録の件数。
    public let incomeCount: Int
    /// 支出のカテゴリ別の記録の件数。記録の無いカテゴリは入れない（`expenseCount(in:)` なら 0 が返る）。
    ///
    /// 件数も合計と同じ区切りで数える。質問の答えに「元になった件数」を添えるとき、合計と件数を別々に数えると、
    /// 境目の記録（月末 24 時ちょうど）を片方だけに数えて食い違うため。
    public let expenseCountByCategory: [EntryCategory: Int]
    /// 期間がかかる暦の日数（1 日あたりの平均を出すときの割る数）。
    ///
    /// 秒数を 1 日の秒数で割らずに暦で数える。夏時間の切り替わる日は 23 時間や 25 時間になり、
    /// 秒で割ると 1 週間が 6.96 日のようになるため。一部だけかかる日も 1 日と数える。
    public let dayCount: Int

    /// `interval` に入る記録だけを合計する。
    public init<Records: Sequence>(records: Records, interval: DateInterval, calendar: Calendar)
    where Records.Element: LedgerRecord {
        var expense = 0
        var income = 0
        var byCategory: [EntryCategory: Int] = [:]
        var expenseCount = 0
        var incomeCount = 0
        var countByCategory: [EntryCategory: Int] = [:]
        // DateInterval.contains は終わりの時刻も含むので使わない。月末 24 時ちょうど（翌月 1 日 0 時）の記録が
        // 両方の月に数えられてしまうため。
        for record in records where record.spentAt >= interval.start && record.spentAt < interval.end {
            if record.isIncome {
                income += record.amount
                incomeCount += 1
            } else {
                expense += record.amount
                byCategory[record.category, default: 0] += record.amount
                expenseCount += 1
                countByCategory[record.category, default: 0] += 1
            }
        }
        self.interval = interval
        self.expense = expense
        self.income = income
        self.expenseByCategory = byCategory
        self.expenseCount = expenseCount
        self.incomeCount = incomeCount
        self.expenseCountByCategory = countByCategory
        self.dayCount = Self.dayCount(of: interval, calendar: calendar)
    }

    /// 収入から支出を引いた額。
    public var balance: Int {
        income - expense
    }

    /// そのカテゴリの支出の合計。記録が無ければ 0。
    public func expense(in category: EntryCategory) -> Int {
        expenseByCategory[category, default: 0]
    }

    /// 期間の記録の件数（支出と収入）。
    public var recordCount: Int {
        expenseCount + incomeCount
    }

    /// そのカテゴリの支出の記録の件数。記録が無ければ 0。
    public func expenseCount(in category: EntryCategory) -> Int {
        expenseCountByCategory[category, default: 0]
    }

    static func dayCount(of interval: DateInterval, calendar: Calendar) -> Int {
        let firstDay = calendar.startOfDay(for: interval.start)
        let lastDayStart = calendar.startOfDay(for: interval.end)
        let wholeDays = calendar.dateComponents([.day], from: firstDay, to: lastDayStart).day ?? 0
        // 終わりが日の途中なら、その日にもかかっている。
        return lastDayStart == interval.end ? wholeDays : wholeDays + 1
    }
}
