import Foundation

/// 集計に使う記録の最小の形。
///
/// 保存用のモデル（SwiftData）をコアに持ち込まずに集計するための境目。
/// アプリ側のモデルがこれに準拠する。
public protocol LedgerRecord {
    /// 金額（円）。支出も収入も正の数で持つ。
    var amount: Int { get }
    var isIncome: Bool { get }
    /// 使った日時（受け取った日時）。
    var spentAt: Date { get }
}

/// ある月の支出と収入の合計。
///
/// 合計はコードで計算する（AI には計算させない）。画面の数字と、あとで AI に渡す数字を
/// 同じ計算から出すため、集計はここに集める。
public struct MonthlySummary: Sendable, Hashable {
    public var expense: Int
    public var income: Int

    public init(expense: Int = 0, income: Int = 0) {
        self.expense = expense
        self.income = income
    }

    /// `month` を含む月の記録だけを合計する。
    public init<Records: Sequence>(records: Records, month: Date, calendar: Calendar)
    where Records.Element: LedgerRecord {
        self.init()
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return }
        for record in records where interval.contains(record.spentAt) && record.spentAt < interval.end {
            if record.isIncome {
                income += record.amount
            } else {
                expense += record.amount
            }
        }
    }

    /// 収入から支出を引いた額。
    public var balance: Int {
        income - expense
    }
}
