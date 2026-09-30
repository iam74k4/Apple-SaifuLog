import Foundation
import Observation
import SaifuLogCore

/// いまのカテゴリの一覧（組み込みの 8 種と作ったカテゴリ）。ホームが 1 つ持ち、画面へは環境（`categoryCatalog`）で渡し、
/// ホームのモデル（作ったカテゴリの名前を読む・聞き返しのボタン）とほかの画面のモデル（予算・まとめ・質問・書き出し）に渡す。
///
/// 保存先に書き込まれたとき・iCloud で取り込んだとき・カテゴリを作ったり直したりしたときに読み直す（`reload()`）。読めなければ
/// 前の一覧のまま（一覧が無くても、組み込みのカテゴリで記録できるため）。
@MainActor
@Observable
final class CategoryCatalogModel {
    private(set) var catalog: CategoryCatalog = .builtIn

    @ObservationIgnored private let store: CustomCategoryStore

    init(store: CustomCategoryStore) {
        self.store = store
        reload()
    }

    /// 保存先から読み直す。変わっていなければ書き換えない（描き直しを起こさないため）。
    func reload() {
        guard let catalog = try? store.catalog(), catalog != self.catalog else { return }
        self.catalog = catalog
    }
}
