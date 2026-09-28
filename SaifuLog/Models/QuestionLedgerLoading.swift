import Foundation
import SaifuLogCore
import SwiftData

extension QuestionLedger {
    /// 質問に答えるための記録と予算を、保存先から読む（値だけの写しにする）。
    ///
    /// 読む範囲は、答えうる期間をすべて覆う範囲（`QuestionLedger.window`）。AI のツールはどの期間を聞かれるかを先に
    /// 知らず、メインスレッドの外で呼ばれて ModelContext を使えないので、先に写しておく。読むだけで書き込まないので、
    /// `StoreHost.pendingWrites` には数えない。
    @MainActor
    static func load(from context: ModelContext, now: Date, calendar: Calendar) throws -> QuestionLedger {
        guard let window = window(now: now, calendar: calendar) else { return QuestionLedger() }
        let entries = try context.fetch(Entry.descriptor(spentIn: window))
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        return QuestionLedger(
            records: entries.map(LedgerRecordValue.init),
            budget: BudgetPlan.resolve(budgets),
            budgetDecidedAt: BudgetPlan.decidedAt(.total, in: budgets)
        )
    }
}
