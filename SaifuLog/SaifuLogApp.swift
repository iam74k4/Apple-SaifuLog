import SwiftData
import SwiftUI

@main
struct SaifuLogApp: App {
    var body: some Scene {
        WindowGroup {
            // 保存先は、最初の画面を作るこの時点で開く（static let は初めて読まれるまで作られない）。
            // App の生成の時点で開くと、iOS が起動を前倒しで済ませておく prewarm の間に開くことがある。
            // 保存先は NSFileProtectionComplete（SaifuLog.entitlements）なので、端末のロック中に開くと
            // 読めずに下の fatalError で止まってしまう。
            HomeView()
                .modelContainer(Self.modelContainer)
        }
    }

    /// 記録の保存先。端末の中だけに保存する。
    ///
    /// iCloud 同期は将来の任意の機能なので、いまは明示的に切っておく（cloudKitDatabase: .none）。
    /// iCloud の entitlements を足した時点で、利用者の同意なしに同期が始まってしまわないようにするため。
    @MainActor
    private static let modelContainer: ModelContainer = {
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
}
