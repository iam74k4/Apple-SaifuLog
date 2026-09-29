import Combine
import CoreData
import Foundation

/// 保存先の中身が、この画面の外で変わったことの知らせ。
///
/// この端末での保存は `ModelContext.didSave` で分かるが、iCloud 同期で届いたほかの端末の変更は、SwiftData が裏で
/// 取り込むので `didSave` にならない。取り込んだときは、SwiftData の下の Core Data が保存先の「外からの変更」
/// （`NSPersistentStoreRemoteChange`）を知らせるので、それを受けて読み直す（`@Query` を使わず、自分で読み込んでいる
/// 画面のモデル: 月のまとめ・先週のふりかえり・設定の予算の行）。同期がオフのときは届かない。
///
/// この知らせは取り込みを受け持つ裏のスレッドから届くので、メインスレッドへ移してから渡す（画面のモデルは
/// メインスレッドのもの）。実際に iCloud から届いたときに読み直すかは、2 台の端末で確かめる（docs/design.md §15）。
enum StoreChanges {
    static var remote: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
            .map { _ in }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
