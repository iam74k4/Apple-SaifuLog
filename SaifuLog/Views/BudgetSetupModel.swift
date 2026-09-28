import Foundation
import Observation
import SaifuLogCore

/// 「予算を決める」（②）の状態と操作。
///
/// 画面（`BudgetSetupView`）から切り離し、保存先と読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
/// 初回の案内（②）・設定（⑧）・ホームのシートで同じものを使う。
@MainActor
@Observable
final class BudgetSetupModel: Identifiable {
    /// すぐに選べる額。入れ始めの目安で、選んだ後も入力欄で自由に変えられる。
    static let quickAmounts = [100_000, 150_000, 200_000]

    /// 月の全体の予算の入力欄（「150,000」の形）。
    var totalText: String
    /// カテゴリ別の予算の入力欄（プレミアム）。空欄は設定なし。
    var categoryTexts: [EntryCategory: String]
    /// 保存に失敗した（アラートを出す）。
    var showsSaveFailure = false
    /// カテゴリ別の予算の欄を出すか。プレミアムの機能で、プレミアムと体験中だけ出す（開く側が `PremiumStatus` で決める）。
    /// 出さないときは、決めてあったカテゴリ別の額に触れない（体験が終わっても額は残り、買えばまた出る）。
    let showsCategoryBudgets: Bool
    /// 開いた時点で全体の予算が決まっていたか。決まっていれば「予算をなくす」を出す。
    let hadTotalBudget: Bool

    @ObservationIgnored private let initialPlan: BudgetPlan
    @ObservationIgnored private let store: BudgetStore
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// - Parameters:
    ///   - showsCategoryBudgets: カテゴリ別の予算の欄を出すか（プレミアム）。
    ///   - announce: VoiceOver に読み上げさせる。テストで読み上げる文を集める。
    init(
        store: BudgetStore,
        showsCategoryBudgets: Bool = false,
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        // 読めなければ決めていないものとして始める。保存するときは保存先を読み直して対象ごとに 1 行へ書く
        // （BudgetStore.setAmounts）ので、行は重ならない。決めてあった額と同じ額を保存したときは、保存先が行を
        // 書き換えないので、予算を決めた日時（月のまとめが前の月に予算の進みを出す基準）も動かない。
        let plan = (try? store.plan()) ?? BudgetPlan()
        self.store = store
        self.announce = announce
        self.showsCategoryBudgets = showsCategoryBudgets
        self.initialPlan = plan
        self.hadTotalBudget = plan.total != nil
        self.totalText = BudgetAmountInput.text(for: plan.total ?? 0)
        self.categoryTexts = Dictionary(uniqueKeysWithValues: EntryCategory.allCases.map { category in
            (category, BudgetAmountInput.text(for: plan.byCategory[category] ?? 0))
        })
    }

    /// 入力欄の全体の予算（空欄は 0）。
    var totalAmount: Int {
        BudgetAmountInput.amount(from: totalText) ?? 0
    }

    /// 保存できるか。0 円の予算は決められない（予算をなくすのは「予算をなくす」から）。
    var canSave: Bool {
        totalAmount > 0
    }

    /// 入力欄の文字を見せる形（「150,000」）にそろえる。入力欄が変わるたびに呼ぶ。
    func normalizeTotalText() {
        let formatted = BudgetAmountInput.formatted(totalText)
        if formatted != totalText { totalText = formatted }
    }

    /// カテゴリ別の予算の入力欄の文字をそろえる。
    func normalizeCategoryText(_ category: EntryCategory) {
        let text = categoryTexts[category] ?? ""
        let formatted = BudgetAmountInput.formatted(text)
        if formatted != text { categoryTexts[category] = formatted }
    }

    /// すぐに選べる額を選ぶ。
    func selectQuickAmount(_ amount: Int) {
        totalText = BudgetAmountInput.text(for: amount)
    }

    /// 入力欄の額が、その選べる額と同じか（選んだ印を出す）。
    func isSelected(quickAmount amount: Int) -> Bool {
        totalAmount == amount
    }

    /// 入力した予算を保存する。保存できたら true（呼び出し側が画面を閉じる）。
    ///
    /// 変えた対象だけを書き込む。変えていない対象まで書き込むと、その行の書き込んだ日時が新しくなり、
    /// iCloud で別の端末が同じころに決めた額を上書きしてしまうため。
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }
        var changes: [BudgetScope: Int] = [:]
        if totalAmount != initialPlan.total {
            changes[.total] = totalAmount
        }
        if showsCategoryBudgets {
            for category in EntryCategory.allCases {
                let amount = BudgetAmountInput.amount(from: categoryTexts[category] ?? "") ?? 0
                if amount != initialPlan.byCategory[category] ?? 0 {
                    changes[.category(category)] = amount
                }
            }
        }
        guard write(changes) else { return false }
        announce(String(localized: "予算を \(YenFormatter.string(from: totalAmount)) にしました"))
        return true
    }

    /// 「予算をなくしますか？」の確認を出しているか（確認を閉じると画面が false に戻す）。
    var showsRemoveConfirmation = false

    /// 「予算をなくす」を押した。すぐにはなくさず、確認を出す。
    ///
    /// 押しただけで消すと、シートが上がる途中の誤タップや、VoiceOver で読み上げを聞こうとしたダブルタップで、
    /// 気づかないうちに予算が消えるため（決め直せても、いくらにしていたかは残らない）。
    func requestRemoveTotalBudget() {
        showsRemoveConfirmation = true
    }

    /// 確認のあとで、全体の予算をなくす（0 を書く）。なくせたら true。カテゴリ別の予算はそのまま残す。
    @discardableResult
    func removeTotalBudget() -> Bool {
        showsRemoveConfirmation = false
        guard write([.total: 0]) else { return false }
        totalText = ""
        announce(String(localized: "予算をなくしました"))
        return true
    }

    private func write(_ changes: [BudgetScope: Int]) -> Bool {
        do {
            try store.setAmounts(changes)
            return true
        } catch {
            showsSaveFailure = true
            return false
        }
    }
}
