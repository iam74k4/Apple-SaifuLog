import Foundation
import Observation
import SaifuLogCore

/// 設定の「覚えたカテゴリ」（修正の記憶の一覧）の状態と操作。覚えた言葉とカテゴリを並べ、カテゴリを変える・忘れる・すべて忘れる。
///
/// 何を覚えているかを利用者が見て、要らない覚えを消せるようにする（黙って覚え続けないため。docs/design.md §3-2）。
/// 画面（`LearnedCategoriesView`）から切り離し、保存先を差し替えて SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class LearnedCategoriesModel {
    /// 覚えた言葉（新しく覚えた順）。
    private(set) var rules: [LearnedCategoryStore.Rule] = []
    /// 読み書きの失敗（アラートを出す）。
    var failure: Failure?
    /// 「すべて忘れる」の確認を出しているか。
    var showsForgetAllConfirmation = false

    @ObservationIgnored private let store: LearnedCategoryStore
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    init(store: LearnedCategoryStore, announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }) {
        self.store = store
        self.announce = announce
        reload()
    }

    /// 保存先から読み直す（画面を開いたとき・iCloud でほかの端末の変更が届いたとき）。
    func reload() {
        do {
            rules = try store.rules()
        } catch {
            rules = []
            failure = .load
        }
    }

    /// 覚えたカテゴリを変える（次から、その言葉の記録を新しいカテゴリにする。前に記録したものは変えない）。
    func change(_ rule: LearnedCategoryStore.Rule, to category: EntryCategory) {
        guard rule.category != category else { return }
        do {
            try store.remember(item: rule.phrase, category: category)
        } catch {
            failure = .save
            return
        }
        reload()
        announce(String(localized: "「\(rule.phrase)」を\(String(localized: category.label))にしました"))
    }

    /// 覚えた言葉を忘れる（次から、その言葉の記録はいつもどおり AI とキーワード辞書で読む）。
    func forget(_ rule: LearnedCategoryStore.Rule) {
        do {
            try store.forget(phrase: rule.phrase)
        } catch {
            failure = .save
            return
        }
        reload()
        announce(String(localized: "「\(rule.phrase)」を忘れました"))
    }

    /// 覚えたものをすべて忘れる（確認のあと）。
    func forgetAll() {
        do {
            try store.forgetAll()
        } catch {
            failure = .save
            return
        }
        reload()
        announce(String(localized: "覚えたカテゴリをすべて忘れました"))
    }

    /// 読み書きの失敗。
    enum Failure: Equatable {
        /// 読めなかった。
        case load
        /// 書き込めなかった（変更は巻き戻してある）。
        case save
    }
}
