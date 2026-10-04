import Foundation
import SaifuLogCore
import SwiftData
import Testing
@testable import SaifuLog

@MainActor
struct PurchaseCheckModelTests {
    func make(premium: Bool = false, now: @escaping () -> Date = { TestSupport.now }) async throws -> (PurchaseCheckModel, ModelContext) {
        let context = try TestSupport.makeContext()
        let purchases = await TestSupport.purchases(premium ? [PremiumPurchase(product: .premium, purchaseDate: TestSupport.now)] : [])
        try BudgetStore(context: context).setAmounts([.total: 50_000])
        for day in 1...28 {
            context.insert(TestSupport.entry(amount: 500, category: .cafe, memo: "カフェ", spentAt: TestSupport.calendar.date(byAdding: .day, value: -day, to: TestSupport.now)!))
        }
        try context.save()
        let model = PurchaseCheckModel(context: context, purchases: purchases, calendar: TestSupport.calendar, now: now)
        model.amountText = "12,000"
        model.reload()
        return (model, context)
    }

    @Test func simulationNeverWritesEntriesOrBudgets() async throws {
        let (model, context) = try await make(premium: true)
        let count = try context.fetchCount(FetchDescriptor<Entry>())
        let habit = try #require(model.analysis?.habits.first)
        model.reserveText = "5,000"
        model.setReduction(1, for: habit)
        #expect(model.comparison?.adjustment == 500)
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == count)
        #expect(try BudgetStore(context: context).plan().total == 50_000)
        #expect(!context.hasChanges)
    }

    @Test func freeComparisonWorksButDoesNotApplyPremiumCuts() async throws {
        let (model, _) = try await make()
        let habit = try #require(model.analysis?.habits.first)
        model.setReduction(2, for: habit)
        #expect(model.comparison != nil)
        #expect(model.comparison?.adjustment == 0)
        #expect(model.reduction(for: habit) == 0)
    }

    @Test func loadFailureClearsPreviouslyValidNumbersAndRetryRecovers() async throws {
        let (model, _) = try await make()
        let load = model.load
        model.load = { _, _ in throw CocoaError(.fileReadUnknown) }
        model.reload()
        #expect(model.loadFailed)
        #expect(model.analysis == nil)
        #expect(model.comparison == nil)
        model.load = load
        model.reload()
        #expect(!model.loadFailed)
        #expect(model.comparison != nil)
    }

    @Test func deletingDataRemovesStaleChoices() async throws {
        let (model, context) = try await make(premium: true)
        model.setReduction(1, for: try #require(model.analysis?.habits.first))
        for entry in try context.fetch(FetchDescriptor<Entry>()) { context.delete(entry) }
        try context.save()
        model.reload()
        #expect(model.analysis?.habits.isEmpty == true)
        #expect(model.reductions.isEmpty)
        #expect(model.comparison?.withPurchase == 38_000)
    }

    @Test func trialExpiryStopsApplyingCutsWithoutDeletingInput() async throws {
        var date = TestSupport.now
        let context = try TestSupport.makeContext()
        let purchases = await TestSupport.purchases([TestSupport.trial(startedDaysAgo: 13)], now: { date })
        let model = PurchaseCheckModel(context: context, purchases: purchases, calendar: TestSupport.calendar, now: { date })
        model.load = { date, _ in
            let history = (1...28).map { day in
                PurchaseCheck.Record(amount: 500, memo: "カフェ", category: .cafe, spentAt: TestSupport.calendar.date(byAdding: .day, value: -day, to: date)!)
            }
            return (history, 50_000, [])
        }
        model.amountText = "12000"
        model.reload()
        model.setReduction(1, for: try #require(model.analysis?.habits.first))
        #expect(model.comparison?.adjustment == 500)
        date = TestSupport.calendar.date(byAdding: .day, value: 2, to: date)!
        model.reload()
        #expect(!purchases.status.unlocksPremium)
        #expect(model.comparison?.adjustment == 0)
        #expect(model.amountText == "12000")
    }

    @Test func invalidInputDoesNotBecomeAnAffordableZeroPurchase() async throws {
        let (model, _) = try await make()
        model.amountText = "0"
        #expect(model.comparison == nil)
        model.amountText = "12000"
        model.reserveText = "1000000000000"
        #expect(model.comparison == nil)
    }

    @Test func crossingMonthRefreshesBudgetAndHistory() async throws {
        var now = TestSupport.now
        let (model, _) = try await make(now: { now })
        #expect(model.analysis?.outlook.spent == 13_500)
        now = TestSupport.date(2026, 10, 1)
        model.reload()
        #expect(model.analysis?.outlook.spent == 0)
        #expect(model.analysis?.outlook.remainingDays == 31)
    }
}
