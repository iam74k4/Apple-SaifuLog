import Foundation
import Testing
@testable import SaifuLogCore

struct PurchaseCheckTests {
    let calendar = Fixture.calendar
    let now = Fixture.date(2026, 10, 15, hour: 12)

    func records(amount: Int = 500, category: EntryCategory = .cafe) -> [PurchaseCheck.Record] {
        (1...28).map { offset in
            .init(amount: amount, memo: "いつものカフェ", category: category,
                  spentAt: calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!)
        }
    }

    func check(records: [PurchaseCheck.Record] = [], budget: Int? = 50_000, now: Date? = nil) throws -> PurchaseCheck {
        let date = now ?? self.now
        let month = try #require(ReportPeriod.thisMonth.interval(now: date, calendar: calendar))
        let outlook = try #require(SpendingOutlook(budget: budget, records: records.map {
            .init(amount: $0.amount, isIncome: $0.isIncome, spentAt: $0.spentAt, isRecurring: $0.isRecurring)
        }, rules: [], now: date, month: month, calendar: calendar))
        return try #require(PurchaseCheck(outlook: outlook, records: records, now: date, calendar: calendar))
    }

    @Test func comparisonReservesMoneyAndShowsBothPaths() throws {
        let check = try check(records: records())
        let result = try #require(check.compare(amount: 12_000, reserve: 10_000))
        #expect(check.outlook.spent == 7_000)
        #expect(result.withoutPurchase == 33_000)
        #expect(result.withPurchase == 21_000)
        #expect(result.dailyWithPurchase == 21_000 / 17)
        #expect(check.projectedVariable == 8_000)
        #expect(result.projectedWithPurchase == 13_000)
    }

    @Test func reductionsNeverIncreaseUnspentBudget() throws {
        let check = try check(records: records())
        let habit = try #require(check.habits.first)
        let before = try #require(check.compare(amount: 12_000, reserve: 0))
        let after = try #require(check.compare(amount: 12_000, reserve: 0, reductions: [habit.id: 4]))
        #expect(after.withPurchase == before.withPurchase)
        #expect(after.dailyWithPurchase == before.dailyWithPurchase)
        #expect(after.adjustment == 2_000)
        #expect(after.projectedWithAdjustment == before.projectedWithPurchase! + 2_000)
    }

    @Test func clampsCountsAndIgnoresUnknownHabits() throws {
        let check = try check(records: records())
        let habit = try #require(check.habits.first)
        #expect(habit.remainingCount == 16)
        #expect(check.compare(amount: 1, reserve: 0, reductions: [habit.id: Int.max])?.adjustment == 8_000)
        #expect(check.compare(amount: 1, reserve: 0, reductions: [habit.id: -2, "missing": 100])?.adjustment == 0)
    }

    @Test func overspendingIsNegativeNotPermissionToBuy() throws {
        let result = try #require(check(budget: 1_000).compare(amount: 2_000, reserve: 500))
        #expect(result.withPurchase == -1_500)
        #expect(result.dailyWithPurchase == 0)
    }

    @Test func missingBudgetAndInvalidAmountsDoNotProduceResults() throws {
        #expect(try check(budget: nil).compare(amount: 1, reserve: 0) == nil)
        let check = try check()
        for amount in [0, -1, Int.max] { #expect(check.compare(amount: amount, reserve: 0) == nil) }
        for reserve in [-1, Int.max] { #expect(check.compare(amount: 1, reserve: reserve) == nil) }
        #expect(check.compare(amount: EntryAmountInput.maximumAmount, reserve: EntryAmountInput.maximumAmount) != nil)
    }

    @Test func sparseHistoryDoesNotPretendToKnowThePace() throws {
        #expect(try check(records: Array(records().prefix(6))).projectedVariable == nil)
        #expect(try check(records: Array(records().prefix(7))).habits.isEmpty == true)
        #expect(try check(records: Array(records().suffix(7))).projectedVariable != nil)
    }

    @Test func newUserPaceDoesNotTreatTimeBeforeFirstRecordAsZeroSpending() throws {
        let history = Array(records(amount: 1000).prefix(14))
        let check = try check(records: history)
        #expect(check.observationDays == 14)
        #expect(check.historyDays == 14)
        #expect(check.projectedVariable == 16_000)
        #expect(check.habits.first?.remainingCount == 16)
    }

    @Test func fullMonthKeepsTwentyEightDayObservationWindow() throws {
        let check = try check(records: records(amount: 1000))
        #expect(check.observationDays == 28)
        #expect(check.projectedVariable == 16_000)
    }

    @Test func incomeFixedCostsAndTodayDoNotBecomeHabits() throws {
        var history = records()
        history.append(.init(amount: 90_000, memo: "家賃", category: .cafe, spentAt: calendar.date(byAdding: .day, value: -1, to: now)!, isRecurring: true))
        history.append(.init(amount: 200_000, memo: "給料", category: .cafe, spentAt: now, isIncome: true))
        history.append(.init(amount: 5_000, memo: "今日", category: .cafe, spentAt: now))
        let check = try check(records: history)
        #expect(check.projectedVariable == 8_000)
        #expect(check.habits.count == 1)
        #expect(check.outlook.spent == 102_000)
    }

    @Test func essentialSpendingIsNotSuggestedForCuts() throws {
        let check = try check(records: records(category: .food))
        #expect(check.projectedVariable != nil)
        #expect(check.habits.isEmpty)
    }

    @Test func medianResistsOutliers() throws {
        var history = records()
        history.append(.init(amount: 100_000, memo: "いつものカフェ", category: .cafe, spentAt: Fixture.date(2026, 10, 1)))
        #expect(try check(records: history).habits.first?.typicalAmount == 500)
    }

    @Test func futureEntriesAreReservedAndNotHistory() throws {
        var history = records()
        history.append(.init(amount: 10_000, memo: "先の買い物", category: .entertainment, spentAt: Fixture.date(2026, 10, 28)))
        let check = try check(records: history)
        #expect(check.projectedVariable == 8_000)
        #expect(check.compare(amount: 1_000, reserve: 0)?.withPurchase == 32_000)
    }

    @Test func fixedCostMovesFromPlanToRecordWithoutChangingAvailableBudget() throws {
        let month = try #require(ReportPeriod.thisMonth.interval(now: now, calendar: calendar))
        var rule = RecurringRule(id: "rent", memo: "家賃", amount: 20_000, isIncome: false, category: .other, dayOfMonth: 27, startMonth: .init(year: 2026, month: 10))
        let before = try #require(SpendingOutlook(budget: 50_000, records: [], rules: [rule], now: now, month: month, calendar: calendar))
        rule.lastRecordedMonth = .init(year: 2026, month: 10)
        let after = try #require(SpendingOutlook(budget: 50_000, records: [.init(amount: 20_000, isIncome: false, spentAt: Fixture.date(2026, 10, 27), isRecurring: true)], rules: [rule], now: now, month: month, calendar: calendar))
        let beforeCheck = try #require(PurchaseCheck(outlook: before, records: [], now: now, calendar: calendar))
        let afterCheck = try #require(PurchaseCheck(outlook: after, records: [], now: now, calendar: calendar))
        #expect(beforeCheck.compare(amount: 10_000, reserve: 5_000)?.withPurchase == 15_000)
        #expect(beforeCheck.compare(amount: 10_000, reserve: 5_000) == afterCheck.compare(amount: 10_000, reserve: 5_000))
    }

    @Test func monthEndHasNoFutureSavingsToInvent() throws {
        let date = Fixture.date(2026, 10, 31)
        let history = (1...28).map { offset in
            PurchaseCheck.Record(amount: 500, memo: "カフェ", category: .cafe, spentAt: calendar.date(byAdding: .day, value: -offset, to: date)!)
        }
        let check = try check(records: history, now: date)
        #expect(check.futureDays == 0)
        #expect(check.projectedVariable == 0)
        #expect(check.habits.isEmpty)
    }
}
