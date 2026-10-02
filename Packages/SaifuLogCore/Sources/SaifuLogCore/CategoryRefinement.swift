import Foundation

/// 品目のカテゴリを選ぶもの（端末内 AI）。キーワード辞書でも覚えたカテゴリでも決まらなかった品目にだけ使う（`CategoryRefinement`）。
///
/// コアは AI に依存しない（FoundationModels を入れない）ので、選び方はアプリが渡す。
public protocol ItemCategoryClassifying: Sendable {
    /// `item`（品名・店名・サービス名）のカテゴリ。組み込みのカテゴリの表示名のどれかを返す（分からなければ「その他」）。
    func categoryName(for item: String) async throws -> String
}

/// キーワード辞書でも覚えたカテゴリでも決まらず「その他」になった記録のカテゴリを、返事で聞き返す前に端末内 AI に聞き直す
/// （docs/design.md §3-2）。
///
/// AI が使える iPhone でも、AI の読み取りが時間切れや失敗でキーワード辞書に戻ると、辞書に無い品目（英語の品名・店名など）は
/// 「その他」になり、返事でカテゴリを聞き返していた。品目だけを AI に渡してカテゴリを選ばせ、その他でないカテゴリを選べたら、
/// そのカテゴリで記録する。選べなければ（その他・失敗・時間切れ）、これまでどおり返事で聞き返す。
///
/// - 聞き直すのは、返事で聞き返す記録と同じもの（支出で「その他」になり、品目が辞書にも覚えにも作ったカテゴリの名前にも当たらない。
///   `CategoryMemory.asksCategory`）。品目の無い記録（金額だけ）は、聞いても決まらないので聞かない。
/// - AI の答えは覚えない（覚えるのは利用者が選んだカテゴリだけ。AI の読み違いを、黙って次からの記録に広げないため）。
/// - AI の選択肢は組み込みの 8 種だけ（作ったカテゴリには当てない。作ったカテゴリは、文の中の名前と覚えで当てる）。
public enum CategoryRefinement {
    /// 聞き直す 1 件（記録の位置と、AI に渡す品目）。
    public struct Request: Equatable, Sendable {
        public let index: Int
        public let item: String

        public init(index: Int, item: String) {
            self.index = index
            self.item = item
        }
    }

    /// 聞き直す記録（記録の順）。AI に渡すのは品目だけ（割り勘や 1 人分の説明・金額・日付は渡さない。カテゴリには要らず、
    /// 数字を渡すと端末内のモデルが写して返すことがあるため）。
    public static func requests(
        for entries: [ParsedEntry], memory: CategoryMemory, catalog: CategoryCatalog = .builtIn
    ) -> [Request] {
        entries.indices.compactMap { index in
            let entry = entries[index]
            guard memory.asksCategory(
                memo: entry.memo, amount: entry.amount, category: entry.category, isIncome: entry.isIncome, catalog: catalog
            ) else { return nil }
            let item = CategoryMemory.item(ofMemo: entry.memo, amount: entry.amount, isIncome: false)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { return nil }
            return Request(index: index, item: item)
        }
    }

    /// AI の答え（記録の位置ごとの表示名）を当てる。組み込みのカテゴリの表示名で、その他でない答えだけを使う。
    public static func applying(_ answers: [Int: String], to entries: [ParsedEntry]) -> [ParsedEntry] {
        var result = entries
        for (index, name) in answers {
            guard result.indices.contains(index), let category = EntryCategory(displayName: name), category != .other
            else { continue }
            result[index].category = category
        }
        return result
    }

    /// 聞き直して当てる。品目ごとに順に聞き、全体で `timeout` まで待つ（間に合った答えだけを使い、残りは「その他」のまま
    /// 返事で聞き返す）。聞き直す記録が無ければ、AI を呼ばずにそのまま返す。
    ///
    /// AI の失敗と時間切れは `onFallback` に渡す（利用者には知らせない。返事で聞き返すだけ）。呼び出した Task が取り消されたら、
    /// `CancellationError` を投げる（読み取りの取り消しと同じく、呼び出し側は記録しない）。
    public static func refine(
        _ entries: [ParsedEntry],
        memory: CategoryMemory,
        catalog: CategoryCatalog = .builtIn,
        classifier: any ItemCategoryClassifying,
        timeout: Duration,
        onFallback: (@Sendable (AIFallbackReason) -> Void)? = nil
    ) async throws -> [ParsedEntry] {
        let requests = requests(for: entries, memory: memory, catalog: catalog)
        guard !requests.isEmpty else { return entries }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var answers: [Int: String] = [:]
        for request in requests {
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else {
                onFallback?(.timedOut(timeout))
                break
            }
            let item = request.item
            do {
                answers[request.index] = try await withDeadline(remaining) {
                    try await classifier.categoryName(for: item)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch is DeadlineExceeded {
                // 全体の上限を使い切った。残りの品目は聞かない。
                onFallback?(.timedOut(timeout))
                break
            } catch {
                // この品目だけ聞けなかった（安全のための拒否など）。ほかの品目は聞く。
                onFallback?(.failed(error))
            }
        }
        try Task.checkCancellation()
        return applying(answers, to: entries)
    }
}
