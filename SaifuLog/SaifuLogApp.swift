import SwiftData
import SwiftUI

@main
struct SaifuLogApp: App {
    /// 記録の保存先。端末の中だけに保存する。
    ///
    /// iCloud 同期は将来の任意の機能なので、いまは明示的に切っておく（cloudKitDatabase: .none）。
    /// iCloud の entitlements を足した時点で、利用者の同意なしに同期が始まってしまわないようにするため。
    private let modelContainer: ModelContainer = {
        // 既定の保存先（Application Support/default.store）のフォルダは、初回起動の時点ではまだ無い。
        // 無いまま開くと Core Data が「作れなかった」というエラーを何十行もログに出してから
        // 自分で作り直す（動作は正常）。そのノイズで本物のエラーを見落とさないよう、先に作っておく。
        // 失敗してもここでは止めない。本当に開けなければ下の ModelContainer が止める。
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)

        let schema = Schema([Entry.self])
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 保存先を開けないまま起動すると、記録したつもりのものが消える。黙って続けずに止める。
            fatalError("記録の保存先を開けませんでした: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(modelContainer)
    }
}
