import SwiftData
import SwiftUI

@main
struct SaifuLogApp: App {
    /// 記録の保存先。ここでは作るだけで、開くのは最初の画面が出るとき（`StoreHost.start()`）。
    /// App の生成の時点で開くと、iOS が起動を前倒しで済ませておく prewarm の間（ロック中のことがある）に
    /// 開くことになり、NSFileProtectionComplete の保存先を読めないため。
    @State private var storeHost = StoreHost()

    var body: some Scene {
        WindowGroup {
            StoreRootView(host: storeHost) { container in
                HomeView(model: HomeModel(context: container.mainContext, pendingWrites: storeHost.pendingWrites))
            }
        }
    }
}
