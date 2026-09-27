import Foundation
import Testing
@testable import SaifuLogCore

@Suite("月の集計")
struct MonthlySummaryTests {
    struct Record: LedgerRecord {
        var amount: Int
        var isIncome = false
        var spentAt: Date
    }

    @Test("その月の支出と収入だけを合計する（月の境目を含む）")
    func sumsWithinMonth() {
        let records = [
            Record(amount: 100, spentAt: Fixture.date(2026, 8, 31, hour: 23, minute: 59)),
            Record(amount: 850, spentAt: Fixture.date(2026, 9, 1)),
            Record(amount: 3_000, spentAt: Fixture.date(2026, 9, 26, hour: 20)),
            Record(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25, hour: 9)),
            Record(amount: 1_200, spentAt: Fixture.date(2026, 9, 30, hour: 23, minute: 59)),
            Record(amount: 500, spentAt: Fixture.date(2026, 10, 1)),
        ]
        let summary = MonthlySummary(records: records, month: Fixture.now, calendar: Fixture.calendar)
        #expect(summary == MonthlySummary(expense: 5_050, income: 250_000))
        #expect(summary.balance == 244_950)
    }

    @Test("記録が無ければ 0")
    func empty() {
        let summary = MonthlySummary(records: [Record](), month: Fixture.now, calendar: Fixture.calendar)
        #expect(summary == MonthlySummary())
    }
}
