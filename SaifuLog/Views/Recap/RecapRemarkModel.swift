import Foundation
import Observation
import SaifuLogCore

/// ふりかえり（先週のふりかえりのカード・月のまとめ）に添える、端末内 AI の一言の状態と書かせ方。
///
/// 一言を添えるのは、プレミアムと体験中で、AI が使える端末のときだけ。無料と AI の使えない端末（プレミアムでも）は、何も
/// 添えない（画面はコードで作る文と数字だけ）。一言は数字の文（`RecapFacts`）と突き合わせ、文に無い数字があれば捨てる
/// （`RecapRemark.checked`）。
///
/// 数字の文が同じなら書き直さない（同じ週や月を開き直すたび・記録が保存されて読み直すたびに AI を呼ばないため）。書いた結果は
/// 数字の文ごとに少しだけ覚えておき、月送りで行き来しても書き直さない。
@MainActor
@Observable
final class RecapRemarkModel {
    /// 一言の状態。
    enum State: Equatable {
        /// 添えない（無料・AI が使えない・照合で捨てた・書けなかった・数字の文が無い）。
        case none
        /// 書いている（画面は進行中の印を出す）。
        case writing
        /// 照合を通った一言。
        case written(String)
    }

    private(set) var state: State = .none

    /// 覚えておく結果の数。月送りで行き来する分くらいで足りる。
    static let cacheLimit = 12

    @ObservationIgnored private let purchases: PurchaseManager?
    @ObservationIgnored private let makeWriter: () -> (any RecapRemarkWriting)?
    @ObservationIgnored private let aiFallbackLog: AIFallbackLog
    /// いま画面に出している数字の文。
    @ObservationIgnored private var facts: String?
    /// 数字の文ごとの、書き終えた結果（照合を通った一言か、捨てた・書けなかったら nil）。
    @ObservationIgnored private var results: [String: String?] = [:]
    /// 覚えた順（古いものから消す）。
    @ObservationIgnored private var resultOrder: [String] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - purchases: プレミアムの状態。nil なら一言を添えない（無料と同じ）。
    ///   - makeWriter: 一言を書くもの。書くたびに選ぶ（AI の使える・使えないは途中から変わるため）。AI が使えなければ nil を返す。
    ///   - aiFallbackLog: 書けなかったときの失敗を残す先（利用者には知らせず、ログと診断画面にだけ出す）。テストで別の記録を渡す。
    init(
        purchases: PurchaseManager?,
        makeWriter: @escaping () -> (any RecapRemarkWriting)? = { RecapRemarkWriterFactory.makeWriter() },
        aiFallbackLog: AIFallbackLog = .shared
    ) {
        self.purchases = purchases
        self.makeWriter = makeWriter
        self.aiFallbackLog = aiFallbackLog
    }

    /// 出している数字の文を替える（読み込み直したとき）。文が変わったら一言を書き直し、同じなら何もしない。書く Task を返す（テストで待つ）。
    @discardableResult
    func update(facts: String?) -> Task<Void, Never>? {
        guard facts != self.facts else { return nil }
        self.facts = facts
        return write()
    }

    /// いま書いている Task（テストで、書き終えるのを待つ）。
    var currentTask: Task<Void, Never>? {
        task
    }

    /// プレミアムの状態や AI の使える・使えないが変わったかもしれないときに、同じ数字の文で決め直す（体験を始めた・買った・返金された）。
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        write()
    }

    private func write() -> Task<Void, Never>? {
        task?.cancel()
        guard let facts, let purchases else {
            state = .none
            task = nil
            return nil
        }
        let task = Task { [weak self] in
            // 購入の事実を読み終える前は、プレミアムでも無料に見えるので、読み終えてから決める（家計への質問と同じ）。
            if !purchases.hasLoadedPurchases {
                await purchases.refreshPurchases()
            }
            guard let self, !Task.isCancelled, self.facts == facts else { return }
            guard purchases.status.unlocksPremium, let writer = makeWriter() else {
                state = .none
                return
            }
            if let cached = results[facts] {
                state = cached.map(State.written) ?? .none
                return
            }
            state = .writing
            let sentence: String
            do {
                sentence = try await writer.remark(from: facts)
            } catch {
                // 書けなかった（安全のための拒否・文脈の長さの超過など）。添えずにおき、結果は覚えない（決め直したときにまた試す）。
                // 取り消した（数字の文が替わった・決め直した）後の失敗は、取り消しによるものかもしれないので残さない。
                guard !Task.isCancelled else { return }
                aiFallbackLog.record(.failed(error), in: .recap)
                if self.facts == facts { state = .none }
                return
            }
            // 待っている間に数字の文が替わったり、取り消されたりしたら、古い一言は出さない（次の Task が決める）。
            guard !Task.isCancelled, self.facts == facts else { return }
            let checked = RecapRemark.checked(sentence, facts: facts)
            remember(checked, for: facts)
            state = checked.map(State.written) ?? .none
        }
        self.task = task
        return task
    }

    private func remember(_ result: String?, for facts: String) {
        if results.updateValue(result, forKey: facts) == nil {
            resultOrder.append(facts)
        }
        while resultOrder.count > Self.cacheLimit {
            results.removeValue(forKey: resultOrder.removeFirst())
        }
    }
}
