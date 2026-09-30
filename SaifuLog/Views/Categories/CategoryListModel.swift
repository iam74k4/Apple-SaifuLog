import Foundation
import Observation
import SaifuLogCore

/// 設定の「カテゴリ」の状態と操作。組み込みのカテゴリと作ったカテゴリを並べ、作る・直す・並べ替える・削除する。
///
/// 一覧はホームと同じ `CategoryCatalogModel` を読み、変えたらそれを読み直す（ホームの聞き返しのボタンや直す画面にもすぐ出るように）。
/// 画面（`CategoryListView`）から切り離し、保存先と読み上げを差し替えて SaifuLogTests で確かめられるようにしている。
@MainActor
@Observable
final class CategoryListModel {
    /// カテゴリを作る・直すシートの状態と操作。出していなければ nil（シートを閉じると画面が nil に戻す）。
    var editor: CategoryEditorModel?
    /// 削除の確認に出しているカテゴリ。出していなければ nil。
    var pendingDeletion: PendingDeletion?
    /// 読み書きの失敗（アラートを出す）。
    var failure: Failure?

    /// いまのカテゴリの一覧（ホームと同じもの）。
    let categories: CategoryCatalogModel

    @ObservationIgnored private let store: CustomCategoryStore
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    init(
        store: CustomCategoryStore,
        categories: CategoryCatalogModel,
        announce: @escaping @MainActor (String) -> Void = { VoiceOver.announce($0) }
    ) {
        self.store = store
        self.categories = categories
        self.announce = announce
    }

    var catalog: CategoryCatalog { categories.catalog }

    /// 作ったカテゴリ（並びの順）。
    var customs: [CustomCategoryInfo] { catalog.customs }

    /// まだ作れるか（`CategoryCatalog.maximumCustomCount` まで）。
    var canCreate: Bool { customs.count < CategoryCatalog.maximumCustomCount }

    /// 保存先から読み直す（画面を開いたとき・iCloud でほかの端末の変更が届いたとき）。
    func reload() {
        categories.reload()
    }

    /// カテゴリを作るシートを出す。
    func presentCreation() {
        guard canCreate else { return }
        editor = CategoryEditorModel(mode: .create, store: store, catalog: catalog, announce: announce) { [weak self] _ in
            self?.categories.reload()
        }
    }

    /// 作ったカテゴリを直すシートを出す（組み込みのカテゴリは直せない）。
    func presentEditing(_ category: EntryCategory) {
        guard catalog.info(for: category) != nil else { return }
        editor = CategoryEditorModel(mode: .edit(category), store: store, catalog: catalog, announce: announce) { [weak self] _ in
            self?.categories.reload()
        }
    }

    /// 削除の確認を出す。確認には、そのカテゴリの記録の件数（「その他」になる件数）を出す。
    func requestDeletion(_ category: EntryCategory) {
        guard let info = catalog.info(for: category) else { return }
        do {
            pendingDeletion = PendingDeletion(category: category, name: info.name, entryCount: try store.entryCount(of: category))
        } catch {
            failure = .load
        }
    }

    /// 確認で「削除」を押した。記録は「その他」にし、予算と覚えたカテゴリからも外す（`CustomCategoryStore.delete`）。
    ///
    /// 何を消すかは、確認に出していた値を受け取る（ボタンを押すと確認を閉じる側が先に `pendingDeletion` を nil にすることがあるため）。
    func confirmDeletion(_ deletion: PendingDeletion) {
        pendingDeletion = nil
        do {
            try store.delete(deletion.category)
        } catch {
            failure = .save
            return
        }
        categories.reload()
        announce(String(localized: "カテゴリ「\(deletion.name)」を削除しました"))
    }

    /// 並べ替える（リストのドラッグ）。
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var order = customs.map(\.category)
        order.move(fromOffsets: source, toOffset: destination)
        reorder(order)
    }

    /// 1 つ前へ動かす（VoiceOver の操作。ドラッグは VoiceOver から使いにくいため）。
    func moveEarlier(_ category: EntryCategory) {
        guard let index = customs.firstIndex(where: { $0.category == category }), index > 0 else { return }
        move(fromOffsets: [index], toOffset: index - 1)
        announceOrder(of: category)
    }

    /// 1 つ後ろへ動かす（VoiceOver の操作）。
    func moveLater(_ category: EntryCategory) {
        guard let index = customs.firstIndex(where: { $0.category == category }), index < customs.count - 1 else { return }
        move(fromOffsets: [index], toOffset: index + 2)
        announceOrder(of: category)
    }

    private func reorder(_ order: [EntryCategory]) {
        guard order != customs.map(\.category) else { return }
        do {
            try store.reorder(order)
        } catch {
            failure = .save
            return
        }
        categories.reload()
    }

    /// 動かした後の位置を読み上げる（「3 番目」）。
    private func announceOrder(of category: EntryCategory) {
        guard let index = customs.firstIndex(where: { $0.category == category }) else { return }
        announce(String(localized: "\(index + 1) 番目にしました"))
    }

    /// 削除の確認の中身。
    struct PendingDeletion: Identifiable, Equatable {
        let category: EntryCategory
        let name: String
        /// このカテゴリの記録の件数（「その他」になる件数）。
        let entryCount: Int

        var id: EntryCategory { category }
    }

    /// 読み書きの失敗。
    enum Failure: Equatable {
        /// 読めなかった。
        case load
        /// 書き込めなかった（変更は巻き戻してある）。
        case save
    }
}
