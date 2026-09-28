import Foundation
import Testing
@testable import SaifuLogCore

@Suite("月の集計")
struct MonthlySummaryTests {
    @Test("その月の支出と収入だけを合計する（月の境目を含む）")
    func sumsWithinMonth() {
        let records = [
            TestRecord(amount: 100, spentAt: Fixture.date(2026, 8, 31, hour: 23, minute: 59)),
            TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 1)),
            TestRecord(amount: 3_000, spentAt: Fixture.date(2026, 9, 26, hour: 20)),
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25, hour: 9)),
            TestRecord(amount: 1_200, spentAt: Fixture.date(2026, 9, 30, hour: 23, minute: 59)),
            TestRecord(amount: 500, spentAt: Fixture.date(2026, 10, 1)),
        ]
        let summary = MonthlySummary(records: records, month: Fixture.now, calendar: Fixture.calendar)
        #expect(summary == MonthlySummary(expense: 5_050, income: 250_000))
        #expect(summary.balance == 244_950)
    }

    @Test("記録が無ければ 0")
    func empty() {
        let summary = MonthlySummary(records: [TestRecord](), month: Fixture.now, calendar: Fixture.calendar)
        #expect(summary == MonthlySummary())
    }

    /// 月の合計は LedgerSummary の計算を使う（ホームの帯と月のまとめで数字が食い違わないように）。
    @Test("LedgerSummary の月の分と同じ合計")
    func matchesLedgerSummary() throws {
        let records = [
            TestRecord(amount: 850, category: .food, spentAt: Fixture.date(2026, 9, 1)),
            TestRecord(amount: 400, category: .cafe, spentAt: Fixture.date(2026, 9, 20)),
            TestRecord(amount: 250_000, isIncome: true, spentAt: Fixture.date(2026, 9, 25)),
            TestRecord(amount: 9_999, spentAt: Fixture.date(2026, 10, 1)),
        ]
        let month = try #require(ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: Fixture.calendar))
        let ledger = LedgerSummary(records: records, interval: month, calendar: Fixture.calendar)

        #expect(MonthlySummary(records: records, month: Fixture.now, calendar: Fixture.calendar) == MonthlySummary(ledger))
        #expect(MonthlySummary(ledger) == MonthlySummary(expense: 1_250, income: 250_000))
    }

    /// ホームの「今月」とまとめ・質問の「今月」（ReportPeriod.thisMonth）は、利用者が選んだ暦で同じ期間にする。
    /// イスラム暦（ウンム・アル＝クラー）では、2026-09-28 を含む月は 9/12〜10/12（日本時間）。
    @Test("月の区切りが西暦と違う暦でも、ReportPeriod.thisMonth と同じ期間で合計する")
    func nonGregorianMonthMatchesReportPeriod() throws {
        let islamic = Fixture.calendar(firstWeekday: 1, identifier: .islamicUmmAlQura)
        let records = [
            // 西暦では 9 月だが、イスラム暦では前の月。
            TestRecord(amount: 100, spentAt: Fixture.date(2026, 9, 5)),
            TestRecord(amount: 850, spentAt: Fixture.date(2026, 9, 12)),
            // 西暦では 10 月だが、イスラム暦では同じ月。
            TestRecord(amount: 3_000, spentAt: Fixture.date(2026, 10, 5)),
            TestRecord(amount: 9_999, spentAt: Fixture.date(2026, 10, 12)),
        ]
        let month = try #require(ReportPeriod.thisMonth.interval(now: Fixture.now, calendar: islamic))
        let ledger = LedgerSummary(records: records, interval: month, calendar: islamic)

        #expect(MonthlySummary(records: records, month: Fixture.now, calendar: islamic) == MonthlySummary(ledger))
        #expect(MonthlySummary(ledger) == MonthlySummary(expense: 3_850, income: 0))
    }
}
