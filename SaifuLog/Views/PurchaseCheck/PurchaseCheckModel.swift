import Foundation
import Observation
import SaifuLogCore
import SwiftData

@MainActor
@Observable
final class PurchaseCheckModel: Identifiable {
    #if DEBUG
    var screenshotScrollsToBottom = false
    #endif
    var amountText = ""
    var reserveText = ""
    private(set) var reductions: [String: Int] = [:]
    private(set) var analysis: PurchaseCheck?
    private(set) var loadFailed = false
    var premiumSheet: PremiumSheetModel?
    var budgetSetup: BudgetSetupModel?
    let purchases: PurchaseManager
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private(set) var calendar: Calendar
    /// 読めなかった固定費を0として見せない。テストでも全体の読み込み失敗を再現する。
    @ObservationIgnored var load: (Date, Calendar) throws -> (records: [PurchaseCheck.Record], budget: Int?, rules: [RecurringRule])

    init(context: ModelContext, purchases: PurchaseManager, calendar: Calendar, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.purchases = purchases
        self.calendar = calendar
        self.now = now
        load = { date, calendar in
            guard let month = ReportPeriod.thisMonth.interval(now: date, calendar: calendar),
                  let historyStart = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: date)) else { throw CocoaError(.validationMissingMandatoryProperty) }
            let interval = DateInterval(start: min(month.start, historyStart), end: month.end)
            let records = try context.fetch(Entry.descriptor(spentIn: interval)).map {
                PurchaseCheck.Record(amount: $0.amount, memo: CategoryMemory.item(ofMemo: $0.memo, amount: $0.amount, isIncome: $0.isIncome), category: $0.category, spentAt: $0.spentAt, isIncome: $0.isIncome, isRecurring: $0.source == .recurring)
            }
            let budget = try BudgetStore(context: context).plan().amount(for: .total)
            let rules = try RecurringEntryStore(context: context).rules().compactMap(\.rule)
            return (records, budget, rules)
        }
    }

    func reload(calendar newCalendar: Calendar? = nil) {
        if let newCalendar { self.calendar = newCalendar }
        purchases.clockDidChange()
        do {
            let date = now()
            let values = try load(date, self.calendar)
            guard let month = ReportPeriod.thisMonth.interval(now: date, calendar: calendar),
                  let outlook = SpendingOutlook(budget: values.budget, records: values.records.map {
                      .init(amount: $0.amount, isIncome: $0.isIncome, spentAt: $0.spentAt, isRecurring: $0.isRecurring)
                  }, rules: values.rules, now: date, month: month, calendar: calendar),
                  let analysis = PurchaseCheck(outlook: outlook, records: values.records, now: date, calendar: calendar) else { throw CocoaError(.validationMissingMandatoryProperty) }
            self.analysis = analysis
            reductions = reductions.filter { id, _ in analysis.habits.contains { $0.id == id } }
            loadFailed = false
        } catch {
            analysis = nil
            reductions = [:]
            loadFailed = true
        }
    }

    var amount: Int? { try? EntryAmountInput.validate(amountText).get() }
    var reserve: Int? {
        if reserveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 0 }
        guard let value = EntryAmountInput.amount(from: reserveText), value <= EntryAmountInput.maximumAmount else { return nil }
        return value
    }
    var comparison: PurchaseCheck.Comparison? {
        guard let amount, let reserve else { return nil }
        return analysis?.compare(amount: amount, reserve: reserve, reductions: purchases.status.unlocksPremium ? reductions : [:])
    }
    func reduction(for habit: PurchaseCheck.Habit) -> Int { min(habit.remainingCount, reductions[habit.id, default: 0]) }
    func setReduction(_ count: Int, for habit: PurchaseCheck.Habit) {
        guard purchases.status.unlocksPremium else { return }
        reductions[habit.id] = min(habit.remainingCount, max(0, count))
    }
    func showPremium() { premiumSheet = PremiumSheetModel(purchases: purchases) }
    func showBudget() {
        budgetSetup = BudgetSetupModel(store: BudgetStore(context: context), showsCategoryBudgets: purchases.status.unlocksPremium, catalog: (try? CustomCategoryStore(context: context).catalog()) ?? .builtIn)
    }
}
