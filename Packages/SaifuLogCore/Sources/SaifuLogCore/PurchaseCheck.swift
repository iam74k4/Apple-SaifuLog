import Foundation

/// 記録を変更せず、買い物と日々の支出の組み合わせを比べる。銀行残高や購入の可否は判断しない。
public struct PurchaseCheck: Sendable {
    public struct Record: Sendable {
        public let amount: Int
        public let memo: String
        public let category: EntryCategory
        public let spentAt: Date
        public let isIncome: Bool
        public let isRecurring: Bool

        public init(amount: Int, memo: String, category: EntryCategory, spentAt: Date, isIncome: Bool = false, isRecurring: Bool = false) {
            self.amount = amount
            self.memo = memo
            self.category = category
            self.spentAt = spentAt
            self.isIncome = isIncome
            self.isRecurring = isRecurring
        }
    }

    public struct Habit: Sendable, Identifiable {
        public let id: String
        public let name: String
        public let category: EntryCategory
        public let count: Int
        public let typicalAmount: Int
        /// 記録のある期間（最長28日）の頻度を残りの日数に当てはめた上限。実際の予定ではない。
        public let remainingCount: Int
    }

    public let outlook: SpendingOutlook
    public let habits: [Habit]
    public let historyDays: Int
    public let observationDays: Int
    public let futureDays: Int
    public let projectedVariable: Int?

    public init?(outlook: SpendingOutlook, records: [Record], now: Date, calendar: Calendar) {
        guard let start = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now)) else { return nil }
        let today = calendar.startOfDay(for: now)
        let history = records.filter { !$0.isIncome && !$0.isRecurring && $0.amount > 0 && $0.amount <= EntryAmountInput.maximumAmount && start <= $0.spentAt && $0.spentAt < today }
        self.outlook = outlook
        let futureDays = max(0, outlook.remainingDays - 1)
        self.futureDays = futureDays
        historyDays = Set(history.map { calendar.startOfDay(for: $0.spentAt) }).count
        // 利用開始前の空白は支出ゼロに数えない。最初の支出の日から昨日までを分母にする。
        let span = history.map(\.spentAt).min().map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: today).day ?? 0 } ?? 0
        let observationDays = min(28, span)
        self.observationDays = observationDays
        let hasHistory = historyDays >= 7 && span >= 14
        var total = 0
        for record in history {
            let addition = total.addingReportingOverflow(record.amount)
            guard !addition.overflow, addition.partialValue <= Int.max / 32 else { return nil }
            total = addition.partialValue
        }
        projectedVariable = hasHistory ? total * futureDays / observationDays : nil
        let groups = Dictionary(grouping: history) { record in
            // カテゴリをまたいだ同名の買い物を、一つの節約案にまとめない。
            record.category.rawValue + "/" + (CategoryMemory.key(for: record.memo) ?? "")
        }
        habits = hasHistory ? groups.compactMap { key, rows -> Habit? in
            guard rows.count >= 3,
                  let latest = rows.max(by: { $0.spentAt < $1.spentAt }),
                  !latest.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  latest.category == .cafe || latest.category == .entertainment else { return nil }
            let amounts = rows.map(\.amount).sorted()
            // 外れ値を含む平均で節約額を大きく見せない。偶数件では小さい側の中央値を使う。
            let typical = amounts[(amounts.count - 1) / 2]
            let remaining = rows.count * futureDays / observationDays
            guard remaining > 0 else { return nil }
            return Habit(id: key, name: latest.memo, category: latest.category, count: rows.count, typicalAmount: typical, remainingCount: remaining)
        }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.id < $1.id
        }.prefix(5).map { $0 } : []
    }

    public struct Comparison: Sendable, Equatable {
        /// 買い物と「残しておく額」を引いた予算の残り。将来の節約見込みを足さない。
        public let withoutPurchase: Int
        public let withPurchase: Int
        public let dailyWithoutPurchase: Int
        public let dailyWithPurchase: Int
        /// 過去のペースが続いた場合の月末の残り。今日の追加支出は含まない。
        public let projectedWithoutPurchase: Int?
        public let projectedWithPurchase: Int?
        public let adjustment: Int
        public let projectedWithAdjustment: Int?
    }

    public func compare(amount: Int, reserve: Int, reductions: [String: Int] = [:]) -> Comparison? {
        guard (1...EntryAmountInput.maximumAmount).contains(amount),
              (0...EntryAmountInput.maximumAmount).contains(reserve), let left = outlook.freeToSpend else { return nil }
        let without = left - reserve
        let with = without - amount
        var saving = 0
        for habit in habits {
            let count = min(habit.remainingCount, max(0, reductions[habit.id, default: 0]))
            saving += count * habit.typicalAmount
        }
        // まだ使っていない予算に「節約」を加算すると二重計上になる。将来の支出見込みだけを減らす。
        saving = min(saving, projectedVariable ?? 0)
        return Comparison(
            withoutPurchase: without, withPurchase: with,
            dailyWithoutPurchase: max(0, without) / outlook.remainingDays,
            dailyWithPurchase: max(0, with) / outlook.remainingDays,
            projectedWithoutPurchase: projectedVariable.map { without - $0 },
            projectedWithPurchase: projectedVariable.map { with - $0 },
            adjustment: saving,
            projectedWithAdjustment: projectedVariable.map { with - $0 + saving }
        )
    }
}
