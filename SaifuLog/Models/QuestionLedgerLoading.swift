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
            records: entries.map { LedgerRecordValue($0, searchText: $0.questionSearchText) },
            budget: BudgetPlan.resolve(budgets),
            budgetDecidedAt: BudgetPlan.decidedAt(.total, in: budgets),
            // 作ったカテゴリの名前でも聞けるように（「今月の衣服いくら?」）。読めなければ組み込みのカテゴリだけで答える。
            catalog: (try? CustomCategoryStore(context: context).catalog()) ?? .builtIn
        )
    }
}

extension Entry {
    /// 品目や店の名前で聞かれたときに探す文（`LedgerRecordValue.searchText`）。品目（メモ）と、レシートの記録は店名の入った元の
    /// 文（「レシート: イオン 合計 ¥…」。品目は品名なので、店名で聞かれても当たらないため）。ひとこと入力の元の文は入れない
    /// （1 回の送信のほかの記録の品目も入っているため）。
    var questionSearchText: String {
        source == .receipt ? "\(memo) \(originalText)" : memo
    }
}
