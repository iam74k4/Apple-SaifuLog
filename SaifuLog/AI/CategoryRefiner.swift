import Foundation
import SaifuLogCore

/// 辞書でも覚えたカテゴリでも決まらず「その他」になった品目のカテゴリを、返事で聞き返す前に端末内 AI に聞き直す
/// （コアの `CategoryRefinement`。docs/design.md §3-2）。
///
/// AI が使える端末でだけ作る（`forDevice()`）。AI が使えない端末では作らず、これまでどおり返事で聞き返す。AI の失敗と時間切れは
/// 利用者に知らせず、`AIFallbackLog` に残す（返事で聞き返すだけ）。
struct CategoryRefiner: Sendable {
    let classifier: any ItemCategoryClassifying
    /// 全体で待つ上限（品目が複数あっても、合わせてこの時間まで）。
    var timeout: Duration = AITimeouts.categoryRefine
    var onFallback: (@Sendable (AIFallbackReason) -> Void)? = AIFallbackLog.shared.reporter(for: .category)

    /// いまの端末で使える聞き直し。AI が使えなければ nil。記録のたびに呼ぶ（AI の使える・使えないは、設定の変更やモデルの
    /// ダウンロードで途中から変わるため。`EntryParserFactory` と同じ）。
    static func forDevice() -> CategoryRefiner? {
        #if canImport(FoundationModels)
        if FoundationModelsEntryParser.isAvailable {
            return CategoryRefiner(classifier: FoundationModelsCategoryClassifier())
        }
        #endif
        return nil
    }

    /// 聞き直して当てる。聞き直す記録が無ければ、AI を呼ばずにそのまま返す。呼び出した Task が取り消されたら投げる。
    func refine(_ entries: [ParsedEntry], memory: CategoryMemory, catalog: CategoryCatalog) async throws -> [ParsedEntry] {
        try await CategoryRefinement.refine(
            entries, memory: memory, catalog: catalog, classifier: classifier, timeout: timeout, onFallback: onFallback
        )
    }
}
