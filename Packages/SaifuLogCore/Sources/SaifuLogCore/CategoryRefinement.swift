import Foundation

/// 品目のカテゴリを選ぶもの（端末内 AI）。手元の手がかりで決まらなかった品目と、作ったカテゴリがあるときの品目にだけ使う
/// （`CategoryRefinement`）。
///
/// コアは AI に依存しない（FoundationModels を入れない）ので、選び方はアプリが渡す。
public protocol ItemCategoryClassifying: Sendable {
    /// `item`（品名・店名・サービス名）のカテゴリ。`choices`（カテゴリの名前。組み込みの表示名と作ったカテゴリの名前、
    /// 最後に「その他」）のどれかを返す（分からなければ「その他」）。
    func categoryName(for item: String, choices: [String]) async throws -> String
}

/// 手元の手がかり（作ったカテゴリの名前・覚えたカテゴリ・過去の記録・読み取ったカテゴリ・店の名前の辞書。`CategoryResolver`）で
/// 決まらなかった記録のカテゴリを、返事で聞き返す前に端末内 AI に聞き直す（docs/design.md §3-2）。
///
/// AI が使える iPhone でも、AI の読み取りが時間切れや失敗でキーワード辞書に戻ると、辞書に無い品目（英語の品名・店名など）は
/// 「その他」になり、返事でカテゴリを聞き返していた。品目だけを AI に渡してカテゴリを選ばせ、その他でないカテゴリを選べたら、
/// そのカテゴリで記録する。選べなければ（その他・失敗・時間切れ）、これまでどおり返事で聞き返す。
///
/// - 聞き直すのは、返事で聞き返す記録（`CategoryResolver.Resolution.asksCategory`）。品目の無い記録（金額だけ）は、聞いても
///   決まらないので聞かない。
/// - 作ったカテゴリがあるときは、読み取ったカテゴリ・店の名前の辞書で決まった記録と、辞書の「その他」の語で「その他」にした記録も
///   聞き直し、作ったカテゴリを選んだときだけ当てる（読み取りの選択肢は組み込みの 8 種なので、名前を書かなくても作ったカテゴリに
///   振り分けるため。組み込みのカテゴリの答えは、読み取ったカテゴリより強い手がかりではないので使わない）。名前で決めた・覚えた・
///   過去の記録で決めた記録は聞き直さない（利用者の選んだものを AI で変えないため）。
/// - AI の選択肢は、組み込みの表示名と作ったカテゴリの名前（`CategoryCatalog.all` の順）。
/// - AI の答えは覚えない（覚えるのは利用者が選んだカテゴリだけ。AI の読み違いを、黙って次からの記録に広げないため）。
public enum CategoryRefinement {
    /// 聞き直す 1 件（記録の位置と、AI に渡す品目）。
    public struct Request: Equatable, Sendable {
        public let index: Int
        public let item: String
        /// 組み込みのカテゴリの答えも使うか（「その他」のままの記録）。false なら作ったカテゴリの答えだけを使う。
        public let acceptsBuiltIn: Bool

        public init(index: Int, item: String, acceptsBuiltIn: Bool = true) {
            self.index = index
            self.item = item
            self.acceptsBuiltIn = acceptsBuiltIn
        }
    }

    /// AI に渡す選択肢（`CategoryCatalog.all` の順の名前。「その他」が最後）。
    public static func choices(in catalog: CategoryCatalog) -> [String] {
        catalog.all.map(catalog.name(of:))
    }

    /// 聞き直す記録（記録の順）。AI に渡すのは品目だけ（割り勘や 1 人分の説明・金額・日付は渡さない。カテゴリには要らず、
    /// 数字を渡すと端末内のモデルが写して返すことがあるため）。
    public static func requests(for resolutions: [CategoryResolver.Resolution], catalog: CategoryCatalog = .builtIn) -> [Request] {
        let hasCustoms = !catalog.customs.isEmpty
        return resolutions.indices.compactMap { index -> Request? in
            let resolution = resolutions[index]
            let item = resolution.item
            guard !item.isEmpty else { return nil }
            if resolution.asksCategory { return Request(index: index, item: item) }
            switch resolution.source {
            case .parsed, .store, .unresolved:
                return hasCustoms ? Request(index: index, item: item, acceptsBuiltIn: false) : nil
            case .income, .named, .learned, .history:
                return nil
            }
        }
    }

    /// AI の答えの名前を、一覧のカテゴリに戻す（表記ゆれをそろえて比べる）。一覧に無い名前は nil。
    static func category(named name: String, in catalog: CategoryCatalog) -> EntryCategory? {
        let folded = CategoryCatalog.fold(name)
        guard !folded.isEmpty else { return nil }
        return catalog.all.first { CategoryCatalog.fold(catalog.name(of: $0)) == folded }
    }

    /// AI の答え（記録の位置ごとの名前）を当てる。一覧のカテゴリの名前で、その他でない答えだけを使う。組み込みのカテゴリを使わない
    /// 聞き直し（`Request.acceptsBuiltIn` が false）には、作ったカテゴリの答えだけを使う。
    public static func applying(
        _ answers: [Int: String], to resolutions: [CategoryResolver.Resolution], requests: [Request],
        catalog: CategoryCatalog = .builtIn
    ) -> [ParsedEntry] {
        var result = resolutions.map(\.entry)
        for request in requests {
            guard result.indices.contains(request.index), let name = answers[request.index],
                  let category = category(named: name, in: catalog), category != .other,
                  request.acceptsBuiltIn || category.isCustom
            else { continue }
            result[request.index].category = category
        }
        return result
    }

    /// 聞き直して当てる。品目ごとに順に聞き、全体で `timeout` まで待つ（間に合った答えだけを使い、残りは手元の手がかりで決めた
    /// カテゴリのまま。「その他」のものは返事で聞き返す）。聞き直す記録が無ければ、AI を呼ばずにそのまま返す。
    ///
    /// 「その他」のままの記録を先に聞く（返事で聞き返す手間を減らすほうが、作ったカテゴリに振り分けるより大事なため。時間切れで
    /// 後ろが聞けなくても、決まらない記録を先に片づける）。
    ///
    /// AI の失敗と時間切れは `onFallback` に渡す（利用者には知らせない。返事で聞き返すだけ）。呼び出した Task が取り消されたら、
    /// `CancellationError` を投げる（読み取りの取り消しと同じく、呼び出し側は記録しない）。
    public static func refine(
        _ resolutions: [CategoryResolver.Resolution],
        catalog: CategoryCatalog = .builtIn,
        classifier: any ItemCategoryClassifying,
        timeout: Duration,
        onFallback: (@Sendable (AIFallbackReason) -> Void)? = nil
    ) async throws -> [ParsedEntry] {
        let requests = requests(for: resolutions, catalog: catalog)
        guard !requests.isEmpty else { return resolutions.map(\.entry) }
        let ordered = requests.filter(\.acceptsBuiltIn) + requests.filter { !$0.acceptsBuiltIn }
        let choices = Self.choices(in: catalog)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var answers: [Int: String] = [:]
        for request in ordered {
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else {
                onFallback?(.timedOut(timeout))
                break
            }
            let item = request.item
            do {
                answers[request.index] = try await withDeadline(remaining) {
                    try await classifier.categoryName(for: item, choices: choices)
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
        return applying(answers, to: resolutions, requests: requests, catalog: catalog)
    }
}
